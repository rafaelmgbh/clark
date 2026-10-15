import AppKit
import ClarkCore
import XCTest
@testable import Clark

private final class Picker: NSObject {
    private(set) var picked: [String] = []
    @objc func pick(_ sender: NSMenuItem) { picked.append(sender.title) }
}

/// O menu em cascata: os níveis que abrem e fecham com o mouse e com o teclado.
final class PixelMenuTests: XCTestCase {
    private var menu: PixelMenu!
    private var picker: Picker!
    private var shown: [NSPanel] = []
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    // Linhas do primeiro nível de `tree`.
    private let api = 1, acme = 3, beta = 4, other = 5

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        picker = Picker()
        shown = []
        menu = PixelMenu()
        // Nenhum painel vai para a tela.
        menu.present = { [unowned self] panel, _ in self.shown.append(panel) }
        menu.bounds = { [screen] _ in screen }
    }

    override func tearDown() {
        menu.close()
        menu = nil
        picker = nil
        super.tearDown()
    }

    private func item(_ title: String, _ children: [NSMenuItem]? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: children == nil ? #selector(Picker.pick(_:)) : nil,
                              keyEquivalent: "")
        item.target = picker
        if let children {
            let submenu = NSMenu(title: title)
            children.forEach(submenu.addItem)
            item.submenu = submenu
        }
        return item
    }

    /// Cabeçalho, `Api`, separador, `ACME >` (`Loja`, `Clientes >` (`Portal`)), `BETA >` (`Site`), `Outra`.
    private func tree() -> NSMenu {
        let tree = NSMenu(title: "Projeto")
        [.sectionHeader(title: "Mais usados"), item("Api"), .separator(),
         item("ACME", [item("Loja"), item("Clientes", [item("Portal")])]), item("BETA", [item("Site")]),
         item("Outra")].forEach(tree.addItem)
        return tree
    }

    private func open() {
        menu.show(tree(), at: NSPoint(x: 100, y: 800), over: nil)
    }

    private var titles: [[String]] { menu.levels.map { $0.view.items.map(\.title) } }
    private var highlights: [Int?] { menu.levels.map(\.view.highlighted) }

    private func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                         keyCode: code)!
    }

    // MARK: abrir e fechar

    func testShowOpensOneLevelWithTheRowsOfTheMenu() {
        XCTAssertFalse(menu.isOpen)
        open()
        XCTAssertTrue(menu.isOpen)
        XCTAssertEqual(titles, [["Mais usados", "Api", "", "ACME", "BETA", "Outra"]])
        XCTAssertEqual(shown.count, 1)
        let level = menu.levels[0]
        XCTAssertTrue(shown[0] === level.panel)
        XCTAssertEqual(level.panel.frame, NSRect(x: 100, y: CGFloat(800 - level.view.fittingHeight),
                                                 width: CGFloat(level.view.fittingWidth),
                                                 height: CGFloat(level.view.fittingHeight)),
                       "o canto de cima à esquerda fica no ponto pedido")
        XCTAssertFalse(level.panel.canBecomeKey, "o terminal continua com o foco")
        XCTAssertFalse(level.panel.isOpaque, "o canto ao lado da sombra é vazado")
        XCTAssertFalse(level.panel.hasShadow, "a sombra é a desenhada")
    }

    func testCloseRemovesEveryLevel() {
        open()
        menu.hover(acme, level: 0)
        XCTAssertEqual(menu.levels.count, 2)
        menu.close()
        XCTAssertFalse(menu.isOpen)
        XCTAssertTrue(menu.levels.isEmpty)
        menu.close()
    }

    func testShowingAgainReplacesTheOpenMenu() {
        open()
        menu.hover(acme, level: 0)
        open()
        XCTAssertEqual(menu.levels.count, 1)
        XCTAssertEqual(highlights, [nil])
    }

    func testLevelsUseTheThemeOfTheMenu() {
        menu.theme = .swapped
        open()
        menu.hover(acme, level: 0)
        XCTAssertEqual(menu.levels.map(\.view.theme.name), [Theme.swapped.name, Theme.swapped.name])
    }

    // MARK: mouse

    func testHoveringASubmenuRowOpensItBeside() {
        open()
        menu.hover(acme, level: 0)
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[1], ["Loja", "Clientes"])
        XCTAssertEqual(highlights, [acme, nil])
        let parent = menu.levels[0], child = menu.levels[1]
        XCTAssertEqual(child.panel.frame.minX,
                       parent.panel.frame.maxX - CGFloat(PixelMenuView.shadow + PixelMenuView.border),
                       "as molduras se encostam")
        let rowTop = parent.panel.frame.maxY - CGFloat(parent.view.top(of: acme))
        XCTAssertEqual(child.panel.frame.maxY - CGFloat(PixelMenuView.inset), rowTop,
                       "a primeira linha do submenu fica na altura da linha que o abriu")
    }

    func testHoveringAPlainRowDoesNotOpenAnything() {
        open()
        menu.hover(api, level: 0)
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(highlights, [api])
    }

    func testLeavingForAPlainRowClosesTheSubmenuOnlyAfterAPause() {
        open()
        menu.hover(acme, level: 0)
        menu.hover(other, level: 0)
        XCTAssertEqual(highlights[0], other, "o destaque acompanha o cursor")
        XCTAssertEqual(titles.count, 2, "o submenu espera: o cursor pode estar só atravessando")
        menu.settleHover()
        XCTAssertEqual(titles.count, 1)
    }

    func testReachingTheSubmenuAcrossOtherRowsKeepsItOpen() {
        open()
        menu.hover(acme, level: 0)
        menu.hover(beta, level: 0)
        menu.hover(nil, level: 0)
        menu.hover(1, level: 1)
        menu.settleHover()
        XCTAssertEqual(titles.count, 3, "chegou em `Clientes`, que abre o dela")
        XCTAssertEqual(titles[1], ["Loja", "Clientes"])
        XCTAssertEqual(highlights, [acme, 1, nil], "a linha que abriu o submenu volta a ficar destacada")
    }

    func testStoppingOnAnotherSubmenuRowSwitchesToIt() {
        open()
        menu.hover(acme, level: 0)
        menu.hover(beta, level: 0)
        XCTAssertEqual(titles[1], ["Loja", "Clientes"], "antes da pausa o submenu aberto é o mesmo")
        menu.settleHover()
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[1], ["Site"])
    }

    func testEnteringTheSubmenuStraightFromAnotherRowKeepsItOpen() {
        open()
        menu.hover(acme, level: 0)
        menu.hover(beta, level: 0)
        // O painel do submenu cobre a borda do nível de cima: o cursor entra nele sem o nível de cima
        // saber que saiu.
        menu.hover(0, level: 1)
        XCTAssertEqual(highlights, [acme, 0])
        menu.settleHover()
        XCTAssertEqual(titles[1], ["Loja", "Clientes"], "a pausa que começou em `BETA` não troca o submenu")
    }

    func testLeavingTheMenuKeepsTheOpenSubmenu() {
        open()
        menu.hover(acme, level: 0)
        menu.hover(0, level: 1)
        menu.hover(nil, level: 1)
        menu.settleHover()
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(highlights, [acme, nil])
    }

    func testLeavingALevelWithNothingOpenClearsTheHighlight() {
        open()
        menu.hover(api, level: 0)
        menu.hover(nil, level: 0)
        XCTAssertEqual(highlights, [nil])
    }

    func testChoosingARowClosesTheMenuAndSendsItsAction() {
        open()
        menu.choose(api, level: 0)
        XCTAssertEqual(picker.picked, ["Api"])
        XCTAssertFalse(menu.isOpen)
    }

    func testChoosingARowOfASubmenu() {
        open()
        menu.hover(acme, level: 0)
        menu.choose(0, level: 1)
        XCTAssertEqual(picker.picked, ["Loja"])
        XCTAssertFalse(menu.isOpen)
    }

    func testClickingASubmenuRowOpensItAtOnce() {
        open()
        menu.hover(acme, level: 0)
        menu.choose(beta, level: 0)
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[1], ["Site"])
        XCTAssertEqual(highlights[0], beta)
        XCTAssertEqual(picker.picked, [])
    }

    /// `tree`, com uma ação também na linha `ACME`, como a empresa que abre a pasta dela.
    private func openWithActionOnAcme() {
        let tree = tree()
        tree.items[acme].action = #selector(Picker.pick(_:))
        menu.show(tree, at: NSPoint(x: 100, y: 800), over: nil)
    }

    func testClickingASubmenuRowThatHasAnActionSendsIt() {
        openWithActionOnAcme()
        menu.hover(acme, level: 0)
        XCTAssertEqual(titles.count, 2, "o cursor continua abrindo o submenu")
        menu.choose(acme, level: 0)
        XCTAssertEqual(picker.picked, ["ACME"])
        XCTAssertFalse(menu.isOpen)
    }

    func testEnterSendsTheActionOfASubmenuRowAndRightStillEntersIt() {
        openWithActionOnAcme()
        menu.keyDown(.down)
        menu.keyDown(.down)
        menu.keyDown(.right)
        XCTAssertEqual(highlights, [acme, 0], "a seta para a direita entra no submenu")
        XCTAssertEqual(picker.picked, [])
        menu.keyDown(.left)
        menu.keyDown(.enter)
        XCTAssertEqual(picker.picked, ["ACME"])
        XCTAssertFalse(menu.isOpen)
    }

    func testShowCanOpenAlreadyInsideASubmenu() {
        let tree = tree()
        menu.show(tree, at: NSPoint(x: 100, y: 800), over: nil, entering: tree.items[acme])
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(highlights, [acme, 0], "pronto para as setas, como depois de um →")
        menu.keyDown(.enter)
        XCTAssertEqual(picker.picked, ["Loja"])
    }

    func testShowEnteringARowWithoutSubmenuOnlyOpensTheMenu() {
        let tree = tree()
        menu.show(tree, at: NSPoint(x: 100, y: 800), over: nil, entering: tree.items[api])
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(highlights, [nil])
    }

    func testTheViewsReportToTheMenu() {
        open()
        menu.levels[0].view.onHover?(acme)
        XCTAssertEqual(titles.count, 2)
        menu.levels[1].view.onChoose?(0)
        XCTAssertEqual(picker.picked, ["Loja"])
    }

    // MARK: teclado

    func testArrowsWalkTheRowsAndOpenSubmenus() {
        open()
        XCTAssertTrue(menu.keyDown(.down))
        XCTAssertEqual(highlights, [api], "o cabeçalho é pulado")
        menu.keyDown(.down)
        XCTAssertEqual(highlights, [acme], "o separador é pulado")
        XCTAssertEqual(titles.count, 1, "com o teclado o submenu só abre na seta para a direita")
        menu.keyDown(.right)
        XCTAssertEqual(highlights, [acme, 0])
        menu.keyDown(.down)
        menu.keyDown(.right)
        XCTAssertEqual(highlights, [acme, 1, 0])
        XCTAssertEqual(titles[2], ["Portal"])
        menu.keyDown(.enter)
        XCTAssertEqual(picker.picked, ["Portal"])
        XCTAssertFalse(menu.isOpen)
    }

    func testUpFromNothingStartsAtTheLastRow() {
        open()
        menu.keyDown(.up)
        XCTAssertEqual(highlights, [other])
    }

    func testEnterOnASubmenuRowOpensIt() {
        open()
        menu.keyDown(.down)
        menu.keyDown(.down)
        menu.keyDown(.enter)
        XCTAssertEqual(highlights, [acme, 0])
        XCTAssertEqual(picker.picked, [])
    }

    func testRightOnAPlainRowDoesNothing() {
        open()
        menu.keyDown(.down)
        menu.keyDown(.right)
        XCTAssertEqual(highlights, [api])
        XCTAssertEqual(picker.picked, [])
        XCTAssertTrue(menu.isOpen)
    }

    func testLeftClosesTheSubmenuAndStaysOnTheRowThatOpenedIt() {
        open()
        menu.keyDown(.down)
        menu.keyDown(.down)
        menu.keyDown(.right)
        menu.keyDown(.left)
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(highlights, [acme])
        menu.keyDown(.left)
        XCTAssertTrue(menu.isOpen, "no primeiro nível a seta para a esquerda não fecha o menu")
    }

    func testArrowsOnTheParentCloseTheSubmenuTheMouseOpened() {
        open()
        menu.hover(acme, level: 0)
        menu.keyDown(.down)
        XCTAssertEqual(highlights, [beta])
        XCTAssertEqual(titles.count, 1)
        menu.settleHover()
        XCTAssertEqual(titles.count, 1, "a pausa do mouse não reabre nada depois da tecla")
    }

    func testRightEntersTheSubmenuTheMouseOpened() {
        open()
        menu.hover(acme, level: 0)
        menu.keyDown(.right)
        XCTAssertEqual(highlights, [acme, 0])
    }

    func testEscapeClosesEverything() {
        open()
        menu.keyDown(.down)
        menu.keyDown(.down)
        menu.keyDown(.right)
        menu.keyDown(.escape)
        XCTAssertFalse(menu.isOpen)
    }

    func testClosedMenuIgnoresKeys() {
        XCTAssertFalse(menu.keyDown(.down))
        XCTAssertFalse(menu.isOpen)
    }

    // MARK: eventos do app

    func testOpenMenuTakesEveryKey() {
        let down = key(125)
        XCTAssertTrue(menu.intercept(down) === down, "menu fechado não mexe nos eventos")
        open()
        XCTAssertNil(menu.intercept(key(125)))
        XCTAssertEqual(highlights, [api])
        XCTAssertNil(menu.intercept(key(126)))
        XCTAssertEqual(highlights, [other], "para cima, do começo, dá a volta")
        XCTAssertNil(menu.intercept(key(0)), "a letra não chega ao terminal")
        XCTAssertTrue(menu.isOpen)
        XCTAssertNil(menu.intercept(key(53)))
        XCTAssertFalse(menu.isOpen, "esc fecha")
    }

    func testReturnSpaceAndKeypadEnterChoose() {
        for code: UInt16 in [36, 76, 49] {
            open()
            menu.keyDown(.down)
            XCTAssertNil(menu.intercept(key(code)))
            XCTAssertFalse(menu.isOpen, "tecla \(code)")
        }
        XCTAssertEqual(picker.picked, ["Api", "Api", "Api"])
    }

    func testShortcutClosesTheMenu() {
        open()
        XCTAssertNil(menu.intercept(key(2, modifiers: .command)), "o ⌘D que abriu o menu também o fecha")
        XCTAssertFalse(menu.isOpen)
    }

    func testClickOutsideClosesTheMenuAndIsSwallowed() {
        open()
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        XCTAssertNil(menu.intercept(click), "clicar de novo no + AGENT só fecha o menu")
        XCTAssertFalse(menu.isOpen)
        XCTAssertTrue(menu.intercept(click) === click)
    }

    func testMenuClosesWhenTheAppLosesFocus() {
        open()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(menu.isOpen)
    }

    // MARK: lugar na tela

    func testRootFrameStaysInsideTheScreen() {
        let size = NSSize(width: 200, height: 300)
        XCTAssertEqual(PixelMenu.rootFrame(size: size, topLeft: NSPoint(x: 100, y: 800), within: screen),
                       NSRect(x: 100, y: 500, width: 200, height: 300))
        XCTAssertEqual(PixelMenu.rootFrame(size: size, topLeft: NSPoint(x: 1400, y: 800), within: screen).minX, 1240,
                       "sem espaço à direita, encosta na borda")
        XCTAssertEqual(PixelMenu.rootFrame(size: size, topLeft: NSPoint(x: 100, y: 200), within: screen),
                       NSRect(x: 100, y: 0, width: 200, height: 200), "o que não cabe abaixo rola")
    }

    func testSubmenuOpensToTheRightAlignedWithItsRow() {
        let parent = NSRect(x: 100, y: 500, width: 203, height: 303)
        let frame = PixelMenu.submenuFrame(size: NSSize(width: 183, height: 103), beside: parent, rowTop: 700,
                                           within: screen)
        XCTAssertEqual(frame, NSRect(x: 298, y: 603, width: 183, height: 103))
    }

    func testSubmenuFlipsToTheLeftWithoutRoomOnTheRight() {
        let parent = NSRect(x: 1200, y: 500, width: 203, height: 303)
        let frame = PixelMenu.submenuFrame(size: NSSize(width: 183, height: 103), beside: parent, rowTop: 700,
                                           within: screen)
        XCTAssertEqual(frame.maxX - CGFloat(PixelMenuView.shadow), parent.minX + CGFloat(PixelMenuView.border),
                       "a face encosta na moldura do pai")
        XCTAssertEqual(frame.maxY, 706)
    }

    func testSubmenuIsPushedUpToFitAndScrollsWhenTallerThanTheScreen() {
        let parent = NSRect(x: 100, y: 0, width: 203, height: 303)
        let low = PixelMenu.submenuFrame(size: NSSize(width: 183, height: 400), beside: parent, rowTop: 100,
                                         within: screen)
        XCTAssertEqual(low.minY, 0, "sobe até caber")
        XCTAssertEqual(low.height, 400)
        let tall = PixelMenu.submenuFrame(size: NSSize(width: 183, height: 2000), beside: parent, rowTop: 100,
                                          within: screen)
        XCTAssertEqual(tall.minY, 0)
        XCTAssertEqual(tall.height, 900, "mais alto que a tela: fica do tamanho dela")
    }
}
