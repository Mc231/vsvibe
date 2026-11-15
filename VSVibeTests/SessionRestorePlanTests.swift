@testable import VSVibe
import XCTest

internal final class SessionRestorePlanTests: XCTestCase {
    private let claude = FolderEntry(url: URL(fileURLWithPath: "/p/claude"), launchCommand: "claude --continue")
    private let flagged = FolderEntry(url: URL(fileURLWithPath: "/p/flagged"), launchCommand: "claude --model opus -c")
    private let codex = FolderEntry(url: URL(fileURLWithPath: "/p/codex"), launchCommand: "codex")
    private let shell = FolderEntry(url: URL(fileURLWithPath: "/p/shell"), launchCommand: "")
    private let wrapper = FolderEntry(url: URL(fileURLWithPath: "/p/wrapper"), launchCommand: "my-claude")

    /// `claude` owns `/cfg/claude`, the custom `work` alias owns `/cfg/work`.
    private let claudeAlias = LaunchAlias(command: "claude", claudeConfigDir: URL(fileURLWithPath: "/cfg/claude"))
    private let workAlias = LaunchAlias(command: "work", claudeConfigDir: URL(fileURLWithPath: "/cfg/work"))

    /// Transcript files that exist.
    private var existing: Set<String> = []

    private func transcript(_ configDir: String, _ id: String) -> String {
        "\(configDir)/projects/-p-claude/\(id).jsonl"
    }

    /// A saved pane running conversation `conv`, whose transcript is `path`.
    private func saved(_ folder: FolderEntry, path: String?) -> PaneSnapshot {
        PaneSnapshot(folderID: folder.id, claudeSessionID: "conv", transcriptPath: path)
    }

    private func plan(_ panes: [PaneSnapshot], focusedIndex: Int? = nil) -> SessionRestorePlan {
        let aliases = [claudeAlias, workAlias] + LaunchCommandResolver.aliases.filter { !$0.supportsClaudeHooks }
        let existing = existing
        return SessionRestorePlan.make(
            snapshot: SessionSnapshot(panes: panes, focusedIndex: focusedIndex),
            folders: [claude, flagged, codex, shell, wrapper],
            lookups: SessionRestorePlan.Lookups(
                aliasForCommand: { command in
                    aliases.first { $0.command == LaunchCommandResolver.baseCommand(of: command) }
                },
                aliasForConfigDir: { dir in aliases.first { $0.claudeConfigDir?.path == dir.path } },
                fileExists: existing.contains
            )
        )
    }

    // MARK: - No transcript path (v1 snapshots, hook scripts before v3)

    internal func testKnownConversationResumesItsOwnSession() {
        let result = plan([
            PaneSnapshot(folderID: claude.id, claudeSessionID: "conv-a"),
            PaneSnapshot(folderID: claude.id, claudeSessionID: "conv-b")
        ])
        XCTAssertEqual(result.panes.map(\.command), ["claude --resume conv-a", "claude --resume conv-b"])
        XCTAssertEqual(result.panes.map(\.claudeSessionID), ["conv-a", "conv-b"])
        XCTAssertEqual(result.panes.map(\.folder), [claude, claude])
        XCTAssertEqual(result.panes.map(\.resolution), [.resumedWithProjectCommand, .resumedWithProjectCommand])
        XCTAssertEqual(result.panes.map(\.transcriptPath), [nil, nil])
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
        XCTAssertEqual(result.panes.map(\.resolution), Array(repeating: .launchCommand, count: 4))
    }

    internal func testATranscriptPathForAnotherIDIsIgnored() {
        existing = [transcript("/cfg/work", "other")]
        let pane = plan([saved(claude, path: transcript("/cfg/work", "other"))]).panes.first

        XCTAssertEqual(pane?.command, "claude --resume conv")
        XCTAssertEqual(pane?.resolution, .resumedWithProjectCommand)
        XCTAssertNil(pane?.transcriptPath)
    }

    // MARK: - Transcript path recorded

    internal func testOwningAliasKeepsTheProjectCommandWhenItRunsThatAlias() {
        existing = [transcript("/cfg/claude", "conv")]
        let pane = plan([saved(flagged, path: transcript("/cfg/claude", "conv"))]).panes.first

        XCTAssertEqual(pane?.command, "claude --model opus --resume conv")
        XCTAssertEqual(pane?.resolution, .resumedWithOwningAlias(command: "claude"))
        XCTAssertEqual(pane?.claudeSessionID, "conv")
        XCTAssertEqual(pane?.transcriptPath, transcript("/cfg/claude", "conv"))
    }

    internal func testOwningAliasReplacesAProjectCommandForAnotherAlias() {
        let path = transcript("/cfg/work", "conv")
        existing = [path]

        let result = plan([saved(claude, path: path), saved(codex, path: path), saved(shell, path: path)])

        XCTAssertEqual(result.panes.map(\.command), Array(repeating: "work --resume conv", count: 3))
        let owner = SessionRestorePlan.Resolution.resumedWithOwningAlias(command: "work")
        XCTAssertEqual(result.panes.map(\.resolution), Array(repeating: owner, count: 3))
        XCTAssertEqual(result.panes.map(\.transcriptPath), [path, path, path])
    }

    internal func testUnknownConfigDirResumesWithTheProjectCommand() {
        let unknown = transcript("/cfg/elsewhere", "conv")
        let noProjects = "/tmp/conv.jsonl"
        existing = [unknown, noProjects]

        let result = plan([saved(claude, path: unknown), saved(wrapper, path: noProjects), saved(codex, path: unknown)])

        XCTAssertEqual(result.panes.map(\.command), ["claude --resume conv", "my-claude --resume conv", "codex"])
        XCTAssertEqual(
            result.panes.map(\.resolution),
            [
                .resumedWithUnknownConfigDir(URL(fileURLWithPath: "/cfg/elsewhere", isDirectory: true)),
                .resumedWithUnknownConfigDir(nil),
                .launchCommand
            ]
        )
        XCTAssertEqual(result.panes.map(\.transcriptPath), [unknown, noProjects, nil])
    }

    internal func testMissingTranscriptStartsTheLaunchCommandWithoutResume() {
        let pane = plan([saved(flagged, path: transcript("/cfg/claude", "conv"))]).panes.first

        XCTAssertEqual(pane?.command, "claude --model opus -c")
        XCTAssertEqual(pane?.resolution, .transcriptMissing)
        XCTAssertNil(pane?.claudeSessionID)
        XCTAssertNil(pane?.transcriptPath)
    }

    // MARK: - Projects and focus

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
