import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// As views desenhadas à mão, conferidas pixel a pixel num bitmap.
final class PixelViewsTests: XCTestCase {
    private let theme = Theme.dark
    /// Cor que não existe no tema: o que aparecer nela veio do agente.
    private let magenta = RGB(r: 1, g: 0, b: 1)

    private func snapshot(_ state: AgentState = .idle, name: String = "AGENT 1", company: String = "ACME",
                          preview: [String] = []) -> AgentSnapshot {
        AgentSnapshot(name: name, company: company, color: magenta, path: "~/Projetos/acme", state: state,
                      preview: preview)
    }

    /// Clique no ponto (x, y) da view, contado de cima para baixo. O evento leva a coordenada
    /// de janela, que cresce para cima.
    private func click(_ view: NSView, x: CGFloat, y: CGFloat, count: Int = 1, up: Bool = false) -> NSEvent {
        let location = NSPoint(x: x, y: view.bounds.height - y)
        let event = NSEvent.mouseEvent(with: up ? .leftMouseUp : .leftMouseDown, location: location,
                                       modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                       eventNumber: 0, clickCount: count, pressure: 1)
        return event!
    }

    // MARK: rótulos

    func testStateLabelAnimatesOnlyBootAndWorking() {
        XCTAssertEqual(StateLabel.text(.working, time: 0), "WORKING")
        XCTAssertEqual(StateLabel.text(.working, time: 0.25), "WORKING.")
        XCTAssertEqual(StateLabel.text(.working, time: 0.75), "WORKING...")
        XCTAssertEqual(StateLabel.text(.working, time: 1), "WORKING")
        XCTAssertEqual(StateLabel.text(.boot, time: 0.5), "BOOT..")
        XCTAssertEqual(StateLabel.text(.idle, time: 0.75), "IDLE")
        XCTAssertEqual(StateLabel.text(.done, time: 0.75), "DONE!")
        XCTAssertEqual(StateLabel.text(.exited, time: 0.75), "GAME OVER")
    }

    func testStateColors() {
        XCTAssertEqual(StateLabel.color(.working, theme: theme), theme.green)
        XCTAssertEqual(StateLabel.color(.done, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.boot, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.idle, theme: theme), theme.dim)
        XCTAssertEqual(StateLabel.color(.exited, theme: theme), theme.red)
        XCTAssertFalse(StateLabel.isAnimated(.idle))
        XCTAssertFalse(StateLabel.isAnimated(.exited))
        XCTAssertTrue(StateLabel.isAnimated(.done))
    }

    func testEveryLabelFitsThePixelFont() {
        // A fonte pixel só tem ASCII maiúsculo: um texto fora dela sairia como "?".
        let labels = AgentState.allCases.map { StateLabel.text($0, time: 0.75) }
            + ["CLARK", "AGENTS 16", "WORKING 16", "DONE 16", "IDLE 16", "GAME OVER 16", "EM FOCO", "AGENTES 16",
               "SEM PERMISSOES", "NENHUM AGENTE ONLINE", "LENDO O AMBIENTE DO SHELL", "PRESS START  -  CMD+N"]
        for label in labels {
            XCTAssertEqual(PixelFont.normalize(label), label, label)
            XCTAssertFalse(PixelFont.fit(label, scale: 1, width: 10_000).contains("?"), label)
        }
    }

    // MARK: botão

    func testButtonWidthFollowsTheTitle() {
        XCTAssertLessThan(PixelButton(title: "A").fittingWidth, PixelButton(title: "ABCDEF").fittingWidth)
        XCTAssertLessThan(PixelButton(title: "ABC", style: .mini).fittingWidth, PixelButton(title: "ABC").fittingWidth)
    }

