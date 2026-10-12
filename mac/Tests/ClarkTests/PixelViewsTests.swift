import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// As views desenhadas à mão, conferidas pixel a pixel num bitmap.
final class PixelViewsTests: XCTestCase {
    private let theme = Theme.dark
    /// Cor que não existe no tema: o que aparecer nela veio do agente.
    private let magenta = RGB(r: 1, g: 0, b: 1)

    /// - Parameter tone: a cor do agente, quando o teste precisa dela diferente da cor da empresa.
    private func snapshot(_ state: AgentState = .idle, name: String = "AGENT 1", project: String = "PORTAL",
                          company: String = "ACME", path: String = "~/Projetos/acme", preview: [String] = [],
                          diff: DiffSummary? = nil, remoteControl: Bool = false,
                          tone: RGB? = nil) -> AgentSnapshot {
        AgentSnapshot(name: name, project: project, company: company, color: tone ?? magenta,
                      companyColor: magenta, path: path, state: state, preview: preview, diff: diff,
                      remoteControl: remoteControl)
    }

    /// A etiqueta `REMOTO` inteira, com o canto em (x, y): fundo azul e as letras na cor do fundo da janela.
    private func assertRemoteTag(in image: RenderedImage, x: Int, y: Int, file: StaticString = #filePath,
                                 line: UInt = #line) {
        let blue = RemoteBadge.color(theme)
        let letters = PixelFont.pixels("REMOTO")
        XCTAssertFalse(letters.isEmpty, file: file, line: line)
        for pixel in letters {
            XCTAssertTrue(image.isColor(theme.bg, atX: x + 4 + pixel.x, y: y + 2 + pixel.y),
                          "letra em (\(pixel.x), \(pixel.y))", file: file, line: line)
        }
        XCTAssertEqual(image.count(blue, x: x, y: y, width: RemoteBadge.width, height: RemoteBadge.height),
                       RemoteBadge.width * RemoteBadge.height - letters.count, "fundo da etiqueta", file: file,
                       line: line)
        XCTAssertEqual(image.count(blue), RemoteBadge.width * RemoteBadge.height - letters.count,
                       "azul só na etiqueta", file: file, line: line)
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
        XCTAssertTrue(image.isColor(magenta, atX: 11, y: 8), "etiqueta da empresa na cor do agente")
        XCTAssertTrue(image.isColor(theme.green, atX: pill.x, y: pill.y), "moldura da pílula em WORKING")

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
        let agent = header.tags(width: 240).last
        XCTAssertEqual(agent?.kind, .agent)
        XCTAssertEqual(agent?.width, tagWidth("AGENT 1", compact: true), "o nome do agente fica inteiro")
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

    // MARK: etiquetas do cabeçalho

    private func tagWidth(_ text: String, compact: Bool = false) -> Int {
        NameTag.width(text, compact: compact)
    }

    /// Até onde as etiquetas podem ir: a pílula do estado, com a folga dela.
    private func tagLimit(width: Int) -> Int {
        let scale = width < AgentHeaderView.compactWidth ? 1 : 2
        return width - (PixelFont.textWidth("WORKING...", scale: scale) + 16) - 6 - 10
    }

    /// Uma etiqueta no desenho dos botões da barra: moldura, face e sombra dura embaixo à direita.
    private func assertTag(in image: RenderedImage, _ tag: AgentHeaderView.Tag, face: RGB,
                           file: StaticString = #filePath, line: UInt = #line) {
        let x = tag.x, y = 5, right = tag.x + tag.width, bottom = y + NameTag.height
        for corner in [(x, y), (right - 1, bottom - 1), (x, y + 10), (right - 1, y + 10)] {
            XCTAssertTrue(image.isColor(theme.shadow, atX: corner.0, y: corner.1), "moldura em \(corner)",
                          file: file, line: line)
        }
        XCTAssertTrue(image.isColor(face, atX: x + 2, y: y + 2), "face", file: file, line: line)
        XCTAssertTrue(image.isColor(face, atX: right - 3, y: bottom - 3), "face", file: file, line: line)
        XCTAssertTrue(image.isColor(theme.shadow, atX: right + 2, y: bottom + 2), "sombra dura", file: file,
                      line: line)
        XCTAssertTrue(image.isColor(theme.bg2, atX: right + 3, y: bottom + 2), "a sombra tem 3 pontos",
                      file: file, line: line)
        XCTAssertTrue(image.isColor(theme.bg2, atX: right, y: y + 2), "a sombra começa 3 pontos abaixo",
                      file: file, line: line)
        XCTAssertTrue(image.isColor(theme.bg2, atX: x - 1, y: y + 10), "folga antes da etiqueta", file: file,
                      line: line)
    }

    func testTagWidthFollowsTheTextInTheButtonFont() {
        XCTAssertEqual(tagWidth("ACME"), Pixel.monoWidth("ACME", size: 11, bold: true) + 18)
        XCTAssertEqual(tagWidth("ACME", compact: true), Pixel.monoWidth("ACME", size: 10, bold: true) + 12)
        XCTAssertEqual(tagWidth(""), NameTag.height, "sem texto, o quadrado da cor")
        XCTAssertEqual(tagWidth("", compact: true), NameTag.height)
    }

    func testTagInkIsTheOneThatReadsBestOnTheFace() {
        XCTAssertEqual(NameTag.ink(on: magenta, theme: theme), theme.onAccent)
        XCTAssertEqual(NameTag.ink(on: RGB(r: 0.1, g: 0.1, b: 0.3), theme: theme), theme.ink)
        // Toda cor de empresa do tema, em qualquer tom, deixa a etiqueta legível.
        for color in theme.agents + [theme.dim] {
            for tone in 0..<CompanyResolver.toneCount {
                let face = CompanyResolver.tone(color, index: tone)
                XCTAssertGreaterThan(NameTag.ink(on: face, theme: theme).contrast(face), 3.8, face.hex)
            }
        }
    }

    func testHeaderShowsCompanyProjectAndAgentAsTagsInThatOrder() {
        let header = AgentHeaderView(snapshot: snapshot(path: ""))
        let tags = header.tags(width: 600)
        let company = tagWidth("ACME"), project = tagWidth("PORTAL")
        XCTAssertEqual(tags, [
            AgentHeaderView.Tag(kind: .company, x: 8, width: company, text: "ACME"),
            AgentHeaderView.Tag(kind: .project, x: 8 + company + 8, width: project, text: "PORTAL"),
            AgentHeaderView.Tag(kind: .agent, x: 8 + company + 8 + project + 8, width: tagWidth("AGENT 1"),
                                text: "AGENT 1"),
        ])

        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        for (tag, face) in zip(tags, [magenta, theme.bg3, theme.bg3]) {
            assertTag(in: image, tag, face: face)
        }
        XCTAssertEqual(image.count(magenta, x: 8 + company), 0, "só a etiqueta da empresa leva a cor dela")
        XCTAssertGreaterThan(image.count(theme.onAccent, x: 8, y: 5, width: company, height: NameTag.height), 0,
                             "letra escura na face clara")
        for tag in tags.dropFirst() {
            XCTAssertGreaterThan(image.count(theme.ink, x: tag.x, y: 5, width: tag.width, height: NameTag.height), 0,
                                 tag.text)
        }
        XCTAssertEqual(image.count(theme.ink, x: 0, y: 0, width: tags[1].x, height: AgentHeaderView.height), 0)
    }

    /// A etiqueta é da empresa: igual em todos os agentes dela, sem o tom que distingue um do outro.
    func testCompanyTagIgnoresTheToneOfTheAgent() {
        let cyan = RGB(r: 0, g: 1, b: 1)
        let header = AgentHeaderView(snapshot: snapshot(tone: cyan))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        assertTag(in: image, header.tags(width: 600)[0], face: magenta)
        XCTAssertEqual(image.count(cyan), 0)

        let drawn = render(AgentCardView(snapshot: snapshot(tone: cyan)))
        XCTAssertGreaterThan(drawn.count(cyan), 0, "o card segue no tom do agente")
        XCTAssertEqual(drawn.count(magenta), 0)
    }

    func testHeaderWithoutCompanySaysGlobalAndDoesNotRepeatIt() {
        let home = AgentHeaderView(snapshot: snapshot(project: "GLOBAL", company: "", path: ""))
        XCTAssertEqual(home.tags(width: 600), [
            AgentHeaderView.Tag(kind: .company, x: 8, width: tagWidth("GLOBAL"), text: "GLOBAL"),
            AgentHeaderView.Tag(kind: .agent, x: 8 + tagWidth("GLOBAL") + 8, width: tagWidth("AGENT 1"),
                                text: "AGENT 1"),
        ], "a home é do GLOBAL: a etiqueta do projeto diria a mesma coisa")
        let image = RenderedImage(home, width: 600, height: AgentHeaderView.height)
        assertTag(in: image, home.tags(width: 600)[0], face: magenta)

        let loose = AgentHeaderView(snapshot: snapshot(project: "Notas", company: "", path: ""))
        XCTAssertEqual(loose.tags(width: 600).map(\.text), ["GLOBAL", "NOTAS", "AGENT 1"],
                       "pasta fora de toda empresa: GLOBAL na frente do projeto")
    }

    func testHeaderDoesNotRepeatTheProjectNamedLikeTheCompany() {
        let header = AgentHeaderView(snapshot: snapshot(project: "Acme", company: "ACME", path: ""))
        XCTAssertEqual(header.tags(width: 600).map(\.kind), [.company, .agent])
        XCTAssertEqual(header.tags(width: 600).map(\.text), ["ACME", "AGENT 1"])
    }

    func testTagsKeepTheAccentsAndGoUpperCase() {
        let header = AgentHeaderView(snapshot: snapshot(name: "Revisão", project: "Área do Cliente",
                                                        company: "Indústria", path: ""))
        XCTAssertEqual(header.tags(width: 900).map(\.text), ["INDÚSTRIA", "ÁREA DO CLIENTE", "REVISÃO"])
    }

    /// A cor já diz a empresa: apertou, o nome dela sai antes de o projeto perder uma letra.
    func testTightHeaderTurnsTheCompanyIntoASquareOfItsColor() {
        let header = AgentHeaderView(snapshot: snapshot(name: "AGENT 12", project: "Portal de Compras", path: ""))
        let project = tagWidth("PORTAL DE COMPRAS", compact: true), agent = tagWidth("AGENT 12", compact: true)
        let whole = 8 + tagWidth("ACME", compact: true) + 8 + project + 8 + agent
        // Largura em que as três inteiras passariam da pílula por 1 ponto.
        let width = (0..<AgentHeaderView.compactWidth).first { tagLimit(width: $0) == whole - 1 } ?? 0
        XCTAssertEqual(header.tags(width: width + 1).map(\.text), ["ACME", "PORTAL DE COMPRAS", "AGENT 12"])

        let tags = header.tags(width: width)
        XCTAssertEqual(tags, [
            AgentHeaderView.Tag(kind: .company, x: 8, width: NameTag.height, text: ""),
            AgentHeaderView.Tag(kind: .project, x: 8 + NameTag.height + 8, width: project,
                                text: "PORTAL DE COMPRAS"),
            AgentHeaderView.Tag(kind: .agent, x: 8 + NameTag.height + 8 + project + 8, width: agent,
                                text: "AGENT 12"),
        ])
        let image = RenderedImage(header, width: width, height: AgentHeaderView.height)
        for (tag, face) in zip(tags, [magenta, theme.bg3, theme.bg3]) {
            assertTag(in: image, tag, face: face)
        }
        let inner = NameTag.height - 4
        XCTAssertEqual(image.count(magenta), inner * inner, "o quadrado é só a cor, sem letra")
    }

    /// Estreitando: sai o nome da empresa, o projeto é cortado, o projeto sai, o quadrado sai e só
    /// no fim o nome do agente é cortado.
    func testNarrowingHeaderCutsTheAgentNameLast() {
        let header = AgentHeaderView(snapshot: snapshot(name: "AGENT 12", project: "Portal de Compras", path: ""))
        let project = tagWidth("PORTAL DE COMPRAS", compact: true), agent = tagWidth("AGENT 12", compact: true)
        var stages: [String] = []
        for width in stride(from: AgentHeaderView.compactWidth - 1, through: 130, by: -1) {
            let tags = header.tags(width: width)
            XCTAssertEqual(tags.first?.x, 8, "largura \(width)")
            XCTAssertLessThanOrEqual((tags.last?.x ?? 0) + (tags.last?.width ?? 0), tagLimit(width: width),
                                     "largura \(width): passou da pílula")
            for (before, after) in zip(tags, tags.dropFirst()) {
                XCTAssertEqual(after.x, before.x + before.width + 8, "largura \(width)")
            }
            let stage: String
            switch tags.map(\.kind) {
            case [.company, .project, .agent]:
                XCTAssertEqual(tags[2].width, agent, "largura \(width)")
                if tags[1].width < project {
                    XCTAssertEqual(tags[0].text, "", "o projeto só é cortado com a empresa já no quadrado")
                    XCTAssertGreaterThanOrEqual(tags[1].width, tagWidth("A…", compact: true), "largura \(width)")
                    stage = "projeto cortado"
                } else {
                    XCTAssertEqual(tags[1].width, project)
                    stage = tags[0].text.isEmpty ? "quadrado" : "inteiro"
                }
            case [.company, .agent]:
                XCTAssertEqual(tags[0].text, "")
                XCTAssertEqual(tags[1].width, agent, "largura \(width)")
                stage = "sem projeto"
            case [.agent]:
                XCTAssertLessThanOrEqual(tags[0].width, agent)
                stage = tags[0].width == agent ? "só o agente" : "agente cortado"
            default:
                stage = "inesperado na largura \(width)"
            }
            XCTAssertEqual(tags.last?.text, "AGENT 12")
            if stages.last != stage { stages.append(stage) }
        }
        XCTAssertEqual(stages, ["inteiro", "quadrado", "projeto cortado", "sem projeto", "só o agente",
                                "agente cortado"])
    }

    func testHeaderWithoutRoomKeepsTheAgentTagASquare() {
        let header = AgentHeaderView(snapshot: snapshot(name: "AGENT 12", project: "Portal de Compras", path: ""))
        // Sem lugar nem para o quadrado, a etiqueta do agente não encolhe mais nem some.
        for width in 0..<130 {
            let tags = header.tags(width: width)
            XCTAssertEqual(tags.map(\.kind), [.agent], "largura \(width)")
            XCTAssertGreaterThanOrEqual(tags.first?.width ?? 0, NameTag.height, "largura \(width)")
        }
        XCTAssertEqual(header.tags(width: 0).first?.width, NameTag.height)
    }

    func testCutProjectStaysInsideItsTag() {
        let header = AgentHeaderView(snapshot: snapshot(name: "AGENT 12", project: "Portal de Compras", path: ""))
        let project = tagWidth("PORTAL DE COMPRAS", compact: true)
        let width = (130..<AgentHeaderView.compactWidth).first { header.tags(width: $0).count == 3 } ?? 0
        let tags = header.tags(width: width)
        XCTAssertLessThan(tags[1].width, project, "na primeira largura com as três, o projeto está cortado")
        let image = RenderedImage(header, width: width, height: AgentHeaderView.height)
        for (tag, face) in zip(tags, [magenta, theme.bg3, theme.bg3]) {
            assertTag(in: image, tag, face: face)
        }
    }

    /// Cortado pelo fim, `AGENT 1` e `AGENT 2` virariam a mesma etiqueta.
    func testCutAgentNameKeepsItsEnd() {
        let one = AgentHeaderView(snapshot: snapshot(name: "REVISOR DE PR NUMERO 1"))
        let two = AgentHeaderView(snapshot: snapshot(name: "REVISOR DE PR NUMERO 2"))
        XCTAssertEqual(one.tags(width: 200), [
            AgentHeaderView.Tag(kind: .agent, x: 8, width: tagLimit(width: 200) - 8, text: "REVISOR DE PR NUMERO 1"),
        ])
        let first = RenderedImage(one, width: 200, height: AgentHeaderView.height)
        assertTag(in: first, one.tags(width: 200)[0], face: theme.bg3)
        XCTAssertNotEqual(first, RenderedImage(two, width: 200, height: AgentHeaderView.height),
                          "o fim do nome continua na tela")
        XCTAssertGreaterThan(first.count(theme.dim, x: tagLimit(width: 200)), 0, "pílula do estado")
    }

    func testPathStartsAfterTheLastTag() {
        let header = AgentHeaderView(snapshot: snapshot())
        let last = header.tags(width: 900).last ?? AgentHeaderView.Tag(kind: .agent, x: 0, width: 0, text: "")
        let end = last.x + last.width
        let image = RenderedImage(header, width: 900, height: AgentHeaderView.height)
        let height = AgentHeaderView.height
        XCTAssertEqual(image.count(theme.bg2, x: end + 3, y: 0, width: 9, height: height), 9 * height,
                       "folga entre a sombra da etiqueta e o caminho")
        XCTAssertLessThan(image.count(theme.bg2, x: end + 12, y: 0, width: 40, height: height), 40 * height,
                          "o caminho começa logo depois")

        let bare = RenderedImage(AgentHeaderView(snapshot: snapshot(path: "")), width: 900, height: height)
        XCTAssertEqual(bare.count(theme.bg2, x: end + 3, y: 0, width: tagLimit(width: 900) - end - 3, height: height),
                       (tagLimit(width: 900) - end - 3) * height, "sem caminho, nada depois das etiquetas")
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

    func testHeaderShowsTheRemoteControlTagBesideThePill() {
        XCTAssertEqual(RemoteBadge.width, PixelFont.textWidth("REMOTO", scale: 1) + 8)
        let header = AgentHeaderView(snapshot: snapshot(.idle, remoteControl: true))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        assertRemoteTag(in: image, x: pillOrigin(width: 600).x - 10 - RemoteBadge.width, y: 9)

        header.snapshot = snapshot(.idle)
        let plain = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertEqual(plain.count(RemoteBadge.color(theme)), 0, "sem controle remoto, sem etiqueta")
    }

    func testHeaderPutsTheDiffSummaryBeforeTheRemoteControlTag() {
        let diff = DiffSummary(files: 4, added: 12, removed: 3)
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: diff, remoteControl: true))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        let tagX = pillOrigin(width: 600).x - 10 - RemoteBadge.width
        let badgeX = tagX - 10 - DiffBadge.width(diff)
        assertRemoteTag(in: image, x: tagX, y: 9)
        XCTAssertGreaterThan(image.count(theme.green, x: badgeX, y: 11, width: PixelFont.textWidth("+12", scale: 1),
                                         height: 7), 0, "+12 em verde")
        XCTAssertEqual(image.count(theme.green, x: 0, y: 0, width: badgeX, height: 30), 0)
        XCTAssertEqual(header.badgeRect, NSRect(x: badgeX - 5, y: 0, width: DiffBadge.width(diff) + 10,
                                                height: AgentHeaderView.height), "o clique acompanha o resumo")
    }

