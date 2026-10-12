import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A coluna dos arquivos alterados dentro do painel do agente: abre pelo selo do cabeçalho, divide o
/// espaço com o terminal e leva o arquivo clicado para a janela do diff.
final class AgentChangedFilesTests: XCTestCase {
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

    /// Repositório com `a.txt` modificado e `novo.txt` ainda não rastreado.
    private func repository() throws -> TestRepository {
        let repo = try TestRepository(at: fixture.home + "/Projetos/acme/api", home: fixture.home)
        fixture.gitPath = repo.git
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        repo.write("a.txt", "um\ndois\n")
        repo.write("novo.txt", "linha nova\n")
        return repo
    }

    /// Controller que não põe janela na tela: guarda o que seria mostrado.
    private func started() -> (controller: MainWindowController, shown: () -> [NSWindowController]) {
        let controller = fixture.started()
        var shown: [NSWindowController] = []
        controller.present = { shown.append($0) }
        return (controller, { shown })
    }

    /// Agente no repositório, já com a primeira leitura, num painel da largura pedida.
    private func agent(in repo: TestRepository, of controller: MainWindowController,
                       width: CGFloat = 900) -> AgentPaneView {
        controller.addAgents(1, in: repo.path)
        let pane = controller.panes[controller.panes.count - 1]
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        resize(pane, width: width)
        return pane
    }

    private func resize(_ pane: AgentPaneView, width: CGFloat) {
        pane.frame = NSRect(x: 0, y: 0, width: width, height: 500)
        pane.layoutSubtreeIfNeeded()
    }

    private func paths(_ pane: AgentPaneView) -> [String] {
        pane.changedFiles.list.rows.compactMap { row in
            if case .file(let file) = row { return file.path }
            return nil
        }
    }

    // MARK: abrir e fechar

