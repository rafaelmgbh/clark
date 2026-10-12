import AppKit
import ClarkCore

/// O que o cabeçalho e o card mostram de um agente.
struct AgentSnapshot: Equatable {
    var name: String
    var company: String
    /// Cor da empresa já no tom deste agente.
    var color: RGB
    /// Pasta de trabalho na forma curta (`~/x`).
    var path: String
    var state: AgentState
    var preview: [String] = []
}

/// Cabeçalho do painel (`_draw_head` do original). O quadrado na cor da empresa ocupa o
/// lugar do mascote, que chega no M3.
final class AgentHeaderView: PixelView {
    static let height = 30

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

        var x = 8 + square + 8
        let name = PixelFont.fit(snapshot.name, scale: 2, width: max(60, width - x - 200))
        Pixel.text(context, name, x, (height - 14) / 2, scale: 2, theme.ink, shadow: theme.shadow)
        x += PixelFont.textWidth(name, scale: 2) + 14

        let scale = width < 300 ? 1 : 2
        let pillWidth = PixelFont.textWidth("WORKING...", scale: scale) + 16
        let pillHeight = 20
        let pillX = width - pillWidth - 6
        let pillY = (height - pillHeight) / 2

        let companyWidth = PixelFont.textWidth(snapshot.company, scale: 1)
        if pillX - x - 10 >= companyWidth {
            Pixel.text(context, snapshot.company, x, (height - 7) / 2, scale: 1, snapshot.color)
            x += companyWidth + 10
        }
        let room = pillX - x - 10
        if room > 60 {
            Pixel.mono(context, snapshot.path, x, (height - 12) / 2, width: room, size: 9, theme.dim,
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
