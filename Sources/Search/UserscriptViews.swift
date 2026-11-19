import AppKit
import SwiftUI

// The page that installs, lists and turns off userscripts: search://userscripts,
// and View › Userscripts…. A tab of its own, as Search's other own pages are
// (see InternalPages.swift), so it can sit beside the page a script is for.

struct UserscriptsPanel: View {
    @ObservedObject private var store = Userscripts.shared

    /// What was pasted or typed: a `.user.js` file's text, or the address of one.
    @State private var draft = ""
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        Plate("Userscripts", width: 620, close: {}) {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paste a script, or the address of one")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            TextField("A .user.js file's text, or https://…", text: $draft, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .lineLimit(1...4)
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Palette.hairline, lineWidth: 1)
                                )
                                .onSubmit { add() }
                            Pill("Add", filled: true) { add() }
                                .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Pill("Paste") { pasteAndAdd() }
                                .disabled(busy)
                        }
                        if busy {
                            Text("Fetching…")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.muted)
                        }
                        if let problem {
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                }

                if store.all.isEmpty {
                    Card { Nothing("Nothing installed yet. A script you add runs on the pages its own header asks for.") }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.all.enumerated()), id: \.element.id) { index, script in
                                VStack(spacing: 0) {
                                    if index > 0 { Rule() }
                                    Row(script: script)
                                }
                            }
                        }
                        .background(Palette.ground)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                    }
                    .listHeight(420)
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Text(store.all.count == 1 ? "1 script" : "\(store.all.count) scripts")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Pill("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
        }
    }

    // MARK: - adding

    private func pasteAndAdd() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            problem = "There is nothing on the clipboard."
            return
        }
        draft = text
        add()
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        problem = nil
        if let address = Userscript.address(text) {
            busy = true
            Task { @MainActor in
                do {
                    try await store.install(from: address)
                    draft = ""
                } catch {
                    problem = error.localizedDescription
                }
                busy = false
            }
            return
        }
        do {
            try store.install(text)
            draft = ""
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// One installed script: what it asks for, whether it runs, and the way out.
private struct Row: View {
    let script: Userscript
    @ObservedObject private var store = Userscripts.shared

    private var where_: String {
        let lines = script.matches + script.includes
        if lines.isEmpty { return "every address" }
        return lines.prefix(2).joined(separator: " · ") + (lines.count > 2 ? " · and \(lines.count - 2) more" : "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(script.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !script.version.isEmpty {
                        Text(script.version)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.faint)
                    }
                }
                Text(where_)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !script.summary.isEmpty {
                    Text(script.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Quick("Remove", tint: .red) { store.remove(script) }
                .frame(width: 54, alignment: .trailing)
            Switch(on: Binding(get: { store.isEnabled(script) },
                               set: { store.setEnabled($0, for: script) }))
                .frame(width: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
