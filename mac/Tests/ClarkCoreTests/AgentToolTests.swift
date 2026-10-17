import XCTest
@testable import ClarkCore

final class AgentToolTests: XCTestCase {
    func testCodexIsFoundInThePathFirstAndThenInTheUsualPlaces() {
        let found = CodexLocator.find(path: "/a:rel:/b", home: "/Users/eu") { $0 == "/b/codex" || $0 == "/opt/homebrew/bin/codex" }
        XCTAssertEqual(found, "/b/codex")
        XCTAssertEqual(CodexLocator.find(path: nil, home: "/Users/eu") { $0 == "/opt/homebrew/bin/codex" },
                       "/opt/homebrew/bin/codex")
        XCTAssertNil(CodexLocator.find(path: "rel", home: "/Users/eu") { !$0.hasPrefix("/") }, "PATH relativo não vale")
    }

    func testEachToolHasItsOwnAutomaticName() {
        XCTAssertEqual(AgentNaming.automaticName(existing: ["AGENT 1"], tool: .codex), "CODEX 1")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["CODEX 1", "AGENT 2"], tool: .codex), "CODEX 2")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["CODEX 1"]), "AGENT 1", "o Claude segue com AGENT")
        XCTAssertEqual(AgentNaming.automaticNumber("CODEX 3", tool: .codex), 3)
        XCTAssertNil(AgentNaming.automaticNumber("CODEX 3"))
    }

    func testToolIsSavedOnlyWhenItIsNotClaude() {
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "A", cwd: "/a", sessionID: nil, tone: 0),
                         SavedAgent(name: "B", cwd: "/b", sessionID: nil, tone: 1, tool: .codex)]
        let entries = config.jsonObject()["agents"] as? [[String: Any]]
        XCTAssertNil(entries?[0]["tool"], "o padrão não suja o arquivo")
        XCTAssertEqual(entries?[1]["tool"] as? String, "codex")
        XCTAssertEqual(ClarkConfig(json: config.jsonObject()).agents.map(\.tool), [.claude, .codex])
    }

    func testUnknownToolFallsBackToClaude() {
        let config = ClarkConfig(json: ["agents": [["name": "A", "tool": "gemini"], ["name": "B", "tool": 3]]])
        XCTAssertEqual(config.agents.map(\.tool), [.claude, .claude])
    }
}
