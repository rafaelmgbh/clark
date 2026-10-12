import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A janela do diff: lista de arquivos, diff do escolhido e os avisos de cada estado.
final class DiffWindowControllerTests: XCTestCase {
    private var fixture: ClarkFixture!
    private let theme = Theme.dark

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

    private func agent(in directory: String, of controller: MainWindowController) -> AgentPaneView {
        controller.addAgents(1, in: directory)
        return controller.panes[controller.panes.count - 1]
    }

    private func select(_ row: Int, in panel: DiffWindowController) {
        panel.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    // MARK: lista e diff

    func testPanelListsTheFilesAndShowsTheFirstDiff() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })

        let panel = controller.diffPanel(for: pane)
        XCTAssertTrue(panel.pane === pane)
        XCTAssertEqual(panel.window?.title, "Diff — AGENT 1")
        XCTAssertEqual(panel.window?.isVisible, false, "pedir a janela não a põe na tela")
        XCTAssertEqual(panel.files.map(\.path), ["a.txt", "novo.txt"])
        XCTAssertEqual(panel.table.numberOfRows, 2)
        XCTAssertEqual(panel.selectedPath, "a.txt")
        XCTAssertTrue(panel.subtitle.stringValue.hasSuffix("+2 -0 2 ARQ"), panel.subtitle.stringValue)
        XCTAssertTrue(panel.subtitle.stringValue.contains("~/Projetos/acme/api"), panel.subtitle.stringValue)
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })
        XCTAssertTrue(panel.text.contains("@@"))
    }

    func testListKeepsItsWidthAndTheDiffFillsTheRest() throws {
        let repo = try repository()
        let (controller, _) = started()
        let panel = controller.diffPanel(for: agent(in: repo.path, of: controller))
        let content = try XCTUnwrap(panel.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let split = try XCTUnwrap(content.subviews.compactMap { $0 as? NSSplitView }.first)
        XCTAssertEqual(split.frame.width, content.bounds.width)
        XCTAssertEqual(split.arrangedSubviews.count, 2)
        XCTAssertEqual(split.arrangedSubviews.first?.frame.width, 320)
        XCTAssertEqual(split.arrangedSubviews.last?.frame.maxX, split.bounds.width, "o diff vai até a borda da janela")

        // Janela mais larga: quem ganha o espaço é o diff.
        split.setFrameSize(NSSize(width: split.frame.width + 300, height: split.frame.height))
        split.layoutSubtreeIfNeeded()
        XCTAssertEqual(split.arrangedSubviews.first?.frame.width, 320)
        XCTAssertEqual(split.arrangedSubviews.last?.frame.maxX, split.bounds.width)
    }

    func testPanelFrameIsRememberedOnlyWhenTheAppAsks() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertEqual(controller.diffPanel(for: pane).window?.frameAutosaveName, "",
                       "sem pedido, a janela não lê nem grava posição nas preferências")
        controller.shutdown()

        let (other, _) = started()
        let name = "ClarkDiffTeste-" + UUID().uuidString
        defer { NSWindow.removeFrame(usingName: name) }
        other.diffAutosaveName = name
        XCTAssertEqual(other.diffPanel(for: agent(in: repo.path, of: other)).window?.frameAutosaveName, name)
        other.shutdown()
    }

    func testChoosingAnotherFileShowsItsDiff() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let panel = controller.diffPanel(for: pane)
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })

        select(1, in: panel)
        XCTAssertEqual(panel.selectedPath, "novo.txt")
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })
        XCTAssertFalse(panel.text.contains("+dois"))
    }

    func testChoosingAFileByItsPathShowsItsDiff() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let panel = controller.diffPanel(for: pane)
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })

        panel.select(path: "novo.txt")
        XCTAssertEqual(panel.selectedPath, "novo.txt")
        XCTAssertEqual(panel.table.selectedRow, 1, "a tabela acompanha")
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })
        XCTAssertFalse(panel.text.contains("+dois"))
    }

    func testPathChosenBeforeTheFirstReadIsShownWhenTheReadArrives() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        let panel = controller.diffPanel(for: pane)
        XCTAssertEqual(panel.files, [])

        panel.select(path: "novo.txt")
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })
        XCTAssertEqual(panel.selectedPath, "novo.txt")
        XCTAssertEqual(panel.table.selectedRow, 1)
    }

    func testPathThatIsNotInTheListLeavesTheChoiceAlone() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let panel = controller.diffPanel(for: pane)
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })

        panel.select(path: "sumiu.txt")
        XCTAssertEqual(panel.selectedPath, "a.txt")
        XCTAssertEqual(panel.table.selectedRow, 0)
        XCTAssertTrue(panel.text.contains("+dois"))
    }

    func testPanelOpenedBeforeTheFirstReadFillsItselfWhenTheReadArrives() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        let panel = controller.diffPanel(for: pane)
        XCTAssertEqual(panel.text, "Lendo o repositório…")
        XCTAssertEqual(panel.files, [])
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })
        XCTAssertEqual(panel.selectedPath, "a.txt")
    }

    func testNewReadKeepsTheChosenFileAndShowsItsNewContent() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let panel = controller.diffPanel(for: pane)
        select(1, in: panel)
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })

        // Um arquivo entra antes do escolhido na lista, e o escolhido muda de conteúdo sem mudar de tamanho.
        repo.write("0.txt", "zero\n")
        repo.write("novo.txt", "linha nova\n".replacingOccurrences(of: "nova", with: "nove"))
        controller.refreshDiff(nil)
        XCTAssertTrue(waitUntil { panel.files.count == 3 })
        XCTAssertEqual(panel.files.map(\.path), ["0.txt", "a.txt", "novo.txt"])
        XCTAssertEqual(panel.selectedPath, "novo.txt", "a escolha segue o arquivo, não a linha da tabela")
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nove") })
    }

    func testChosenFileThatLeftTheListGivesPlaceToTheFirst() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let panel = controller.diffPanel(for: pane)
        select(1, in: panel)
        XCTAssertTrue(waitUntil { panel.text.contains("+linha nova") })

        try FileManager.default.removeItem(atPath: repo.path + "/novo.txt")
        controller.refreshDiff(nil)
        XCTAssertTrue(waitUntil { panel.files.count == 1 })
        XCTAssertEqual(panel.selectedPath, "a.txt")
        XCTAssertTrue(waitUntil { panel.text.contains("+dois") })
    }

    // MARK: avisos

    func testCleanRepositorySaysNothingChanged() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        try FileManager.default.removeItem(atPath: repo.path + "/novo.txt")
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        let panel = controller.diffPanel(for: pane)
        XCTAssertEqual(panel.text, "Nada mudou desde o último commit.")
        XCTAssertEqual(panel.files, [])
        XCTAssertNil(panel.selectedPath)
    }

    func testFolderOutsideARepositorySaysSo() throws {
        _ = try repository()
        let (controller, _) = started()
        let pane = agent(in: fixture.temp.makeDirectory("Projetos/solta"), of: controller)
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        XCTAssertEqual(controller.diffPanel(for: pane).text, "Esta pasta não é um repositório git.")
    }

    func testWithoutGitThePanelSaysSo() {
        let controller = fixture.started(agents: 1)
        let panel = controller.diffPanel(for: controller.panes[0])
        XCTAssertEqual(panel.text, "git não encontrado no PATH.")
        XCTAssertTrue(panel.subtitle.stringValue.hasPrefix("~"), panel.subtitle.stringValue)
    }

    func testGitThatFailsSaysSo() {
        fixture.gitPath = fixture.temp.write("bin/git", "#!/bin/sh\nexit 1\n", permissions: 0o755)
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
        XCTAssertEqual(pane.diff.state, .notRepository)

        fixture.gitPath = fixture.temp.path + "/bin/nao-existe"
        let broken = fixture.started(agents: 1)
        XCTAssertTrue(waitUntil { !broken.panes[0].diff.isLoading })
        XCTAssertEqual(broken.diffPanel(for: broken.panes[0]).text, "O git falhou ou não respondeu a tempo.")
    }

    // MARK: abrir, trocar e fechar

    func testShowDiffPresentsThePanelOfTheCurrentAgentAndReadsAgain() throws {
        let repo = try repository()
        let (controller, shown) = started()
        controller.showDiff(nil)
        XCTAssertTrue(shown().isEmpty, "sem agente não há o que mostrar")

        let first = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { first.snapshot.diff?.files == 2 })
        repo.write("outro.txt", "x\n")
        controller.showDiff(nil)
        XCTAssertEqual(shown().count, 1)
        XCTAssertTrue(shown().first === controller.diffPanel)
        XCTAssertTrue(controller.diffPanel?.pane === first)
        XCTAssertTrue(waitUntil { controller.diffPanel?.files.count == 3 }, "abrir relê o repositório")

        // A janela é uma só: pedir o diff de outro agente troca o conteúdo dela.
        let second = agent(in: fixture.home, of: controller)
        controller.showDiff(nil)
        XCTAssertEqual(shown().count, 2)
        XCTAssertTrue(shown()[0] === shown()[1])
        XCTAssertTrue(controller.diffPanel?.pane === second)
        XCTAssertEqual(controller.diffPanel?.window?.title, "Diff — AGENT 2")
        XCTAssertEqual(controller.diffPanel?.files, [])
    }

    func testHeaderMenuOpensTheDiffOfThatAgent() throws {
        let repo = try repository()
        let (controller, shown) = started()
        let first = agent(in: repo.path, of: controller)
        _ = agent(in: repo.path, of: controller)
        let menu = first.contextMenu()
        XCTAssertEqual(menu.items.prefix(7).map(\.title),
                       ["Renomear…", "Apelidar projeto…", "Zoom", "Ver diff", "Arquivos alterados",
                        "Novo agente nesta pasta", "Fechar"])
        let item = try XCTUnwrap(menu.items.first { $0.title == "Ver diff" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(shown().count, 1)
        XCTAssertTrue(controller.diffPanel?.pane === first, "o do agente clicado, não o do agente em foco")
    }

    func testClosingTheAgentClosesItsPanelAndOnlyIts() throws {
        let repo = try repository()
        let (controller, _) = started()
        let first = agent(in: repo.path, of: controller)
        let second = agent(in: repo.path, of: controller)
        let panel = controller.diffPanel(for: first)

        controller.close(second)
        XCTAssertTrue(panel.pane === first)
        controller.close(first)
        XCTAssertNil(panel.pane)
        XCTAssertEqual(panel.files, [])
        XCTAssertEqual(panel.text, "")
    }

    func testCloseShortcutInsideThePanelClosesThePanelAndNotTheAgent() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        let panel = controller.diffPanel(for: pane)
        // Com a janela do diff na frente, o ⌘W chega nela antes de chegar no controller.
        XCTAssertTrue(panel.responds(to: #selector(MainWindowController.closeAgent(_:))))
        panel.perform(#selector(MainWindowController.closeAgent(_:)), with: nil)
        XCTAssertEqual(controller.panes.count, 1)
        XCTAssertNotEqual(pane.state, .exited)
    }

    func testRenamingTheAgentRenamesThePanel() throws {
        let repo = try repository()
        let (controller, _) = started()
        let pane = agent(in: repo.path, of: controller)
        let panel = controller.diffPanel(for: pane)
        controller.applyRename(pane, text: "API")
        XCTAssertEqual(panel.window?.title, "Diff — API")
    }

    func testMenuItemsOfTheDiffNeedAnAgent() {
        let controller = fixture.started()
        func enabled(_ action: Selector) -> Bool {
            controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        XCTAssertFalse(enabled(#selector(MainWindowController.showDiff(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.refreshDiff(_:))))
        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.showDiff(_:))))
        XCTAssertTrue(enabled(#selector(MainWindowController.refreshDiff(_:))))
    }

    // MARK: texto colorido

    private func color(_ text: NSAttributedString, at needle: String) -> NSColor? {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    func testDiffLinesGetTheirColors() {
        let diff = FileDiff(text: "diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n igual\n-saiu\n+entrou\n"
            + "\\ No newline at end of file\n", truncated: false)
        let text = DiffWindowController.attributed(diff, theme: theme)
        XCTAssertEqual(text.string, diff.text)
        XCTAssertEqual(color(text, at: "diff --git"), theme.dim.nsColor)
        XCTAssertEqual(color(text, at: "+++ b/a.txt"), theme.dim.nsColor, "cabeçalho não é linha adicionada")
        XCTAssertEqual(color(text, at: "@@"), theme.accent.nsColor)
        XCTAssertEqual(color(text, at: " igual"), theme.ink.nsColor)
        XCTAssertEqual(color(text, at: "-saiu"), theme.red.nsColor)
        XCTAssertEqual(color(text, at: "+entrou"), theme.green.nsColor)
        XCTAssertEqual(color(text, at: "\\ No newline"), theme.dim.nsColor)
    }

    func testHugeDiffIsCutOnTheScreen() {
        let long = String(repeating: "x", count: 50)
        let diff = FileDiff(text: "@@ -0,0 +1,4 @@\n+a\n+\(long)\n+c\n+d\n", truncated: false)
        let text = DiffWindowController.attributed(diff, theme: theme, lineLimit: 3, lineLength: 10)
        XCTAssertEqual(text.string, "@@ -0,0 +1…\n+a\n+xxxxxxxxx…\n" + DiffWindowController.cutNote + "\n")
        XCTAssertEqual(color(text, at: DiffWindowController.cutNote), theme.yellow.nsColor)

        let cutByGit = DiffWindowController.attributed(FileDiff(text: "@@ -0,0 +1 @@\n+a\n", truncated: true), theme: theme)
        XCTAssertTrue(cutByGit.string.hasSuffix(DiffWindowController.cutNote + "\n"))
    }

    func testFileWithoutTextDifferenceSaysSo() {
        let text = DiffWindowController.attributed(FileDiff(text: "", truncated: false), theme: theme)
        XCTAssertEqual(text.string, "(sem diferença de texto)")
    }
}