    func testButtonFacesAndHardShadow() {
        let normal = RenderedImage(PixelButton(title: "OK"), width: 80, height: 27)
        XCTAssertTrue(normal.isColor(theme.shadow, atX: 0, y: 0), "moldura")
        XCTAssertTrue(normal.isColor(theme.bg3, atX: 3, y: 3), "face")
        XCTAssertTrue(normal.isColor(theme.shadow, atX: 79, y: 26), "sombra dura embaixo à direita")

        let primary = RenderedImage(PixelButton(title: "OK", style: .primary), width: 80, height: 27)
        XCTAssertTrue(primary.isColor(theme.accent, atX: 3, y: 3))

        let mini = RenderedImage(PixelButton(title: "X", style: .miniClose), width: 30, height: 30)
        XCTAssertTrue(mini.isColor(theme.bg2, atX: 1, y: 1))
    }

    func testButtonClicksOnlyWhenReleasedInside() {
        var clicks = 0
        let button = PixelButton(title: "OK") { clicks += 1 }
        button.frame = NSRect(x: 0, y: 0, width: 80, height: 27)
        button.mouseDown(with: click(button, x: 5, y: 5))
        XCTAssertTrue(button.isPressed)
        button.mouseUp(with: click(button, x: 5, y: 5, up: true))
        XCTAssertEqual(clicks, 1)

        button.mouseDown(with: click(button, x: 5, y: 5))
        button.mouseUp(with: click(button, x: 500, y: 500, up: true))
        XCTAssertEqual(clicks, 1, "soltar fora do botão cancela")
        XCTAssertFalse(button.isPressed)
        XCTAssertFalse(button.acceptsFirstResponder, "o botão não tira o teclado do terminal")
    }

    // MARK: cabeçalho

    private func pillOrigin(width: Int) -> (x: Int, y: Int) {
        (width - (PixelFont.textWidth("WORKING...", scale: 2) + 16) - 6, 5)
    }

    func testHeaderShowsTheAgentColorAndTheStatePill() {
        let header = AgentHeaderView(snapshot: snapshot(.working))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        let pill = pillOrigin(width: 600)
        XCTAssertTrue(image.isColor(theme.bg2, atX: 1, y: 1))
        XCTAssertTrue(image.isColor(magenta, atX: 15, y: 15), "quadrado na cor do agente")
        XCTAssertTrue(image.isColor(theme.green, atX: pill.x, y: pill.y), "moldura da pílula em WORKING")
        XCTAssertGreaterThan(image.count(theme.ink, x: 30, y: 8, width: 200, height: 14), 0, "nome")

        header.snapshot = snapshot(.exited)
        let exited = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(exited.isColor(theme.red, atX: pill.x, y: pill.y))
    }

    func testHeaderDonePillBlinks() {
        let header = AgentHeaderView(snapshot: snapshot(.done))
        let pill = pillOrigin(width: 600)
        header.time = 0
        let filled = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(filled.isColor(theme.yellow, atX: pill.x + 3, y: pill.y + 3), "pílula cheia")

        header.time = 0.34
        let hollow = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(hollow.isColor(theme.yellow, atX: pill.x, y: pill.y), "só a moldura")
        XCTAssertFalse(hollow.isColor(theme.yellow, atX: pill.x + 3, y: pill.y + 3))
    }

    func testHeaderShowsTheCompanyWhenThereIsRoom() {
        let with = RenderedImage(AgentHeaderView(snapshot: snapshot(company: "ACME")), width: 600,
                                 height: AgentHeaderView.height)
        let without = RenderedImage(AgentHeaderView(snapshot: snapshot(company: "")), width: 600,
                                    height: AgentHeaderView.height)
        // Depois do quadrado (x < 30) a cor do agente só aparece no nome da empresa.
        XCTAssertGreaterThan(with.count(magenta, x: 30), 0)
        XCTAssertEqual(without.count(magenta, x: 30), 0)

        let narrow = RenderedImage(AgentHeaderView(snapshot: snapshot(name: "NOME BEM COMPRIDO 123", company: "ACME")),
                                   width: 200, height: AgentHeaderView.height)
        XCTAssertEqual(narrow.count(magenta, x: 30), 0, "sem espaço, a empresa some e o estado fica")
        XCTAssertGreaterThan(narrow.count(theme.dim, x: 100), 0, "pílula do estado")
    }

