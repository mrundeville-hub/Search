import WebKit
import XCTest
@testable import Search

/// Reading a `.user.js`, where it is allowed to run, and keeping it.
final class UserscriptsTests: XCTestCase {
    private let sample = """
    // ==UserScript==
    // @name        Darker GitHub
    // @namespace   example.com/darker
    // @version     1.2.0
    // @description Makes github.com darker.
    // @match       https://github.com/*
    // @match       https://*.github.com/*
    // @exclude     https://gist.github.com/*
    // @run-at      document-start
    // @noframes
    // ==/UserScript==

    document.documentElement.style.filter = 'invert(1)';
    """

    func testHeaderIsRead() throws {
        let script = try Userscript.read(sample)
        XCTAssertEqual(script.name, "Darker GitHub")
        XCTAssertEqual(script.namespace, "example.com/darker")
        XCTAssertEqual(script.version, "1.2.0")
        XCTAssertEqual(script.summary, "Makes github.com darker.")
        XCTAssertEqual(script.matches.count, 2)
        XCTAssertEqual(script.excludes, ["https://gist.github.com/*"])
        XCTAssertTrue(script.noFrames)
        XCTAssertEqual(script.runAt, .atDocumentStart)
        XCTAssertEqual(script.code, sample, "the file goes in as written, header and all")
    }

    func testLooks() {
        XCTAssertTrue(Userscript.looks(sample))
        XCTAssertFalse(Userscript.looks("console.log('not a userscript')"))
    }

    func testReadRefusesWhatIsNotAUserscript() {
        XCTAssertThrowsError(try Userscript.read("console.log(1)"))
        XCTAssertThrowsError(try Userscript.read("// ==UserScript==\n// @match *://*\n// ==/UserScript=="),
                             "a header with no @name is not a script")
    }

    func testNoPatternsMeansEverywhere() throws {
        let script = try Userscript.read("""
        // ==UserScript==
        // @name Everywhere
        // ==/UserScript==
        """)
        XCTAssertTrue(script.runs(at: URL(string: "https://example.com/a")!))
        XCTAssertTrue(script.runs(at: URL(string: "http://localhost:8080/b")!))
        XCTAssertFalse(script.runs(at: URL(string: "about:blank")!))
    }

    func testMatchPatterns() throws {
        let script = try Userscript.read(sample)
        XCTAssertTrue(script.runs(at: URL(string: "https://github.com/o/r")!))
        XCTAssertTrue(script.runs(at: URL(string: "https://api.github.com/repos")!))
        XCTAssertTrue(script.runs(at: URL(string: "https://gist.github.com/")!) == false,
                      "an @exclude wins over the @match that would have included it")
        XCTAssertFalse(script.runs(at: URL(string: "https://notgithub.com/")!))
        XCTAssertFalse(script.runs(at: URL(string: "https://github.com.evil.test/")!),
                       "a trailing part of the host is not the host")
    }

    func testIncludeGlobAndRegex() throws {
        let glob = try Userscript.read("""
        // ==UserScript==
        // @name Glob
        // @include https://example.*/page*
        // ==/UserScript==
        """)
        XCTAssertTrue(glob.runs(at: URL(string: "https://example.co.uk/page/2")!))
        XCTAssertFalse(glob.runs(at: URL(string: "https://example.co.uk/other")!))

        let regex = try Userscript.read("""
        // ==UserScript==
        // @name Regex
        // @include /^https:\\/\\/example\\.com\\/(a|b)\\/?$/
        // ==/UserScript==
        """)
        XCTAssertTrue(regex.runs(at: URL(string: "https://example.com/a")!))
        XCTAssertFalse(regex.runs(at: URL(string: "https://example.com/c")!))
    }

    func testAllURLs() throws {
        let script = try Userscript.read("""
        // ==UserScript==
        // @name Everywhere with file
        // @match <all_urls>
        // ==/UserScript==
        """)
        XCTAssertTrue(script.runs(at: URL(string: "https://example.com/")!))
        XCTAssertTrue(script.runs(at: URL(string: "file:///Users/someone/page.html")!))
    }

    @MainActor
    func testStoreKeepsTogglesAcrossLoads() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscripts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = Userscripts(file: file)
        let installed = try store.install(sample)
        XCTAssertEqual(store.all.count, 1)
        XCTAssertTrue(store.isEnabled(installed))

        // Read again, as the app does at launch.
        let again = Userscripts(file: file)
        XCTAssertEqual(again.all.map(\.name), ["Darker GitHub"])
        XCTAssertTrue(again.isEnabled(again.all[0]))

        again.setEnabled(false, for: again.all[0])
        let off = Userscripts(file: file)
        XCTAssertFalse(off.isEnabled(off.all[0]), "off survives a relaunch")

        off.remove(off.all[0])
        XCTAssertTrue(Userscripts(file: file).all.isEmpty)
    }

    @MainActor
    func testInstallingAgainReplacesAndStaysOn() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscripts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = Userscripts(file: file)
        let first = try store.install(sample)
        store.setEnabled(false, for: first)
        try store.install(sample.replacingOccurrences(of: "1.2.0", with: "1.3.0"))
        XCTAssertEqual(store.all.count, 1, "same name and namespace is the same script")
        XCTAssertEqual(store.all[0].version, "1.3.0")
        XCTAssertTrue(store.isEnabled(store.all[0]), "installing again turns it on")
    }

    @MainActor
    func testScriptsForAPage() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscripts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = Userscripts(file: file)
        let script = try store.install(sample)

        XCTAssertEqual(store.scripts(for: URL(string: "https://github.com/x")).count, 1)
        XCTAssertEqual(store.scripts(for: URL(string: "https://example.com/")).count, 0)

        store.setEnabled(false, for: script)
        XCTAssertEqual(store.scripts(for: URL(string: "https://github.com/x")).count, 0)
    }
}
