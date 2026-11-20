import Foundation

/// Where the VSVibe hooks live on a remote host, and the POSIX sh scripts that
/// read and write them there. Every path is absolute, free of control
/// characters and single-quoted (`SSHCommand.shellQuoted`) in the scripts.
internal struct RemoteHookLayout: Equatable {
    /// Exit status of `readScript(_:)` when the file does not exist.
    internal static let missingFileStatus: Int32 = 3

    private static let unquotedCommandCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-"
    )

    /// The remote `$HOME`.
    internal let home: String
    /// The remote Claude config dir holding `settings.json`.
    internal let configDir: String

    internal var hooksDirectory: String {
        Self.join(home, ".vsvibe/hooks")
    }

    internal var scriptPath: String {
        Self.join(hooksDirectory, "claude-notify.sh")
    }

    internal var settingsPath: String {
        Self.join(configDir, "settings.json")
    }

    /// The previous `settings.json`, like the local installer's backup.
    internal var settingsBackupPath: String {
        settingsPath + ".vsvibe.bak"
    }

    /// How a hook command names the script: quoted only when it has to be.
    internal var scriptCommand: String {
        scriptPath.unicodeScalars.allSatisfy(Self.unquotedCommandCharacters.contains)
            ? scriptPath
            : SSHCommand.shellQuoted(scriptPath)
    }

    /// Writes stdin to the hook script and makes it executable.
    internal var writeScriptScript: String {
        let directory = SSHCommand.shellQuoted(hooksDirectory)
        let script = SSHCommand.shellQuoted(scriptPath)
        return "mkdir -p \(directory) && cat > \(script) && chmod 755 \(script)"
    }

    /// Backs up `settings.json` (when it exists), then replaces it with stdin
    /// through a temporary file.
    internal var writeSettingsScript: String {
        let directory = SSHCommand.shellQuoted(configDir)
        let settings = SSHCommand.shellQuoted(settingsPath)
        let backup = SSHCommand.shellQuoted(settingsBackupPath)
        let temporary = SSHCommand.shellQuoted(settingsPath + ".vsvibe.tmp")
        return "mkdir -p \(directory) && { [ ! -f \(settings) ] || cp -p \(settings) \(backup); } "
            + "&& cat > \(temporary) && mv -f \(temporary) \(settings)"
    }

    /// A layout for `home` and `configDir`; nil unless both are valid paths.
    internal init?(home: String, configDir: String) {
        guard Self.isValidPath(home), Self.isValidPath(configDir) else {
            return nil
        }
        self.home = home
        self.configDir = configDir
    }

    /// Prints the file at `path`, or exits with `missingFileStatus`.
    internal static func readScript(_ path: String) -> String {
        let file = SSHCommand.shellQuoted(path)
        return "if [ -f \(file) ]; then cat \(file); else exit \(missingFileStatus); fi"
    }

    /// An absolute path without control characters.
    internal static func isValidPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
