import Foundation

/// The remote (SSH) fields of the project editor as typed, and their
/// conversion to a validated `RemoteTarget`. Keeps the editor view free of
/// parsing and validation.
internal struct RemoteProjectForm: Equatable {
    internal var destination = ""
    /// Port as typed; blank means ssh's default.
    internal var port = ""
    internal var remotePath = ""
    internal var command = LaunchCommandResolver.defaultCommand
    internal var runsClaude = true

    /// The target the fields describe, or the first problem with them.
    internal var target: Result<RemoteTarget, RemoteTargetError> {
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)
        var parsedPort: Int?
        if !trimmedPort.isEmpty {
            guard let value = Int(trimmedPort) else {
                return .failure(.portNotANumber)
            }
            parsedPort = value
        }
        let target = RemoteTarget(
            destination: destination.trimmingCharacters(in: .whitespaces),
            port: parsedPort,
            remotePath: remotePath.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespaces),
            runsClaude: runsClaude
        )
        if let error = SSHCommand.validationError(of: target) {
            return .failure(error)
        }
        return .success(target)
    }

    /// The problem to show under the fields; nil while the host is still
    /// blank (nothing typed yet) or when everything is valid.
    internal var visibleError: RemoteTargetError? {
        guard case .failure(let error) = target, error != .destinationEmpty else {
            return nil
        }
        return error
    }

    /// Whether "Runs Claude" applies: an empty command is a plain shell.
    internal var canRunClaude: Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Name suggested for a new project from the current fields.
    internal var suggestedName: String {
        RemoteTarget(
            destination: destination.trimmingCharacters(in: .whitespaces),
            remotePath: remotePath.trimmingCharacters(in: .whitespaces)
        )
        .defaultDisplayName
    }

    internal init() {
        // Blank host and folder, `claude`, runs Claude.
    }

    internal init(target: RemoteTarget) {
        destination = target.destination
        port = target.port.map(String.init) ?? ""
        remotePath = target.remotePath
        command = target.command
        runsClaude = target.runsClaude
    }
}
