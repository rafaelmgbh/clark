import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A coluna dos arquivos alterados, conferida pelo desenho e pelos cliques.
final class ChangedFilesViewTests: XCTestCase {
    private let theme = Theme.dark
    private let files = [
        DiffFile(path: "notas.md", status: .untracked, added: 4, removed: 0),
        DiffFile(path: "vendas/models/pedido.py", status: .modified, added: 84, removed: 3),
        DiffFile(path: "vendas/views/pedido.xml", status: .added, added: 7, removed: 0),
    ]

    private func changes(_ files: [DiffFile], truncated: Bool = false) -> DiffState {
        .changes(RepoChanges(root: "/repo", base: "HEAD", files: files, truncated: truncated))
    }

    /// Clique no ponto (x, y) da view, contado de cima para baixo.
    private func click(_ view: NSView, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: view.bounds.height - y),
                           modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    private func column(_ state: DiffState, height: Int = 400) -> (view: ChangedFilesView, image: RenderedImage) {
        let view = ChangedFilesView()
        view.state = state
        return (view, RenderedImage(view, width: ChangedFilesView.width, height: height))
    }

    /// Lista solta, com a largura que tem dentro da coluna.
    private func list(_ files: [DiffFile]) -> ChangedFilesListView {
        let list = ChangedFilesListView()
        list.rows = ChangedFiles.rows(files)
        list.frame = NSRect(x: 0, y: 0, width: ChangedFilesView.width - ChangedFilesView.edge, height: 300)
        return list
    }

    private func render(_ list: ChangedFilesListView) -> RenderedImage {
        RenderedImage(list, width: Int(list.frame.width), height: Int(list.frame.height))
    }

    // MARK: coluna

    func testEveryTextFitsThePixelFont() {
        for text in [ChangedFilesView.reading, ChangedFilesView.noGit, ChangedFilesView.notRepository,
                     ChangedFilesView.failed, ChangedFilesView.clean, ChangedFilesView.cutNote, "ALTERADOS 1.2K"] {
            XCTAssertEqual(PixelFont.normalize(text), text, text)
            XCTAssertLessThanOrEqual(PixelFont.textWidth(text, scale: 1), ChangedFilesView.width - 24, text)
        }
    }

    func testTitleCountsTheFiles() {
        XCTAssertEqual(column(changes(files)).view.title, "ALTERADOS 3")
        XCTAssertEqual(column(changes([])).view.title, "ALTERADOS 0")
        XCTAssertEqual(column(.unknown).view.title, "ALTERADOS", "sem leitura não há o que contar")
        let many = (0..<1234).map { DiffFile(path: "f\($0).txt", status: .modified, added: 1, removed: 1) }
        XCTAssertEqual(column(changes(many)).view.title, "ALTERADOS 1.2K")
    }

    func testHeadShowsTheTitleAndTheButtonsOnTheRight() {
        let (view, image) = column(changes(files))
        let head = ChangedFilesView.headHeight
        XCTAssertTrue(image.isColor(theme.shadow, atX: 0, y: 200), "risco que separa a coluna do terminal")
        XCTAssertTrue(image.isColor(theme.bg2, atX: ChangedFilesView.edge + 1, y: 1), "cabeçalho")
        XCTAssertTrue(image.isColor(theme.bg, atX: ChangedFilesView.edge + 1, y: head + 1), "corpo")
        XCTAssertGreaterThan(image.count(theme.dim, x: 12, y: (head - 7) / 2,
                                         width: PixelFont.textWidth("ALTERADOS 3", scale: 1), height: 7), 0)
        XCTAssertEqual(image.count(theme.yellow, y: 0, height: head), 0, "lista inteira: sem aviso")

        XCTAssertEqual(Int(view.closeButton.frame.maxX), ChangedFilesView.width)
        XCTAssertEqual(view.refreshButton.frame.maxX, view.closeButton.frame.minX)
        XCTAssertEqual(view.closeButton.frame.height, CGFloat(head))
        XCTAssertEqual(view.refreshButton.frame.minY, 0)
        XCTAssertEqual(view.refreshButton.title, "R")
        XCTAssertEqual(view.closeButton.title, "X")
    }

    func testCutListIsFlaggedInTheHead() {
        let image = column(changes(files, truncated: true)).image
        let x = 12 + PixelFont.textWidth("ALTERADOS 3", scale: 1) + 10
        XCTAssertGreaterThan(image.count(theme.yellow, x: x, y: (ChangedFilesView.headHeight - 7) / 2,
                                         width: PixelFont.textWidth(ChangedFilesView.cutNote, scale: 1), height: 7), 0)
    }

