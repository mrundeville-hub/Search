import SwiftUI
import XCTest
@testable import Search

/// A boost's colours and type: the CSS they write, and the same thing read
/// back after a relaunch.
final class BoostLookTests: XCTestCase {
    func testAnEmptyLookWritesNothing() {
        XCTAssertEqual(BoostLook().css(), "")
        XCTAssertTrue(BoostLook().isEmpty)
    }

    func testTheFourFieldsWriteOneRule() {
        let look = BoostLook(background: "#101010", text: "#EEEEEE", font: "Georgia", size: 18)
        let css = look.css()
        XCTAssertTrue(css.hasPrefix("html, body {"))
        XCTAssertTrue(css.contains("background-color: #101010 !important;"))
        XCTAssertTrue(css.contains("color: #EEEEEE !important;"))
        XCTAssertTrue(css.contains("font-family: \"Georgia\", -apple-system, sans-serif;"))
        XCTAssertTrue(css.contains("font-size: 18px;"))
    }

    func testLinesAndParagraphsWriteTheirOwnRules() {
        let look = BoostLook(lineHeight: 1.6, paragraphSpacing: 10)
        let css = look.css()
        XCTAssertTrue(css.contains("line-height: 1.60;"))
        XCTAssertTrue(css.contains("p, li { margin-block: 10px; }"))
        XCTAssertTrue(css.hasPrefix("html, body {"), "the root rule comes first")

        XCTAssertFalse(BoostLook(lineHeight: 0.5).css().contains("line-height"))
        XCTAssertFalse(BoostLook(lineHeight: 9).css().contains("line-height"))
        XCTAssertFalse(BoostLook(paragraphSpacing: 40).css().contains("margin-block"))
        XCTAssertEqual(BoostLook(paragraphSpacing: 0).css(), "p, li { margin-block: 0px; }",
                       "no room at all is a choice, not nothing")
    }

    func testASizeOutOfRangeIsNotWritten() {
        XCTAssertFalse(BoostLook(size: 4).css().contains("font-size"))
        XCTAssertFalse(BoostLook(size: 400).css().contains("font-size"))
        XCTAssertTrue(BoostLook(size: 32).css().contains("font-size: 32px"))
    }

    @MainActor
    func testTheLookIsPutOnThePageBeforeTheStyle() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-look-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let styles = SiteStyles(file: dir.appendingPathComponent("styles.json"))
        styles.on = true

        styles.setLook(BoostLook(background: "#010203"), on: "example.com")
        styles.set("h1 { color: red }", on: "example.com")
        let css = try? XCTUnwrap(styles.css(on: "example.com"))
        XCTAssertTrue(css?.hasPrefix("html, body { background-color: #010203 !important; }") == true,
                      "the look comes first, so the site's own CSS written here wins")
        XCTAssertTrue(css?.contains("h1 { color: red }") == true)

        styles.setLook(BoostLook(), on: "example.com")
        XCTAssertFalse(styles.css(on: "example.com")?.contains("background-color") == true,
                       "cleared, the look writes nothing")
    }

    @MainActor
    func testTheLookSurvivesARelaunchAndOlderFilesStillRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-look-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("styles.json")

        let styles = SiteStyles(file: file)
        styles.setLook(BoostLook(background: "#0A0B0C", font: "Menlo", size: 15), on: "example.com")
        styles.writeNow()

        let again = SiteStyles(file: file)
        XCTAssertEqual(again.look(on: "example.com")?.background, "#0A0B0C")
        XCTAssertEqual(again.look(on: "example.com")?.font, "Menlo")
        XCTAssertEqual(again.look(on: "example.com")?.size, 15)

        // A file from before a boost had a look: two halves, nothing else.
        let old = dir.appendingPathComponent("old.json")
        try #"{"version":2,"css":{"a.example":"p{}"},"script":{}}"#.write(to: old, atomically: true, encoding: .utf8)
        let older = SiteStyles(file: old)
        XCTAssertEqual(older.written(on: "a.example"), "p{}")
        XCTAssertNil(older.look(on: "a.example"))
    }

    @MainActor
    func testABoostFileCarriesTheLook() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-look-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let styles = SiteStyles(file: dir.appendingPathComponent("styles.json"))
        styles.on = true
        styles.setLook(BoostLook(background: "#123456", size: 20), on: "example.com")

        let shared = try XCTUnwrap(styles.boost(on: "example.com"))
        XCTAssertEqual(shared.look?.background, "#123456")
        let back = try BoostFile.read(Data(shared.json().utf8))
        XCTAssertEqual(back.look?.size, 20, "the look travels with the file")
    }

    func testAColourGoesOutAndComesBack() {
        let hex = BoostLook.hex(Color(red: 1, green: 0, blue: 0))
        XCTAssertEqual(hex, "#FF0000")
        XCTAssertEqual(BoostLook.hex(nil), "")
        XCTAssertNotNil(BoostLook.colour(hex))
        XCTAssertNil(BoostLook.colour("nonsense"))
    }
}
