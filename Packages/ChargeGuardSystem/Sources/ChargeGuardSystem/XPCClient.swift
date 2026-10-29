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
    /// Set by `connect()`: the client wants pushed updates and re-subscribes after the helper restarts.
    private var wantsUpdates = false
    private var subscribed = false

    public init(serviceName: String = HelperProtocol.machServiceName, timeout: TimeInterval = 15) {
        self.serviceName = serviceName
        self.timeout = timeout
        super.init()
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let existing = connection { return existing }
        let c = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: ChargeGuardHelperXPC.self)
        c.exportedInterface = NSXPCInterface(with: ChargeGuardClientXPC.self)
        c.exportedObject = self
        let id = ObjectIdentifier(c)
        c.invalidationHandler = { [weak self] in self?.connectionEnded(id, interrupted: false) }
        c.interruptionHandler = { [weak self] in self?.connectionEnded(id, interrupted: true) }
        c.resume()
        connection = c
        subscribed = false
        return c
    }

    /// Only the end of the current connection matters; a late handler of an older connection is ignored.
    private func connectionEnded(_ id: ObjectIdentifier, interrupted: Bool) {
        lock.lock()
        var ended: NSXPCConnection?
        if let current = connection, ObjectIdentifier(current) == id {
            ended = current
            connection = nil
            subscribed = false
        }
        lock.unlock()
        guard let endedConnection = ended else { return }
        // The helper exited or restarted: drop this connection (it holds `self` as exported object);
        // the next request opens a new one.
        if interrupted { endedConnection.invalidate() }
        onConnectionChange?(false)
    }

    /// Opens the connection and subscribes to pushed updates.
    public func connect() {
        lock.lock()
        wantsUpdates = true
        lock.unlock()
        subscribeIfNeeded(currentConnection())
    }

    private func subscribeIfNeeded(_ c: NSXPCConnection) {
        lock.lock()
        let needed = wantsUpdates && !subscribed && connection === c
        if needed { subscribed = true }
        lock.unlock()
        guard needed else { return }
        let remote = c.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.subscriptionFailed()
        } as? ChargeGuardHelperXPC
        guard let helper = remote else {
            subscriptionFailed()
            return
        }
        helper.subscribe { [weak self] ok in
            if !ok { self?.subscriptionFailed() } else { self?.onConnectionChange?(true) }
        }
    }

    private func subscriptionFailed() {
        lock.lock()
        subscribed = false
        lock.unlock()
        onConnectionChange?(false)
    }

    public func invalidate() {
        lock.lock()
        let c = connection
        connection = nil
        subscribed = false
        wantsUpdates = false
        lock.unlock()
        c?.invalidate()
    }

    public func send(_ request: HelperRequest) async throws -> HelperResponse {
        let data = try MessageCodec.encode(request)
        let c = currentConnection()
        subscribeIfNeeded(c)
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HelperResponse, Error>) in
            let once = ResumeOnce(continuation)
            let remote = c.remoteObjectProxyWithErrorHandler { error in
                once.resume(with: .failure(error))
            } as? ChargeGuardHelperXPC
            guard let helper = remote else {
                once.resume(with: .failure(TransportError.notConnected))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(with: .failure(TransportError.timedOut))
            }
            helper.send(data) { reply in
                once.resume(with: Result { try MessageCodec.decodeResponse(reply) })
            }
        }
    }

    /// Blocking variant for chargectl. Do not call on the main thread of an app.
    /// Replies arrive on the connection's private queue, so blocking the CLI's main thread is fine.
    public func sendSync(_ request: HelperRequest) throws -> HelperResponse {
        let data = try MessageCodec.encode(request)
        let c = currentConnection()
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox<Result<HelperResponse, Error>>(.failure(TransportError.timedOut))
        let remote = c.remoteObjectProxyWithErrorHandler { error in
            result.value = .failure(error)
            semaphore.signal()
        } as? ChargeGuardHelperXPC
        guard let helper = remote else { throw TransportError.notConnected }
        helper.send(data) { reply in
            result.value = Result { try MessageCodec.decodeResponse(reply) }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { throw TransportError.timedOut }
        return try result.value.get()
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
