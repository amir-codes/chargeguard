import Foundation
import ChargeGuardCore

/// The daemon's exported interface. Messages are JSON `MessageEnvelope`s (ChargeGuardCore.MessageCodec),
/// so the @objc surface stays tiny and versioned.
@objc public protocol ChargeGuardHelperXPC {
    func send(_ request: Data, withReply reply: @escaping (Data) -> Void)
    /// Registers the calling connection for pushed status and events.
    func subscribe(withReply reply: @escaping (Bool) -> Void)
}

/// The client's exported interface, used by the daemon to push updates.
@objc public protocol ChargeGuardClientXPC {
    func statusDidChange(_ status: Data)
    func eventsOccurred(_ events: Data)
}

/// Resumes a continuation exactly once (reply, error handler or timeout, whichever comes first).
final class ResumeOnce<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}

/// XPC connection to the root helper (Mach service com.amir.chargeguard.helper).
public final class XPCHelperClient: NSObject, HelperTransport, ChargeGuardClientXPC {
    public var onStatus: ((DaemonStatus) -> Void)?
    public var onEvents: (([EventRecord]) -> Void)?
    public var onConnectionChange: ((Bool) -> Void)?

    private let serviceName: String
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var subscribed = false

    public init(serviceName: String = HelperProtocol.machServiceName, timeout: TimeInterval = 15) {
        self.serviceName = serviceName
        self.timeout = timeout
        super.init()
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        let c = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: ChargeGuardHelperXPC.self)
        c.exportedInterface = NSXPCInterface(with: ChargeGuardClientXPC.self)
        c.exportedObject = self
        c.invalidationHandler = { [weak self] in self?.connectionEnded() }
        c.interruptionHandler = { [weak self] in self?.connectionEnded() }
        c.resume()
        connection = c
        subscribed = false
        return c
    }

    private func connectionEnded() {
        lock.lock()
        connection = nil
        subscribed = false
        lock.unlock()
        onConnectionChange?(false)
    }

    /// Opens the connection and subscribes to pushed updates.
    public func connect() {
        let c = currentConnection()
        lock.lock()
        let needsSubscribe = !subscribed
        subscribed = true
        lock.unlock()
        guard needsSubscribe else { return }
        let proxy = c.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.lock.lock()
            self?.subscribed = false
            self?.lock.unlock()
            self?.onConnectionChange?(false)
        } as? ChargeGuardHelperXPC
        proxy?.subscribe { [weak self] ok in
            self?.onConnectionChange?(ok)
        }
    }

    public func invalidate() {
        lock.lock()
        let c = connection
        connection = nil
        subscribed = false
        lock.unlock()
        c?.invalidate()
    }

    public func send(_ request: HelperRequest) async throws -> HelperResponse {
        let data = try MessageCodec.encode(request)
        let c = currentConnection()
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HelperResponse, Error>) in
            let once = ResumeOnce(continuation)
            let proxy = c.remoteObjectProxyWithErrorHandler { error in
                once.resume(with: .failure(error))
            } as? ChargeGuardHelperXPC
            guard let proxy else {
                once.resume(with: .failure(TransportError.notConnected))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(with: .failure(TransportError.timedOut))
            }
            proxy.send(data) { reply in
                once.resume(with: Result { try MessageCodec.decodeResponse(reply) })
            }
        }
    }

    /// Blocking variant for chargectl. Do not call on the main thread of an app.
    public func sendSync(_ request: HelperRequest) throws -> HelperResponse {
        let data = try MessageCodec.encode(request)
        let c = currentConnection()
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<HelperResponse, Error> = .failure(TransportError.timedOut)
        let proxy = c.remoteObjectProxyWithErrorHandler { error in
            result = .failure(error)
            semaphore.signal()
        } as? ChargeGuardHelperXPC
        guard let proxy else { throw TransportError.notConnected }
        proxy.send(data) { reply in
            result = Result { try MessageCodec.decodeResponse(reply) }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { throw TransportError.timedOut }
        return try result.get()
    }

    // MARK: ChargeGuardClientXPC

    public func statusDidChange(_ status: Data) {
        guard case .status(let decoded)? = try? MessageCodec.decodeResponse(status) else { return }
        onStatus?(decoded)
    }

    public func eventsOccurred(_ events: Data) {
        guard case .events(let decoded)? = try? MessageCodec.decodeResponse(events) else { return }
        onEvents?(decoded)
    }
}
