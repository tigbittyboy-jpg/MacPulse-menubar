import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum UsageClientError: Error, LocalizedError {
    case missingExecutable, timeout, rejected, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .missingExecutable: return "Choose an installed Codex CLI executable in Settings."
        case .timeout: return "Codex did not respond before the usage request timed out."
        case .rejected: return "Codex could not read usage. Check your CLI version and sign-in status; API-key accounts may not provide subscription allowances."
        case .invalidResponse: return "The installed Codex returned an unsupported usage response."
        }
    }
}
/// Explicit, read-only connection to the user's installed official CLI. Never accesses auth files.
public enum AppServerUsageClient {
    public static func read(executable: URL, timeout: Double = 20) async throws -> UsageReading {
        try await Task.detached(priority: .utility) { try readBlocking(executable: executable, timeout: timeout) }.value
    }
    private static func readBlocking(executable: URL, timeout: Double) throws -> UsageReading {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw UsageClientError.missingExecutable }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable; process.arguments = ["app-server"]
        process.standardInput = input; process.standardOutput = output
        // Avoid retaining unrelated diagnostic messages, prompts or credentials.
        process.standardError = FileHandle.nullDevice
        #if canImport(Darwin)
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        #endif
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 0.5) == .timedOut && process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, min(60, timeout))
        var buffer = Data()
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func receive(id: Int) throws -> [String: Any] {
            while ProcessInfo.processInfo.systemUptime < deadline {
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.subdata(in: 0..<newline); buffer.removeSubrange(0...newline)
                    guard let response = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], response["id"] as? Int == id else { continue }
                    guard response["error"] == nil else { throw UsageClientError.rejected }
                    guard let result = response["result"] as? [String: Any] else { throw UsageClientError.invalidResponse }
                    return result
                }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                let status = poll(&descriptor, 1, Int32(max(1, min(500, remaining * 1000))))
                if status < 0 { if errno == EINTR { continue }; throw UsageClientError.invalidResponse }
                if status == 0 { continue }
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = bytes.withUnsafeMutableBytes { raw in
                    #if canImport(Darwin)
                    return Darwin.read(descriptor.fd, raw.baseAddress, raw.count)
                    #else
                    return Glibc.read(descriptor.fd, raw.baseAddress, raw.count)
                    #endif
                }
                guard count > 0 else { throw UsageClientError.invalidResponse }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count < 1_048_576 else { throw UsageClientError.invalidResponse }
            }
            throw UsageClientError.timeout
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "macpulse", "title": "MacPulse", "version": "0.2.0"], "capabilities": ["experimentalApi": false]]])
        _ = try receive(id: 1)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
        let reading = UsageParser.parse(result: try receive(id: 2))
        guard !reading.windows.isEmpty else { throw UsageClientError.invalidResponse }
        return reading
    }
}