    func testHeaderClicks() {
        var clicks = 0, doubles = 0
        let header = AgentHeaderView(snapshot: snapshot())
        header.onClick = { clicks += 1 }
        header.onDoubleClick = { doubles += 1 }
        header.mouseDown(with: click(header, x: 5, y: 5))
        header.mouseDown(with: click(header, x: 5, y: 5, count: 2))
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(doubles, 1)
    }

    // MARK: card

    private let cardWidth = 304

    private func render(_ card: AgentCardView) -> RenderedImage {
        RenderedImage(card, width: cardWidth, height: AgentCardView.height)
    }

    func testCardStripeAndActiveEdge() {
        let card = AgentCardView(snapshot: snapshot())
        let idle = render(card)
        XCTAssertTrue(idle.isColor(magenta, atX: 1, y: 40), "faixa na cor do agente")
        XCTAssertFalse(idle.isColor(magenta, atX: 5, y: 40))
        XCTAssertTrue(idle.isColor(theme.bg2, atX: 100, y: 0), "sem moldura fora do foco")

        card.isActive = true
        let active = render(card)
        XCTAssertTrue(active.isColor(magenta, atX: 5, y: 40), "faixa mais larga no agente em foco")
        XCTAssertTrue(active.isColor(theme.accent, atX: 100, y: 2), "moldura de 3 px")
        XCTAssertTrue(active.isColor(theme.accent, atX: 100, y: AgentCardView.height - 1))
        XCTAssertTrue(active.isColor(theme.accent, atX: cardWidth - 1, y: 40))
        let tagWidth = PixelFont.textWidth("EM FOCO", scale: 1)
        XCTAssertTrue(active.isColor(theme.accent, atX: cardWidth - tagWidth - 13, y: 7), "etiqueta EM FOCO")
        XCTAssertFalse(idle.isColor(theme.accent, atX: cardWidth - tagWidth - 13, y: 7))
    }

    func testCardEdgeFollowsTheState() {
        let card = AgentCardView(snapshot: snapshot(.exited))
        let exited = render(card)
        XCTAssertTrue(exited.isColor(theme.red, atX: 100, y: 1))
        XCTAssertFalse(exited.isColor(theme.red, atX: 100, y: 2), "moldura de 2 px")

        card.snapshot = snapshot(.done)
        card.time = 0
        XCTAssertTrue(render(card).isColor(theme.yellow, atX: 100, y: 0))
        card.time = 0.34
        XCTAssertFalse(render(card).isColor(theme.yellow, atX: 100, y: 0), "DONE pisca")
    }

    func testCardShortcutNumberOnlyUpToNine() {
        let card = AgentCardView(snapshot: snapshot())
        card.index = 3
        XCTAssertGreaterThan(render(card).count(theme.dim, x: cardWidth - 16, y: 10, width: 6, height: 7), 0)
        card.index = 12
        XCTAssertEqual(render(card).count(theme.dim, x: cardWidth - 16, y: 10, width: 6, height: 7), 0)
    }

    func testCardCloseButtonAppearsOnHover() {
        var selected = 0, closed = 0
        let card = AgentCardView(snapshot: snapshot())
        card.frame = NSRect(x: 0, y: 0, width: cardWidth, height: AgentCardView.height)
        card.onSelect = { selected += 1 }
        card.onClose = { closed += 1 }
        let close = AgentCardView.closeRect(width: cardWidth)
        XCTAssertFalse(render(card).isColor(theme.red, atX: Int(close.minX) + 1, y: Int(close.minY) + 1))

        // Sem o mouse em cima não há botão: o clique no canto seleciona.
        card.mouseDown(with: click(card, x: close.midX, y: close.midY))
        XCTAssertEqual([selected, closed], [1, 0])

        card.setHovering(true)
        XCTAssertTrue(render(card).isColor(theme.red, atX: Int(close.minX) + 1, y: Int(close.minY) + 1))
        card.mouseDown(with: click(card, x: close.midX, y: close.midY))
        XCTAssertEqual([selected, closed], [1, 1])
        card.mouseDown(with: click(card, x: 20, y: 40))
        XCTAssertEqual([selected, closed], [2, 1])
    }

