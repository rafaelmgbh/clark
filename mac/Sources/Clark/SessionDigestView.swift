import AppKit
import ClarkCore

/// Faixa com o resumo da última conversa da pasta, entre o cabeçalho e o terminal do agente que
/// começa conversa nova num projeto. Um clique fecha.
final class SessionDigestView: PixelView {
    static let rowHeight = 15
    static let padding = 5
    static let label = "ULTIMA SESSAO"

    var digest: SessionDigest? { didSet { if digest != oldValue { needsDisplay = true } } }
    var onDismiss: (() -> Void)?
    /// Data de hoje, para o `HOJE` e o `ONTEM`. Trocada nos testes.
    var now: () -> Date = { Date() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Última conversa do Claude nesta pasta. Some com um clique ou quando você digita."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    /// Uma linha de título e uma por linha do corpo.
    static func height(for digest: SessionDigest) -> Int {
        2 * padding + rowHeight * (1 + digest.body.count)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2)
        Pixel.fill(context, 0, 0, 3, height, theme.accent)
        Pixel.fill(context, 0, height - 2, width, 2, theme.shadow)
        guard let digest else { return }

        let x = 12
        var y = Self.padding
        let closeX = width - 10 - PixelFont.textWidth("X", scale: 1)
        Pixel.text(context, "X", closeX, y + 4, scale: 1, theme.dim)
        Pixel.text(context, Self.label, x, y + 4, scale: 1, theme.accent)
        var textX = x + PixelFont.textWidth(Self.label, scale: 1) + 10
        let when = digest.when(now: now())
        if textX + PixelFont.textWidth(when, scale: 1) < closeX - 10 {
            Pixel.text(context, when, textX, y + 4, scale: 1, theme.dim)
            textX += PixelFont.textWidth(when, scale: 1) + 12
        }
        if let title = digest.title {
            Pixel.mono(context, title, textX, y, width: closeX - 10 - textX, size: 10, theme.ink, bold: true)
        }
        y += Self.rowHeight

        for line in digest.body {
            let color: RGB
            switch line.kind {
            case .prompt: color = theme.dim
            case .answer: color = theme.ink
            case .pending: color = theme.yellow
            }
            Pixel.mono(context, line.text, x, y, width: width - x - 10, size: 10, color)
            y += Self.rowHeight
        }
    }
}
