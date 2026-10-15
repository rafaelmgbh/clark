import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// Um nível do menu desenhado, conferido pixel a pixel num bitmap.
final class PixelMenuViewTests: XCTestCase {
    private let theme = Theme.dark
    /// Cor que não existe no tema: o que aparecer nela veio do item.
    private let magenta = RGB(r: 1, g: 0, b: 1)

    private func item(_ title: String, submenu: [NSMenuItem]? = nil, swatch: RGB? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let submenu {
            item.submenu = NSMenu(title: title)
            submenu.forEach { item.submenu?.addItem($0) }
        }
        if let swatch { item.image = PixelMenuView.swatch(swatch) }
        return item
    }

    /// Cabeçalho, duas linhas, separador, linha com submenu.
    private func view(swatch: RGB? = nil) -> PixelMenuView {
        let view = PixelMenuView(items: [
            .sectionHeader(title: "Mais usados"), item("Api"), item("Portal"), .separator(),
            item("ACME", submenu: [item("Loja")], swatch: swatch),
        ])
        view.frame = NSRect(x: 0, y: 0, width: view.fittingWidth, height: view.fittingHeight)
        return view
    }

    /// Vinte linhas numa altura em que cabem cinco.
    private func tallView() -> PixelMenuView {
        let view = PixelMenuView(items: (1...20).map { item("Projeto \($0)") })
        let height = 5 * PixelMenuView.rowHeight + 2 * PixelMenuView.inset + PixelMenuView.shadow
        view.frame = NSRect(x: 0, y: 0, width: view.fittingWidth, height: height)
        return view
    }

    private func image(_ view: PixelMenuView) -> RenderedImage {
        RenderedImage(view, width: Int(view.bounds.width), height: Int(view.bounds.height))
    }

    private func faceWidth(_ view: PixelMenuView) -> Int { view.fittingWidth - PixelMenuView.shadow }