    func testCardPreviewChangesTheDrawing() {
        let empty = render(AgentCardView(snapshot: snapshot()))
        let filled = render(AgentCardView(snapshot: snapshot(preview: ["compilando o projeto", "42 testes verdes"])))
        let background = theme.bg2
        XCTAssertLessThan(filled.count(background, y: 44, height: 36), empty.count(background, y: 44, height: 36))
    }

    // MARK: barra superior

    private let statsY = (46 - 14) / 2
    private var firstStatX: Int { 10 + PixelFont.textWidth("CLARK", scale: 3) + 4 + 10 + 16 }

    func testTopBarLogoAndBottomEdge() {
        let image = RenderedImage(TopBarView(), width: 1200, height: TopBarView.height)
        XCTAssertTrue(image.isColor(theme.bg2, atX: 2, y: 2))
        XCTAssertTrue(image.isColor(theme.bg2, atX: 5, y: 45))
        for y in 46..<49 { XCTAssertTrue(image.isColor(theme.shadow, atX: 5, y: y), "borda inferior, linha \(y)") }
        XCTAssertGreaterThan(image.count(theme.accent, x: 10, y: 12, width: PixelFont.textWidth("CLARK", scale: 3),
                                         height: 21), 0)
    }

    func testTopBarStatsColors() {
        let bar = TopBarView()
        let zero = RenderedImage(bar, width: 1200, height: TopBarView.height)
        XCTAssertTrue(zero.isColor(theme.dim, atX: firstStatX + 1, y: statsY + 5), "contagem zero fica apagada")
        XCTAssertEqual(zero.count(theme.red), 0, "GAME OVER só aparece quando há algum")

        bar.stats = AgentStats(states: [.working, .working, .done, .exited])
        let image = RenderedImage(bar, width: 1200, height: TopBarView.height)
        let working = firstStatX + PixelFont.textWidth("AGENTS 4", scale: 2) + 34
        let done = working + PixelFont.textWidth("WORKING 2", scale: 2) + 34
        XCTAssertTrue(image.isColor(theme.ink, atX: firstStatX + 1, y: statsY + 5))
        XCTAssertTrue(image.isColor(theme.green, atX: working + 1, y: statsY + 5))
        XCTAssertTrue(image.isColor(theme.yellow, atX: done + 1, y: statsY + 5))
        XCTAssertGreaterThan(image.count(theme.red), 0)
    }

    func testTopBarDropsStatsThatWouldRunUnderTheButtons() {
        let bar = TopBarView()
        bar.stats = AgentStats(states: [.working, .working, .done, .exited])
        let image = RenderedImage(bar, width: 620, height: TopBarView.height)
        let buttons = Int(bar.folderButton.frame.minX)
        XCTAssertGreaterThan(buttons, 0)
        for color in [theme.ink, theme.green, theme.yellow, theme.red] {
            XCTAssertEqual(image.count(color, x: buttons - 10), 0)
        }
    }

    func testAgentStatsCountBootAsIdle() {
        let stats = AgentStats(states: [.boot, .idle, .working, .done, .done, .exited])
        XCTAssertEqual(stats.agents, 6)
        XCTAssertEqual(stats.idle, 2)
        XCTAssertEqual(stats.working, 1)
        XCTAssertEqual(stats.done, 2)
        XCTAssertEqual(stats.exited, 1)
        XCTAssertEqual(AgentStats(states: []), AgentStats())
    }

    func testFolderTitleKeepsTheEndOfALongPath() {
        XCTAssertEqual(TopBarView.folderTitle(shortPath: "~/x"), "DIR ~/x")
        let exact = "~/" + String(repeating: "a", count: 26)
        XCTAssertEqual(TopBarView.folderTitle(shortPath: exact), "DIR " + exact)
        let long = "~/Projetos/" + String(repeating: "b", count: 30) + "/fim"
        let title = TopBarView.folderTitle(shortPath: long)
        XCTAssertEqual(title, "DIR …" + long.suffix(27))
        XCTAssertTrue(title.hasSuffix("/fim"))
    }

