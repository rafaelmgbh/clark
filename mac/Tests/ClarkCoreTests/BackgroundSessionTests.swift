import XCTest
@testable import ClarkCore

/// A conversa que o Claude Code mandou para segundo plano: o `claude` do agente sai e ela segue num
/// processo próprio, que se reabre com `claude attach <job>`.
final class BackgroundSessionTests: XCTestCase {
    private let temp = TemporaryDirectory()
    private let job = "a1b2c3d4"
    private let id = "a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let alive: Set<Int32> = [50123]

    @discardableResult
    private func session(pid: Int32, _ body: String) -> String {
        temp.write("sessions/\(pid).json", body)
    }

    private func background(pid: Int32 = 50123, job: String? = nil, id: String? = nil, kind: String = "bg") {
        session(pid: pid, #"{"pid": \#(pid), "kind": "\#(kind)", "jobId": "\#(job ?? self.job)", "#
                + #""sessionId": "\#(id ?? self.id)", "status": "waiting"}"#)
    }

    private func live(job: String) -> BackgroundSession? {
        BackgroundSession.live(configDir: temp.path, jobID: job) { self.alive.contains($0) }
    }

    private func live(session: String) -> BackgroundSession? {
        BackgroundSession.live(configDir: temp.path, sessionID: session) { self.alive.contains($0) }
    }

    // MARK: o anúncio na saída

    /// O que o `claude` escreve ao mandar a conversa para segundo plano, logo antes de sair.
    func testJobComesFromTheMessageTheClaudeLeavesOnExit() {
        let screen = ["  ⎿  feito", "", "backgrounded · a1b2c3d4",
                      "  claude agents             list sessions",
                      "  claude attach a1b2c3d4    open in this terminal",
                      "  claude logs a1b2c3d4      show recent output"]
        XCTAssertEqual(BackgroundSession.handoff(in: screen), job)
        XCTAssertEqual(BackgroundSession.handoff(in: ["backgrounded · a1b2c3d4 · api (worktree handed off)"]), job)
    }

    func testOnlyTheLastAnnouncementCounts() {
        XCTAssertEqual(BackgroundSession.handoff(in: ["backgrounded · aaaaaaaa", "backgrounded · bbbbbbbb"]), "bbbbbbbb")
    }

    func testScreensWithoutTheAnnouncementHaveNoJob() {
        for screen in [[], ["Nothing to background — exiting."], ["o agente disse backgrounded · a1b2c3d4"],
                       ["backgrounded · "], ["backgrounded · --dangerously-skip-permissions"],
                       ["backgrounded · a1b2c3d4;rm"], ["backgrounded a1b2c3d4"]] {
            XCTAssertNil(BackgroundSession.handoff(in: screen), "\(screen)")
        }
    }

    // MARK: o processo que segue a conversa

    func testLiveJobIsFoundByItsID() {
        background(id: "A1B2C3D4-5E6F-4A7B-8C9D-0E1F2A3B4C5D")
        XCTAssertEqual(live(job: job), BackgroundSession(jobID: job, sessionID: id))
        XCTAssertNil(live(job: "deadbeef"))
    }

    func testLiveJobIsFoundByTheConversationItContinues() {
        background()
        XCTAssertEqual(live(session: id.uppercased()), BackgroundSession(jobID: job, sessionID: id))
        XCTAssertNil(live(session: SessionLocator.newID()))
        XCTAssertNil(live(session: "nao-e-uuid"))
    }

    func testJobWhoseProcessIsGoneIsNotLive() {
        background(pid: 777)
        XCTAssertNil(live(job: job))
        XCTAssertNil(live(session: id))
    }

    func testInteractiveSessionsAreNotJobs() {
        background(kind: "interactive")
        XCTAssertNil(live(job: job))
        session(pid: 50123, #"{"pid": 50123, "jobId": "a1b2c3d4", "sessionId": "\#(id)"}"#)
        XCTAssertNil(live(job: job))
    }

    func testFileThatDoesNotMatchItsProcessOrIsMalformedIsIgnored() {
        session(pid: 50123, #"{"pid": 1234, "kind": "bg", "jobId": "a1b2c3d4", "sessionId": "\#(id)"}"#)
        XCTAssertNil(live(job: job))
        for body in [#"{"pid": 50123, "kind": "bg", "jobId": "a1b2c3d4", "sessionId": "abc"}"#,
                     #"{"pid": 50123, "kind": "bg", "jobId": "-rm", "sessionId": "\#(id)"}"#,
                     #"{"pid": 50123, "kind": "bg", "sessionId": "\#(id)"}"#, "[]", "bg"] {
            session(pid: 50123, body)
            XCTAssertNil(live(session: id), body)
        }
    }

    func testFilesThatAreNotSessionsAreIgnored() {
        temp.write("sessions/notas.json", #"{"pid": 50123, "kind": "bg", "jobId": "a1b2c3d4", "sessionId": "\#(id)"}"#)
        temp.makeDirectory("sessions/50123.json")
        XCTAssertNil(live(job: job))
    }

    func testWithoutTheSessionsFolderThereIsNoJob() {
        XCTAssertNil(live(job: job))
    }

    func testTheProcessOfThisTestIsAlive() {
        XCTAssertTrue(BackgroundSession.processIsAlive(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(BackgroundSession.processIsAlive(0))
        XCTAssertFalse(BackgroundSession.processIsAlive(-1))
    }
}
