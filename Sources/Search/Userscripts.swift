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
    let source: String
    /// Every `@key` of the header, lowercased, with each line's value in order.
    let header: [String: [String]]

    struct Invalid: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
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

    /// What goes into the page: the file as it was written, header and all, as
    /// Tampermonkey puts it in. Nothing is rewritten, so a script that reads
    /// its own header still finds it.
    var code: String { source }
}

// MARK: - keeping them

/// Every userscript installed, on or off, in `userscripts.json` beside
/// Search's other small files.
@MainActor
final class Userscripts: ObservableObject {
    static let shared = Userscripts(file: Store.file("userscripts.json"))

    /// One line of the file: the script as it was read, and whether it runs.
    private struct Kept: Codable, Equatable {
        var source: String
        var enabled: Bool
        var added: Date
    }

    /// In the order they were installed.
    @Published private(set) var all: [Userscript] = []

    private var enabled: Set<String> = []
    private var added: [String: Date] = [:]
    /// The `WKUserScript` made for each script, kept and handed back on every
    /// navigation: the content controller compares the scripts it already has
    /// by identity, and a new instance on every page would send every script
    /// to the page's process again (see the last check in Tab.arm).
    private var made: [String: WKUserScript] = [:]
    private let file: URL

    init(file: URL) {
        self.file = file
        load()
    }

    func isEnabled(_ script: Userscript) -> Bool { enabled.contains(script.id) }

    /// Reads a script and keeps it. Returns it as read; an error says what is
    /// wrong with the text. A script already installed with the same name and
    /// namespace replaces the old one and stays on.
    @discardableResult
    func install(_ source: String) throws -> Userscript {
        let script = try Userscript.read(source)
        let wasOn = enabled.contains(script.id)
        all.removeAll { $0.id == script.id }
        all.append(script)
        made[script.id] = nil
        enabled.insert(script.id)
        if !wasOn { added[script.id] = Date() }
        save()
        return script
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
                let built = WKUserScript(source: script.code, injectionTime: script.runAt,
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
            guard let script = try? Userscript.read(line.source) else { continue }
            if all.contains(where: { $0.id == script.id }) { continue }
            all.append(script)
            if line.enabled { enabled.insert(script.id) }
            added[script.id] = line.added
        }
    }

    private func save() {
        let kept = all.map { Kept(source: $0.source, enabled: enabled.contains($0.id), added: added[$0.id] ?? Date()) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(kept) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
