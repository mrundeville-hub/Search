import XCTest
@testable import Search

final class SpaceChatTests: XCTestCase {
    @MainActor func testEachSpaceResumesOnlyItsOwnConversation() throws {
        let work = UUID(), personal = UUID()
        defer { Store.settings.removeObject(forKey: "chat.thread." + work.uuidString) }
        let thread = try XCTUnwrap(URL(string: "https://claude.ai/chat/" + UUID().uuidString.lowercased()))
        SpaceChat.remember(thread, for: work)
        XCTAssertEqual(SpaceChat.address(for: work), thread)
        XCTAssertEqual(SpaceChat.address(for: personal).path, "/new")
        SpaceChat.remember(try XCTUnwrap(URL(string: "https://example.org/chat/" + UUID().uuidString)), for: work)
        XCTAssertEqual(SpaceChat.address(for: work), thread)
        SpaceChat.remember(try XCTUnwrap(URL(string: "https://claude.ai/new")), for: work)
        XCTAssertEqual(SpaceChat.address(for: work).path, "/new")
    }
}
