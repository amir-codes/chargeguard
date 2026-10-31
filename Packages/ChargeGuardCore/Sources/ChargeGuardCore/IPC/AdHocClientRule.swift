import Foundation

/// The helper's client check for ad-hoc signed builds, where there is no Team ID to pin.
///
/// A client is accepted when its signing identifier is the app's or chargectl's, and its on-disk location
/// matches that identifier. `SecCodeCopyPath` reports the bundle for an app (".../ChargeGuard.app") and the
/// executable for a plain tool (".../chargectl"), so the app is matched by its bundle path. This is weaker
/// than a Team ID check: any validly signed code with the same identifier and name would pass.
public enum AdHocClientRule {
    public static func accepts(identifier: String, path: String) -> Bool {
        switch identifier {
        case HelperProtocol.appBundleIdentifier:
            // The bundle path is what SecCodeCopyPath returns; the executable path is accepted too in case a
            // caller passes it.
            return path.hasSuffix("/ChargeGuard.app") || path.hasSuffix("/ChargeGuard.app/Contents/MacOS/ChargeGuard")
        case HelperProtocol.chargectlIdentifier:
            return (path as NSString).lastPathComponent == "chargectl"
        default:
            return false
        }
    }
}
