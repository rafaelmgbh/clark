import XCTest
@testable import ClarkCore

final class CodexSessionsTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private let now = Date(timeIntervalSince1970: 1_792_160_000)
    private let day: TimeInterval = 24 * 60 * 60
    private var serial = 0

    override func setUp() {
        super.setUp()
        temp = TemporaryDirectory()
        serial = 0
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private var codexHome: String { temp.path + "/.codex" }

    /// Grava uma conversa do Codex como ele grava: na pasta do dia, com a pasta de trabalho na primeira linha.
    @discardableResult
    private func rollout(cwd: String, age: TimeInterval = 60, events: [String] = [], id: String? = nil) -> (id: String, path: String) {
        serial += 1
        let id = id ?? String(format: "01a14518-c19d-7260-8caf-%012x", serial)
        let date = now.addingTimeInterval(-age)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let folder = String(format: ".codex/sessions/%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
        let meta = #"{"timestamp":"x","type":"session_meta","payload":{"session_id":"\#(id)","id":"\#(id)","timestamp":"x","cwd":"\#(cwd)","base_instructions":"\#(String(repeating: "a", count: 9000))"}}"#
        let lines = [meta] + events.map { #"{"timestamp":"x","type":"event_msg","payload":{"type":"\#($0)"}}"# }
        let path = temp.write(folder + "/rollout-2026-10-16T11-23-32-\(id).jsonl", lines.joined(separator: "\n") + "\n")
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        return (id, path)
    }

    func testHomeFollowsCodexHome() {
        XCTAssertEqual(CodexSessions.home(environment: [:], home: "/Users/eu"), "/Users/eu/.codex")
        XCTAssertEqual(CodexSessions.home(environment: ["CODEX_HOME": "~/outro"], home: "/Users/eu"), "/Users/eu/outro")
    }

    func testFindsTheConversationByItsID() {
        let old = rollout(cwd: "/p/api", age: 90 * day)
        XCTAssertEqual(CodexSessions.path(of: old.id, codexHome: codexHome), old.path, "retomar vale para conversa antiga")
        XCTAssertNil(CodexSessions.path(of: "01a14518-c19d-7260-8caf-ffffffffffff", codexHome: codexHome))
        XCTAssertNil(CodexSessions.path(of: "../../etc", codexHome: codexHome), "só UUID")
    }

    func testReadsTheFolderFromTheFirstLine() {
        let session = rollout(cwd: "/p/a\\\"spa")
        XCTAssertEqual(CodexSessions.cwd(path: session.path), "/p/a\"spa")
    }

    func testNewConversationOfTheAgentIsTheFirstInItsFolderAfterItOpened() {
        rollout(cwd: "/p/api", age: 600)
        let mine = rollout(cwd: "/p/api", age: 50)
        let other = rollout(cwd: "/p/api", age: 40)
        rollout(cwd: "/p/site", age: 55)
        let since = now.addingTimeInterval(-60)
        XCTAssertEqual(CodexSessions.newSession(codexHome: codexHome, directory: "/p/api", since: since,
                                                excluding: [], now: now, canonicalize: { $0 }), mine.id)
        XCTAssertEqual(CodexSessions.newSession(codexHome: codexHome, directory: "/p/api", since: since,
                                                excluding: [mine.id], now: now, canonicalize: { $0 }), other.id,
                       "a conversa de outro agente aberto fica de fora")
        XCTAssertNil(CodexSessions.newSession(codexHome: codexHome, directory: "/p/nada", since: since,
                                              excluding: [], now: now, canonicalize: { $0 }))
    }

    func testBusyWhileTheLastTurnHasNotEnded() {
        XCTAssertFalse(CodexSessions.isBusy(path: rollout(cwd: "/p", events: []).path))
        XCTAssertTrue(CodexSessions.isBusy(path: rollout(cwd: "/p", events: ["task_started", "agent_message"]).path))
        XCTAssertFalse(CodexSessions.isBusy(path: rollout(cwd: "/p", events: ["task_started", "task_complete"]).path))
        XCTAssertFalse(CodexSessions.isBusy(path: rollout(cwd: "/p", events: ["task_started", "turn_aborted"]).path),
                       "Esc interrompe o turno")
        XCTAssertTrue(CodexSessions.isBusy(path: rollout(cwd: "/p", events: ["task_started", "task_complete",
                                                                                "task_started"]).path))
        XCTAssertFalse(CodexSessions.isBusy(path: temp.path + "/nao-existe.jsonl"))
    }

    func testUsageCountsConversationsPerFolderInsideTheWindow() {
        rollout(cwd: "/p/api", age: 3 * day)
        rollout(cwd: "/p/api", age: 600)
        rollout(cwd: "/p/site", age: 60)
        rollout(cwd: "/p/velho", age: ProjectUsage.window + day)
        let usage = CodexSessions.usage(codexHome: codexHome, now: now, canonicalize: { $0 })
        XCTAssertEqual(usage["/p/api"], ProjectUsage.Count(conversations: 2, latest: now.addingTimeInterval(-600)))
        XCTAssertEqual(usage["/p/site"]?.conversations, 1)
        XCTAssertNil(usage["/p/velho"])
    }

    func testCodexUsageAddsToTheClaudeCount() {
        let extra = ["/p/site": ProjectUsage.Count(conversations: 3, latest: now)]
        XCTAssertEqual(ProjectUsage.mostUsed(["/p/api", "/p/site"], configDir: temp.path + "/.claude", now: now,
                                             extra: extra), ["/p/site"])
    }
}
