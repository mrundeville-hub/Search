import Foundation
import SwiftUI

// Notes a coding agent keeps for itself: what it learned about this Mac, this
// person's setup, a site, a task — so the next session starts where the last
// one ended instead of asking again. Yab's agents have the same (its memory_*
// tools); Search's had nothing that outlived a session.
//
// It is the agent's notebook, not the person's data: nothing of theirs is read
// to write it, and the notes are a small JSON file in Search's own folder that
// the person can read or empty. Kept short on purpose — a notebook is for what
// is worth remembering, not a log: 200 notes, 4,000 characters each, and the
// oldest goes when the two hundred and first comes.

struct AgentNote: Codable, Equatable, Identifiable {
    var key: String
    var text: String
    var date: Date

    var id: String { key }
}

@MainActor
final class AgentMemory {
    static let shared = AgentMemory(file: Store.file("agent-memory.json"))

    /// The most notes kept, and the most one may say.
    static let cap = 200
    static let textCap = 4_000
    /// The longest key worth having.
    static let keyCap = 64

    private(set) var notes: [AgentNote] = []
    private let file: URL

    init(file: URL) {
        self.file = file
        load()
    }

    /// Newest first.
    var all: [AgentNote] { notes.sorted { $0.date > $1.date } }

    /// Keeps a note: under the key it was given, or one made from its first
    /// words, replacing whatever had that key. Answers what is kept.
    @discardableResult
    func write(_ text: String, key: String? = nil) -> AgentNote? {
        let said = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentMemory.textCap))
        guard !said.isEmpty else { return nil }
        let name = AgentMemory.tidy(key) ?? AgentMemory.slug(said)
        let note = AgentNote(key: name, text: said, date: Date())
        notes.removeAll { $0.key == name }
        notes.append(note)
        // The oldest goes when the notebook is full.
        while notes.count > AgentMemory.cap {
            guard let oldest = notes.min(by: { $0.date < $1.date }) else { break }
            notes.removeAll { $0.key == oldest.key }
        }
        save()
        return note
    }

    /// One note by its key, or all of them, newest first.
    func read(_ key: String? = nil) -> [AgentNote] {
        guard let name = AgentMemory.tidy(key) else { return all }
        return all.filter { $0.key == name }
    }

    /// Every note carrying all of the words, anywhere.
    func search(_ words: String) -> [AgentNote] {
        let wanted = words.lowercased().split(separator: " ").map(String.init)
        guard !wanted.isEmpty else { return all }
        return all.filter { note in
            let haystack = (note.key + " " + note.text).lowercased()
            return wanted.allSatisfy { haystack.contains($0) }
        }
    }

    func forget(_ key: String) -> Bool {
        guard let name = AgentMemory.tidy(key) else { return false }
        let before = notes.count
        notes.removeAll { $0.key == name }
        guard notes.count != before else { return false }
        save()
        return true
    }

    /// Everything, for a person emptying the notebook.
    func forgetEverything() {
        notes.removeAll()
        save()
    }

    /// A key as it is kept: lowercase words, dashes between, short.
    static func tidy(_ key: String?) -> String? {
        guard let key else { return nil }
        let slug = slug(key)
        return slug.isEmpty ? nil : String(slug.prefix(keyCap))
    }

    /// The first few words of a note, as a key: enough to find it by, and to
    /// recognise in a list.
    static func slug(_ text: String) -> String {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(6)
            .map(String.init)
        return words.joined(separator: "-")
    }

    // MARK: - the file

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file),
              let kept = try? decoder.decode([AgentNote].self, from: data) else { return }
        notes = kept
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notes) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - the person's side

/// "Notes coding agents kept": how many, and a way to empty them.
struct AgentMemoryControl: View {
    @State private var count = AgentMemory.shared.notes.count
    @State private var said: String?

    var body: some View {
        HStack(spacing: 8) {
            if let said {
                Text(said)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            } else {
                Text(count == 1 ? "1 note" : "\(count) notes")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
            Pill("Clear") {
                AgentMemory.shared.forgetEverything()
                count = AgentMemory.shared.notes.count
                said = "Emptied."
            }
            .disabled(count == 0)
        }
        .onAppear { count = AgentMemory.shared.notes.count }
    }
}
