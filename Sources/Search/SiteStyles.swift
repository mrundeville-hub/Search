import Combine
import Foundation
import SwiftUI

// Your own style for a site, as Arc's Boosts are, and Yab's: CSS you write,
// put on every page of that site, and a script if you want one — the CSS goes
// in before the page has drawn, the script runs once its document is there.
// The script is yours and runs in the page's own world: that is what a boost
// is for. Nothing else in Search runs script you type into a page.
//
// Off until Settings › Browsing › Pages › Your own style for a site. Then
// View › Edit Site Style… writes the site you're on, and what you type is on
// the page as you type it. Kept by site the way hidden elements are (no
// www.), in styles.json beside hidden.json. Turning the setting off takes
// every style and script off the pages and keeps them all.

@MainActor
final class SiteStyles: ObservableObject {
    static let shared = SiteStyles(file: Store.file("styles.json"))

    /// The element the sheet lives in, apart from the one that hides things.
    static let element = "office-style"

    /// Settings › Browsing › Pages. Off, pages get nothing at all.
    var on = false {
        didSet { if on != oldValue { changed.send(nil) } }
    }

    @Published private(set) var byHost: [String: String] = [:]
    /// The script half of a boost, by the same host. Empty for most sites.
    @Published private(set) var scriptByHost: [String: String] = [:]
    /// Its colours and type (see BoostLook.swift), by the same host.
    @Published private(set) var lookByHost: [String: BoostLook] = [:]

    /// A site whose style changed, for every window to pass on to its open
    /// pages of that site; nil for all of them, when the switch moved.
    let changed = PassthroughSubject<String?, Never>()

    private let file: URL
    private var saving = false

    init(file: URL) {
        self.file = file
        load()
    }

    /// The same host hidden elements and dark pages are kept by: no www., and
    /// only for a website.
    static func host(of url: URL?) -> String? { Dusk.host(of: url) }

