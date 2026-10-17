import AppKit
import ClarkCore
import XCTest
@testable import Clark

final class MainWindowControllerTests: XCTestCase {
    private var fixture: ClarkFixture!

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

    private func savedConfig() -> ClarkConfig {
        fixture.store.load().config
    }

    private func click() -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    // MARK: início

    func testStartsEmptyAndThenOpensAgents() {
        let controller = fixture.started()
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertNil(controller.currentPane)
        XCTAssertTrue(controller.visiblePanes.isEmpty)
        XCTAssertEqual(controller.window?.title, "CLARK — 0 agentes")

        controller.addAgents(2)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 2"])
        XCTAssertTrue(controller.mainPane === controller.panes[1], "o agente novo vira o principal")
        XCTAssertTrue(controller.focusedPane === controller.panes[1])
        XCTAssertTrue(controller.window?.firstResponder === controller.panes[1].terminal)
        XCTAssertEqual(controller.liveAgentCount, 2)
        XCTAssertEqual(controller.window?.title, "CLARK — 2 agentes")
    }

    func testOpensOneAgentInTheGlobalWhenNothingIsSaved() {
        let controller = fixture.started(openGlobal: true)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1"])
        XCTAssertEqual(controller.panes[0].directory, fixture.home)
        XCTAssertTrue(controller.panes[0].isGlobal)
        XCTAssertEqual(controller.panes[0].project, "GLOBAL")
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        XCTAssertTrue(controller.window?.firstResponder === controller.panes[0].terminal)
        XCTAssertEqual(savedConfig().agents.map(\.cwd), [fixture.home])
    }

    func testSavedAgentsComeBackInsteadOfTheGlobal() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let first = fixture.started()
        first.addAgents(1, in: project)
        first.shutdown()

