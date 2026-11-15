/// Whether VSVibe asks, on launch, to install or update the Claude hooks.
internal enum HookPromptDecision {
    internal enum Reason: Equatable {
        /// The script or some alias's hooks are not installed at all.
        case missing
        /// Installed by an older VSVibe (`HookInstaller.Status.needsUpdate`).
        case outdated
    }

    /// UserDefaults key holding the `HookScript.version` for which the user
    /// chose "Don't ask again". A newer script version asks again.
    internal static let dismissedScriptVersionKey = "hookPromptDismissedScriptVersion"

    /// Why the hooks need attention, or nil when every hook-capable alias and
    /// the script are installed and current.
    internal static func reason(for status: HookInstaller.Status) -> Reason? {
        guard !status.isFullyInstalled else {
            return nil
        }
        return status.needsUpdate ? .outdated : .missing
    }

    /// The reason to prompt, unless the user opted out for this script version.
    internal static func prompt(
        status: HookInstaller.Status,
        dismissedScriptVersion: Int?,
        currentScriptVersion: Int = HookScript.version
    ) -> Reason? {
        guard dismissedScriptVersion != currentScriptVersion else {
            return nil
        }
        return reason(for: status)
    }
}
