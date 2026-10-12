import AppKit
import ClarkCore

/// O que o cabeçalho e o card mostram de um agente.
struct AgentSnapshot: Equatable {
    var name: String
    /// Projeto da pasta do agente: o apelido, o nome da pasta arrumado ou `GLOBAL`.
    var project: String = ""
    /// Vazio no agente da home, que não é de empresa nenhuma: o cabeçalho mostra `GLOBAL`.
    var company: String
    /// Cor da empresa já no tom deste agente: a faixa e o projeto no card.
    var color: RGB
    /// Cor da empresa, igual em todos os agentes dela: a etiqueta no cabeçalho.
    var companyColor: RGB
    /// Pasta de trabalho na forma curta (`~/x`).
    var path: String
    var state: AgentState
    var preview: [String] = []
    /// O que mudou no repositório da pasta. nil: sem leitura, fora de repositório ou sem mudança.
    var diff: DiffSummary? = nil
    /// O controle remoto do Claude Code está ligado na sessão do agente.
    var remoteControl = false
}

/// Cabeçalho do painel (`_draw_head` do original). Três etiquetas dizem de quem é o agente, da
/// esquerda para a direita: a empresa na cor dela, o projeto e o nome do agente.
final class AgentHeaderView: PixelView {
    static let height = 30
    /// Abaixo desta largura a pílula do estado e as etiquetas encolhem.
    static let compactWidth = 420

    /// Uma etiqueta do cabeçalho e onde ela cai.
    struct Tag: Equatable {
        enum Kind { case company, project, agent }

        var kind: Kind
        var x: Int
        /// Largura da face. Menor que a do texto: o desenho corta o texto com reticências.
        var width: Int
        /// Vazio na empresa que virou o quadrado da cor.
        var text: String
    }

