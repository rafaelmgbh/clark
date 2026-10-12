import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// As views desenhadas à mão, conferidas pixel a pixel num bitmap.
final class PixelViewsTests: XCTestCase {
    private let theme = Theme.dark
    /// Cor que não existe no tema: o que aparecer nela veio do agente.
    private let magenta = RGB(r: 1, g: 0, b: 1)

    private func snapshot(_ state: AgentState = .idle, name: String = "AGENT 1", project: String = "PORTAL",
                          company: String = "ACME", path: String = "~/Projetos/acme", preview: [String] = [],
                          diff: DiffSummary? = nil) -> AgentSnapshot {
        AgentSnapshot(name: name, project: project, company: company, color: magenta, path: path, state: state,
                      preview: preview, diff: diff)
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
        XCTAssertEqual(StateLabel.text(.shell, time: 0), "SHELL")
        XCTAssertEqual(StateLabel.text(.shell, time: 0.5), "SHELL..")
    }

    func testStateColors() {
        XCTAssertEqual(StateLabel.color(.working, theme: theme), theme.green)
        XCTAssertEqual(StateLabel.color(.done, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.boot, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.idle, theme: theme), theme.dim)
        XCTAssertEqual(StateLabel.color(.exited, theme: theme), theme.red)
        // A mesma cor em que o Claude Code escreve `1 shell` no rodapé do terminal.
        XCTAssertEqual(StateLabel.color(.shell, theme: theme), theme.term[6])
        XCTAssertNotEqual(StateLabel.color(.shell, theme: theme), StateLabel.color(.working, theme: theme))
        XCTAssertTrue(StateLabel.isAnimated(.shell))
        XCTAssertFalse(StateLabel.isAnimated(.idle))
        XCTAssertFalse(StateLabel.isAnimated(.exited))
        XCTAssertTrue(StateLabel.isAnimated(.done))
    }

    func testEveryLabelFitsThePixelFont() {
        // A fonte pixel só tem ASCII maiúsculo: um texto fora dela sairia como "?".
        let labels = AgentState.allCases.map { StateLabel.text($0, time: 0.75) }
            + ["CLARK", "AGENTS 16", "WORKING 16", "DONE 16", "IDLE 16", "GAME OVER 16", "EM FOCO", "AGENTES 16",
               "SEM PERMISSOES", "NENHUM AGENTE ONLINE", "LENDO O AMBIENTE DO SHELL", "PRESS START  -  CMD+N",
               "PROJETO", "GLOBAL", SessionDigestView.label, "HOJE 09:07", "ONTEM 23:40", "03/10 09:07", "31/12/2025"]
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

    func testHeaderShowsTheDiffSummaryBeforeThePill() {
        let diff = DiffSummary(files: 4, added: 12, removed: 3)
        XCTAssertEqual(DiffBadge.width(diff), PixelFont.textWidth("+12 -3 4 ARQ", scale: 1))
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: diff))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        let badgeX = pillOrigin(width: 600).x - 10 - DiffBadge.width(diff)
        let added = PixelFont.textWidth("+12", scale: 1)
        XCTAssertGreaterThan(image.count(theme.green, x: badgeX, y: 11, width: added, height: 7), 0, "+12 em verde")
        XCTAssertGreaterThan(image.count(theme.red, x: badgeX + added, y: 11, width: 30, height: 7), 0, "-3 em vermelho")
        XCTAssertEqual(image.count(theme.green, x: 0, y: 0, width: badgeX, height: 30), 0)

