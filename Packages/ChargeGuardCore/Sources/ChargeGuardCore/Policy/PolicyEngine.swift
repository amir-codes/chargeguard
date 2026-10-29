import Foundation

/// The policy engine: a pure, deterministic function
/// (PolicyConfig, BatterySnapshot, ControlState, PolicyContext) -> Decision.
///
/// Precedence, highest first:
/// 1. Gates: no battery, another charging tool, control disabled, enforcement suspended.
/// 2. Heat Protection: blocks charging, overriding calibration and top up.
/// 3. Sleep: no forced discharge while sleeping; optional charge block before sleep.
/// 4. Lid closed without clamshell discharge: discharge pauses.
/// 5. Calibration, then manual discharge, then top up, then automatic discharge, then the limit.
public enum PolicyEngine {
    /// Discharge is never allowed below this level.
    public static let minimumDischargeFloor = 5

    public static func evaluate(config rawConfig: PolicyConfig, snapshot: BatterySnapshot,
                                previous: ControlState, context: PolicyContext) -> Decision {
        let config = rawConfig.normalized()
        let now = context.now
        let pct = snapshot.controlPercentage(useHardware: config.useHardwarePercentage)
        let adapter = snapshot.adapterPresent || snapshot.externalConnected
        var state = previous
        var events: [PolicyEvent] = []
        var reasons: [String] = []

        func gate(_ status: ChargeStatus, _ reason: String, writes: Bool, outputs: ControlOutputs = .normal) -> Decision {
            Decision(outputs: outputs, nextState: state, status: status, events: [], reasons: [reason],
                     writesAllowed: writes, effectiveLimit: config.chargeLimit, controlPercentage: pct)
        }

        // 1. Gates.
        guard snapshot.batteryInstalled else {
            return gate(.noBattery, "no battery installed", writes: false)
        }
        if !context.conflicts.isEmpty {
            return gate(.conflict(tools: context.conflicts),
                        "another charging tool is running: \(context.conflicts.joined(separator: ", "))", writes: false)
        }
        if !config.controlEnabled {
            state.ledManaged = false
            state.dischargeActive = false
            return gate(.disabled, "charge control is off", writes: false)
        }
        if state.enforcementSuspended {
            var outputs = ControlOutputs.normal
            if state.ledManaged { outputs.led = .system }
            state.ledManaged = false
            state.dischargeActive = false
            return gate(.suspended, "ChargeGuard quit with \"restore normal charging\" selected", writes: true, outputs: outputs)
        }

        // 2. Heat latch.
        let heat = config.heatProtection
        let resumeTemperature = heat.maxTemperatureC - heat.resumeDeltaC
        if heat.enabled {
            if !state.heatPaused && snapshot.temperatureC >= heat.maxTemperatureC {
                state.heatPaused = true
                events.append(.heatPaused(temperatureC: snapshot.temperatureC))
            } else if state.heatPaused && snapshot.temperatureC <= resumeTemperature {
                state.heatPaused = false
                events.append(.heatResumed(temperatureC: snapshot.temperatureC))
            }
        } else if state.heatPaused {
            state.heatPaused = false
        }

        // 3. Top up end conditions.
        if let topUp = state.topUp {
            var endReason: String?
            if !adapter {
                endReason = "adapter unplugged"
            } else if snapshot.fullyCharged || (pct >= 100 && !snapshot.isCharging) {
                endReason = "fully charged"
            } else if now.timeIntervalSince(topUp.startedAt) > TopUpState.maximumDuration {
                endReason = "timed out after 12 hours"
            }
            if let endReason {
                state.topUp = nil
                if adapter { state.autoDischargeSuppressed = true }
                events.append(.topUpFinished(reason: endReason))
                reasons.append("top up finished: \(endReason)")
            }
        }
        if !adapter { state.autoDischargeSuppressed = false }

        // 4. Calibration.
        if let cal = state.calibration {
            let step = CalibrationMachine.advance(cal, percentage: pct, snapshot: snapshot, adapterConnected: adapter,
                                                  config: config, now: now)
            state.calibration = step.state
            events += step.events
            if step.finished != nil { reasons.append("calibration finished, configured limit restored") }
        }

        // 5. Effective ceiling and resume band.
        var ceiling = config.chargeLimit
        if let cal = state.calibration {
            ceiling = CalibrationMachine.ceiling(for: cal.phase, configuredLimit: config.chargeLimit)
        } else if state.topUp != nil {
            ceiling = 100
        }
        var band = config.resumeBand
        if context.backend.inhibitIsAdapterCutoff { band = max(band, config.adapterCutoffMinBand) }
        let resumeAt = max(0, ceiling - band)

        // 6. Limit latch (hysteresis / sailing).
        var latch = state.chargeInhibitLatched
        if ceiling >= 100 {
            latch = false
        } else if pct >= ceiling {
            if !latch && adapter { events.append(.limitReached(limit: ceiling)) }
            latch = true
            reasons.append("\(pct) % >= limit \(ceiling) %")
        } else if let last = state.lastEffectiveLimit, ceiling > last {
            latch = false
            reasons.append("limit raised from \(last) % to \(ceiling) %")
        } else if latch {
            let resume = config.sailing.enabled ? pct <= resumeAt : pct < resumeAt
            if resume {
                latch = false
                reasons.append(config.sailing.enabled ? "sailing range reached (\(pct) % <= \(resumeAt) %)"
                                                      : "below resume level (\(pct) % < \(resumeAt) %)")
            }
        }
        state.lastEffectiveLimit = ceiling

        // 7. Discharge target.
        var dischargeTarget: Int?
        var automatic = false
        if let cal = state.calibration, cal.phase == .dischargeToFloor {
            dischargeTarget = max(CalibrationMachine.absoluteFloor, cal.dischargeTarget ?? config.calibration.dischargeFloor)
            reasons.append("calibration phase B: discharge to \(dischargeTarget!) %")
        } else if state.manualDischarge {
            let target = max(minimumDischargeFloor, config.chargeLimit)
            if pct > target {
                dischargeTarget = target
                reasons.append("manual discharge to \(target) %")
            } else {
                state.manualDischarge = false
                latch = ceiling < 100
                reasons.append("manual discharge reached \(target) %, charging stays blocked")
            }
        } else if config.automaticDischarge, state.topUp == nil, !state.autoDischargeSuppressed, adapter, ceiling < 100, pct > ceiling {
            dischargeTarget = max(minimumDischargeFloor, ceiling)
            automatic = true
            reasons.append("automatic discharge to \(ceiling) %")
        }

        var forceDischarge = false
        var dischargePausedReason: String?
        if let target = dischargeTarget, adapter, pct > target {
            if context.backend.canForceDischarge {
                forceDischarge = true
            } else {
                dischargePausedReason = "this Mac has no usable discharge key"
            }
        }

        // 8. Charging inhibit and overrides.
        var inhibit = latch && ceiling < 100
        var overrideHold: Int?
        if forceDischarge || state.calibration?.phase == .dischargeToFloor {
            inhibit = true
            overrideHold = dischargeTarget ?? pct
        }

        if state.heatPaused && adapter {
            inhibit = true
            if overrideHold == nil { overrideHold = pct }
            reasons.append(String(format: "heat protection: %.1f °C", snapshot.temperatureC))
        }

        if forceDischarge && context.lidClosed && !config.dischargeInClamshell {
            forceDischarge = false
            dischargePausedReason = "lid closed (turn on Discharge in Clamshell Mode)"
            reasons.append("discharge paused: lid closed")
        }

        var sleepBlocked = false
        if context.sleepImminent {
            if forceDischarge {
                forceDischarge = false
                dischargePausedReason = "Mac is going to sleep"
                reasons.append("discharge paused for sleep")
            }
            if config.stopChargingWhenSleeping && adapter && !inhibit && ceiling < 100 && pct < ceiling {
                inhibit = true
                overrideHold = pct
                sleepBlocked = true
                reasons.append("stop charging when sleeping: holding at \(pct) %")
            }
            if context.backend.inhibitIsAdapterCutoff {
                // The adapter must stay connected while asleep: nothing could reconnect it.
                inhibit = false
                overrideHold = nil
                sleepBlocked = false
                reasons.append("adapter-cutoff backend: adapter reconnected for sleep")
            }
        }

        if !adapter { forceDischarge = false }

        // Discharge start/finish events.
        if forceDischarge && !previous.dischargeActive, let target = dischargeTarget {
            events.append(.dischargeStarted(target: target, automatic: automatic))
        }
        if !forceDischarge && previous.dischargeActive && dischargeTarget == nil {
            events.append(.dischargeFinished(percentage: pct))
        }
        state.dischargeActive = forceDischarge
        state.chargeInhibitLatched = latch

        // 9. MagSafe LED.
        var led: LEDState?
        if context.backend.canControlLED {
            switch config.magSafeLED {
            case .systemDefault:
                if state.ledManaged { led = .system }
                state.ledManaged = false
            case .alwaysOff:
                led = adapter ? .off : nil
                state.ledManaged = true
            case .followState:
                state.ledManaged = true
                if !adapter {
                    led = nil
                } else if forceDischarge {
                    led = .off
                } else if inhibit || pct >= 100 || snapshot.fullyCharged {
                    led = .green
                } else {
                    led = .orange
                }
            }
        }

        // 10. Keep awake expiry.
        if let keepAwake = state.keepAwake {
            if let until = keepAwake.until, now >= until {
                state.keepAwake = nil
                events.append(.keepAwakeEnded)
            } else if keepAwake.untilChargeLimit && pct >= ceiling {
                state.keepAwake = nil
                events.append(.keepAwakeEnded)
            }
        }

        // 11. Power assertions.
        var assertions = AssertionSet()
        if let keepAwake = state.keepAwake {
            assertions.preventIdleSystemSleep = true
            assertions.preventDisplaySleep = keepAwake.preventDisplaySleep
        }
        if state.calibration != nil {
            assertions.preventIdleSystemSleep = true
        }
        if config.disableSleepUntilLimit && adapter && !inhibit && !forceDischarge && pct < ceiling {
            assertions.preventIdleSystemSleep = true
            reasons.append("disable sleep until limit")
        }
        if forceDischarge && config.dischargeInClamshell {
            assertions.preventSystemSleep = true
        }
        let holdSleepDisabled = forceDischarge && config.dischargeInClamshell && config.clamshellForceAwake
            && context.externalDisplayConnected

        // 12. Low Power Mode.
        let lowPowerMode = config.lowPowerMode.desiredState(adapterConnected: adapter)

        let outputs = ControlOutputs(inhibitCharging: inhibit,
                                     forceDischarge: forceDischarge,
                                     chargeCeiling: ceiling,
                                     resumeFloor: resumeAt,
                                     holdAtPercentage: inhibit ? overrideHold : nil,
                                     led: led,
                                     assertions: assertions,
                                     holdSleepDisabled: holdSleepDisabled,
                                     lowPowerMode: lowPowerMode)

        // 13. Status.
        let status: ChargeStatus
        if state.heatPaused && adapter {
            status = .heatPaused(temperatureC: snapshot.temperatureC, resumeAtC: resumeTemperature)
        } else if let cal = state.calibration {
            status = .calibrating(phase: cal.phase, waitingForAdapter: !adapter && CalibrationMachine.needsAdapter(cal.phase))
        } else if forceDischarge, let target = dischargeTarget {
            status = .discharging(target: target, automatic: automatic)
        } else if let reason = dischargePausedReason, adapter {
            status = .dischargePaused(reason: reason)
        } else if !adapter {
            status = .onBattery
        } else if sleepBlocked {
            status = .sleepBlocked
        } else if state.topUp != nil {
            status = .toppingUp
        } else if inhibit && ceiling < 100 {
            status = config.sailing.enabled ? .sailing(limit: ceiling, resumeAt: resumeAt) : .limitReached(limit: ceiling)
        } else if pct >= 100 || snapshot.fullyCharged {
            status = .fullyCharged
        } else {
            status = .charging(target: ceiling)
        }

        if reasons.isEmpty { reasons.append(inhibit ? "holding at limit \(ceiling) %" : "charging allowed up to \(ceiling) %") }

        return Decision(outputs: outputs, nextState: state, status: status, events: events, reasons: reasons,
                        writesAllowed: true, effectiveLimit: ceiling, controlPercentage: pct)
    }
}
