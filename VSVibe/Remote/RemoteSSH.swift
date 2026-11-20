import Foundation

/// Argument lists for VSVibe's own background ssh calls to a remote host
/// (hook install, git branch, event and transcript streams). Unlike a pane's
/// typed `ssh` line (`SSHCommand.line`) these run `/usr/bin/ssh` directly with
/// an argv array, never through a local shell:
///
///     ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=auto
///         -o ControlPath=~/.vsvibe/ssh/cm-%C -o ControlPersist=60
///         [-o ServerAliveInterval=15 -o ServerAliveCountMax=3] [-p PORT]
///         -- DEST 'exec /bin/sh -c <quoted remote script>'
///
/// `BatchMode` never prompts (a password or passphrase prompt would hang),
/// and every call to one host shares one multiplexed connection. The remote
/// login shell (whatever it is, e.g. fish) only execs `/bin/sh`, so remote
/// scripts are POSIX sh; every value in them is quoted with
/// `SSHCommand.shellQuoted` by its builder.
internal enum RemoteSSH {
    /// The ssh client run for every background call.
    internal static let executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    /// Where the multiplexing sockets live (created with mode 0700).
    internal static let controlDirectory = HookInstaller.appDir.appendingPathComponent("ssh", isDirectory: true)

    /// ssh expands the `~` itself, so a home path with spaces stays one option.
    private static let controlPath = "~/.vsvibe/ssh/cm-%C"
    private static let controlDirectoryPermissions: Int16 = 0o700
    private static let baseOptions = [
        "BatchMode=yes",
        "ConnectTimeout=10",
        "ControlMaster=auto",
        "ControlPath=\(controlPath)",
        "ControlPersist=60"
    ]
    private static let keepAliveOptions = ["ServerAliveInterval=15", "ServerAliveCountMax=3"]

    /// A one-shot call running `script` on the host.
    internal static func commandArguments(for connection: SSHConnection, script: String) -> [String] {
        arguments(for: connection, options: baseOptions, script: script)
    }

    /// A long-running stream (`tail -F`): also detects a dead connection.
    internal static func streamArguments(for connection: SSHConnection, script: String) -> [String] {
        arguments(for: connection, options: baseOptions + keepAliveOptions, script: script)
    }

    /// Creates `directory` (and its parents) and makes it private to the user,
    /// also tightening one that already exists.
    internal static func prepareControlDirectory(at directory: URL = controlDirectory) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: controlDirectoryPermissions]
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
    }

    private static func arguments(for connection: SSHConnection, options: [String], script: String) -> [String] {
        var arguments = options.flatMap { ["-o", $0] }
        if let port = connection.port {
            arguments += ["-p", String(port)]
        }
        return arguments + ["--", connection.destination, "exec /bin/sh -c " + SSHCommand.shellQuoted(script)]
    }
}
