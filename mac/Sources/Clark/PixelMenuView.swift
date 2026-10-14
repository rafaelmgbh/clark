import AppKit
import ClarkCore

/// Um nível de menu no estilo do app: as linhas de um `NSMenu`, uma embaixo da outra, com moldura e
/// sombra dura. Quem abre, fecha e encadeia os níveis é o `PixelMenu`.
final class PixelMenuView: PixelView {
    static let border = 2
    static let shadow = 3
    /// Do alto da view até a primeira linha: a moldura e uma folga.
    static let inset = 6
    static let rowHeight = 22
    static let headerHeight = 20
    static let separatorHeight = 10
    static let textX = 12
    /// Barra de destaque à esquerda da linha sob o cursor.
    static let barWidth = 3
    static let swatchSide = 8
    static let swatchGap = 6
    /// Do canto direito da face até a seta de quem tem submenu.
    static let arrowInset = 14
    /// Folga à direita do título, onde fica a seta.
    static let trailing = 28
    static let minWidth = 180
    static let maxWidth = 440
    static let fontSize: CGFloat = 11
    /// Pontos acesos da marca de que há mais linhas: um triângulo de 7, 5, 3 e 1.
    static let markPixels = 16

    /// As linhas: os itens do menu que não estão escondidos.
    let items: [NSMenuItem]
    /// Linha sob o cursor ou escolhida pelo teclado.
    var highlighted: Int? {
        didSet {
            toolTip = highlighted.flatMap { items[$0].toolTip }
            needsDisplay = true
        }
    }
    /// Quanto do conteúdo já rolou para cima.
    private(set) var offset = 0
    /// O mouse passou a uma linha que pode ser escolhida, ou saiu de todas.
    var onHover: ((Int?) -> Void)?
    var onChoose: ((Int) -> Void)?

    /// Por linha, onde ela começa no conteúdo, contado da primeira.
    private let starts: [Int]
    let contentHeight: Int
    /// Largura que as linhas pedem, com a sombra.
    let fittingWidth: Int
    /// Onde o título começa: recua quando alguma linha tem imagem.
    let titleX: Int

