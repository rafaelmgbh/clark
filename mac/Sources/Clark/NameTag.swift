import AppKit
import ClarkCore

/// Etiqueta do cabeçalho do agente, no desenho dos botões da barra: face, moldura e sombra dura.
enum NameTag {
    /// Altura da face, a mesma da pílula do estado. A sombra desce mais `shadow` pontos.
    static let height = 20
    static let shadow = 3

    private static func fontSize(compact: Bool) -> CGFloat { compact ? 10 : 11 }
    private static func padding(compact: Bool) -> Int { compact ? 6 : 9 }

    /// Largura da face. Sem texto, o quadrado que só mostra a cor.
    static func width(_ text: String, compact: Bool) -> Int {
        guard !text.isEmpty else { return height }
        return Pixel.monoWidth(text, size: fontSize(compact: compact), bold: true) + 2 * padding(compact: compact)
    }

    /// A letra que mais contrasta com a face: a cor de uma empresa pode ser clara ou escura.
    static func ink(on face: RGB, theme: Theme) -> RGB {
        theme.onAccent.contrast(face) >= theme.ink.contrast(face) ? theme.onAccent : theme.ink
    }

    /// - Parameters:
    ///   - width: largura da face. Menor que a do texto, o texto é cortado com reticências.
    ///   - truncate: de que lado o texto perde letras quando não cabe.
    static func draw(_ context: CGContext, _ text: String, x: Int, y: Int, width: Int, face: RGB, compact: Bool,
                     truncate: NSLineBreakMode = .byTruncatingTail, theme: Theme) {
        Pixel.fill(context, x + shadow, y + shadow, width, height, theme.shadow)
        Pixel.fill(context, x, y, width, height, face)
        Pixel.frame(context, x, y, width, height, thickness: 2, theme.shadow)
        let size = fontSize(compact: compact), padding = padding(compact: compact)
        let lineHeight = Pixel.monoLineHeight(size: size, bold: true)
        Pixel.mono(context, text, x + padding, y + (height - lineHeight) / 2, width: width - 2 * padding + 1,
                   size: size, ink(on: face, theme: theme), truncate: truncate, bold: true)
    }
}
