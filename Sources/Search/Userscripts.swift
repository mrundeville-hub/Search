import CryptoKit
import Foundation
import WebKit

// Userscripts: a `.user.js` file, read — its `==UserScript==` header, where
// it runs, and whether this page is one of them.
//
// Ported from Yab (github.com/yetanotherbrowser/yab), Apache-2.0,
// Copyright 2026 Serafim Korablev. The header reader, the Chrome match
// patterns and the include globs are Yab's; the storage is Search's, the way
// SiteStyles keeps a site's CSS.
//
// What this first slice does: reads a script, keeps it in
// `userscripts.json`, and puts it into a page whose address its `@match`,
// `@include` and `@exclude` lines accept. What it does not do yet: `GM_*`
// calls, `@require` and `@resource` files, and a window to manage them in
// (the store is already here for it). A script that needs those keeps the
// parts of it that are plain JavaScript.

/// One `.user.js`: the text, its header parsed, and where it is allowed to run.
struct Userscript: Equatable {
    /// One `@require` file, as fetched when the script was installed: its text
    /// and the SHA-256 of it, so a later copy can be told apart from this one.
    struct File: Codable, Equatable {
        var url: String
        var sha256: String
        var text: String
    }

    let source: String
    /// The `@require` files fetched with it, in the order the header lists them.
    /// Run before the script, as Tampermonkey runs them.
    var requires: [File] = []
    /// Every `@key` of the header, lowercased, with each line's value in order.
    let header: [String: [String]]

