import AppKit
import ClarkCore

/// O resumo do diff no cabeçalho e no card: `+12 -3 4 ARQ`, cada parte na sua cor.
enum DiffBadge {
    static func width(_ summary: DiffSummary) -> Int {
        PixelFont.textWidth(summary.label, scale: 1)
    }

    static func draw(_ context: CGContext, _ summary: DiffSummary, x: Int, y: Int, theme: Theme) {
        var x = x
        for (text, color) in [(summary.addedLabel, theme.green), (summary.removedLabel, theme.red),
                              (summary.filesLabel, theme.dim)] {
            Pixel.text(context, text, x, y, scale: 1, color)
            // A parte e o espaço que a separa da próxima, como no rótulo inteiro.
            x += (text.count + 1) * PixelFont.advance
        }
    }
}
