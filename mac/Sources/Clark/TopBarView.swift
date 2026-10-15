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
        // Comando em segundo plano também é coisa rodando.
        working = states.filter { $0 == .working || $0 == .shell }.count
        done = states.filter { $0 == .done }.count
        idle = states.filter { $0 == .idle || $0 == .boot }.count
        exited = states.filter { $0 == .exited }.count
    }
}

/// Medidor do consumo do plano do Claude: por janela, o rótulo, uma barra de blocos e o percentual.
final class UsageMeterView: PixelView {
    static let height = 14
    static let segments = 10
    private static let segmentWidth = 4
    private static let segmentStep = 5
    static let barWidth = segments * segmentStep - (segmentStep - segmentWidth)
    private static let gap = 6
    private static let between = 16

    var meter: UsageMeter? {
        didSet {
            guard meter != oldValue else { return }
            toolTip = meter?.summary
            needsDisplay = true
        }
    }
    /// Sem as barras, para a barra superior apertada.
    var isCompact = false { didSet { if isCompact != oldValue { needsDisplay = true } } }

    func fittingWidth(compact: Bool) -> Int {
        guard let meter else { return 0 }
        let widths = meter.gauges.map { gauge in
            PixelFont.textWidth(gauge.label, scale: 2) + Self.gap + (compact ? 0 : Self.barWidth + Self.gap)
                + PixelFont.textWidth(gauge.text, scale: 2)
        }
        return widths.reduce(0, +) + Self.between * max(0, widths.count - 1)
    }

    private func color(_ level: UsageMeter.Level) -> RGB {
        switch level {
        case .ok: return theme.green
        case .warn: return theme.yellow
        case .critical: return theme.red
        }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        guard let meter else { return }
        var x = 0
        for gauge in meter.gauges {
            // Leitura velha sai toda apagada: o número pode não valer mais.
            let level = meter.isStale ? theme.dim : color(gauge.level)
            Pixel.text(context, gauge.label, x, 0, scale: 2, theme.dim)
            x += PixelFont.textWidth(gauge.label, scale: 2) + Self.gap
            if !isCompact {
                let filled = gauge.filled(of: Self.segments)
                for index in 0..<Self.segments {
                    Pixel.fill(context, x + index * Self.segmentStep, 2, Self.segmentWidth, 10,
                               index < filled ? level : theme.bg4)
                }
                x += Self.barWidth + Self.gap
            }
            let ink = meter.isStale || gauge.level != .ok ? level : theme.ink
            Pixel.text(context, gauge.text, x, 0, scale: 2, ink)
            x += PixelFont.textWidth(gauge.text, scale: 2) + Self.between
        }
    }
}

/// Barra superior: logo, contagens, consumo do plano e os botões de projeto, layout e novo agente.
final class TopBarView: PixelView {
    static let height = 49
    private static let contentHeight = 46

    var stats = AgentStats() {
        didSet {
            guard stats != oldValue else { return }
            // O medidor de consumo fica com o espaço que as contagens deixam.
            needsLayout = true
            needsDisplay = true
        }
    }
    /// Consumo do plano do Claude. nil: sem leitura, sem medidor.
    var usage: UsageMeter? {
        didSet {
            guard usage != oldValue else { return }
            usageView.meter = usage
            needsLayout = true
        }
    }
    let usageView = UsageMeterView()
    let layoutButton = PixelButton(title: "FOCO", toolTip: "Alternar layout foco / grade (⌘L)")
    let addButton = PixelButton(title: "+ AGENT", style: .primary, toolTip: "Novo agente (⌘N) ou num projeto (⌘D)")
    private var buttons: [PixelButton] { [layoutButton, addButton] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buttons.forEach(addSubview)
        usageView.isHidden = true
        addSubview(usageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet {
            buttons.forEach { $0.theme = theme }
            usageView.theme = theme
        }
    }

    private static let statsLeft = 10 + PixelFont.textWidth("CLARK", scale: 3) + 4 + 10 + 16
    private static let statSpacing = 34
    private static let usageMargin = 16

    private var statItems: [(label: String, color: RGB)] {
        var items = [("AGENTS \(stats.agents)", stats.agents == 0 ? theme.dim : theme.ink),
                     ("WORKING \(stats.working)", stats.working == 0 ? theme.dim : theme.green),
                     ("DONE \(stats.done)", stats.done == 0 ? theme.dim : theme.yellow),
                     ("IDLE \(stats.idle)", theme.dim)]
        if stats.exited > 0 { items.append(("GAME OVER \(stats.exited)", theme.red)) }
        return items
    }

    /// Onde as contagens terminam, com todas na barra.
    private var statsRight: Int {
        statItems.reduce(Self.statsLeft) { $0 + PixelFont.textWidth($1.label, scale: 2) + Self.statSpacing }
            - Self.statSpacing + 12
    }

    private var buttonsLeft: Int {
        Int(bounds.width) - 10 - buttons.map(\.fittingWidth).reduce(0, +) - 10 * (buttons.count - 1)
    }

    override func layout() {
        super.layout()
        var x = buttonsLeft
        let y = (Self.contentHeight - PixelButton.barHeight) / 2
        for button in buttons {
            button.frame = NSRect(x: x, y: y, width: button.fittingWidth, height: PixelButton.barHeight)
            x += button.fittingWidth + 10
        }
        layoutUsage()
    }

    /// O medidor entra entre as contagens e os botões. Apertado, perde as barras; sem espaço nem para os
    /// números, some: as contagens têm a preferência.
    private func layoutUsage() {
        let right = buttonsLeft - Self.usageMargin
        let room = right - (statsRight + Self.usageMargin)
        let full = usageView.fittingWidth(compact: false), compact = usageView.fittingWidth(compact: true)
        usageView.isHidden = usage == nil || room < compact
        guard !usageView.isHidden else { return }
        usageView.isCompact = room < full
        let width = usageView.isCompact ? compact : full
        usageView.frame = NSRect(x: right - width, y: (Self.contentHeight - UsageMeterView.height) / 2,
                                 width: width, height: UsageMeterView.height)
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        let content = Self.contentHeight
        Pixel.fill(context, 0, 0, width, content, theme.bg2)
        Pixel.fill(context, 0, content, width, height - content, theme.shadow)

        let logoY = (content - 21) / 2
        Pixel.text(context, "CLARK", 12, logoY + 2, scale: 3, theme.accent.mix(.black, 0.5))
        Pixel.text(context, "CLARK", 10, logoY, scale: 3, theme.accent)

        var x = Self.statsLeft
        let y = (content - 14) / 2
        let limit = buttonsLeft - 10
        for item in statItems {
            let labelWidth = PixelFont.textWidth(item.label, scale: 2)
            if x + 12 + labelWidth > limit { break }
            Pixel.fill(context, x, y + 4, 6, 6, item.color)
            Pixel.text(context, item.label, x + 12, y, scale: 2, item.color)
            x += labelWidth + Self.statSpacing
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
