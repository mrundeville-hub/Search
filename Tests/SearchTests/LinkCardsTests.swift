import XCTest
@testable import Search

/// A card about the link under the pointer: what a page says about itself, and
/// asking once.
final class LinkCardsTests: XCTestCase {
    private func page(_ head: String) -> String {
        "<!doctype html><html><head>\(head)</head><body><p>Body text</p></body></html>"
    }

    func testTitleDescriptionAndIcon() {
        let card = LinkCards.read(page("""
        <title>Plain title</title>
        <meta name="description" content="A page about things">
        <link rel="shortcut icon" href="/favicon.ico">
        """), at: URL(string: "https://example.com/some/page")!)
        XCTAssertEqual(card.title, "Plain title")
        XCTAssertEqual(card.summary, "A page about things")
        XCTAssertEqual(card.icon?.absoluteString, "https://example.com/favicon.ico",
                       "a made-up address is resolved against the page's")
        XCTAssertEqual(card.host, "example.com")
        XCTAssertTrue(card.isWorthShowing)
    }

    func testOpenGraphWins() {
        let card = LinkCards.read(page("""
        <title>Plain title</title>
        <meta property="og:title" content="The page's own title">
        <meta property="og:description" content="How it wants to be described">
        <meta property="og:image" content="https://cdn.example.com/picture.png">
        """), at: URL(string: "https://example.com/")!)
        XCTAssertEqual(card.title, "The page's own title")
        XCTAssertEqual(card.summary, "How it wants to be described")
        XCTAssertEqual(card.icon?.absoluteString, "https://cdn.example.com/picture.png")
    }

    func testContentBeforeNameStillReads() {
        let card = LinkCards.read(page("""
        <title>Kept</title>
        <meta content="Description first, name second" name="description">
        """), at: URL(string: "https://example.com/")!)
        XCTAssertEqual(card.summary, "Description first, name second")
    }

    func testEntitiesAndTagsAreUndone() {
        let card = LinkCards.read(page("""
        <title>Tom &amp; Jerry &lt;3  <b>bold</b>   spaced</title>
        """), at: URL(string: "https://example.com/")!)
        XCTAssertEqual(card.title, "Tom & Jerry <3 bold spaced")
    }

    func testNoTitleIsNotWorthDrawing() {
        let card = LinkCards.read(page("<meta name=\"description\" content=\"only a description\">"),
                                  at: URL(string: "https://example.com/")!)
        XCTAssertEqual(card.title, "")
        XCTAssertFalse(card.isWorthShowing)
    }

    @MainActor
    func testAnAddressIsAskedForOnce() async {
        let counter = Counter()
        let cards = LinkCards(fetch: { address in
            await counter.bump()
            return Data("""
            <title>Fetched once</title><meta name="description" content="asked one time">
            """.utf8)
        })
        let url = URL(string: "https://example.com/page")!

        let first = await cards.summary(for: url)
        let second = await cards.summary(for: url)
        XCTAssertEqual(first?.title, "Fetched once")
        XCTAssertEqual(second?.title, "Fetched once")
        let asked = await counter.count
        XCTAssertEqual(asked, 1, "the second look comes out of the cache")

        cards.forget()
        _ = await cards.summary(for: url)
        let askedAgain = await counter.count
        XCTAssertEqual(askedAgain, 2, "forgetting asks again")
    }

    @MainActor
    func testAFailedPageIsNothingAndIsNotAskedTwice() async {
        let counter = Counter()
        let cards = LinkCards(fetch: { _ in
            await counter.bump()
            throw URLError(.cannotConnectToHost)
        })
        let url = URL(string: "https://example.com/gone")!
        let first = await cards.summary(for: url)
        let second = await cards.summary(for: url)
        XCTAssertNil(first)
        XCTAssertNil(second)
        let asked = await counter.count
        XCTAssertEqual(asked, 1, "a page that failed is remembered as having nothing")
    }

    @MainActor
    func testOnlyWebAddressesAreAskedFor() async {
        let counter = Counter()
        let cards = LinkCards(fetch: { _ in
            await counter.bump()
            return Data("<title>x</title>".utf8)
        })
        let internalPage = await cards.summary(for: URL(string: "search://history")!)
        let mail = await cards.summary(for: URL(string: "mailto:someone@example.com")!)
        XCTAssertNil(internalPage)
        XCTAssertNil(mail)
        let asked = await counter.count
        XCTAssertEqual(asked, 0)
    }
}

/// How many times the page was asked for, from anywhere.
private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
