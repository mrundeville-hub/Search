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

    func testAnAddressIsToldFromAScript() {
        XCTAssertNotNil(Userscript.address("https://example.com/tools/darker.user.js"))
        XCTAssertNotNil(Userscript.address("  http://localhost:8000/x.user.js  "))
        XCTAssertNil(Userscript.address("// ==UserScript==\n// @name x"))
        XCTAssertNil(Userscript.address("document.body.style.background = 'red'"))
        XCTAssertNil(Userscript.address("file:///Users/someone/x.user.js"), "nothing is fetched from the disk by the panel")
        XCTAssertNil(Userscript.address(""))
    }

    func testThePagesAddressIsOne() {
        XCTAssertEqual(InternalPage(url: URL(string: "search://userscripts")!)?.kind, .userscripts)
        XCTAssertEqual(InternalPage(.userscripts).url.absoluteString, "search://userscripts")
    }


    func testAScriptThatAsksForGMCallsIsToldSo() throws {
        let granted = try Userscript.read("""
        // ==UserScript==
        // @name Grants
        // @grant GM_setValue
        // ==/UserScript==
        """)
        XCTAssertTrue(granted.wantsGM)

        let plain = try Userscript.read("""
        // ==UserScript==
        // @name Plain
        // @grant none
        // ==/UserScript==
        document.body.append('hello');
        """)
        XCTAssertFalse(plain.wantsGM)

        let silent = try Userscript.read("""
        // ==UserScript==
        // @name Silent
        // ==/UserScript==
        const kept = GM_getValue('k', 1);
        """)
        XCTAssertTrue(silent.wantsGM, "one that calls them without a @grant gets them too")
    }

    func testTheBootCarriesTheScriptAndItsValues() throws {
        let script = try Userscript.read("""
        // ==UserScript==
        // @name "Quoted" name
        // @namespace bench
        // @grant GM_getValue
        // ==/UserScript==
        document.title = GM_getValue('greeting', 'none');
        """)
        let boot = Userscript.boot(script: script, values: ["greeting": "hi \"there\""],
                                   handler: Userscripts.handler)
        XCTAssertTrue(boot.contains(#""greeting":"hi \"there\"""#), "the value goes in as JSON, escaped")
        XCTAssertTrue(boot.contains("document.title = GM_getValue"), "the script runs inside the boot")
        XCTAssertTrue(boot.contains("officeUserscript"), "the channel it writes on is named")
        XCTAssertTrue(boot.contains(#"\"Quoted\" name"#), "the header's quoting doesn't break the boot")
    }

    @MainActor
    func testValuesAreKeptPerScriptAndSurvive() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscript-values-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("userscript-values.json")

        let values = UserscriptValues(file: file)
        values.set("hi", for: "greeting", script: "one")
        values.set(42.0, for: "count", script: "one")
        values.set("other", for: "greeting", script: "two")
        values.set(["nested": ["a": 1.0]] as [String: Any], for: "tree", script: "one")

        XCTAssertEqual(values.read("one")["greeting"] as? String, "hi")
        XCTAssertEqual(values.read("two")["greeting"] as? String, "other", "two scripts never share values")
        XCTAssertEqual((values.read("one")["tree"] as? [String: Any])?["nested"] as? [String: Double], ["a": 1])

        let again = UserscriptValues(file: file)
        XCTAssertEqual(again.read("one")["count"] as? Double, 42, "a value is there at the next launch")

        again.remove("greeting", script: "one")
        XCTAssertNil(again.read("one")["greeting"])
        XCTAssertNotNil(again.read("two")["greeting"], "removing one script's key leaves the other's")
    }


    func testRequireLinesAreRead() throws {
        let script = try Userscript.read("""
        // ==UserScript==
        // @name Needs files
        // @require https://example.com/a.js
        // @require https://example.com/b.js
        // ==/UserScript==
        window.a = 1;
        """)
        XCTAssertEqual(script.requireURLs, ["https://example.com/a.js", "https://example.com/b.js"])
        XCTAssertEqual(script.requiresCode, "", "nothing is fetched at read time")
        XCTAssertEqual(Userscript.sha256(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @MainActor
    func testInstallingFromAnAddressBringsItsRequiredFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscripts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("userscripts.json")

        let helper = "window.__helper = 'loaded';"
        let store = Userscripts(file: file, fetch: { address in
            if address.path == "/tool.user.js" {
                return Data("""
                // ==UserScript==
                // @name Bench tool
                // @namespace bench
                // @require http://127.0.0.1:9/helper.js
                // @match http://127.0.0.1/*
                // ==/UserScript==
                document.title = window.__helper || 'missing';
                """.utf8)
            }
            return Data(helper.utf8)
        })

        let script = try await store.install(from: URL(string: "http://127.0.0.1:9/tool.user.js")!)
        XCTAssertEqual(script.requires.count, 1)
        XCTAssertEqual(script.requires[0].url, "http://127.0.0.1:9/helper.js")
        XCTAssertEqual(script.requires[0].text, helper)
        XCTAssertEqual(script.requires[0].sha256, Userscript.sha256(Data(helper.utf8)),
                       "each file is pinned by its own hash")

        let injected = store.scripts(for: URL(string: "http://127.0.0.1:9/page")!)
        XCTAssertEqual(injected.count, 1)
        XCTAssertTrue(injected[0].source.contains("window.__helper = 'loaded';"),
                      "the required file goes in ahead of the script")
        XCTAssertTrue(injected[0].source.contains("document.title = window.__helper"))

        // A required file that can't be had means the script isn't installed half-formed.
        let strict = Userscripts(file: folder.appendingPathComponent("other.json"), fetch: { _ in
            throw Userscript.Invalid("nope")
        })
        do {
            _ = try await strict.install(from: URL(string: "http://127.0.0.1:9/tool.user.js")!)
            XCTFail("an install with an unreachable @require should fail")
        } catch let error as Userscript.Invalid {
            XCTAssertTrue(error.message.contains("nope"), error.message)
        }
        XCTAssertTrue(strict.all.isEmpty)
    }

    @MainActor
    func testRequiredFilesSurviveARelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("userscripts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("userscripts.json")

        let store = Userscripts(file: file, fetch: { address in
            address.path == "/tool.user.js"
                ? Data("// ==UserScript==\n// @name Tool\n// @require http://x/y.js\n// @match *://*/*\n// ==/UserScript==\nwindow.z = 1;\n".utf8)
                : Data("window.y = 2;".utf8)
        })
        _ = try await store.install(from: URL(string: "http://x/tool.user.js")!)

        let again = Userscripts(file: file)
        XCTAssertEqual(again.all.count, 1)
        XCTAssertEqual(again.all[0].requires.map(\.text), ["window.y = 2;"],
                       "the fetched file is kept with the script, not fetched again")
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