    // MARK: avisos

    func testWarningBarQueuesWithoutRepeating() {
        var changes = 0
        let bar = WarningBarView()
        bar.onChange = { changes += 1 }
        XCTAssertEqual(RenderedImage(bar, width: 600, height: WarningBarView.height).count(theme.yellow), 0)

        bar.add("config invalido")
        bar.add("config invalido")
        bar.add("claude nao encontrado")
        XCTAssertEqual(bar.messages, ["config invalido", "claude nao encontrado"])
        XCTAssertEqual(changes, 2)
        XCTAssertGreaterThan(RenderedImage(bar, width: 600, height: WarningBarView.height).count(theme.yellow), 0)

        bar.mouseDown(with: click(bar, x: 5, y: 5))
        XCTAssertEqual(bar.messages, ["claude nao encontrado"])
        bar.mouseDown(with: click(bar, x: 5, y: 5))
        bar.mouseDown(with: click(bar, x: 5, y: 5))
        XCTAssertEqual(bar.messages, [])
        XCTAssertEqual(changes, 4)
    }

    // MARK: tela vazia

    func testEmptyStateHidesTheButtonsWhileLoading() {
        var asked: [Int] = []
        let view = EmptyStateView()
        view.onAdd = { asked.append($0) }
        let buttons = view.subviews.compactMap { $0 as? PixelButton }
        XCTAssertEqual(buttons.map(\.title), ["1 AGENTE", "2 AGENTES", "4 AGENTES", "6 AGENTES"])
        XCTAssertTrue(buttons.allSatisfy(\.isHidden))
        let loading = RenderedImage(view, width: 900, height: 600)
        XCTAssertGreaterThan(loading.count(theme.ink), 0)
        XCTAssertEqual(loading.count(theme.accent), 0)

        view.isLoading = false
        XCTAssertFalse(buttons.contains(where: \.isHidden))
        buttons.forEach { $0.onClick?() }
        XCTAssertEqual(asked, [1, 2, 4, 6])
    }

    func testEmptyStateHintBlinks() {
        let view = EmptyStateView()
        view.isLoading = false
        view.time = 0
        XCTAssertGreaterThan(RenderedImage(view, width: 900, height: 600).count(theme.accent), 0)
        view.time = 0.5
        XCTAssertEqual(RenderedImage(view, width: 900, height: 600).count(theme.accent), 0)
    }

    // MARK: lista lateral

    func testSidebarStacksTheCards() {
        let sidebar = SidebarView()
        let cards = (1...3).map { AgentCardView(snapshot: snapshot(name: "AGENT \($0)")) }
        sidebar.setCards(cards)
        let image = RenderedImage(sidebar, width: SidebarView.width, height: 600)
        XCTAssertEqual(sidebar.cards.count, 3)
        XCTAssertEqual(cards[0].frame, NSRect(x: 3, y: 3, width: 304, height: 86))
        XCTAssertEqual(cards[1].frame.minY, 92)
        XCTAssertEqual(cards[2].frame.minY, 181)
        XCTAssertEqual(Int(sidebar.closeAllButton.frame.maxX), SidebarView.width)
        XCTAssertTrue(image.isColor(theme.shadow, atX: 1, y: 300), "borda esquerda")
        XCTAssertTrue(image.isColor(theme.bg2, atX: 200, y: 3), "cabeçalho")
        XCTAssertGreaterThan(image.count(theme.dim, y: 0, height: 30), 0, "AGENTES 3")

        sidebar.setCards([cards[2]])
        sidebar.layoutSubtreeIfNeeded()
        XCTAssertNil(cards[0].superview)
        XCTAssertEqual(cards[2].frame.minY, 3)
    }
}