    func testButtonsAskToRereadAndToClose() {
        var refreshed = 0, closed = 0
        let view = column(changes(files)).view
        view.onRefresh = { refreshed += 1 }
        view.onClose = { closed += 1 }
        view.refreshButton.onClick?()
        XCTAssertEqual([refreshed, closed], [1, 0])
        view.closeButton.onClick?()
        XCTAssertEqual([refreshed, closed], [1, 1])
    }

    func testMessageTakesThePlaceOfTheListWhenThereIsNoFile() {
        let cases: [(DiffState, String)] = [
            (.unknown, ChangedFilesView.reading), (.noGit, ChangedFilesView.noGit),
            (.notRepository, ChangedFilesView.notRepository), (.failed, ChangedFilesView.failed),
            (changes([]), ChangedFilesView.clean),
        ]
        for (state, message) in cases {
            let (view, image) = column(state)
            XCTAssertEqual(view.message, message)
            XCTAssertTrue(view.list.rows.isEmpty, message)
            XCTAssertEqual(view.list.enclosingScrollView?.isHidden, true, "a lista vazia cobriria o aviso: " + message)
            XCTAssertGreaterThan(image.count(theme.dim, x: 12, y: ChangedFilesView.headHeight + 12,
                                             width: PixelFont.textWidth(message, scale: 1), height: 7), 0, message)
        }
        let (view, image) = column(changes(files))
        XCTAssertNil(view.message)
        XCTAssertEqual(view.list.enclosingScrollView?.isHidden, false)
        XCTAssertEqual(image.count(theme.dim, y: ChangedFilesView.headHeight), 0, "com arquivo, o corpo é da lista")
    }

    func testListFollowsTheState() {
        let (view, _) = column(changes(files))
        XCTAssertEqual(view.list.rows, ChangedFiles.rows(files))
        view.state = changes([files[1]])
        XCTAssertEqual(view.list.rows, [.group(.modified, count: 1), .file(files[1])])
        view.state = .failed
        XCTAssertTrue(view.list.rows.isEmpty, "lista velha não fica embaixo do aviso")
        XCTAssertEqual(view.list.enclosingScrollView?.isHidden, true)
        view.state = changes(files)
        XCTAssertEqual(view.list.enclosingScrollView?.isHidden, false, "a lista volta quando há arquivo")
    }

