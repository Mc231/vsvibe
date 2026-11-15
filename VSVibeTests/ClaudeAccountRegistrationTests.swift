@testable import VSVibe
import XCTest

/// Unregistered launch commands, registering a shell alias's Claude account,
/// and the config-dir state shown in the hook status.
@MainActor
internal final class ClaudeAccountRegistrationTests: XCTestCase {
    private var directory = TestSupport.placeholderURL

    private var scriptURL: URL { directory.appendingPathComponent("hooks/claude-notify.sh") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("accounts")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func makeStore() -> LaunchAliasStore {
        LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
    }

    // MARK: - Candidates

    internal func testCandidatesSkipRegisteredBuiltInNonClaudeAndInvalidCommands() throws {
        let store = makeStore()
        try store.save(command: "work", configPath: "/tmp/work")
        let aliases = store.aliases
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "claude --continue", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "work", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "codex", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "zsh", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "  ", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "~/bin/claude", aliases: aliases))
        XCTAssertNil(UnregisteredClaudeCommand.candidate(forLaunchCommand: "X=1 claude", aliases: aliases))
        XCTAssertEqual(
            UnregisteredClaudeCommand.candidate(forLaunchCommand: " claudework -c", aliases: aliases),
            "claudework"
        )
        XCTAssertEqual(
            UnregisteredClaudeCommand.candidates(
                forLaunchCommands: ["cx", "claude", "cy --continue", "cx -c", "opencode", "work"],
                aliases: aliases
            ),
            ["cx", "cy"]
        )
    }

    internal func testDisplayConfigDirAbbreviatesHome() {
        let home = "/Users/me"
        func display(_ path: String?) -> String? {
            UnregisteredClaudeCommand(command: "c", configDir: path.map { URL(fileURLWithPath: $0) })
                .displayConfigDir(home: home)
        }
        XCTAssertEqual(display("/Users/me/.claude-x"), "~/.claude-x")
        XCTAssertEqual(display("/Users/me"), "~")
        XCTAssertEqual(display("/Users/meow/x"), "/Users/meow/x")
        XCTAssertNil(display(nil))
        XCTAssertEqual(UnregisteredClaudeCommand(command: "c", configDir: nil).id, "c")
    }

    // MARK: - Register

    internal func testRegisterSavesAliasAndInstallsHooksIntoMissingConfigDir() throws {
        let store = makeStore()
        let configDir = directory.appendingPathComponent("claude-work-2", isDirectory: true)
        XCTAssertEqual(ClaudeConfigDirState.of(configDir), .missing)

        let alias = try ClaudeAccountRegistrar.register(
            command: "claudework",
            configDir: configDir,
            in: store,
            scriptURL: scriptURL
        )

        XCTAssertEqual(alias.command, "claudework")
        XCTAssertEqual(store.alias(for: "claudework --continue"), alias)
        XCTAssertTrue(HookInstaller.isScriptCurrent(at: scriptURL))
        // The dir and settings.json are created; Claude Code reads that file on first run.
        let settings = try XCTUnwrap(alias.settingsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))
        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)
        XCTAssertTrue(status.isFullyInstalled)
        XCTAssertEqual(status.aliases.first?.configDirState, .notSetUp)
    }

    internal func testRegisterRejectsInvalidOrDuplicateCommands() throws {
        let store = makeStore()
        let dir = directory.appendingPathComponent("c")
        let script = scriptURL
        func register(_ command: String) throws {
            try ClaudeAccountRegistrar.register(command: command, configDir: dir, in: store, scriptURL: script)
        }
        XCTAssertThrowsError(try register("a b"))
        XCTAssertThrowsError(try register("claude"))
        try register("cw")
        XCTAssertThrowsError(try register("cw"))
        XCTAssertEqual(store.customAliases.map(\.command), ["cw"])
    }

    // MARK: - Config dir state

    internal func testConfigDirStates() throws {
        let dir = directory.appendingPathComponent("cfg", isDirectory: true)
        XCTAssertEqual(ClaudeConfigDirState.of(dir), .missing)
        TestSupport.write("file", to: directory.appendingPathComponent("plain"))
        XCTAssertEqual(ClaudeConfigDirState.of(directory.appendingPathComponent("plain")), .missing)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(ClaudeConfigDirState.of(dir), .notSetUp)
        TestSupport.write("{}", to: dir.appendingPathComponent("settings.json"))
        TestSupport.write("{}", to: dir.appendingPathComponent("settings.json.vsvibe.bak"))
        XCTAssertEqual(ClaudeConfigDirState.of(dir), .notSetUp)
        TestSupport.write("{}", to: dir.appendingPathComponent(".claude.json"))
        XCTAssertEqual(ClaudeConfigDirState.of(dir), .ready)
    }

    internal func testNoticeAndDetection() async {
        let found = UnregisteredClaudeCommand(command: "cw", configDir: URL(fileURLWithPath: "/Users/me/.cw"))
        XCTAssertEqual(found.notice(home: "/Users/me"), "`cw` uses Claude account `~/.cw`, not registered in VSVibe.")
        XCTAssertNil(UnregisteredClaudeCommand(command: "cw", configDir: nil).notice(home: "/Users/me"))

        let output = "__VSVIBE_BEGIN__\ncw='CLAUDE_CONFIG_DIR=/opt/cw claude'\n__VSVIBE_END__\n"
        let resolver = ShellAliasResolver { _, _ in output }
        let detected = await UnregisteredClaudeCommand.detect("cw", resolver: resolver, shell: "/bin/zsh")
        XCTAssertEqual(detected.command, "cw")
        XCTAssertEqual(detected.configDir?.path, "/opt/cw")
        let failing = ShellAliasResolver { _, _ in nil }
        let none = await UnregisteredClaudeCommand.detect("cw", resolver: failing, shell: "/bin/zsh")
        XCTAssertNil(none.configDir)
    }

    internal func testHomePathAbbreviation() {
        XCTAssertEqual(HomePath.abbreviate("/Users/me/.x", home: "/Users/me"), "~/.x")
        XCTAssertEqual(HomePath.abbreviate("/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(HomePath.abbreviate("/Users/meow", home: "/Users/me"), "/Users/meow")
        XCTAssertEqual(HomePath.abbreviate(NSHomeDirectory() + "/a"), "~/a")
    }

    internal func testAliasStatusTexts() {
        let alias = LaunchAlias(command: "cw", claudeConfigDir: URL(fileURLWithPath: "/Users/me/.cw"))
        let full = HookInstaller.AliasStatus(alias: alias, registeredEvents: HookInstaller.installedEvents)
        XCTAssertEqual(full.summary, "SessionStart + Stop + Notification registered")
        XCTAssertNil(full.setupHint(home: "/Users/me"))
        let none = HookInstaller.AliasStatus(alias: alias, registeredEvents: [], configDirState: .missing)
        XCTAssertEqual(none.summary, "Not registered")
        XCTAssertEqual(
            none.setupHint(home: "/Users/me"),
            "~/.cw doesn't exist yet: run `cw` once in a terminal and log in. "
                + "Installing the hooks creates it with a settings.json Claude Code will read."
        )
        let partial = HookInstaller.AliasStatus(alias: alias, registeredEvents: ["Stop"], configDirState: .notSetUp)
        XCTAssertEqual(partial.summary, "Partial: Stop")
        XCTAssertEqual(
            partial.setupHint(home: "/Users/me"),
            "Claude Code hasn't used ~/.cw yet: run `cw` once in a terminal and log in."
        )
        let noConfig = HookInstaller.AliasStatus(
            alias: LaunchAlias(command: "x", claudeConfigDir: nil),
            registeredEvents: [],
            configDirState: .missing
        )
        XCTAssertEqual(noConfig.setupHint(home: "/Users/me")?.hasPrefix("(no config)"), true)
    }

    internal func testStatusReportsMissingConfigDirWithoutCreatingIt() {
        let dir = directory.appendingPathComponent("never-run", isDirectory: true)
        let alias = LaunchAlias(command: "nr", claudeConfigDir: dir)
        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)
        XCTAssertEqual(status.aliases.first?.configDirState, .missing)
        XCTAssertFalse(status.aliases.first?.isInstalled ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    deinit {
        // The temp dir is removed in tearDown.
    }
}
