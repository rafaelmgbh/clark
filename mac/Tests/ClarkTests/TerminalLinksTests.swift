import ClarkCore
import SwiftTerm
import XCTest
@testable import Clark

final class TerminalLinksTests: XCTestCase {
    private let esc = "\u{1b}"

    /// Terminal sem processo, com a tela deste tamanho e este texto.
    private func terminal(cols: Int = 40, rows: Int = 6, _ text: String) -> AgentTerminalView {
        let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.resize(cols: cols, rows: rows)
        view.feed(text: text)
        return view
    }

    private func spans(_ view: AgentTerminalView) -> [LinkSpan] {
        TerminalLinks.spans(in: view.getTerminal())
    }

    private func spans(cols: Int = 40, rows: Int = 6, _ text: String) -> [LinkSpan] {
        spans(terminal(cols: cols, rows: rows, text))
    }

    /// Link explícito (OSC 8): o texto aparece, o endereço fica escondido.
    private func explicit(_ url: String, _ text: String) -> String {
        "\(esc)]8;;\(url)\(esc)\\\(text)\(esc)]8;;\(esc)\\"
    }

    // MARK: onde está o link

    func testWebLinkIsFoundWhereItIs() {
        XCTAssertEqual(spans("veja https://example.com/a agora"), [LinkSpan(row: 0, columns: 5..<26)])
        XCTAssertEqual(spans("ola\r\n  http://example.com"), [LinkSpan(row: 1, columns: 2..<20)])
    }

    func testPunctuationAfterTheLinkStaysOut() {
        XCTAssertEqual(spans("abra http://example.com/a."), [LinkSpan(row: 0, columns: 5..<25)])
        XCTAssertEqual(spans("(https://example.com/a)"), [LinkSpan(row: 0, columns: 1..<22)])
    }

    func testEveryLinkOfTheLineIsFound() {
        XCTAssertEqual(spans("https://a.example/x e https://b.example/y"),
                       [LinkSpan(row: 0, columns: 0..<19), LinkSpan(row: 0, columns: 22..<40),
                        LinkSpan(row: 1, columns: 0..<1)])
    }

    func testLinkInsideAnotherIsOneLink() {
        XCTAssertEqual(spans(cols: 60, "https://a.example/?next=https://b.example/y fim"),
                       [LinkSpan(row: 0, columns: 0..<43)])
    }

    func testTextWithoutLinkHasNoSpan() {
        XCTAssertEqual(spans("nada aqui\r\nhttp sem endereco, https tambem"), [])
        XCTAssertEqual(spans(""), [])
    }

    // MARK: só o que o clique abre

    func testOnlyWhatTheClickOpensIsFound() {
        // O SwiftTerm também acha caminhos e outros esquemas; o clique do CLARK não abre nenhum deles.
        let text = ["file:///etc/hosts", "ssh://host/x mailto:a@example.com", "~/Projetos/acme/api.txt",
                    "src/main.swift", "docs/https://example.com/a"].joined(separator: "\r\n")
        XCTAssertEqual(spans(text), [])
    }

    func testAddressTheClickCannotOpenIsNotFound() {
        // O SwiftTerm aceita como link, mas a porta não é número: não há endereço para abrir.
        let view = terminal("abra http://localhost:PORTA/x")
        XCTAssertEqual(view.getTerminal().link(at: .buffer(Position(col: 5, row: 0)), mode: .explicitAndImplicit),
                       "http://localhost:PORTA/x")
        XCTAssertNil(TerminalLinks.webURL("http://localhost:PORTA/x"))
        XCTAssertEqual(spans(view), [])
    }

    func testExplicitLinkIsFoundUnderItsText() {
        XCTAssertEqual(spans("abra " + explicit("https://example.com/a", "aqui") + " hoje"),
                       [LinkSpan(row: 0, columns: 5..<9)])
        XCTAssertEqual(spans(explicit("HTTP://example.com", "a") + explicit("https://example.com", "b")),
                       [LinkSpan(row: 0, columns: 0..<1), LinkSpan(row: 0, columns: 1..<2)],
                       "dois links colados são dois")
    }

    func testExplicitLinkWithItsAddressAsTextIsOneLink() {
        XCTAssertEqual(spans(explicit("https://example.com/a", "https://example.com/a") + " fim"),
                       [LinkSpan(row: 0, columns: 0..<21)])
    }

    func testLinksComeInTheOrderOfTheScreen() {
        XCTAssertEqual(spans("https://example.com/a " + explicit("https://example.com/b", "aqui")),
                       [LinkSpan(row: 0, columns: 0..<21), LinkSpan(row: 0, columns: 22..<26)])
    }

    func testExplicitLinkToAnotherSchemeIsNotFound() {
        // O texto parece um link da web, mas o clique abriria o endereço escondido: nada.
        XCTAssertEqual(spans(explicit("file:///etc/hosts", "https://example.com/a") + " fim"), [])
        XCTAssertEqual(spans(explicit("ssh://host", "entrar") + " https://example.com/a"),
                       [LinkSpan(row: 0, columns: 7..<28)])
    }