    /// Apertou: sai o resumo do diff, que também está no menu e no card, e fica o aviso.
    func testTightHeaderDropsTheDiffSummaryBeforeTheRemoteControlTag() {
        let diff = DiffSummary(files: 4, added: 12, removed: 3)
        let header = AgentHeaderView(snapshot: snapshot(.idle, diff: diff, remoteControl: true))
        var onlyTheTag = 0
        for width in stride(from: 600, through: 240, by: -4) {
            let image = RenderedImage(header, width: width, height: AgentHeaderView.height)
            let hasTag = image.count(RemoteBadge.color(theme)) > 0
            if header.badgeRect != nil {
                XCTAssertTrue(hasTag, "largura \(width): o resumo ficou e o aviso saiu")
            } else if hasTag {
                onlyTheTag += 1
            }
        }
        XCTAssertGreaterThan(onlyTheTag, 0, "há larguras em que só o aviso cabe")
    }

    /// As etiquetas dizem qual é o agente: o aviso nunca tira espaço delas.
    func testRemoteControlTagNeverShrinksTheNameTags() {
        let plain = AgentHeaderView(snapshot: snapshot(.idle, project: "PORTAL DO CLIENTE"))
        let remote = AgentHeaderView(snapshot: snapshot(.idle, project: "PORTAL DO CLIENTE", remoteControl: true))
        var withTag = 0
        for width in stride(from: 700, through: 200, by: -10) {
            let off = RenderedImage(plain, width: width, height: AgentHeaderView.height)
            let on = RenderedImage(remote, width: width, height: AgentHeaderView.height)
            let tags = plain.tags(width: width)
            XCTAssertEqual(remote.tags(width: width), tags, "etiquetas na largura \(width)")
            // Só a área das etiquetas: o caminho, suavizado, tem pixels de tom vizinho ao da face.
            let end = (tags.last?.x ?? 0) + (tags.last?.width ?? 0) + NameTag.shadow
            for color in [theme.bg3, theme.ink, magenta, theme.shadow] {
                XCTAssertEqual(on.count(color, width: end), off.count(color, width: end),
                               "\(color.hex) na largura \(width)")
            }
            if on.count(RemoteBadge.color(theme)) > 0 { withTag += 1 }
        }
        XCTAssertGreaterThan(withTag, 0)
        let narrow = RenderedImage(remote, width: 240, height: AgentHeaderView.height)
        XCTAssertEqual(narrow.count(RemoteBadge.color(theme)), 0, "no cabeçalho estreito o aviso fica só no card")
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

    func testCardShowsTheRemoteControlTagAtTheEndOfTheDetailLine() {
        let card = AgentCardView(snapshot: snapshot(.idle, remoteControl: true))
        let image = render(card)
        assertRemoteTag(in: image, x: cardWidth - 8 - RemoteBadge.width, y: AgentCardView.detailY - 2)
        XCTAssertGreaterThan(image.count(theme.dim, x: 14, y: AgentCardView.detailY, width: 23, height: 7), 0,
                             "a empresa continua na linha")

        card.snapshot = snapshot(.idle)
        XCTAssertEqual(render(card).count(RemoteBadge.color(theme)), 0, "sem controle remoto, sem etiqueta")
    }

    func testCardPutsTheDiffSummaryBeforeTheRemoteControlTag() {
        let diff = DiffSummary(files: 1234, added: 98_765, removed: 43_210)
        let card = AgentCardView(snapshot: snapshot(.idle, diff: diff, remoteControl: true))
        let tagX = cardWidth - 8 - RemoteBadge.width
        let badgeX = tagX - 8 - DiffBadge.width(diff)
        let y = AgentCardView.detailY
        let image = render(card)
        assertRemoteTag(in: image, x: tagX, y: y - 2)
        XCTAssertGreaterThan(image.count(theme.green, x: badgeX, y: y, width: 40, height: 7), 0, "+98765 em verde")
        XCTAssertEqual(image.count(theme.green, x: 0, y: 0, width: badgeX, height: AgentCardView.height), 0)
        XCTAssertEqual(image.count(theme.red, x: tagX - 8, y: 0, width: cardWidth, height: AgentCardView.height), 0,
                       "o resumo termina antes da etiqueta")
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
