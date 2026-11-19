import AppKit
import Foundation
import SwiftUI

// Snippets: short names for things you type often, put into a page's boxes as
// you type — `;sig` and a space, and the signature is there.
//
// Yab has these (its docs/snippets.md): the same list, offered under the caret
// as you type a name and taken in with Return or Tab, brought in from Text
// Replacements, Alfred, espanso and Raycast, and working in Mail too. This is
// the plain half of it: a list of your own, a name taken in with a space or Tab
// in any box on a page that isn't for a password or a code, and nothing else.
// No list under the caret, no import, nothing in the address field yet.
//
// Off until Settings › Browsing › Pages › "Snippets in a page's boxes". Kept in
// snippets.json beside the other small files.

struct Snippet: Codable, Equatable, Identifiable {
    var name: String
    var text: String
    var id: String { name }

    /// What a name may be: letters, numbers, a dash and an underscore, so a
    /// `;name` is one token and nothing else.
    static func tidyName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(32)
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

@MainActor
final class Snippets: ObservableObject {
    static let shared = Snippets(file: Store.file("snippets.json"))

    /// Settings › Browsing › Pages. Off, pages get nothing at all.
    static var on = false

    /// In the order they were added.
    @Published private(set) var all: [Snippet] = []

    private let file: URL

    init(file: URL) {
        self.file = file
        load()
    }

    var byName: [String: String] {
        var out: [String: String] = [:]
        for snippet in all { out[snippet.name] = snippet.text }
        return out
    }

    /// Adds one, or replaces the one that had its name. Answers nil when there
    /// is nothing to keep: no name, or nothing to put in.
    @discardableResult
    func add(name: String, text: String) -> Snippet? {
        let name = Snippet.tidyName(name)
        guard !name.isEmpty else { return nil }
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        guard let kept else { return nil }
        let snippet = Snippet(name: name, text: kept)
        all.removeAll { $0.name == name }
        all.append(snippet)
        save()
        return snippet
    }

    func remove(_ name: String) {
        all.removeAll { $0.name == name }
        save()
    }

    /// What goes into a page: the list as one object of name to text, in a
    /// script that takes a name in when a space or Tab follows it. Nothing is
    /// put in when the setting is off or the list is empty.
    func script() -> String? {
        guard Snippets.on, !all.isEmpty else { return nil }
        let library = byName
        guard let data = try? JSONSerialization.data(withJSONObject: library, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "(\(Snippets.take))\n(\(json));"
    }

    /// The page's half. A box's value is read before the caret only; a name
    /// that matches is replaced through `insertText`, so the page's own undo
    /// takes it back in one step, and the input event that follows is not
    /// mistaken for another name.
    static let take = """
    function (snippets) {
      if (!snippets || Object.keys(snippets).length === 0) return;
      var NAME = /;([A-Za-z0-9_-]{1,32})/;

      function box(el) {
        if (!el || el.__searchSnippetBusy) return null;
        if (el.tagName === 'INPUT') {
          var type = (el.type || 'text').toLowerCase();
          if (!/^(text|search|url|email|tel)$/.test(type)) return null;
          if (el.autocomplete && /one-time-code/.test(el.autocomplete)) return null;
          return el;
        }
        if (el.tagName === 'TEXTAREA') return el;
        return null;
      }

      function replace(el, from, to, text) {
        el.__searchSnippetBusy = true;
        try {
          el.focus();
          if (el.setSelectionRange) el.setSelectionRange(from, to);
          var done = false;
          try { done = document.execCommand('insertText', false, text); } catch (e) { done = false; }
          if (!done) {
            var next = el.value.slice(0, from) + text + el.value.slice(to);
            var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value');
            if (setter && setter.set) setter.set.call(el, next); else el.value = next;
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
        } finally {
          el.__searchSnippetBusy = false;
        }
      }

      // `;name` and a space, as it is typed: the token goes, the text stays.
      document.addEventListener('input', function (event) {
        var el = box(event.target);
        if (!el || el.selectionStart == null) return;
        var before = el.value.slice(0, el.selectionStart);
        var match = NAME.exec(before);
        if (!match) return;
        var ending = before.slice(match.index + match[0].length);
        if (!/^[ \\t]$/.test(ending)) return;
        var text = snippets[match[1]];
        if (!text) return;
        var start = match.index;
        var end = match.index + match[0].length + ending.length;
        replace(el, start, end, text);
      }, true);

      // `;name` and Tab, before the space is ever typed.
      document.addEventListener('keydown', function (event) {
        if (event.key !== 'Tab' || event.shiftKey) return;
        var el = box(event.target);
        if (!el || el.selectionStart == null) return;
        var caret = el.selectionStart;
        if (caret !== el.selectionEnd) return;
        var before = el.value.slice(0, caret);
        var match = /;([A-Za-z0-9_-]{1,32})$/.exec(before);
        if (!match) return;
        var text = snippets[match[1]];
        if (!text) return;
        event.preventDefault();
        replace(el, caret - match[0].length, caret, text);
      }, true);
    }
    """

    // MARK: - the file

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let kept = try? JSONDecoder().decode([Snippet].self, from: data) else { return }
        all = kept
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - the page that keeps them

/// search://snippets, and View › Snippets…: the list, and the two fields that
/// add to it.
struct SnippetsPanel: View {
    @ObservedObject private var snippets = Snippets.shared

    @State private var name = ""
    @State private var text = ""

    private var problem: String? {
        let tidy = Snippet.tidyName(name)
        if name.isEmpty { return nil }
        if tidy.isEmpty { return "A name is letters, numbers, a dash and an underscore." }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return nil
    }

    private var canAdd: Bool {
        !Snippet.tidyName(name).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Plate("Snippets", width: 620, close: {}) {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A name to type, and what it stands for")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            Text(";")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Palette.faint)
                            TextField("sig", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 120)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1))
                            TextField("Best,\nMussa", text: $text, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .lineLimit(1...3)
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1))
                            Pill("Add", filled: true) {
                                add()
                            }
                            .disabled(!canAdd)
                        }
                        if let problem {
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.red)
                        }
                        Text("Type the name in any box on a page and press space or Tab.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(14)
                }

                if snippets.all.isEmpty {
                    Card { Nothing("Nothing yet. A snippet is a name and the text it stands for.") }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(snippets.all.enumerated()), id: \.element.id) { index, snippet in
                                VStack(spacing: 0) {
                                    if index > 0 { Rule() }
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(";\(snippet.name)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(Palette.ink)
                                            .frame(width: 120, alignment: .leading)
                                        Text(snippet.text)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Quick("Remove", tint: .red) { snippets.remove(snippet.name) }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                        .background(Palette.ground)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1))
                    }
                    .listHeight(420)
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Text(snippets.all.count == 1 ? "1 snippet" : "\(snippets.all.count) snippets")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Pill("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.file("snippets.json")]) }
            }
        }
    }

    private func add() {
        guard snippets.add(name: name, text: text) != nil else { return }
        name = ""
        text = ""
    }
}
