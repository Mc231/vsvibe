import Foundation

/// Registers a shell alias for a Claude account as a VSVibe alias and installs
/// the hooks into its config dir in one step (the "Register" buttons).
@MainActor
internal enum ClaudeAccountRegistrar {
    /// Saves `command` → `configDir` in `store`, then writes the hook script and
    /// registers the hooks in `<configDir>/settings.json` (creating the dir if
    /// needed, see `HookInstaller.installInto(alias:)`). Returns the new alias.
    @discardableResult
    internal static func register(
        command: String,
        configDir: URL,
        in store: LaunchAliasStore,
        scriptURL: URL = HookInstaller.hookScriptURL
    ) throws -> LaunchAlias {
        try store.save(command: command, configPath: configDir.path)
        guard let alias = store.alias(for: command) else {
            throw LaunchAliasStore.AliasError.missingAlias
        }
        try HookInstaller.install(aliases: [alias], scriptURL: scriptURL)
        return alias
    }
}
