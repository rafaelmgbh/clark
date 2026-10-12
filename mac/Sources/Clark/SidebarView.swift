import AppKit
import ClarkCore

/// Lista lateral do modo foco: um card por agente, na ordem dos agentes.
final class SidebarView: PixelView {
    static let width = 310
    private static let headHeight = 30
    private static let spacing = 3

    let closeAllButton = PixelButton(title: "FECHAR TODOS", style: .miniClose,
                                     toolTip: "Fechar os outros agentes (ou todos)")
    private(set) var cards: [AgentCardView] = []
    private let scroll = NSScrollView()
    private let list = FlippedView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        addSubview(scroll)
        addSubview(closeAllButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet {
            closeAllButton.theme = theme
            cards.forEach { $0.theme = theme }
        }
    }

    /// Troca os cards pelos da lista, na ordem dada.
    func setCards(_ newCards: [AgentCardView]) {
        cards.forEach { $0.removeFromSuperview() }
        cards = newCards
        for card in cards {
            card.theme = theme
            list.addSubview(card)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = Int(bounds.width), height = Int(bounds.height)
        let buttonWidth = closeAllButton.fittingWidth
        closeAllButton.frame = NSRect(x: width - buttonWidth, y: 0, width: buttonWidth, height: Self.headHeight)
        scroll.frame = NSRect(x: 3, y: Self.headHeight, width: width - 3, height: max(0, height - Self.headHeight))
        let cardWidth = width - 3 - 3
        var y = Self.spacing
        for card in cards {
            card.frame = NSRect(x: 3, y: y, width: cardWidth, height: AgentCardView.height)
            y += AgentCardView.height + Self.spacing
        }
        list.frame = NSRect(x: 0, y: 0, width: width - 3, height: max(y, Int(scroll.frame.height)))
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        Pixel.fill(context, 0, 0, 3, height, theme.shadow)
        Pixel.fill(context, 3, 0, width - 3, Self.headHeight, theme.bg2)
        Pixel.text(context, "AGENTES \(cards.count)", 12, (Self.headHeight - 7) / 2, scale: 1, theme.dim)
    }
}

/// Container com a origem em cima à esquerda, como as views desenhadas.
final class FlippedView: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
