import Foundation
import Security
import ChargeGuardCore

/// Validates XPC clients before the daemon accepts them.
///
/// Signed with a Team ID (Apple Development or Developer ID): the client's code, looked up by its audit
/// token with SecCodeCopyGuestWithAttributes, must satisfy the designated requirement
/// "anchor apple generic, same Team ID, identifier com.amir.chargeguard or com.amir.chargeguard.chargectl"
/// (SecCodeCheckValidity). The connection also gets the same requirement through
/// NSXPCConnection.setCodeSigningRequirement as a second check.
///
/// Ad-hoc signed (releases and development without a certificate): there is no Team ID to pin, so the
/// check falls back to a valid signature plus `AdHocClientRule`: an exact signing identifier
/// (com.amir.chargeguard or com.amir.chargeguard.chargectl) at a matching location. This is weaker and is
/// logged as such.
final class ClientValidator {
    private let logger: CoreLogger
    private let allowAnyClient: Bool
    static let allowedIdentifiers = [HelperProtocol.appBundleIdentifier, HelperProtocol.chargectlIdentifier]

    /// The daemon's own Team ID, nil when ad-hoc signed.
    let ownTeamID: String?

    init(logger: CoreLogger, allowAnyClient: Bool = false) {
        self.logger = logger
        self.allowAnyClient = allowAnyClient
        self.ownTeamID = Self.teamIdentifierOfSelf()
        if let team = ownTeamID {
            logger.info(LogCategory.xpc, "clients must be signed by Team ID \(team)")
        } else {
            logger.notice(LogCategory.xpc, "helper is ad-hoc signed: client validation uses the weaker identifier and path check")
        }
    }

    var requirementText: String? {
        guard let team = ownTeamID else { return nil }
        let identifiers = Self.allowedIdentifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and (\(identifiers))"
    }

    func validate(_ connection: NSXPCConnection) -> Bool {
        if allowAnyClient {
            logger.notice(LogCategory.xpc, "simulation without root: accepting any client")
            return true
        }
        guard let code = guestCode(for: connection) else {
            logger.error(LogCategory.xpc, "could not look up the client's code")
            return false
        }

        if let requirementText {
            var requirementRef: SecRequirement?
            guard SecRequirementCreateWithString(requirementText as CFString, [], &requirementRef) == errSecSuccess,
                  let requirement = requirementRef else {
                logger.error(LogCategory.xpc, "invalid requirement: \(requirementText)")
                return false
            }
            let status = SecCodeCheckValidity(code, [], requirement)
            guard status == errSecSuccess else {
                logger.error(LogCategory.xpc, "client fails the designated requirement (OSStatus \(status))")
                return false
            }
            connection.setCodeSigningRequirement(requirementText)
            return true
        }

        // Ad-hoc fallback (weaker).
        logger.notice(LogCategory.xpc, "ad-hoc signed build: checking the client's identifier and path only (weaker than a Team ID check)")
        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else {
            logger.error(LogCategory.xpc, "client signature invalid")
            return false
        }
        let identifier = Self.signingIdentifier(of: code) ?? ""
        let path = Self.path(of: code) ?? ""
        // Exact identifier, and a location that matches it. SecCodeCopyPath gives the bundle for the app,
        // so matching the app's executable path (as before 1.0.0) rejected the app; see AdHocClientRule.
        let accepted = AdHocClientRule.accepts(identifier: identifier, path: path)
        if !accepted {
            logger.error(LogCategory.xpc, "client rejected: identifier '\(identifier)', path '\(path)'")
        }
        return accepted
    }

    // MARK: Security framework helpers

    private func guestCode(for connection: NSXPCConnection) -> SecCode? {
        var attributes: [CFString: Any] = [:]
        if let token = Self.auditTokenData(connection) {
            attributes[kSecGuestAttributeAudit] = token
        } else {
            logger.notice(LogCategory.xpc, "audit token unavailable, falling back to the pid (racy)")
            attributes[kSecGuestAttributePid] = connection.processIdentifier
        }
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code)
        guard status == errSecSuccess else {
            logger.error(LogCategory.xpc, "SecCodeCopyGuestWithAttributes failed: \(status)")
            return nil
        }
        return code
    }

    /// NSXPCConnection's audit token is not public API; it is read with KVC, as most privileged helpers do.
    static func auditTokenData(_ connection: NSXPCConnection) -> Data? {
        guard connection.responds(to: NSSelectorFromString("auditToken")),
              let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        value.getValue(&token, size: MemoryLayout<audit_token_t>.size)
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    static func signingInformation(of code: SecCode) -> [String: Any]? {
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticRef) == errSecSuccess, let staticCode = staticRef else { return nil }
        var infoRef: CFDictionary?
        // kSecCSSigningInformation imports as UInt32 (anonymous CF_ENUM); if not, use SecCSFlags(rawValue: 1 << 1).
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef else { return nil }
        return info as? [String: Any]
    }

    static func signingIdentifier(of code: SecCode) -> String? {
        signingInformation(of: code)?[kSecCodeInfoIdentifier as String] as? String
    }

    static func path(of code: SecCode) -> String? {
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticRef) == errSecSuccess, let staticCode = staticRef else { return nil }
        var urlRef: CFURL?
        guard SecCodeCopyPath(staticCode, [], &urlRef) == errSecSuccess, let url = urlRef else { return nil }
        return (url as URL).path
    }

    static func teamIdentifierOfSelf() -> String? {
        var selfRef: SecCode?
        guard SecCodeCopySelf([], &selfRef) == errSecSuccess, let code = selfRef else { return nil }
        return signingInformation(of: code)?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
