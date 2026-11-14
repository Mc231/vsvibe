@testable import VSVibe
import XCTest

internal final class SessionRestorePlanTests: XCTestCase {
    private let claude = FolderEntry(url: URL(fileURLWithPath: "/p/claude"), launchCommand: "claude --continue")
    private let codex = FolderEntry(url: URL(fileURLWithPath: "/p/codex"), launchCommand: "codex")
    private let shell = FolderEntry(url: URL(fileURLWithPath: "/p/shell"), launchCommand: "")
    private let wrapper = FolderEntry(url: URL(fileURLWithPath: "/p/wrapper"), launchCommand: "my-claude")

    private func plan(_ panes: [PaneSnapshot], focusedIndex: Int? = nil) -> SessionRestorePlan {
        SessionRestorePlan.make(
            snapshot: SessionSnapshot(panes: panes, focusedIndex: focusedIndex),
            folders: [claude, codex, shell, wrapper]
        ) { command in
            LaunchCommandResolver.alias(for: LaunchCommandResolver.baseCommand(of: command))
        }
    }

    internal func testKnownConversationResumesItsOwnSession() {
        let result = plan([
            PaneSnapshot(folderID: claude.id, claudeSessionID: "conv-a"),
            PaneSnapshot(folderID: claude.id, claudeSessionID: "conv-b")
        ])
        XCTAssertEqual(result.panes.map(\.command), ["claude --resume conv-a", "claude --resume conv-b"])
        XCTAssertEqual(result.panes.map(\.claudeSessionID), ["conv-a", "conv-b"])
        XCTAssertEqual(result.panes.map(\.folder), [claude, claude])
    }

    internal func testUnknownCommandsMayWrapClaude() {
        let result = plan([PaneSnapshot(folderID: wrapper.id, claudeSessionID: "conv")])
        XCTAssertEqual(result.panes.first?.command, "my-claude --resume conv")
    }

    internal func testFallsBackToTheLaunchCommand() {
        let result = plan([
            PaneSnapshot(folderID: claude.id, claudeSessionID: nil),
            PaneSnapshot(folderID: claude.id, claudeSessionID: "bad id; rm"),
            PaneSnapshot(folderID: codex.id, claudeSessionID: "conv"),
            PaneSnapshot(folderID: shell.id, claudeSessionID: "conv")
        ])
        XCTAssertEqual(result.panes.map(\.command), ["claude --continue", "claude --continue", "codex", ""])
        XCTAssertEqual(result.panes.map(\.claudeSessionID), [nil, nil, nil, nil])
    }

    internal func testSkipsRemovedProjectsAndRemapsFocus() {
        let gone = PaneSnapshot(folderID: UUID(), claudeSessionID: "conv")
        let kept = PaneSnapshot(folderID: codex.id, claudeSessionID: nil)

        let focusedKept = plan([gone, kept, gone], focusedIndex: 1)
        XCTAssertEqual(focusedKept.panes.map(\.folder), [codex])
        XCTAssertEqual(focusedKept.focusedIndex, 0)

        XCTAssertNil(plan([kept, gone], focusedIndex: 1).focusedIndex)
        XCTAssertNil(plan([kept], focusedIndex: nil).focusedIndex)
        XCTAssertEqual(plan([]).panes, [])
    }

    deinit {
        // Stateless tests.
    }
}
