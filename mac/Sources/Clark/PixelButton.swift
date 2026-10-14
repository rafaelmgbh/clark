import AppKit
import ClarkCore

/// Botão quadrado do original (`button.px` e `button.mini` do CSS).
final class PixelButton: PixelView {
    enum Style {
        /// Botão da barra: moldura e sombra dura.
        case normal
        /// Igual ao `normal`, na cor de destaque.
        case primary
        /// Botão chapado do cabeçalho do painel.
        case mini
        /// `mini` que fica vermelho sob o mouse.
        case miniClose
    }

    static let barHeight = 27

    var title: String { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    let style: Style
    private(set) var isHovering = false
    private(set) var isPressed = false

    init(title: String, style: Style = .normal, toolTip: String? = nil, onClick: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onClick = onClick
        super.init(frame: .zero)
        self.toolTip = toolTip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private var isMini: Bool { style == .mini || style == .miniClose }
    private var fontSize: CGFloat { isMini ? 10 : 11 }

    /// Largura que o título pede.
    var fittingWidth: Int {
        let text = Pixel.monoWidth(title, size: fontSize, bold: true)
        return isMini ? text + 18 : text + 24 + 4 + 3
    }

    // Clicar num botão não tira o foco do terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setState(hovering: true, pressed: isPressed) }
    override func mouseExited(with event: NSEvent) { setState(hovering: false, pressed: false) }
    override func mouseDown(with event: NSEvent) { setState(hovering: true, pressed: true) }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = isPressed
        setState(hovering: inside, pressed: false)
        if inside && wasPressed { onClick?() }
    }

    private func setState(hovering: Bool, pressed: Bool) {
        guard hovering != isHovering || pressed != isPressed else { return }
        isHovering = hovering
        isPressed = pressed
        needsDisplay = true
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        if isMini {
            renderMini(context, width: width, height: height)
            return
        }
        let faceWidth = width - 3, faceHeight = height - 3
        if !isPressed { Pixel.fill(context, 3, 3, faceWidth, faceHeight, theme.shadow) }
        let face: RGB
        if style == .primary {
            face = isPressed ? theme.accentLo : (isHovering ? theme.accentHi : theme.accent)
        } else {
            face = isPressed ? theme.bg5 : (isHovering ? theme.bg4 : theme.bg3)
        }
        Pixel.fill(context, 0, 0, faceWidth, faceHeight, face)
        Pixel.frame(context, 0, 0, faceWidth, faceHeight, thickness: 2, theme.shadow)
        let ink = style == .primary ? theme.onAccent : theme.ink
        drawTitle(context, x: 14, width: faceWidth - 28, height: faceHeight, ink)
    }

    private func renderMini(_ context: CGContext, width: Int, height: Int) {
        var face = theme.bg2, ink = theme.dim
        if isHovering {
            face = style == .miniClose ? theme.red : theme.bg3
            ink = style == .miniClose ? theme.onAccent : theme.ink
        }
        Pixel.fill(context, 0, 0, width, height, face)
        drawTitle(context, x: 9, width: width - 18, height: height, ink)
    }

    private func drawTitle(_ context: CGContext, x: Int, width: Int, height: Int, _ color: RGB) {
        let lineHeight = Pixel.monoLineHeight(size: fontSize, bold: true)
        Pixel.mono(context, title, x, (height - lineHeight) / 2, width: width + 1, size: fontSize, color,
                   truncate: .byTruncatingHead, bold: true)
    }
}
