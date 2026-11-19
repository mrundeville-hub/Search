import XCTest
@testable import Search

/// Snippets: the list, the names, and the script a page gets.
final class SnippetsTests: XCTestCase {
    @MainActor
    private func store() -> (Snippets, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (Snippets(file: dir.appendingPathComponent("snippets.json")), dir)
    }

    @MainActor
    func testAddingAndKeeping() {
        let (snippets, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNotNil(snippets.add(name: "sig", text: "Best,\nMussa"))
        XCTAssertEqual(snippets.byName["sig"], "Best,\nMussa")

        let again = Snippets(file: dir.appendingPathComponent("snippets.json"))
        XCTAssertEqual(again.byName, ["sig": "Best,\nMussa"], "the list is there at the next launch")
    }

    @MainActor
    func testANameIsOneToken() {
        let (snippets, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(Snippet.tidyName("  sig! "), "sig", "punctuation is not part of a name")
        XCTAssertEqual(Snippet.tidyName("my-name_2"), "my-name_2")
        XCTAssertNil(snippets.add(name: "!!!", text: "nothing to name it"), "a name with nothing left is no name")
        XCTAssertNil(snippets.add(name: "sig", text: "   "), "nothing to say is no snippet")
        XCTAssertTrue(snippets.all.isEmpty)
    }

    @MainActor
    func testTheSameNameReplaces() {
        let (snippets, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }

        snippets.add(name: "sig", text: "first")
        snippets.add(name: "sig", text: "second")
        XCTAssertEqual(snippets.all.count, 1)
        XCTAssertEqual(snippets.byName["sig"], "second")

        snippets.remove("sig")
        XCTAssertTrue(snippets.all.isEmpty)
    }

    @MainActor
    func testNothingGoesIntoAPageUntilTheSettingSaysSo() {
        let (snippets, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }

        snippets.add(name: "sig", text: "Best,\nMussa")
        Snippets.on = false
        XCTAssertNil(snippets.script(), "off, pages get nothing")

        Snippets.on = true
        let script = try? XCTUnwrap(snippets.script())
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("\"sig\":\"Best,\\nMussa\"") == true,
                      "the text travels as JSON, newline and all")
        XCTAssertTrue(script?.contains("addEventListener") == true)
        Snippets.on = false
    }

    @MainActor
    func testAnEmptyListPutsNothingIn() {
        let (snippets, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        Snippets.on = true
        XCTAssertNil(snippets.script())
        Snippets.on = false
    }

    func testQuotesInASnippetCannotBreakTheScript() {
        let text = "He said \"hi\" \\ and `that`"
        guard let data = try? JSONSerialization.data(withJSONObject: ["q": text], options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return XCTFail("no JSON")
        }
        XCTAssertTrue(json.contains("\\\"hi\\\""), "a quote is escaped, so the object still parses")
    }
}
