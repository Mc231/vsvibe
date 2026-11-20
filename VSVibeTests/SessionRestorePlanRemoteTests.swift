@testable import VSVibe
import XCTest

/// Restore of remote panes: their saved conversation id is resumed by the pane
/// itself, without transcript checks (the transcript is on the remote host);
/// a valid transcript path is carried along.
internal final class SessionRestorePlanRemoteTests: XCTestCase {
    private let claude = FolderEntry(remote: RemoteTarget(destination: "dev", command: "claudework"))
    private let plain = FolderEntry(remote: RemoteTarget(destination: "dev", command: "htop", runsClaude: false))
    private let shell = FolderEntry(remote: RemoteTarget(destination: "dev", command: ""))

    private func plan(_ panes: [PaneSnapshot]) -> SessionRestorePlan {
        SessionRestorePlan.make(
            snapshot: SessionSnapshot(panes: panes),
            folders: [claude, plain, shell],
            lookups: SessionRestorePlan.Lookups(
                aliasForCommand: { _ in nil },
                aliasForConfigDir: { _ in nil },
                fileExists: { _ in
                    XCTFail("remote transcripts are not checked locally")
                    return false
                }
            )
        )
    }

    internal func testSavedConversationIsResumed() {
        let pane = plan([
            PaneSnapshot(
                folderID: claude.id,
                claudeSessionID: "conv",
                transcriptPath: "/home/me/.claude/projects/p/conv.jsonl"
            )
        ])
        .panes.first

        XCTAssertEqual(pane?.command, "claudework")
        XCTAssertEqual(pane?.claudeSessionID, "conv")
        XCTAssertEqual(pane?.transcriptPath, "/home/me/.claude/projects/p/conv.jsonl")
        XCTAssertEqual(pane?.resolution, .resumedRemote)
    }

    internal func testInvalidTranscriptPathIsDropped() {
        let pane = plan([
            PaneSnapshot(folderID: claude.id, claudeSessionID: "conv", transcriptPath: "/home/me/elsewhere.jsonl")
        ])
        .panes.first

        XCTAssertEqual(pane?.claudeSessionID, "conv")
        XCTAssertNil(pane?.transcriptPath)
    }

    internal func testOtherPanesRunTheRemoteCommand() {
        let result = plan([
            PaneSnapshot(folderID: claude.id, claudeSessionID: nil),
            PaneSnapshot(folderID: claude.id, claudeSessionID: "bad id; rm"),
            PaneSnapshot(folderID: plain.id, claudeSessionID: "conv"),
            PaneSnapshot(folderID: shell.id, claudeSessionID: "conv")
        ])

        XCTAssertEqual(result.panes.map(\.command), ["claudework", "claudework", "htop", ""])
        XCTAssertEqual(result.panes.map(\.claudeSessionID), [nil, nil, nil, nil])
        XCTAssertEqual(result.panes.map(\.resolution), Array(repeating: .launchCommand, count: 4))
    }

    deinit {
        // Stateless tests.
    }
}
