@testable import VSVibe
import XCTest

@MainActor
internal final class HookPromptTests: XCTestCase {
    private struct InstallError: LocalizedError {
        var errorDescription: String? { "disk full" }
    }

    private let suiteName = "vsvibe-hook-prompt-tests"
    private var defaults = UserDefaults.standard
    private let alias = LaunchAlias(command: "claude", claudeConfigDir: URL(fileURLWithPath: "/tmp/c"))

    private var installed: HookInstaller.Status {
        HookInstaller.Status(
            scriptInstalled: true,
            aliases: [HookInstaller.AliasStatus(alias: alias, registeredEvents: HookInstaller.installedEvents)]
        )
    }

    private var missing: HookInstaller.Status {
        HookInstaller.Status(
            scriptInstalled: false,
            aliases: [HookInstaller.AliasStatus(alias: alias, registeredEvents: [])]
        )
    }

    private var outdated: HookInstaller.Status {
        HookInstaller.Status(
            scriptInstalled: true,
            aliases: [HookInstaller.AliasStatus(alias: alias, registeredEvents: ["Stop", "Notification"])]
        )
    }

    override internal func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    override internal func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Decision

    internal func testReasonFollowsStatus() {
        XCTAssertNil(HookPromptDecision.reason(for: installed))
        XCTAssertEqual(HookPromptDecision.reason(for: missing), .missing)
        XCTAssertEqual(HookPromptDecision.reason(for: outdated), .outdated)
        let staleScript = HookInstaller.Status(scriptInstalled: true, aliases: installed.aliases, scriptOutdated: true)
        XCTAssertEqual(HookPromptDecision.reason(for: staleScript), .outdated)
        let noAliases = HookInstaller.Status(scriptInstalled: true, aliases: [])
        XCTAssertEqual(HookPromptDecision.reason(for: noAliases), .missing)
    }

    internal func testDontAskAgainHoldsOnlyForTheSameScriptVersion() {
        func prompt(_ status: HookInstaller.Status, dismissed: Int?) -> HookPromptDecision.Reason? {
            HookPromptDecision.prompt(status: status, dismissedScriptVersion: dismissed, currentScriptVersion: 3)
        }
        XCTAssertEqual(prompt(missing, dismissed: nil), .missing)
        XCTAssertNil(prompt(missing, dismissed: 3))
        XCTAssertEqual(prompt(outdated, dismissed: 2), .outdated)
        XCTAssertNil(HookPromptDecision.prompt(status: installed, dismissedScriptVersion: nil))
        XCTAssertEqual(HookPromptDecision.dismissedScriptVersionKey, "hookPromptDismissedScriptVersion")
    }

    // MARK: - Controller

    private func makeController(
        status: HookInstaller.Status,
        version: Int = 3,
        install: @escaping () throws -> Void = { /* Installs nothing. */ }
    ) -> HookPromptController {
        HookPromptController(defaults: defaults, scriptVersion: version, status: { status }, install: install)
    }

    internal func testPromptsOncePerLaunchAndInstalls() {
        var statusReads = 0
        var installs = 0
        let status = missing
        let controller = HookPromptController(
            defaults: defaults,
            scriptVersion: 3,
            status: {
                statusReads += 1
                return status
            },
            install: { installs += 1 }
        )
        XCTAssertFalse(controller.isVisible)
        controller.evaluateOnLaunch()
        XCTAssertEqual(controller.state, .prompting(.missing))
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.title, "Claude hooks aren't installed")
        XCTAssertTrue(controller.message.contains("session restore"))

        controller.installHooks()
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(controller.state, .installed)
        XCTAssertEqual(controller.title, "Claude hooks installed")
        XCTAssertTrue(controller.message.contains("Restart running Claude sessions"))

        controller.dismiss()
        controller.evaluateOnLaunch()
        XCTAssertEqual(statusReads, 1, "Evaluated only once per launch")
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(controller.title, "")
        XCTAssertEqual(controller.message, "")
    }

    internal func testOutdatedPromptAndNotNow() {
        let controller = makeController(status: outdated)
        controller.evaluateOnLaunch()
        XCTAssertEqual(controller.state, .prompting(.outdated))
        XCTAssertEqual(controller.title, "Claude hooks are outdated")
        XCTAssertTrue(controller.message.contains("newer hooks"))
        controller.dismiss()
        XCTAssertEqual(controller.state, .hidden)
        XCTAssertNil(defaults.object(forKey: HookPromptDecision.dismissedScriptVersionKey))
    }

    internal func testInstallFailureIsShown() {
        let controller = makeController(status: missing) { throw InstallError() }
        controller.evaluateOnLaunch()
        controller.installHooks()
        XCTAssertEqual(controller.state, .failed("disk full"))
        XCTAssertEqual(controller.title, "Couldn't install the Claude hooks")
        XCTAssertEqual(controller.message, "disk full")
    }

    internal func testDontAskAgainPersistsUntilTheScriptVersionChanges() {
        let first = makeController(status: missing)
        first.evaluateOnLaunch()
        first.dontAskAgain()
        XCTAssertFalse(first.isVisible)
        XCTAssertEqual(defaults.integer(forKey: HookPromptDecision.dismissedScriptVersionKey), 3)

        let nextLaunch = makeController(status: missing)
        nextLaunch.evaluateOnLaunch()
        XCTAssertFalse(nextLaunch.isVisible)

        let afterUpgrade = makeController(status: outdated, version: 4)
        afterUpgrade.evaluateOnLaunch()
        XCTAssertEqual(afterUpgrade.state, .prompting(.outdated))
    }

    internal func testInstalledHooksNeverPrompt() {
        let controller = makeController(status: installed)
        controller.evaluateOnLaunch()
        XCTAssertFalse(controller.isVisible)
    }

    deinit {
        // The defaults suite is removed in tearDown.
    }
}
