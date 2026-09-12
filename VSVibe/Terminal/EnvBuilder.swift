import Foundation

enum EnvBuilder {
    /// PATH entries the spawned shell starts with: well-known tool dirs
    /// prepended to the inherited PATH, deduplicated in order.
    static func searchPaths(extraPaths: [String] = []) -> [String] {
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
        for p in prepend + existingParts {
            if !p.isEmpty && seen.insert(p).inserted {
                combined.append(p)
            }
        }
        return combined
    }

    static func build(extraPaths: [String] = []) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths(extraPaths: extraPaths).joined(separator: ":")

        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["COLORTERM"] = "truecolor"
        env["VSVIBE"] = "1"

        return env.map { "\($0.key)=\($0.value)" }
    }
}
