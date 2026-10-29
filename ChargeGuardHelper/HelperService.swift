import Foundation
import ChargeGuardCore
import ChargeGuardSystem

/// XPC listener delegate. Validates every client, exports one endpoint per connection and pushes
/// status and events to subscribed clients.
final class HelperService: NSObject, NSXPCListenerDelegate {
    let controller: ChargeController
    let logger: CoreLogger
    let validator: ClientValidator

    private let lock = NSLock()
    private var subscribers: [ObjectIdentifier: NSXPCConnection] = [:]

    init(controller: ChargeController, logger: CoreLogger, validator: ClientValidator) {
        self.controller = controller
        self.logger = logger
        self.validator = validator
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard validator.validate(connection) else {
            logger.error(LogCategory.xpc, "rejected XPC client pid \(connection.processIdentifier)")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: ChargeGuardHelperXPC.self)
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeGuardClientXPC.self)
        connection.exportedObject = HelperEndpoint(service: self, connection: connection)
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in self?.removeSubscriber(id) }
        connection.interruptionHandler = { [weak self] in self?.removeSubscriber(id) }
        connection.resume()
        logger.info(LogCategory.xpc, "accepted XPC client pid \(connection.processIdentifier)")
        return true
    }

    func handle(_ data: Data, reply: @escaping (Data) -> Void) {
        let request: HelperRequest
        do {
            request = try MessageCodec.decodeRequest(data)
        } catch {
            logger.error(LogCategory.xpc, "bad request: \(error)")
            reply(MessageCodec.errorData("\(error)"))
            return
        }
        controller.handle(request) { response in
            do {
                reply(try MessageCodec.encode(response))
            } catch {
                reply(MessageCodec.errorData("could not encode the response: \(error)"))
            }
        }
    }

    func subscribe(_ connection: NSXPCConnection) {
        lock.lock()
        subscribers[ObjectIdentifier(connection)] = connection
        lock.unlock()
    }

    private func removeSubscriber(_ id: ObjectIdentifier) {
        lock.lock()
        subscribers[id] = nil
        lock.unlock()
    }

    private func currentSubscribers() -> [NSXPCConnection] {
        lock.lock(); defer { lock.unlock() }
        return Array(subscribers.values)
    }

    func broadcast(status: DaemonStatus) {
        guard let data = try? MessageCodec.encode(.status(status)) else { return }
        for connection in currentSubscribers() {
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? ChargeGuardClientXPC
            proxy?.statusDidChange(data)
        }
    }

    func broadcast(events: [EventRecord]) {
        guard !events.isEmpty, let data = try? MessageCodec.encode(.events(events)) else { return }
        for connection in currentSubscribers() {
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? ChargeGuardClientXPC
            proxy?.eventsOccurred(data)
        }
    }
}

/// The object exported to one client connection.
final class HelperEndpoint: NSObject, ChargeGuardHelperXPC {
    private weak var service: HelperService?
    private weak var connection: NSXPCConnection?

    init(service: HelperService, connection: NSXPCConnection) {
        self.service = service
        self.connection = connection
    }

    func send(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard let service else {
            reply(MessageCodec.errorData("helper is shutting down"))
            return
        }
        service.handle(request, reply: reply)
    }

    func subscribe(withReply reply: @escaping (Bool) -> Void) {
        guard let service, let connection else {
            reply(false)
            return
        }
        service.subscribe(connection)
        reply(true)
    }
}
