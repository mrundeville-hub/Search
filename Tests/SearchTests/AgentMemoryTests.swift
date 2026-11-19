import XCTest
@testable import Search

/// The notebook an agent keeps: keys, finding them again, and the limits.
final class AgentMemoryTests: XCTestCase {
    @MainActor
    private func memory() -> (AgentMemory, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (AgentMemory(file: dir.appendingPathComponent("agent-memory.json")), dir)
    }

    @MainActor
    func testANoteIsKeptAndFoundAgain() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = memory.write("The person's dev server runs on :3000", key: "dev-server")
        XCTAssertEqual(note?.key, "dev-server")
        XCTAssertEqual(memory.read("dev-server").first?.text, "The person's dev server runs on :3000")

        let again = AgentMemory(file: dir.appendingPathComponent("agent-memory.json"))
        XCTAssertEqual(again.read("dev-server").first?.text, "The person's dev server runs on :3000",
                       "it is there in the next session")
    }

    @MainActor
    func testWithoutAKeyOneIsMadeFromTheWords() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = memory.write("Staging is behind Cloudflare Access!")
        XCTAssertEqual(note?.key, "staging-is-behind-cloudflare-access", "the first words, as a key")
        XCTAssertEqual(memory.read("staging-is-behind-cloudflare-access").count, 1)
        XCTAssertEqual(memory.read().count, 1, "no key reads them all")
    }

    @MainActor
    func testTheSameKeyReplacesAndSearchNarrows() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        memory.write("first", key: "site")
        memory.write("the checkout uses a test card 4242", key: "site")
        XCTAssertEqual(memory.read().count, 1, "one note per key")
        XCTAssertEqual(memory.read("site").first?.text, "the checkout uses a test card 4242")

        memory.write("The other site wants a login", key: "other")
        XCTAssertEqual(memory.search("checkout card").count, 1)
        XCTAssertEqual(memory.search("site").count, 2, "both mention the word")
        XCTAssertEqual(memory.search("nothing-like-this").count, 0)
        XCTAssertEqual(memory.search("").count, 2, "no words finds everything")
    }

    @MainActor
    func testEmptyNotesAndOddKeys() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(memory.write("   "))
        XCTAssertEqual(memory.write("x", key: "   ")?.key, "x",
                       "a key of spaces is no key, so one is made from the words")

        let note = memory.write("Some text", key: "My Key/With Spaces")
        XCTAssertEqual(note?.key, "my-key-with-spaces", "a key is tidied into words and dashes")
        XCTAssertNotNil(memory.write(String(repeating: "a", count: 9_000), key: "long"))
        XCTAssertEqual(memory.read("long").first?.text.count, AgentMemory.textCap, "a note is cut at its cap")
    }

    @MainActor
    func testTheOldestGoesWhenItIsFull() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        for index in 0..<(AgentMemory.cap + 3) {
            memory.write("note \(index)", key: "note-\(index)")
        }
        XCTAssertEqual(memory.notes.count, AgentMemory.cap)
        XCTAssertTrue(memory.read("note-0").isEmpty, "the oldest went")
        XCTAssertFalse(memory.read("note-\(AgentMemory.cap + 2)").isEmpty, "the newest is there")
    }

    @MainActor
    func testForgettingOneAndEverything() {
        let (memory, dir) = memory()
        defer { try? FileManager.default.removeItem(at: dir) }

        memory.write("one", key: "one")
        memory.write("two", key: "two")
        XCTAssertTrue(memory.forget("one"))
        XCTAssertFalse(memory.forget("one"), "forgetting what isn't there says so")
        XCTAssertEqual(memory.read().count, 1)

        memory.forgetEverything()
        XCTAssertTrue(AgentMemory(file: dir.appendingPathComponent("agent-memory.json")).read().isEmpty,
                      "emptied for good")
    }
}
