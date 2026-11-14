import Foundation
import SwiftTerm

extension LocalProcessTerminalView {
    internal func spawnShell(at folder: URL, paneID: UUID) {
        let shell = ShellResolver.userLoginShell()
        let env = EnvBuilder.build(paneID: paneID)

        let escapedPath = folder.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedShell = shell.replacingOccurrences(of: "'", with: "'\\''")
        let script = "cd '\(escapedPath)' 2>/dev/null || cd \"$HOME\"; exec '\(escapedShell)' -l"

        startProcess(
            executable: "/bin/sh",
            args: ["-c", script],
            environment: env,
            execName: nil
        )
    }

    internal func injectCommand(_ command: String) {
        send(txt: "\(command)\n")
    }
}
