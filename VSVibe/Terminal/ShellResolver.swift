import Foundation
import Darwin

enum ShellResolver {
    static func userLoginShell() -> String {
        if let pw = getpwuid(getuid()), let shellPtr = pw.pointee.pw_shell {
            let path = String(cString: shellPtr)
            if !path.isEmpty {
                return path
            }
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return "/bin/zsh"
    }

    static func loginArgs(for shellPath: String) -> [String] {
        ["-l"]
    }
}