        header.snapshot = snapshot(.idle)
        let plain = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertEqual(plain.count(theme.green) + plain.count(theme.red), 0, "sem mudanças, sem resumo")
    }

    func testNarrowHeaderDropsTheDiffSummaryAndKeepsTheName() {
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: DiffSummary(files: 4, added: 12, removed: 3)))
        let image = RenderedImage(header, width: 240, height: AgentHeaderView.height)
        XCTAssertEqual(image.count(theme.green) + image.count(theme.red), 0)
        XCTAssertGreaterThan(image.count(theme.ink, x: 30, y: 8, width: 100, height: 14), 0, "nome")
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

    /// Onde o cabeçalho põe o projeto e a empresa, com o nome e o projeto na escala 2.
    private func headerColumns(name: String = "AGENT 1", project: String) -> (project: Int, company: Int) {
        let projectX = 30 + PixelFont.textWidth(name, scale: 2) + 14
        return (projectX, projectX + PixelFont.textWidth(project, scale: 2) + 12)
    }

    func testHeaderShowsTheProjectInTheAgentColorAndTheCompanyInGray() {
        let columns = headerColumns(project: "PORTAL")
        let pill = pillOrigin(width: 600)
        let image = RenderedImage(AgentHeaderView(snapshot: snapshot(path: "")), width: 600,
                                  height: AgentHeaderView.height)
        XCTAssertGreaterThan(image.count(magenta, x: columns.project, y: 8,
                                         width: PixelFont.textWidth("PORTAL", scale: 2), height: 14), 0,
                             "projeto grande, na cor do agente")
        XCTAssertEqual(image.count(magenta, x: columns.company), 0, "depois do projeto nada leva a cor do agente")
        XCTAssertGreaterThan(image.count(theme.dim, x: columns.company, y: 11,
                                         width: PixelFont.textWidth("ACME", scale: 1), height: 7), 0,
                             "empresa pequena e apagada")

        let global = RenderedImage(AgentHeaderView(snapshot: snapshot(project: "GLOBAL", company: "", path: "")),
                                   width: 600, height: AgentHeaderView.height)
        let globalColumns = headerColumns(project: "GLOBAL")
        XCTAssertGreaterThan(global.count(magenta, x: globalColumns.project), 0)
        XCTAssertEqual(global.count(theme.dim, x: globalColumns.company, width: pill.x - globalColumns.company), 0,
                       "o GLOBAL não é de empresa nenhuma")
    }

    func testHeaderDoesNotRepeatTheCompanyNamedLikeTheProject() {
        let columns = headerColumns(project: "ACME")
        let image = RenderedImage(AgentHeaderView(snapshot: snapshot(project: "Acme", company: "ACME", path: "")),
                                  width: 600, height: AgentHeaderView.height)
        XCTAssertGreaterThan(image.count(magenta, x: columns.project), 0)
        XCTAssertEqual(image.count(theme.dim, x: columns.company, width: pillOrigin(width: 600).x - columns.company), 0)
    }

    func testTightHeaderShrinksTheProjectBeforeTouchingTheName() {
        // 480 px: o nome e o projeto na escala 2 não cabem até a pílula.
        let snapshot = snapshot(name: "REVISOR DE PR", project: "Portal de Compras", path: "")
        let image = RenderedImage(AgentHeaderView(snapshot: snapshot), width: 480, height: AgentHeaderView.height)
        let nameWidth = PixelFont.textWidth("REVISOR DE PR", scale: 2)
        let projectX = 30 + nameWidth + 14
        let projectWidth = PixelFont.textWidth("PORTAL DE COMPRAS", scale: 1)
        XCTAssertGreaterThan(image.count(theme.ink, x: 30 + nameWidth - 10, y: 8, width: 10, height: 14), 0,
                             "o nome fica inteiro e grande")
        XCTAssertGreaterThan(image.count(magenta, x: projectX + projectWidth - 5, y: 11, width: 5, height: 7), 0,
                             "o projeto fica inteiro, na escala 1")
        XCTAssertEqual(image.count(magenta, x: projectX, y: 0, width: 480, height: 11), 0)
    }

    func testNarrowHeaderShrinksTheNameInsteadOfCuttingIt() {
        // 240 px, grade cheia: cortados, `AGENT 1` e `AGENT 2` virariam o mesmo `AGE...`.
        let image = RenderedImage(AgentHeaderView(snapshot: snapshot(path: "")), width: 240,
                                  height: AgentHeaderView.height)
        let nameWidth = PixelFont.textWidth("AGENT 1", scale: 1)
        XCTAssertGreaterThan(image.count(theme.ink, x: 30 + nameWidth - 5, y: 11, width: 5, height: 7), 0,
                             "o número do agente continua lá")
        XCTAssertEqual(image.count(theme.ink, x: 30 + nameWidth), 0, "nome na escala 1")
        XCTAssertGreaterThan(image.count(magenta, x: 30 + nameWidth + 14, y: 11,
                                         width: PixelFont.textWidth("PORTAL", scale: 1), height: 7), 0, "projeto")
    }

    func testVeryNarrowHeaderKeepsTheNameAndTheState() {
        let narrow = RenderedImage(AgentHeaderView(snapshot: snapshot(name: "NOME BEM COMPRIDO 123")),
                                   width: 200, height: AgentHeaderView.height)
        XCTAssertEqual(narrow.count(magenta, x: 30), 0, "sem espaço, o projeto some e o estado fica")
        XCTAssertGreaterThan(narrow.count(theme.ink, x: 30, y: 8, width: 60, height: 14), 0, "nome")
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

    func testHeaderTellsWhereTheDiffSummaryIs() {
        let diff = DiffSummary(files: 4, added: 12, removed: 3)
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: diff))
        header.frame = NSRect(x: 0, y: 0, width: 600, height: AgentHeaderView.height)
        let badgeX = pillOrigin(width: 600).x - 10 - DiffBadge.width(diff)
        XCTAssertEqual(header.badgeRect, NSRect(x: badgeX - 5, y: 0, width: DiffBadge.width(diff) + 10,
                                                height: AgentHeaderView.height),
                       "a altura inteira do cabeçalho e uma folga dos lados: o texto tem 7 pontos de altura")

        header.snapshot = snapshot(.idle)
        XCTAssertNil(header.badgeRect, "sem mudanças não há resumo")
        header.snapshot = snapshot(.idle, diff: diff)
        header.frame = NSRect(x: 0, y: 0, width: 240, height: AgentHeaderView.height)
        XCTAssertNil(header.badgeRect, "no cabeçalho estreito o resumo não é desenhado")
    }

    func testClickOnTheDiffSummaryIsNotAHeaderClick() {
        var clicks = 0, doubles = 0, badge = 0
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: DiffSummary(files: 4, added: 12, removed: 3)))
        header.frame = NSRect(x: 0, y: 0, width: 600, height: AgentHeaderView.height)
        header.onClick = { clicks += 1 }
        header.onDoubleClick = { doubles += 1 }
        header.onBadgeClick = { badge += 1 }
        let rect = header.badgeRect ?? .zero
        header.mouseDown(with: click(header, x: rect.midX, y: 15))
        XCTAssertEqual([clicks, doubles, badge], [0, 0, 1])
        header.mouseDown(with: click(header, x: rect.midX, y: 15, count: 2))
        XCTAssertEqual([clicks, doubles, badge], [0, 0, 2], "o segundo clique fecha a lista, não abre o renomear")
        header.mouseDown(with: click(header, x: rect.minX - 2, y: 15))
        header.mouseDown(with: click(header, x: rect.maxX + 2, y: 15))
        XCTAssertEqual([clicks, doubles, badge], [2, 0, 2], "fora do resumo o clique é do cabeçalho")

        header.onBadgeClick = nil
        header.mouseDown(with: click(header, x: rect.midX, y: 15))
        XCTAssertEqual([clicks, doubles, badge], [3, 0, 2], "sem quem ouça, o resumo é parte do cabeçalho")
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

    /// Onde o card põe o projeto: depois do estado, na mesma linha.
    private var cardProjectX: Int { 14 + 9 + PixelFont.textWidth("WORKING...", scale: 1) + 10 }

    func testCardShowsTheProjectBigAndShrinksALongOne() {
        let short = render(AgentCardView(snapshot: snapshot()))
        XCTAssertGreaterThan(short.count(magenta, x: cardProjectX, y: AgentCardView.projectY,
                                         width: PixelFont.textWidth("PORTAL", scale: 2), height: 4), 0,
                             "projeto na escala 2, na cor do agente")

        let long = render(AgentCardView(snapshot: snapshot(project: "Portal de compras da empresa")))
        XCTAssertEqual(long.count(magenta, x: cardProjectX, y: AgentCardView.projectY, width: cardWidth, height: 4), 0,
                       "o nome comprido desce para a escala 1")
        let width = PixelFont.textWidth("PORTAL DE COMPRAS DA EMPRESA", scale: 1)
        XCTAssertGreaterThan(long.count(magenta, x: cardProjectX + width - 5, y: AgentCardView.projectY + 4,
                                        width: 5, height: 7), 0, "e cabe inteiro")
    }

    func testCardShowsTheCompanyUnderTheProject() {
        let width = PixelFont.textWidth("ACME", scale: 1)
        let with = render(AgentCardView(snapshot: snapshot()))
        XCTAssertGreaterThan(with.count(theme.dim, x: 14, y: AgentCardView.detailY, width: width, height: 7), 0)

        let global = render(AgentCardView(snapshot: snapshot(project: "GLOBAL", company: "")))
        XCTAssertEqual(global.count(theme.dim, x: 14, y: AgentCardView.detailY, width: width, height: 7), 0,
                       "o GLOBAL não tem empresa: o caminho começa ali, em outro tom")
        let same = render(AgentCardView(snapshot: snapshot(project: "Acme", company: "ACME")))
        XCTAssertEqual(same.count(theme.dim, x: 14, y: AgentCardView.detailY, width: width, height: 7), 0,
                       "a empresa com o nome do projeto não se repete")
    }

    func testCardShowsTheDiffSummaryOnTheDetailLine() {
        let diff = DiffSummary(files: 4, added: 12, removed: 3)
        let card = AgentCardView(snapshot: snapshot(.idle, diff: diff))
        let badgeX = cardWidth - 8 - DiffBadge.width(diff)
        let y = AgentCardView.detailY
        let image = render(card)
        XCTAssertGreaterThan(image.count(theme.green, x: badgeX, y: y, width: 20, height: 7), 0, "+12 em verde")
        XCTAssertGreaterThan(image.count(theme.red, x: badgeX, y: y, width: DiffBadge.width(diff), height: 7), 0)
        XCTAssertEqual(image.count(theme.green, x: 0, y: 0, width: badgeX, height: AgentCardView.height), 0)
        XCTAssertGreaterThan(image.count(theme.dim, x: 14, y: y, width: 23, height: 7), 0, "a empresa continua na linha")

        card.snapshot = snapshot(.idle)
        let plain = render(card)
        XCTAssertEqual(plain.count(theme.green) + plain.count(theme.red), 0, "sem mudanças, sem resumo")
    }

    func testCardWithBigNumbersStillFitsTheSummary() {
        let diff = DiffSummary(files: 1234, added: 98_765, removed: 43_210)
        XCTAssertLessThan(DiffBadge.width(diff), cardWidth - 110, "cabe ao lado da empresa")
        let image = render(AgentCardView(snapshot: snapshot(.working, diff: diff)))
        XCTAssertGreaterThan(image.count(theme.red, x: 100, y: AgentCardView.detailY, width: cardWidth - 100,
                                         height: 7), 0)
    }

    func testCardPreviewChangesTheDrawing() {
        let empty = render(AgentCardView(snapshot: snapshot()))
        let filled = render(AgentCardView(snapshot: snapshot(preview: ["compilando o projeto", "42 testes verdes"])))
        let background = theme.bg2
        let (y, height) = (AgentCardView.previewY, AgentCardView.height - AgentCardView.previewY)
        XCTAssertLessThan(filled.count(background, y: y, height: height), empty.count(background, y: y, height: height))
    }

    // MARK: resumo da última sessão

    private let digestDate = Date(timeIntervalSince1970: 1_760_000_000)

    private func digest(pending: String? = "falta rodar a migração") -> SessionDigest {
        SessionDigest(title: "Ajuste do relatório", prompt: "corrige o total", answer: ["Total corrigido.", "Suíte verde."],
                      pending: pending, date: digestDate)
    }

    private func digestView(_ digest: SessionDigest?) -> SessionDigestView {
        let view = SessionDigestView()
        view.digest = digest
        view.now = { [digestDate] in digestDate }
        return view
    }

    func testDigestStripHeightFollowsTheLines() {
        XCTAssertEqual(SessionDigestView.height(for: digest()), 10 + 15 * 4, "título, pedido, resposta e pendência")
        XCTAssertEqual(SessionDigestView.height(for: digest(pending: nil)), 10 + 15 * 4, "sem pendência: duas da resposta")
        let onlyTitle = SessionDigest(title: "Só o título", prompt: nil, date: digestDate)
        XCTAssertEqual(SessionDigestView.height(for: onlyTitle), 10 + 15)
    }

    func testDigestStripShowsTheLabelTheDateAndTheLines() {
        let height = SessionDigestView.height(for: digest())
        let image = RenderedImage(digestView(digest()), width: 600, height: height)
        let label = PixelFont.textWidth(SessionDigestView.label, scale: 1)
        XCTAssertTrue(image.isColor(theme.accent, atX: 1, y: height / 2), "faixa lateral")
        XCTAssertGreaterThan(image.count(theme.accent, x: 12, y: 9, width: label, height: 7), 0, "ULTIMA SESSAO")
        XCTAssertGreaterThan(image.count(theme.dim, x: 12 + label + 10, y: 9,
                                         width: PixelFont.textWidth("HOJE 00:00", scale: 1), height: 7), 0, "HOJE hh:mm")
        XCTAssertGreaterThan(image.count(theme.dim, x: 600 - 20, y: 9, width: 20, height: 7), 0, "o X de fechar")

        // O texto corrido é suavizado: confere-se pelo fundo que ele cobre, linha a linha.
        let empty = RenderedImage(digestView(nil), width: 600, height: height)
        for row in 0..<4 {
            let y = 5 + 15 * row
            XCTAssertLessThan(image.count(theme.bg2, x: 12, y: y, width: 560, height: 15),
                              empty.count(theme.bg2, x: 12, y: y, width: 560, height: 15), "linha \(row)")
        }
    }

    func testDigestStripPendingLineIsYellow() {
        let height = SessionDigestView.height(for: digest())
        let with = RenderedImage(digestView(digest()), width: 600, height: height)
        let without = RenderedImage(digestView(digest(pending: nil)), width: 600, height: height)
        XCTAssertGreaterThan(with.count(theme.yellow, y: 5 + 15 * 3, height: 15), 0)
        XCTAssertEqual(without.count(theme.yellow), 0)
        XCTAssertEqual(with.count(theme.yellow, y: 0, height: 5 + 15 * 3), 0, "só a linha da pendência")
    }

    func testDigestStripClosesOnClick() {
        var dismissed = 0
        let view = digestView(digest())
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 70)
        view.onDismiss = { dismissed += 1 }
        view.mouseDown(with: click(view, x: 300, y: 20))
        XCTAssertEqual(dismissed, 1)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "fecha no primeiro clique, mesmo com a janela atrás")
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
        let buttons = Int(bar.projectButton.frame.minX)
        XCTAssertGreaterThan(buttons, 0)
        for color in [theme.ink, theme.green, theme.yellow, theme.red] {
            XCTAssertEqual(image.count(color, x: buttons - 10), 0)
        }
    }

    // MARK: medidor de consumo

    private func usage(_ percents: [Int?], age: Double = 60) -> UsageMeter {
        let labels = ["5H", "7D"]
        let gauges = percents.enumerated().map { UsageMeter.Gauge(label: labels[$0.offset], percent: $0.element,
                                                                 resetsIn: 3600) }
        return UsageMeter(gauges: gauges, age: age)
    }

    private func meterView(_ meter: UsageMeter?, compact: Bool = false) -> (view: UsageMeterView, image: RenderedImage) {
        let view = UsageMeterView()
        view.meter = meter
        view.isCompact = compact
        let width = max(1, view.fittingWidth(compact: compact))
        return (view, RenderedImage(view, width: width, height: UsageMeterView.height))
    }

    func testUsageMeterColorsEachBarByItsLevel() {
        let (view, image) = meterView(usage([20, 85]))
        let half = view.fittingWidth(compact: false) / 2
        XCTAssertEqual(image.count(theme.green), 2 * 4 * 10, "20% acende dois blocos verdes")
        XCTAssertEqual(image.count(theme.green, x: half), 0)
        XCTAssertGreaterThan(image.count(theme.yellow, x: half), 8 * 4 * 10, "85%: oito blocos e o número, amarelos")
        XCTAssertEqual(image.count(theme.red), 0)
        XCTAssertEqual(image.count(theme.bg4), (8 + 2) * 4 * 10, "os blocos apagados")
        XCTAssertGreaterThan(image.count(theme.ink, width: half), 0, "abaixo do alerta o número sai na cor do texto")
        XCTAssertGreaterThan(meterView(usage([96])).image.count(theme.red), 9 * 4 * 10)
    }

    func testStaleUsageMeterIsAllGray() {
        let image = meterView(usage([20, 96], age: UsageMeter.staleAfter + 1)).image
        for color in [theme.green, theme.yellow, theme.red, theme.ink] { XCTAssertEqual(image.count(color), 0) }
        XCTAssertGreaterThan(image.count(theme.dim), 0)
    }

    func testCompactUsageMeterDropsTheBars() {
        let (view, image) = meterView(usage([20, 85]), compact: true)
        XCTAssertEqual(view.fittingWidth(compact: false) - view.fittingWidth(compact: true),
                       2 * (UsageMeterView.barWidth + 6))
        XCTAssertEqual(image.count(theme.bg4), 0)
        XCTAssertEqual(image.count(theme.green), 0)
        XCTAssertGreaterThan(image.count(theme.yellow), 0, "o número continua na cor do nível")
    }

    func testUsageMeterWithoutAReadingTakesNoRoomAndTellsItsSummaryOtherwise() {
        let view = UsageMeterView()
        XCTAssertEqual(view.fittingWidth(compact: false), 0)
        XCTAssertNil(view.toolTip)
        view.meter = usage([20])
        XCTAssertEqual(view.toolTip, usage([20]).summary)
        view.meter = nil
        XCTAssertNil(view.toolTip)
    }

    func testUnknownUsageShowsDashesAndAnEmptyBar() {
        let (view, image) = meterView(usage([nil]))
        XCTAssertEqual(view.fittingWidth(compact: false),
                       PixelFont.textWidth("5H", scale: 2) + 6 + UsageMeterView.barWidth + 6
                           + PixelFont.textWidth("--", scale: 2))
        XCTAssertEqual(image.count(theme.bg4), 10 * 4 * 10)
        XCTAssertEqual(image.count(theme.green), 0)
    }

    func testTopBarShowsTheUsageMeterBetweenTheStatsAndTheButtons() {
        let bar = TopBarView()
        XCTAssertTrue(bar.usageView.isHidden, "sem leitura não há medidor")
        bar.stats = AgentStats(states: [.working, .working, .done])
        bar.usage = usage([20, 85])
        _ = RenderedImage(bar, width: 1360, height: TopBarView.height)
        let meter = bar.usageView
        XCTAssertFalse(meter.isHidden)
        XCTAssertFalse(meter.isCompact)
        XCTAssertEqual(meter.meter, bar.usage)
        XCTAssertEqual(Int(meter.frame.width), meter.fittingWidth(compact: false))
        XCTAssertEqual(Int(meter.frame.maxX), Int(bar.projectButton.frame.minX) - 16)
        XCTAssertEqual(Int(meter.frame.minY), (46 - UsageMeterView.height) / 2)
        bar.usage = nil
        _ = RenderedImage(bar, width: 1360, height: TopBarView.height)
        XCTAssertTrue(meter.isHidden)
    }

    func testTightTopBarShrinksTheUsageMeterAndThenHidesItBeforeAnyStat() {
        let bar = TopBarView()
        bar.stats = AgentStats(states: [.working, .working, .done])
        bar.usage = usage([20, 85])
        let meter = bar.usageView
        let statsRight = firstStatX + ["AGENTS 3", "WORKING 2", "DONE 1", "IDLE 0"]
            .map { PixelFont.textWidth($0, scale: 2) + 34 }.reduce(0, +) - 22
        // Largura em que o medidor inteiro cabe com a folga exata, e um pixel a menos.
        _ = RenderedImage(bar, width: 1360, height: TopBarView.height)
        let right = 1360 - Int(bar.projectButton.frame.minX)
        let full = statsRight + 16 + meter.fittingWidth(compact: false) + 16 + right
        _ = RenderedImage(bar, width: full, height: TopBarView.height)
        XCTAssertFalse(meter.isHidden)
        XCTAssertFalse(meter.isCompact)
        _ = RenderedImage(bar, width: full - 1, height: TopBarView.height)
        XCTAssertFalse(meter.isHidden)
        XCTAssertTrue(meter.isCompact, "sem espaço para as barras ficam só os números")
        XCTAssertEqual(Int(meter.frame.width), meter.fittingWidth(compact: true))

        let compact = statsRight + 16 + meter.fittingWidth(compact: true) + 16 + right
        _ = RenderedImage(bar, width: compact, height: TopBarView.height)
        XCTAssertFalse(meter.isHidden)
        let tight = RenderedImage(bar, width: compact - 1, height: TopBarView.height)
        XCTAssertTrue(meter.isHidden, "o medidor some antes de qualquer contagem")
        let idle = statsRight - PixelFont.textWidth("IDLE 0", scale: 2)
        XCTAssertGreaterThan(tight.count(theme.dim, x: idle, y: statsY, width: statsRight - idle, height: 14), 0,
                             "a última contagem continua na barra")
    }

    func testTopBarRecomputesTheUsageMeterWhenTheStatsGrow() {
        let bar = TopBarView()
        bar.stats = AgentStats(states: [.working])
        bar.usage = usage([20, 85])
        _ = RenderedImage(bar, width: 1360, height: TopBarView.height)
        let right = 1360 - Int(bar.projectButton.frame.minX)
        let statsRight = firstStatX + ["AGENTS 1", "WORKING 1", "DONE 0", "IDLE 0"]
            .map { PixelFont.textWidth($0, scale: 2) + 34 }.reduce(0, +) - 22
        let width = statsRight + 16 + bar.usageView.fittingWidth(compact: false) + 16 + right
        _ = RenderedImage(bar, width: width, height: TopBarView.height)
        XCTAssertFalse(bar.usageView.isCompact)
        // GAME OVER entra na barra e toma o lugar das barras do medidor.
        bar.stats = AgentStats(states: [.working, .exited])
        _ = RenderedImage(bar, width: width, height: TopBarView.height)
        XCTAssertTrue(bar.usageView.isHidden)
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

    func testAgentStatsCountAShellInTheBackgroundAsWorking() {
        let stats = AgentStats(states: [.shell, .working, .idle])
        XCTAssertEqual(stats.agents, 3)
        XCTAssertEqual(stats.working, 2)
        XCTAssertEqual(stats.idle, 1)
    }

    func testProjectButtonHasAFixedTitle() {
        // O projeto de cada agente está no cabeçalho dele; o botão só abre o menu.
        XCTAssertEqual(TopBarView().projectButton.title, "PROJETO")
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
        let step = CGFloat(AgentCardView.height + 3)
        XCTAssertEqual(AgentCardView.height, 104, "três linhas de texto e duas de prévia")
        XCTAssertEqual(cards[0].frame, NSRect(x: 3, y: 3, width: 304, height: 104))
        XCTAssertEqual(cards[1].frame.minY, 3 + step)
        XCTAssertEqual(cards[2].frame.minY, 3 + 2 * step)
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