        let second = fixture.started(openGlobal: true)
        XCTAssertEqual(second.panes.map(\.directory), [project], "com agente salvo, o GLOBAL não é aberto por conta")
    }

    func testCountOptionOpensAgentsInTheGlobal() {
        let controller = fixture.started(agents: 3)
        XCTAssertEqual(controller.panes.count, 3)
        XCTAssertEqual(Set(controller.panes.map(\.directory)), [fixture.home])
        XCTAssertEqual(Set(controller.panes.map(\.sessionID)).count, 3)
        XCTAssertTrue(controller.panes.allSatisfy { SessionLocator.isValidUUID($0.sessionID) })
    }

    func testDirectoryOptionOpensTheRequestedAgentsThere() {
        let project = fixture.temp.makeDirectory("Projetos/acme/app")
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = project
        options.count = 2
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(controller.panes.map(\.directory), [project, project])
        XCTAssertEqual(controller.panes.map(\.project), ["App", "App"])

        controller.addAgents(1)
        XCTAssertEqual(controller.panes[2].directory, fixture.home, "a pasta da linha de comando não vira padrão")
    }

    func testDirectoryOptionAloneOpensOneAgentThere() {
        let project = fixture.temp.makeDirectory("Projetos/acme/app")
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = project
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(controller.panes.map(\.directory), [project], "sem -n, `clark PASTA` é um agente na pasta")
    }

    func testMissingDirectoryOptionWarnsAndOpensInTheGlobal() {
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = fixture.home + "/nao-existe"
        options.count = 2
        controller.start(launch: fixture.launch(), options: options, startupWarnings: ["config.json invalido"])
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, fixture.home])
        XCTAssertEqual(controller.warnings.messages, [
            "config.json invalido",
            "claude nao encontrado: os agentes abrem o shell",
            "pasta nao encontrada: abrindo no GLOBAL",
        ])
    }

    func testMissingDirectoryOptionAloneStillOpensOneAgentInTheGlobal() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let first = fixture.started()
        first.addAgents(1, in: project)
        first.shutdown()

        let second = fixture.controller()
        var options = CLIOptions()
        options.directory = fixture.home + "/nao-existe"
        second.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(second.panes.map(\.directory), [project, fixture.home],
                       "o aviso fala em GLOBAL: o agente pedido abre lá, ao lado dos salvos")
    }

    func testSavedDirectoryThatVanishedFallsBackToHome() {
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "API", cwd: fixture.home + "/apagada", sessionID: nil, tone: nil)]
        let controller = fixture.started(config: config)
        XCTAssertEqual(controller.panes[0].directory, fixture.home)
        XCTAssertTrue(controller.panes[0].isGlobal)
    }

    func testOldDefaultFolderInTheConfigIsKeptButNoLongerUsed() {
        // O `cwd` das versões anteriores era a pasta do ⌘N. Hoje o GLOBAL do ⌘N abre na home; o valor fica no arquivo.
        let project = fixture.temp.makeDirectory("Projetos/acme")
        var config = ClarkConfig()
        config.cwd = project
        let controller = fixture.started(config: config)
        choose(item(controller.agentMenu(), "GLOBAL"))
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home])
        XCTAssertEqual(savedConfig().cwd, project)
    }

    func testAgentWhoseFolderVanishedStartsANewConversationAtHome() throws {
        // Worktree apagada entre uma abertura e outra: a conversa antiga é de outra pasta,
        // e o `claude --resume` não a acha da home. Sem conversa nova, o agente nasce em GAME OVER.
        let gone = fixture.temp.makeDirectory("Projetos/acme/worktree")
        let id = SessionLocator.newID()
        fixture.temp.write(".claude/projects/-um-projeto/\(id).jsonl", "{}\n")
        var config = ClarkConfig()
        config.agents = [
            SavedAgent(name: "API", cwd: gone, sessionID: id, tone: nil),
            SavedAgent(name: "WEB", cwd: gone, sessionID: SessionLocator.newID(), tone: nil),
        ]
        try FileManager.default.removeItem(atPath: gone)

        let controller = fixture.started(config: config, claude: fixture.fakeClaude(printEnvironment))
        let pane = controller.panes[0]
        XCTAssertEqual(pane.directory, fixture.home)
        XCTAssertNotEqual(pane.sessionID, id)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertTrue(lines(pane).contains("ARGS=--session-id \(pane.sessionID)"))
        XCTAssertEqual(controller.warnings.messages, ["pasta de agente sumiu: abriu na home, conversa nova"],
                       "um aviso só, mesmo com dois agentes na mesma situação")
        XCTAssertEqual(savedConfig().agents.map(\.sessionID), controller.panes.map(\.sessionID))
    }

    func testAgentLimit() {
        let controller = fixture.started()
        controller.addAgents(ClarkConfig.maxAgents + 4)
        XCTAssertEqual(controller.panes.count, ClarkConfig.maxAgents)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.count, ClarkConfig.maxAgents)
        XCTAssertEqual(controller.warnings.messages.last, "limite de 16 agentes: feche um para abrir outro",
                       "o + AGENT e o ⌘D não ficam mudos no limite")
        let item = NSMenuItem(title: "", action: #selector(MainWindowController.newAgent(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        let sibling = NSMenuItem(title: "", action: #selector(MainWindowController.newSiblingAgent(_:)),
                                 keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(sibling))
    }

    // MARK: layout

    func testFocusModeShowsOnePaneAndTheSidebar() {
        let controller = fixture.started(agents: 1)
        XCTAssertEqual(controller.layoutMode, "focus")
        XCTAssertTrue(controller.sidebar.isHidden, "um agente só não precisa de lista")

        controller.addAgents(2)
        XCTAssertFalse(controller.sidebar.isHidden)
        XCTAssertEqual(controller.sidebar.cards.count, 3)
        XCTAssertEqual(controller.visiblePanes.count, 1)
        XCTAssertTrue(controller.visiblePanes[0] === controller.panes[2])
        XCTAssertEqual(controller.panes.map(\.isHidden), [true, true, false])
        // Os ocultos ficam do tamanho do principal: trocar de agente não muda as colunas do terminal.
        XCTAssertEqual(Set(controller.panes.map { NSStringFromRect($0.frame) }).count, 1)
        XCTAssertLessThanOrEqual(controller.panes[2].frame.maxX, controller.sidebar.frame.minX)
        XCTAssertEqual(controller.sidebar.frame.width, CGFloat(SidebarView.width))
    }

    func testGridShowsEveryPaneWithoutOverlap() throws {
        let controller = fixture.started(agents: 4)
        controller.toggleLayout(nil)
        XCTAssertEqual(controller.layoutMode, "grid")
        XCTAssertTrue(controller.sidebar.isHidden)
        XCTAssertEqual(controller.visiblePanes.count, 4)
        XCTAssertFalse(controller.panes.contains(where: \.isHidden))
        XCTAssertEqual(controller.topBar.layoutButton.title, "GRADE")
        let content = try XCTUnwrap(controller.window?.contentView).bounds
        for (index, pane) in controller.panes.enumerated() {
            XCTAssertGreaterThan(pane.frame.width, 100)
            XCTAssertGreaterThan(pane.frame.height, 100)
            XCTAssertLessThanOrEqual(pane.frame.maxX, content.width)
            for other in controller.panes[(index + 1)...] {
                XCTAssertFalse(pane.frame.intersects(other.frame), "\(pane.name) sobre \(other.name)")
            }
        }
        XCTAssertEqual(savedConfig().layout, "grid")

        controller.toggleLayout(nil)
        XCTAssertEqual(controller.layoutMode, "focus")
        XCTAssertEqual(controller.visiblePanes.count, 1)
        XCTAssertEqual(controller.topBar.layoutButton.title, "FOCO")
    }

    func testZoomShowsOnlyOnePaneAndFollowsTheSelection() {
        let controller = fixture.started(agents: 3)
        controller.toggleLayout(nil)
        controller.toggleZoom(of: controller.panes[0])
        XCTAssertTrue(controller.zoomedPane === controller.panes[0])
        XCTAssertEqual(controller.panes.map(\.isHidden), [false, true, true])
        XCTAssertTrue(controller.currentPane === controller.panes[0])

        controller.select(controller.panes[2])
        XCTAssertTrue(controller.zoomedPane === controller.panes[2], "com zoom, selecionar troca o agente ampliado")
        XCTAssertEqual(controller.panes.map(\.isHidden), [true, true, false])

        controller.addAgents(1)
        XCTAssertTrue(controller.zoomedPane === controller.panes[3])

        controller.toggleZoom(nil)
        XCTAssertNil(controller.zoomedPane)
        XCTAssertEqual(controller.visiblePanes.count, 4)

        controller.toggleZoom(of: controller.panes[1])
        controller.toggleLayout(nil)
        XCTAssertNil(controller.zoomedPane, "trocar de layout desfaz o zoom")
    }

    func testSelectBringsTheAgentToTheMainPane() {
        let controller = fixture.started(agents: 3)
        let first = controller.panes[0]
        controller.select(first)
        XCTAssertTrue(controller.mainPane === first)
        XCTAssertTrue(controller.focusedPane === first)
        XCTAssertTrue(first.isFocused)
        XCTAssertFalse(controller.panes[2].isFocused)
        XCTAssertEqual(controller.panes.map(\.isHidden), [false, true, true])
        XCTAssertTrue(controller.window?.firstResponder === first.terminal)
        XCTAssertEqual(savedConfig().mainAgent, 0)
    }

    func testNextPreviousAndNumberShortcuts() {
        let controller = fixture.started(agents: 3)
        controller.nextAgent(nil)
        XCTAssertTrue(controller.mainPane === controller.panes[0], "depois do último vem o primeiro")
        controller.previousAgent(nil)
        XCTAssertTrue(controller.mainPane === controller.panes[2])

        let item = NSMenuItem(title: "", action: #selector(MainWindowController.selectAgentByNumber(_:)),
                              keyEquivalent: "2")
        item.tag = 2
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.selectAgentByNumber(item)
        XCTAssertTrue(controller.mainPane === controller.panes[1])

        item.tag = 7
        XCTAssertFalse(controller.validateMenuItem(item))
        controller.selectAgentByNumber(item)
        XCTAssertTrue(controller.mainPane === controller.panes[1], "número sem agente não faz nada")
    }

    func testFocusInGridMakesThePaneTheMainOne() {
        let controller = fixture.started(agents: 3)
        controller.toggleLayout(nil)
        controller.window?.makeFirstResponder(controller.panes[0].terminal)
        XCTAssertTrue(controller.focusedPane === controller.panes[0])
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        XCTAssertTrue(controller.currentPane === controller.panes[0])
        XCTAssertEqual(controller.sidebar.cards.map(\.isActive), [true, false, false])
    }

    // MARK: cards

    func testCardsMirrorTheAgents() {
        let controller = fixture.started(agents: 3)
        let cards = controller.sidebar.cards
        XCTAssertEqual(cards.map(\.snapshot.name), ["AGENT 1", "AGENT 2", "AGENT 3"])
        XCTAssertEqual(cards.map(\.index), [1, 2, 3])
        XCTAssertEqual(cards.map(\.isActive), [false, false, true])

        cards[0].onSelect?()
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        XCTAssertEqual(controller.sidebar.cards.map(\.isActive), [true, false, false])

        cards[1].onClose?()
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 3"])
        XCTAssertEqual(controller.sidebar.cards.map(\.index), [1, 2])
    }

    // MARK: fechar

    func testCloseMovesTheMainPaneToTheNeighbour() {
        let controller = fixture.started(agents: 3)
        let (first, second, third) = (controller.panes[0], controller.panes[1], controller.panes[2])
        controller.closeAgent(nil)
        XCTAssertEqual(controller.panes.count, 2)
        XCTAssertNil(third.superview)
        XCTAssertTrue(controller.mainPane === second)
        XCTAssertTrue(controller.window?.firstResponder === second.terminal)
        XCTAssertEqual(savedConfig().agents.map(\.name), ["AGENT 1", "AGENT 2"])

        controller.close(first)
        XCTAssertTrue(controller.mainPane === second)
        controller.close(second)
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertNil(controller.mainPane)
        XCTAssertNil(controller.focusedPane)
        XCTAssertEqual(savedConfig().agents.count, 0)
        XCTAssertEqual(controller.liveAgentCount, 0)
    }

    func testClosedNumberIsReused() {
        let controller = fixture.started(agents: 3)
        controller.close(controller.panes[1])
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 3", "AGENT 2"])
    }

    func testCloseAllChoices() {
        let controller = fixture.started(agents: 3)
        controller.select(controller.panes[0])
        let choices = controller.closeAllChoices()
        XCTAssertEqual(choices.map(\.title), ["Cancelar", "Só os outros (2)", "Todos (3)"])
        XCTAssertTrue(choices[0].panes.isEmpty)
        XCTAssertEqual(choices[1].panes.map(\.name), ["AGENT 2", "AGENT 3"])
        XCTAssertEqual(choices[2].panes.count, 3)

        choices[1].panes.forEach(controller.close)
        XCTAssertEqual(controller.closeAllChoices().map(\.title), ["Cancelar", "Todos (1)"])
    }

    // MARK: nome, pasta e fonte

    func testRenameSanitizesAndPersists() {
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        controller.applyRename(pane, text: "  api de pagamentos do cliente  ")
        XCTAssertEqual(pane.name, "API DE PAGAMENTOS DO")
        XCTAssertEqual(pane.header.snapshot.name, "API DE PAGAMENTOS DO")
        XCTAssertEqual(savedConfig().agents.first?.name, "API DE PAGAMENTOS DO")

        controller.applyRename(pane, text: "   ")
        XCTAssertEqual(pane.name, "API DE PAGAMENTOS DO", "nome vazio não troca nada")
    }

    func testEachAgentKeepsItsOwnFolder() {
        let project = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started(agents: 1)
        controller.addAgents(1, in: fixture.home + "/nao-existe")
        controller.addAgents(1, in: project)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, fixture.home, project, fixture.home],
                       "pasta que não existe cai na home; abrir num projeto não muda onde o próximo abre")
        XCTAssertEqual(controller.panes.map(\.project), ["GLOBAL", "GLOBAL", "Beta", "GLOBAL"])
    }

    func testNewAgentInTheSameFolder() {
        let project = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started()
        controller.addAgents(1, in: project)
        controller.paneRequestsSibling(controller.panes[0])
        XCTAssertEqual(controller.panes.map(\.directory), [project, project])
        XCTAssertNotEqual(controller.panes[0].sessionID, controller.panes[1].sessionID, "conversa nova, não a mesma")
        XCTAssertTrue(controller.mainPane === controller.panes[1])

        controller.select(controller.panes[0])
        controller.newSiblingAgent(nil)
        XCTAssertEqual(controller.panes.map(\.directory), [project, project, project], "⌘⇧N age sobre o agente atual")
    }

    func testFontScaleIsClampedAndReachesEveryTerminal() {
        let controller = fixture.started(agents: 2)
        controller.increaseFont(nil)
        XCTAssertEqual(controller.fontScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(controller.panes[0].terminal.font.pointSize, 13.2, accuracy: 0.01)
        XCTAssertEqual(controller.panes[1].terminal.font.pointSize, 13.2, accuracy: 0.01)
        XCTAssertEqual(savedConfig().fontScale, 1.1, accuracy: 0.0001)

        controller.setFontScale(99)
        XCTAssertEqual(controller.fontScale, 2.5)
        controller.setFontScale(-3)
        XCTAssertEqual(controller.fontScale, 0.6)
        controller.resetFont(nil)
        XCTAssertEqual(controller.fontScale, 1)
        controller.decreaseFont(nil)
        XCTAssertEqual(controller.fontScale, 0.9, accuracy: 0.0001)

        controller.addAgents(1)
        XCTAssertEqual(controller.panes[2].terminal.font.pointSize, 10.8, accuracy: 0.01, "agente novo já nasce na escala")
    }

    // MARK: salvar e restaurar

    func testAgentsComeBackAfterReopening() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let first = fixture.started(agents: 2)
        first.addAgents(1, in: project)
        first.applyRename(first.panes[1], text: "revisor")
        first.toggleLayout(nil)
        first.select(first.panes[1])
        let saved = first.panes.map { [$0.name, $0.directory, $0.sessionID, String($0.tone)] }
        first.shutdown()

        let second = fixture.started()
        XCTAssertEqual(second.panes.map { [$0.name, $0.directory, $0.sessionID, String($0.tone)] }, saved)
        XCTAssertEqual(second.panes.map(\.name), ["AGENT 1", "REVISOR", "AGENT 3"])
        XCTAssertEqual(second.layoutMode, "grid")
        XCTAssertTrue(second.mainPane === second.panes[1])
        XCTAssertEqual(second.panes.map(\.directory), [fixture.home, fixture.home, project])
    }

    func testCountOptionAddsToTheRestoredAgents() {
        fixture.started(agents: 2).shutdown()
        let controller = fixture.started(agents: 1)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 2", "AGENT 3"])
        XCTAssertTrue(controller.mainPane === controller.panes[2])
    }

    func testFreshIgnoresTheSavedAgents() {
        fixture.started(agents: 2).shutdown()
        let controller = fixture.controller()
        var options = CLIOptions()
        options.fresh = true
        controller.start(launch: fixture.launch(), options: options, openGlobalWhenEmpty: false)
        XCTAssertTrue(controller.panes.isEmpty)
    }

    func testFreshOpensTheGlobalInsteadOfTheSavedAgents() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let first = fixture.started()
        first.addAgents(2, in: project)
        let saved = first.panes.map(\.sessionID)
        first.shutdown()

        let controller = fixture.controller()
        var options = CLIOptions()
        options.fresh = true
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home])
        XCTAssertFalse(saved.contains(controller.panes[0].sessionID))
    }

    func testQuittingBeforeTheStartKeepsTheSavedAgents() {
        fixture.started(agents: 2).shutdown()
        // Fechou o app enquanto o ambiente do shell ainda era lido: a lista em memória está vazia.
        fixture.controller().shutdown()
        XCTAssertEqual(savedConfig().agents.count, 2)
    }

    func testRepeatedSessionIDGetsANewOne() {
        let id = SessionLocator.newID()
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "A", cwd: fixture.home, sessionID: id, tone: 0),
                         SavedAgent(name: "B", cwd: fixture.home, sessionID: id, tone: 1)]
        let controller = fixture.started(config: config)
        XCTAssertEqual(controller.panes[0].sessionID, id)
        XCTAssertNotEqual(controller.panes[1].sessionID, id, "duas abas na mesma conversa corromperiam o histórico")
    }

    func testUnknownConfigKeysSurviveASave() throws {
        fixture.temp.write(".config/clark/config.json", #"{"chave_do_futuro": {"x": 1}, "theme": "dark"}"#)
        let controller = fixture.started(agents: 1)
        controller.toggleLayout(nil)
        let data = try XCTUnwrap(FileManager.default.contents(atPath: fixture.store.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["chave_do_futuro"] as? [String: Int], ["x": 1])
        XCTAssertEqual(object["layout"] as? String, "grid")
    }

    func testConfigThatCannotBeSavedWarnsAndKeepsTheAgents() {
        // `~/.config/clark` é um arquivo: nada grava. O app segue aberto e avisa uma vez.
        fixture.temp.write(".config/clark", "nao sou uma pasta")
        let controller = fixture.started(agents: 2)
        controller.toggleLayout(nil)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.count, 3)
        XCTAssertEqual(controller.layoutMode, "grid")
        XCTAssertTrue(controller.panes.allSatisfy { $0.terminal.process.running })
        XCTAssertEqual(controller.warnings.messages, [
            "claude nao encontrado: os agentes abrem o shell",
            "config.json nao gravado: os agentes nao voltam ao reabrir",
        ])
    }

    func testSaveFailureWarningDoesNotComeBackAfterBeingDismissed() throws {
        fixture.temp.write(".config/clark", "nao sou uma pasta")
        let controller = fixture.started(agents: 2)
        let warning = "config.json nao gravado: os agentes nao voltam ao reabrir"
        XCTAssertTrue(controller.warnings.messages.contains(warning))
        // Um clique dispensa o aviso mostrado.
        let click = try XCTUnwrap(click())
        while !controller.warnings.messages.isEmpty { controller.warnings.mouseDown(with: click) }
        // Cada troca de agente grava de novo, e a gravação segue falhando.
        controller.select(controller.panes[0])
        controller.select(controller.panes[1])
        XCTAssertEqual(controller.warnings.messages, [])
    }

    // MARK: empresa e ambiente

    private let printEnvironment = """
    printf 'AGENTE=%s\\n' "$CLARK_AGENT"
    printf 'EMPRESA=%s\\n' "$CLARK_COMPANY"
    printf 'A=%s\\n' "${ACME_API_KEY:-vazio}"
    printf 'B=%s\\n' "${BETA_API_KEY:-vazio}"
    printf 'GH=%s\\n' "${GITHUB_TOKEN:-vazio}"
    printf 'PAI=%s\\n' "${CLAUDECODE:-vazio}"
    printf 'EDITOR=%s\\n' "$EDITOR"
    printf 'PASTA=%s\\n' "${PWD##*/}"
    printf 'ARGS=%s\\n' "$*"
    printf 'FIM\\n'
    read x
    """

    func testEachAgentGetsOnlyItsCompanyEnvironment() {
        let acme = fixture.temp.makeDirectory("Projetos/acme/api")
        let beta = fixture.temp.makeDirectory("clientes/beta")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [
          {"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"], "color": "#ff00ff"},
          {"name": "BETA", "paths": ["~/clientes/beta"], "env_allow": ["BETA_API_KEY"], "color": "#00ffff"}
        ]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        environment["BETA_API_KEY"] = "segredo-beta"
        environment["GITHUB_TOKEN"] = "segredo-global"
        environment["CLAUDECODE"] = "1"
        environment["EDITOR"] = "vim"
        let controller = fixture.started(claude: fixture.fakeClaude(printEnvironment), environment: environment)
        XCTAssertEqual(controller.warnings.messages, [])

        controller.addAgents(1, in: acme)
        controller.addAgents(1, in: beta)
        let (first, second) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(waitUntil { self.lines(first).contains("FIM") && self.lines(second).contains("FIM") })

        XCTAssertEqual(first.company.name, "ACME")
        XCTAssertEqual(Array(lines(first).prefix(9)), [
            "AGENTE=AGENT 1", "EMPRESA=ACME", "A=segredo-acme", "B=vazio", "GH=vazio", "PAI=vazio", "EDITOR=vim",
            "PASTA=api", "ARGS=--session-id \(first.sessionID)",
        ])
        XCTAssertEqual(first.removedVariables, ["BETA_API_KEY", "GITHUB_TOKEN"])
        XCTAssertEqual(first.color, RGB(r: 1, g: 0, b: 1))

        XCTAssertEqual(second.company.name, "BETA")
        XCTAssertEqual(Array(lines(second).prefix(9)), [
            "AGENTE=AGENT 2", "EMPRESA=BETA", "A=vazio", "B=segredo-beta", "GH=vazio", "PAI=vazio", "EDITOR=vim",
            "PASTA=beta", "ARGS=--session-id \(second.sessionID)",
        ])
        XCTAssertEqual(second.removedVariables, ["ACME_API_KEY", "GITHUB_TOKEN"])
        XCTAssertEqual(second.header.snapshot.company, "BETA")

        let menu = first.contextMenu()
        XCTAssertEqual(menu.items.last?.title, "Variáveis removidas (2)")
        XCTAssertEqual(menu.items.last?.submenu?.items.map(\.title), ["BETA_API_KEY", "GITHUB_TOKEN"])
    }

    func testLinkIntoAnotherCompanyCountsAsTheDestination() throws {
        // Um link dentro da pasta da ACME que aponta para a BETA: o agente mexe nos arquivos da BETA,
        // então é da BETA e não recebe a chave da ACME.
        let acme = fixture.temp.makeDirectory("Projetos/acme")
        let beta = fixture.temp.makeDirectory("Projetos/beta/api")
        try FileManager.default.createSymbolicLink(atPath: acme + "/atalho", withDestinationPath: beta)
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]}]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        let controller = fixture.started(claude: fixture.fakeClaude(printEnvironment), environment: environment)
        controller.addAgents(1, in: acme + "/atalho")
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertEqual(pane.company.name, "beta")
        XCTAssertTrue(lines(pane).contains("A=vazio"))
        XCTAssertEqual(pane.removedVariables, ["ACME_API_KEY"])
    }

    func testCompanyRuleOnAFolderCreatedLaterStillMatches() throws {
        // A regra da BETA é escrita por um link e aponta para uma pasta que só nasce depois de o
        // CLARK abrir. Sem resolver a parte que já existe, o agente cairia na ACME, a empresa de fora.
        let temp = fixture.temp
        temp.makeDirectory("Projetos/acme")
        try FileManager.default.createSymbolicLink(atPath: temp.path + "/trab",
                                                   withDestinationPath: temp.path + "/Projetos")
        temp.write(".config/clark/companies.json", """
        {"companies": [
          {"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]},
          {"name": "BETA", "paths": ["~/trab/acme/terceiro"], "env_allow": ["BETA_API_KEY"]}
        ]}
        """)
        let launch = fixture.launch()
        let company = launch.company(forDirectory: temp.makeDirectory("Projetos/acme/terceiro"))
        XCTAssertEqual(company.name, "BETA")
        XCTAssertEqual(company.envAllow, ["BETA_API_KEY"])
    }

    func testFolderOutsideAnyCompanyGetsNoSecret() {
        fixture.temp.write(".config/clark/companies.json", """
        {"env_allow": ["GITHUB_TOKEN"],
         "companies": [{"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]}]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        environment["GITHUB_TOKEN"] = "liberado-para-todos"
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(printEnvironment),
                                         environment: environment)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertEqual(pane.company.name, CompanyResolver.fallbackName)
        XCTAssertEqual(Array(lines(pane)[1...4]), ["EMPRESA=GLOBAL", "A=vazio", "B=vazio", "GH=liberado-para-todos"])
        XCTAssertEqual(pane.removedVariables, ["ACME_API_KEY"])
    }

    func testAgentsOfTheSameCompanyGetDifferentTones() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let other = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started()
        controller.addAgents(2, in: project)
        controller.addAgents(1, in: other)
        XCTAssertEqual(controller.panes.map(\.company.name), ["acme", "acme", "beta"])
        XCTAssertEqual(controller.panes.map(\.tone), [0, 1, 0])
        XCTAssertNotEqual(controller.panes[0].color, controller.panes[1].color)
        // O tom distingue os agentes no card. A etiqueta da empresa no cabeçalho é igual nos dois.
        XCTAssertEqual(controller.panes.map(\.snapshot.color), controller.panes.map(\.color))
        XCTAssertEqual(controller.panes.map(\.snapshot.companyColor), controller.panes.map(\.company.color))
        XCTAssertEqual(controller.panes[0].snapshot.companyColor, controller.panes[1].snapshot.companyColor)
    }

    func testSavedConversationIsResumed() {
        let id = SessionLocator.newID()
        fixture.temp.write(".claude/projects/-um-projeto/\(id).jsonl", "{}\n")
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "ANTIGO", cwd: fixture.home, sessionID: id, tone: 0)]
        let controller = fixture.started(agents: 1, config: config, claude: fixture.fakeClaude(printEnvironment),
                                         claudeArgs: ["--model", "opus"])
        let (old, new) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(waitUntil { self.lines(old).contains("FIM") && self.lines(new).contains("FIM") })
        XCTAssertTrue(lines(old).contains("ARGS=--model opus --resume \(id)"))
        XCTAssertTrue(lines(new).contains("ARGS=--model opus --session-id \(new.sessionID)"))
    }

    func testSkippingPermissionsShowsTheRedStrip() {
        let plain = fixture.started(agents: 1, claude: fixture.fakeClaude("read x")).panes[0]
        XCTAssertFalse(plain.bypassesPermissions)
        let plainImage = RenderedImage(plain, width: 660, height: 450)
        XCTAssertFalse(plainImage.isColor(Theme.dark.red, atX: 10, y: 37))
        let plainTop = plain.terminal.frame.minY

        let bypass = fixture.started(agents: 1, config: ClarkConfig(), claude: fixture.fakeClaude("read x"),
                                     claudeArgs: ["--dangerously-skip-permissions"]).panes[0]
        XCTAssertTrue(bypass.bypassesPermissions)
        let image = RenderedImage(bypass, width: 660, height: 450)
        XCTAssertTrue(image.isColor(Theme.dark.red, atX: 10, y: 37), "faixa SEM PERMISSOES")
        XCTAssertEqual(bypass.terminal.frame.minY - plainTop, CGFloat(AgentPaneView.stripHeight))

        // A coluna dos arquivos alterados fica abaixo da faixa, não por cima dela.
        bypass.frame = NSRect(x: 0, y: 0, width: 900, height: 450)
        bypass.toggleChangedFiles()
        bypass.layoutSubtreeIfNeeded()
        XCTAssertFalse(bypass.changedFiles.isHidden)
        XCTAssertEqual(bypass.changedFiles.frame.minY,
                       bypass.header.frame.maxY + 2 + CGFloat(AgentPaneView.stripHeight))
    }

    func testWithoutClaudeTheAgentOpensTheShellWithAWarning() {
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains { $0.contains("claude nao encontrado no PATH") } })
        XCTAssertNotEqual(pane.state, .exited)
        XCTAssertEqual(controller.liveAgentCount, 1)
    }

    func testWithoutClaudeTheMenuDoesNotClaimRemovedVariables() {
        // Sem `claude` o painel abre o shell de login, que relê o rc: o que saiu do ambiente pode voltar.
        var environment = fixture.environment
        environment["GITHUB_TOKEN"] = "segredo"
        let controller = fixture.started(agents: 1, environment: environment)
        let item = controller.panes[0].contextMenu().items.last
        XCTAssertEqual(item?.title, "Sem claude: o shell relê o rc e o filtro de variáveis não vale")
        XCTAssertEqual(item?.isEnabled, false)
        XCTAssertNil(item?.submenu)
    }

    // MARK: estados e avisos

    /// Leva o agente a WORKING por `seconds` e deixa a saída parar.
    private func work(_ pane: AgentPaneView, in controller: MainWindowController, seconds: Double) {
        pane.terminal.onUserInput?()
        fixture.now += 1
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .working)
        fixture.now += seconds
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 1.5
        controller.tick()
    }

    func testFinishedAgentNotifiesWhenNobodyIsLooking() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { false }
        controller.isWindowKey = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
        XCTAssertEqual(fixture.notifier.badges.last, 1)
        XCTAssertEqual(controller.window?.title, "(1) CLARK — 1 agentes")
        XCTAssertEqual(controller.topBar.stats.done, 1)
        XCTAssertEqual(controller.sidebar.cards.count, 1)

        // Voltar à janela com o agente em foco apaga o DONE.
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.badges.last, 0)
        XCTAssertEqual(controller.window?.title, "CLARK — 1 agentes")
    }

    func testWatchedAgentFinishesQuietly() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.done, [])
    }

    func testShortBurstOfOutputIsNotAFinishedTask() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(pane, in: controller, seconds: 0.5)
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.done, [])
    }

    func testHiddenAgentFinishingWithTheAppInFrontMarksDoneWithoutNotification() {
        let controller = fixture.started(agents: 2)
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        let hidden = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(hidden, in: controller, seconds: 4)
        XCTAssertEqual(hidden.state, .done)
        XCTAssertEqual(fixture.notifier.done, [], "com o app na frente, o card piscando já avisa")
        XCTAssertEqual(controller.sidebar.cards[0].snapshot.state, .done)

        controller.select(hidden)
        XCTAssertEqual(hidden.state, .idle)
    }

    func testBellMarksDone() {
        let controller = fixture.started(agents: 2)
        controller.isAppActive = { false }
        controller.panes[0].terminal.onBell?()
        XCTAssertEqual(controller.panes[0].state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
    }

    func testNotificationSaysWhereTheAgentWorks() {
        let api = fixture.temp.makeDirectory("Projetos/acme/api")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "ACME", "paths": ["~/Projetos/acme"]}]}
        """)
        let controller = fixture.started()
        controller.isAppActive = { false }
        controller.addAgents(1, in: api)
        controller.addAgents(1)

        controller.panes[0].terminal.onBell?()
        controller.panes[1].terminal.onBell?()
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1", "AGENT 2"])
        XCTAssertEqual(fixture.notifier.places, ["ACME › Api", ""], "o agente do GLOBAL não tem projeto para mostrar")
    }

    // MARK: comando em segundo plano

    /// Grava o arquivo em que o Claude Code diz o que a sessão do agente está fazendo.
    /// - Parameter bridge: nome da sessão remota, que o arquivo guarda enquanto o controle remoto dura.
    @discardableResult
    private func session(of pane: AgentPaneView, status: String, configDir: String = ".claude",
                         bridge: String? = nil) -> String {
        let pid = pane.terminal.process.shellPid
        let remote = bridge.map { ", \"bridgeSessionId\": \"\($0)\"" } ?? ""
        return fixture.temp.write("\(configDir)/sessions/\(pid).json",
                                  "{\"pid\": \(pid), \"kind\": \"interactive\", \"status\": \"\(status)\"\(remote)}")
    }

    func testAgentWithAShellInTheBackgroundShowsShellInsteadOfIdle() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        session(of: pane, status: "shell")
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .shell)
        XCTAssertEqual(controller.sidebar.cards[0].snapshot.state, .shell)
        XCTAssertEqual(controller.topBar.stats.working, 1)
        XCTAssertEqual(controller.topBar.stats.idle, 0)
        XCTAssertEqual(fixture.notifier.done, [])
    }

    func testShellIsRereadOncePerSecondUntilTheCommandEnds() throws {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        let path = session(of: pane, status: "shell")
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .shell)

        session(of: pane, status: "idle")
        fixture.now += AgentPaneView.activityInterval / 2
        controller.tick()
        XCTAssertEqual(pane.state, .shell)
        fixture.now += AgentPaneView.activityInterval / 2
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(controller.topBar.stats.idle, 1)
        XCTAssertEqual(controller.sidebar.cards[0].snapshot.state, .idle)

        // O claude apaga o arquivo quando sai: sem ele, o agente está só parado.
        session(of: pane, status: "shell")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.state, .shell)
        try FileManager.default.removeItem(atPath: path)
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
    }

    func testTurnThatLeavesAShellRunningNotifiesAndThenShowsShell() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        controller.isAppActive = { false }
        controller.isWindowKey = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        session(of: pane, status: "shell")
        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])

        // Ao voltar para o agente, o DONE dá lugar ao SHELL sem passar pelo IDLE.
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        XCTAssertEqual(pane.state, .shell)
    }

    /// Turno encerrado com agente em segundo plano: a tela para, mas o Claude Code segue dizendo `busy`.
    func testTurnThatLeavesAgentsRunningDoesNotNotifyUntilTheSessionIsFree() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        controller.isAppActive = { false }
        controller.isWindowKey = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        session(of: pane, status: "busy")
        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .working)
        XCTAssertEqual(fixture.notifier.done, [])

        // O rodapé redesenha os contadores dos agentes e para de novo: segue sem aviso.
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 3
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 1.5
        controller.tick()
        XCTAssertEqual(pane.state, .working)
        XCTAssertEqual(fixture.notifier.done, [])

        // Os agentes acabaram e o turno fechou: o aviso sai na releitura seguinte.
        session(of: pane, status: "idle")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
    }

    /// O aviso de verdade não espera a vez da releitura: quando a tela para, o arquivo é lido na hora.
    func testBusyReadJustBeforeTheTurnEndsDoesNotDelayTheNotification() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        controller.isAppActive = { false }
        controller.isWindowKey = { false }
        let pane = controller.panes[0]
        session(of: pane, status: "busy")
        fixture.now += 5
        controller.tick()

        pane.terminal.onUserInput?()
        fixture.now += 1
        pane.terminal.onOutput?()
        controller.tick()
        for _ in 1...5 {
            fixture.now += 0.6
            pane.terminal.onOutput?()
            controller.tick()
        }
        fixture.now += 0.6
        controller.tick()
        XCTAssertEqual(pane.state, .working)

        // O `busy` acabou de ser lido; o turno acaba 0,6 s depois.
        session(of: pane, status: "idle")
        fixture.now += 0.6
        controller.tick()
        XCTAssertEqual(pane.state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
    }

    func testAgentWithoutClaudeDoesNotLookForASessionFile() {
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        session(of: pane, status: "shell", bridge: "session_01AbC")
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
        XCTAssertFalse(pane.snapshot.remoteControl)
    }

    func testSessionFileLeftByAnOlderProcessIsIgnored() throws {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        let path = session(of: pane, status: "shell", bridge: "session_01AbC")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                              ofItemAtPath: path)
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
        XCTAssertFalse(pane.snapshot.remoteControl)
    }

    // MARK: controle remoto

    func testAgentWithRemoteControlOnSaysSoInTheHeaderAndInTheCard() throws {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        XCTAssertFalse(pane.header.snapshot.remoteControl)
        XCTAssertFalse(controller.sidebar.cards[0].snapshot.remoteControl)

        let path = session(of: pane, status: "idle", bridge: "session_01AbC")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertTrue(pane.header.snapshot.remoteControl)
        XCTAssertTrue(controller.sidebar.cards[0].snapshot.remoteControl)
        XCTAssertEqual(pane.state, .idle, "o controle remoto não é estado do agente")

        // Desligado no Claude Code, o aviso some na leitura seguinte.
        session(of: pane, status: "idle")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertFalse(pane.header.snapshot.remoteControl)
        XCTAssertFalse(controller.sidebar.cards[0].snapshot.remoteControl)

        // Sem o arquivo ninguém diz que o controle remoto está ligado.
        session(of: pane, status: "idle", bridge: "session_01AbC")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertTrue(pane.header.snapshot.remoteControl)
        try FileManager.default.removeItem(atPath: path)
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertFalse(pane.header.snapshot.remoteControl)
    }

    /// Trabalhando, o estado sai do terminal, mas o controle remoto só o arquivo conta.
    func testRemoteControlIsRereadOncePerSecondWhileTheAgentWorks() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        let step = { (seconds: Double) in
            self.fixture.now += seconds
            pane.terminal.onOutput?()
            controller.tick()
            XCTAssertEqual(pane.state, .working)
        }
        pane.terminal.onUserInput?()
        step(1)
        XCTAssertFalse(pane.snapshot.remoteControl)

        session(of: pane, status: "busy", bridge: "session_01AbC")
        step(AgentPaneView.activityInterval)
        XCTAssertTrue(pane.header.snapshot.remoteControl)
        XCTAssertTrue(controller.sidebar.cards[0].snapshot.remoteControl)

        session(of: pane, status: "busy")
        step(AgentPaneView.activityInterval / 2)
        XCTAssertTrue(pane.header.snapshot.remoteControl, "o arquivo não é relido a cada tique")
        step(AgentPaneView.activityInterval / 2)
        XCTAssertFalse(pane.header.snapshot.remoteControl)
        XCTAssertFalse(controller.sidebar.cards[0].snapshot.remoteControl)
    }

    /// O SHELL não espera a vez do controle remoto: ao fim do turno o arquivo é lido na hora.
    func testReadingRemoteControlWhileWorkingDoesNotDelayTheShellState() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        session(of: pane, status: "busy", bridge: "session_01AbC")
        fixture.now += 5
        controller.tick()

        pane.terminal.onUserInput?()
        fixture.now += 1
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 0.6
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 0.6
        controller.tick()
        XCTAssertEqual(pane.state, .working)
        XCTAssertTrue(pane.snapshot.remoteControl)

        // O controle remoto acabou de ser lido; o turno acaba 0,6 s depois, com um comando rodando.
        session(of: pane, status: "shell", bridge: "session_01AbC")
        fixture.now += 0.6
        controller.tick()
        XCTAssertEqual(pane.state, .shell)
        XCTAssertTrue(pane.snapshot.remoteControl)
    }

    /// Morto à força, o processo deixa o arquivo para trás com o controle remoto ainda anotado.
    func testAgentInGameOverIsNotRemoteAnymore() {
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"))
        let pane = controller.panes[0]
        session(of: pane, status: "idle", bridge: "session_01AbC")
        fixture.now += 5
        controller.tick()
        XCTAssertTrue(pane.header.snapshot.remoteControl)

        kill(pane.terminal.process.shellPid, SIGKILL)
        XCTAssertTrue(waitUntil { pane.state == .exited })
        XCTAssertFalse(pane.header.snapshot.remoteControl)
        XCTAssertFalse(controller.sidebar.cards[0].snapshot.remoteControl)
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertFalse(pane.header.snapshot.remoteControl, "em GAME OVER o arquivo que sobrou não é lido")
    }

    func testSessionFileComesFromTheConfigFolderOfTheAgent() {
        var environment = fixture.environment
        environment["CLAUDE_CONFIG_DIR"] = fixture.home + "/outra-conta"
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude("read x"), environment: environment)
        let pane = controller.panes[0]
        session(of: pane, status: "shell")
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        session(of: pane, status: "shell", configDir: "outra-conta")
        fixture.now += AgentPaneView.activityInterval
        controller.tick()
        XCTAssertEqual(pane.state, .shell)
    }

    func testClickingTheNotificationSelectsTheAgent() {
        let controller = fixture.started(agents: 3)
        fixture.notifier.onOpen?(controller.panes[0].sessionID)
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        fixture.notifier.onOpen?("sessao-que-nao-existe")
        XCTAssertTrue(controller.mainPane === controller.panes[0])
    }

    func testGameOverAndEnterReopensTheSameConversation() {
        let script = """
        if [ -f "$HOME/viva" ]; then printf 'de volta\\n'; read x; fi
        exit 0
        """
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(script))
        let pane = controller.panes[0]
        let sessionID = pane.sessionID
        XCTAssertTrue(waitUntil { pane.state == .exited })
        XCTAssertTrue(lines(pane).contains { $0.contains("GAME OVER") })
        XCTAssertEqual(controller.liveAgentCount, 0)
        controller.tick()
        XCTAssertEqual(controller.topBar.stats.exited, 1)
        XCTAssertTrue(RenderedImage(pane, width: 660, height: 450).isColor(Theme.dark.red, atX: 0, y: 0))
        XCTAssertEqual(savedConfig().agents.count, 1, "agente em GAME OVER continua salvo")

        fixture.temp.write("viva", "")
        let old = pane.terminal
        controller.window?.makeFirstResponder(old)
        old.send(txt: "x")
        XCTAssertTrue(pane.terminal === old, "só o Enter reabre")
        old.send(txt: "\r")
        XCTAssertFalse(pane.terminal === old, "terminal novo, sem o lixo do anterior")
        XCTAssertNil(old.superview)
        XCTAssertEqual(pane.state, .boot)
        XCTAssertEqual(pane.sessionID, sessionID)
        XCTAssertTrue(controller.window?.firstResponder === pane.terminal)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("de volta") })
        XCTAssertEqual(controller.liveAgentCount, 1)
    }

    func testClaudeThatCannotRunEndsInGameOver() {
        let controller = fixture.started(agents: 1, claude: fixture.home + "/bin/nao-existe")
        XCTAssertTrue(waitUntil { controller.panes[0].state == .exited })
    }

    func testPaneBorderFollowsFocusAndState() {
        let controller = fixture.started(agents: 2)
        controller.toggleLayout(nil)
        let (first, second) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(RenderedImage(second, width: 660, height: 450).isColor(Theme.dark.accent, atX: 1, y: 1))
        XCTAssertTrue(RenderedImage(first, width: 660, height: 450).isColor(Theme.dark.bg3, atX: 1, y: 1))
        controller.isAppActive = { false }
        first.terminal.onBell?()
        XCTAssertTrue(RenderedImage(first, width: 660, height: 450).isColor(Theme.dark.yellow, atX: 1, y: 1))
    }

    // MARK: projetos

    /// Um menu de projetos como texto: `>` marca um submenu, e os itens de dentro vêm recuados.
    private func outline(_ menu: NSMenu, indent: String = "") -> [String] {
        menu.items.flatMap { item -> [String] in
            if item.isSeparatorItem { return [indent + "-"] }
            guard let submenu = item.submenu else { return [indent + item.title] }
            return [indent + item.title + " >"] + outline(submenu, indent: indent + "  ")
        }
    }

    /// Item achado pelos títulos, um por nível do menu. Antes do último título só vale linha com submenu:
    /// o nome da empresa sobre os mais usados não é a linha da empresa.
    private func item(_ menu: NSMenu, _ titles: String...) -> NSMenuItem? {
        var current: NSMenu? = menu
        var found: NSMenuItem?
        for (index, title) in titles.enumerated() {
            let last = index == titles.count - 1
            found = current?.items.first { $0.title == title && (last || $0.hasSubmenu) }
            current = found?.submenu
        }
        return found
    }

    private func choose(_ item: NSMenuItem?, file: StaticString = #filePath, line: UInt = #line) {
        guard let item, let action = item.action else {
            return XCTFail("item fora do menu ou sem ação", file: file, line: line)
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), "ninguém atendeu", file: file, line: line)
    }

    /// Pasta com repositório git: é o que o menu trata como projeto.
    @discardableResult
    private func repository(_ relative: String) -> String {
        fixture.temp.makeDirectory(relative + "/.git")
        return fixture.home + "/" + relative
    }

    func testProjectMenuListsCompaniesAndTheirProjects() {
        repository("Projetos/acme/api")
        fixture.temp.write("Projetos/acme/portal_web/CLAUDE.md", "contexto\n")
        repository("Projetos/acme/clientes/loja")
        fixture.temp.makeDirectory("Projetos/acme/rascunhos")
        fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Empresas",
            "ACME >",
            "  Api", "  Portal Web",
            "  Clientes >", "    Loja",
            "  -",
            "  Outras pastas >", "    Clientes", "    Rascunhos",
            "  Pasta da empresa",
            "BETA",
        ], "o projeto fundo fica no grupo da pasta em que está; empresa sem nada dentro abre direto")
        XCTAssertTrue(menu.items[0].isSectionHeader, "o título do bloco não é uma escolha")
        XCTAssertEqual(item(menu, "ACME", "Api")?.toolTip, "~/Projetos/acme/api")
        XCTAssertEqual(item(menu, "ACME", "Clientes")?.toolTip, "~/Projetos/acme/clientes")
        XCTAssertEqual(item(menu, "ACME", "Clientes", "Loja")?.toolTip, "~/Projetos/acme/clientes/loja")
        XCTAssertEqual(item(menu, "ACME", "Pasta da empresa")?.toolTip, "~/Projetos/acme")
    }

    func testProjectMenuWithoutCompaniesIsEmpty() {
        let controller = fixture.started()
        XCTAssertEqual(outline(controller.projectMenu()), [])
    }

    func testClickingACompanyOpensAnAgentInItsFolder() throws {
        repository("Projetos/acme/api")
        let controller = fixture.started()
        let acme = item(controller.projectMenu(), "ACME")
        XCTAssertEqual(outline(try XCTUnwrap(acme?.submenu)), ["Api", "-", "Pasta da empresa"],
                       "o cursor continua abrindo os projetos dela")
        XCTAssertEqual(acme?.toolTip, "~/Projetos/acme")
        choose(acme)
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home + "/Projetos/acme"])
        XCTAssertEqual(controller.panes.map(\.company.name), ["acme"])
    }

    func testProjectMenuShowsEachFolderOfADeclaredCompany() throws {
        repository("Projetos/acme/api")
        repository("trabalho/legado/antigo")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "ACME", "paths": ["~/Projetos/acme", "~/trabalho/legado"]}]}
        """)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Empresas",
            "ACME >", "  Antigo", "  Api", "  -", "  ~/Projetos/acme", "  ~/trabalho/legado",
        ])
        XCTAssertFalse(PixelMenu.hasOwnAction(try XCTUnwrap(item(menu, "ACME"))),
                       "com duas pastas, o clique na empresa só abre os projetos")
    }

    func testChoosingAProjectOpensAnAgentThere() {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started(agents: 1)
        choose(item(controller.projectMenu(), "ACME", "Api"))
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, api])
        XCTAssertEqual(controller.panes.map(\.project), ["GLOBAL", "Api"])
        XCTAssertEqual(controller.panes[1].company.name, "acme")
        XCTAssertTrue(controller.mainPane === controller.panes[1], "o agente do projeto vira o principal")

        choose(item(controller.agentMenu(), "GLOBAL"))
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, api, fixture.home],
                       "o GLOBAL do + AGENT abre na home, não na pasta do último agente")
    }

    func testCompanyFolderOtherFoldersAndDeepProjectsCanBeChosen() {
        let loja = repository("Projetos/acme/clientes/loja")
        let controller = fixture.started()
        let menu = controller.projectMenu()
        choose(item(menu, "ACME", "Pasta da empresa"))
        choose(item(menu, "ACME", "Outras pastas", "Clientes"))
        choose(item(menu, "ACME", "Clientes", "Loja"))
        XCTAssertEqual(controller.panes.map(\.directory),
                       [fixture.home + "/Projetos/acme", fixture.home + "/Projetos/acme/clientes", loja])
        XCTAssertEqual(Set(controller.panes.map(\.company.name)), ["acme"])
        XCTAssertEqual(controller.panes.map(\.project), ["Acme", "Clientes", "Loja"])
    }

    func testProjectMenuKeepsWorktreesApartAndOpensAGroupFolderFromItsGroup() {
        let api = repository("Projetos/acme/api")
        let chamado = fixture.home + "/Projetos/acme/api-431"
        fixture.temp.write("Projetos/acme/api-431/.git", "gitdir: \(api)/.git/worktrees/api-431\n")
        let suite = fixture.home + "/Projetos/acme/suite"
        fixture.temp.write("Projetos/acme/suite/CLAUDE.md", "contexto\n")
        let nucleo = repository("Projetos/acme/suite/nucleo")
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Empresas",
            "ACME >",
            "  Api",
            "  Suite >", "    Suite", "    -", "    Nucleo",
            "  -",
            "  Worktrees >", "    Api 431",
            "  Pasta da empresa",
        ], "a worktree não se passa por projeto, e o projeto que guarda projetos é um grupo só")

        choose(item(menu, "ACME", "Suite", "Suite"))
        choose(item(menu, "ACME", "Suite", "Nucleo"))
        choose(item(menu, "ACME", "Worktrees", "Api 431"))
        XCTAssertEqual(controller.panes.map(\.directory), [suite, nucleo, chamado])
        XCTAssertEqual(controller.panes.map(\.project), ["Suite", "Nucleo", "Api 431"])
        XCTAssertEqual(Set(controller.panes.map(\.company.name)), ["acme"])
    }

    func testGlobalOpensAnAgentAtHomeOutsideAnyCompany() {
        repository("Projetos/acme/api")
        let controller = fixture.started()
        choose(item(controller.projectMenu(), "ACME", "Api"))
        choose(item(controller.agentMenu(), "GLOBAL"))
        let pane = controller.panes[1]
        XCTAssertEqual(pane.directory, fixture.home)
        XCTAssertEqual(pane.company.name, CompanyResolver.fallbackName)
        XCTAssertTrue(pane.isGlobal)
        XCTAssertEqual(pane.snapshot.project, "GLOBAL")
        XCTAssertEqual(pane.snapshot.company, "", "o GLOBAL não é de empresa nenhuma")
        XCTAssertEqual(controller.panes[0].snapshot.company, "acme")
    }

    func testProjectMenuFollowsTheDisk() {
        repository("Projetos/acme/api")
        let controller = fixture.started()
        XCTAssertNil(item(controller.projectMenu(), "ACME", "Novo"))
        repository("Projetos/acme/novo")
        XCTAssertNotNil(item(controller.projectMenu(), "ACME", "Novo"), "a lista é lida a cada abertura do menu")
    }

    func testProjectThatVanishedBeforeTheClickWarnsAndOpensNothing() throws {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        let entry = item(controller.projectMenu(), "ACME", "Api")
        try FileManager.default.removeItem(atPath: api)
        choose(entry)
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertEqual(controller.warnings.messages.last, "pasta nao encontrada: nada foi aberto")
    }

    func testOpeningAProjectBeforeTheStartDoesNothing() {
        let api = repository("Projetos/acme/api")
        let controller = fixture.controller()
        XCTAssertEqual(outline(controller.projectMenu()), [],
                       "sem o ambiente do shell ainda não há empresas para listar")
        controller.openAgent(in: api)
        controller.addAgents(1)
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertEqual(controller.warnings.messages, [])
    }

    func testProjectChosenAtTheAgentLimitWarnsAndOpensNothing() {
        repository("Projetos/acme/api")
        let controller = fixture.started(agents: ClarkConfig.maxAgents)
        choose(item(controller.projectMenu(), "ACME", "Api"))
        XCTAssertEqual(controller.panes.count, ClarkConfig.maxAgents)
        XCTAssertEqual(controller.warnings.messages.last, "limite de 16 agentes: feche um para abrir outro")

        controller.close(controller.panes[0])
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.last?.directory, fixture.home, "o projeto recusado não fica na fila")
    }

    func testCompanyRowsAreUppercaseWithASwatchInTheCompanyColor() {
        repository("Projetos/acme/api")
        fixture.temp.makeDirectory("Projetos/beta")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "Acme Labs", "paths": ["~/Projetos/acme"], "color": "#ff00ff"}]}
        """)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Empresas",
            "ACME LABS >", "  Api", "  -", "  Pasta da empresa",
            "BETA",
        ])
        XCTAssertNil(item(controller.agentMenu(), "GLOBAL")?.image)
        XCTAssertNil(item(menu, "ACME LABS", "Api")?.image)
        XCTAssertNotNil(item(menu, "BETA")?.image, "a empresa que abre direto também tem a cor dela")

        // Só a linha da empresa declarada, desenhada: o quadradinho sai na cor do `companies.json`.
        let view = PixelMenuView(items: [item(menu, "ACME LABS")].compactMap { $0 })
        let image = RenderedImage(view, width: view.fittingWidth, height: view.fittingHeight)
        XCTAssertEqual(image.count(RGB(r: 1, g: 0, b: 1)), PixelMenuView.swatchSide * PixelMenuView.swatchSide)
    }

    func testProjectShortcutOpensTheAgentMenuAlreadyInsideTheProjects() {
        repository("Projetos/acme/api")
        let controller = fixture.started(agents: 1)
        var shown: [NSPanel] = []
        controller.pixelMenu.present = { panel, _ in shown.append(panel) }
        controller.pixelMenu.bounds = { _ in NSRect(x: -50_000, y: -50_000, width: 100_000, height: 100_000) }
        controller.chooseProject(nil)

        XCTAssertTrue(controller.pixelMenu.isOpen)
        XCTAssertEqual(controller.pixelMenu.levels.map { $0.view.items.map(\.title) }, [
            ["GLOBAL", "Projeto", "Digitar pasta…", "Outra pasta…"], ["Empresas", "ACME"],
        ])
        XCTAssertEqual(controller.pixelMenu.levels.map(\.view.highlighted), [1, 1], "o ⌘D já entra no Projeto")
        let button = controller.topBar.addButton
        let anchor = try? XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
        XCTAssertEqual(shown[0].frame.minX, anchor?.minX, "o menu é o do + AGENT, sob ele")

        controller.pixelMenu.keyDown(.right)
        controller.pixelMenu.keyDown(.enter)
        XCTAssertFalse(controller.pixelMenu.isOpen)
        XCTAssertEqual(controller.panes.map(\.project), ["GLOBAL", "Api"], "só com o teclado até o projeto")
    }

    func testShutdownClosesTheOpenProjectMenu() {
        let controller = fixture.started(agents: 1)
        controller.pixelMenu.present = { _, _ in }
        controller.chooseProject(nil)
        XCTAssertTrue(controller.pixelMenu.isOpen)
        controller.shutdown()
        XCTAssertFalse(controller.pixelMenu.isOpen)
    }

    // MARK: + AGENT

    func testAgentMenuOffersGlobalTheProjectsAndATypedFolder() {
        repository("Projetos/acme/api")
        let controller = fixture.started()
        XCTAssertEqual(outline(controller.agentMenu()), [
            "GLOBAL",
            "Projeto >", "  Empresas", "  ACME >", "    Api", "    -", "    Pasta da empresa",
            "Digitar pasta…",
            "Outra pasta…",
        ], "o Projeto traz os mais usados e as empresas; a Outra pasta escolhe qualquer pasta no Finder")
        XCTAssertEqual(item(controller.agentMenu(), "GLOBAL")?.toolTip, "~")
        XCTAssertEqual(item(controller.agentMenu(), "Outra pasta…")?.action,
                       #selector(MainWindowController.chooseFolder(_:)))
    }

    func testAgentMenuWithoutProjectsHasNoProjectRow() {
        let controller = fixture.started()
        XCTAssertEqual(outline(controller.agentMenu()), ["GLOBAL", "Digitar pasta…", "Outra pasta…"])
    }

    func testAgentMenuProjectRowStartsWithTheMostUsed() {
        let site = repository("Projetos/beta/site")
        used(2, in: site)
        let controller = fixture.started()
        XCTAssertEqual(Array(outline(controller.agentMenu()).prefix(5)),
                       ["GLOBAL", "Projeto >", "  Mais usados", "  BETA", "  Site"])
    }

    func testGlobalInTheAgentMenuOpensAtHome() {
        repository("Projetos/acme/api")
        let controller = fixture.started()
        choose(item(controller.agentMenu(), "GLOBAL"))
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home])
    }

    func testProjectInTheAgentMenuOpensAnAgentThere() {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        choose(item(controller.agentMenu(), "Projeto", "ACME", "Api"))
        XCTAssertEqual(controller.panes.map(\.directory), [api])
        XCTAssertEqual(controller.panes.map(\.project), ["Api"])
    }

    func testAddButtonOpensTheAgentMenuUnderIt() {
        repository("Projetos/acme/api")
        let controller = fixture.started(agents: 1)
        var shown: [NSPanel] = []
        controller.pixelMenu.present = { panel, _ in shown.append(panel) }
        controller.pixelMenu.bounds = { _ in NSRect(x: -50_000, y: -50_000, width: 100_000, height: 100_000) }
        let button = controller.topBar.addButton
        button.onClick?()

        XCTAssertTrue(controller.pixelMenu.isOpen)
        XCTAssertEqual(controller.panes.count, 1, "o + AGENT pergunta antes de abrir")
        XCTAssertEqual(controller.pixelMenu.levels[0].view.items.map(\.title),
                       ["GLOBAL", "Projeto", "Digitar pasta…", "Outra pasta…"])
        let anchor = try? XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
        XCTAssertEqual(shown[0].frame.minX, anchor?.minX)
        XCTAssertEqual(shown[0].frame.maxY, (anchor?.minY ?? 0) - PixelMenu.gap, "logo abaixo do botão")

        controller.pixelMenu.hover(1, level: 0)
        controller.pixelMenu.hover(1, level: 1)
        controller.pixelMenu.choose(0, level: 2)
        XCTAssertFalse(controller.pixelMenu.isOpen)
        XCTAssertEqual(controller.panes.map(\.project), ["GLOBAL", "Api"])
    }

    func testNewAgentShortcutOpensTheSameMenu() {
        let controller = fixture.started(agents: 1)
        controller.pixelMenu.present = { _, _ in }
        controller.newAgent(nil)
        XCTAssertTrue(controller.pixelMenu.isOpen)
        XCTAssertEqual(controller.panes.count, 1, "o ⌘N pergunta como o + AGENT")
        XCTAssertEqual(controller.pixelMenu.levels[0].view.items.map(\.title),
                       ["GLOBAL", "Digitar pasta…", "Outra pasta…"])
    }

    func testTypedFolderOpensAnAgentThere() {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        controller.openTypedFolder("~/Projetos/acme/api/")
        XCTAssertEqual(controller.panes.map(\.directory), [api])
    }

    func testTypedRelativeFolderStartsAtTheAgentInFocus() {
        let acme = fixture.temp.makeDirectory("Projetos/acme")
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        controller.openAgent(in: acme)
        controller.openTypedFolder("  api ")
        XCTAssertEqual(controller.panes.map(\.directory), [acme, api])
    }

    func testTypedFolderThatDoesNotExistWarnsAndOpensNothing() {
        let controller = fixture.started()
        let before = controller.warnings.messages
        controller.openTypedFolder("~/nao/existe")
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertEqual(controller.warnings.messages, before + ["pasta nao encontrada: nada foi aberto"])
    }

    func testEmptyTypedFolderDoesNothing() {
        let controller = fixture.started()
        let before = controller.warnings.messages
        controller.openTypedFolder("   ")
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertEqual(controller.warnings.messages, before, "campo vazio não é pasta que sumiu")
    }

    func testTypeFolderShowsAFieldWhoseEnterOpensTheAgent() throws {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        choose(item(controller.agentMenu(), "Digitar pasta…"))
        let field = try XCTUnwrap(controller.folderField, "o Digitar pasta… mostra o campo")
        field.stringValue = "~/Projetos/acme/api"
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(field.action), to: field.target, from: field))
        XCTAssertEqual(controller.panes.map(\.directory), [api])
        XCTAssertNil(controller.folderField, "o Enter fecha o campo")
    }

    // MARK: mais usados

    /// Conversas do Claude Code na pasta, gravadas onde ele grava: `<config>/projects/<pasta>/<id>.jsonl`.
    /// - Parameter age: há quantos segundos as conversas foram mexidas.
    private func used(_ times: Int, in directory: String, age: TimeInterval = 60, configDir: String = ".claude") {
        let canonical = PathTools.canonical(directory, base: fixture.home, home: fixture.home)
        let folder = SessionDigestReader.projectFolder(canonicalDirectory: canonical, configDir: configDir)
        for _ in 0..<times {
            let path = fixture.temp.write(folder + "/\(UUID().uuidString.lowercased()).jsonl", "{}\n")
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)],
                                                   ofItemAtPath: path)
        }
    }

    func testProjectMenuOpensWithTheMostUsedProjectsOnTop() {
        let api = repository("Projetos/acme/api")
        repository("Projetos/acme/portal")
        let site = repository("Projetos/beta/site")
        used(2, in: api)
        used(5, in: site)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Mais usados", "BETA", "Site", "ACME", "Api", "-",
            "Empresas",
            "ACME >", "  Api", "  Portal", "  -", "  Pasta da empresa",
            "BETA >", "  Site", "  -", "  Pasta da empresa",
        ], "o mais usado vem primeiro; o que nunca foi usado só aparece na empresa")
        XCTAssertTrue(menu.items[0].isSectionHeader, "o título do bloco não é uma escolha")
        XCTAssertEqual(item(menu, "Site")?.toolTip, "~/Projetos/beta/site")
    }

    func testSuggestionsAreGroupedUnderTheirCompany() {
        let api = repository("Projetos/acme/api")
        let portal = repository("Projetos/acme/portal")
        let site = repository("Projetos/beta/site")
        used(5, in: api)
        used(4, in: site)
        used(3, in: portal)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(Array(outline(menu).prefix(7)), ["Mais usados", "ACME", "Api", "Portal", "BETA", "Site", "-"],
                       "a empresa do mais usado vem primeiro, com os projetos dela na ordem de uso")
        let label = menu.items[1]
        XCTAssertFalse(label.isEnabled, "o nome da empresa não é uma escolha")
        XCTAssertNil(label.action)
        XCTAssertNotNil(label.image, "o nome vem com o quadradinho da cor da empresa")
        XCTAssertEqual(menu.items[2...3].map(\.indentationLevel), [1, 1], "os projetos ficam recuados sob ela")
        XCTAssertEqual(menu.items[2].toolTip, "~/Projetos/acme/api")
    }

    func testChoosingASuggestionOpensAnAgentThere() {
        let api = repository("Projetos/acme/api")
        used(1, in: api)
        let controller = fixture.started()
        choose(item(controller.projectMenu(), "Api"))
        XCTAssertEqual(controller.panes.map(\.directory), [api])
        XCTAssertEqual(controller.panes.map(\.project), ["Api"])
        XCTAssertEqual(controller.panes.map(\.company.name), ["acme"])
    }

    func testChosenProjectMovesUpBeforeItsFirstConversation() {
        let api = repository("Projetos/acme/api")
        let site = repository("Projetos/beta/site")
        used(1, in: api, age: 3600)
        let controller = fixture.started()
        XCTAssertEqual(Array(outline(controller.projectMenu()).prefix(4)), ["Mais usados", "ACME", "Api", "-"])
        controller.openAgent(in: site)
        XCTAssertEqual(Array(outline(controller.projectMenu()).prefix(6)),
                       ["Mais usados", "BETA", "Site", "ACME", "Api", "-"],
                       "o projeto escolhido entra já na próxima abertura, sem esperar a conversa no disco")
    }

    func testUsedWorktreeIsSuggestedToo() {
        let api = repository("Projetos/acme/api")
        let chamado = fixture.home + "/Projetos/acme/api-431"
        fixture.temp.write("Projetos/acme/api-431/.git", "gitdir: \(api)/.git/worktrees/api-431\n")
        used(2, in: chamado)
        used(1, in: api)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(Array(outline(menu).prefix(5)), ["Mais usados", "ACME", "Api 431", "Api", "-"])
        choose(item(menu, "Api 431"))
        XCTAssertEqual(controller.panes.map(\.directory), [chamado])
    }

    func testProjectNeverUsedIsNotSuggested() {
        repository("Projetos/acme/api")
        used(9, in: fixture.home)
        let controller = fixture.started()
        XCTAssertEqual(outline(controller.projectMenu()), [
            "Empresas", "ACME >", "  Api", "  -", "  Pasta da empresa",
        ], "a home é o GLOBAL, uma linha acima no + AGENT: não entra na conta")
    }

    func testConversationsOlderThanTheWindowSuggestNothing() {
        let api = repository("Projetos/acme/api")
        used(3, in: api, age: ProjectUsage.window + 3600)
        let controller = fixture.started()
        XCTAssertNil(item(controller.projectMenu(), MainWindowController.mostUsedTitle))
        used(1, in: api, age: 3600)
        XCTAssertNotNil(item(controller.projectMenu(), "Api"), "a conta é refeita a cada abertura do menu")
    }

    func testSuggestionsCoverEverythingTheMenuOffers() {
        let api = repository("Projetos/acme/api")
        let loja = repository("Projetos/acme/clientes/loja")
        let drafts = fixture.temp.makeDirectory("Projetos/acme/rascunhos")
        let notes = fixture.temp.makeDirectory("notas")
        var config = ClarkConfig()
        config.projectNames = [api: "Portal de Compras", notes: "Diário"]
        used(5, in: api)
        used(4, in: loja)
        used(3, in: fixture.home + "/Projetos/acme")
        used(2, in: drafts)
        used(1, in: notes)
        let controller = fixture.started(config: config)
        let menu = controller.projectMenu()
        XCTAssertEqual(Array(outline(menu).prefix(8)), [
            "Mais usados", "ACME", "Portal de Compras", "Loja", "Pasta da empresa", "Rascunhos", "Diário", "-",
        ], "o apelido, o projeto fundo, a pasta da empresa, a pasta que não é projeto e a apelidada sem empresa")
        XCTAssertEqual(item(menu, "Pasta da empresa")?.toolTip, "~/Projetos/acme")
        XCTAssertEqual(item(menu, "Diário")?.indentationLevel, 0, "fora de toda empresa: sem nome em cima e sem recuo")
        choose(item(menu, "Loja"))
        XCTAssertEqual(controller.panes.map(\.directory), [loja])
    }

    func testSuggestionsNameTheFolderOfACompanyThatHasMoreThanOne() {
        repository("Projetos/acme/api")
        fixture.temp.makeDirectory("trabalho/legado")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "ACME", "paths": ["~/Projetos/acme", "~/trabalho/legado"]}]}
        """)
        used(1, in: fixture.home + "/trabalho/legado")
        let controller = fixture.started()
        XCTAssertEqual(Array(outline(controller.projectMenu()).prefix(4)),
                       ["Mais usados", "ACME", "~/trabalho/legado", "-"])
    }

    func testProjectReachedThroughALinkIsCountedWhereItReallyIs() {
        let real = repository("Projetos/acme/arquivo/2025/real")
        try? FileManager.default.createSymbolicLink(atPath: fixture.home + "/Projetos/acme/atalho",
                                                    withDestinationPath: real)
        // O Claude Code grava a conversa pela pasta de verdade, não pelo link por onde se entrou.
        used(2, in: real)
        let controller = fixture.started()
        let menu = controller.projectMenu()
        XCTAssertEqual(Array(outline(menu).prefix(4)), ["Mais usados", "ACME", "Atalho", "-"])
        XCTAssertEqual(item(menu, "Atalho")?.representedObject as? String, fixture.home + "/Projetos/acme/atalho",
                       "abre pelo mesmo caminho da linha da empresa")
    }

    func testSuggestionsStopAtFive() {
        for (index, name) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            used(index + 1, in: repository("Projetos/acme/" + name))
        }
        let controller = fixture.started()
        XCTAssertEqual(ProjectUsage.maxSuggestions, 5)
        XCTAssertEqual(Array(outline(controller.projectMenu()).prefix(8)), [
            "Mais usados", "ACME", "F", "E", "D", "C", "B", "-",
        ])
    }

    func testSuggestionsComeFromTheConfigFolderOfTheAccount() {
        let api = repository("Projetos/acme/api")
        let site = repository("Projetos/beta/site")
        used(3, in: api)
        used(1, in: site, configDir: "outra-conta")
        var environment = fixture.environment
        environment["CLAUDE_CONFIG_DIR"] = fixture.home + "/outra-conta"
        let controller = fixture.started(environment: environment)
        XCTAssertEqual(Array(outline(controller.projectMenu()).prefix(4)), ["Mais usados", "BETA", "Site", "-"])
    }

    // MARK: apelidos

    func testNicknameRenamesTheProjectOfEveryAgentInTheRepository() {
        let api = repository("Projetos/acme/api")
        let source = fixture.temp.makeDirectory("Projetos/acme/api/src")
        let controller = fixture.started()
        controller.addAgents(1, in: api)
        controller.addAgents(1, in: source)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.project), ["Api", "Api", "GLOBAL"],
                       "a subpasta leva o nome do repositório em que está")

        controller.applyNickname(controller.panes[1], text: "  Portal   de\tCompras ")
        XCTAssertEqual(controller.panes.map(\.project), ["Portal de Compras", "Portal de Compras", "GLOBAL"])
        XCTAssertEqual(controller.panes[1].header.snapshot.project, "Portal de Compras")
        XCTAssertEqual(controller.sidebar.cards.map(\.snapshot.project),
                       ["Portal de Compras", "Portal de Compras", "GLOBAL"], "os cards acompanham")
        XCTAssertEqual(savedConfig().projectNames, [api: "Portal de Compras"], "o apelido é do repositório")
        XCTAssertEqual(outline(controller.projectMenu()), [
            "Empresas",
            "ACME >", "  Portal de Compras", "  -", "  Pasta da empresa",
        ], "o apelidado sobe para o topo da empresa e sai da lista comum")
        XCTAssertEqual(item(controller.projectMenu(), "ACME", "Portal de Compras")?.toolTip, "~/Projetos/acme/api")
    }

    func testNicknameSurvivesReopening() {
        let api = repository("Projetos/acme/api")
        let first = fixture.started()
        first.addAgents(1, in: api)
        first.applyNickname(first.panes[0], text: "Portal")
        first.shutdown()

        let second = fixture.started()
        XCTAssertEqual(second.panes.map(\.project), ["Portal"])
        choose(item(second.projectMenu(), "ACME", "Portal"))
        XCTAssertEqual(second.panes.map(\.directory), [api, api])
        XCTAssertEqual(second.panes.map(\.project), ["Portal", "Portal"])
    }

    func testEmptyOrDefaultNicknameGoesBackToTheFolderName() {
        let api = repository("Projetos/acme/api")
        let controller = fixture.started()
        controller.addAgents(1, in: api)
        let pane = controller.panes[0]

        controller.applyNickname(pane, text: "Portal")
        controller.applyNickname(pane, text: "   ")
        XCTAssertEqual(pane.project, "Api")
        XCTAssertEqual(savedConfig().projectNames, [:])

        controller.applyNickname(pane, text: "Portal")
        controller.applyNickname(pane, text: "Api")
        XCTAssertEqual(pane.project, "Api")
        XCTAssertEqual(savedConfig().projectNames, [:], "igual ao nome da pasta não é apelido")
        XCTAssertNotNil(item(controller.projectMenu(), "ACME", "Api"))
    }

    func testNicknameReplacesTheSameFolderWrittenAnotherWay() {
        let api = repository("Projetos/acme/api")
        var config = ClarkConfig()
        config.projectNames = ["~/Projetos/acme/api": "Antigo"]
        let controller = fixture.started(config: config)
        controller.addAgents(1, in: api)
        XCTAssertEqual(controller.panes[0].project, "Antigo", "o `~` do arquivo vale")

        controller.applyNickname(controller.panes[0], text: "Novo")
        XCTAssertEqual(savedConfig().projectNames, [api: "Novo"], "uma chave por pasta")
    }

    func testGlobalHasNoNickname() {
        let controller = fixture.started(agents: 1)
        controller.applyNickname(controller.panes[0], text: "Casa")
        XCTAssertEqual(controller.panes[0].project, "GLOBAL")
        XCTAssertEqual(savedConfig().projectNames, [:])
        let item = NSMenuItem(title: "", action: #selector(MainWindowController.nicknameProject(_:)),
                              keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(controller.panes[0].contextMenu().items.first { $0.title == "Apelidar projeto…" }?.isEnabled,
                       false)
    }

    func testNicknamedFolderOutsideEveryCompanySitsInTheMainMenu() {
        let notes = fixture.temp.makeDirectory("notas")
        repository("Projetos/acme/api")
        let controller = fixture.started()
        controller.addAgents(1, in: notes)
        XCTAssertEqual(controller.panes[0].project, "Notas")
        XCTAssertEqual(controller.panes[0].snapshot.company, CompanyResolver.fallbackName)

        controller.applyNickname(controller.panes[0], text: "Diário")
        let menu = controller.projectMenu()
        XCTAssertEqual(outline(menu), [
            "Empresas",
            "ACME >", "  Api", "  -", "  Pasta da empresa",
            "-", "Diário",
        ])
        XCTAssertEqual(item(menu, "Diário")?.toolTip, "~/notas")
        let nickname = NSMenuItem(title: "", action: #selector(MainWindowController.nicknameProject(_:)),
                                  keyEquivalent: "")
        XCTAssertTrue(controller.validateMenuItem(nickname))
    }

    // MARK: consumo do plano

    /// O arquivo que o AiUsageBar deixa no cache dele, na home de teste.
    private func writeUsage(percent: Int, fetched: Double) {
        fixture.temp.write("Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json", """
        {"Claude Code-credentials": {"fetchedAt": \(fetched), "fiveHour": {"percent": \(percent), "resetsAt": 9000}}}
        """)
    }

    func testTopBarShowsTheUsageFromTheUsageBarCacheAndRereadsItOnceAMinute() {
        let controller = fixture.started()
        controller.wallClock = { 5000 }
        controller.tick()
        XCTAssertNil(controller.topBar.usage, "sem o arquivo do AiUsageBar não há medidor")

        writeUsage(percent: 7, fetched: 4900)
        fixture.now += MainWindowController.usageInterval - 1
        controller.tick()
        XCTAssertNil(controller.topBar.usage, "ainda não é hora de reler")
        fixture.now += 1
        controller.tick()
        XCTAssertEqual(controller.topBar.usage,
                       UsageMeter(gauges: [UsageMeter.Gauge(label: "5H", percent: 7, resetsIn: 4000)], age: 100))

        writeUsage(percent: 9, fetched: 4950)
        controller.tick()
        XCTAssertEqual(controller.topBar.usage?.gauges.map(\.percent), [7])
        fixture.now += MainWindowController.usageInterval
        controller.tick()
        XCTAssertEqual(controller.topBar.usage?.gauges.map(\.percent), [9])
    }

    func testComingBackToTheAppRereadsTheUsage() {
        let controller = fixture.started()
        controller.wallClock = { 5000 }
        controller.tick()
        writeUsage(percent: 7, fetched: 4900)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        XCTAssertEqual(controller.topBar.usage?.gauges.map(\.percent), [7])
        // A volta ao app conta como leitura: a próxima é um minuto depois dela.
        writeUsage(percent: 9, fetched: 4950)
        fixture.now += MainWindowController.usageInterval - 1
        controller.tick()
        XCTAssertEqual(controller.topBar.usage?.gauges.map(\.percent), [7])
    }

    func testUsageFileThatGoesAwayTakesTheMeterAway() {
        let controller = fixture.started()
        controller.wallClock = { 5000 }
        writeUsage(percent: 7, fetched: 4900)
        controller.tick()
        XCTAssertNotNil(controller.topBar.usage)
        try? FileManager.default.removeItem(atPath: UsageMeter.path(home: fixture.home))
        fixture.now += MainWindowController.usageInterval
        controller.tick()
        XCTAssertNil(controller.topBar.usage)
    }

    // MARK: menu

    func testMenuItemsFollowTheAgents() {
        let controller = fixture.controller()
        func enabled(_ action: Selector) -> Bool {
            controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        XCTAssertFalse(enabled(#selector(MainWindowController.newAgent(_:))), "antes do ambiente do shell")
        let project = [#selector(MainWindowController.chooseProject(_:)),
                       #selector(MainWindowController.openProject(_:)),
                       #selector(MainWindowController.chooseFolder(_:))]
        for action in project { XCTAssertFalse(enabled(action), "\(action) antes do ambiente do shell") }

        var options = CLIOptions()
        controller.start(launch: fixture.launch(), options: options, openGlobalWhenEmpty: false)
        XCTAssertTrue(enabled(#selector(MainWindowController.newAgent(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.newSiblingAgent(_:))), "sem agente não há pasta")
        XCTAssertFalse(enabled(#selector(MainWindowController.nicknameProject(_:))))
        for action in project { XCTAssertTrue(enabled(action), "\(action)") }
        XCTAssertFalse(enabled(#selector(MainWindowController.closeAllAgents(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.toggleZoom(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.nextAgent(_:))))
        XCTAssertTrue(enabled(#selector(MainWindowController.toggleLayout(_:))))

        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.renameAgent(_:))))
        XCTAssertTrue(enabled(#selector(MainWindowController.newSiblingAgent(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.previousAgent(_:))))
        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.previousAgent(_:))))
        options.count = 0
    }

    func testMenuShortcutsAreUniqueAndReachTheController() {
        let controller = fixture.controller()
        var leaves: [NSMenuItem] = []
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { collect(submenu) } else if !item.isSeparatorItem { leaves.append(item) }
            }
        }
        collect(MainMenu.build())

        let shortcuts = leaves.filter { !$0.keyEquivalent.isEmpty }.map {
            "\($0.keyEquivalentModifierMask.contains(.option) ? "opt+" : "")\($0.keyEquivalent)"
        }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "atalho repetido: \(shortcuts)")
        // As maiúsculas levam o Shift: `D` é o ⌘⇧D do diff e `d` o ⌘D do projeto; `N` é o ⌘⇧N do agente na
        // mesma pasta e `n` o ⌘N, que pergunta onde o agente abre; `C` é o ⌘⇧C que copia uma linha pelo teclado.
        for key in ["n", "N", "w", "d", "D", "r", "l", "\r", "{", "}", "+", "=", "-", "0", "c", "C", "v", "q"]
            + (1...9).map(String.init) {
            XCTAssertTrue(shortcuts.contains(key), "falta ⌘\(key)")
        }
        XCTAssertFalse(shortcuts.contains("t"), "⌘T é da fila de tarefas, que chega no M2")

        // Toda ação do CLARK no menu precisa existir no controller: seletor errado vira item morto, sem erro.
        let expected = ["newAgent:", "newSiblingAgent:", "chooseProject:", "closeAgent:", "closeAllAgents:",
                        "toggleLayout:", "toggleZoom:", "increaseFont:", "decreaseFont:", "resetFont:",
                        "previousAgent:", "nextAgent:", "renameAgent:", "nicknameProject:", "showDiff:",
                        "refreshDiff:", "selectAgentByNumber:", "copyLines:"]
        let actions = Set(leaves.compactMap(\.action).map(NSStringFromSelector))
        for name in expected {
            XCTAssertTrue(actions.contains(name), "falta no menu: \(name)")
            XCTAssertTrue(controller.responds(to: NSSelectorFromString(name)), "controller sem \(name)")
        }
        let system = ["orderFrontStandardAboutPanel:", "hide:", "hideOtherApplications:", "terminate:", "copy:",
                      "paste:", "selectAll:", "performMiniaturize:", "performZoom:"]
        XCTAssertEqual(actions, Set(expected + system), "item novo no menu sem teste")
        XCTAssertEqual(leaves.filter { $0.action == #selector(MainWindowController.selectAgentByNumber(_:)) }
            .map(\.tag), Array(1...9))
    }
}
