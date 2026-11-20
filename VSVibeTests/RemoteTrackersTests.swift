@testable import VSVibe
import XCTest

/// Remote usage (transcript stream) and git branch (polling) of one pane.
@MainActor
internal final class RemoteTrackersTests: XCTestCase {
    private static let assistantLine = #"{"type":"assistant","message":{"model":"m","usage":{"input_tokens":3,"#
        + #""output_tokens":4}}}"# + "\n"

    private var launcher = FakeProcessLauncher()
    private var usages: [SessionUsage] = []
    private var branches: [String?] = []

    private var dev: SSHConnection {
        get throws {
            try XCTUnwrap(SSHConnection(target: RemoteTarget(destination: "dev")))
        }
    }

    override internal func setUp() {
        super.setUp()
        launcher = FakeProcessLauncher()
        usages = []
        branches = []
    }

    override internal func tearDown() {
        usages = []
        super.tearDown()
    }

    // MARK: - Usage

    internal func testTranscriptPathValidation() {
        XCTAssertTrue(RemoteUsageTracker.isValidPath("/home/me/.claude/projects/p/a.jsonl"))
        XCTAssertFalse(RemoteUsageTracker.isValidPath(nil))
        XCTAssertFalse(RemoteUsageTracker.isValidPath("~/x.jsonl"))
        XCTAssertFalse(RemoteUsageTracker.isValidPath("/home/me/x.json"))
        XCTAssertFalse(RemoteUsageTracker.isValidPath("/home/me/\nx.jsonl"))
        XCTAssertEqual(
            RemoteUsageTracker.script(for: "/home/it's/a.jsonl"),
            #"exec tail -c +1 -F '/home/it'\''s/a.jsonl'"#
        )
    }

    internal func testStreamedChunksPublishUsage() async throws {
        let tracker = RemoteUsageTracker(
            connection: try dev,
            transcriptPath: "/home/me/a.jsonl",
            services: .fake(launcher: launcher)
        ) { [weak self] usage in
            self?.usages.append(usage)
        }
        let launch = try XCTUnwrap(launcher.launches.first)
        XCTAssertEqual(launch.script, "exec tail -c +1 -F '/home/me/a.jsonl'")
        XCTAssertEqual(tracker.transcriptPath, "/home/me/a.jsonl")

        let line = Self.assistantLine
        launch.emit(String(line.prefix(20)))
        launch.emit(String(line.dropFirst(20)) + line)

        let published = await AsyncWait.until { self.usages.last?.messageCount == 2 }
        XCTAssertTrue(published)
        XCTAssertEqual(usages.last?.totalInput, 6)
        XCTAssertEqual(usages.last?.totalOutput, 8)
        tracker.stop()
    }

    internal func testReconnectRereadsIntoFreshTotals() async throws {
        let tracker = RemoteUsageTracker(
            connection: try dev,
            transcriptPath: "/home/me/a.jsonl",
            services: .fake(launcher: launcher)
        ) { [weak self] usage in
            self?.usages.append(usage)
        }
        launcher.launches.first?.emit(Self.assistantLine)
        _ = await AsyncWait.until { !self.usages.isEmpty }

        launcher.launches.first?.exit()
        _ = await AsyncWait.until { self.launcher.launches.count == 2 }
        launcher.launches.last?.emit(Self.assistantLine)
        let republished = await AsyncWait.until { self.usages.count == 2 }

        XCTAssertTrue(republished)
        XCTAssertEqual(usages.map(\.messageCount), [1, 1])
        tracker.stop()
    }

    internal func testStoppedTrackerPublishesNothing() async throws {
        let tracker = RemoteUsageTracker(
            connection: try dev,
            transcriptPath: "/home/me/a.jsonl",
            services: .fake(launcher: launcher)
        ) { [weak self] usage in
            self?.usages.append(usage)
        }
        let launch = try XCTUnwrap(launcher.launches.first)
        tracker.stop()
        tracker.stop()
        launch.emit(Self.assistantLine)
        await AsyncWait.drainMainQueue()

        XCTAssertTrue(usages.isEmpty)
        XCTAssertTrue(launch.isTerminated)
    }

    // MARK: - Branch

    internal func testBranchScriptAndParsing() {
        XCTAssertEqual(
            RemoteBranchTracker.script(for: "~/my app"),
            "cd ~/'my app' 2>/dev/null && "
                + "{ git symbolic-ref --short -q HEAD || git rev-parse --short HEAD; } 2>/dev/null"
        )
        XCTAssertTrue(RemoteBranchTracker.script(for: "").hasPrefix("cd ~ 2>/dev/null"))

        let branch = RemoteBranchTracker.branch(from:)
        XCTAssertEqual(branch(RemoteCommandResult(status: 0, output: Data("feature/x\n".utf8))), "feature/x")
        XCTAssertNil(branch(RemoteCommandResult(status: 1, output: Data("main\n".utf8))))
        XCTAssertNil(branch(RemoteCommandResult(status: 0, output: Data("\n".utf8))))
        XCTAssertNil(branch(RemoteCommandResult(status: 0, output: Data("a\u{1B}b".utf8))))
        XCTAssertNil(branch(RemoteCommandResult(status: 0, output: Data(String(repeating: "b", count: 256).utf8))))
    }

    internal func testBranchPollingReportsChanges() async throws {
        let answers = Answers(["main\n", "main\n", "dev\n"])
        let runner = FakeRemoteRunner { _, _ in
            let next = answers.next()
            return next.map { RemoteCommandResult(status: 0, output: Data($0.utf8)) }
                ?? RemoteCommandResult(status: 255, errorOutput: "down")
        }
        let tracker = RemoteBranchTracker(
            connection: try dev,
            remotePath: "/srv/app",
            services: .fake(launcher: launcher, runner: runner)
        ) { [weak self] branch in
            self?.branches.append(branch)
        }

        tracker.start()
        tracker.start()
        XCTAssertTrue(tracker.isRunning)
        let reported = await AsyncWait.until { self.branches.count == 3 }
        tracker.stop()

        XCTAssertTrue(reported)
        XCTAssertEqual(branches, ["main", "dev", nil])
        XCTAssertFalse(tracker.isRunning)
        XCTAssertTrue(runner.calls.first?.script.hasPrefix("cd '/srv/app' 2>/dev/null") ?? false)
        XCTAssertNil(runner.calls.first?.input)
    }

    deinit {
        // Trackers are stopped by each test.
    }
}
