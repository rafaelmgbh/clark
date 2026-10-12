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

    func testCountOptionOpensAgentsInTheDefaultDirectory() {
        let controller = fixture.started(agents: 3)
        XCTAssertEqual(controller.panes.count, 3)
        XCTAssertEqual(Set(controller.panes.map(\.directory)), [fixture.home])
        XCTAssertEqual(Set(controller.panes.map(\.sessionID)).count, 3)
        XCTAssertTrue(controller.panes.allSatisfy { SessionLocator.isValidUUID($0.sessionID) })
    }

    func testDirectoryOptionBecomesTheDefaultDirectory() {
        let project = fixture.temp.makeDirectory("Projetos/acme/app")
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = project
        options.count = 1
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(controller.defaultDirectory, project)
        XCTAssertEqual(controller.panes[0].directory, project)
        XCTAssertEqual(controller.topBar.folderButton.title, "DIR ~/Projetos/acme/app")
        XCTAssertEqual(savedConfig().cwd, project)
    }

    func testMissingDirectoryOptionWarnsAndKeepsThePreviousOne() {
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = fixture.home + "/nao-existe"
        controller.start(launch: fixture.launch(), options: options, startupWarnings: ["config.json invalido"])
        XCTAssertEqual(controller.defaultDirectory, fixture.home)
        XCTAssertEqual(controller.warnings.messages, [
            "config.json invalido",
            "claude nao encontrado: os agentes abrem o shell",
            "pasta nao encontrada: valendo a anterior",
        ])
    }

    func testSavedDirectoryThatVanishedFallsBackToHome() {
        var config = ClarkConfig()
        config.cwd = fixture.home + "/apagada"
        config.agents = [SavedAgent(name: "API", cwd: fixture.home + "/apagada", sessionID: nil, tone: nil)]
        let controller = fixture.started(config: config)
        XCTAssertEqual(controller.defaultDirectory, fixture.home)
        XCTAssertEqual(controller.panes[0].directory, fixture.home)
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
        let item = NSMenuItem(title: "", action: #selector(MainWindowController.newAgent(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
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

    func testChangingTheFolderAffectsOnlyNewAgents() {
        let project = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started(agents: 1)
        controller.setDefaultDirectory(fixture.home + "/nao-existe")
        XCTAssertEqual(controller.defaultDirectory, fixture.home)

        controller.setDefaultDirectory(project)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, project])
        XCTAssertEqual(controller.topBar.folderButton.title, "DIR ~/Projetos/beta")
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
        first.setDefaultDirectory(project)
        first.addAgents(1)
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
        XCTAssertEqual(second.defaultDirectory, project)
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
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertTrue(controller.panes.isEmpty)
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

        controller.setDefaultDirectory(acme)
        controller.addAgents(1)
        controller.setDefaultDirectory(beta)
        controller.addAgents(1)
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
        controller.setDefaultDirectory(acme + "/atalho")
        controller.addAgents(1)
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
        XCTAssertEqual(Array(lines(pane)[1...4]), ["EMPRESA=AVULSO", "A=vazio", "B=vazio", "GH=liberado-para-todos"])
        XCTAssertEqual(pane.removedVariables, ["ACME_API_KEY"])
    }

    func testAgentsOfTheSameCompanyGetDifferentTones() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let other = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started()
        controller.setDefaultDirectory(project)
        controller.addAgents(2)
        controller.setDefaultDirectory(other)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.company.name), ["acme", "acme", "beta"])
        XCTAssertEqual(controller.panes.map(\.tone), [0, 1, 0])
        XCTAssertNotEqual(controller.panes[0].color, controller.panes[1].color)
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

    // MARK: menu

    func testMenuItemsFollowTheAgents() {
        let controller = fixture.controller()
        func enabled(_ action: Selector) -> Bool {
            controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        XCTAssertFalse(enabled(#selector(MainWindowController.newAgent(_:))), "antes do ambiente do shell")
        XCTAssertFalse(enabled(#selector(MainWindowController.chooseFolder(_:))))

        var options = CLIOptions()
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertTrue(enabled(#selector(MainWindowController.newAgent(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.closeAllAgents(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.toggleZoom(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.nextAgent(_:))))
        XCTAssertTrue(enabled(#selector(MainWindowController.toggleLayout(_:))))

        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.renameAgent(_:))))
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
        for key in ["n", "w", "d", "l", "\r", "{", "}", "+", "=", "-", "0", "c", "v", "q"] + (1...9).map(String.init) {
            XCTAssertTrue(shortcuts.contains(key), "falta ⌘\(key)")
        }
        XCTAssertFalse(shortcuts.contains("t"), "⌘T é da fila de tarefas, que chega no M2")

        // Toda ação do CLARK no menu precisa existir no controller: seletor errado vira item morto, sem erro.
        let expected = ["newAgent:", "chooseFolder:", "closeAgent:", "closeAllAgents:", "toggleLayout:", "toggleZoom:",
                        "increaseFont:", "decreaseFont:", "resetFont:", "previousAgent:", "nextAgent:",
                        "renameAgent:", "selectAgentByNumber:"]
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
