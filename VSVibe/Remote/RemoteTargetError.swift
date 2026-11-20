/// Why a `RemoteTarget` cannot be turned into an `ssh` line. Every field ends
/// up typed into a shell, so anything that could break out of its quoting or
/// be read as an `ssh` option is rejected rather than escaped.
internal enum RemoteTargetError: Error, Equatable {
    case commandHasControlCharacters
    case destinationEmpty
    case destinationHasInvalidCharacters
    case destinationStartsWithDash
    case destinationTooLong
    case invalidClaudeSessionID
    case pathHasControlCharacters
    case portNotANumber
    case portOutOfRange

    /// A sentence for the project editor and the pane's error banner.
    internal var message: String {
        switch self {
        case .commandHasControlCharacters:
            "The command must be a single line."

        case .destinationEmpty:
            "Enter a host: an ~/.ssh/config Host, host or user@host."

        case .destinationHasInvalidCharacters:
            "The host may only contain letters, digits and . _ - @ : %."

        case .destinationStartsWithDash:
            "The host can't start with \"-\"."

        case .destinationTooLong:
            "The host is too long."

        case .invalidClaudeSessionID:
            "The Claude conversation id is not valid."

        case .pathHasControlCharacters:
            "The remote folder must be a single line."

        case .portNotANumber:
            "The port must be a number."

        case .portOutOfRange:
            "The port must be between 1 and 65535."
        }
    }
}
