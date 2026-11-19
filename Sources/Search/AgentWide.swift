import Foundation

// The parts of Search an agent may reach that aren't a page: the bookmarks it
// keeps, the places it has been lately, and the spaces a window has.
//
// yab gives its agents the same reach (its McpToolsShelf, McpToolsMail and
// friends); Search's half stayed inside a page until now. Everything here is
// read-only except adding a bookmark and going to a space, and nothing here
// reaches a password, a card number, a private tab or Settings.

@MainActor
enum AgentWide {
    /// Every bookmark, with the folder it sits in said as a path: "", "Bar",
    /// "Bar/Work". Folders that are empty are not listed: an agent can find
    /// nothing in them.
    static func bookmarks(_ browser: Browser) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ nodes: [Bookmark], _ path: [String]) {
            for node in nodes {
                if let url = node.url {
                    out.append(["title": node.label, "url": url, "folder": path.joined(separator: "/")])
                } else if let children = node.children {
                    walk(children, path + [node.title])
                }
            }
        }
        walk(browser.bookmarks.roots, [])
        return out
    }

    /// Where the window's space has been lately, newest first, and only what
    /// the words match — every one of them, anywhere in the title or the
    /// address. The history keeps the last few hundred places, not all of them.
    static func recent(_ browser: Browser, words: String, limit: Int) -> [[String: Any]] {
        let wanted = words.lowercased().split(separator: " ").map(String.init)
        var out: [[String: Any]] = []
        for trace in browser.history.recent() {
            let address = trace.url.absoluteString
            if !wanted.isEmpty {
                let haystack = (trace.title + " " + address).lowercased()
                guard wanted.allSatisfy({ haystack.contains($0) }) else { continue }
            }
            out.append(["title": trace.title.isEmpty ? address : trace.title,
                        "url": address,
                        "visits": trace.count,
                        "last": ISO8601DateFormatter().string(from: trace.last)])
            if out.count >= limit { break }
        }
        return out
    }

    /// The spaces this window has, numbered as its own shortcuts number them.
    static func spaces(_ browser: Browser) -> [[String: Any]] {
        browser.spaces.enumerated().map { index, space in
            ["index": index,
             "name": space.name,
             "id": space.id.uuidString,
             "current": space.id == browser.spaceID]
        }
    }
}
