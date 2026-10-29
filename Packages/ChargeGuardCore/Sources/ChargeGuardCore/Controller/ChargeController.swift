import Foundation
import Dispatch

public enum ControllerError: Error, Equatable, CustomStringConvertible {
    case rejected(String)

    public var description: String {
        switch self {
        case .rejected(let why): return why
        }
    }
}

/// The control loop: read a snapshot, evaluate the policy, apply the decision through the backend,
/// publish the new state. Owns the persisted state. Every method that touches state runs on `queue`.
///
/// Used by the root helper (real dependencies) and in-process by the app's `--simulate` mode.
public final class ChargeController {
    public let queue: DispatchQueue
    let deps: ControllerDependencies
    var logger: CoreLogger { deps.logger }

    // State, only touched on `queue`.
    private(set) var persisted = PersistedState()
    private(set) var writer: GuardedSMCWriter
    private(set) var backend: ChargeBackend?
    private var backendError: String?
    private var lastSnapshot: BatterySnapshot?
    private var lastDecision: Decision?
    private var conflicts = ConflictReport.none
    private var lastConflictScan: Date?
    private var sleepImminent = false
    private var lidClosed = false
    private var externalDisplayConnected = false
    private var timer: DispatchSourceTimer?
    private var timerInterval: Double = 0
    private var recentWrites: [KeyWriteRecord] = []
    private var lastWriteFailure: Date?
    private var lastSaveDate: Date?
    private var lowPowerModeActive: Bool?
    private var lastLowPowerDesired: Bool?
    private var lastAdapterConnected: Bool?
    private var sleepDisabledHeld = false
    private var lastSavedData: Data?
    private var started = false
    private var stopped = false

    /// Called on `queue` after every tick and command.
    public var onStatus: ((DaemonStatus) -> Void)?
    /// Called on `queue` with the events of a tick (the app turns some into notifications).
    public var onEvents: (([EventRecord]) -> Void)?

    public init(dependencies: ControllerDependencies,
                queue: DispatchQueue = DispatchQueue(label: "com.amir.chargeguard.controller")) {
        self.deps = dependencies
        self.queue = queue
        self.writer = GuardedSMCWriter(io: dependencies.smc, report: .empty)
    }

    // MARK: - Lifecycle

    /// Loads state, probes keys, selects a backend, handles stale state, starts the timer.
    public func start() {
        queue.async { self.startOnQueue() }
    }

    /// Synchronous start for tests and the simulator. Must not be called on `queue`.
    public func startSync(startTimer: Bool = true) {
        queue.sync { self.startOnQueue(startTimer: startTimer) }
    }

    private func startOnQueue(startTimer: Bool = true) {
        guard !started else { return }
        started = true
        do {
            if let loaded = try deps.store.load() {
                persisted = loaded
                logger.info(LogCategory.persistence, "loaded state (schema \(loaded.schemaVersion), keysDirty \(loaded.keysDirty))")
            } else {
                logger.info(LogCategory.persistence, "no saved state, starting with defaults (charge control off)")
            }
        } catch {
            logger.error(LogCategory.persistence, "could not load state: \(error). Starting with defaults; the old file is kept.")
        }
        persisted.config = persisted.config.normalized()

        writer.now = { [deps] in deps.clock.now }
        writer.onWrite = { [weak self] record in self?.recordWrite(record) }
        probeAndSelectBackend(reason: "startup")

        // Crash recovery: a sleep-disabled hold left behind by a previous run.
        if let snapshot = persisted.sleepDisabledSnapshot {
            do {
                try deps.sleepDisable.setSleepDisabled(snapshot)
                logger.notice(LogCategory.power, "restored SleepDisabled=\(snapshot) left by a previous run")
            } catch {
                logger.error(LogCategory.power, "could not restore SleepDisabled: \(error)")
            }
            persisted.sleepDisabledSnapshot = nil
        }

        // Scan for other charging tools before anything can be written (never write while one runs).
        // The scan also sets `writer.blockedReason`.
        rescanConflicts(force: true)

        // Stale state: keys left modified by a previous run.
        if persisted.keysDirty {
            if !conflicts.active.isEmpty {
                logger.notice(LogCategory.controller, "keys modified by a previous run, but another charging tool is running: not restoring")
            } else if persisted.config.appClosedBehavior == .restoreOnQuit || !persisted.config.controlEnabled {
                restoreKeys(reason: "stale state found on start", bypassBlock: false)
            } else {
                logger.info(LogCategory.controller, "keys modified by a previous run; enforcement continues (keep enforced)")
            }
        }

        if startTimer { scheduleTimer() }
        tickOnQueue()
    }

