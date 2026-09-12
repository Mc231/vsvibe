import XCTest
@testable import VSVibe

final class FolderEntryTests: XCTestCase {

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    func testInitDefaults() {
        let url = URL(fileURLWithPath: "/Users/x/pet/demo")
        let entry = FolderEntry(url: url)
        XCTAssertEqual(entry.displayName, "demo")
        XCTAssertEqual(entry.launchCommand, "claude")
    }

    func testInitWithXimDefaultsCommand() {
        let url = URL(fileURLWithPath: "/Users/x/xim/app")
        XCTAssertEqual(FolderEntry(url: url).launchCommand, "claudexim")
    }

    func testRoundTrip() throws {
        let original = FolderEntry(url: URL(fileURLWithPath: "/Users/x/demo"),
                                   displayName: "Demo",
                                   launchCommand: "opencode")
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(FolderEntry.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.displayName, "Demo")
        XCTAssertEqual(decoded.launchCommand, "opencode")
        XCTAssertEqual(decoded.url.standardizedFileURL, original.url.standardizedFileURL)
    }

    func testDecodeMissingLaunchCommandUsesDefault() throws {
        // Encode then strip launchCommand to simulate older persisted data.
        let entry = FolderEntry(url: URL(fileURLWithPath: "/Users/x/pet/demo"),
                                displayName: "demo",
                                launchCommand: "opencode")
        let data = try makeEncoder().encode(entry)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "launchCommand")
        let stripped = try JSONSerialization.data(withJSONObject: obj)

        let decoded = try makeDecoder().decode(FolderEntry.self, from: stripped)
        XCTAssertEqual(decoded.launchCommand, "claude") // default for non-xim path
    }

    func testPersistedStateRoundTrip() throws {
        let state = PersistedState(version: PersistedState.currentVersion,
                                   folders: [FolderEntry(url: URL(fileURLWithPath: "/Users/x/a")),
                                             FolderEntry(url: URL(fileURLWithPath: "/Users/x/b"))])
        let data = try makeEncoder().encode(state)
        let decoded = try makeDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded.version, PersistedState.currentVersion)
        XCTAssertEqual(decoded.folders.count, 2)
        XCTAssertEqual(decoded.folders.map(\.displayName), ["a", "b"])
    }
}
