import XCTest
@testable import Search

/// Setting a coding agent up: the file it needs, what was there kept, and a
/// second run that changes nothing.
final class DeveloperSetupTests: XCTestCase {
    private func home() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("developers-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let command = "/Applications/Search.app/Contents/Resources/search-mcp"

    func testClaudesEntryKeepsWhatWasThere() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".claude.json")
        try """
        {"numStartups": 41, "mcpServers": {"other": {"command": "/usr/bin/other"}}}
        """.write(to: config, atomically: true, encoding: .utf8)

        let written = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        XCTAssertEqual(written, [config, dir.appendingPathComponent(".claude/skills/search/SKILL.md")])

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertEqual(object?["numStartups"] as? Int, 41, "Claude Code's own keys are untouched")
        let servers = object?["mcpServers"] as? [String: Any]
        XCTAssertNotNil(servers?["other"], "another server stays")
        let entry = servers?["search"] as? [String: Any]
        XCTAssertEqual(entry?["command"] as? String, command)
        XCTAssertEqual(entry?["args"] as? [String], [])

        let backup = dir.appendingPathComponent(".claude.json.search.backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "what was there is kept")
    }

    func testClaudeWithoutAConfig() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        let config = dir.appendingPathComponent(".claude.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertEqual((object?["mcpServers"] as? [String: Any])?["search"] as? [String: Any] != nil, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path + ".search.backup"),
                       "nothing to back up, nothing kept")
    }

    func testAThingThatIsNotJSONIsNotOverwritten() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".claude.json")
        try "this is not json".write(to: config, atomically: true, encoding: .utf8)
        // A file that can't be read as JSON starts again as an object: the old
        // text is kept beside it, and nothing is lost.
        _ = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(".claude.json.search.backup"), encoding: .utf8),
                       "this is not json")
    }

    func testCodicesTableIsAddedAndThenReplaced() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/usr/bin/other"
        """.write(to: config, atomically: true, encoding: .utf8)

        _ = try DeveloperSetup.apply(for: .codex, command: command, home: dir)
        var text = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(text.contains("model = \"gpt-5\""), "the rest of the file is untouched")
        XCTAssertTrue(text.contains("[mcp_servers.other]"))
        XCTAssertTrue(text.contains("[mcp_servers.search]"))
        XCTAssertTrue(text.contains(command))

        // A second run with another path replaces the table rather than adding
        // a second one.
        let moved = "/tmp/elsewhere/search-mcp"
        _ = try DeveloperSetup.apply(for: .codex, command: moved, home: dir)
        text = try String(contentsOf: config, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "[mcp_servers.search]").count, 2, "one table, not two")
        XCTAssertTrue(text.contains(moved))
        XCTAssertFalse(text.contains(command), "the old path is gone")
    }

    func testTheSkillIsWrittenForBoth() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try DeveloperSetup.apply(for: .codex, command: command, home: dir)
        let skill = dir.appendingPathComponent(".agents/skills/search/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\nname: search"), "a skill starts with its front matter")
        XCTAssertTrue(text.contains("read_page"))
        XCTAssertTrue(text.contains("Private tabs are never shown"))
    }

    func testASecondRunWritesNothing() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        let again = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        XCTAssertEqual(again, [], "nothing changed, so nothing is written")
    }

    func testTheCopiedConfigIsTheEntry() throws {
        let text = DeveloperSetup.json(command: command)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let entry = (object?["mcpServers"] as? [String: Any])?["search"] as? [String: Any]
        XCTAssertEqual(entry?["command"] as? String, command)
    }

    // MARK: - taking it back

    func testRemovingClaudesEntryKeepsEverythingElse() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        let report = DeveloperSetup.remove(for: .claudeCode, command: command, home: dir)
        XCTAssertTrue(report.kept.isEmpty, report.kept.joined())

        let config = dir.appendingPathComponent(".claude.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertNil((object?["mcpServers"] as? [String: Any])?["search"], "the entry is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".claude/skills/search/SKILL.md").path))
    }

    func testAnEntryPointingElsewhereIsLeftAlone() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".claude.json")
        try """
        {"mcpServers": {"search": {"command": "/somewhere/else/search-mcp", "args": []}}}
        """.write(to: config, atomically: true, encoding: .utf8)

        let report = DeveloperSetup.remove(for: .claudeCode, command: command, home: dir)
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(report.kept.count, 1)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertNotNil((object?["mcpServers"] as? [String: Any])?["search"], "someone else's entry stays")
    }

    func testCodicesTableGoesAndTheRestStays() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/usr/bin/other"
        """.write(to: config, atomically: true, encoding: .utf8)

        _ = try DeveloperSetup.apply(for: .codex, command: command, home: dir)
        let report = DeveloperSetup.remove(for: .codex, command: command, home: dir)
        XCTAssertEqual(report.removed.count, 2, "the table and the skill")
        let text = try String(contentsOf: config, encoding: .utf8)
        XCTAssertFalse(text.contains("[mcp_servers.search]"))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[mcp_servers.other]"))
        XCTAssertFalse(text.hasSuffix("\n\n"), "no blank line left where the table was")
    }

    func testAnEditedSkillStays() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try DeveloperSetup.apply(for: .claudeCode, command: command, home: dir)
        let skill = dir.appendingPathComponent(".claude/skills/search/SKILL.md")
        try (DeveloperSetup.skillText + "\nMy own note.\n").write(to: skill, atomically: true, encoding: .utf8)

        let report = DeveloperSetup.remove(for: .claudeCode, command: command, home: dir)
        XCTAssertEqual(report.kept.count, 1, report.kept.joined())
        XCTAssertTrue(FileManager.default.fileExists(atPath: skill.path), "a skill someone changed is theirs")
    }

    func testRemovingWhatWasNeverThereDoesNothing() throws {
        let dir = home()
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = DeveloperSetup.remove(for: .claudeCode, command: command, home: dir)
        XCTAssertTrue(report.isEmpty, report.said)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".claude.json").path),
                       "nothing was created to remove from")
    }
}