    // MARK: link em mais de uma linha

    func testLinkWrappedByTheTerminalIsFoundOnEveryLine() {
        let url = "https://example.com/" + String(repeating: "a", count: 30)
        XCTAssertEqual(spans(cols: 20, url + " fim"),
                       [LinkSpan(row: 0, columns: 0..<20), LinkSpan(row: 1, columns: 0..<20),
                        LinkSpan(row: 2, columns: 0..<10)])
    }

    func testLinkBrokenByTheProgramIsFoundOnBothLines() {
        // O Claude Code quebra a linha ele mesmo e recua a continuação.
        XCTAssertEqual(spans(cols: 20, "  https://example.co\r\n  m/caminho fim"),
                       [LinkSpan(row: 0, columns: 2..<20), LinkSpan(row: 1, columns: 2..<11)])
    }

    func testContinuationIndentedByMovingTheCursorIsFound() {
        // O recuo feito com o cursor deixa células vazias, sem espaço escrito nelas.
        XCTAssertEqual(spans(cols: 20, "  https://example.co\r\n\(esc)[2Cm/caminho fim"),
                       [LinkSpan(row: 0, columns: 2..<20), LinkSpan(row: 1, columns: 2..<11)])
    }

    func testSchemeBrokenBetweenLinesIsStillFound() {
        XCTAssertEqual(spans(cols: 20, String(repeating: "a", count: 16) + " https://example.com/a"),
                       [LinkSpan(row: 0, columns: 17..<20), LinkSpan(row: 1, columns: 0..<18)])
    }

    // MARK: rolagem

    func testOnlyTheVisiblePartCounts() {
        let view = terminal(cols: 40, rows: 4, "https://example.com/a\r\n1\r\n2\r\n3\r\n4\r\n5")
        XCTAssertEqual(spans(view), [], "o link rolou para cima da tela")
        view.scrollTo(row: 0)
        XCTAssertEqual(spans(view), [LinkSpan(row: 0, columns: 0..<21)])
        view.scrollTo(row: 1)
        XCTAssertEqual(spans(view), [])
    }

    func testLinkThatStartsAboveTheScreenIsFoundInWhatShows() {
        let url = "https://example.com/" + String(repeating: "a", count: 30)
        XCTAssertEqual(spans(cols: 20, rows: 3, url + "\r\nfim\r\nfim"), [LinkSpan(row: 0, columns: 0..<10)])
    }

    func testLinkThatEndsBelowTheScreenIsFoundInWhatShows() {
        let url = "https://example.com/" + String(repeating: "a", count: 30)
        let view = terminal(cols: 20, rows: 2, url + "\r\nfim\r\nfim")
        view.scrollTo(row: 0)
        XCTAssertEqual(spans(view), [LinkSpan(row: 0, columns: 0..<20), LinkSpan(row: 1, columns: 0..<20)])
    }

    func testLinkThatStartsFarAboveTheScreenIsNotFound() {
        // O começo ficou acima do que é lido. O endereço que aparece no meio dele não é outro link:
        // o clique ali abre o link inteiro.
        let cols = 20
        let url = "https://a.example/" + String(repeating: "a", count: cols * (TerminalLinks.lookback + 2))
            + "?next=https://b.example/y"
        XCTAssertEqual(spans(cols: cols, rows: 2, url), [])
    }

    // MARK: teto de trabalho

    func testLineWrappedTooManyTimesIsNotSearched() {
        let cols = 20
        // Uma linha só, sem quebra, maior que o teto: achar o link nela custaria ler a linha inteira.
        let huge = String(repeating: "a", count: cols * TerminalLinks.maxWrappedRows) + " https://example.com/a"
        XCTAssertEqual(spans(cols: cols, rows: 4, huge + "\r\nhttp://b.example/x"),
                       [LinkSpan(row: 3, columns: 0..<18)])

        // No teto ainda procura: o link ocupa as duas últimas das 32 linhas.
        let fits = String(repeating: "a", count: cols * (TerminalLinks.maxWrappedRows - 2)) + " https://example.com/a"
        XCTAssertEqual(spans(cols: cols, rows: 4, fits),
                       [LinkSpan(row: 2, columns: 1..<20), LinkSpan(row: 3, columns: 0..<2)])
    }

    func testLinkAtTheStartOfALineWrappedTooManyTimesIsNotSearched() {
        let cols = 20, rows = TerminalLinks.maxWrappedRows + 4
        // O link está na primeira das linhas: o que passa do teto vem depois dele.
        let huge = "https://example.com/a " + String(repeating: "a", count: cols * TerminalLinks.maxWrappedRows)
        XCTAssertEqual(spans(cols: cols, rows: rows, huge), [])

        // No teto ainda procura.
        let fits = "https://example.com/a " + String(repeating: "a", count: cols * TerminalLinks.maxWrappedRows - 22)
        XCTAssertEqual(spans(cols: cols, rows: rows, fits),
                       [LinkSpan(row: 0, columns: 0..<20), LinkSpan(row: 1, columns: 0..<1)])
    }