    /// Evento do mouse na altura `y` da view, contada de cima para baixo.
    private func mouse(_ view: NSView, x: Int = 20, y: Int, type: NSEvent.EventType = .mouseMoved) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: CGFloat(x), y: view.bounds.height - CGFloat(y)),
                           modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    // MARK: linhas

    func testOnlyItemsCanBeSelected() {
        XCTAssertEqual(view().selectable, [false, true, true, false, true])
    }

    func testDisabledItemIsNotSelectableAndHiddenItemIsNotARow() {
        let off = item("Desligado")
        off.isEnabled = false
        let hidden = item("Escondido")
        hidden.isHidden = true
        let view = PixelMenuView(items: [item("Api"), hidden, off])
        XCTAssertEqual(view.items.map(\.title), ["Api", "Desligado"])
        XCTAssertEqual(view.selectable, [true, false])
    }

    func testHeightAddsUpTheRows() {
        let view = view()
        let rows = PixelMenuView.headerHeight + 3 * PixelMenuView.rowHeight + PixelMenuView.separatorHeight
        XCTAssertEqual(view.contentHeight, rows)
        XCTAssertEqual(view.fittingHeight, rows + 2 * PixelMenuView.inset + PixelMenuView.shadow)
        XCTAssertEqual(view.top(of: 0), PixelMenuView.inset)
        XCTAssertEqual(view.top(of: 1), PixelMenuView.inset + PixelMenuView.headerHeight)
    }

    func testWidthFollowsTheLongestTitleWithinLimits() {
        let short = PixelMenuView(items: [item("Api")])
        let long = PixelMenuView(items: [item("Api"), item(String(repeating: "m", count: 40))])
        let huge = PixelMenuView(items: [item(String(repeating: "m", count: 400))])
        XCTAssertEqual(short.fittingWidth, PixelMenuView.minWidth + PixelMenuView.shadow)
        XCTAssertGreaterThan(long.fittingWidth, short.fittingWidth)
        XCTAssertEqual(huge.fittingWidth, PixelMenuView.maxWidth + PixelMenuView.shadow, "título enorme é cortado")
    }

    func testRowUnderAPoint() {
        let view = view()
        XCTAssertEqual(view.row(atY: view.top(of: 1)), 1)
        XCTAssertEqual(view.row(atY: view.top(of: 2) - 1), 1)
        XCTAssertEqual(view.row(atY: view.top(of: 2)), 2)
        XCTAssertNil(view.row(atY: view.top(of: 0) + 2), "cabeçalho não é escolhido")
        XCTAssertNil(view.row(atY: view.top(of: 3) + 2), "separador não é escolhido")
        XCTAssertNil(view.row(atY: 0), "moldura")
        XCTAssertNil(view.row(atY: view.fittingHeight - 1), "sombra")
    }

    // MARK: desenho

    func testDrawsFaceFrameAndHardShadow() {
        let view = view()
        let image = image(view)
        let width = view.fittingWidth, height = view.fittingHeight
        XCTAssertTrue(image.isColor(theme.shadow, atX: 0, y: 0), "moldura")
        XCTAssertTrue(image.isColor(theme.shadow, atX: faceWidth(view) - 1, y: height - PixelMenuView.shadow - 1),
                      "moldura")
        XCTAssertTrue(image.isColor(theme.bg2, atX: PixelMenuView.border, y: PixelMenuView.border), "fundo")
        XCTAssertTrue(image.isColor(theme.shadow, atX: width - 1, y: height - 1), "sombra dura")
        XCTAssertFalse(image.isColor(theme.shadow, atX: width - 1, y: 0), "a sombra sai deslocada: o canto fica vazio")
        XCTAssertFalse(image.isColor(theme.shadow, atX: 0, y: height - 1))
    }

    func testHeaderIsDrawnInThePixelFont() {
        let view = view()
        let image = image(view)
        let letters = PixelFont.pixels("MAIS USADOS")
        let y = view.top(of: 0) + (PixelMenuView.headerHeight - PixelFont.rows) / 2
        XCTAssertFalse(letters.isEmpty)
        for pixel in letters {
            XCTAssertTrue(image.isColor(theme.dim, atX: PixelMenuView.textX + pixel.x, y: y + pixel.y),
                          "letra em (\(pixel.x), \(pixel.y))")
        }
    }

    func testHighlightedRowHasBackgroundAndAccentBar() {
        let view = view()
        let top = view.top(of: 1), right = faceWidth(view) - PixelMenuView.border - 1
        let plain = image(view)
        XCTAssertEqual(plain.count(theme.accent), 0)
        XCTAssertTrue(plain.isColor(theme.bg2, atX: right, y: top))

        view.highlighted = 1
        let image = image(view)
        XCTAssertEqual(image.count(theme.accent), PixelMenuView.barWidth * PixelMenuView.rowHeight)
        XCTAssertTrue(image.isColor(theme.accent, atX: PixelMenuView.border, y: top), "barra à esquerda")
        XCTAssertTrue(image.isColor(theme.bg4, atX: right, y: top), "fundo até a moldura")
        XCTAssertTrue(image.isColor(theme.bg4, atX: right, y: top + PixelMenuView.rowHeight - 1))
        XCTAssertTrue(image.isColor(theme.bg2, atX: right, y: view.top(of: 2)), "só a linha escolhida")
    }

    func testSubmenuRowShowsThePixelArrow() {
        let view = view()
        let image = image(view)
        let x = faceWidth(view) - PixelMenuView.arrowInset
        let y = view.top(of: 4) + (PixelMenuView.rowHeight - PixelFont.rows) / 2
        for pixel in PixelFont.pixels(">") {
            XCTAssertTrue(image.isColor(theme.dim, atX: x + pixel.x, y: y + pixel.y), "seta em (\(pixel.x), \(pixel.y))")
        }
        let plainY = view.top(of: 1) + (PixelMenuView.rowHeight - PixelFont.rows) / 2
        XCTAssertEqual(image.count(theme.dim, x: x, y: plainY, width: PixelFont.columns, height: PixelFont.rows), 0,
                       "linha sem submenu não tem seta")
    }

    func testSwatchIsDrawnInTheItemColorAndIndentsEveryTitle() {
        let view = view(swatch: magenta)
        let image = image(view)
        let side = PixelMenuView.swatchSide
        let y = view.top(of: 4) + (PixelMenuView.rowHeight - side) / 2
        XCTAssertEqual(image.count(magenta), side * side)
        XCTAssertEqual(image.count(magenta, x: PixelMenuView.textX, y: y, width: side, height: side), side * side)
        XCTAssertEqual(view.titleX, PixelMenuView.textX + side + PixelMenuView.swatchGap)
        XCTAssertEqual(self.view().titleX, PixelMenuView.textX, "sem quadradinho, o título não recua")
    }

    func testIndentedRowMovesItsTitleRight() {
        let deep = item("Natutec")
        deep.indentationLevel = 1
        let view = PixelMenuView(items: [item("Natutec"), deep])
        view.frame = NSRect(x: 0, y: 0, width: view.fittingWidth, height: view.fittingHeight)
        let image = image(view)
        let x = view.titleX, indent = PixelMenuView.indent, height = PixelMenuView.rowHeight
        XCTAssertGreaterThan(image.count(theme.ink, x: x, y: view.top(of: 0), width: indent, height: height), 0)
        XCTAssertEqual(image.count(theme.ink, x: 0, y: view.top(of: 1), width: x + indent, height: height), 0,
                       "a linha recuada começa um recuo depois")
        XCTAssertGreaterThan(image.count(theme.ink, x: x + indent, y: view.top(of: 1), width: indent, height: height), 0)

        let long = String(repeating: "m", count: 30)
        let deepLong = item(long)
        deepLong.indentationLevel = 1
        XCTAssertEqual(PixelMenuView(items: [deepLong]).fittingWidth,
                       PixelMenuView(items: [item(long)]).fittingWidth + indent, "o recuo entra na largura")
    }

    func testSeparatorIsALineAcrossTheMenu() {
        let view = view()
        let image = image(view)
        let y = view.top(of: 3) + (PixelMenuView.separatorHeight - PixelMenuView.border) / 2
        let inner = faceWidth(view) - 2 * PixelMenuView.border
        XCTAssertEqual(image.count(theme.shadow, x: PixelMenuView.border, y: y, width: inner, height: PixelMenuView.border),
                       (faceWidth(view) - 2 * PixelMenuView.textX) * PixelMenuView.border)
    }

    // MARK: rolagem

    func testScrolledMenuShowsTheRowsBelow() {
        let view = tallView()
        let visible = 5 * PixelMenuView.rowHeight
        XCTAssertEqual(view.visibleHeight, visible)
        XCTAssertEqual(view.row(atY: PixelMenuView.inset), 0)

        view.reveal(row: 9)
        XCTAssertEqual(view.offset, 5 * PixelMenuView.rowHeight, "desce só até a linha aparecer inteira")
        XCTAssertEqual(view.row(atY: PixelMenuView.inset), 5)
        XCTAssertEqual(view.top(of: 9), PixelMenuView.inset + 4 * PixelMenuView.rowHeight)
        view.highlighted = 9
        XCTAssertTrue(image(view).isColor(theme.accent, atX: PixelMenuView.border, y: PixelMenuView.inset + visible - 1),
                      "a linha escolhida é a última à vista")
    }

    func testScrollStopsAtTheEnds() {
        let view = tallView()
        view.scroll(by: 10_000)
        XCTAssertEqual(view.offset, 15 * PixelMenuView.rowHeight)
        view.scroll(by: -10_000)
        XCTAssertEqual(view.offset, 0)
    }

    func testMenuThatFitsDoesNotScroll() {
        let view = view()
        view.scroll(by: 50)
        XCTAssertEqual(view.offset, 0)
    }

    func testMarksShowWhereThereAreMoreRows() {
        let view = tallView()
        XCTAssertEqual(image(view).count(theme.accent), PixelMenuView.markPixels, "há mais abaixo")
        view.scroll(by: PixelMenuView.rowHeight)
        XCTAssertEqual(image(view).count(theme.accent), 2 * PixelMenuView.markPixels, "acima e abaixo")
        view.scroll(by: 10_000)
        XCTAssertEqual(image(view).count(theme.accent), PixelMenuView.markPixels, "só acima")
        XCTAssertEqual(image(self.view()).count(theme.accent), 0, "menu que cabe não tem marca")
    }

    // MARK: mouse

    func testMouseReportsTheRowUnderIt() {
        let view = view()
        var hovered: [Int?] = []
        view.onHover = { hovered.append($0) }
        view.mouseMoved(with: mouse(view, y: view.top(of: 1) + 3))
        view.mouseMoved(with: mouse(view, y: view.top(of: 0) + 3))
        view.mouseMoved(with: mouse(view, y: view.top(of: 4) + 3))
        view.mouseExited(with: mouse(view, y: 0))
        XCTAssertEqual(hovered, [1, nil, 4, nil])
    }

    func testTheShadowBesideTheRowsIsNotARow() {
        let view = view()
        var hovered: [Int?] = []
        var chosen: [Int] = []
        view.onHover = { hovered.append($0) }
        view.onChoose = { chosen.append($0) }
        let y = view.top(of: 2) + 3
        let inShadow = Int(view.bounds.width) - 1
        view.mouseMoved(with: mouse(view, x: inShadow - PixelMenuView.shadow, y: y))
        view.mouseMoved(with: mouse(view, x: inShadow, y: y))
        view.mouseUp(with: mouse(view, x: inShadow, y: y, type: .leftMouseUp))
        XCTAssertEqual(hovered, [2, nil])
        XCTAssertEqual(chosen, [])
    }

    func testPressingARowHighlightsItBeforeTheRelease() {
        let view = view()
        var hovered: [Int?] = []
        view.onHover = { hovered.append($0) }
        view.mouseDown(with: mouse(view, y: view.top(of: 2) + 3, type: .leftMouseDown))
        XCTAssertEqual(hovered, [2])
    }

    func testReleasingTheMouseOnARowChoosesIt() {
        let view = view()
        var chosen: [Int] = []
        view.onChoose = { chosen.append($0) }
        view.mouseUp(with: mouse(view, y: view.top(of: 2) + 3, type: .leftMouseUp))
        view.mouseUp(with: mouse(view, y: view.top(of: 0) + 3, type: .leftMouseUp))
        XCTAssertEqual(chosen, [2], "cabeçalho não é escolhido")
    }

    func testHighlightedRowLendsItsTooltip() {
        let view = view()
        view.items[1].toolTip = "~/Projetos/acme/api"
        view.highlighted = 1
        XCTAssertEqual(view.toolTip, "~/Projetos/acme/api")
        view.highlighted = 2
        XCTAssertNil(view.toolTip)
    }
}