    /// Quadradinho de cor para a frente de uma linha: a imagem do item.
    static func swatch(_ color: RGB) -> NSImage {
        let side = CGFloat(swatchSide)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.nsColor.setFill()
            rect.fill()
            return true
        }
    }

    init(items: [NSMenuItem]) {
        let rows = items.filter { !$0.isHidden }
        self.items = rows
        var starts: [Int] = [], total = 0
        for item in rows {
            starts.append(total)
            total += Self.height(of: item)
        }
        self.starts = starts
        contentHeight = total
        let titleX = rows.contains { $0.image != nil } ? Self.textX + Self.swatchSide + Self.swatchGap : Self.textX
        self.titleX = titleX
        let widest = rows.map { item -> Int in
            if item.isSeparatorItem { return 0 }
            if item.isSectionHeader { return 2 * Self.textX + PixelFont.textWidth(item.title, scale: 1) }
            return titleX + Pixel.monoWidth(item.title, size: Self.fontSize, bold: true) + Self.trailing
        }.max() ?? 0
        fittingWidth = min(Self.maxWidth, max(Self.minWidth, widest)) + Self.shadow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private static func height(of item: NSMenuItem) -> Int {
        if item.isSeparatorItem { return separatorHeight }
        return item.isSectionHeader ? headerHeight : rowHeight
    }

    /// Por linha, se ela pode ser escolhida. Cabeçalho, separador e item desligado não podem.
    var selectable: [Bool] {
        items.map { !$0.isSeparatorItem && !$0.isSectionHeader && $0.isEnabled }
    }

    /// Altura que as linhas pedem, com a moldura e a sombra.
    var fittingHeight: Int { contentHeight + 2 * Self.inset + Self.shadow }

    /// Quanto do conteúdo aparece na altura que a view tem.
    var visibleHeight: Int { max(0, Int(bounds.height) - 2 * Self.inset - Self.shadow) }

    private var maxOffset: Int { max(0, contentHeight - visibleHeight) }

    /// Onde a linha começa na view, contado de cima.
    func top(of row: Int) -> Int { Self.inset + starts[row] - offset }

    /// A linha que pode ser escolhida na altura `y` da view.
    func row(atY y: Int) -> Int? {
        guard y >= Self.inset, y < Self.inset + visibleHeight else { return nil }
        let position = y - Self.inset + offset
        guard let row = starts.lastIndex(where: { $0 <= position }),
              position < starts[row] + Self.height(of: items[row]), selectable[row] else { return nil }
        return row
    }

    /// Rola o mínimo para a linha aparecer inteira.
    func reveal(row: Int) {
        scroll(to: MenuNavigation.scroll(showing: starts[row], height: Self.height(of: items[row]), offset: offset,
                                         visible: visibleHeight))
    }

    func scroll(by delta: Int) { scroll(to: offset + delta) }

    private func scroll(to target: Int) {
        let clamped = min(maxOffset, max(0, target))
        guard clamped != offset else { return }
        offset = clamped
        needsDisplay = true
    }

    // MARK: mouse

    // Como os botões: clicar no menu não tira o foco do terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `activeAlways`: o painel do menu nunca é a janela principal.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x >= 0, Int(point.x) < Int(bounds.width) - Self.shadow else { return nil }
        return row(atY: Int(point.y))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(row(at: event)) }
    override func mouseMoved(with event: NSEvent) { onHover?(row(at: event)) }
    // O clique sem movimento antes, com o cursor já parado onde o menu abriu, também destaca a linha.
    override func mouseDown(with event: NSEvent) { onHover?(row(at: event)) }
    // Apertar no botão PROJETO, arrastar e soltar na linha também escolhe.
    override func mouseDragged(with event: NSEvent) { onHover?(row(at: event)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    override func mouseUp(with event: NSEvent) {
        if let row = row(at: event) { onChoose?(row) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY
            : event.scrollingDeltaY * CGFloat(Self.rowHeight)
        scroll(by: -Int(delta.rounded()))
        onHover?(row(at: event))
    }

    // MARK: desenho

    override func render(_ context: CGContext, width: Int, height: Int) {
        let faceWidth = width - Self.shadow, faceHeight = height - Self.shadow
        Pixel.fill(context, Self.shadow, Self.shadow, faceWidth, faceHeight, theme.shadow)
        Pixel.fill(context, 0, 0, faceWidth, faceHeight, theme.bg2)
        Pixel.frame(context, 0, 0, faceWidth, faceHeight, thickness: Self.border, theme.shadow)

        let visible = max(0, faceHeight - 2 * Self.inset)
        context.saveGState()
        context.clip(to: CGRect(x: Self.border, y: Self.inset, width: faceWidth - 2 * Self.border, height: visible))
        for (row, item) in items.enumerated() {
            let top = top(of: row)
            guard top < Self.inset + visible, top + Self.height(of: item) > Self.inset else { continue }
            render(context, item, top: top, faceWidth: faceWidth, isHighlighted: row == highlighted)
        }
        context.restoreGState()

        let markX = faceWidth - Self.border - 12
        if offset > 0 { renderMark(context, x: markX, y: Self.inset, pointingUp: true) }
        if offset < contentHeight - visible {
            renderMark(context, x: markX, y: Self.inset + visible - 6, pointingUp: false)
        }
    }

    private func render(_ context: CGContext, _ item: NSMenuItem, top: Int, faceWidth: Int, isHighlighted: Bool) {
        if item.isSeparatorItem {
            Pixel.fill(context, Self.textX, top + (Self.separatorHeight - Self.border) / 2,
                       faceWidth - 2 * Self.textX, Self.border, theme.shadow)
            return
        }
        if item.isSectionHeader {
            Pixel.text(context, item.title, Self.textX, top + (Self.headerHeight - PixelFont.rows) / 2, scale: 1,
                       theme.dim)
            return
        }
        if isHighlighted {
            Pixel.fill(context, Self.border, top, faceWidth - 2 * Self.border, Self.rowHeight, theme.bg4)
            Pixel.fill(context, Self.border, top, Self.barWidth, Self.rowHeight, theme.accent)
        }
        item.image?.draw(in: NSRect(x: Self.textX, y: top + (Self.rowHeight - Self.swatchSide) / 2,
                                    width: Self.swatchSide, height: Self.swatchSide),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let lineHeight = Pixel.monoLineHeight(size: Self.fontSize, bold: true)
        Pixel.mono(context, item.title, titleX, top + (Self.rowHeight - lineHeight) / 2,
                   width: faceWidth - titleX - Self.trailing + 1, size: Self.fontSize,
                   item.isEnabled ? theme.ink : theme.dim, bold: true)
        if item.hasSubmenu {
            Pixel.text(context, ">", faceWidth - Self.arrowInset, top + (Self.rowHeight - PixelFont.rows) / 2,
                       scale: 1, isHighlighted ? theme.ink : theme.dim)
        }
    }

    /// Triângulo que avisa que há mais linhas para o lado em que aponta, sobre um fundo que o destaca
    /// do que estiver embaixo.
    private func renderMark(_ context: CGContext, x: Int, y: Int, pointingUp: Bool) {
        Pixel.fill(context, x - 2, y, 11, 6, theme.bg2)
        for step in 0..<4 {
            let line = pointingUp ? 3 - step : step
            Pixel.fill(context, x + line, y + 1 + step, 7 - 2 * line, 1, theme.accent)
        }
    }
}
