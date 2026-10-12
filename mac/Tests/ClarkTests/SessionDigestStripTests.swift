import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A faixa `ULTIMA SESSAO` do painel: quando aparece, quando some e de que conversa ela fala.
final class SessionDigestStripTests: XCTestCase {
    private var fixture: ClarkFixture!
    private let previous = "11111111-1111-4111-8111-111111111111"
    private let older = "22222222-2222-4222-8222-222222222222"
    private let sentinel = "99999999-9999-4999-8999-999999999999"

    override func setUp() {
        super.setUp()
        fixture = ClarkFixture()
    }

    override func tearDown() {
        fixture.shutdown()
        fixture = nil
        super.tearDown()
    }

    /// `claude` de mentira que fica parado esperando, como o de verdade num agente novo.
    private var claude: String { fixture.fakeClaude("read x") }

    /// Conversa anterior na pasta, gravada onde o Claude Code grava: `~/.claude/projects/<pasta>/<id>.jsonl`.
    /// - Parameter age: há quantos segundos a conversa foi mexida.
    private func conversation(_ id: String, in directory: String, title: String, answer: String = "Feito.",
                              age: TimeInterval = 60) {
        let canonical = PathTools.canonical(directory, base: fixture.home, home: fixture.home)
        let folder = SessionDigestReader.projectFolder(canonicalDirectory: canonical, configDir: ".claude")
        let records: [[String: Any]] = [
            ["type": "ai-title", "aiTitle": title],
            ["type": "last-prompt", "lastPrompt": "pedido de " + title],
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": answer]]]],
        ]
        let lines = records.map { record in
            String(decoding: (try? JSONSerialization.data(withJSONObject: record)) ?? Data(), as: UTF8.self) + "\n"
        }
        let path = fixture.temp.write(folder + "/\(id).jsonl", lines.joined())
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: path)
    }

    /// Espera a leitura dos resumos terminar. A fila é uma só e anda em ordem: quando o agente de
    /// outro projeto, aberto por último, recebe o resumo dele, os pedidos de antes já foram atendidos.
    private func settle(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) {
        let other = fixture.temp.makeDirectory("Projetos/beta/site")
        conversation(sentinel, in: other, title: "Sentinela")
        controller.addAgents(1, in: other)
        let pane = controller.panes[controller.panes.count - 1]
        XCTAssertTrue(waitUntil { pane.digest != nil }, "a leitura não terminou", file: file, line: line)
    }

    func testNewAgentInAProjectShowsTheLastConversationOfTheFolder() throws {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(older, in: api, title: "Conversa antiga", age: 3600)
        conversation(previous, in: api, title: "Ajuste do relatório",
                     answer: "Total corrigido.\n\nFalta rodar a migração.")
        let controller = fixture.started(claude: claude)
        controller.openAgent(in: api)
        let pane = controller.panes[0]
        XCTAssertTrue(pane.startedNewConversation)
        XCTAssertNil(pane.digest, "a leitura do disco não segura a abertura do agente")
        XCTAssertTrue(waitUntil { pane.digest != nil })

        let digest = try XCTUnwrap(pane.digest)
        XCTAssertEqual(digest.title, "Ajuste do relatório")
        XCTAssertEqual(digest.prompt, "pedido de Ajuste do relatório")
        XCTAssertEqual(digest.answer, ["Total corrigido."])
        XCTAssertEqual(digest.pending, "Falta rodar a migração.")
        XCTAssertFalse(pane.digestView.isHidden)

        pane.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.digestView.frame.minY, pane.header.frame.maxY + 2, "logo abaixo do cabeçalho")
        XCTAssertEqual(pane.digestView.frame.height, CGFloat(SessionDigestView.height(for: digest)))
        XCTAssertEqual(pane.terminal.frame.minY, pane.digestView.frame.maxY + 4, "o terminal começa depois da faixa")
    }

    func testDigestGoesAwayWhenTheUserTypes() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(previous, in: api, title: "Ajuste do relatório")
        let controller = fixture.started(claude: claude)
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { pane.digest != nil })
        pane.layoutSubtreeIfNeeded()
        let withStrip = pane.terminal.frame

        pane.terminal.onUserInput?()
        XCTAssertNil(pane.digest)
        XCTAssertTrue(pane.digestView.isHidden)
        pane.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.terminal.frame.minY, pane.header.frame.maxY + 2 + 4, "o terminal volta a encostar no cabeçalho")
        XCTAssertGreaterThan(pane.terminal.frame.height, withStrip.height)
    }

    func testDigestGoesAwayOnClick() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(previous, in: api, title: "Ajuste do relatório")
        let controller = fixture.started(claude: claude)
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { pane.digest != nil })
        pane.digestView.onDismiss?()
        XCTAssertNil(pane.digest)
        XCTAssertTrue(pane.digestView.isHidden)
    }

    func testTypingBeforeTheDigestArrivesCancelsIt() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(previous, in: api, title: "Ajuste do relatório")
        let controller = fixture.started(claude: claude)
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]
        pane.terminal.onUserInput?()
        settle(controller)
        XCTAssertNil(pane.digest, "quem já está digitando não leva uma faixa no meio da tela")
    }

    func testGlobalAgentShowsNoDigest() {
        conversation(previous, in: fixture.home, title: "Assuntos da home")
        let controller = fixture.started(agents: 1, claude: claude)
        let pane = controller.panes[0]
        XCTAssertTrue(pane.isGlobal)
        XCTAssertTrue(pane.startedNewConversation)
        settle(controller)
        XCTAssertNil(pane.digest)
        XCTAssertTrue(pane.digestView.isHidden)
    }

    func testResumedConversationShowsNoDigest() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(older, in: api, title: "Conversa antiga", age: 3600)
        conversation(previous, in: api, title: "A conversa do agente")
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "API", cwd: api, sessionID: previous, tone: nil)]
        let controller = fixture.started(config: config, claude: claude)
        let pane = controller.panes[0]
        XCTAssertEqual(pane.sessionID, previous)
        XCTAssertFalse(pane.startedNewConversation)
        settle(controller)
        XCTAssertNil(pane.digest, "a conversa retomada já mostra a própria história")
    }

    func testAgentWithoutClaudeShowsNoDigest() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(previous, in: api, title: "Ajuste do relatório")
        let controller = fixture.started()
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(pane.digest, "no shell não há conversa para continuar")
    }

    func testConversationsOfOpenAgentsAreNotTheLastSession() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        conversation(previous, in: api, title: "Ajuste do relatório", age: 3600)
        let controller = fixture.started(claude: claude)
        controller.addAgents(1, in: api)
        let first = controller.panes[0]
        // O primeiro agente já conversou: o arquivo dele é o mais novo da pasta.
        conversation(first.sessionID, in: api, title: "Trabalho em andamento do agente 1", age: 0)

        controller.paneRequestsSibling(first)
        let second = controller.panes[1]
        XCTAssertTrue(waitUntil { second.digest != nil })
        XCTAssertEqual(second.digest?.title, "Ajuste do relatório", "a do agente ao lado está aberta, não é a última")
    }

    func testFolderWithoutPreviousConversationShowsNothing() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        let controller = fixture.started(claude: claude)
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]
        settle(controller)
        XCTAssertNil(pane.digest)
        XCTAssertTrue(pane.digestView.isHidden)
        pane.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.terminal.frame.minY, pane.header.frame.maxY + 2 + 4)
    }
}
