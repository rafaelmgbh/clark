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
    var menuProvider: (() -> NSMenu?)?

    init(snapshot: AgentSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2)
        let square = 14
        Pixel.fill(context, 8, (height - square) / 2, square, square, snapshot.color)
        Pixel.frame(context, 8, (height - square) / 2, square, square, thickness: 2, snapshot.color.darkened(0.35))

        let scale = width < Self.compactWidth ? 1 : 2
        let pillWidth = PixelFont.textWidth("WORKING...", scale: scale) + 16
        let pillHeight = 20
        let pillX = width - pillWidth - 6
        let pillY = (height - pillHeight) / 2
        var right = pillX - 10

        // O nome e o projeto dividem o que há até a pílula. Apertou: o projeto desce para a escala 1,
        // depois o nome, e só então o nome é cortado. Cortados, `AGENT 1` e `AGENT 2` ficariam iguais.
        var x = 8 + square + 8
        let project = PixelFont.normalize(snapshot.project)
        let room = right - x
        let nameWidth = PixelFont.textWidth(snapshot.name, scale: 2)
        var nameScale = 2, projectScale = 2
        if !project.isEmpty, nameWidth + 14 + PixelFont.textWidth(project, scale: 2) > room {
            projectScale = 1
            if nameWidth + 14 + PixelFont.textWidth(project, scale: 1) > room { nameScale = 1 }
        }
        let reserved = project.isEmpty ? 0 : min(PixelFont.textWidth(project, scale: projectScale), room / 2) + 14
        let name = PixelFont.fit(snapshot.name, scale: nameScale, width: max(60, room - reserved))
        Pixel.text(context, name, x, (height - 7 * nameScale) / 2, scale: nameScale, theme.ink,
                   shadow: nameScale == 2 ? theme.shadow : nil)
        x += PixelFont.textWidth(name, scale: nameScale) + 14
        if !project.isEmpty, right - x >= PixelFont.textWidth("A...", scale: projectScale) {
            let shown = PixelFont.fit(project, scale: projectScale, width: right - x)
            Pixel.text(context, shown, x, (height - 7 * projectScale) / 2, scale: projectScale, snapshot.color,
                       shadow: projectScale == 2 ? theme.shadow : nil)
            x += PixelFont.textWidth(shown, scale: projectScale) + 12
        }

        // Depois do projeto: a empresa, o resumo do diff encostado na pílula se couber, e o caminho
        // com o que sobrar. A empresa que tem o mesmo nome do projeto não se repete.
        let company = PixelFont.normalize(snapshot.company)
        let companyWidth = PixelFont.textWidth(company, scale: 1)
        if !company.isEmpty, company != project, right - x >= companyWidth {
            Pixel.text(context, company, x, (height - 7) / 2, scale: 1, theme.dim)
            x += companyWidth + 10
        }
        if let diff = snapshot.diff {
            let badgeWidth = DiffBadge.width(diff)
            if right - badgeWidth >= x {
                DiffBadge.draw(context, diff, x: right - badgeWidth, y: (height - 7) / 2, theme: theme)
                right -= badgeWidth + 10
            }
        }
        if right - x > 60 {
            Pixel.mono(context, snapshot.path, x, (height - 12) / 2, width: right - x, size: 9, theme.dim,
                       truncate: .byTruncatingHead)
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
