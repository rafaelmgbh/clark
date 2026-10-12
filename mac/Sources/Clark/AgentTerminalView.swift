import AppKit
import ClarkCore
import SwiftTerm

/// Aparência dos terminais, igual para todos os agentes.
struct TerminalAppearance {
    var theme: Theme
    var fontName: String
    var fontSize: Double

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

/// Terminal de um agente: traduz os ganchos do SwiftTerm em eventos simples.
final class AgentTerminalView: LocalProcessTerminalView {
    static let scrollbackLines = 20_000

    var onOutput: (() -> Void)?
    var onUserInput: (() -> Void)?
    var onBell: (() -> Void)?
    var onExit: ((Int32?) -> Void)?
    var onResize: (() -> Void)?
    var onRestartRequested: (() -> Void)?
    /// Abre um link no navegador. Trocado nos testes.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var hasExited = false
    private var replying = false

    /// Leitura dos links da tela que custa mais que isto é cara: as seguintes são espaçadas.
    static let linkReadBudget: TimeInterval = 0.002
    /// Depois de uma leitura cara o terminal espera este tanto de vezes o custo dela até a próxima:
    /// a leitura fica com no máximo um décimo do tempo.
    static let linkReadRest: TimeInterval = 9

    /// Sublinha o que o ⌘-clique abre. Sem isso o link é clicável e ninguém fica sabendo.
    let linkUnderlines = LinkUnderlineView()
    /// Relógio da leitura dos links. Trocado nos testes.
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var linksReadableAt: TimeInterval = 0
    private var linkReadScheduled = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        linkUnderlines.frame = bounds
        linkUnderlines.autoresizingMask = [.width, .height]
        addSubview(linkUnderlines, positioned: .below, relativeTo: nil)
        // O SwiftTerm passa a avisar, antes de cada redesenho, que a tela mudou.
        notifyUpdateChanges = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    /// Código de saída a partir do status bruto que o SwiftTerm repassa do `waitpid`.
    static func exitCode(fromWaitStatus status: Int32?) -> Int32? {
        guard let status else { return nil }
        return (status >> 8) & 0xff
    }

    func apply(_ appearance: TerminalAppearance) {
        let theme = appearance.theme
        nativeBackgroundColor = theme.bg.nsColor
        nativeForegroundColor = theme.ink.nsColor
        caretColor = theme.accent.nsColor
        caretTextColor = theme.bg.nsColor
        selectedTextBackgroundColor = theme.accent.mix(theme.bg, 0.55).nsColor
        installColors(theme.term.map { color in
            SwiftTerm.Color(red8: Self.byte(color.r), green8: Self.byte(color.g), blue8: Self.byte(color.b))
        })
        font = appearance.font
        linkUnderlines.color = theme.term[4]
        refreshLinkUnderlines()
    }

    private static func byte(_ value: Double) -> UInt16 {
        UInt16((max(0, min(1, value)) * 255).rounded())
    }

    /// Sem processo vivo, o Enter pede a reabertura. Usado quando o processo nem chegou a abrir.
    func markExited() {
        hasExited = true
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }

    /// Resposta do emulador a um pedido de leitura do clipboard (OSC 52): `ESC ] 52 ; …`.
    static func isClipboardReply(_ data: ArraySlice<UInt8>) -> Bool {
        let bytes = Array(data)
        let body: ArraySlice<UInt8>
        if bytes.starts(with: [0x1b, 0x5d]) {
            body = bytes.dropFirst(2)
        } else if bytes.first == 0x9d {
            body = bytes.dropFirst()
        } else {
            return false
        }
        return body.starts(with: Array("52;".utf8))
    }

    // Respostas do próprio emulador (posição do cursor, foco) passam por aqui e não contam como tecla.
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        // O SwiftTerm responde ao OSC 52 de leitura com o clipboard do usuário, e a classe-base não
        // deixa trocar isso. Um texto qualquer na saída do agente leria o que você copiou: a resposta
        // morre aqui. Escrever no clipboard (o `copiar` dos programas) continua valendo.
        if Self.isClipboardReply(data) { return }
        replying = true
        defer { replying = false }
        super.send(source: source, data: data)
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if hasExited {
            if data.contains(13) { onRestartRequested?() }
            return
        }
        if !replying { onUserInput?() }
        super.send(source: source, data: data)
    }

    override func bell(source: Terminal) {
        onBell?()
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        hasExited = true
        super.processTerminated(source, exitCode: exitCode)
        onExit?(Self.exitCode(fromWaitStatus: exitCode))
    }

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = TerminalLinks.webURL(link) else { return }
        openURL(url)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        guard changed else { return }
        // O texto mudou de lugar agora, e o SwiftTerm só avisa no redesenho seguinte.
        refreshLinkUnderlines()
        onResize?()
    }

    // A tela mudou ou rolou: o aviso chega antes do redesenho, e os dois saem juntos.
    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        refreshLinkUnderlines()
    }

    /// Refaz os sublinhados dos links com o que está na tela.
    func refreshLinkUnderlines() {
        linkUnderlines.metrics = linkMetrics()
        let start = uptime()
        guard start >= linksReadableAt else {
            // Cedo demais depois de uma leitura cara. O sublinhado velho ficaria debaixo de outro
            // texto: melhor nenhum até a próxima leitura.
            linkUnderlines.spans = []
            scheduleLinkRead(after: linksReadableAt - start)
            return
        }
        linkUnderlines.spans = TerminalLinks.spans(in: getTerminal())
        let cost = uptime() - start
        linksReadableAt = cost > Self.linkReadBudget ? start + cost * (1 + Self.linkReadRest) : 0
    }

    private func scheduleLinkRead(after delay: TimeInterval) {
        guard !linkReadScheduled else { return }
        linkReadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.linkReadScheduled = false
            self.refreshLinkUnderlines()
        }
    }

    /// O traço fica onde o SwiftTerm desenha o sublinhado dele: abaixo da linha de base, na posição
    /// e na espessura que a fonte pede.
    private func linkMetrics() -> LinkUnderlineView.Metrics {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let rows = CGFloat(max(1, getTerminal().rows))
        return LinkUnderlineView.Metrics(
            cell: CGSize(width: caretFrame.width, height: getOptimalFrameSize().height / rows),
            offset: ceil(font.leading - font.descender) + font.underlinePosition,
            thickness: max(1, (scale * font.underlineThickness).rounded() / scale))
    }

    /// Linhas visíveis acima do cursor, de cima para baixo.
    func linesAboveCursor() -> [String] {
        let terminal = getTerminal()
        let cursorRow = terminal.getCursorLocation().y
        guard cursorRow > 0 else { return [] }
        return (0..<cursorRow).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }
}

/// Encerra o processo de um agente fechado e recolhe o filho, para não deixar zumbi.
enum ProcessReaper {
    /// SIGHUP; se o processo ignorar por `grace` segundos, SIGKILL.
    static func hangUp(_ pid: pid_t, grace: TimeInterval = 2) {
        guard pid > 1 else { return }
        kill(pid, SIGHUP)
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            let attempts = max(1, Int(grace / 0.1))
            for _ in 0..<attempts {
                // Diferente de zero: o filho já foi recolhido aqui (pid) ou pelo SwiftTerm (-1).
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }
    }
}
