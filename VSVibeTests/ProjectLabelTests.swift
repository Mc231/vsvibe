@testable import VSVibe
import XCTest

final class ColorHexTests: XCTestCase {
    func testParsesSixDigitWithHash() {
        let rgb = ColorHex.rgb(from: "#FF8000")
        XCTAssertEqual(rgb?.red ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.green ?? 0, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.blue ?? 0, 0.0, accuracy: 0.001)
    }

    func testParsesWithoutHashAndLowercase() {
        XCTAssertEqual(ColorHex.rgb(from: "ff8000"), ColorHex.rgb(from: "#FF8000"))
    }

    func testParsesShorthand() {
        XCTAssertEqual(ColorHex.rgb(from: "#abc"), ColorHex.rgb(from: "#AABBCC"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(ColorHex.rgb(from: "  #3B82F6 "), ColorHex.rgb(from: "#3B82F6"))
    }

    func testRejectsInvalid() {
        XCTAssertNil(ColorHex.rgb(from: ""))
        XCTAssertNil(ColorHex.rgb(from: "#GGGGGG"))
        XCTAssertNil(ColorHex.rgb(from: "#12345"))
        XCTAssertNil(ColorHex.rgb(from: "blue"))
        XCTAssertNil(ColorHex.rgb(from: "#12345678"))
    }

    func testNormalizedUppercasesAndAddsHash() {
        XCTAssertEqual(ColorHex.normalized("3b82f6"), "#3B82F6")
        XCTAssertEqual(ColorHex.normalized("#abc"), "#AABBCC")
        XCTAssertNil(ColorHex.normalized("nope"))
    }

    func testNormalizedIsIdempotent() {
        let once = ColorHex.normalized("#3b82f6")!
        XCTAssertEqual(ColorHex.normalized(once), once)
    }
}

final class ProjectLabelTests: XCTestCase {
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

    func testInitNormalizesColor() {
        XCTAssertEqual(ProjectLabel(name: "Work", colorHex: "3b82f6").colorHex, "#3B82F6")
    }

    func testInitFallsBackOnBadColorAndEmptySymbol() {
        let label = ProjectLabel(name: "Work", colorHex: "not-a-color", symbolName: "")
        XCTAssertEqual(label.colorHex, LabelPalette.defaultColor)
        XCTAssertEqual(label.symbolName, LabelPalette.defaultSymbol)
    }

    func testRoundTrip() throws {
        let original = ProjectLabel(name: "Pet", colorHex: "#22C55E", symbolName: "leaf.fill", isCollapsed: true)
        let decoded = try makeDecoder().decode(ProjectLabel.self, from: makeEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Pet")
        XCTAssertEqual(decoded.colorHex, "#22C55E")
        XCTAssertEqual(decoded.symbolName, "leaf.fill")
        XCTAssertTrue(decoded.isCollapsed)
    }

    func testDecodeMissingOptionalFieldsUsesDefaults() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Work"}"#
        let decoded = try makeDecoder().decode(ProjectLabel.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertEqual(decoded.colorHex, LabelPalette.defaultColor)
        XCTAssertEqual(decoded.symbolName, LabelPalette.defaultSymbol)
        XCTAssertFalse(decoded.isCollapsed)
    }

    func testSuggestedColorSkipsUsedOnes() {
        let first = LabelPalette.colors[0]
        let second = LabelPalette.colors[1]
        XCTAssertEqual(LabelPalette.suggestedColor(usedBy: []), first)
        let taken = [ProjectLabel(name: "A", colorHex: first)]
        XCTAssertEqual(LabelPalette.suggestedColor(usedBy: taken), second)
    }

    func testSuggestedColorCyclesWhenPaletteExhausted() {
        let all = LabelPalette.colors.enumerated().map { ProjectLabel(name: "L\($0.offset)", colorHex: $0.element) }
        let suggested = LabelPalette.suggestedColor(usedBy: all)
        XCTAssertTrue(LabelPalette.colors.contains(suggested))
    }

    func testFolderEntryCarriesLabelIDs() throws {
        let labelID = UUID()
        let entry = FolderEntry(url: URL(fileURLWithPath: "/x/a"), labelIDs: [labelID])
        let decoded = try makeDecoder().decode(FolderEntry.self, from: makeEncoder().encode(entry))
        XCTAssertEqual(decoded.labelIDs, [labelID])
    }

    func testFolderEntryDecodesLegacyEntryWithoutLabels() throws {
        let entry = FolderEntry(url: URL(fileURLWithPath: "/x/a"))
        var obj = try JSONSerialization.jsonObject(with: makeEncoder().encode(entry)) as! [String: Any]
        obj.removeValue(forKey: "labelIDs")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try makeDecoder().decode(FolderEntry.self, from: stripped).labelIDs, [])
    }

    func testPersistedStateRoundTripWithLabels() throws {
        let label = ProjectLabel(name: "Work")
        let state = PersistedState(version: PersistedState.currentVersion,
                                   folders: [FolderEntry(url: URL(fileURLWithPath: "/x/a"), labelIDs: [label.id])],
                                   labels: [label],
                                   ungroupedCollapsed: true)
        let decoded = try makeDecoder().decode(PersistedState.self, from: makeEncoder().encode(state))
        XCTAssertEqual(decoded.labels.map(\.name), ["Work"])
        XCTAssertEqual(decoded.folders.first?.labelIDs, [label.id])
        XCTAssertTrue(decoded.ungroupedCollapsed)
    }

    /// A v1 file (folders only) must still load, with no labels.
    func testPersistedStateDecodesVersion1() throws {
        let json = #"{"version":1,"folders":[]}"#
        let decoded = try makeDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.labels.isEmpty)
        XCTAssertFalse(decoded.ungroupedCollapsed)
    }
}
