/// Result of asking the user's shell whether a command exists.
internal enum CommandAvailability: Equatable, Sendable {
    case found
    case missing
    /// The shell could not answer (timeout, no shell, unsafe name): don't warn.
    case unknown
}
