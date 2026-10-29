import Foundation

/// Chooses a backend from probe results. Never looks at the macOS version or chip name.
public enum BackendSelector {
    /// Automatic preference order: direct charge keys, then the firmware limit, then adapter cutoff.
    public static let automaticOrder: [BackendKind] = [.legacyKeys, .firmwareLimit, .adapterCutoff]

    /// Whether the probe (minus keys that failed with kIOReturnNotPrivileged) supports `kind`.
    public static func isSupported(_ kind: BackendKind, report: KeyProbeReport) -> Bool {
        switch kind {
        case .legacyKeys:
            return report.isUsable(SMCKey.chargeInhibitTahoe)
                || (report.isUsable(SMCKey.chargeInhibitB) && report.isUsable(SMCKey.chargeInhibitC))
        case .firmwareLimit:
            return SMCKey.firmwareKeys.allSatisfy { report.isUsable($0) }
        case .adapterCutoff:
            return SMCKey.dischargeKeys.contains { report.isUsable($0) }
        case .simulated, .none:
            return false
        }
    }

    /// Supported backends in fallback order, starting with the preferred one when it is supported.
    public static func candidates(report: KeyProbeReport, preference: BackendPreference,
                                  excluding: Set<BackendKind> = []) -> [BackendKind] {
        var order = automaticOrder
        if let preferred = BackendKind(preference: preference), let index = order.firstIndex(of: preferred) {
            order.remove(at: index)
            order.insert(preferred, at: 0)
        }
        return order.filter { !excluding.contains($0) && isSupported($0, report: report) }
    }

    public static func select(report: KeyProbeReport, preference: BackendPreference,
                              excluding: Set<BackendKind> = []) -> BackendKind {
        candidates(report: report, preference: preference, excluding: excluding).first ?? .none
    }

    /// Instantiates a backend over `writer`. Returns nil for `.none` or when the keys are missing.
    public static func make(_ kind: BackendKind, writer: GuardedSMCWriter) -> ChargeBackend? {
        switch kind {
        case .legacyKeys: return LegacyKeysBackend(writer: writer)
        case .firmwareLimit: return FirmwareLimitBackend(writer: writer)
        case .adapterCutoff: return AdapterCutoffBackend(writer: writer)
        case .simulated: return SimulatedBackend(writer: writer)
        case .none: return nil
        }
    }
}

extension BackendKind {
    init?(preference: BackendPreference) {
        switch preference {
        case .automatic: return nil
        case .legacyKeys: self = .legacyKeys
        case .firmwareLimit: self = .firmwareLimit
        case .adapterCutoff: self = .adapterCutoff
        }
    }
}
