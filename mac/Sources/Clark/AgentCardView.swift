import AppKit
import ClarkCore

/// Card do agente na lista lateral (`AgentCard` do original).
final class AgentCardView: PixelView {
    static let height = 104
    /// Linha do estado e do projeto.
    static let projectY = 30
    /// Linha da empresa, do caminho e do diff.
    static let detailY = 52
    /// Primeira das duas linhas da prévia do terminal.
    static let previewY = 66

    var snapshot: AgentSnapshot { didSet { if snapshot != oldValue { needsDisplay = true } } }
    /// Posição do agente, a partir de 1. Até 9 aparece no canto: é o número do atalho ⌘N.
    var index = 1 { didSet { if index != oldValue { needsDisplay = true } } }
    /// É o agente do painel principal.
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isHovering = false

    init(snapshot: AgentSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Retângulo do botão de fechar, que só existe com o mouse em cima do card.
    static func closeRect(width: Int) -> CGRect {
        CGRect(x: width - 26, y: 4, width: 22, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isHovering && Self.closeRect(width: Int(bounds.width)).contains(point) {
            onClose?()
        } else {
            onSelect?()
        }
    }

    // Botão do meio fecha, como no original.
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        let base = isHovering ? theme.bg3 : theme.bg2
        let background = isActive ? base.mix(theme.accent, 0.18) : base
        Pixel.fill(context, 0, 0, width, height, background)

        var edge: (color: RGB, thickness: Int)?
        if snapshot.state == .done {
            if Int(time * 3) % 2 == 0 { edge = (theme.yellow, 2) }
        } else if snapshot.state == .exited {
            edge = (theme.red, 2)
        } else if isActive {
            edge = (theme.accent, 3)
        }
        if let edge {
            Pixel.fill(context, 0, 0, width, edge.thickness, edge.color)
            Pixel.fill(context, 0, height - edge.thickness, width, edge.thickness, edge.color)
            Pixel.fill(context, width - edge.thickness, 0, edge.thickness, height, edge.color)
        }
        Pixel.fill(context, 0, 0, isActive ? 6 : 4, height, snapshot.color)

        let x = 14
        let tagWidth = PixelFont.textWidth("EM FOCO", scale: 1)
        var reserved = 24
        if isHovering {
            let close = Self.closeRect(width: width)
            Pixel.fill(context, Int(close.minX), Int(close.minY), Int(close.width), Int(close.height), theme.red)
            Pixel.text(context, "X", Int(close.minX) + 6, Int(close.minY) + 3, scale: 2, theme.bg)
            reserved = 34
        } else if isActive {
            Pixel.fill(context, width - tagWidth - 14, 6, tagWidth + 8, 13, theme.accent)
            Pixel.text(context, "EM FOCO", width - tagWidth - 10, 9, scale: 1, theme.onAccent)
            reserved = tagWidth + 20
        } else if index <= 9 {
            Pixel.text(context, String(index), width - 16, 10, scale: 1, theme.dim)
        }

        let name = PixelFont.fit(snapshot.name, scale: 2, width: width - x - reserved)
        Pixel.text(context, name, x, 10, scale: 2, isActive ? theme.accent : theme.ink, shadow: theme.shadow)

        // Segunda linha: o estado e o projeto, grande enquanto couber.
        let stateColor = StateLabel.color(snapshot.state, theme: theme)
        Pixel.fill(context, x, Self.projectY + 5, 5, 5, stateColor)
        Pixel.text(context, StateLabel.text(snapshot.state, time: time), x + 9, Self.projectY + 4, scale: 1,
                   stateColor)
        let projectX = x + 9 + PixelFont.textWidth("WORKING...", scale: 1) + 10
        var limit = width - 8
        let project = PixelFont.normalize(snapshot.project)
        if !project.isEmpty {
            let scale = PixelFont.textWidth(project, scale: 2) <= limit - projectX ? 2 : 1
            Pixel.text(context, PixelFont.fit(project, scale: scale, width: limit - projectX), projectX,
                       Self.projectY + (scale == 2 ? 0 : 4), scale: scale, snapshot.color)
        }

        // Terceira linha: a empresa, o caminho e, na ponta direita, o resumo do diff.
        var pathX = x
        let company = PixelFont.normalize(snapshot.company)
        let companyWidth = PixelFont.textWidth(company, scale: 1)
        if !company.isEmpty, company != project, pathX + companyWidth < limit {
            Pixel.text(context, company, pathX, Self.detailY, scale: 1, theme.dim)
            pathX += companyWidth + 8
        }
        if let diff = snapshot.diff {
            let badgeWidth = DiffBadge.width(diff)
            if limit - badgeWidth > pathX {
                DiffBadge.draw(context, diff, x: limit - badgeWidth, y: Self.detailY, theme: theme)
                limit -= badgeWidth + 8
            }
        }
        Pixel.mono(context, snapshot.path, pathX, Self.detailY - 3, width: limit - pathX, size: 9,
                   theme.dim.mix(background, 0.3), truncate: .byTruncatingHead)

        let lines = snapshot.preview.isEmpty ? ["…"] : snapshot.preview
        for (row, line) in lines.prefix(2).enumerated() {
            Pixel.mono(context, line, x, Self.previewY + row * 16, width: width - x - 10, size: 10,
                       isActive ? theme.ink : theme.dim)
        }
    }
}
