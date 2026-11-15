import Foundation

/// Display helpers for paths under the user's home directory.
internal enum HomePath {
    /// `path` with a leading `home` shown as `~` (`/Users/me/.x` → `~/.x`).
    internal static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home {
            return "~"
        }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
