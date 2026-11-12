@testable import VSVibe
import XCTest

@MainActor
internal final class EditorRegistryTests: XCTestCase {
    private enum LaunchError: Error {
        case refused
    }

    private let appURL = URL(fileURLWithPath: "/Applications/Fake.app")
    private let folder = URL(fileURLWithPath: "/tmp/project")

    internal func testRegistryIdsAreUniqueAndEditorsWellFormed() {
        let ids = EditorRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for editor in EditorRegistry.all {
            XCTAssertFalse(editor.displayName.isEmpty, editor.id)
            XCTAssertFalse(editor.bundleIdentifiers.isEmpty, editor.id)
            XCTAssertFalse(editor.iconSystemName.isEmpty, editor.id)
            // A shortcut key always comes with modifiers.
            XCTAssertEqual(editor.shortcutKey == nil, editor.shortcutModifiers.isEmpty, editor.id)
        }
    }

    internal func testAvailableEditorsUsesLookup() {
        let installed: Set<String> = ["com.apple.dt.Xcode", "dev.zed.Zed-Preview"]
        let editors = EditorRegistry.availableEditors { bundleIdentifier in
            installed.contains(bundleIdentifier) ? self.appURL : nil
        }
        XCTAssertEqual(editors.map(\.id), ["xcode", "zed"])
        XCTAssertTrue(EditorRegistry.availableEditors { _ in nil }.isEmpty)
    }

    internal func testResolvedAppURLPrefersFirstInstalledBundleIdentifier() throws {
        let editor = try XCTUnwrap(EditorRegistry.all.first { $0.id == "vscode" })
        let insiders = URL(fileURLWithPath: "/Applications/Insiders.app")
        let stable = URL(fileURLWithPath: "/Applications/Stable.app")
        var asked: [String] = []
        let resolved = editor.resolvedAppURL { bundleIdentifier in
            asked.append(bundleIdentifier)
            return bundleIdentifier == "com.microsoft.VSCode" ? stable : insiders
        }
        XCTAssertEqual(resolved, stable)
        XCTAssertEqual(asked, ["com.microsoft.VSCode"])

        let fallback = editor.resolvedAppURL { $0 == "com.microsoft.VSCodeInsiders" ? insiders : nil }
        XCTAssertEqual(fallback, insiders)
        XCTAssertNil(editor.resolvedAppURL { _ in nil })
        XCTAssertTrue(editor.isInstalled { _ in stable })
        XCTAssertFalse(editor.isInstalled { _ in nil })
    }

    internal func testEqualityAndHashUseIdOnly() {
        let first = makeEditor(id: "same", name: "One")
        let second = makeEditor(id: "same", name: "Two")
        let other = makeEditor(id: "other", name: "One")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(Set([first, second, other]).count, 2)
    }

    internal func testWorkspaceLookupMissesUnknownBundle() {
        let editor = makeEditor(id: "ghost", name: "Ghost", bundle: "invalid.vsvibe.tests.no-such-app")
        XCTAssertNil(ExternalEditor.workspaceLookup("invalid.vsvibe.tests.no-such-app"))
        XCTAssertNil(editor.resolvedAppURL())
        XCTAssertFalse(editor.isInstalled())
    }

    internal func testOpenLaunchesResolvedApp() {
        let editor = makeEditor(id: "fake", name: "Fake")
        var launches: [(folder: URL, app: URL)] = []
        EditorRegistry.open(
            folder: folder,
            with: editor,
            lookup: { _ in self.appURL },
            launcher: { folder, app, completion in
                launches.append((folder, app))
                completion(nil)
            }
        )
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.folder, folder)
        XCTAssertEqual(launches.first?.app, appURL)
    }

    internal func testOpenReportsLaunchFailureThroughCompletion() {
        let editor = makeEditor(id: "fake", name: "Fake")
        var completed = false
        EditorRegistry.open(
            folder: folder,
            with: editor,
            lookup: { _ in self.appURL },
            launcher: { _, _, completion in
                completion(LaunchError.refused)
                completed = true
            }
        )
        XCTAssertTrue(completed)
    }

    internal func testOpenSkipsLaunchWhenEditorNotInstalled() {
        let editor = makeEditor(id: "fake", name: "Fake")
        var launched = false
        EditorRegistry.open(
            folder: folder,
            with: editor,
            lookup: { _ in nil },
            launcher: { _, _, _ in launched = true }
        )
        XCTAssertFalse(launched)
    }

    internal func testWorkspaceLauncherReportsErrorForMissingApp() async {
        let missingApp = URL(fileURLWithPath: "/nonexistent-vsvibe-tests/Missing-\(UUID().uuidString).app")
        let finished = expectation(description: "workspace launcher completes")
        EditorRegistry.workspaceLauncher(FileManager.default.temporaryDirectory, missingApp) { error in
            XCTAssertNotNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
    }

    private func makeEditor(id: String, name: String, bundle: String = "com.example.fake") -> ExternalEditor {
        ExternalEditor(
            id: id,
            displayName: name,
            bundleIdentifiers: [bundle],
            iconSystemName: "star",
            shortcutKey: nil,
            shortcutModifiers: []
        )
    }

    deinit {
        // No shared state to release.
    }
}
