@testable import VSVibe
import XCTest

/// The project editor's remote hook section state, and the report wording.
@MainActor
internal final class RemoteHookSetupModelTests: XCTestCase {
    private let target = RemoteTarget(destination: "me@dev")

    private func model(probe: String) -> RemoteHookSetupModel {
        let runner = FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data(probe.utf8))
            }
            return RemoteCommandResult(status: script.hasPrefix("if [ -f") ? 3 : 0)
        }
        return RemoteHookSetupModel(installer: RemoteHookInstaller(runner: runner))
    }

    internal func testCheckThenInstall() async {
        let model = model(probe: "__VSVIBE_HOME__/home/me\n")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "")
        XCTAssertFalse(model.isBusy)

        await model.check(target)
        XCTAssertEqual(model.statusText, "Hooks are not installed in /home/me/.claude.")
        XCTAssertEqual(model.actionTitle(host: target.host), "Install Hooks on dev")
        XCTAssertFalse(model.isInstalled)

        await model.install(target)
        XCTAssertTrue(model.isInstalled)
        XCTAssertEqual(model.statusText, "Hooks installed and up to date in /home/me/.claude.")
        XCTAssertEqual(model.actionTitle(host: "dev"), "Reinstall Hooks on dev")

        model.reset()
        XCTAssertEqual(model.phase, .idle)
    }

    internal func testResultForAnEditedTargetIsDropped() async {
        let model = model(probe: "__VSVIBE_HOME__/home/me\n")
        let task = Task { await model.check(target) }
        XCTAssertEqual(model.phase, .idle)
        await Task.yield()
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.statusText, "Checking the hooks on the host…")
        model.reset()
        await task.value

        XCTAssertEqual(model.phase, .idle)
    }

    internal func testInstallingStatus() async {
        let model = model(probe: "__VSVIBE_HOME__/home/me\n")
        let task = Task { await model.install(target) }
        await Task.yield()
        XCTAssertEqual(model.statusText, "Installing the hooks on the host…")
        await task.value
    }

    internal func testReportTexts() {
        XCTAssertEqual(RemoteHookReport(state: .outdated).statusText, "Hooks are outdated or incomplete.")
        XCTAssertEqual(
            RemoteHookReport(state: .unreachable("Permission denied")).statusText,
            "Can't reach the host without a prompt: Permission denied"
        )
        XCTAssertEqual(RemoteHookReport(state: .failed("x")).statusText, "Hook setup failed: x")
        XCTAssertTrue(RemoteHookReport(state: .missing).needsInstall)
        XCTAssertFalse(RemoteHookReport(state: .installed).needsInstall)
        XCTAssertEqual(RemoteHookInstallerError.readFailed("a"), .readFailed("a"))
    }

    internal func testOutdatedOffersAnUpdate() async {
        let runner = FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data("__VSVIBE_HOME__/h\n".utf8))
            }
            return RemoteCommandResult(status: 0, output: Data((script.contains("settings.json") ? "{}" : "old").utf8))
        }
        let model = RemoteHookSetupModel(installer: RemoteHookInstaller(runner: runner))

        await model.check(target)

        XCTAssertEqual(model.actionTitle(host: "dev"), "Update Hooks on dev")
    }

    deinit {
        // Stateless tests.
    }
}
