import AppKit
import Foundation
import Observation
import ChargeGuardCore
import ChargeGuardSystem
import ChargeGuardSessionKit

/// Connection to the helper as the UI sees it.
enum HelperConnection: Equatable {
    case connecting
    case connected
    /// The helper is not installed or not running.
    case missing
    /// App and helper speak different protocol versions: offer to reinstall the helper.
    case versionMismatch(helper: Int)
}

/// The app's single source of truth. The daemon owns the policy; this model mirrors its status,
/// sends commands, and keeps app-only state (preferences, energy list, history).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(simulate: CommandLine.arguments.contains("--simulate"))

    let simulated: Bool
    let preferences = AppPreferences()
    let installer = HelperInstaller()
    let notifier = Notifier()

    private(set) var connection: HelperConnection = .connecting
    private(set) var status: DaemonStatus?
    /// Read directly from the IORegistry (no root): live data even without the helper, and the
    /// 2-second refresh of the power flow.
    private(set) var liveSnapshot: BatterySnapshot?
    private(set) var energy: EnergySample?
    private(set) var calibrationHistory: [CalibrationRecord] = []
    private(set) var recentEvents: [EventRecord] = []
    private(set) var recentWrites: [KeyWriteRecord] = []
    /// Fast user switching: the app in an inactive session stops sending commands (feature 23).
    private(set) var isPassive = false
    var lastError: String?
    /// Set when the first-run window should open.
    var showOnboarding = false

    private let transport: HelperTransport
    private let localReader = IORegistryBatteryReader()
    private let workspace = WorkspaceObserver()
    private var pollTimer: Timer?
    private var liveTimer: Timer?
    private var liveRefreshClients = 0
    private var lastStatusDate = Date.distantPast
    private var started = false

    init(simulate: Bool) {
        simulated = simulate
        if simulate {
            transport = InProcessTransport.simulated(timeScale: 60)
        } else {
            transport = XPCHelperClient()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        notifier.enabled = { [weak self] in self?.preferences.notificationsEnabled ?? true }
        notifier.requestAuthorization()

        transport.onStatus = { [weak self] status in
            Task { @MainActor in self?.receive(status) }
        }
        transport.onEvents = { [weak self] events in
            Task { @MainActor in self?.receive(events) }
        }
        transport.onConnectionChange = { [weak self] connected in
            Task { @MainActor in
                if !connected { self?.connection = .missing }
            }
        }
        transport.connect()

        workspace.onSessionActiveChange = { [weak self] active in
            Task { @MainActor in self?.isPassive = !active }
        }
        workspace.onDidWake = { [weak self] in
            Task { @MainActor in await self?.refreshStatus() }
        }
        workspace.onScreensChange = { [weak self] in
            Task { @MainActor in await self?.reportDisplays() }
        }
        workspace.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollBackstop() }
        }
        Task {
            await handshake()
            await send(.appLaunched)
            await reportDisplays()
            await refreshStatus()
            if !preferences.hasCompletedOnboarding && !simulated { showOnboarding = true }
        }
        readLocalSnapshot()
    }

    /// Called from applicationWillTerminate. Tells the helper so "restore on quit" can apply.
    func prepareForQuit() {
        guard !isPassive else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let transport = self.transport
        Task.detached {
            _ = try? await transport.send(.command(.appWillQuit))
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    // MARK: Receiving

    private func receive(_ status: DaemonStatus) {
        self.status = status
        lastStatusDate = Date()
        if connection != .connected, status.protocolVersion == HelperProtocol.version { connection = .connected }
    }

    private func receive(_ events: [EventRecord]) {
        recentEvents = Array((recentEvents + events).suffix(200))
        guard !isPassive else { return }
        for record in events { notifier.post(record.event) }
    }

    private func handshake() async {
        do {
            let response = try await transport.send(.hello(clientProtocolVersion: HelperProtocol.version, client: "ChargeGuard app"))
            if case .hello(let info) = response {
                connection = info.compatible ? .connected : .versionMismatch(helper: info.protocolVersion)
            }
        } catch {
            connection = .missing
        }
    }

    func refreshStatus() async {
        installer.refresh()
        do {
            let status = try await transport.status()
            receive(status)
        } catch {
            if case .versionMismatch = connection { return }
            connection = .missing
        }
    }

    private func pollBackstop() async {
        readLocalSnapshot()
        if connection != .connected {
            await handshake()
            if connection == .connected { await send(.appLaunched) }
        }
        if Date().timeIntervalSince(lastStatusDate) > 8 { await refreshStatus() }
    }

    private func readLocalSnapshot() {
        if simulated {
            liveSnapshot = status?.snapshot
        } else {
            liveSnapshot = try? localReader.readSnapshot()
        }
    }

    /// Views that need 2-second updates (power flow) call begin/end.
    func beginLiveRefresh() {
        liveRefreshClients += 1
        guard liveTimer == nil else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readLocalSnapshot() }
        }
    }

    func endLiveRefresh() {
        liveRefreshClients = max(0, liveRefreshClients - 1)
        if liveRefreshClients == 0 {
            liveTimer?.invalidate()
            liveTimer = nil
        }
    }

    private func reportDisplays() async {
        await send(.setExternalDisplayConnected(WorkspaceObserver.externalDisplayConnected), quiet: true)
    }

    // MARK: Derived state

    var config: PolicyConfig { status?.config ?? PolicyConfig() }
    var control: ControlState { status?.control ?? ControlState() }
    /// Daemon snapshot when connected, else the locally read one.
    var snapshot: BatterySnapshot? {
        if connection == .connected, let s = status?.snapshot { return s }
        return liveSnapshot ?? status?.snapshot
    }
    /// The freshest snapshot for live views (power flow).
    var freshSnapshot: BatterySnapshot? { simulated ? status?.snapshot : (liveSnapshot ?? status?.snapshot) }
    var isConnected: Bool { connection == .connected }
    var controlEnabled: Bool { config.controlEnabled }
    var conflicts: [String] { status?.conflicts.active ?? [] }

    var statusKind: StatusKind {
        guard isConnected, let status else { return .helperMissing }
        if !status.conflicts.active.isEmpty { return .conflict }
        return status.chargeStatus.kind
    }

    var stateLine: String {
        switch connection {
        case .connecting: return "Connecting to the helper…"
        case .missing: return "Helper not running: showing battery data only"
        case .versionMismatch: return "Helper version mismatch: reinstall the helper"
        case .connected: return status?.chargeStatus.title ?? "Waiting for the helper…"
        }
    }

    var canDischarge: Bool { isConnected && (status?.backendCapabilities.canForceDischarge ?? false) }

    // MARK: Commands

    @discardableResult
    func send(_ command: HelperCommand, quiet: Bool = false) async -> Bool {
        guard !isPassive else {
            if !quiet { lastError = "ChargeGuard is passive in this user session; switch back to change settings." }
            return false
        }
        do {
            if let status = try await transport.command(command) { receive(status) }
            if !quiet { lastError = nil }
            return true
        } catch {
            if !quiet { lastError = "\(error)" }
            if (error as? TransportError) == .notConnected { connection = .missing }
            return false
        }
    }

    func perform(_ command: HelperCommand) {
        Task { await send(command) }
    }

    /// Edits the policy and sends the whole config.
    func updateConfig(_ change: (inout PolicyConfig) -> Void) {
        var c = config
        change(&c)
        perform(.updateConfig(c))
    }

    func setLimit(_ limit: Int) { perform(.setChargeLimit(limit)) }

    func setDischarge(_ on: Bool) { perform(on ? .startDischarge : .stopDischarge) }
    func setTopUp(_ on: Bool) { perform(on ? .startTopUp : .cancelTopUp) }
    func setHeatProtection(_ on: Bool) { perform(.setHeatProtection(on)) }
    func setSailing(_ on: Bool) { perform(.setSailing(on)) }

    func startCalibration(fast: Bool = false) { perform(.startCalibration(fast: fast, origin: "user")) }
    func cancelCalibration() { perform(.cancelCalibration) }

    func keepAwake(seconds: TimeInterval?, untilLimit: Bool = false, display: Bool = false) {
        perform(.keepAwake(KeepAwakeRequest(durationSeconds: seconds, untilChargeLimit: untilLimit, preventDisplaySleep: display)))
    }

    func restoreNormalCharging() { perform(.restoreNormalCharging) }

    func confirmFirstRun() async -> Bool {
        let ok = await send(.confirmFirstRun)
        if ok { preferences.hasCompletedOnboarding = true }
        return ok
    }

    func probeKeys() async -> KeyProbeReport? {
        guard let response = try? await transport.send(.probeKeys), case .probe(let report) = response else { return nil }
        await refreshStatus()
        return report
    }

    func setSchedule(_ rules: [ScheduleRule]) { perform(.setSchedule(rules)) }

    // MARK: Energy, history, logs

    /// Asks the helper (powermetrics as root); falls back to a local proc_pid_rusage sample.
    func refreshEnergy() async {
        if isConnected, let response = try? await transport.send(.energySample), case .energy(let sample) = response,
           !sample.processes.isEmpty {
            energy = sample
            return
        }
        let sample = await Task.detached(priority: .utility) { RusageSampler().sample() }.value
        energy = sample
    }

    func loadHistory() async {
        if let response = try? await transport.send(.calibrationHistory(limit: 50)), case .calibrationHistory(let records) = response {
            calibrationHistory = records.reversed()
        }
        if let response = try? await transport.send(.recentEvents(limit: 200)), case .events(let events) = response {
            recentEvents = events
        }
        if let response = try? await transport.send(.recentWrites(limit: 100)), case .writes(let writes) = response {
            recentWrites = writes
        }
    }

    func exportSettings(to url: URL) async throws {
        let response = try await transport.send(.exportSettings)
        guard case .settings(var export) = response else { throw TransportError.unexpectedResponse }
        export.appPreferences = preferences.exportData()
        try CoreJSON.encoder(pretty: true).encode(export).write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let export = try CoreJSON.decoder().decode(SettingsExport.self, from: data)
        if let prefs = export.appPreferences { preferences.importData(prefs) }
        _ = try await transport.command(.importSettings(export))
        await refreshStatus()
    }

    /// Writes the unified log for subsystem com.amir.chargeguard (last 24 h) plus the helper's
    /// recent key writes and events to a text file.
    func exportLogs(to url: URL) async throws {
        await loadHistory()
        let writes = recentWrites.map(\.line).joined(separator: "\n")
        let events = recentEvents.map { "\($0.date): \($0.event.summary)" }.joined(separator: "\n")
        let log = await Task.detached(priority: .utility) { () -> String in
            let result = try? ProcessRunner().run("/usr/bin/log", ["show", "--last", "1d", "--style", "compact",
                                                                  "--predicate", "subsystem == \"com.amir.chargeguard\""],
                                                  timeout: 60)
            return result?.stdout ?? "(log show failed)"
        }.value
        let text = """
        ChargeGuard log export \(Date())
        App \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), helper \(status?.daemonVersion ?? "not connected")
        macOS \(MachineInfo.osVersion), model \(MachineInfo.modelIdentifier ?? "?"), firmware \(status?.firmwareVersion ?? "?")
        Backend: \(status?.backend.displayName ?? "-")

        == Probe ==
        \(status?.probe?.text ?? "-")

        == Recent SMC writes ==
        \(writes)

        == Recent events ==
        \(events)

        == Unified log (subsystem com.amir.chargeguard) ==
        \(log)
        """
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    func quitApp(pid: Int32) {
        RunningApps.quit(pid: pid)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await refreshEnergy()
        }
    }
}
