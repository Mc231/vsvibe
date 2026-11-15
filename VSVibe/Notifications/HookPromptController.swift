import Foundation
import Observation

/// The launch-time banner asking to install or update the Claude hooks
/// (notifications and session restore need them). Evaluated once per launch
/// by `AppEnvironment.startEventStream()` (never in the unit-test host); the
/// decision is `HookPromptDecision`, the opt-out a UserDefaults entry.
@MainActor
@Observable
internal final class HookPromptController {
    internal enum State: Equatable {
        case failed(String)
        case hidden
        case installed
        case prompting(HookPromptDecision.Reason)
    }

    internal private(set) var state: State = .hidden

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let status: () -> HookInstaller.Status
    @ObservationIgnored private let install: () throws -> Void
    @ObservationIgnored private let scriptVersion: Int
    @ObservationIgnored private var hasEvaluated = false

    internal var isVisible: Bool { state != .hidden }

    /// Banner title for the current state.
    internal var title: String {
        switch state {
        case .prompting(.missing):
            "Claude hooks aren't installed"

        case .prompting(.outdated):
            "Claude hooks are outdated"

        case .installed:
            "Claude hooks installed"

        case .failed:
            "Couldn't install the Claude hooks"

        case .hidden:
            ""
        }
    }

    /// Banner text for the current state.
    internal var message: String {
        switch state {
        case .prompting(.missing):
            "Notifications and session restore need VSVibe's hooks in each Claude alias's settings."

        case .prompting(.outdated):
            "This VSVibe version needs newer hooks for notifications and session restore."

        case .installed:
            "Restart running Claude sessions so they pick up the hooks."

        case .failed(let reason):
            reason

        case .hidden:
            ""
        }
    }

    internal init(
        defaults: UserDefaults = .standard,
        scriptVersion: Int = HookScript.version,
        status: @escaping () -> HookInstaller.Status,
        install: @escaping () throws -> Void
    ) {
        self.defaults = defaults
        self.scriptVersion = scriptVersion
        self.status = status
        self.install = install
    }

    /// Shows the prompt if the hooks need attention. Only the first call does anything.
    internal func evaluateOnLaunch() {
        guard !hasEvaluated else {
            return
        }
        hasEvaluated = true
        let dismissed = defaults.object(forKey: HookPromptDecision.dismissedScriptVersionKey) as? Int
        if let reason = HookPromptDecision.prompt(
            status: status(),
            dismissedScriptVersion: dismissed,
            currentScriptVersion: scriptVersion
        ) {
            state = .prompting(reason)
        }
    }

    /// Install / Update Hooks: runs the installer, then reminds to restart sessions.
    internal func installHooks() {
        do {
            try install()
            state = .installed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Not Now: hides the banner for this launch.
    internal func dismiss() {
        state = .hidden
    }

    /// Don't Ask Again: hides it until the hook script version changes.
    internal func dontAskAgain() {
        defaults.set(scriptVersion, forKey: HookPromptDecision.dismissedScriptVersionKey)
        state = .hidden
    }

    deinit {
        // Value state only.
    }
}
