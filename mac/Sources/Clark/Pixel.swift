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

    /// Largura do texto na fonte monoespaçada. Sem fonte nenhuma, a de 0,6 do tamanho por letra.
    static func monoWidth(_ text: String, size: CGFloat, bold: Bool = false, fonts: MonoFonts = .shared) -> Int {
        guard let font = fonts.font(size: size, bold: bold) else {
            return Int((size * 0.6 * CGFloat(text.count)).rounded(.up))
        }
        return Int((text as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
    }

    /// Altura da linha na fonte monoespaçada. Sem fonte nenhuma, 1,2 do tamanho.
    static func monoLineHeight(size: CGFloat, bold: Bool = false, fonts: MonoFonts = .shared) -> Int {
        Int(lineHeight(fonts.font(size: size, bold: bold), size: size).rounded(.up))
    }

    private static func lineHeight(_ font: NSFont?, size: CGFloat) -> CGFloat {
        font.map { $0.ascender - $0.descender + $0.leading } ?? size * 1.2
    }

    /// Texto na fonte monoespaçada do sistema, para o que tem acento ou minúscula: caminhos e
    /// linhas do terminal. Uma linha só, cortada com reticências.
    static func mono(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, width: Int, size: CGFloat,
                     _ color: RGB, truncate: NSLineBreakMode = .byTruncatingTail, bold: Bool = false,
                     fonts: MonoFonts = .shared) {
        guard width > 0, !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = truncate
        let font = fonts.font(size: size, bold: bold)
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color.nsColor, .paragraphStyle: style]
        attributes[.font] = font
        context.saveGState()
        context.setShouldAntialias(true)
        (text as NSString).draw(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width),
                                           height: lineHeight(font, size: size).rounded(.up)),
                                withAttributes: attributes)
        context.restoreGState()
    }
}

/// A fonte monoespaçada do sistema, uma por tamanho e peso.
///
/// O `monospacedSystemFont` já devolveu nil, embora o Swift o importe como não opcional: o nil entrou
/// calado nos atributos do texto e o CoreText derrubou o app ao medir um botão. A fonte que vem certa
/// fica guardada e não é pedida de novo. Sem ela vale a reserva, e a do sistema é pedida outra vez na
/// próxima chamada.
final class MonoFonts {
    typealias Source = (_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont?

    static let shared = MonoFonts(system: MonoFonts.systemFont, fallback: MonoFonts.fixedPitchFont)

    private struct Key: Hashable {
        let size: CGFloat
        let bold: Bool
    }

    private let system: Source
    private let fallback: Source
    private var fonts: [Key: NSFont] = [:]
    private let lock = NSLock()

    init(system: @escaping Source, fallback: @escaping Source) {
        self.system = system
        self.fallback = fallback
    }

    /// nil só quando nem a reserva existe.
    func font(size: CGFloat, bold: Bool) -> NSFont? {
        let key = Key(size: size, bold: bold), weight: NSFont.Weight = bold ? .heavy : .regular
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[key] { return font }
        guard let font = system(size, weight) else { return fallback(size, weight) }
        fonts[key] = font
        return font
    }

    /// `monospacedSystemFont` chamado pela implementação, com o retorno opcional: pela chamada comum,
    /// o Swift trata o resultado como se nunca fosse nil.
    static func systemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        typealias Implementation = @convention(c) (AnyObject, Selector, CGFloat, CGFloat) -> NSFont?
        let selector = #selector(NSFont.monospacedSystemFont(ofSize:weight:))
        guard let method = class_getClassMethod(NSFont.self, selector) else { return nil }
        let call = unsafeBitCast(method_getImplementation(method), to: Implementation.self)
        return call(NSFont.self, selector, size, weight.rawValue)
    }

    static func fixedPitchFont(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        NSFont(name: weight == .regular ? "Menlo-Regular" : "Menlo-Bold", size: size)
            ?? NSFont.userFixedPitchFont(ofSize: size)
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
