import Foundation

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

        var timedOut = false
        let timer = DispatchWorkItem {
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        var errData = Data()
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()
        timer.cancel()
        if timedOut { throw ProcessRunnerError.timedOut(path) }
        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
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
