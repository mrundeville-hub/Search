import AppKit
import Foundation
import SwiftUI

// A card about the link under the pointer: what the page says it is, before
// you open it. Yab draws one by loading the page in a hidden tab, signed in as
// you are (see its LinkCard.swift); this is the smaller thing — one request for
// the page's own text, no cookies, no scripts, no tab — and the card says only
// what a stranger could read.
//
// Off unless Settings › Links › "A card about the link under the pointer" is
// turned on: a card means the page you are hovering is asked for, which is a
// thing the page's owner can see. When it is on, a request goes out only after
// the pointer has rested on the link for a moment, once per address per session.

/// What the card says. Small on purpose: the page's title, its description,
/// and the icon it names.
struct LinkCardSummary: Equatable {
    var url: URL
    var title: String
    var summary: String
    var icon: URL?

    /// The page's name as a person reads it: its host, and the port when it is
    /// not the web's own, as a page on localhost is a page on a port.
    var host: String {
        guard let name = url.host() else { return url.absoluteString }
        guard let port = url.port, port != 80, port != 443 else { return name }
        return "\(name):\(port)"
    }

    /// What is left to draw: a card with no title is no card.
    var isWorthShowing: Bool { !title.isEmpty }
}

@MainActor
final class LinkCards: ObservableObject {
    static let shared = LinkCards()

    /// Whether the setting is on. Set from Preferences, as HoveredLink.on is.
    static var on = false

    /// How the page is fetched: the network by default, a test's own answer
    /// when it says so.
    typealias Fetch = @Sendable (URL) async throws -> Data

    private let fetch: Fetch
    /// What each address said, by absolute string, oldest first.
    private var cache: [String: LinkCardSummary] = [:]
    private var order: [String] = []
    /// Addresses already being asked about, so ten hovers on one link are one
    /// request.
    private var asking: [String: Task<LinkCardSummary?, Never>] = [:]

    /// Enough to keep a session's worth of cards and no reason to grow.
    private let kept = 200
    init(fetch: Fetch? = nil) {
        self.fetch = fetch ?? { address in
            // Never the cookies of the tab you are in: what the card says is
            // what anyone would see, and a link you merely rest on is not a
            // sign-in.
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 6
            config.httpCookieStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            var request = URLRequest(url: address)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession(configuration: config).data(for: request)
            return data
        }
    }

    /// What the card says about this address, from the cache when it can be.
    /// Answers nil when there is nothing worth drawing or the page can't be
    /// read — a card is an addition, never a reason to say anything went wrong.
    func summary(for url: URL) async -> LinkCardSummary? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let key = url.absoluteString
        if let known = cache[key] { return known.isWorthShowing ? known : nil }
        if let running = asking[key] { return await running.value }
        let work = Task { [fetch] () -> LinkCardSummary? in
            let data: Data
            do {
                data = try await fetch(url)
            } catch {
                return nil
            }
            // The head of a page is where all of this lives; a page that sends
            // megabytes is not worth reading for a card.
            guard data.count <= 1_000_000,
                  let html = String(data: data.prefix(512_000), encoding: .utf8) else { return nil }
            return LinkCards.read(html, at: url)
        }
        asking[key] = work
        let summary = await work.value
        asking[key] = nil
        if let summary {
            remember(summary, for: key)
        } else {
            // A page that gave nothing is remembered as such, so a link is not
            // asked for twice.
            remember(LinkCardSummary(url: url, title: "", summary: "", icon: nil), for: key)
        }
        return summary?.isWorthShowing == true ? summary : nil
    }

    private func remember(_ summary: LinkCardSummary, for key: String) {
        if cache[key] == nil { order.append(key) }
        cache[key] = summary
        while order.count > kept, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }

    /// Forgets everything, for a test or for someone who asks.
    func forget() {
        cache.removeAll()
        order.removeAll()
    }

    // MARK: - reading the page

    /// The card out of a page's own text: its title, its description and the
    /// icon it names. Open Graph first, as a page with one means it, then the
    /// plain tags. Each attribute is read with its own quote, so an apostrophe
    /// inside a title is a character and not the end of it; tags come out
    /// before entities are undone, so `&lt;3` can never become one.
    nonisolated static func read(_ html: String, at url: URL) -> LinkCardSummary {
        func captured(_ patterns: [String]) -> String? {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, options: [], range: range) else { continue }
                for group in 1..<match.numberOfRanges {
                    guard let found = Range(match.range(at: group), in: html) else { continue }
                    let text = tidy(String(html[found]))
                    if !text.isEmpty { return text }
                }
            }
            return nil
        }

        let title = captured([
            #"<meta[^>]+property=["']og:title["'][^>]*content=(?:"([^"]*)"|'([^']*)')"#,
            #"<meta[^>]+content=(?:"([^"]*)"|'([^']*)')[^>]*property=["']og:title["']"#,
            #"<title[^>]*>(.*?)</title>"#,
        ]) ?? ""

        let summary = captured([
            #"<meta[^>]+property=["']og:description["'][^>]*content=(?:"([^"]*)"|'([^']*)')"#,
            #"<meta[^>]+name=["']description["'][^>]*content=(?:"([^"]*)"|'([^']*)')"#,
            #"<meta[^>]+content=(?:"([^"]*)"|'([^']*)')[^>]*name=["']description["']"#,
        ]) ?? ""

        let iconText = captured([
            #"<link[^>]+rel=["'](?:shortcut )?icon["'][^>]*href=(?:"([^"]*)"|'([^']*)')"#,
            #"<link[^>]+href=(?:"([^"]*)"|'([^']*)')[^>]*rel=["'](?:shortcut )?icon["']"#,
            #"<meta[^>]+property=["']og:image["'][^>]*content=(?:"([^"]*)"|'([^']*)')"#,
        ])

        return LinkCardSummary(url: url,
                               title: title,
                               summary: summary,
                               icon: iconText.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL })
    }

    /// Tags out first, then the entities a title is likely to carry, then runs
    /// of space made one. Order matters: undoing `&lt;` before the tags were
    /// taken out would make a tag of it.
    nonisolated static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - drawing it

/// The card itself, over the page's bottom edge where the address bubble is,
/// with the icon the page named when it named one.
struct LinkCardView: View {
    let card: LinkCardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if let icon = card.icon {
                    AsyncImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                }
                Text(card.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(card.host)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: 320, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
    }
}
