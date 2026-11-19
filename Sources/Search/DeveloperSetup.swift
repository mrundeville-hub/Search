import AppKit
import SwiftUI

// Setting a coding agent up to use Search: the entry it needs in its own
// config, and the skill that tells it when to use it.
//
// Yab does this from Settings › Developers — one click per agent, a Copy Config
// for the rest, and Remove taking back only what it added. This is the same
// idea for Search's MCP server (search-mcp, which now ships inside the app):
// Claude Code and Codex read JSON and TOML files of their own, so what is
// written here is theirs, with a backup of what was there before.
//
// Nothing here grants anything by itself: the setting that lets agents ask is
// turned on, and every agent still asks the window, once per session, and is
// answered by a person.

enum DeveloperSetup {
    /// The name the agent sees in its own tool list: `search`.
    static let serverName = "search"

    /// The MCP server that ships with the app. Nil in a build that doesn't
    /// carry it, which is what the settings row then says.
    static var command: String? {
        Bundle.main.url(forResource: "search-mcp", withExtension: nil)?.path
    }

    enum Client: String, CaseIterable, Identifiable {
        case claudeCode = "claude_code"
        case codex

        var id: String { rawValue }

        var title: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            }
        }

        /// Where its config is, under a home folder.
        func config(in home: URL) -> URL {
            switch self {
            case .claudeCode: return home.appendingPathComponent(".claude.json")
            case .codex: return home.appendingPathComponent(".codex/config.toml")
            }
        }

        /// Where its skills are read from.
        var skillFolder: String {
            switch self {
            case .claudeCode: return ".claude/skills"
            case .codex: return ".agents/skills"
            }
        }
    }

    /// One file to write: what it was, and what it will be.
    struct Change: Equatable {
        var path: URL
        var before: String?
        var after: String
    }

    // MARK: - what goes in

    /// The entry, as the agent's config holds it.
    static func entry(command: String) -> [String: Any] {
        ["command": command, "args": [String]()]
    }

    /// The entry as JSON, for Copy Config and for a client this doesn't write.
    static func json(command: String) -> String {
        let pretty = JSONSerialization.WritingOptions.prettyPrinted.union(.sortedKeys)
        guard let data = try? JSONSerialization.data(withJSONObject: ["mcpServers": [serverName: entry(command: command)]],
                                                     options: pretty),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The TOML block Codex keeps its servers in.
    static func toml(command: String) -> String {
        """
        [mcp_servers.\(serverName)]
        command = \(quoted(command))
        args = []
        startup_timeout_sec = 30
        """
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - planning and writing

    /// Every file the client needs, as it will be: the config merged into what
    /// was there, and the skill beside it.
    static func plan(for client: Client, command: String, home: URL) throws -> [Change] {
        var changes: [Change] = []
        let config = client.config(in: home)
        let before = try? String(contentsOf: config, encoding: .utf8)
        switch client {
        case .claudeCode:
            changes.append(Change(path: config,
                                  before: before,
                                  after: try mergedJSON(before, command: command)))
        case .codex:
            changes.append(Change(path: config,
                                  before: before,
                                  after: mergedTOML(before, command: command)))
        }
        let skill = home.appendingPathComponent(client.skillFolder).appendingPathComponent("search/SKILL.md")
        changes.append(Change(path: skill,
                              before: try? String(contentsOf: skill, encoding: .utf8),
                              after: skillText))
        return changes
    }

    /// Writes every file that isn't already as it should be, keeping a copy of
    /// anything it replaces. Answers the files it touched.
    @discardableResult
    static func apply(for client: Client, command: String, home: URL) throws -> [URL] {
        var written: [URL] = []
        for change in try plan(for: client, command: command, home: home) {
            if change.before == change.after { continue }
            let folder = change.path.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let before = change.before {
                try? before.write(to: URL(fileURLWithPath: change.path.path + ".search.backup"),
                                  atomically: true, encoding: .utf8)
            }
            try change.after.write(to: change.path, atomically: true, encoding: .utf8)
            written.append(change.path)
        }
        return written
    }

    /// The home folder of the person using the app, or the one a test says.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: - the two formats

    /// `.claude.json` is one JSON object with everything else Claude Code
    /// keeps in it: only `mcpServers.search` is touched.
    static func mergedJSON(_ before: String?, command: String) throws -> String {
        var object: [String: Any] = [:]
        if let before, let data = before.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object = parsed
        }
        var servers = (object["mcpServers"] as? [String: Any]) ?? [:]
        servers[serverName] = entry(command: command)
        object["mcpServers"] = servers
        let pretty = JSONSerialization.WritingOptions.prettyPrinted.union(.sortedKeys).union(.withoutEscapingSlashes)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: pretty),
              let text = String(data: data, encoding: .utf8) else {
            throw Failure("That config isn't JSON this can read.")
        }
        return text + "\n"
    }

    /// `config.toml` is TOML: the one table is replaced where it stands, or
    /// added at the end. Everything else in the file is left as it was.
    static func mergedTOML(_ before: String?, command: String) -> String {
        let block = toml(command: command)
        guard let before, !before.isEmpty else { return block + "\n" }
        var lines = before.components(separatedBy: "\n")
        let header = "[mcp_servers.\(serverName)]"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            var text = before
            if !text.hasSuffix("\n") { text += "\n" }
            return text + "\n" + block + "\n"
        }
        // The table runs until the next table's header, or the end.
        var end = start + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
        lines.replaceSubrange(start..<end, with: block.components(separatedBy: "\n"))
        return lines.joined(separator: "\n")
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: - the skill

    /// What the agent reads to know when Search is the right tool. Kept short:
    /// the tool list it can see is the truth, and this says what the list can't.
    static let skillText = """
    ---
    name: search
    description: Use the person's own Search browser for anything on the web — open a page in their signed-in sessions, read it, click, type, or take a screenshot. Use it when a task needs a page the person is logged into, a local site, or a look at what their browser shows.
    ---

    # Search

    Search is the browser the person is using. Its MCP server gives you tabs of your own,
    in their sign-ins: the work they did signing in is not yours to redo.

    ## Work in a tab, not a copy

    1. `open_tab` with the address; it answers with a page handle (`p1`).
    2. `read_page` for the visible controls, headings and text, each with an element handle.
       Each read ends the handles of the one before it, so read again after changing the page.
    3. `click`, `type`, `press` by handle; every click is a real mouse event and every typed
       value is checked against the field afterwards.
    4. `screenshot` for what it looks like. Passwords and card fields are blacked out in it.

    ## What is not yours

    - The person's own tabs are read-only and only if they allowed it; never act in them.
    - Private tabs are never shown to you.
    - A page that asks for a password, a card or a one-time code is answered by the person.
    - The first call asks the person in Search's window. If they say no, stop and say so.

    ## Beyond the page

    `bookmarks` and `bookmark_add` read and keep addresses, `history` lists where this space
    has been lately, `spaces` and `space_switch` move the window between spaces. Use them
    only when the task is about the person's browsing, not as a shortcut around a page.

    ## When to reach for it

    Use Search when the answer lives behind a sign-in you don't have, on localhost, or in a
    page that only exists in their browser. For a public page you can simply fetch, fetching
    is cheaper — don't spend a tab on it.
    """
}

