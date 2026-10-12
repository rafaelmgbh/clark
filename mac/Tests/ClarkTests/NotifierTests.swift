import UserNotifications
import XCTest
@testable import Clark

final class NotifierTests: XCTestCase {
    func testNoticeNamesTheAgentAndWhereItWorks() {
        let content = Notifier.content(name: "AGENT 3", place: "ACME › Api", sessionID: "sessao-3")
        XCTAssertEqual(content.title, "CLARK · AGENT 3")
        XCTAssertEqual(content.subtitle, "ACME › Api")
        XCTAssertEqual(content.body, "Terminou e está te esperando.")
        XCTAssertEqual(content.userInfo["session_id"] as? String, "sessao-3")
    }

    func testNoticeOfTheGlobalAgentHasNoSubtitle() {
        let content = Notifier.content(name: "AGENT 1", place: "", sessionID: "sessao-1")
        XCTAssertEqual(content.title, "CLARK · AGENT 1")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Terminou e está te esperando.")
    }
}
