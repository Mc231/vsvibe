@testable import VSVibe
import XCTest

/// Keeping a remote stream alive: reconnects with backoff, stop, stale output.
@MainActor
internal final class RemoteStreamTests: XCTestCase {
    private final class Delays: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval] = []

        var recorded: [TimeInterval] {
            lock.withLock { values }
        }

        func record(_ delay: TimeInterval) {
            lock.withLock { values.append(delay) }
        }

        deinit {
            // Test double; nothing to release.
        }
    }

    private var launcher = FakeProcessLauncher()
    private var delays = Delays()
    private var clock = Date(timeIntervalSince1970: 0)
    private var connects = 0
    private var received: [String] = []

    override internal func setUp() {
        super.setUp()
        launcher = FakeProcessLauncher()
        delays = Delays()
        clock = Date(timeIntervalSince1970: 0)
        connects = 0
        received = []
    }

    override internal func tearDown() {
        received = []
        super.tearDown()
    }

    private func services() -> RemoteServices {
        var services = RemoteServices.fake(launcher: launcher)
        let delays = delays
        services.sleep = { delay in
            delays.record(delay)
            await Task.yield()
        }
        services.now = { [weak self] in self?.clock ?? Date() }
        return services
    }

    private func makeStream(_ services: RemoteServices? = nil) -> RemoteStream {
        RemoteStream(
            arguments: ["a"],
            services: services ?? self.services(),
            onConnect: { [weak self] in self?.connects += 1 },
            onOutput: { [weak self] data in self?.received.append(String(bytes: data, encoding: .utf8) ?? "") }
        )
    }

    internal func testOutputIsDeliveredAfterConnect() {
        let stream = makeStream()

        stream.start()
        stream.start()
        launcher.launches.first?.emit("hello")

        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(launcher.launches.first?.arguments, ["a"])
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(received, ["hello"])
        XCTAssertTrue(stream.isRunning)
        stream.stop()
    }

    internal func testExitReconnectsWithGrowingDelays() async {
        let stream = makeStream()
        stream.start()

        for expected in 2...4 {
            launcher.launches.last?.exit()
            let reconnected = await AsyncWait.until { self.launcher.launches.count == expected }
            XCTAssertTrue(reconnected)
        }
        XCTAssertEqual(delays.recorded, [1, 2, 4])
        XCTAssertEqual(connects, 4)

        // A connection that stayed up resets the backoff.
        clock = clock.addingTimeInterval(60)
        launcher.launches.last?.exit()
        _ = await AsyncWait.until { self.launcher.launches.count == 5 }
        XCTAssertEqual(delays.recorded, [1, 2, 4, 1])
        stream.stop()
    }

    internal func testStopTerminatesAndPreventsReconnects() async {
        let stream = makeStream()
        stream.start()
        let first = launcher.launches.first

        stream.stop()
        stream.stop()
        first?.emit("late")
        first?.exit()
        await AsyncWait.drainMainQueue()

        XCTAssertEqual(first?.isTerminated, true)
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(received, [])
        XCTAssertFalse(stream.isRunning)
    }

    internal func testStopWhileWaitingCancelsTheReconnect() async {
        var services = services()
        services.sleep = { _ in try? await Task.sleep(nanoseconds: 200_000_000) }
        let stream = makeStream(services)
        stream.start()
        launcher.launches.first?.exit()

        stream.stop()
        await AsyncWait.drainMainQueue(seconds: 0.3)

        XCTAssertEqual(launcher.launches.count, 1)
    }

    internal func testOutputOfAnEndedProcessIsIgnored() async {
        let stream = makeStream()
        stream.start()
        let old = launcher.launches.first
        old?.exit()
        _ = await AsyncWait.until { self.launcher.launches.count == 2 }

        old?.emit("stale")
        old?.exit()
        launcher.launches.last?.emit("fresh")

        XCTAssertEqual(received, ["fresh"])
        XCTAssertEqual(launcher.launches.count, 2)
        stream.stop()
    }

    deinit {
        // Streams are stopped by each test.
    }
}
