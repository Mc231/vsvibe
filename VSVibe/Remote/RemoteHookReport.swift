/// The outcome of a remote hook check or install, for the project editor.
internal struct RemoteHookReport: Equatable {
    internal let state: RemoteHookState
    /// The remote Claude config dir whose `settings.json` holds the hooks;
    /// nil when it could not be determined.
    internal let configDir: String?

    /// One line describing the state.
    internal var statusText: String {
        switch state {
        case .installed:
            "Hooks installed and up to date\(inConfigDir)."

        case .outdated:
            "Hooks are outdated or incomplete\(inConfigDir)."

        case .missing:
            "Hooks are not installed\(inConfigDir)."

        case .unreachable(let message):
            "Can't reach the host without a prompt: \(message)"

        case .failed(let message):
            "Hook setup failed: \(message)"
        }
    }

    /// Whether the hooks still need installing or updating.
    internal var needsInstall: Bool {
        state != .installed
    }

    private var inConfigDir: String {
        configDir.map { " in \($0)" } ?? ""
    }

    internal init(state: RemoteHookState, configDir: String? = nil) {
        self.state = state
        self.configDir = configDir
    }
}
