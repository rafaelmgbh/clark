import AppKit
import ClarkCore

/// Desenho em pixels inteiros, com a origem no canto superior esquerdo.
enum Pixel {
    static func fill(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
                     _ color: RGB, alpha: Double = 1) {
        guard width > 0, height > 0 else { return }
        context.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha))
        context.fill(CGRect(x: x, y: y, width: width, height: height))
    }

    /// Moldura por dentro do retângulo.
    static func frame(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
                      thickness: Int, _ color: RGB) {
        fill(context, x, y, width, thickness, color)
        fill(context, x, y + height - thickness, width, thickness, color)
        fill(context, x, y, thickness, height, color)
        fill(context, x + width - thickness, y, thickness, height, color)
    }

    /// Texto na fonte pixel (`draw_text` do original). A sombra sai deslocada de `scale`.
    static func text(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, scale: Int,
                     _ color: RGB, shadow: RGB? = nil) {
        let pixels = PixelFont.pixels(text)
        if let shadow {
            context.setFillColor(shadow.cgColor)
            for pixel in pixels {
                context.fill(CGRect(x: x + (pixel.x + 1) * scale, y: y + (pixel.y + 1) * scale,
                                    width: scale, height: scale))
            }
        }
        context.setFillColor(color.cgColor)
        for pixel in pixels {
            context.fill(CGRect(x: x + pixel.x * scale, y: y + pixel.y * scale, width: scale, height: scale))
        }
    }

    static func monoFont(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .heavy : .regular)
    }

    static func monoWidth(_ text: String, size: CGFloat, bold: Bool = false) -> Int {
        Int((text as NSString).size(withAttributes: [.font: monoFont(size: size, bold: bold)]).width.rounded(.up))
    }

    /// Texto na fonte monoespaçada do sistema, para o que tem acento ou minúscula: caminhos e
    /// linhas do terminal. Uma linha só, cortada com reticências.
    static func mono(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, width: Int, size: CGFloat,
                     _ color: RGB, truncate: NSLineBreakMode = .byTruncatingTail, bold: Bool = false) {
        guard width > 0, !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = truncate
        let font = monoFont(size: size, bold: bold)
        let height = (font.ascender - font.descender + font.leading).rounded(.up)
        context.saveGState()
        context.setShouldAntialias(true)
        (text as NSString).draw(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: height),
                                withAttributes: [.font: font, .foregroundColor: color.nsColor,
                                                 .paragraphStyle: style])
        context.restoreGState()
    }
}

/// View desenhada à mão: coordenadas inteiras, origem em cima à esquerda, sem suavização.
class PixelView: NSView {
    var theme = Theme.dark { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(false)
        render(context, width: Int(bounds.width), height: Int(bounds.height))
        context.restoreGState()
    }

    /// Desenho da view. Chamado pelo `draw` e pelos testes, que desenham num bitmap.
    func render(_ context: CGContext, width: Int, height: Int) {}
}

/// Rótulo e cor de cada estado, iguais no cabeçalho e no card.
enum StateLabel {
    static func text(_ state: AgentState, time: Double) -> String {
        let dots = String(repeating: ".", count: Int(time * 4) % 4)
        switch state {
        case .boot: return "BOOT" + dots
        case .working: return "WORKING" + dots
        case .idle: return "IDLE"
        case .shell: return "SHELL" + dots
        case .done: return "DONE!"
        case .exited: return "GAME OVER"
        }
    }

    static func color(_ state: AgentState, theme: Theme) -> RGB {
        switch state {
        case .boot, .done: return theme.yellow
        case .working: return theme.green
        case .idle: return theme.dim
        // Ciano do terminal: a cor em que o Claude Code escreve `1 shell` no rodapé.
        case .shell: return theme.term[6]
        case .exited: return theme.red
        }
    }

    /// Estados cujo desenho muda com o tempo e pedem redesenho a cada tique.
    static func isAnimated(_ state: AgentState) -> Bool {
        state == .boot || state == .working || state == .done || state == .shell
    }
}