// MARK: - the two controls

/// "Set Up" beside the words of a row: writes the entry, then says what to do.
struct DeveloperButton: View {
    let client: DeveloperSetup.Client
    let prefs: Preferences

    @State private var said: String?

    var body: some View {
        HStack(spacing: 8) {
            if let said {
                Text(said)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            Pill("Set Up", filled: true) { write() }
        }
    }

    private func write() {
        guard let command = DeveloperSetup.command else {
            said = "This build has no MCP server inside it."
            return
        }
        do {
            let written = try DeveloperSetup.apply(for: client, command: command, home: DeveloperSetup.home)
            // Nothing is granted by writing a file: the setting still has to be
            // on for the socket to exist, and the agent still asks the window.
            prefs.agents = true
            said = written.isEmpty ? "Already set up." : "Done — restart \(client.title)."
        } catch {
            said = error.localizedDescription
        }
    }
}

/// "Copy the agent config": the entry, on the clipboard, for a client that
/// isn't written for.
struct CopyAgentConfig: View {
    @State private var said: String?

    var body: some View {
        HStack(spacing: 8) {
            if let said {
                Text(said)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
            Pill("Copy") {
                guard let command = DeveloperSetup.command else {
                    said = "This build has no MCP server inside it."
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(DeveloperSetup.json(command: command), forType: .string)
                said = "Copied."
            }
        }
    }
}
