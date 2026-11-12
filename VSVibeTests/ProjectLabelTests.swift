@testable import VSVibe
import XCTest

internal final class ProjectLabelTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    internal func testInitNormalizesColor() {
        XCTAssertEqual(ProjectLabel(name: "Work", colorHex: "3b82f6").colorHex, "#3B82F6")
    }

    internal func testInitFallsBackOnBadColorAndEmptySymbol() {
        let label = ProjectLabel(name: "Work", colorHex: "not-a-color", symbolName: "")
        XCTAssertEqual(label.colorHex, LabelPalette.defaultColor)
        XCTAssertEqual(label.symbolName, LabelPalette.defaultSymbol)
    }

    internal func testRoundTrip() throws {
        let original = ProjectLabel(name: "Pet", colorHex: "#22C55E", symbolName: "leaf.fill", isCollapsed: true)
        let decoded = try makeDecoder().decode(ProjectLabel.self, from: makeEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Pet")
        XCTAssertEqual(decoded.colorHex, "#22C55E")
        XCTAssertEqual(decoded.symbolName, "leaf.fill")
        XCTAssertTrue(decoded.isCollapsed)
    }

    internal func testDecodeMissingOptionalFieldsUsesDefaults() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Work"}"#
        let decoded = try makeDecoder().decode(ProjectLabel.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertEqual(decoded.colorHex, LabelPalette.defaultColor)
        XCTAssertEqual(decoded.symbolName, LabelPalette.defaultSymbol)
        XCTAssertFalse(decoded.isCollapsed)
    }

    internal func testSuggestedColorSkipsUsedOnes() {
        let first = LabelPalette.colors[0]
        let second = LabelPalette.colors[1]
        XCTAssertEqual(LabelPalette.suggestedColor(usedBy: []), first)
        let taken = [ProjectLabel(name: "A", colorHex: first)]
        XCTAssertEqual(LabelPalette.suggestedColor(usedBy: taken), second)
    }

    internal func testSuggestedColorCyclesWhenPaletteExhausted() {
        let all = LabelPalette.colors.enumerated().map { ProjectLabel(name: "L\($0.offset)", colorHex: $0.element) }
        let suggested = LabelPalette.suggestedColor(usedBy: all)
        XCTAssertTrue(LabelPalette.colors.contains(suggested))
    }

    internal func testFolderEntryCarriesLabelIDs() throws {
        let labelID = UUID()
        let entry = FolderEntry(url: URL(fileURLWithPath: "/x/a"), labelIDs: [labelID])
        let decoded = try makeDecoder().decode(FolderEntry.self, from: makeEncoder().encode(entry))
        XCTAssertEqual(decoded.labelIDs, [labelID])
    }

    internal func testFolderEntryDecodesLegacyEntryWithoutLabels() throws {
        let entry = FolderEntry(url: URL(fileURLWithPath: "/x/a"))
        let encoded = try makeEncoder().encode(entry)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "labelIDs")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try makeDecoder().decode(FolderEntry.self, from: stripped).labelIDs, [])
    }

    internal func testPersistedStateRoundTripWithLabels() throws {
        let label = ProjectLabel(name: "Work")
        let state = PersistedState(
            version: PersistedState.currentVersion,
            folders: [FolderEntry(url: URL(fileURLWithPath: "/x/a"), labelIDs: [label.id])],
            labels: [label],
            ungroupedCollapsed: true
        )
        let decoded = try makeDecoder().decode(PersistedState.self, from: makeEncoder().encode(state))
        XCTAssertEqual(decoded.labels.map(\.name), ["Work"])
        XCTAssertEqual(decoded.folders.first?.labelIDs, [label.id])
        XCTAssertTrue(decoded.ungroupedCollapsed)
    }

    /// A v1 file (folders only) must still load, with no labels.
    internal func testPersistedStateDecodesVersion1() throws {
        let json = #"{"version":1,"folders":[]}"#
        let decoded = try makeDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.labels.isEmpty)
        XCTAssertFalse(decoded.ungroupedCollapsed)
    }

    deinit {
        // Nothing to release.
    }
}
