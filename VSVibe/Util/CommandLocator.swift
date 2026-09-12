import Foundation

/// Checks whether a launch command's executable exists. The fast check walks an
/// explicit PATH list (the same one `EnvBuilder` hands the spawned shell); the
/// slow check asks the user's login shell, which also sees rc-managed paths
/// (nvm, asdf, …) the app itself doesn't inherit.
enum CommandLocator {
    /// Absolute path of `command` resolved against `searchPaths`, or nil when
    /// not found. `command` must be a bare executable token (no arguments) —
    /// strip flags with `LaunchCommandResolver.baseCommand(of:)` first.
    static func resolveExecutable(_ command: String,
                                  searchPaths: [String],
                                  fileManager: FileManager = .default) -> String? {
        guard !command.isEmpty else { return nil }
        if command.contains("/") {
            let path = (command as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? path : nil
        }
        for dir in searchPaths where !dir.isEmpty {
            let candidate = dir.hasSuffix("/") ? dir + command : dir + "/" + command
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Authoritative check via the user's login shell
    /// (`<shell> -l -c "command -v <command>"`). Runs the shell's rc files, so
    /// it is slow — only call off the main thread, in response to a user
    /// action, and only after `resolveExecutable` came up empty.
    static func loginShellCanFind(_ command: String, shell: String) -> Bool {
        guard !command.isEmpty, !command.contains("'") else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v '\(command)' >/dev/null 2>&1"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
