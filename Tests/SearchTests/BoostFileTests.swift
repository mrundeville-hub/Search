import XCTest
@testable import Search

/// A boost as a file: what it says, what it refuses, and what comes back out
/// of it.
final class BoostFileTests: XCTestCase {
    private let sample = """
    {
      "format": "search-boost",
      "version": 1,
      "site": "www.Example.com",
      "css": "body { background: #111 }",
      "script": "document.body.classList.add('dark')"
    }
    """

    func testItReadsAndTidiesTheSite() throws {
        let boost = try BoostFile.read(Data(sample.utf8))
        XCTAssertEqual(boost.site, "example.com", "a host, without www., lowercase")
        XCTAssertEqual(boost.css, "body { background: #111 }")
        XCTAssertEqual(boost.script, "document.body.classList.add('dark')")
        XCTAssertEqual(boost.fileName, "example.com.boost")
    }

    func testWritingItKeepsBothHalves() throws {
        let boost = try BoostFile.read(Data(sample.utf8))
        let again = try BoostFile.read(Data(boost.json().utf8))
        XCTAssertEqual(again, boost, "what is written comes back the same")
        XCTAssertTrue(boost.json().contains("\"format\" : \"search-boost\""))
    }

    func testWhatIsNotABoost() {
        XCTAssertThrowsError(try BoostFile.read(Data("not json".utf8)))
        XCTAssertThrowsError(try BoostFile.read(Data(#"{"format":"something-else","site":"a.com","css":"x"}"#.utf8)))
        XCTAssertThrowsError(try BoostFile.read(Data(#"{"format":"search-boost","version":9,"site":"a.com","css":"x"}"#.utf8)),
                             "a file from a newer Search is refused, not half-read")
        XCTAssertThrowsError(try BoostFile.read(Data(#"{"format":"search-boost","site":"https://a.com/x","css":"x"}"#.utf8)),
                             "a boost is for a site, not an address with a path")
        XCTAssertThrowsError(try BoostFile.read(Data(#"{"format":"search-boost","site":"a.com","css":"  ","script":""}"#.utf8)),
                             "nothing in either half is not a boost")
    }

    @MainActor
    func testABoostGoesOnItsSiteAndComesBackOut() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let styles = SiteStyles(file: dir.appendingPathComponent("styles.json"))
        styles.on = true

        let boost = try BoostFile.read(Data(sample.utf8))
        let said = styles.bring(in: boost)
        XCTAssertTrue(said.contains("style and script"), said)
        XCTAssertEqual(styles.written(on: "example.com"), boost.css)
        XCTAssertEqual(styles.writtenScript(on: "example.com"), boost.script)

        let out = try XCTUnwrap(styles.boost(on: "example.com"))
        XCTAssertEqual(out.site, "example.com")
        XCTAssertEqual(out.css, boost.css)
        XCTAssertEqual(out.script, boost.script)
        XCTAssertNil(styles.boost(on: "nothing.example"), "a site with neither half has no boost")
    }

    @MainActor
    func testABoostWithOnlyAStyle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let styles = SiteStyles(file: dir.appendingPathComponent("styles.json"))
        styles.on = true

        let boost = try BoostFile.read(Data(#"{"format":"search-boost","site":"a.example","css":"p { color: red }"}"#.utf8))
        XCTAssertTrue(styles.bring(in: boost).contains("Brought in style for a.example"))
        XCTAssertEqual(styles.writtenScript(on: "a.example"), "")
    }
}
