import Foundation

/// A bare command name that is safe to put into a shell script: letters,
/// digits, `.`, `_` and `-` only, not starting with `-`, and not `.` / `..`.
/// Launch commands come from user input, so every script VSVibe builds from one
/// validates the name here first and quotes it with `quoted(_:)`.
internal enum ShellCommandName {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
    )

    internal static func isValid(_ name: String) -> Bool {
        !name.isEmpty
            && name.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
            && !name.hasPrefix("-")
            && name != "."
            && name != ".."
    }

    /// `'name'` when `name` is valid, else nil. The allowed characters never
    /// need escaping, so the single quotes only guard against word splitting.
    internal static func quoted(_ name: String) -> String? {
        isValid(name) ? "'\(name)'" : nil
    }
}
