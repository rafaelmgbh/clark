import AppKit
import ClarkCore

/// Contagem de agentes por estado, mostrada na barra superior.
struct AgentStats: Equatable {
    var agents = 0
    var working = 0
    var done = 0
    var idle = 0
    var exited = 0

    init() {}

    init(states: [AgentState]) {
        agents = states.count
        working = states.filter { $0 == .working }.count
        done = states.filter { $0 == .done }.count
        idle = states.filter { $0 == .idle || $0 == .boot }.count
        exited = states.filter { $0 == .exited }.count
    }
}

/// Barra superior: logo, contagens e os botões de projeto, layout e novo agente.
final class TopBarView: PixelView {
    static let height = 49
    private static let contentHeight = 46

    var stats = AgentStats() { didSet { if stats != oldValue { needsDisplay = true } } }
    let projectButton = PixelButton(title: "PROJETO GLOBAL", toolTip: "Abrir agente num projeto (⌘D)")
    let layoutButton = PixelButton(title: "FOCO", toolTip: "Alternar layout foco / grade (⌘L)")
    let addButton = PixelButton(title: "+ AGENT", style: .primary, toolTip: "Novo agente (⌘N)")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        [projectButton, layoutButton, addButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet { [projectButton, layoutButton, addButton].forEach { $0.theme = theme } }
    }

    /// `PROJETO acme/app`: as duas últimas pastas, com reticências no começo quando passam de 28 caracteres.
    /// A home é o `GLOBAL`, fora de projeto.
    static func projectTitle(shortPath: String) -> String {
        if shortPath == "~" { return "PROJETO GLOBAL" }
        let folders = shortPath.split(separator: "/")
        let name = folders.count > 2 ? folders.suffix(2).joined(separator: "/") : shortPath
        return name.count > 28 ? "PROJETO …" + name.suffix(27) : "PROJETO " + name
    }

    private var buttonsLeft: Int {
        Int(bounds.width) - 10 - [projectButton, layoutButton, addButton].map(\.fittingWidth).reduce(0, +) - 20
    }

    override func layout() {
        super.layout()
        var x = buttonsLeft
        let y = (Self.contentHeight - PixelButton.barHeight) / 2
        for button in [projectButton, layoutButton, addButton] {
            button.frame = NSRect(x: x, y: y, width: button.fittingWidth, height: PixelButton.barHeight)
            x += button.fittingWidth + 10
        }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        let content = Self.contentHeight
        Pixel.fill(context, 0, 0, width, content, theme.bg2)
        Pixel.fill(context, 0, content, width, height - content, theme.shadow)

        let logoY = (content - 21) / 2
        Pixel.text(context, "CLARK", 12, logoY + 2, scale: 3, theme.accent.mix(.black, 0.5))
        Pixel.text(context, "CLARK", 10, logoY, scale: 3, theme.accent)

        var x = 10 + PixelFont.textWidth("CLARK", scale: 3) + 4 + 10 + 16
        let y = (content - 14) / 2
        let limit = buttonsLeft - 10
        var items: [(label: String, count: Int, color: RGB)] = [
            ("AGENTS", stats.agents, theme.ink), ("WORKING", stats.working, theme.green),
            ("DONE", stats.done, theme.yellow), ("IDLE", stats.idle, theme.dim),
        ]
        if stats.exited > 0 { items.append(("GAME OVER", stats.exited, theme.red)) }
        for item in items {
            let label = "\(item.label) \(item.count)"
            let labelWidth = PixelFont.textWidth(label, scale: 2)
            if x + 12 + labelWidth > limit { break }
            let color = item.count == 0 ? theme.dim : item.color
            Pixel.fill(context, x, y + 4, 6, 6, color)
            Pixel.text(context, label, x + 12, y, scale: 2, color)
            x += labelWidth + 34
        }
    }
}

/// Faixa de avisos abaixo da barra superior. Um clique dispensa o aviso mostrado.
final class WarningBarView: PixelView {
    static let height = 22

    private(set) var messages: [String] = []
    var onChange: (() -> Void)?

    func add(_ message: String) {
        guard !messages.contains(message) else { return }
        messages.append(message)
        needsDisplay = true
        onChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard !messages.isEmpty else { return }
        messages.removeFirst()
        needsDisplay = true
        onChange?()
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2.mix(theme.yellow, 0.12))
        Pixel.fill(context, 0, height - 2, width, 2, theme.shadow)
        guard let first = messages.first else { return }
        let more = messages.count > 1 ? "  (+\(messages.count - 1))" : ""
        let close = "X"
        let room = width - 20 - PixelFont.textWidth(close, scale: 1) - 12
        Pixel.text(context, PixelFont.fit("! " + first + more, scale: 1, width: room), 10, (height - 2 - 7) / 2,
                   scale: 1, theme.yellow)
        Pixel.text(context, close, width - 10 - PixelFont.textWidth(close, scale: 1), (height - 2 - 7) / 2,
                   scale: 1, theme.dim)
    }
}

/// Tela sem agentes (`_draw_empty` do original, sem o mascote, que chega no M3).
final class EmptyStateView: PixelView {
    /// true enquanto o ambiente do shell ainda está sendo lido: sem botões.
    var isLoading = true { didSet { buttons.forEach { $0.isHidden = isLoading }; needsDisplay = true } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onAdd: ((Int) -> Void)?
    private var buttons: [PixelButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for count in [1, 2, 4, 6] {
            let button = PixelButton(title: "\(count) AGENTE" + (count > 1 ? "S" : ""),
                                     style: count == 1 ? .primary : .normal)
            button.onClick = { [weak self] in self?.onAdd?(count) }
            button.isHidden = true
            buttons.append(button)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme { didSet { buttons.forEach { $0.theme = theme } } }

    override func layout() {
        super.layout()
        let total = buttons.map(\.fittingWidth).reduce(0, +) + 14 * (buttons.count - 1)
        var x = (Int(bounds.width) - total) / 2
        let y = Int(bounds.height) - 90 - PixelButton.barHeight
        for button in buttons {
            button.frame = NSRect(x: x, y: y, width: button.fittingWidth, height: PixelButton.barHeight)
            x += button.fittingWidth + 14
        }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        let unit = max(4, min(width, height) / 70)
        let scale = max(2, unit / 2)
        let y = Int(Double(height) * 0.42)
        let message = isLoading ? "LENDO O AMBIENTE DO SHELL" : "NENHUM AGENTE ONLINE"
        Pixel.text(context, message, (width - PixelFont.textWidth(message, scale: scale)) / 2, y, scale: scale,
                   theme.ink, shadow: theme.shadow)
        guard !isLoading, Int(time * 2) % 2 == 0 else { return }
        let hint = "PRESS START  -  CMD+N"
        Pixel.text(context, hint, (width - PixelFont.textWidth(hint, scale: 2)) / 2, y + 7 * scale + 3 * unit,
                   scale: 2, theme.accent)
    }
}
