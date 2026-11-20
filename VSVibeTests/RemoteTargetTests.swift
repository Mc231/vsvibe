@testable import VSVibe
import XCTest

/// `RemoteTarget`, the editor helpers built on it (`RemoteProjectForm`,
/// `ProjectDraft`, `ProjectLocation`) and remote `FolderEntry`s.
internal final class RemoteTargetTests: XCTestCase {
    // MARK: - RemoteTarget

    internal func testDerivedValues() {
        let target = RemoteTarget(destination: "me@dev.example", remotePath: "~/src/app/")
        XCTAssertEqual(target.host, "dev.example")
        XCTAssertEqual(target.location, "me@dev.example:~/src/app/")
        XCTAssertEqual(target.defaultDisplayName, "app (dev.example)")
        XCTAssertTrue(target.launchesClaude)

        let home = RemoteTarget(destination: "dev", remotePath: "~", command: "", runsClaude: true)
        XCTAssertEqual(home.defaultDisplayName, "dev")
        XCTAssertEqual(RemoteTarget(destination: "dev").location, "dev")
        XCTAssertFalse(home.launchesClaude, "an empty command is a shell")
        XCTAssertFalse(RemoteTarget(destination: "dev", runsClaude: false).launchesClaude)
    }

    internal func testDecodingFillsDefaults() throws {
        let decoded = try JSONDecoder().decode(RemoteTarget.self, from: Data(#"{"destination":"dev"}"#.utf8))
        XCTAssertEqual(decoded, RemoteTarget(destination: "dev"))
    }

    internal func testRoundTrip() throws {
        let target = RemoteTarget(destination: "dev", port: 222, remotePath: "/srv", command: "", runsClaude: false)
        let decoded = try JSONDecoder().decode(RemoteTarget.self, from: JSONEncoder().encode(target))
        XCTAssertEqual(decoded, target)
    }

    // MARK: - FolderEntry

    internal func testRemoteEntryUsesASyntheticIdentity() {
        let id = UUID()
        let entry = FolderEntry(remote: RemoteTarget(destination: "dev", remotePath: "/srv/api"), id: id)
        XCTAssertEqual(entry.url.path, "/.vsvibe-remote/\(id.uuidString)")
        XCTAssertEqual(entry.displayName, "api (dev)")
        XCTAssertEqual(entry.launchCommand, "ssh")
        XCTAssertEqual(entry.primaryCommand, "claude")
        XCTAssertEqual(entry.locationDescription, "dev:/srv/api")
        XCTAssertTrue(entry.isRemote)
        XCTAssertEqual(entry.location, .remote(RemoteTarget(destination: "dev", remotePath: "/srv/api")))
    }

    internal func testLocalEntryHelpers() {
        let entry = FolderEntry(url: URL(fileURLWithPath: "/p/app"), launchCommand: "codex")
        XCTAssertFalse(entry.isRemote)
        XCTAssertEqual(entry.locationDescription, "/p/app")
        XCTAssertEqual(entry.primaryCommand, "codex")
        XCTAssertEqual(entry.location, .local(folder: URL(fileURLWithPath: "/p/app"), launchCommand: "codex"))
    }

    internal func testOldStateDecodesAsLocal() throws {
        let json = #"{"id":"\#(UUID().uuidString)","url":"file:///p/app/","displayName":"App","addedAt":0}"#
        let entry = try JSONDecoder().decode(FolderEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.remote)
    }

    internal func testRemoteEntryRoundTrip() throws {
        let entry = FolderEntry(remote: RemoteTarget(destination: "dev", port: 22), displayName: "Box")
        let decoded = try JSONDecoder().decode(FolderEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)
    }

    internal func testLaunchesDifferently() {
        let local = FolderEntry(url: URL(fileURLWithPath: "/p/app"), launchCommand: "claude")
        var renamed = local
        renamed.displayName = "Other"
        XCTAssertFalse(local.launchesDifferently(than: renamed))
        var recommanded = local
        recommanded.launchCommand = " codex "
        XCTAssertTrue(local.launchesDifferently(than: recommanded))
        var moved = local
        moved.url = URL(fileURLWithPath: "/p/other")
        XCTAssertTrue(local.launchesDifferently(than: moved))
        var remote = local
        remote.remote = RemoteTarget(destination: "dev")
        XCTAssertTrue(local.launchesDifferently(than: remote))
    }

    // MARK: - ProjectLocation

    internal func testLocationAccessors() {
        let folder = URL(fileURLWithPath: "/p/app")
        let local = ProjectLocation.local(folder: folder, launchCommand: "codex")
        XCTAssertEqual(local.launchCommand, "codex")
        XCTAssertEqual(local.localFolder, folder)
        XCTAssertNil(local.remote)
        let remote = ProjectLocation.remote(RemoteTarget(destination: "dev"))
        XCTAssertEqual(remote.launchCommand, "ssh")
        XCTAssertNil(remote.localFolder)
        XCTAssertEqual(remote.remote, RemoteTarget(destination: "dev"))
    }

    // MARK: - RemoteProjectForm

    internal func testFormBuildsATrimmedTarget() {
        var form = RemoteProjectForm()
        form.destination = " me@dev "
        form.port = " 222 "
        form.remotePath = " ~/app "
        form.command = " claudework "
        XCTAssertEqual(
            form.target,
            .success(RemoteTarget(destination: "me@dev", port: 222, remotePath: "~/app", command: "claudework"))
        )
        XCTAssertNil(form.visibleError)
        XCTAssertEqual(form.suggestedName, "app (dev)")
        XCTAssertEqual(RemoteProjectForm(target: RemoteTarget(destination: "me@dev", port: 222)).port, "222")
    }

    internal func testFormErrors() {
        var form = RemoteProjectForm()
        XCTAssertEqual(form.target, .failure(.destinationEmpty))
        XCTAssertNil(form.visibleError, "a blank host is not shown as an error")
        form.destination = "-oProxyCommand=x"
        XCTAssertEqual(form.visibleError, .destinationStartsWithDash)
        form.destination = "dev"
        form.port = "ssh"
        XCTAssertEqual(form.visibleError, .portNotANumber)
        form.port = "0"
        XCTAssertEqual(form.visibleError, .portOutOfRange)
        form.port = ""
        XCTAssertNil(form.visibleError)
    }

    internal func testRunsClaudeNeedsACommand() {
        var form = RemoteProjectForm()
        XCTAssertTrue(form.canRunClaude)
        form.command = " "
        XCTAssertFalse(form.canRunClaude)
    }

    // MARK: - ProjectDraft

    internal func testLocalDraft() {
        var draft = ProjectDraft(creatingAt: URL(fileURLWithPath: "/p/app"))
        XCTAssertEqual(draft.effectiveName, "app")
        XCTAssertEqual(draft.subtitle, "/p/app")
        XCTAssertEqual(draft.location, .local(folder: URL(fileURLWithPath: "/p/app"), launchCommand: "claude"))
        XCTAssertTrue(draft.canSave)
        draft.launchCommand = " "
        XCTAssertNil(draft.location)
        XCTAssertFalse(draft.canSave)
    }

    internal func testRemoteDraftNamesItselfFromTheHost() {
        var draft = ProjectDraft()
        XCTAssertTrue(draft.isRemote)
        XCTAssertEqual(draft.subtitle, "Remote (SSH)")
        XCTAssertFalse(draft.canSave)
        draft.remote.destination = "dev"
        draft.remote.remotePath = "/srv/api"
        XCTAssertEqual(draft.subtitle, "ssh dev")
        XCTAssertEqual(draft.effectiveName, "api (dev)")
        XCTAssertEqual(draft.location, .remote(RemoteTarget(destination: "dev", remotePath: "/srv/api")))
        XCTAssertTrue(draft.canSave)
        draft.name = " Mine "
        XCTAssertEqual(draft.effectiveName, "Mine")
    }

    internal func testSwitchingARemoteDraftToLocalNeedsAFolder() {
        var draft = ProjectDraft(editing: FolderEntry(remote: RemoteTarget(destination: "dev"), displayName: "Box"))
        XCTAssertEqual(draft.name, "Box")
        XCTAssertEqual(draft.remote.destination, "dev")
        draft.isRemote = false
        XCTAssertEqual(draft.subtitle, "Choose a folder")
        XCTAssertNil(draft.location)
        draft.localFolder = URL(fileURLWithPath: "/p/box")
        XCTAssertEqual(draft.location, .local(folder: URL(fileURLWithPath: "/p/box"), launchCommand: "claude"))
    }

    internal func testEditingALocalProject() {
        let folder = FolderEntry(url: URL(fileURLWithPath: "/p/app"), displayName: "App", launchCommand: "codex")
        let draft = ProjectDraft(editing: folder)
        XCTAssertFalse(draft.isRemote)
        XCTAssertEqual(draft.location, folder.location)
    }

    deinit {
        // Nothing to release.
    }
}
