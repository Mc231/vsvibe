import Darwin
import Foundation

internal enum ShellResolver {
    private static let fallbackShell = "/bin/zsh"

    /// The user's login shell: the passwd entry first, then `$SHELL`, then zsh.
    internal static func userLoginShell() -> String {
        resolveShell(passwdShell: passwdShell(), environment: ProcessInfo.processInfo.environment)
    }

    /// Pure resolution order behind `userLoginShell()`; empty values are skipped.
    internal static func resolveShell(passwdShell: String?, environment: [String: String]) -> String {
        if let passwdShell, !passwdShell.isEmpty {
            return passwdShell
        }
        if let envShell = environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return fallbackShell
    }

    internal static func loginArgs(for _: String) -> [String] {
        ["-l"]
    }

    private static func passwdShell() -> String? {
        guard let entry = getpwuid(getuid()), let shellPointer = entry.pointee.pw_shell else {
            return nil
        }
        return String(cString: shellPointer)
    }
}
