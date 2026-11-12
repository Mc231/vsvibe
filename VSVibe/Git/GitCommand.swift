import Foundation
import Darwin

/// Synchronous worker-only runner. Files avoid stdout/stderr pipe deadlocks;
/// a deadline bounds stalled Git commands, and reads have a memory limit.
enum GitCommand {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let truncated: Bool
    }

    static func run(_ arguments: [String], in folder: URL,
                    outputLimit: Int = 16 * 1024 * 1024,
                    timeout: TimeInterval = 20,
                    executable: URL = URL(fileURLWithPath: "/usr/bin/git")) throws -> Output {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vsvibe-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_PAGER"] = "cat"
        process.environment = environment
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw GitInfo.GitError.failed("Git took too long. Try again with a smaller comparison.")
        }
        let reader = try FileHandle(forReadingFrom: outURL)
        let errorReader = try FileHandle(forReadingFrom: errURL)
        defer { try? reader.close(); try? errorReader.close() }
        let limit = max(0, outputLimit)
        let data = try reader.read(upToCount: limit + 1) ?? Data()
        let errorData = try errorReader.read(upToCount: 64 * 1024) ?? Data()
        return Output(exitCode: process.terminationStatus,
                      stdout: String(decoding: data.prefix(limit), as: UTF8.self),
                      stderr: String(decoding: errorData, as: UTF8.self),
                      truncated: data.count > limit)
    }
}
