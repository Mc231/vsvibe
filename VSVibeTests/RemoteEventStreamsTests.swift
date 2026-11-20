@testable import VSVibe
import XCTest

/// One event stream per host: lifecycle, line splitting and decoding.
@MainActor
internal final class RemoteEventStreamsTests: XCTestCase {
    private var launcher = FakeProcessLauncher()
    private var events: [HookEvent] = []

    override internal func setUp() {
        super.setUp()
        launcher = FakeProcessLauncher()
        events = []
    }

    override internal func tearDown() {
        events = []
        super.tearDown()
    }

    private func connection(_ destination: String, port: Int? = nil) throws -> SSHConnection {
        try XCTUnwrap(SSHConnection(target: RemoteTarget(destination: destination, port: port)))
    }

    private func makeStreams() -> RemoteEventStreams {
        let streams = RemoteEventStreams(services: .fake(launcher: launcher))
        streams.onEvent = { [weak self] event in self?.events.append(event) }
        return streams
    }

    internal func testOneStreamPerHostFollowingTheEventsFile() throws {
        let streams = makeStreams()
        let dev = try connection("dev")
        let other = try connection("dev", port: 2_200)

        streams.update([dev, other])
        streams.update([dev, other])

        XCTAssertEqual(streams.connections, [dev, other])
        XCTAssertEqual(launcher.launches.count, 2)
        let launch = try XCTUnwrap(launcher.launches.first { !$0.arguments.contains("-p") })
        XCTAssertEqual(launch.script, RemoteEventStreams.script)
        XCTAssertTrue(launch.script.hasSuffix("exec tail -n 0 -F ~/.vsvibe/events.jsonl"))
        XCTAssertTrue(launch.arguments.contains("ServerAliveInterval=15"))
        XCTAssertEqual(launch.arguments.suffix(2).first, "dev")
        streams.stopAll()
    }

    internal func testHostsWithoutPanesAreStopped() throws {
        let streams = makeStreams()
        let dev = try connection("dev")
        let box = try connection("box")
        streams.update([dev, box])

        streams.update([box])

        XCTAssertEqual(streams.connections, [box])
        XCTAssertEqual(launcher.running.count, 1)
        XCTAssertTrue(launcher.running.first?.arguments.contains("box") ?? false)

        streams.stopAll()
        XCTAssertTrue(streams.connections.isEmpty)
        XCTAssertTrue(launcher.running.isEmpty)
    }

    internal func testLinesSplitAcrossChunksAreDecoded() throws {
        let streams = makeStreams()
        streams.update([try connection("dev")])
        let pane = UUID()
        let launch = try XCTUnwrap(launcher.launches.first)

        launch.emit(#"{"event":"Notification","projectDir":"/srv","ts":1,"paneId":"\#(pane.uuidString)","#)
        XCTAssertTrue(events.isEmpty)
        launch.emit(#""message":"Waiting"}"# + "\nnot json\n" + #"{"event":"Stop","ts":2}"# + "\n")

        XCTAssertEqual(events.map(\.event), [.notification, .stop])
        XCTAssertEqual(events.first?.paneID, pane)
        XCTAssertEqual(events.first?.message, "Waiting")
        streams.stopAll()
    }

    internal func testReconnectDropsAPartialLine() async throws {
        let streams = makeStreams()
        streams.update([try connection("dev")])
        launcher.launches.first?.emit(#"{"event":"Stop","#)
        launcher.launches.first?.exit()
        _ = await AsyncWait.until { self.launcher.launches.count == 2 }

        launcher.launches.last?.emit(#"{"event":"Notification","ts":3}"# + "\n")

        XCTAssertEqual(events.map(\.event), [.notification])
        streams.stopAll()
    }

    deinit {
        // Streams are stopped by each test.
    }
}
