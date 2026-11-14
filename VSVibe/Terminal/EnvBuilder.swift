import Foundation

internal enum EnvBuilder {
    /// Identifies the pane a shell (and the Claude hooks it runs) belongs to.
    internal static let paneIDKey = "VSVIBE_PANE_ID"

    /// PATH entries the spawned shell starts with: well-known tool dirs
    /// prepended to the inherited PATH, deduplicated in order.
    internal static func searchPaths(extraPaths: [String] = []) -> [String] {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let prepend = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin"
        ] + extraPaths

        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingParts = existing.split(separator: ":").map(String.init)
        var seen = Set<String>()
        var combined: [String] = []
        for path in prepend + existingParts {
            if !path.isEmpty && seen.insert(path).inserted {
                combined.append(path)
            }
        }
        return combined
    }

    /// The environment for a pane's shell. `paneID` is exported as
    /// `VSVIBE_PANE_ID` so hook events can be routed to that pane; without it
    /// any inherited value is removed.
    internal static func build(extraPaths: [String] = [], paneID: UUID? = nil) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths(extraPaths: extraPaths).joined(separator: ":")

        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["COLORTERM"] = "truecolor"
        env["VSVIBE"] = "1"
        env[paneIDKey] = paneID?.uuidString

        return env.map { "\($0.key)=\($0.value)" }
    }
}
