import XCTest
@testable import Search

/// The two halves of a boost: a site's own CSS, and the script beside it.
final class BoostTests: XCTestCase {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("boosts-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testBothHalvesAreKeptAndSurviveARelaunch() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("styles.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let styles = SiteStyles(file: file)
        styles.on = true
        styles.set("body { background: black }", on: "example.com")
        styles.setScript("document.body.dataset.boost = '1';", on: "example.com")
        styles.set("p { color: red }", on: "other.com")
        styles.writeNow()

        let again = SiteStyles(file: file)
        again.on = true
        XCTAssertEqual(again.written(on: "example.com"), "body { background: black }")
        XCTAssertEqual(again.writtenScript(on: "example.com"), "document.body.dataset.boost = '1';")
        XCTAssertEqual(again.writtenScript(on: "other.com"), "", "a site with only a style has no script")
        XCTAssertEqual(again.hosts, ["example.com", "other.com"])
    }

    @MainActor
    func testASiteFromBeforeTheScriptHalfStillReads() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("styles.json")
        // What styles.json was before this: one plain map of host to CSS.
        try JSONEncoder().encode(["example.com": "h1 { color: red }"]).write(to: file)

        let styles = SiteStyles(file: file)
        styles.on = true
        XCTAssertEqual(styles.written(on: "example.com"), "h1 { color: red }")
        XCTAssertEqual(styles.writtenScript(on: "example.com"), "")
    }

    @MainActor
    func testTheSwitchTakesBothHalvesOff() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("styles.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let styles = SiteStyles(file: file)
        styles.set("body { color: red }", on: "example.com")
        styles.setScript("window.boosted = 1;", on: "example.com")
        XCTAssertNil(styles.css(on: "example.com"), "off, nothing is put on a page")
        XCTAssertNil(styles.script(on: "example.com"))

        styles.on = true
        XCTAssertEqual(styles.script(on: "example.com"), "window.boosted = 1;")
        XCTAssertNotNil(styles.css(on: "example.com"))
    }

    @MainActor
    func testRemovingASiteTakesItsScriptToo() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("styles.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let styles = SiteStyles(file: file)
        styles.on = true
        styles.set("body { color: red }", on: "example.com")
        styles.setScript("window.boosted = 1;", on: "example.com")
        styles.remove(on: "example.com")
        XCTAssertEqual(styles.hosts, [], "the site is gone from the list")
        XCTAssertNil(styles.script(on: "example.com"))
    }

    @MainActor
    func testAScriptGoesInWrapped() {
        let code = SiteStyles.scriptCode("this is not javascript {{")
        XCTAssertTrue(code.hasPrefix("(function () { try {"))
        XCTAssertTrue(code.contains("this is not javascript {{"))
        XCTAssertTrue(code.contains("catch (e)"), "a mistake in a boost is a console line, not a half-run page")
    }

    @MainActor
    func testHostIsTheOneBoostsAreKeptBy() {
        XCTAssertEqual(SiteStyles.host(of: URL(string: "https://www.Example.com/a")!), "example.com")
        XCTAssertEqual(SiteStyles.host(of: URL(string: "http://127.0.0.1:8080/page")!), "127.0.0.1")
        XCTAssertNil(SiteStyles.host(of: URL(string: "search://history")!))
    }
}