    func testColumnStartsClosedAndTheTerminalHasThePaneForItself() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        XCTAssertFalse(pane.showsChangedFiles)
        XCTAssertTrue(pane.changedFiles.isHidden)
        XCTAssertTrue(pane.changedFiles.superview === pane)
        XCTAssertEqual(pane.terminal.frame.width, 900 - 2 * CGFloat(AgentPaneView.border) - 12)
    }

    func testClickOnTheSummaryOpensTheColumnBesideTheTerminal() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let pane = agent(in: repo, of: controller)
        let whole = pane.terminal.frame

        pane.header.onBadgeClick?()
        pane.layoutSubtreeIfNeeded()
        XCTAssertTrue(pane.showsChangedFiles)
        XCTAssertFalse(pane.changedFiles.isHidden)
        let border = CGFloat(AgentPaneView.border), column = CGFloat(ChangedFilesView.width)
        let top = pane.header.frame.maxY + 2
        XCTAssertEqual(pane.changedFiles.frame,
                       NSRect(x: 900 - border - column, y: top, width: column, height: 500 - border - top))
        XCTAssertEqual(pane.terminal.frame.width, whole.width - column, "o terminal cede a largura da coluna")
        XCTAssertEqual(pane.terminal.frame.minX, whole.minX)
        XCTAssertEqual(pane.terminal.frame.minY, whole.minY)
        XCTAssertEqual(pane.terminal.frame.height, whole.height)
        XCTAssertLessThanOrEqual(pane.terminal.frame.maxX, pane.changedFiles.frame.minX)
        XCTAssertEqual(pane.changedFiles.title, "ALTERADOS 2")
        XCTAssertEqual(paths(pane), ["a.txt", "novo.txt"])
        XCTAssertTrue(shown().isEmpty, "a coluna não abre a janela do diff")
    }

    func testClickingTheSummaryAgainClosesTheColumn() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        let whole = pane.terminal.frame
        pane.header.onBadgeClick?()
        pane.header.onBadgeClick?()
        pane.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.showsChangedFiles)
        XCTAssertTrue(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame, whole)
    }

    func testCloseButtonOfTheColumnClosesIt() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        let whole = pane.terminal.frame
        pane.header.onBadgeClick?()
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        pane.changedFiles.closeButton.onClick?()
        XCTAssertFalse(pane.diff.isLoading, "fechar não relê: não há mais quem veja a lista")
        pane.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.showsChangedFiles)
        XCTAssertTrue(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame, whole)
    }

    func testHeaderMenuOpensAndClosesTheColumn() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        func item() throws -> NSMenuItem {
            try XCTUnwrap(pane.contextMenu().items.first { $0.title == "Arquivos alterados" })
        }
        func choose() throws {
            let item = try item()
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(try item().state, .off)
        try choose()
        XCTAssertTrue(pane.showsChangedFiles)
        XCTAssertEqual(try item().state, .on, "o menu diz que a coluna está aberta")
        try choose()
        XCTAssertFalse(pane.showsChangedFiles)
    }

    func testEachAgentHasItsOwnColumn() throws {
        let repo = try repository()
        let (controller, _) = started()
        let first = agent(in: repo, of: controller)
        let second = agent(in: repo, of: controller)
        first.header.onBadgeClick?()
        XCTAssertTrue(first.showsChangedFiles)
        XCTAssertFalse(second.showsChangedFiles)
    }

    // MARK: o que a coluna mostra

    func testOpeningTheColumnReadsTheRepositoryAgain() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        repo.write("outro.txt", "x\n")
        pane.header.onBadgeClick?()
        XCTAssertEqual(paths(pane), ["a.txt", "novo.txt"], "a última leitura aparece na hora")
        XCTAssertTrue(waitUntil { self.paths(pane) == ["a.txt", "novo.txt", "outro.txt"] })
        XCTAssertEqual(pane.changedFiles.title, "ALTERADOS 3")
    }

    func testRereadButtonOfTheColumnReadsTheRepositoryAgain() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        pane.header.onBadgeClick?()
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        repo.write("outro.txt", "x\n")
        XCTAssertFalse(waitUntil(timeout: 0.3) { self.paths(pane).count == 3 }, "sem gatilho, nada é relido")
        pane.changedFiles.refreshButton.onClick?()
        XCTAssertTrue(waitUntil { self.paths(pane) == ["a.txt", "novo.txt", "outro.txt"] })
    }

    func testClosedColumnStillFollowsTheReads() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        XCTAssertEqual(paths(pane), ["a.txt", "novo.txt"], "quando abrir, já abre com a lista")
        try FileManager.default.removeItem(atPath: repo.path + "/novo.txt")
        controller.refreshDiff(nil)
        XCTAssertTrue(waitUntil { self.paths(pane) == ["a.txt"] })
    }

    func testAgentOutsideARepositoryShowsTheWarningInTheColumn() throws {
        _ = try repository()
        let (controller, _) = started()
        controller.addAgents(1, in: fixture.temp.makeDirectory("Projetos/solta"))
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { pane.diff.state == .notRepository })
        resize(pane, width: 900)
        pane.toggleChangedFiles()
        pane.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.changedFiles.message, ChangedFilesView.notRepository)
    }

    // MARK: painel estreito

    func testNarrowPaneOpensTheDiffWindowInsteadOfTheColumn() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let fits = CGFloat(AgentPaneView.minTerminalWidth + ChangedFilesView.width + 2 * AgentPaneView.border + 12)
        let pane = agent(in: repo, of: controller, width: fits - 1)
        let whole = pane.terminal.frame

        pane.header.onBadgeClick?()
        pane.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.showsChangedFiles, "a coluna não cabe: o clique não a deixa pedida")
        XCTAssertTrue(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame, whole)
        XCTAssertEqual(shown().count, 1)
        XCTAssertTrue(controller.diffPanel?.pane === pane)

        // Com um ponto a mais de largura, a coluna cabe.
        resize(pane, width: fits)
        pane.header.onBadgeClick?()
        pane.layoutSubtreeIfNeeded()
        XCTAssertTrue(pane.showsChangedFiles)
        XCTAssertFalse(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame.width, CGFloat(AgentPaneView.minTerminalWidth))
        XCTAssertEqual(shown().count, 1)
    }

    func testColumnHidesWhileThePaneIsNarrowAndComesBack() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let pane = agent(in: repo, of: controller)
        pane.header.onBadgeClick?()
        pane.layoutSubtreeIfNeeded()
        let open = pane.terminal.frame.width

        resize(pane, width: 500)
        XCTAssertTrue(pane.showsChangedFiles, "continua pedida")
        XCTAssertTrue(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame.width, 500 - 2 * CGFloat(AgentPaneView.border) - 12)

        resize(pane, width: 900)
        XCTAssertFalse(pane.changedFiles.isHidden)
        XCTAssertEqual(pane.terminal.frame.width, open)
        XCTAssertTrue(shown().isEmpty)
    }

    func testClickOnTheSummaryWithTheColumnHiddenClosesIt() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let pane = agent(in: repo, of: controller)
        pane.header.onBadgeClick?()
        resize(pane, width: 500)

        // Pedida mas sem caber: o clique desfaz o pedido, não abre a janela.
        pane.header.onBadgeClick?()
        XCTAssertFalse(pane.showsChangedFiles)
        XCTAssertTrue(shown().isEmpty)
        resize(pane, width: 900)
        XCTAssertTrue(pane.changedFiles.isHidden)
    }

    // MARK: arquivo clicado

    func testClickOnAFileOpensTheDiffWindowOnThatFile() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let pane = agent(in: repo, of: controller)
        pane.header.onBadgeClick?()
        let file = try XCTUnwrap(pane.changedFiles.list.rows.compactMap { row -> DiffFile? in
            if case .file(let file) = row, file.path == "novo.txt" { return file }
            return nil
        }.first)

        pane.changedFiles.onSelect?(file)
        XCTAssertEqual(shown().count, 1)
        let panel = try XCTUnwrap(controller.diffPanel)
        XCTAssertTrue(shown().first === panel)
        XCTAssertTrue(panel.pane === pane)
        XCTAssertEqual(panel.selectedPath, "novo.txt")
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })
        XCTAssertFalse(panel.text.contains("+dois"))
        XCTAssertTrue(pane.showsChangedFiles, "a coluna continua aberta")
    }

    func testClickOnAFileReadsTheRepositoryAgain() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        pane.header.onBadgeClick?()
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        repo.write("outro.txt", "x\n")

        pane.changedFiles.onSelect?(DiffFile(path: "novo.txt", status: .untracked, added: 1, removed: 0))
        let panel = try XCTUnwrap(controller.diffPanel)
        XCTAssertTrue(waitUntil { panel.files.contains { $0.path == "outro.txt" } },
                      "a janela abre com o que há agora no repositório")
        XCTAssertEqual(panel.selectedPath, "novo.txt", "a releitura não tira o arquivo escolhido")
    }

    func testClickOnAFileOfAnotherAgentMovesTheWindowToIt() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let first = agent(in: repo, of: controller)
        let second = agent(in: repo, of: controller)
        controller.showDiff(nil)
        XCTAssertTrue(controller.diffPanel?.pane === second, "o ⌘⇧D abre no agente em foco")

        first.toggleChangedFiles()
        first.changedFiles.onSelect?(DiffFile(path: "novo.txt", status: .untracked, added: 1, removed: 0))
        XCTAssertEqual(shown().count, 2)
        XCTAssertTrue(controller.diffPanel?.pane === first)
        XCTAssertEqual(controller.diffPanel?.selectedPath, "novo.txt")
    }

    // MARK: estado e tema

    func testOpeningTheColumnDoesNotCountAsWork() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        // O terminal fica mais estreito e o agente redesenha a tela: isso não é trabalho.
        pane.header.onBadgeClick?()
        fixture.now += 0.7
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        fixture.now += 5
        controller.tick()
        pane.changedFiles.closeButton.onClick?()
        fixture.now += 0.7
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .idle, "fechar também muda a largura")

        fixture.now += 5
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .working, "fora da janela de silêncio, saída é trabalho")
    }

    func testThemeReachesTheColumn() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo, of: controller)
        XCTAssertEqual(pane.changedFiles.theme.name, Theme.dark.name)
        pane.apply(TerminalAppearance(theme: .swapped, fontName: "Menlo", fontSize: 12))
        XCTAssertEqual(pane.changedFiles.theme.name, "outro")
    }
}