    /// Restores normal charging (SIGTERM, uninstall), releases assertions and saves.
    public func shutdown(reason: String, completion: @escaping () -> Void) {
        queue.async {
            self.shutdownOnQueue(reason: reason)
            completion()
        }
    }

    public func shutdownSync(reason: String) {
        queue.sync { self.shutdownOnQueue(reason: reason) }
    }

    private func shutdownOnQueue(reason: String) {
        guard !stopped else { return }
        stopped = true
        timer?.cancel()
        timer = nil
        if persisted.keysDirty && conflicts.active.isEmpty {
            restoreKeys(reason: reason, bypassBlock: false)
        }
        deps.assertions.releaseAll()
        releaseSleepDisabled()
        saveIfChanged(force: true)
        logger.notice(LogCategory.controller, "shut down: \(reason)")
    }

    private func scheduleTimer() {
        let interval = persisted.config.pollIntervalSeconds
        guard interval != timerInterval || timer == nil else { return }
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in self?.tickOnQueue() }
        t.resume()
        timer = t
        timerInterval = interval
    }

    // MARK: - Sleep, wake, lid

    /// Called from the system power callback before sleep. `completion` runs after charging has been
    /// set up for sleep; the caller then allows the power change.
    public func systemWillSleep(completion: @escaping () -> Void) {
        queue.async {
            self.sleepImminent = true
            self.logger.info(LogCategory.power, "system will sleep")
            self.tickOnQueue()
            completion()
        }
    }

    /// Sleep was vetoed or cancelled.
    public func systemWillNotSleep() {
        queue.async {
            self.sleepImminent = false
            self.tickOnQueue()
        }
    }

    /// Re-evaluates on wake (also runs schedule catch-up).
    public func systemDidWake() {
        queue.async {
            self.sleepImminent = false
            self.logger.info(LogCategory.power, "system did wake")
            self.rescanConflicts(force: true)
            self.tickOnQueue()
        }
    }

    public func powerSourceChanged() {
        queue.async { self.tickOnQueue() }
    }

    // MARK: - Requests

    /// Handles a client request asynchronously. Energy sampling runs off the control queue because
    /// powermetrics takes about a second.
    public func handle(_ request: HelperRequest, reply: @escaping (HelperResponse) -> Void) {
        if case .energySample = request {
            DispatchQueue.global(qos: .utility).async { [deps] in
                reply(.energy(deps.energy.sample()))
            }
            return
        }
        queue.async { reply(self.handleOnQueue(request)) }
    }

    /// Synchronous variant for tests and the in-process simulator. Must not be called on `queue`.
    public func handleSync(_ request: HelperRequest) -> HelperResponse {
        if case .energySample = request { return .energy(deps.energy.sample()) }
        return queue.sync { handleOnQueue(request) }
    }

    /// Runs one control-loop tick synchronously (tests). Must not be called on `queue`.
    public func tickSync() {
        queue.sync { tickOnQueue() }
    }

    public func statusSync() -> DaemonStatus {
        queue.sync { makeStatus() }
    }

    private func handleOnQueue(_ request: HelperRequest) -> HelperResponse {
        switch request {
        case .hello(let version, let client):
            logger.info(LogCategory.xpc, "hello from \(client), protocol \(version)")
            return .hello(HelloInfo(protocolVersion: HelperProtocol.version, daemonVersion: deps.daemonVersion,
                                    simulated: deps.simulated, compatible: version == HelperProtocol.version))
        case .getStatus:
            return .status(makeStatus())
        case .command(let command):
            do {
                try perform(command, origin: "client")
            } catch {
                logger.error(LogCategory.controller, "command \(command) rejected: \(error)")
                return .error("\(error)")
            }
            saveIfChanged()
            if case .prepareUninstall = command {
                // No tick: the daemon must not re-apply anything before it is removed.
                return .status(makeStatus())
            }
            tickOnQueue()
            return .status(makeStatus())
        case .probeKeys:
            probeAndSelectBackend(reason: "probe requested")
            tickOnQueue()
            return .probe(writer.report)
        case .readKey(let key):
            do {
                let info = try deps.smc.keyInfo(key)
                let bytes = try? deps.smc.read(key)
                return .keyValue(KeyReadResult(key: key, info: info, bytes: bytes, error: nil))
            } catch {
                return .keyValue(KeyReadResult(key: key, info: nil, bytes: nil, error: "\(error)"))
            }
        case .energySample:
            return .energy(deps.energy.sample())
        case .calibrationHistory(let limit):
            return .calibrationHistory(deps.store.calibrationHistory(limit: limit))
        case .recentEvents(let limit):
            return .events(deps.store.recentEvents(limit: limit))
        case .recentWrites(let limit):
            return .writes(deps.store.recentWrites(limit: limit))
        case .exportSettings:
            return .settings(SettingsExport(exportedAt: deps.clock.now, config: persisted.config,
                                            schedule: persisted.schedule))
        }
    }

    // MARK: - Commands

    private func perform(_ command: HelperCommand, origin: String) throws {
        let now = deps.clock.now
        var config = persisted.config
        var control = persisted.control
        var emitted: [PolicyEvent] = []

        switch command {
        case .setChargeLimit(let limit):
            config.chargeLimit = limit.clamped(to: PolicyConfig.limitRange)
            control.autoDischargeSuppressed = false
        case .updateConfig(let newConfig):
            var c = newConfig.normalized()
            c.controlEnabled = config.controlEnabled // only confirmFirstRun / setControlEnabled change this
            if c.chargeLimit != config.chargeLimit { control.autoDischargeSuppressed = false }
            let backendChanged = c.backendPreference != config.backendPreference
            config = c
            if backendChanged {
                persisted.config = config
                probeAndSelectBackend(reason: "backend preference changed to \(c.backendPreference.rawValue)")
            }
        case .startDischarge:
            guard control.calibration == nil else { throw ControllerError.rejected("Calibration is running. Cancel it first.") }
            guard backend?.capabilities.canForceDischarge == true else {
                throw ControllerError.rejected("This Mac has no usable discharge key.")
            }
            guard config.chargeLimit < 100 else { throw ControllerError.rejected("Set a charge limit below 100 % to discharge to.") }
            control.topUp = nil
            control.manualDischarge = true
            control.autoDischargeSuppressed = false
        case .stopDischarge:
            control.manualDischarge = false
            // Automatic discharge would restart at once; hold it off until unplug or a limit change.
            if config.automaticDischarge { control.autoDischargeSuppressed = true }
        case .startTopUp:
            guard control.calibration == nil else { throw ControllerError.rejected("Calibration is running. Cancel it first.") }
            control.manualDischarge = false
            control.topUp = TopUpState(startedAt: now, startPercentage: lastSnapshot?.percentage ?? 0)
        case .cancelTopUp:
            control.topUp = nil
        case .startCalibration(let fast, let calOrigin):
            guard control.calibration == nil else { throw ControllerError.rejected("Calibration is already running.") }
            guard let snapshot = lastSnapshot ?? (try? deps.battery.readSnapshot()) else {
                throw ControllerError.rejected("Battery data unavailable.")
            }
            var c = config
            if fast { c.calibration.fastMode = true }
            control.calibration = CalibrationMachine.start(config: c, snapshot: snapshot, now: now, origin: calOrigin)
            control.topUp = nil
            control.manualDischarge = false
            emitted.append(.calibrationPhaseChanged(phase: .chargeToFull))
        case .cancelCalibration:
            if let cal = control.calibration {
                let record = CalibrationMachine.cancel(cal, snapshot: lastSnapshot, now: now)
                deps.store.appendCalibration(record)
                emitted.append(.calibrationFinished(record: record))
                control.calibration = nil
            }
        case .keepAwake(let request):
            control.keepAwake = KeepAwakeState(request: request, now: now)
        case .cancelKeepAwake:
            control.keepAwake = nil
        case .setSchedule(let rules):
            persisted.schedule = rules
        case .runScheduleRuleNow(let id):
            guard let rule = persisted.schedule.first(where: { $0.id == id }) else {
                throw ControllerError.rejected("No schedule rule with that id.")
            }
            persisted.config = config
            persisted.control = control
            try perform(Self.command(for: rule.action), origin: "schedule")
            config = persisted.config
            control = persisted.control
            emitted.append(.scheduleRan(ruleID: rule.id, summary: rule.summary))
        case .setHeatProtection(let on):
            config.heatProtection.enabled = on
        case .setSailing(let on):
            config.sailing.enabled = on
        case .setLowPowerMode(let mode):
            config.lowPowerMode = mode
            lastLowPowerDesired = nil
        case .setMagSafeLED(let mode):
            config.magSafeLED = mode
        case .selectBackend(let preference):
            config.backendPreference = preference
            persisted.config = config
            probeAndSelectBackend(reason: "backend preference changed to \(preference.rawValue)")
        case .reprobe:
            persisted.config = config
            probeAndSelectBackend(reason: "re-probe requested")
        case .confirmFirstRun:
            config.controlEnabled = true
            logger.notice(LogCategory.controller, "first-run confirmation received: charge control enabled")
        case .setControlEnabled(let on):
            config.controlEnabled = on
        case .restoreNormalCharging:
            // Section 8: never write while another charging tool runs (it would rewrite the keys anyway).
            // `sudo chargectl restore --direct` is the explicit manual override.
            guard conflicts.active.isEmpty else {
                throw ControllerError.rejected(Self.conflictRefusal(conflicts.active))
            }
            // Turn control off first so the next tick does not re-apply the limit.
            config.controlEnabled = false
            control.manualDischarge = false
            control.topUp = nil
            if let cal = control.calibration {
                let record = CalibrationMachine.cancel(cal, snapshot: lastSnapshot, now: now)
                deps.store.appendCalibration(record)
                emitted.append(.calibrationFinished(record: record))
                control.calibration = nil
            }
            persisted.config = config
            persisted.control = control
            restoreKeys(reason: "user requested restore (\(origin))", bypassBlock: true)
            control = persisted.control
        case .appLaunched:
            if control.enforcementSuspended { logger.info(LogCategory.controller, "app launched: enforcement resumes") }
            control.enforcementSuspended = false
        case .appWillQuit:
            if config.appClosedBehavior == .restoreOnQuit {
                control.enforcementSuspended = true
                logger.info(LogCategory.controller, "app quit with restore-on-quit: restoring normal charging")
            }
        case .setExternalDisplayConnected(let connected):
            externalDisplayConnected = connected
        case .importSettings(let export):
            guard export.format == SettingsExport.formatIdentifier else {
                throw ControllerError.rejected("Not a ChargeGuard settings file.")
            }
            config = export.configForImport(keepingControlEnabled: config.controlEnabled)
            persisted.schedule = export.schedule
            control.autoDischargeSuppressed = false
        case .prepareUninstall:
            config.controlEnabled = false
            control.manualDischarge = false
            control.topUp = nil
            control.keepAwake = nil
            control.calibration = nil
            persisted.config = config
            persisted.control = control
            deps.assertions.releaseAll()
            releaseSleepDisabled()
            guard conflicts.active.isEmpty else {
                saveIfChanged(force: true)
                throw ControllerError.rejected("Charge control is off, but the keys were not restored: "
                                               + Self.conflictRefusal(conflicts.active))
            }
            restoreKeys(reason: "uninstall", bypassBlock: false)
            control = persisted.control
        }

        persisted.config = config
        persisted.control = control
        if timer != nil { scheduleTimer() }
        publish(events: emitted)
    }

    static func conflictRefusal(_ tools: [String]) -> String {
        "another charging tool is running (\(tools.joined(separator: ", "))). Quit it first: ChargeGuard never writes "
            + "while it runs. Emergency override: sudo chargectl restore --direct"
    }

    static func command(for action: ScheduleAction) -> HelperCommand {
        switch action {
        case .startCalibration: return .startCalibration(fast: false, origin: "schedule")
        case .topUp: return .startTopUp
        case .setLimit(let limit): return .setChargeLimit(limit)
        case .enableDischarge: return .startDischarge
        case .disableDischarge: return .stopDischarge
        case .setLowPowerMode(let mode): return .setLowPowerMode(mode)
        }
    }

    // MARK: - Control loop

    private func tickOnQueue() {
        guard started, !stopped else { return }
        let now = deps.clock.now

        rescanConflicts(force: false)

        let snapshot: BatterySnapshot
        do {
            snapshot = try deps.battery.readSnapshot()
        } catch {
            setBackendError("battery read failed: \(error)")
            publishStatus()
            return
        }
        lastSnapshot = snapshot
        lidClosed = deps.lid.isLidClosed() ?? false

        var events: [PolicyEvent] = []
        events += runSchedule(now: now)

        let context = PolicyContext(now: now, sleepImminent: sleepImminent, lidClosed: lidClosed,
                                    externalDisplayConnected: externalDisplayConnected,
                                    conflicts: conflicts.active,
                                    backend: backend?.capabilities ?? BackendCapabilities.none)
        let decision = PolicyEngine.evaluate(config: persisted.config, snapshot: snapshot,
                                             previous: persisted.control, context: context)
        persisted.control = decision.nextState
        lastDecision = decision
        events += decision.events

        apply(decision, snapshot: snapshot, now: now)

        for event in events {
            if case .calibrationFinished(let record) = event, record.outcome == .completed {
                deps.store.appendCalibration(record)
            }
        }
        publish(events: events)
        saveIfChanged()
        publishStatus()
    }

    private func apply(_ decision: Decision, snapshot: BatterySnapshot, now: Date) {
        let outputs = decision.outputs

        guard decision.writesAllowed else {
            // Control off or another tool running. Restore once if ChargeGuard left keys modified,
            // but never while another tool is running, and never retry faster than the control interval.
            if conflicts.active.isEmpty && persisted.keysDirty && !writeRetryBlocked(now: now) {
                lastWriteFailure = restoreKeys(reason: decision.reasonText, bypassBlock: false) ? nil : now
            }
            deps.assertions.apply(AssertionSet.none)
            releaseSleepDisabled()
            return
        }

        // Assertions, Low Power Mode and the sleep hold do not need the SMC.
        deps.assertions.apply(outputs.assertions)
        applyLowPowerMode(outputs.lowPowerMode, adapterConnected: snapshot.adapterPresent || snapshot.externalConnected)
        applySleepDisabled(outputs.holdSleepDisabled)

        guard let backend else {
            setBackendError("No supported charge-control keys on this Mac")
            return
        }
        // Never retry writes faster than the control interval.
        if writeRetryBlocked(now: now) {
            return
        }

        let dirty = Self.outputsModifyKeys(outputs, backend: backend) || persisted.control.ledManaged
        if dirty { persisted.keysDirty = true }
        writer.snapshotSummary = Self.summary(snapshot)
        do {
            _ = try backend.apply(outputs, reason: decision.reasonText)
            persisted.lastApplied = outputs
            persisted.keysDirty = dirty
            lastWriteFailure = nil
            if backendError != nil { setBackendError(nil) }
        } catch let error as SMCError {
            lastWriteFailure = now
            handleWriteFailure(error, backend: backend)
        } catch {
            lastWriteFailure = now
            setBackendError("\(error)")
        }
    }

    /// Switches to the next backend after a failed write, or shows an error state.
    private func handleWriteFailure(_ error: SMCError, backend failed: ChargeBackend) {
        logger.error(LogCategory.smc, "write failed on \(failed.kind.rawValue): \(error)")
        switch error {
        case .notPrivileged, .notProbed, .sizeMismatch:
            let next = BackendSelector.select(report: writer.report, preference: persisted.config.backendPreference)
            if next != failed.kind, let newBackend = BackendSelector.make(next, writer: writer) {
                backend = newBackend
                setBackendError(nil)
                publish(events: [.backendChanged(from: failed.kind.rawValue, to: next.rawValue, reason: error.description)])
                logger.notice(LogCategory.controller, "switched backend \(failed.kind.rawValue) -> \(next.rawValue)")
            } else if next == BackendKind.none {
                backend = nil
                setBackendError("No usable charge-control keys left: \(error.description)")
            } else {
                setBackendError(error.description)
            }
        case .writesBlocked:
            break
        default:
            setBackendError(error.description)
        }
    }

    private func setBackendError(_ message: String?) {
        if message != backendError, let message {
            publish(events: [.backendError(message: message)])
        }
        backendError = message
    }

    static func outputsModifyKeys(_ outputs: ControlOutputs, backend: ChargeBackend) -> Bool {
        if outputs.inhibitCharging || outputs.forceDischarge { return true }
        if let led = outputs.led, led != .system { return true }
        if backend.capabilities.usesFirmwareLimit && FirmwareLimitBackend.target(for: outputs) != nil { return true }
        return false
    }

    static func summary(_ s: BatterySnapshot) -> String {
        // Ints are interpolated: `%ld` is 32-bit on Windows. `%.1f` with a Double is portable.
        let hw = String(format: "%.1f", s.hardwarePercentage)
        let temp = String(format: "%.1f", s.temperatureC)
        return "battery \(s.percentage) % (hw \(hw) %), \(temp) °C, \(s.amperageMA) mA"
            + ", adapter \(s.adapterPresent ? "yes" : "no"), charging \(s.isCharging ? "yes" : "no")"
    }

    /// True while the last failed write is more recent than one control interval.
    private func writeRetryBlocked(now: Date) -> Bool {
        guard let failure = lastWriteFailure else { return false }
        return now.timeIntervalSince(failure) < persisted.config.pollIntervalSeconds * 0.9
    }

    private func blockedReasonForConflicts() -> String? {
        conflicts.active.isEmpty ? nil : "another charging tool is running (\(conflicts.active.joined(separator: ", ")))"
    }

    /// Returns true when every present key now holds its deactivate value.
    @discardableResult
    private func restoreKeys(reason: String, bypassBlock: Bool) -> Bool {
        let result = writer.restoreAll(reason: "restore: \(reason)", bypassBlock: bypassBlock)
        if result.errors.isEmpty {
            persisted.keysDirty = false
            persisted.lastApplied = .normal
            persisted.control.ledManaged = false
            if backendError?.hasPrefix("Restore incomplete") == true { setBackendError(nil) }
            logger.notice(LogCategory.controller, "normal charging restored (\(reason)), \(result.records.count) writes")
            publish(events: [.restoredNormalCharging(reason: reason)])
            return true
        } else {
            logger.error(LogCategory.controller, "restore incomplete (\(reason)): \(result.errors.joined(separator: "; "))")
            setBackendError("Restore incomplete: \(result.errors.joined(separator: "; ")). A reboot also resets the keys.")
            return false
        }
    }

    // MARK: - Low Power Mode and sleep hold

    private func applyLowPowerMode(_ desired: Bool?, adapterConnected: Bool) {
        defer { lastAdapterConnected = adapterConnected }
        guard let desired else {
            lastLowPowerDesired = nil
            return
        }
        let powerSourceChanged = lastAdapterConnected != adapterConnected
        guard desired != lastLowPowerDesired || powerSourceChanged else { return }
        lastLowPowerDesired = desired
        let current = deps.lowPowerMode.isLowPowerModeEnabled()
        lowPowerModeActive = current
        guard current != desired else { return }
        do {
            try deps.lowPowerMode.setLowPowerMode(desired)
            lowPowerModeActive = desired
            logger.info(LogCategory.power, "Low Power Mode \(desired ? "on" : "off") (\(persisted.config.lowPowerMode.rawValue))")
        } catch {
            logger.error(LogCategory.power, "pmset lowpowermode failed: \(error)")
        }
    }

    private func applySleepDisabled(_ hold: Bool) {
        if hold && !sleepDisabledHeld {
            let previous = deps.sleepDisable.isSleepDisabled() ?? false
            persisted.sleepDisabledSnapshot = previous
            saveIfChanged(force: true) // persist the snapshot before changing the system setting
            do {
                try deps.sleepDisable.setSleepDisabled(true)
                sleepDisabledHeld = true
                logger.notice(LogCategory.power, "holding SleepDisabled for clamshell discharge (was \(previous))")
            } catch {
                persisted.sleepDisabledSnapshot = nil
                logger.error(LogCategory.power, "pmset disablesleep 1 failed: \(error)")
            }
        } else if !hold && sleepDisabledHeld {
            releaseSleepDisabled()
        }
    }

    private func releaseSleepDisabled() {
        guard sleepDisabledHeld || persisted.sleepDisabledSnapshot != nil else { return }
        let restore = persisted.sleepDisabledSnapshot ?? false
        do {
            try deps.sleepDisable.setSleepDisabled(restore)
            logger.notice(LogCategory.power, "released SleepDisabled hold (restored \(restore))")
        } catch {
            logger.error(LogCategory.power, "could not restore SleepDisabled=\(restore): \(error)")
        }
        sleepDisabledHeld = false
        persisted.sleepDisabledSnapshot = nil
    }

    // MARK: - Schedule

    private func runSchedule(now: Date) -> [PolicyEvent] {
        let result = ScheduleEngine.check(rules: persisted.schedule, lastCheck: persisted.scheduleLastCheck,
                                          now: now, calendar: deps.calendar)
        persisted.schedule = result.updatedRules
        persisted.scheduleLastCheck = now
        var events: [PolicyEvent] = []
        for occurrence in result.due {
            let summary = persisted.schedule.first { $0.id == occurrence.ruleID }?.summary ?? occurrence.action.summary
            do {
                try perform(Self.command(for: occurrence.action), origin: "schedule")
                events.append(.scheduleRan(ruleID: occurrence.ruleID, summary: summary))
                logger.info(LogCategory.schedule, "ran \(summary) (scheduled \(occurrence.scheduledAt))")
            } catch {
                events.append(.scheduleMissed(ruleID: occurrence.ruleID, summary: "\(summary): \(error)"))
                logger.error(LogCategory.schedule, "could not run \(summary): \(error)")
            }
        }
        for occurrence in result.missed {
            let summary = persisted.schedule.first { $0.id == occurrence.ruleID }?.summary ?? occurrence.action.summary
            events.append(.scheduleMissed(ruleID: occurrence.ruleID, summary: "\(summary) (more than 2 hours late)"))
            logger.notice(LogCategory.schedule, "missed \(summary) scheduled \(occurrence.scheduledAt)")
        }
        return events
    }

    // MARK: - Probe and backend selection

    private func probeAndSelectBackend(reason: String) {
        let report = KeyProber.probe(deps.smc, keys: SMCKey.probeKeys, now: deps.clock.now)
        writer.updateReport(report)
        logger.info(LogCategory.smc, "probe (\(reason)):\n\(writer.report.text)")
        let kind: BackendKind
        if deps.simulated {
            kind = SimulatedBackend(writer: writer) != nil ? .simulated
                : BackendSelector.select(report: writer.report, preference: persisted.config.backendPreference)
        } else {
            kind = BackendSelector.select(report: writer.report, preference: persisted.config.backendPreference)
        }
        let previous = backend?.kind
        backend = BackendSelector.make(kind, writer: writer)
        if backend == nil {
            setBackendError("No supported charge-control keys on this Mac")
        } else if backendError?.hasPrefix("No supported") == true {
            setBackendError(nil)
        }
        if previous != kind {
            logger.notice(LogCategory.controller, "backend: \(kind.rawValue) (\(reason))")
        }
    }

    private func rescanConflicts(force: Bool) {
        let now = deps.clock.now
        if !force, let last = lastConflictScan, now.timeIntervalSince(last) < 60 { return }
        lastConflictScan = now
        let report = deps.conflicts.scan()
        if report.active != conflicts.active {
            if report.active.isEmpty {
                publish(events: [.conflictCleared])
                logger.notice(LogCategory.conflicts, "no other charging tool detected")
            } else {
                publish(events: [.conflictDetected(tools: report.active)])
                logger.notice(LogCategory.conflicts, "another charging tool is running: \(report.active.joined(separator: ", "))")
            }
        }
        conflicts = report
        writer.blockedReason = blockedReasonForConflicts()
    }

    // MARK: - Publishing and persistence

    private func recordWrite(_ record: KeyWriteRecord) {
        recentWrites.append(record)
        if recentWrites.count > 50 { recentWrites.removeFirst(recentWrites.count - 50) }
        deps.store.appendWrite(record)
        if record.success {
            logger.notice(LogCategory.writes, record.line)
        } else {
            logger.error(LogCategory.writes, record.line)
        }
    }

    private func publish(events: [PolicyEvent]) {
        guard !events.isEmpty else { return }
        let now = deps.clock.now
        let records = events.map { EventRecord(date: now, event: $0) }
        for record in records {
            deps.store.appendEvent(record)
            logger.info(LogCategory.policy, "event: \(record.event.summary)")
        }
        onEvents?(records)
    }

    private func publishStatus() {
        onStatus?(makeStatus())
    }

    /// Saves when the state changed. `scheduleLastCheck` moves on every tick, so on its own it is only
    /// checkpointed once a minute (enough for schedule catch-up after a reboot) instead of rewriting
    /// state.json every 5 seconds.
    private func saveIfChanged(force: Bool = false) {
        var comparable = persisted
        comparable.savedAt = nil
        comparable.scheduleLastCheck = nil
        guard let data = try? comparable.encoded() else { return }
        let now = deps.clock.now
        let contentChanged = data != lastSavedData
        let checkpointDue = lastSaveDate.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard force || contentChanged || checkpointDue else { return }
        var stamped = persisted
        stamped.savedAt = now
        do {
            try deps.store.save(stamped)
            lastSavedData = data
            lastSaveDate = now
        } catch {
            logger.error(LogCategory.persistence, "could not save state: \(error)")
        }
    }

    func makeStatus() -> DaemonStatus {
        let now = deps.clock.now
        let next = ScheduleEngine.nextRun(rules: persisted.schedule, after: now, calendar: deps.calendar)
        var topUpMinutes: Int?
        if persisted.control.topUp != nil, let s = lastSnapshot { topUpMinutes = TimeEstimates.minutesToFull(s) }
        let status: ChargeStatus
        if let error = backendError, lastDecision?.writesAllowed == true, backend == nil || lastWriteFailure != nil {
            status = .error(message: error)
        } else {
            status = lastDecision?.status ?? .disabled
        }
        return DaemonStatus(daemonVersion: deps.daemonVersion,
                            simulated: deps.simulated,
                            date: now,
                            snapshot: lastSnapshot,
                            config: persisted.config,
                            control: persisted.control,
                            chargeStatus: status,
                            effectiveLimit: lastDecision?.effectiveLimit ?? persisted.config.chargeLimit,
                            controlPercentage: lastDecision?.controlPercentage,
                            lastOutputs: persisted.lastApplied,
                            backend: backend?.kind ?? BackendKind.none,
                            backendCapabilities: backend?.capabilities ?? BackendCapabilities.none,
                            backendLimitations: backend?.limitations ?? [],
                            backendError: backendError,
                            hardware: backend?.readState(),
                            conflicts: conflicts,
                            probe: writer.report,
                            schedule: persisted.schedule,
                            nextScheduledRun: next.map { ScheduledRunInfo(ruleID: $0.rule.id, date: $0.date, summary: $0.rule.summary) },
                            lowPowerModeActive: lowPowerModeActive,
                            keysDirty: persisted.keysDirty,
                            sleepImminent: sleepImminent,
                            lidClosed: lidClosed,
                            topUpMinutesRemaining: topUpMinutes,
                            firmwareVersion: deps.firmwareVersion,
                            lastWrites: recentWrites)
    }

    // MARK: - Test hooks

    /// Current persisted state (tests). Must not be called on `queue`.
    public func persistedSync() -> PersistedState {
        queue.sync { persisted }
    }
}