    struct Invalid: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// The address of a script, when the text is one: one line, an http or
    /// https link. Anything else the panel is given is the script itself.
    static func address(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains(" ") else { return nil }
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// Whether the text is a userscript at all: a `==UserScript==` block near
    /// its top, wherever it was served from.
    static func looks(_ text: String) -> Bool {
        String(text.prefix(4000)).range(of: #"(?m)^\s*//\s*==UserScript==\s*$"#, options: .regularExpression) != nil
    }

    /// Reads a script, or says why it can't be one. Runs nothing, fetches nothing.
    static func read(_ source: String) throws -> Userscript {
        guard source.utf8.count <= 5_000_000 else { throw Invalid("This userscript is larger than 5 MB.") }
        guard let start = source.range(of: #"(?m)^\s*//\s*==UserScript==\s*$"#, options: .regularExpression),
              let end = source.range(of: #"(?m)^\s*//\s*==/UserScript==\s*$"#,
                                     options: .regularExpression, range: start.upperBound..<source.endIndex) else {
            throw Invalid("This file has no ==UserScript== header.")
        }
        var header: [String: [String]] = [:]
        for line in source[start.upperBound..<end.lowerBound].split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("//") else { continue }
            let rest = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("@") else { continue }
            let body = rest.dropFirst()
            let key = body.prefix { !$0.isWhitespace }.lowercased()
            let value = body.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            header[key, default: []].append(value)
        }
        let script = Userscript(source: source, header: header)
        guard !script.name.isEmpty else { throw Invalid("The header has no @name.") }
        guard script.name.count <= 200 else { throw Invalid("The @name is too long.") }
        return script
    }

    func first(_ key: String) -> String? { header[key]?.first(where: { !$0.isEmpty }) }
    func all(_ key: String) -> [String] { (header[key] ?? []).filter { !$0.isEmpty } }

    var name: String { first("name") ?? "" }
    var namespace: String { first("namespace") ?? "" }
    var version: String { first("version") ?? "" }
    var summary: String { first("description") ?? "" }
    var author: String { first("author") ?? "" }
    var matches: [String] { all("match") }
    var includes: [String] { all("include") }
    var excludes: [String] { all("exclude") + all("exclude-match") }
    var grants: [String] { all("grant") }
    /// The addresses its `@require` lines ask for. Fetched at install; nothing
    /// is fetched when a page runs.
    var requireURLs: [String] { all("require") }
    /// The files it asked for, as fetched.
    var requiresCode: String { requires.map(\.text).joined(separator: "\n") }

    /// The SHA-256 of a fetched file, as pinned beside it.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var icon: String? { first("icon") ?? first("iconurl") ?? first("defaulticon") }
    /// The whole frame's business or the top one's: `@noframes` keeps it out
    /// of the top frame's children.
    var noFrames: Bool { header["noframes"] != nil }

    /// When in the document's life it goes in, as Tampermonkey's `@run-at`.
    var runAt: WKUserScriptInjectionTime {
        switch first("run-at")?.lowercased() {
        case "document-start": return .atDocumentStart
        default: return .atDocumentEnd
        }
    }

    /// A short lowercase id for the list, from its name and namespace.
    var id: String {
        let slug = Userscript.slug(name)
        let digest = SHA256.hash(data: Data((namespace + "\n" + name).utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        return String((slug.isEmpty ? "script" : slug).prefix(48)) + "-" + digest
    }

    /// Lowercase words and dashes, for a name that is used as one.
    static func slug(_ name: String) -> String {
        name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
    }

    // MARK: - where it runs

    /// The regular expression (source, flags) for one `@match`: Chrome's match
    /// pattern as Tampermonkey reads it, the port allowed.
    static func regex(match pattern: String) -> (String, String)? {
        if pattern == "<all_urls>" || pattern == "*" { return (#"^(?:https?|file):\/\/.*$"#, "") }
        guard let scheme = pattern.range(of: "://") else { return regex(include: pattern) }
        let schemePart = String(pattern[..<scheme.lowerBound])
        let rest = pattern[scheme.upperBound...]
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let host = String(rest[..<slash])
        let path = rest[slash...].isEmpty ? "/*" : String(rest[slash...])
        let schemes = (schemePart == "*" || schemePart.lowercased() == "http*")
            ? "https?" : NSRegularExpression.escapedPattern(for: schemePart.lowercased())
        let hostPattern: String
        if host == "*" { hostPattern = "[^/]*" }
        else if host.hasPrefix("*.") { hostPattern = "(?:[^/]*\\.)?" + hostGlob(String(host.dropFirst(2))) }
        else { hostPattern = hostGlob(host) }
        return ("^" + schemes + ":\\/\\/" + hostPattern + "(?::\\d+)?" + glob(path) + "$", "i")
    }

    /// `google.*` matches every country's, as Tampermonkey lets it.
    private static func hostGlob(_ host: String) -> String {
        host.lowercased().split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[^/]*")
            .replacingOccurrences(of: "\\.tld", with: #"\.[a-z]{2,}(?:\.[a-z]{2,})?"#)
    }

    private static func glob(_ text: String) -> String {
        text.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
    }

    /// The regular expression for an `@include` or `@exclude`: a glob over the
    /// whole address, or a `/regex/` written as one.
    static func regex(include pattern: String) -> (String, String)? {
        if pattern == "*" || pattern == "<all_urls>" { return (".*", "") }
        if pattern.count > 2, pattern.hasPrefix("/"), let close = pattern.lastIndex(of: "/"),
           close > pattern.startIndex {
            let body = String(pattern[pattern.index(after: pattern.startIndex)..<close])
            let flags = String(pattern[pattern.index(after: close)...]).filter { "imsu".contains($0) }
            return body.isEmpty ? nil : (body, flags)
        }
        return ("^" + glob(pattern).replacingOccurrences(of: "\\.tld", with: #"\.[a-z]{2,}(?:\.[a-z]{2,})?"#) + "$", "i")
    }

    /// Whether a page's address is one this script asked for: one of its
    /// `@match`/`@include` patterns, and none of its exclusions. No patterns at
    /// all means every address, as Tampermonkey reads it.
    func runs(at url: URL) -> Bool {
        let address = url.absoluteString
        guard ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return false }
        func hit(_ pattern: (String, String)) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern.0,
                                                       options: pattern.1.contains("i") ? .caseInsensitive : []) else {
                return false
            }
            let range = NSRange(address.startIndex..<address.endIndex, in: address)
            return regex.firstMatch(in: address, options: [], range: range) != nil
        }
        if excludes.compactMap(Self.regex(include:)).contains(where: hit) { return false }
        var allowed = matches.compactMap(Self.regex(match:)) + includes.compactMap(Self.regex(include:))
        if matches.isEmpty && includes.isEmpty { allowed = [(".*", "")] }
        return allowed.contains(where: hit)
    }

    /// Whether it asks for the `GM_*` calls, by `@grant` or by using them
    /// without one, as Tampermonkey gives them to a script that does either.
    var wantsGM: Bool {
        if grants.contains(where: { $0.hasPrefix("GM_") || $0.hasPrefix("GM.") }) { return true }
        return source.range(of: #"\bGM[_.][A-Za-z]"#, options: .regularExpression) != nil
    }

    /// What goes into the page: the file as it was written, header and all, as
    /// Tampermonkey puts it in. Nothing is rewritten, so a script that reads
    /// its own header still finds it.
    var code: String { source }

    /// The few lines that stand the `GM_*` calls up before the script, when it
    /// asked for them. The values it can see are the ones Search kept, read
    /// into the page as they stand: `GM_getValue` answers at once, and a write
    /// is handed to Search to keep (see UserscriptBridge). The script itself
    /// runs inside the same function, so its `GM_getValue` is this script's and
    /// two scripts on one page never see each other's values.
    static func boot(script: Userscript, values: [String: Any], handler: String,
                     requires: String = "") -> String {
        let kept = (try? JSONSerialization.data(withJSONObject: values))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let meta = (try? JSONSerialization.data(withJSONObject: [
            "script": ["name": script.name, "namespace": script.namespace, "version": script.version],
            "scriptHandler": "Search",
        ])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // A bare string is a fragment, which JSONSerialization only writes when
        // told to: without the option this throws, and the app went with it.
        let id = (try? JSONSerialization.data(withJSONObject: script.id, options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"script\""
        return """
        (function () {
          "use strict";
          const id = \(id);
          const values = \(kept);
          const info = \(meta);
          const send = (message) => {
            try { window.webkit.messageHandlers["\(handler)"].postMessage(message); } catch (e) {}
          };
          const get = (key, fallback) => Object.prototype.hasOwnProperty.call(values, key) ? values[key] : fallback;
          const set = (key, value) => {
            values[key] = value;
            send({ do: "set", id: id, key: String(key), value: value });
          };
          const drop = (key) => {
            delete values[key];
            send({ do: "delete", id: id, key: String(key) });
          };
          const list = () => Object.keys(values);
          const GM = {
            info: info,
            getValue: (key, fallback) => Promise.resolve(get(key, fallback)),
            setValue: (key, value) => { set(key, value); return Promise.resolve(); },
            deleteValue: (key) => { drop(key); return Promise.resolve(); },
            listValues: () => Promise.resolve(list()),
          };
          const GM_getValue = get, GM_setValue = set, GM_deleteValue = drop, GM_listValues = list;
          const GM_info = info;
        \(requires)
        \(script.code)
        }).call(window);
        """
    }
}

// MARK: - keeping them

/// Every userscript installed, on or off, in `userscripts.json` beside
/// Search's other small files.
@MainActor
final class Userscripts: ObservableObject {
    static let shared = Userscripts(file: Store.file("userscripts.json"))

    /// The channel a script's `GM_setValue` writes on (see Userscript.boot).
    static let handler = "officeUserscript"

    /// One line of the file: the script as it was read, and whether it runs.
    private struct Kept: Codable, Equatable {
        var source: String
        var enabled: Bool
        var added: Date
        /// Absent in a file written before @require was fetched: an old line
        /// still reads, with nothing fetched for it.
        var requires: [Userscript.File]?
    }

    /// In the order they were installed.
    @Published private(set) var all: [Userscript] = []

    @Published private(set) var enabled: Set<String> = []
    private var added: [String: Date] = [:]
    /// The `WKUserScript` made for each script, kept and handed back on every
    /// navigation: the content controller compares the scripts it already has
    /// by identity, and a new instance on every page would send every script
    /// to the page's process again (see the last check in Tab.arm).
    private var made: [String: WKUserScript] = [:]
    /// How a script and its `@require` files are fetched: the network by
    /// default, a test's own answer when it says so.
    typealias Fetch = @Sendable (URL) async throws -> Data

    private let file: URL
    private let fetch: Fetch
    /// What scripts keep with `GM_setValue`.
    let values: UserscriptValues

    init(file: URL, values: UserscriptValues? = nil, fetch: Fetch? = nil) {
        self.file = file
        self.fetch = fetch ?? { address in
            var request = URLRequest(url: address)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Userscript.Invalid("That address answered \(http.statusCode).")
            }
            return data
        }
        self.values = values ?? UserscriptValues(
            file: file.deletingLastPathComponent().appendingPathComponent("userscript-values.json"))
        load()
    }

    /// A script wrote a value: the next page gets it in the boot, so the
    /// `WKUserScript` made for the last one is dropped.
    func valueChanged(_ id: String) { made[id] = nil }

    func isEnabled(_ script: Userscript) -> Bool { enabled.contains(script.id) }

    /// Where the list is kept, for Show in Finder.
    var fileURL: URL { file }

    /// Reads a script and keeps it. Returns it as read; an error says what is
    /// wrong with the text. A script already installed with the same name and
    /// namespace replaces the old one and stays on.
    @discardableResult
    func install(_ source: String, requires: [Userscript.File] = []) throws -> Userscript {
        var script = try Userscript.read(source)
        script.requires = requires
        let wasOn = enabled.contains(script.id)
        all.removeAll { $0.id == script.id }
        all.append(script)
        made[script.id] = nil
        enabled.insert(script.id)
        if !wasOn { added[script.id] = Date() }
        save()
        return script
    }

    /// Fetches a script from an address and keeps it, as pasting its text does,
    /// and fetches the `@require` files it asks for while it is about it: the
    /// page it runs on fetches nothing.
    @discardableResult
    func install(from address: URL) async throws -> Userscript {
        let text = try await text(at: address)
        let reading = try Userscript.read(text)
        return try install(text, requires: try await required(reading.requireURLs))
    }

    /// A script's `@require` files, each fetched once and pinned by its SHA-256
    /// so a later copy can be told apart from this one.
    private func required(_ lines: [String]) async throws -> [Userscript.File] {
        guard lines.count <= 10 else {
            throw Userscript.Invalid("A script can bring 10 required files with it at most here.")
        }
        var kept: [Userscript.File] = []
        for line in lines {
            guard let address = URL(string: line),
                  ["http", "https"].contains(address.scheme?.lowercased() ?? "") else {
                throw Userscript.Invalid("@require \(line) isn't an http or https address.")
            }
            let data = try await self.data(at: address)
            guard data.count <= 5_000_000 else {
                throw Userscript.Invalid("@require \(line) is larger than 5 MB.")
            }
            guard let source = String(data: data, encoding: .utf8) else {
                throw Userscript.Invalid("@require \(line) isn't text.")
            }
            kept.append(Userscript.File(url: line, sha256: Userscript.sha256(data), text: source))
        }
        return kept
    }

    /// The bytes behind an address, through `fetch`: the network, or a test's
    /// own answer.
    private func data(at address: URL) async throws -> Data {
        guard ["http", "https"].contains(address.scheme?.lowercased() ?? "") else {
            throw Userscript.Invalid("Only an http or https address can be fetched.")
        }
        do {
            return try await fetch(address)
        } catch let refused as Userscript.Invalid {
            throw refused
        } catch {
            throw Userscript.Invalid("\(address.absoluteString) couldn't be reached: \(error.localizedDescription)")
        }
    }

    private func text(at address: URL) async throws -> String {
        let data = try await self.data(at: address)
        guard data.count <= 5_000_000 else { throw Userscript.Invalid("That file is larger than 5 MB.") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw Userscript.Invalid("That file isn't text.")
        }
        return text
    }

    func remove(_ script: Userscript) {
        all.removeAll { $0.id == script.id }
        enabled.remove(script.id)
        made[script.id] = nil
        added[script.id] = nil
        save()
    }

    func setEnabled(_ on: Bool, for script: Userscript) {
        if on { enabled.insert(script.id) } else { enabled.remove(script.id) }
        save()
    }

    /// The scripts that run on a page, in install order, ready to hand to the
    /// content controller. `@noframes` is the caller's to honour: the main
    /// frame's list is this one; a child frame's leaves those out.
    func scripts(for url: URL?, mainFrame: Bool = true) -> [WKUserScript] {
        guard let url else { return [] }
        return all
            .filter { enabled.contains($0.id) && $0.runs(at: url) && (mainFrame || !$0.noFrames) }
            .map { script in
                if let kept = made[script.id] { return kept }
                let required = script.requiresCode
                let source = script.wantsGM
                    ? Userscript.boot(script: script, values: values.read(script.id),
                                      handler: Self.handler, requires: required)
                    : (required.isEmpty ? script.code : required + "\n" + script.code)
                let built = WKUserScript(source: source, injectionTime: script.runAt,
                                         forMainFrameOnly: script.noFrames, in: .page)
                made[script.id] = built
                return built
            }
    }

    // MARK: - the file

    private func load() {
        // The same date reading `save` writes with: a plain decoder makes every
        // line unreadable, and a list that came back empty would have been
        // overwritten by the next save.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file),
              let kept = try? decoder.decode([Kept].self, from: data) else { return }
        for line in kept {
            guard var script = try? Userscript.read(line.source) else { continue }
            if all.contains(where: { $0.id == script.id }) { continue }
            script.requires = line.requires ?? []
            all.append(script)
            if line.enabled { enabled.insert(script.id) }
            added[script.id] = line.added
        }
    }

    private func save() {
        let kept = all.map { Kept(source: $0.source, enabled: enabled.contains($0.id),
                                  added: added[$0.id] ?? Date(), requires: $0.requires) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(kept) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - what scripts keep

/// The values userscripts keep with `GM_setValue`, by script id and key, in
/// `userscript-values.json`. One small file beside `userscripts.json`, not one
/// per script: there are never many.
@MainActor
final class UserscriptValues {
    private let file: URL
    private var byScript: [String: [String: Any]] = [:]

    init(file: URL) {
        self.file = file
        load()
    }

    func read(_ script: String) -> [String: Any] { byScript[script] ?? [:] }

    /// A value a script asked to keep. Only something JSON can hold: a value
    /// that can't be written down would be lost at the next launch anyway.
    func set(_ value: Any, for key: String, script: String) {
        guard JSONSerialization.isValidJSONObject(["value": value]) else { return }
        var kept = byScript[script] ?? [:]
        kept[key] = value
        byScript[script] = kept
        save()
    }

    func remove(_ key: String, script: String) {
        guard var kept = byScript[script], kept[key] != nil else { return }
        kept[key] = nil
        if kept.isEmpty { byScript[script] = nil } else { byScript[script] = kept }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]]
        else { return }
        byScript = object
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: byScript,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// What a script's `GM_setValue` and `GM_deleteValue` arrive on: the id the
/// script was booted with, and the key it wrote (see Userscript.boot). Nothing
/// else is taken from a page.
@MainActor
final class UserscriptBridge: NSObject, WKScriptMessageHandler {
    static let name = Userscripts.handler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let key = body["key"] as? String else { return }
        let store = Userscripts.shared
        switch body["do"] as? String {
        case "set":
            guard let value = body["value"] else { return }
            store.values.set(value, for: key, script: id)
        case "delete":
            store.values.remove(key, script: id)
        default:
            return
        }
        store.valueChanged(id)
    }
}
