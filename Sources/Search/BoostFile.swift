import AppKit
import Foundation
import UniformTypeIdentifiers

// A boost as a file: one site's style and script, written down so it can be
// given to someone else — Yab's boosts are shared this way (its BoostApp and
// BoostCLI), and so are Arc's.
//
//   {
//     "format": "search-boost",
//     "version": 1,
//     "site": "example.com",
//     "css": "body { background: #111 }",
//     "script": "document.body.classList.add('dark')"
//   }
//
// Reading one runs nothing: the script is text until a page of that site is
// opened with the setting on. What a file may not do is say another site than
// its own: a boost is a site's, and the site is a host, nothing else.

struct BoostFile: Codable, Equatable {
    static let format = "search-boost"
    /// The only version this reads. A newer file says so and is refused.
    static let version = 1
    static let suffix = "boost"

    var format: String = BoostFile.format
    var version: Int = BoostFile.version
    /// The site it is for: a host, lowercase, without www., as boosts are kept.
    var site: String
    var css: String = ""
    var script: String = ""
    /// The colours and type chosen for the site, when there are any.
    var look: BoostLook? = nil

    init(site: String, css: String = "", script: String = "", look: BoostLook? = nil) {
        self.site = site
        self.css = css
        self.script = script
        self.look = look
    }

    /// A file from a person's hand needn't carry every key: what it doesn't say
    /// is this version of the format, with nothing in that half.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        format = try box.decodeIfPresent(String.self, forKey: .format) ?? BoostFile.format
        version = try box.decodeIfPresent(Int.self, forKey: .version) ?? BoostFile.version
        site = try box.decode(String.self, forKey: .site)
        css = try box.decodeIfPresent(String.self, forKey: .css) ?? ""
        script = try box.decodeIfPresent(String.self, forKey: .script) ?? ""
        look = try box.decodeIfPresent(BoostLook.self, forKey: .look)
    }

    /// Whether either half has anything in it.
    var isEmpty: Bool {
        css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (look?.isEmpty ?? true)
    }

    struct Invalid: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: - reading and writing

    static func read(_ data: Data) throws -> BoostFile {
        guard let boost = try? JSONDecoder().decode(BoostFile.self, from: data) else {
            throw Invalid("That file isn't a boost.")
        }
        guard boost.format == BoostFile.format else {
            throw Invalid("That file is a “\(boost.format)”, not a boost.")
        }
        guard boost.version <= BoostFile.version else {
            throw Invalid("That boost was made by a newer Search (version \(boost.version)).")
        }
        let site = boost.site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !site.isEmpty else { throw Invalid("That boost doesn't say which site it is for.") }
        guard !site.contains("/"), !site.contains(" "), !site.contains(":"), site.contains(".") else {
            throw Invalid("“\(site)” isn't a site: a boost is for a host, like example.com.")
        }
        guard !boost.isEmpty else { throw Invalid("That boost has nothing in it.") }
        return BoostFile(site: site.hasPrefix("www.") ? String(site.dropFirst(4)) : site,
                         css: boost.css, script: boost.script,
                         look: boost.look.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func read(at url: URL) throws -> BoostFile {
        guard let data = try? Data(contentsOf: url) else {
            throw Invalid("That file couldn't be read.")
        }
        return try read(data)
    }

    /// The file's text, in a shape a person can read and diff.
    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    /// What the file is called: the site, `.boost`.
    var fileName: String { site + "." + BoostFile.suffix }
}

// MARK: - the halves of a boost, as a file

extension SiteStyles {
    /// This site's boost, as it would be written to a file. Nil when the site
    /// has neither a style nor a script.
    func boost(on host: String) -> BoostFile? {
        let boost = BoostFile(site: host, css: written(on: host), script: writtenScript(on: host),
                              look: look(on: host))
        return boost.isEmpty ? nil : boost
    }

    /// Puts a boost's two halves on its own site, and takes them off every
    /// other page of that site as they are typed. Answers what it did.
    @discardableResult
    func bring(in boost: BoostFile) -> String {
        set(boost.css, on: boost.site)
        setScript(boost.script, on: boost.site)
        if let look = boost.look { setLook(look, on: boost.site) }
        revise()
        var parts: [String] = []
        if !boost.css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("style") }
        if !boost.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("script") }
        if let look = boost.look, !look.isEmpty { parts.append("colours and type") }
        return "Brought in \(parts.joined(separator: " and ")) for \(boost.site)"
    }

    /// Puts the boost on the pages of that site that are open now: the change
    /// was made outside the editor, so nothing else would tell them.
    private func revise() {
        changed.send(nil)
    }
}

// MARK: - sharing one

/// Writes a site's boost to a file the person picks, or puts it on the
/// clipboard. Both are in the editor's foot (see StylePanel), for the site in
/// front.
@MainActor
enum BoostSharing {
    static func save(_ boost: BoostFile, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = boost.fileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.title = "Share this boost"
        panel.message = "One file, with this site's style and script. Whoever opens it gets both."
        let run: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try boost.json().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: run)
        } else {
            run(panel.runModal())
        }
    }

    static func copy(_ boost: BoostFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(boost.json(), forType: .string)
    }

    /// Reads one the person picks and puts it on its site. Answers what it did,
    /// or why it didn't.
    static func bring(inFrom window: NSWindow?, into styles: SiteStyles) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Bring in a boost"
        panel.message = "A .boost file: one site's style and script."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return styles.bring(in: try BoostFile.read(at: url))
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}
