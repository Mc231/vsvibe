@testable import VSVibe
import XCTest

/// Remote panes monitored over (fake) ssh through `SessionManager`: event
/// streams per host, git branch and usage, and routing of remote events.
@MainActor
internal final class RemotePaneMonitorTests: XCTestCase {
    private static let transcript = "/home/me/.claude/projects/-srv-app/conv-1.jsonl"

    private var directory = TestSupport.placeholderURL
    private var fake = FakeSessionLauncher()
    private var launcher = FakeProcessLauncher()
    private var monitor = RemotePaneMonitor(services: .fake(launcher: FakeProcessLauncher()))
    private var manager = SessionManager(
        statsStore: StatsStore(fileURL: TestSupport.placeholderURL) { [] },
        aliasStore: LaunchAliasStore(fileURL: TestSupport.placeholderURL)
    )
    private var notifier = RecordingNotifier()
    private var coordinator: EventCoordinator?

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("remote-monitor")
        fake = FakeSessionLauncher()
        fake.onPath = ["ssh", "ls"]
        launcher = FakeProcessLauncher()
        var services = RemoteServices.fake(
            launcher: launcher,
            runner: FakeRemoteRunner { _, _ in RemoteCommandResult(status: 0, output: Data("main\n".utf8)) }
        )
        services.sleep = { _ in try? await Task.sleep(nanoseconds: 20_000_000) }
        monitor = RemotePaneMonitor(services: services)
        let stats = StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
        manager = SessionManager(
            statsStore: stats,
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher,
            remoteMonitor: monitor
        )
        notifier = RecordingNotifier()
        let folderStore = FolderStore(fileURL: directory.appendingPathComponent("state.json"))
        let coordinator = EventCoordinator(
            folderStore: folderStore,
            sessionManager: manager,
            statsStore: stats,
            notifier: notifier,
            eventsURL: directory.appendingPathComponent("events.jsonl")
        )
        monitor.onEvent = { [weak coordinator] event in
            coordinator?.handleRemote(event)
        }
        self.coordinator = coordinator
    }

    override internal func tearDown() {
        manager.closeAllSessions()
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func remote(_ destination: String = "dev", port: Int? = nil) -> FolderEntry {
        FolderEntry(remote: RemoteTarget(destination: destination, port: port, remotePath: "/srv/app"))
    }

    private func eventStreams() -> [FakeProcessLauncher.Launch] {
        launcher.running.filter { $0.script == RemoteEventStreams.script }
    }

    private func usageStreams() -> [FakeProcessLauncher.Launch] {
        launcher.running.filter { $0.script.hasPrefix("exec tail -c +1 -F") }
    }

    private func event(_ kind: HookEventKind, pane: UUID, sessionID: String? = nil, path: String? = nil) -> String {
        var fields = [#""event":"\#(kind.rawValue)""#, #""ts":1"#, #""paneId":"\#(pane.uuidString)""#]
        if let sessionID {
            fields.append(#""sessionId":"\#(sessionID)""#)
        }
        if let path {
            fields.append(#""transcriptPath":"\#(path)""#)
        }
        return "{" + fields.joined(separator: ",") + "}\n"
    }

    // MARK: - Lifecycle

    internal func testOneEventStreamPerHostUntilItsLastPaneCloses() throws {
        let first = manager.createSession(for: remote())
        let second = manager.createSession(for: remote())
        let other = manager.createSession(for: remote("dev", port: 2_222))
        let local = manager.createSession(
            for: FolderEntry(url: directory, displayName: "local", launchCommand: "ls")
        )

        XCTAssertEqual(eventStreams().count, 2)
        XCTAssertEqual(monitor.streamedConnections.count, 2)
        XCTAssertEqual(monitor.monitoredPaneIDs, [first.id, second.id, other.id])
        XCTAssertFalse(monitor.monitoredPaneIDs.contains(local.id))

        manager.closeSession(id: first.id)
        XCTAssertEqual(eventStreams().count, 2)
        manager.closeSession(id: second.id)
        XCTAssertEqual(eventStreams().count, 1)
        XCTAssertTrue(eventStreams().first?.arguments.contains("2222") ?? false)

        manager.closeAllSessions()
        XCTAssertTrue(launcher.running.isEmpty)
        XCTAssertTrue(monitor.monitoredPaneIDs.isEmpty)
    }

    internal func testBranchComesFromTheHost() async {
        let session = manager.createSession(for: remote())

        let shown = await AsyncWait.until { session.gitBranch == "main" }

        XCTAssertTrue(shown)
    }

    internal func testInvalidTargetsAreNotMonitored() {
        let session = manager.createSession(for: FolderEntry(remote: RemoteTarget(destination: "-bad")))

        XCTAssertFalse(monitor.monitoredPaneIDs.contains(session.id))
        XCTAssertTrue(launcher.launches.isEmpty)
        monitor.paneClosed(id: session.id)
        monitor.conversationChanged(session)
    }

    // MARK: - Usage

    internal func testNoUsageBeforeTheFirstHookEvent() {
        let session = manager.createSession(for: remote())

        XCTAssertNotNil(session.claudeSessionID)
        XCTAssertNil(monitor.streamedTranscriptPath(forPane: session.id))
        XCTAssertTrue(usageStreams().isEmpty)
        XCTAssertNil(session.usage)
    }

    internal func testTranscriptPathStartsAndRetargetsTheUsageStream() async throws {
        let session = manager.createSession(for: remote())

        manager.recordClaudeConversation("conv-1", transcriptPath: Self.transcript, in: session)
        let stream = try XCTUnwrap(usageStreams().first)
        stream.emit(#"{"type":"assistant","message":{"usage":{"input_tokens":5}}}"# + "\n")
        let shown = await AsyncWait.until { session.usage?.totalInput == 5 }
        XCTAssertTrue(shown)
        XCTAssertEqual(monitor.streamedTranscriptPath(forPane: session.id), Self.transcript)

        manager.recordClaudeConversation("conv-1", transcriptPath: Self.transcript, in: session)
        XCTAssertEqual(usageStreams().count, 1)

        let next = "/home/me/.claude/projects/-srv-app/conv-2.jsonl"
        manager.recordClaudeConversation("conv-2", transcriptPath: next, in: session)
        XCTAssertTrue(stream.isTerminated)
        XCTAssertNil(session.usage)
        XCTAssertEqual(usageStreams().first?.script, RemoteUsageTracker.script(for: next))

        manager.recordClaudeConversation("conv-3", transcriptPath: "relative.jsonl", in: session)
        XCTAssertTrue(usageStreams().isEmpty)
        XCTAssertNil(monitor.streamedTranscriptPath(forPane: session.id))
    }

    internal func testRestoredPaneStreamsItsSavedTranscript() throws {
        let session = manager.restoreSession(
            for: remote(),
            command: "claude",
            claudeSessionID: "conv-1",
            transcriptPath: Self.transcript
        )

        XCTAssertEqual(session.claudeSessionID, "conv-1")
        XCTAssertEqual(session.claudeTranscriptPath, Self.transcript)
        XCTAssertEqual(monitor.streamedTranscriptPath(forPane: session.id), Self.transcript)
    }

    // MARK: - Events

    internal func testRemoteEventsReachTheirPane() throws {
        let session = manager.createSession(for: remote())
        let stream = try XCTUnwrap(eventStreams().first)

        stream.emit(event(.sessionStart, pane: session.id, sessionID: "conv-1", path: Self.transcript))
        stream.emit(event(.notification, pane: session.id))

        XCTAssertEqual(session.claudeSessionID, "conv-1")
        XCTAssertEqual(monitor.streamedTranscriptPath(forPane: session.id), Self.transcript)
        XCTAssertTrue(session.awaitingInput)
        XCTAssertEqual(session.unreadEventCount, 1)
        XCTAssertEqual(notifier.posts.map(\.sessionID), [session.id])
    }

    internal func testRemoteEventsNeverReachLocalOrUnknownPanes() throws {
        let local = manager.createSession(for: FolderEntry(url: directory, displayName: "local", launchCommand: "ls"))
        _ = manager.createSession(for: remote())
        let stream = try XCTUnwrap(eventStreams().first)

        stream.emit(event(.notification, pane: local.id))
        stream.emit(event(.stop, pane: UUID()))
        stream.emit(#"{"event":"Stop","projectDir":"\#(directory.path)","ts":1}"# + "\n")

        XCTAssertEqual(local.unreadEventCount, 0)
        XCTAssertTrue(notifier.posts.isEmpty)
    }

    internal func testLocalEventsFileIgnoresRemotePanes() throws {
        let session = manager.createSession(for: remote())
        let event = HookEvent(
            event: .notification,
            projectDir: "/srv/app",
            timestamp: 1,
            message: nil,
            paneID: session.id
        )

        try XCTUnwrap(coordinator).handle(event)

        XCTAssertEqual(session.unreadEventCount, 0)
        XCTAssertTrue(notifier.posts.isEmpty)
    }

    deinit {
        // Panes are closed in tearDown.
    }
}