    /// What a page of this site is to wear: nothing while the setting is off.
    func css(on host: String?) -> String? {
        guard on, let host else { return nil }
        // The look first, then what was written: a rule of yours of the same
        // weight wins, which is what a person who writes CSS expects.
        let parts = [look(on: host)?.css() ?? "", byHost[host] ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// The colours and type chosen for a site, on or off.
    func look(on host: String) -> BoostLook? {
        lookByHost[host].flatMap { $0.isEmpty ? nil : $0 }
    }

    func setLook(_ look: BoostLook, on host: String) {
        let kept = look.isEmpty ? nil : look
        guard lookByHost[host] != kept else { return }
        lookByHost[host] = kept
        save()
        changed.send(host)
    }

    /// The script half, for a page of this site: nothing while the setting is
    /// off, as with the style.
    func script(on host: String?) -> String? {
        guard on, let host, let script = scriptByHost[host], !script.isEmpty else { return nil }
        return script
    }

    /// What was written for a site, on or off.
    func written(on host: String) -> String { byHost[host] ?? "" }
    func writtenScript(on host: String) -> String { scriptByHost[host] ?? "" }

    /// Every site with a style, a script or a look.
    var hosts: [String] {
        Set(byHost.keys).union(scriptByHost.keys).union(lookByHost.keys).sorted()
    }

    /// Nothing but whitespace is no style at all, and the site is forgotten.
    func set(_ css: String, on host: String) {
        let kept = css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : css
        guard byHost[host] != kept else { return }
        byHost[host] = kept
        save()
        changed.send(host)
    }

    /// The script half. Nothing but whitespace takes it off again.
    func setScript(_ script: String, on host: String) {
        let kept = script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : script
        guard scriptByHost[host] != kept else { return }
        scriptByHost[host] = kept
        save()
        changed.send(host)
    }

    /// Both halves, for good.
    func remove(on host: String) {
        set("", on: host)
        setScript("", on: host)
        setLook(BoostLook(), on: host)
    }

    // MARK: - into the page

    /// Puts the sheet in, or empties it. Last in the document once there is
    /// one, so a rule of yours wins over the site's own of the same weight
    /// without needing !important. Text in a style element, never markup:
    /// nothing in it can close the element and become something else.
    private static let apply = """
    function (css) {
      var sheet = document.getElementById('\(element)');
      if (!sheet) {
        if (!css) return;
        sheet = document.createElement('style');
        sheet.id = '\(element)';
      }
      sheet.textContent = css;
      var last = function () { document.documentElement.appendChild(sheet); };
      last();
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', last, { once: true });
    }
    """

    /// For a page about to load: the sheet as a string the script can't be
    /// broken out of, whatever quotes, backticks or `${` it holds.
    static func script(_ css: String) -> String {
        "(\(apply))(\(literal(css)));"
    }

    /// For the page up now, where the CSS travels as an argument and is
    /// never part of the source (see Tab.callInSearch).
    static let live = "(\(apply))(css);"

    /// The script half, once the document is there: wrapped so a mistake in
    /// yours is a line in the console rather than a page that stops halfway.
    static func scriptCode(_ script: String) -> String {
        "(function () { try {\n" + script + "\n} catch (e) { console.error('Search boost:', e); } })();"
    }

    /// A JavaScript string literal: JSON's, with the two line separators and
    /// `<` spelled out as well.
    static func literal(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            .replacingOccurrences(of: "<", with: "\\u003c")
    }

    // MARK: - the file

    /// What `styles.json` holds: the two halves by host, under a version so a
    /// file from before the script half still reads. Written before that as
    /// one plain `[host: css]`, which is still the style half.
    private struct Kept: Codable {
        var version: Int
        var css: [String: String]
        var script: [String: String]
        /// Absent in a file from before a boost had a look.
        var look: [String: BoostLook]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        if let stored = try? JSONDecoder().decode(Kept.self, from: data) {
            byHost = stored.css
            scriptByHost = stored.script
            lookByHost = stored.look ?? [:]
            return
        }
        if let old = try? JSONDecoder().decode([String: String].self, from: data) { byHost = old }
    }

    /// Typing writes a few times a second; the file is written once it stops.
    private func save() {
        guard !saving else { return }
        saving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            saving = false
            let snapshot = Kept(version: 3, css: byHost, script: scriptByHost, look: lookByHost)
            let file = file
            DispatchQueue.global(qos: .utility).async { Self.write(snapshot, to: file) }
        }
    }

    /// Now rather than in a moment, for a test.
    func writeNow() {
        Self.write(Kept(version: 3, css: byHost, script: scriptByHost, look: lookByHost), to: file)
    }

    nonisolated private static func write(_ styles: Kept, to file: URL) {
        guard let data = try? JSONEncoder().encode(styles) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// View › Edit Site Style…: the CSS for the site in front, on the page as
/// you type. Done closes it; there is nothing to save, it already is.
/// Its bottom corner, away from the corner it hangs from, makes it larger
/// or smaller, the editor taking the room; the size is kept for next time.
struct StylePanel: View {
    /// Which half is being written: the stylesheet, or the script beside it.
    enum Half: Hashable, CaseIterable {
        case css, script, look

        var title: String {
            switch self {
            case .css: return "CSS"
            case .script: return "Script"
            case .look: return "Look"
            }
        }
    }

    @ObservedObject var browser: Browser
    let host: String

    @State private var half: Half = .css
    @State private var text = ""
    @State private var look = BoostLook()
    @State private var pending: DispatchWorkItem?
    @FocusState private var typing: Bool
    /// The card's width and the editor's height, as last left.
    @State private var size = StylePanel.kept
    @State private var start: CGSize?
    @State private var over = false

    /// What it opens at the first time, and the least it is made.
    static let first = CGSize(width: 420, height: 220)
    static let least = CGSize(width: 340, height: 120)

    static var kept: CGSize {
        let width = Store.settings.double(forKey: "sitestyle.width")
        let height = Store.settings.double(forKey: "sitestyle.height")
        guard width > 0, height > 0 else { return first }
        return CGSize(width: max(width, least.width), height: max(height, least.height))
    }

    static func keep(_ size: CGSize) {
        Store.settings.set(Double(size.width), forKey: "sitestyle.width")
        Store.settings.set(Double(size.height), forKey: "sitestyle.height")
    }

    /// The most it may take: the window, less the margins round the card,
    /// its title and its foot.
    static func most(in room: CGSize?) -> CGSize {
        guard let room, room.width > 0, room.height > 0 else { return CGSize(width: 1200, height: 900) }
        return CGSize(width: max(least.width, room.width - 28),
                      height: max(least.height, room.height - Metrics.strip - 8 - 14 - 150))
    }

    /// `from` pulled by `moved` at the corner under the card's left edge:
    /// left and down make it larger.
    static func pulled(_ from: CGSize, by moved: CGSize, room: CGSize?) -> CGSize {
        let most = most(in: room)
        return CGSize(width: min(max(from.width - moved.width, least.width), most.width),
                      height: min(max(from.height + moved.height, least.height), most.height))
    }

    private var room: CGSize? { browser.window?.contentView?.bounds.size }

    var body: some View {
        let most = Self.most(in: room)
        let shown = CGSize(width: min(size.width, most.width), height: min(size.height, most.height))
        return Plate(host, width: shown.width, close: close) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Segmented(options: Half.allCases.map { ($0, $0.title) }, selection: $half)
                    Caption(half == .css ? "CSS for every page of this site"
                            : half == .script ? "Script for every page, run once its document is there"
                            : "Colours and type, before your own CSS")
                    Spacer()
                }
                if half == .look {
                    LookControls(look: $look)
                        .padding(8)
                        .frame(height: shown.height, alignment: .top)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .padding(8)
                    .frame(height: shown.height)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Pill("Done", filled: true, action: close)
                if !text.isEmpty {
                    Pill("Clear") { text = "" }
                }
                // A boost is a file: this site's two halves, as it stands —
                // including what has just been typed and not yet committed.
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Pill("Share…") { share() }
                    Pill("Copy") { copy() }
                }
                Spacer()
            }
        }
        .overlay(alignment: .bottomLeading) { corner }
        .onAppear {
            text = SiteStyles.shared.written(on: host)
            look = SiteStyles.shared.look(on: host) ?? BoostLook()
            typing = true
        }
        .onChange(of: look) { _, now in
            SiteStyles.shared.setLook(now, on: host)
        }
        .onChange(of: text) { _, now in
            // A moment after the last key, so a half-typed rule isn't sent
            // to every open page of the site on each letter.
            pending?.cancel()
            let name = half
            let work = DispatchWorkItem { StylePanel.write(now, half: name, on: host) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        .onChange(of: half) { _, now in
            // Half-typed in one, and now the other: what was typed stays.
            pending?.cancel()
            if half != .look {
                let leaving: Half = now == .css ? .script : .css
                StylePanel.write(text, half: leaving, on: host)
            }
            if now != .look {
                text = now == .css ? SiteStyles.shared.written(on: host)
                                    : SiteStyles.shared.writtenScript(on: host)
                typing = true
            }
        }
    }

    /// The corner that resizes it: a small mark, the pointer's resize arrow
    /// over it; a double-click puts it back to its first size.
    private var corner: some View {
        Image(systemName: "arrow.down.left.and.arrow.up.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(over || start != nil ? Palette.muted : Palette.faint)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != over else { return }
                over = inside
                if inside { Self.cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let from = start ?? size
                        if start == nil { start = from }
                        size = Self.pulled(from, by: drag.translation, room: room)
                    }
                    .onEnded { _ in
                        start = nil
                        Self.keep(size)
                    }
            )
            .onTapGesture(count: 2) {
                size = Self.first
                Self.keep(size)
            }
            .help("Drag to resize")
            .accessibilityHidden(true)
    }

    /// The diagonal resize arrow where macOS has one to give.
    private static var cursor: NSCursor {
        if #available(macOS 15, *) { return .frameResize(position: .bottomLeft, directions: .all) }
        return .crosshair
    }

    /// One half of the boost, into the store the site is kept in.
    static func write(_ text: String, half: Half, on host: String) {
        switch half {
        case .css: SiteStyles.shared.set(text, on: host)
        case .script: SiteStyles.shared.setScript(text, on: host)
        case .look: break  // written as it is changed, by LookControls
        }
    }

    /// What is in the editor now goes into the store first, so the file holds
    /// what is on the page rather than the last committed letter.
    private func share() {
        StylePanel.write(text, half: half, on: host)
        guard var boost = SiteStyles.shared.boost(on: host) else { return }
        let veils = browser.curtain.veils(on: host)
        if !veils.isEmpty {
            boost.hidden = veils.map { BoostFile.Hidden(selector: $0.selector, label: $0.label) }
        }
        BoostSharing.save(boost, from: browser.window)
    }

    /// The same, on the clipboard.
    private func copy() {
        StylePanel.write(text, half: half, on: host)
        guard var boost = SiteStyles.shared.boost(on: host) else { return }
        let veils = browser.curtain.veils(on: host)
        if !veils.isEmpty {
            boost.hidden = veils.map { BoostFile.Hidden(selector: $0.selector, label: $0.label) }
        }
        BoostSharing.copy(boost)
    }

    private func close() {
        pending?.cancel()
        StylePanel.write(text, half: half, on: host)
        browser.styling = nil
    }
}

/// The setting's switch, and beside it the sites that have a style, each to
/// take off for good. Their styles are kept while the switch is off.
struct SiteStylesControl: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var browser: Browser
    @ObservedObject private var styles = SiteStyles.shared

    var body: some View {
        HStack(spacing: 10) {
            if !styles.hosts.isEmpty {
                Menu(styles.hosts.count == 1 ? "1 site" : "\(styles.hosts.count) sites") {
                    ForEach(styles.hosts, id: \.self) { host in
                        Menu(host) {
                            Button("Remove Style and Script") { styles.remove(on: host) }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Pill("Bring in…") {
                _ = BoostSharing.bring(inFrom: nil, into: styles,
                                       curtain: browser.curtain,
                                       reapply: { browser.applyHidden(on: $0) })
            }
            Switch(on: $prefs.sitesStyles)
        }
    }
}

/// A boost's colours and type: four rows, each of them "the site's own" until
/// it is turned on (see BoostLook.swift).
struct LookControls: View {
    @Binding var look: BoostLook

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            row("Ground", hex: $look.background)
            row("Text", hex: $look.text)
            HStack(spacing: 8) {
                Text("Font")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 56, alignment: .leading)
                Picker("", selection: $look.font) {
                    ForEach(BoostLook.fonts, id: \.self) { font in
                        Text(BoostLook.title(of: font)).tag(font)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Lines")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 56, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { look.lineHeight != nil },
                    set: { look.lineHeight = $0 ? 1.5 : nil }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Stepper(value: Binding(
                    get: { look.lineHeight ?? 1.5 },
                    set: { look.lineHeight = min(max(($0 * 10).rounded() / 10, 1), 2.5) }),
                        in: 1...2.5, step: 0.1) {
                    Text(look.lineHeight.map { String(format: "%.1f", $0) } ?? "the site's own")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .disabled(look.lineHeight == nil)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Paragraphs")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 56, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { look.paragraphSpacing != nil },
                    set: { look.paragraphSpacing = $0 ? 12 : nil }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Stepper(value: Binding(
                    get: { look.paragraphSpacing ?? 12 },
                    set: { look.paragraphSpacing = min(max($0.rounded(), 0), 24) }),
                        in: 0...24, step: 2) {
                    Text(look.paragraphSpacing.map { "\(Int($0)) px" } ?? "the site's own")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .disabled(look.paragraphSpacing == nil)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Text size")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 56, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { look.size != nil },
                    set: { look.size = $0 ? 16 : nil }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Stepper(value: Binding(
                    get: { look.size ?? 16 },
                    set: { look.size = min(max($0, 8), 32) }), in: 8...32) {
                    Text(look.size.map { "\(Int($0)) px" } ?? "the site's own")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .disabled(look.size == nil)
                Spacer()
            }
        }
    }

    private func row(_ title: String, hex: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { !hex.wrappedValue.isEmpty },
                set: { hex.wrappedValue = $0 ? "#111111" : "" }))
                .toggleStyle(.switch)
                .labelsHidden()
            ColorPicker("", selection: Binding(
                get: { BoostLook.colour(hex.wrappedValue) ?? .black },
                set: { hex.wrappedValue = BoostLook.hex($0) }),
                        supportsOpacity: false)
                .labelsHidden()
                .disabled(hex.wrappedValue.isEmpty)
            Text(hex.wrappedValue.isEmpty ? "the site's own" : hex.wrappedValue)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.muted)
            Spacer()
        }
    }
}
