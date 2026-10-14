import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A conversa que o agente guarda no `config.json` é a que o `claude` dele está seguindo: ela troca
/// com `/clear` e `/resume`, e vai para outro processo quando a conversa segue em segundo plano.
final class AgentConversationTests: XCTestCase {
    private var fixture: ClarkFixture!
    private let job = "a1b2c3d4"
    private let id = "a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    /// O processo destes testes: um pid que está vivo.
    private let livePid = ProcessInfo.processInfo.processIdentifier
    /// O que o `claude` escreve ao mandar a conversa para segundo plano, logo antes de sair.
    private let handoff = #"printf 'backgrounded \302\267 a1b2c3d4\n  claude attach a1b2c3d4    open in this terminal\n'"#

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        fixture = ClarkFixture()
    }

    override func tearDown() {
        fixture.shutdown()
        fixture = nil
        super.tearDown()
    }

    private func lines(_ pane: AgentPaneView) -> [String] {
        pane.terminal.linesAboveCursor()
    }

    private func saved() -> [String?] {
        fixture.store.load().config.agents.map(\.sessionID)
    }

    /// O arquivo em que o Claude Code descreve a sessão do processo `pid`.
    private func session(pid: Int32, kind: String = "interactive", job: String? = nil, sessionID: String) {
        let jobField = job.map { #", "jobId": "\#($0)""# } ?? ""
        fixture.temp.write(".claude/sessions/\(pid).json",
                           #"{"pid": \#(pid), "kind": "\#(kind)", "status": "idle", "sessionId": "\#(sessionID)"\#(jobField)}"#)
    }

    private func backgroundJob(pid: Int32? = nil) {
        session(pid: pid ?? livePid, kind: "bg", job: job, sessionID: id)
    }

    private func restored(claude script: String) -> AgentPaneView {
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "API", cwd: fixture.home, sessionID: id, tone: nil)]
        return fixture.started(config: config, claude: fixture.fakeClaude(script)).panes[0]
    }

    // MARK: troca de conversa no mesmo processo

    func testAgentFollowsTheConversationTheClaudeSwitchedTo() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        let cleared = SessionLocator.newID()
        session(pid: pane.terminal.process.shellPid, sessionID: cleared.uppercased())
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.sessionID, cleared)
        XCTAssertEqual(saved(), [cleared], "a conversa nova é a que volta ao reabrir")
    }

    func testFileWithoutAConversationKeepsTheOneTheAgentHas() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        let before = pane.sessionID
        session(pid: pane.terminal.process.shellPid, sessionID: "nao-e-uuid")
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.sessionID, before)
        XCTAssertEqual(saved(), [before])
    }

    // MARK: conversa em segundo plano

    func testConversationSentToTheBackgroundIsTheOneTheAgentKeeps() {
        backgroundJob()
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(handoff))
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { pane.state == .exited })
        fixture.now += 1
        controller.tick()
        XCTAssertEqual(pane.sessionID, id)
        XCTAssertEqual(saved(), [id])
    }

    /// O anúncio pode chegar antes de o processo em segundo plano gravar o arquivo dele.
    func testJobThatShowsUpAfterTheExitIsStillFollowed() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(handoff))
        let pane = controller.panes[0]
        let before = pane.sessionID
        XCTAssertTrue(waitUntil { pane.state == .exited })
        fixture.now += 1
        controller.tick()
        XCTAssertEqual(pane.sessionID, before)

        backgroundJob()
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.sessionID, id)
        XCTAssertEqual(saved(), [id])
    }

    func testExitWithoutTheAnnouncementKeepsTheConversation() {
        backgroundJob()
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("echo tchau"))
        let pane = controller.panes[0]
        let before = pane.sessionID
        XCTAssertTrue(waitUntil { pane.state == .exited })
        fixture.now += 1
        controller.tick()
        XCTAssertEqual(pane.sessionID, before)
    }

    func testRestoredAgentWhoseConversationRunsInTheBackgroundReattaches() {
        backgroundJob()
        let pane = restored(claude: #"echo "ARGS=$*"; echo FIM; read x"#)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertTrue(lines(pane).contains("ARGS=attach \(job)"), "\(lines(pane))")
        XCTAssertEqual(pane.sessionID, id)
    }

    /// Reaberto pelo `attach`, o processo do agente só mostra o job: a conversa é a que o job segue.
    func testAttachedAgentFollowsTheJobAndNotItsOwnProcess() {
        backgroundJob()
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "API", cwd: fixture.home, sessionID: id, tone: nil)]
        let controller = fixture.started(config: config, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        session(pid: pane.terminal.process.shellPid, sessionID: SessionLocator.newID())
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.sessionID, id)

        let cleared = SessionLocator.newID()
        session(pid: livePid, kind: "bg", job: job, sessionID: cleared)
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.sessionID, cleared)
        XCTAssertEqual(saved(), [cleared])
    }

    func testRestoredAgentWhoseBackgroundJobEndedResumesTheConversation() {
        backgroundJob(pid: Int32.max - 1)
        fixture.temp.write(".claude/projects/-um-projeto/\(id).jsonl", "{}\n")
        let pane = restored(claude: #"echo "ARGS=$*"; echo FIM; read x"#)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertTrue(lines(pane).contains("ARGS=--resume \(id)"), "\(lines(pane))")
    }

    /// Com a conversa escolhida pelas flags do agente, o CLARK não troca a escolha.
    func testSessionFlagsOfTheAgentWinOverTheBackgroundJob() {
        backgroundJob()
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "API", cwd: fixture.home, sessionID: id, tone: nil)]
        let pane = fixture.started(config: config, claude: fixture.fakeClaude(#"echo "ARGS=$*"; echo FIM; read x"#),
                                   claudeArgs: ["--continue"]).panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertTrue(lines(pane).contains("ARGS=--continue"), "\(lines(pane))")
    }
}