    var snapshot: AgentSnapshot { didSet { if snapshot != oldValue { needsDisplay = true } } }
    /// Relógio das animações, em segundos.
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Clique no resumo do diff. Sem quem ouça, o resumo é só mais um pedaço do cabeçalho.
    var onBadgeClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    init(snapshot: AgentSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // No resumo todo clique vale por um: o segundo de um duplo clique fecha o que o primeiro abriu.
        if let onBadgeClick, badgeRect?.contains(convert(event.locationInWindow, from: nil)) == true {
            onBadgeClick()
        } else if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    /// Área de clique do resumo do diff: a altura inteira do cabeçalho e uma folga dos lados.
    /// nil quando o resumo não está na tela.
    var badgeRect: NSRect? {
        guard let diff = snapshot.diff, let x = layout(width: Int(bounds.width)).badgeX else { return nil }
        return NSRect(x: CGFloat(x - 5), y: 0, width: CGFloat(DiffBadge.width(diff) + 10), height: bounds.height)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    private static let tagX = 8
    /// Entre duas etiquetas: a sombra da primeira e 5 pontos de folga.
    private static let tagGap = 8

    /// As etiquetas que cabem nesta largura.
    func tags(width: Int) -> [Tag] {
        layout(width: width).tags
    }

    /// As etiquetas que cabem até `limit`. Apertou, nesta ordem: a empresa vira o quadrado da cor
    /// dela, que já diz qual é; o projeto é cortado e depois sai; o quadrado sai; e só no fim o nome
    /// do agente é cortado, pelo começo. Cortados pelo fim, `AGENT 1` e `AGENT 2` ficariam iguais.
    private func tags(limit: Int, compact: Bool) -> [Tag] {
        func width(_ text: String) -> Int { NameTag.width(text, compact: compact) }
        let company = snapshot.company.isEmpty ? ProjectNaming.global : snapshot.company.uppercased()
        let project = snapshot.project.uppercased()
        let agent = snapshot.name.uppercased()
        // O projeto que tem o mesmo nome da empresa não se repete.
        let hasProject = !project.isEmpty && project != company
        let gap = Self.tagGap, square = NameTag.height, room = limit - Self.tagX

        var parts: [(kind: Tag.Kind, text: String, width: Int)]
        let whole = width(company) + gap + (hasProject ? width(project) + gap : 0) + width(agent)
        let projectRoom = room - square - gap - gap - width(agent)
        if whole <= room {
            parts = [(.company, company, width(company)), (.project, project, width(project)),
                     (.agent, agent, width(agent))]
        } else if hasProject, projectRoom >= width("A…") {
            parts = [(.company, "", square), (.project, project, min(width(project), projectRoom)),
                     (.agent, agent, width(agent))]
        } else if square + gap + width(agent) <= room {
            parts = [(.company, "", square), (.agent, agent, width(agent))]
        } else {
            parts = [(.agent, agent, max(square, min(width(agent), room)))]
        }
        if !hasProject { parts.removeAll { $0.kind == .project } }

        var x = Self.tagX
        return parts.map { part in
            defer { x += part.width + gap }
            return Tag(kind: part.kind, x: x, width: part.width, text: part.text)
        }
    }

    /// Onde cada parte cai numa largura. O desenho e o clique no resumo do diff leem a mesma conta.
    private struct Layout {
        var scale = 2
        var pillX = 0
        var pillWidth = 0
        var tags: [Tag] = []
        /// nil: controle remoto desligado ou o aviso não coube.
        var remoteX: Int?
        /// nil: sem resumo do diff ou ele não coube.
        var badgeX: Int?
        var pathX = 0
        var pathWidth = 0
    }

    private func layout(width: Int) -> Layout {
        var layout = Layout()
        layout.scale = width < Self.compactWidth ? 1 : 2
        layout.pillWidth = PixelFont.textWidth("WORKING...", scale: layout.scale) + 16
        layout.pillX = width - layout.pillWidth - 6
        var right = layout.pillX - 10

        // As etiquetas escolhem primeiro: são elas que dizem qual é o agente.
        layout.tags = tags(limit: right, compact: layout.scale == 1)
        let x = layout.tags.last.map { $0.x + $0.width + NameTag.shadow + 9 } ?? Self.tagX

        // Depois das etiquetas: o aviso do controle remoto encostado na pílula, o resumo do diff antes
        // do aviso e o caminho com o que sobrar. O aviso escolhe primeiro: o caminho também está no
        // card, e o resumo do diff, no card e no menu.
        if snapshot.remoteControl, right - RemoteBadge.width >= x {
            layout.remoteX = right - RemoteBadge.width
            right -= RemoteBadge.width + 10
        }
        if let diff = snapshot.diff {
            let badgeWidth = DiffBadge.width(diff)
            if right - badgeWidth >= x {
                layout.badgeX = right - badgeWidth
                right -= badgeWidth + 10
            }
        }
        layout.pathX = x
        layout.pathWidth = right - x
        return layout
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2)

        let layout = layout(width: width)
        let scale = layout.scale, pillX = layout.pillX, pillWidth = layout.pillWidth
        let pillHeight = 20
        let pillY = (height - pillHeight) / 2

        for tag in layout.tags {
            // Só a empresa leva cor. O nome do agente cortado guarda o fim, que é o que o distingue.
            NameTag.draw(context, tag.text, x: tag.x, y: (height - NameTag.height) / 2, width: tag.width,
                         face: tag.kind == .company ? snapshot.companyColor : theme.bg3, compact: scale == 1,
                         truncate: tag.kind == .agent ? .byTruncatingHead : .byTruncatingTail, theme: theme)
        }
        if let diff = snapshot.diff, let badgeX = layout.badgeX {
            DiffBadge.draw(context, diff, x: badgeX, y: (height - 7) / 2, theme: theme)
        }
        if let remoteX = layout.remoteX {
            RemoteBadge.draw(context, x: remoteX, textY: (height - 7) / 2, theme: theme)
        }
        if layout.pathWidth > 60 {
            Pixel.mono(context, snapshot.path, layout.pathX, (height - 12) / 2, width: layout.pathWidth, size: 9,
                       theme.dim, truncate: .byTruncatingHead)
        }

        let label = StateLabel.text(snapshot.state, time: time)
        let color = StateLabel.color(snapshot.state, theme: theme)
        let textY = pillY + (pillHeight - 7 * scale) / 2
        if snapshot.state == .done && Int(time * 3) % 2 == 0 {
            Pixel.fill(context, pillX, pillY, pillWidth, pillHeight, color)
            Pixel.text(context, label, pillX + 8, textY, scale: scale, theme.bg)
        } else {
            Pixel.fill(context, pillX, pillY, pillWidth, pillHeight, color, alpha: 0.15)
            Pixel.frame(context, pillX, pillY, pillWidth, pillHeight, thickness: 2, color)
            Pixel.text(context, label, pillX + 8, textY, scale: scale, color)
        }
    }
}
