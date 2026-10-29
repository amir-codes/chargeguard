import Foundation

public enum TransportError: Error, Equatable, CustomStringConvertible {
    case notConnected
    case timedOut
    case remote(String)
    case unexpectedResponse

    public var description: String {
        switch self {
        case .notConnected: return "The ChargeGuard helper is not running or not installed."
        case .timedOut: return "The ChargeGuard helper did not answer in time."
        case .remote(let message): return message
        case .unexpectedResponse: return "Unexpected answer from the helper."
        }
    }
}

/// How the app talks to the controller: over XPC to the root helper (ChargeGuardSystem.XPCHelperClient),
/// or in-process for `--simulate` (`InProcessTransport`).
public protocol HelperTransport: AnyObject {
    var onStatus: ((DaemonStatus) -> Void)? { get set }
    var onEvents: (([EventRecord]) -> Void)? { get set }
    var onConnectionChange: ((Bool) -> Void)? { get set }
    func connect()
    func invalidate()
    func send(_ request: HelperRequest) async throws -> HelperResponse
}

public extension HelperTransport {
    /// Sends a command and returns the resulting status, mapping `.error` to a thrown error.
    @discardableResult
    func command(_ command: HelperCommand) async throws -> DaemonStatus? {
        let response = try await send(.command(command))
        switch response {
        case .status(let status): return status
        case .error(let message): throw TransportError.remote(message)
        case .ok: return nil
        default: throw TransportError.unexpectedResponse
        }
    }

    func status() async throws -> DaemonStatus {
        let response = try await send(.getStatus)
        switch response {
        case .status(let status): return status
        case .error(let message): throw TransportError.remote(message)
        default: throw TransportError.unexpectedResponse
        }
    }
}

/// Runs a `ChargeController` in the app process (simulation). No XPC, no root.
public final class InProcessTransport: HelperTransport {
    public let controller: ChargeController
    public var onStatus: ((DaemonStatus) -> Void)?
    public var onEvents: (([EventRecord]) -> Void)?
    public var onConnectionChange: ((Bool) -> Void)?

    public init(controller: ChargeController) {
        self.controller = controller
    }

    public func connect() {
        controller.onStatus = { [weak self] status in self?.onStatus?(status) }
        controller.onEvents = { [weak self] events in self?.onEvents?(events) }
        controller.start()
        onConnectionChange?(true)
    }

    public func invalidate() {
        controller.onStatus = nil
        controller.onEvents = nil
    }

    public func send(_ request: HelperRequest) async throws -> HelperResponse {
        // Round-trip through the codec so simulation exercises the same encoding as XPC.
        let data = try MessageCodec.encode(request)
        let decoded = try MessageCodec.decodeRequest(data)
        return try await withCheckedThrowingContinuation { continuation in
            controller.handle(decoded) { response in
                do {
                    let encoded = try MessageCodec.encode(response)
                    continuation.resume(returning: try MessageCodec.decodeResponse(encoded))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A simulated Mac for `--simulate`: time runs `timeScale` times faster, with a scripted battery curve.
    public static func simulated(timeScale: Double = 60, profile: SimulatedSMC.Profile = .tahoe,
                                 logger: CoreLogger = MemoryLogger()) -> InProcessTransport {
        let clock = ScaledTimeSource(scale: timeScale)
        let (deps, _) = ControllerDependencies.makeSimulated(profile: profile, clock: clock, charge: 62,
                                                             script: SimulatedBattery.demoScript(), logger: logger)
        // Simulation starts with control enabled so the UI shows real behaviour.
        try? deps.store.save(PersistedState(config: PolicyConfig(controlEnabled: true)))
        let controller = ChargeController(dependencies: deps)
        return InProcessTransport(controller: controller)
    }
}
