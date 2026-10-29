import Foundation

/// A lock-protected value shared with escaping closures (Dispatch, XPC reply blocks).
final class LockedBox<Value> {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var stdoutData: Data
}

public enum ProcessRunnerError: Error, CustomStringConvertible {
    case launchFailed(String, String)
    case timedOut(String)
    case failed(String, Int32, String)

    public var description: String {
        switch self {
        case .launchFailed(let path, let why): return "could not launch \(path): \(why)"
        case .timedOut(let path): return "\(path) timed out"
        case .failed(let path, let status, let stderr): return "\(path) exited with \(status): \(stderr)"
        }
    }
}

/// Runs a command with a timeout and captures its output. Output is read before waiting, so a
/// large output (powermetrics) cannot fill the pipe and deadlock.
public final class ProcessRunner {
    public init() {}

    public func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(path, "\(error)")
        }

        // Boxes instead of captured `var`s: Dispatch closures may be @Sendable, and mutating a captured
        // var there is an error.
        let timedOut = LockedBox(false)
        let timer = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.value = true
            process.terminate()
            // SIGKILL if SIGTERM is ignored, so a hung tool cannot block the caller (the control queue) forever.
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        let errData = LockedBox(Data())
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errData.value = err.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()
        timer.cancel()
        if timedOut.value { throw ProcessRunnerError.timedOut(path) }
        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData.value, as: UTF8.self),
                             stdoutData: outData)
    }

    /// Runs and throws unless the exit status is 0.
    @discardableResult
    public func check(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> ProcessResult {
        let result = try run(path, arguments, timeout: timeout)
        guard result.status == 0 else {
            throw ProcessRunnerError.failed(path, result.status, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}
