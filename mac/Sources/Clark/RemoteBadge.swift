import AppKit
import ClarkCore

/// O aviso de que o controle remoto do Claude Code está ligado, no cabeçalho e no card: `REMOTO`
/// numa etiqueta cheia.
enum RemoteBadge {
    static let label = "REMOTO"
    static let height = 11
    static let width = PixelFont.textWidth(label, scale: 1) + 8

    /// Azul do terminal: nenhum estado do agente usa essa cor.
    static func color(_ theme: Theme) -> RGB { theme.term[4] }

    /// - Parameter textY: topo do texto, a mesma linha do resumo do diff.
    static func draw(_ context: CGContext, x: Int, textY: Int, theme: Theme) {
        Pixel.fill(context, x, textY - 2, width, height, color(theme))
        Pixel.text(context, label, x + 4, textY, scale: 1, theme.bg)
    }
}