    func testSearchStopsAtTheLimitOfLinks() {
        // Longe da borda direita: perto dela o SwiftTerm emendaria o fim de uma linha no começo da outra.
        let line = "http://a.co http://b.co http://c.co http://d.co"
        let rows = TerminalLinks.maxProbes / 4 + 5
        let view = terminal(cols: 80, rows: rows, Array(repeating: line, count: rows).joined(separator: "\r\n"))
        XCTAssertEqual(spans(view).count, TerminalLinks.maxProbes)
        XCTAssertEqual(spans(view).first, LinkSpan(row: 0, columns: 0..<11))
    }

    // MARK: o endereço que abre

    func testOnlyWebAddressesOpen() {
        XCTAssertEqual(TerminalLinks.webURL("https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(TerminalLinks.webURL("HTTP://example.com")?.absoluteString, "HTTP://example.com")
        for link in ["file:///etc/passwd", "javascript:alert(1)", "ssh://host", "", "sem esquema", "/bin/sh",
                     "docs/https://example.com/a"] {
            XCTAssertNil(TerminalLinks.webURL(link), link)
        }
    }
}

final class LinkUnderlineViewTests: XCTestCase {
    private let color = RGB(hex: "#5e9be0")!
    private let metrics = LinkUnderlineView.Metrics(cell: CGSize(width: 10, height: 20), offset: 3.5, thickness: 1)

    private func makeView(_ spans: [LinkSpan]) -> LinkUnderlineView {
        let view = LinkUnderlineView()
        view.color = color
        view.metrics = metrics
        view.spans = spans
        return view
    }

    func testLineGoesUnderTheCellsOfTheLink() {
        let image = RenderedImage(drawing: makeView([LinkSpan(row: 1, columns: 2..<5)]), width: 200, height: 100)
        // Linha 1 da tela: de 20 a 40 a partir de cima. O traço fica a 3,5 do pé dela: de 36 a 37.
        XCTAssertEqual(image.count(color), 30)
        XCTAssertEqual(image.count(color, x: 20, y: 36, width: 30, height: 1), 30)
    }

    func testEverySpanGetsItsLine() {
        let view = makeView([LinkSpan(row: 0, columns: 0..<20), LinkSpan(row: 4, columns: 19..<20)])
        let image = RenderedImage(drawing: view, width: 200, height: 100)
        XCTAssertEqual(image.count(color, x: 0, y: 16, width: 200, height: 1), 200)
        XCTAssertEqual(image.count(color, x: 190, y: 96, width: 10, height: 1), 10)
        XCTAssertEqual(image.count(color), 210)
    }

    func testThicknessIsTheOneAsked() {
        let view = makeView([LinkSpan(row: 0, columns: 0..<1)])
        view.metrics.thickness = 2
        view.metrics.offset = 4
        let image = RenderedImage(drawing: view, width: 200, height: 100)
        XCTAssertEqual(image.count(color, x: 0, y: 15, width: 10, height: 2), 20)
        XCTAssertEqual(image.count(color), 20)
    }

    func testNothingIsDrawnWithoutSpansOrCells() {
        XCTAssertEqual(RenderedImage(drawing: makeView([]), width: 200, height: 100).count(color), 0)
        let view = makeView([LinkSpan(row: 0, columns: 0..<3)])
        view.metrics.cell = .zero
        XCTAssertEqual(RenderedImage(drawing: view, width: 200, height: 100).count(color), 0)
    }

    func testClicksGoThroughToTheTerminal() {
        let view = makeView([LinkSpan(row: 0, columns: 0..<20)])
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertNil(view.hitTest(NSPoint(x: 5, y: 85)))
    }

    func testChangeAsksForRedrawAndRepeatDoesNot() {
        let view = makeView([LinkSpan(row: 0, columns: 0..<3)])
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        // Fora de uma janela a vista não diz se precisa de redesenho; a camada dela diz.
        view.wantsLayer = true
        guard let layer = view.layer else { return XCTFail("a vista ficou sem camada") }
        layer.displayIfNeeded()
        XCTAssertFalse(layer.needsDisplay())

        view.spans = [LinkSpan(row: 0, columns: 0..<3)]
        view.metrics = metrics
        view.color = color
        XCTAssertFalse(layer.needsDisplay(), "o terminal refaz a conta a cada quadro: igual não redesenha")

        view.spans = [LinkSpan(row: 0, columns: 0..<4)]
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        view.metrics.offset = 5
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        view.color = RGB(hex: "#7fc86a")!
        XCTAssertTrue(layer.needsDisplay())
    }
}
