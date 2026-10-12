import AppKit
import ClarkCore

/// O que o cabeçalho e o card mostram de um agente.
struct AgentSnapshot: Equatable {
    var name: String
    /// Projeto da pasta do agente: o apelido, o nome da pasta arrumado ou `GLOBAL`.
    var project: String = ""
    /// Vazio no agente do `GLOBAL`, que não é de empresa nenhuma.
    var company: String
    /// Cor da empresa já no tom deste agente.
    var color: RGB
    /// Pasta de trabalho na forma curta (`~/x`).
    var path: String
    var state: AgentState
    var preview: [String] = []
    /// O que mudou no repositório da pasta. nil: sem leitura, fora de repositório ou sem mudança.
    var diff: DiffSummary? = nil
    /// O controle remoto do Claude Code está ligado na sessão do agente.
    var remoteControl = false
}

/// Cabeçalho do painel (`_draw_head` do original). O quadrado na cor da empresa ocupa o
/// lugar do mascote, que chega no M3.
final class AgentHeaderView: PixelView {
    static let height = 30
    /// Abaixo desta largura a pílula do estado encolhe para o nome e o projeto caberem.
    static let compactWidth = 420

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

    private static let square = 14

    /// Onde cada parte cai numa largura. O desenho e o clique no resumo do diff leem a mesma conta.
    private struct Layout {
        var scale = 2
        var pillX = 0
        var pillWidth = 0
        var nameX = 0
        var name = ""
        var nameScale = 2
        var projectX = 0
        /// Vazio: o agente não tem projeto ou ele não coube.
        var project = ""
        var projectScale = 2
        var companyX = 0
        /// Vazio: sem empresa, igual ao projeto ou não coube.
        var company = ""
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

        // O nome e o projeto dividem o que há até a pílula. Apertou: o projeto desce para a escala 1,
        // depois o nome, e só então o nome é cortado. Cortados, `AGENT 1` e `AGENT 2` ficariam iguais.
        var x = 8 + Self.square + 8
        let project = PixelFont.normalize(snapshot.project)
        let room = right - x
        let nameWidth = PixelFont.textWidth(snapshot.name, scale: 2)
        if !project.isEmpty, nameWidth + 14 + PixelFont.textWidth(project, scale: 2) > room {
            layout.projectScale = 1
            if nameWidth + 14 + PixelFont.textWidth(project, scale: 1) > room { layout.nameScale = 1 }
        }
        let reserved = project.isEmpty
            ? 0 : min(PixelFont.textWidth(project, scale: layout.projectScale), room / 2) + 14
        layout.nameX = x
        layout.name = PixelFont.fit(snapshot.name, scale: layout.nameScale, width: max(60, room - reserved))
        x += PixelFont.textWidth(layout.name, scale: layout.nameScale) + 14
        if !project.isEmpty, right - x >= PixelFont.textWidth("A...", scale: layout.projectScale) {
            layout.projectX = x
            layout.project = PixelFont.fit(project, scale: layout.projectScale, width: right - x)
            x += PixelFont.textWidth(layout.project, scale: layout.projectScale) + 12
        }

        // Depois do projeto: o aviso do controle remoto encostado na pílula, a empresa, o resumo do
        // diff antes do aviso e o caminho com o que sobrar. O aviso escolhe primeiro: a empresa e o
        // caminho também estão no card, e o resumo do diff, no card e no menu.
        if snapshot.remoteControl, right - RemoteBadge.width >= x {
            layout.remoteX = right - RemoteBadge.width
            right -= RemoteBadge.width + 10
        }
        // A empresa que tem o mesmo nome do projeto não se repete.
        let company = PixelFont.normalize(snapshot.company)
        let companyWidth = PixelFont.textWidth(company, scale: 1)
        if !company.isEmpty, company != project, right - x >= companyWidth {
            layout.companyX = x
            layout.company = company
            x += companyWidth + 10
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
        let square = Self.square
        Pixel.fill(context, 8, (height - square) / 2, square, square, snapshot.color)
        Pixel.frame(context, 8, (height - square) / 2, square, square, thickness: 2, snapshot.color.darkened(0.35))

        let layout = layout(width: width)
        let scale = layout.scale, pillX = layout.pillX, pillWidth = layout.pillWidth
        let pillHeight = 20
        let pillY = (height - pillHeight) / 2

        Pixel.text(context, layout.name, layout.nameX, (height - 7 * layout.nameScale) / 2, scale: layout.nameScale,
                   theme.ink, shadow: layout.nameScale == 2 ? theme.shadow : nil)
        if !layout.project.isEmpty {
            Pixel.text(context, layout.project, layout.projectX, (height - 7 * layout.projectScale) / 2,
                       scale: layout.projectScale, snapshot.color,
                       shadow: layout.projectScale == 2 ? theme.shadow : nil)
        }
        if !layout.company.isEmpty {
            Pixel.text(context, layout.company, layout.companyX, (height - 7) / 2, scale: 1, theme.dim)
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