    func testListFillsTheColumnAndGrowsWithTheFiles() {
        let (view, _) = column(changes(files), height: 400)
        let body = CGFloat(400 - ChangedFilesView.headHeight)
        XCTAssertEqual(view.list.frame.width, CGFloat(ChangedFilesView.width - ChangedFilesView.edge))
        XCTAssertEqual(view.list.frame.height, body, "poucos arquivos: a lista ocupa o corpo inteiro")
        XCTAssertEqual(view.list.enclosingScrollView?.frame,
                       NSRect(x: CGFloat(ChangedFilesView.edge), y: CGFloat(ChangedFilesView.headHeight),
                              width: CGFloat(ChangedFilesView.width - ChangedFilesView.edge), height: body))

        let many = (0..<60).map { DiffFile(path: "pasta/f\($0).txt", status: .modified, added: 1, removed: 1) }
        view.state = changes(many)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.list.frame.height, CGFloat(view.list.contentHeight), "muitos: a lista rola")
        XCTAssertGreaterThan(view.list.frame.height, body)
    }

    func testThemeReachesTheButtonsAndTheList() {
        let view = column(changes(files)).view
        view.theme = .swapped
        XCTAssertEqual(view.list.theme.name, "outro")
        XCTAssertEqual(view.refreshButton.theme.name, "outro")
        XCTAssertEqual(view.closeButton.theme.name, "outro")
    }

    func testFileChosenInTheListReachesWhoListensToTheColumn() {
        var chosen: [String] = []
        let view = column(changes(files)).view
        view.onSelect = { chosen.append($0.path) }
        view.list.onSelect?(files[1])
        XCTAssertEqual(chosen, ["vendas/models/pedido.py"])
    }

    // MARK: lista

    func testRowsHaveTheHeightOfWhatTheyShow() {
        let list = list(files)
        // MODIFICADOS, pedido.py, NOVOS, pedido.xml, NAO RASTREADOS, notas.md
        let group = ChangedFilesListView.groupHeight, file = ChangedFilesListView.fileHeight
        let root = ChangedFilesListView.rootFileHeight
        XCTAssertLessThan(root, file, "arquivo na raiz não tem a linha da pasta")
        XCTAssertEqual((0..<6).map(list.top(ofRow:)),
                       [0, group, group + file, 2 * group + file, 2 * group + 2 * file, 3 * group + 2 * file])
        XCTAssertEqual(list.contentHeight, 3 * group + 2 * file + root)
        XCTAssertEqual(list.row(atY: 0), 0)
        XCTAssertEqual(list.row(atY: group - 1), 0)
        XCTAssertEqual(list.row(atY: group), 1)
        XCTAssertEqual(list.row(atY: list.contentHeight - 1), 5)
        XCTAssertNil(list.row(atY: list.contentHeight), "abaixo da última linha não há arquivo")
        XCTAssertNil(list.row(atY: -1))
    }

    func testFileRowShowsTheStatusLetterInItsColorAndTheCounts() {
        let list = list(files)
        let image = render(list)
        let width = Int(list.frame.width)
        let modified = list.top(ofRow: 1), added = list.top(ofRow: 3), untracked = list.top(ofRow: 5)
        XCTAssertGreaterThan(image.count(theme.yellow, x: 10, y: modified + 6, width: 5, height: 7), 0, "M amarelo")
        XCTAssertGreaterThan(image.count(theme.green, x: 10, y: added + 6, width: 5, height: 7), 0, "A verde")
        XCTAssertGreaterThan(image.count(theme.green, x: 10, y: untracked + 6, width: 5, height: 7), 0, "? verde")

        // `+84 -3` encostado na direita: o verde antes do vermelho.
        let counts = PixelFont.textWidth("+84 -3", scale: 1)
        let plus = PixelFont.textWidth("+84", scale: 1)
        let x = width - 8 - counts
        XCTAssertGreaterThan(image.count(theme.green, x: x, y: modified + 6, width: plus, height: 7), 0)
        XCTAssertEqual(image.count(theme.red, x: x, y: modified + 6, width: plus, height: 7), 0)
        XCTAssertGreaterThan(image.count(theme.red, x: x + plus, y: modified + 6, width: counts - plus, height: 7), 0)
        XCTAssertEqual(image.count(theme.green, x: 20, y: modified, width: x - 20, height: 34), 0,
                       "o nome não entra na cor das contagens")
    }

    func testFileRowShowsTheNameAndTheFolderUnderIt() {
        let list = list(files)
        let image = render(list)
        let empty = render(self.list([]))
        let width = Int(list.frame.width)
        let row = list.top(ofRow: 1)
        // O texto corrido é suavizado: confere-se pelo fundo que ele cobre.
        func covered(_ y: Int, _ height: Int, upTo right: Int? = nil) -> Int {
            let span = (right ?? width) - 24
            return empty.count(theme.bg, x: 24, y: y, width: span, height: height)
                - image.count(theme.bg, x: 24, y: y, width: span, height: height)
        }
        // O nome é conferido só até onde as contagens começam: elas também cobrem o fundo.
        let counts = width - 8 - PixelFont.textWidth("+84 -3", scale: 1)
        XCTAssertGreaterThan(covered(row, 17, upTo: counts), 0, "nome do arquivo")
        XCTAssertGreaterThan(covered(row + 17, ChangedFilesListView.fileHeight - 17), 0, "pasta")

        // Na raiz do repositório não há pasta: a linha é mais baixa e só tem o nome.
        let root = list.top(ofRow: 5)
        let rootCounts = width - 8 - PixelFont.textWidth("+4 -0", scale: 1)
        XCTAssertGreaterThan(covered(root, ChangedFilesListView.rootFileHeight, upTo: rootCounts), 0, "notas.md")
        XCTAssertEqual(covered(root + ChangedFilesListView.rootFileHeight, 40), 0)
    }

    func testLongNameIsCutBeforeTheCounts() {
        let long = [DiffFile(path: "pasta/" + String(repeating: "nome_comprido_", count: 12) + ".py", status: .modified,
                             added: 84, removed: 3)]
        let list = list(long)
        let image = render(list)
        let empty = render(self.list([]))
        let width = Int(list.frame.width), row = list.top(ofRow: 1)
        let counts = width - 8 - PixelFont.textWidth("+84 -3", scale: 1)
        XCTAssertEqual(image.count(theme.bg, x: counts - 8, y: row, width: 8, height: 17),
                       empty.count(theme.bg, x: counts - 8, y: row, width: 8, height: 17),
                       "sobra um respiro entre o nome e as contagens")
        XCTAssertGreaterThan(image.count(theme.green, x: counts, y: row + 6, width: 17, height: 7), 0)
    }

    func testOnlyTheStretchAskedForIsDrawn() {
        let many = (0..<100).map { DiffFile(path: "pasta/f\($0).txt", status: .modified, added: 1, removed: 1) }
        let list = list(many)
        let width = Int(list.frame.width), height = list.contentHeight
        let file = ChangedFilesListView.fileHeight
        let stretch = RenderedImage(list, width: width, height: height,
                                    dirty: NSRect(x: 0, y: 1000, width: width, height: 200))
        XCTAssertGreaterThan(stretch.count(theme.yellow, y: 1000, height: 200), 0)
        XCTAssertEqual(stretch.count(theme.yellow, y: 0, height: 1000 - file), 0, "acima do trecho nada é desenhado")
        XCTAssertEqual(stretch.count(theme.yellow, y: 1200 + file), 0, "nem abaixo")
        XCTAssertTrue(stretch.isColor(theme.bg, atX: 2, y: 2), "o fundo é da lista inteira")

        let whole = RenderedImage(list, width: width, height: height)
        XCTAssertGreaterThan(whole.count(theme.yellow, y: 0, height: 100), 0, "sem trecho pedido, tudo")
        XCTAssertGreaterThan(whole.count(theme.yellow, y: height - 100), 0)
    }

    func testFileWithoutCountsShowsADash() {
        let binary = [DiffFile(path: "logo.png", status: .modified, added: nil, removed: nil)]
        let list = list(binary)
        let image = render(list)
        let width = Int(list.frame.width), row = list.top(ofRow: 1)
        XCTAssertEqual(image.count(theme.green) + image.count(theme.red), 0)
        XCTAssertGreaterThan(image.count(theme.dim, x: width - 8 - 5, y: row + 6, width: 5, height: 7), 0)
    }

    func testGroupRowShowsTheTitleAndHowManyFiles() {
        let list = list(files)
        let image = render(list)
        let title = PixelFont.textWidth("MODIFICADOS 1", scale: 1)
        XCTAssertGreaterThan(image.count(theme.dim, x: 10, y: 9, width: title, height: 7), 0)
        XCTAssertEqual(image.count(theme.dim, x: 10 + title + 2, y: 9, width: 100, height: 7), 0)
        XCTAssertEqual(ChangedFilesListView.groupTitle(.untracked, count: 12), "NAO RASTREADOS 12")
        XCTAssertEqual(ChangedFilesListView.groupTitle(.modified, count: 1234), "MODIFICADOS 1.2K")
    }

    func testClickChoosesTheFileOfTheRow() {
        var chosen: [DiffFile] = []
        let list = list(files)
        list.onSelect = { chosen.append($0) }
        list.mouseDown(with: click(list, x: 40, y: CGFloat(list.top(ofRow: 3) + 10)))
        XCTAssertEqual(chosen, [files[2]])
        list.mouseDown(with: click(list, x: 40, y: 5))
        XCTAssertEqual(chosen, [files[2]], "título de grupo não é arquivo")
        list.mouseDown(with: click(list, x: 40, y: CGFloat(list.contentHeight + 20)))
        XCTAssertEqual(chosen, [files[2]], "abaixo da lista não há o que abrir")
        list.mouseDown(with: click(list, x: 40, y: CGFloat(list.top(ofRow: 5) + 2)))
        XCTAssertEqual(chosen, [files[2], files[0]])
        XCTAssertTrue(list.acceptsFirstMouse(for: nil), "abre no primeiro clique, mesmo com a janela atrás")
        XCTAssertFalse(list.acceptsFirstResponder, "o teclado continua no terminal")
    }

    func testRowUnderTheMouseIsHighlighted() {
        let list = list(files)
        let row = list.top(ofRow: 1)
        XCTAssertTrue(render(list).isColor(theme.bg, atX: 2, y: row + 2))
        list.setHovered(1)
        XCTAssertEqual(list.hovered, 1)
        let image = render(list)
        XCTAssertTrue(image.isColor(theme.bg3, atX: 2, y: row + 2))
        XCTAssertTrue(image.isColor(theme.bg3, atX: Int(list.frame.width) - 2, y: row + ChangedFilesListView.fileHeight - 1))
        XCTAssertTrue(image.isColor(theme.bg, atX: 2, y: list.top(ofRow: 3) + 2), "só a linha sob o mouse")

        list.setHovered(0)
        XCTAssertNil(list.hovered, "título de grupo não acende")
        list.setHovered(99)
        XCTAssertNil(list.hovered)
        list.setHovered(1)
        list.rows = ChangedFiles.rows([files[1]])
        XCTAssertNil(list.hovered, "lista nova: a linha sob o mouse pode ser outra")
    }
}
