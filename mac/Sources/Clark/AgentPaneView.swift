import AppKit
import ClarkCore

/// O que todo agente precisa para abrir o processo. Montado uma vez, depois da captura do ambiente.
struct AgentLaunch {
    var baseEnvironment: [String: String]
    /// nil: o `claude` não foi encontrado e o painel abre o shell com o aviso.
    var claudePath: String?
    var shell: String
    var home: String
    /// Argumentos extras vindos de `clark -- <args>`.
    var claudeArgs: [String]
    var resolver: CompanyResolver

    /// A pasta pedida quando existe; senão a home.
    func usableDirectory(_ directory: String) -> String {
        PathTools.isDirectory(directory) ? directory : home
    }

    func company(forDirectory directory: String) -> Company {
        resolver.resolve(canonicalPath: PathTools.canonical(usableDirectory(directory), base: home, home: home))
    }
}

protocol AgentPaneDelegate: AnyObject {
    /// O painel está com o foco e a janela está ativa.
    func paneIsWatched(_ pane: AgentPaneView) -> Bool
    /// O agente terminou e ninguém está olhando.
    func paneNeedsAttention(_ pane: AgentPaneView)
    /// Estado, nome ou prévia mudaram.
    func paneDidChange(_ pane: AgentPaneView)
    func paneRequestsSelect(_ pane: AgentPaneView)
    func paneRequestsZoom(_ pane: AgentPaneView)
    func paneRequestsClose(_ pane: AgentPaneView)
    func paneRequestsRename(_ pane: AgentPaneView)
}

/// Painel de um agente: moldura, cabeçalho, faixa de aviso e o terminal.
final class AgentPaneView: PixelView {
    static let border = 3
    static let stripHeight = 16
    static let gameOver = "\r\n\r\n\u{1b}[1;41;97m  GAME OVER  \u{1b}[0m  "
        + "\u{1b}[2mENTER = continue?  CMD+W = sair\u{1b}[0m\r\n"
    static let missingClaude = "\r\n\u{1b}[1;31m  claude nao encontrado no PATH.\u{1b}[0m "
        + "Instale o Claude Code e reabra o CLARK.\r\n\r\n"
    static let launchFailed = "\r\n\u{1b}[1;31m  falha ao iniciar o processo.\u{1b}[0m\r\n"
    static let unfilteredShell = "Sem claude: o shell relê o rc e o filtro de variáveis não vale"

    private(set) var name: String
    private(set) var directory: String
    let sessionID: String
    /// Passo de escurecimento da cor da empresa.
    let tone: Int
    let company: Company
    private(set) var machine: AgentStateMachine
    private(set) var terminal: AgentTerminalView
    private(set) var preview: [String] = []
    /// Nomes das variáveis que a política de ambiente tirou deste agente. Nunca os valores.
    private(set) var removedVariables: [String] = []
    private(set) var bypassesPermissions = false
    weak var delegate: AgentPaneDelegate?
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }

    let header: AgentHeaderView
    private let zoomButton = PixelButton(title: "[ ]", style: .mini, toolTip: "Zoom (⌘↩)")
    private let closeButton = PixelButton(title: "X", style: .miniClose, toolTip: "Fechar (⌘W)")
    private let launch: AgentLaunch
    private var terminalAppearance: TerminalAppearance
    private let clock: () -> Double
    private var previewAt = -Double.infinity

    var color: RGB { CompanyResolver.tone(company.color, index: tone) }
    var state: AgentState { machine.state }

    var snapshot: AgentSnapshot {
        AgentSnapshot(name: name, company: company.name, color: color,
                      path: PathTools.short(directory, home: launch.home), state: machine.state, preview: preview)
    }

    init(name: String, directory: String, sessionID: String, tone: Int, launch: AgentLaunch,
         appearance: TerminalAppearance, clock: @escaping () -> Double) {
        self.name = name
        self.directory = launch.usableDirectory(directory)
        self.sessionID = sessionID
        self.tone = tone
        self.launch = launch
        terminalAppearance = appearance
        self.clock = clock
        company = launch.company(forDirectory: directory)
        machine = AgentStateMachine(now: clock())
        terminal = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        header = AgentHeaderView(snapshot: AgentSnapshot(name: name, company: "", color: .black, path: "",
                                                         state: .boot))
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 450))
        theme = appearance.theme
        header.theme = appearance.theme
        header.snapshot = snapshot
        header.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsSelect($0) } }
        header.onDoubleClick = { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } }
        header.menuProvider = { [weak self] in self?.contextMenu() }
        zoomButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } }
        closeButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } }
        addSubview(header)
        addSubview(zoomButton)
        addSubview(closeButton)
        install(terminal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    // MARK: processo

    /// Abre o `claude` (ou o shell, sem `claude`) no terminal atual.
    func spawn() {
        let now = clock()
        let environment = EnvPolicy.apply(base: launch.baseEnvironment, globalAllow: launch.resolver.globalEnvAllow,
                                          company: company, agentName: name)
        removedVariables = environment.removed
        machine.spawned(now: now)
        if let claude = launch.claudePath {
            let configDir = SessionLocator.configDir(environment: environment.variables, home: launch.home)
            let command = ClaudeCommand.build(
                extraArgs: launch.claudeArgs, sessionID: sessionID,
                sessionExists: SessionLocator.sessionExists(sessionID, configDir: configDir))
            bypassesPermissions = command.bypassesPermissions
            terminal.startProcess(executable: claude, args: command.arguments, environment: environment.asArray,
                                  currentDirectory: directory)
        } else {
            bypassesPermissions = false
            terminal.feed(text: Self.missingClaude)
            terminal.startProcess(executable: launch.shell, args: ["-l"], environment: environment.asArray,
                                  currentDirectory: directory)
        }
        if !terminal.process.running && !terminal.hasExited {
            terminal.feed(text: Self.launchFailed)
            terminal.markExited()
            machine.exited()
        }
        needsLayout = true
        changed()
    }

    /// Enter em GAME OVER: terminal novo, mesma conversa.
    func respawn() {
        guard machine.state == .exited else { return }
        let hadFocus = window?.firstResponder === terminal
        detach(terminal)
        terminal = AgentTerminalView(frame: terminal.frame)
        install(terminal)
        spawn()
        if hadFocus { window?.makeFirstResponder(terminal) }
    }

    /// SIGHUP no processo. Chamado ao fechar o agente e ao sair do app.
    func shutdown() {
        let process = terminal.process
        detach(terminal)
        if let process, process.running { ProcessReaper.hangUp(process.shellPid) }
    }

    private func install(_ terminal: AgentTerminalView) {
        terminal.apply(terminalAppearance)
        terminal.changeScrollback(AgentTerminalView.scrollbackLines)
        terminal.onOutput = { [weak self] in self.map { $0.machine.output(now: $0.clock()) } }
        terminal.onUserInput = { [weak self] in
            guard let self else { return }
            let before = self.machine.state
            self.machine.userInput(now: self.clock())
            if self.machine.state != before { self.changed() }
        }
        terminal.onResize = { [weak self] in self.map { $0.machine.resized(now: $0.clock()) } }
        terminal.onBell = { [weak self] in
            guard let self else { return }
            let notify = self.machine.bell(watched: self.delegate?.paneIsWatched(self) ?? false)
            self.changed()
            if notify { self.delegate?.paneNeedsAttention(self) }
        }
        terminal.onExit = { [weak self] _ in
            guard let self else { return }
            self.machine.exited()
            self.terminal.feed(text: Self.gameOver)
            self.changed()
        }
        terminal.onRestartRequested = { [weak self] in self?.respawn() }
        addSubview(terminal)
        needsLayout = true
    }

    private func detach(_ terminal: AgentTerminalView) {
        terminal.onOutput = nil
        terminal.onUserInput = nil
        terminal.onResize = nil
        terminal.onBell = nil
        terminal.onExit = nil
        terminal.onRestartRequested = nil
        terminal.removeFromSuperview()
    }

    // MARK: estado

    /// Tique de 100 ms.
    func tick(now: Double) {
        let before = machine.state
        let notify = machine.tick(now: now, watched: delegate?.paneIsWatched(self) ?? false)
        if machine.state != before { changed() }
        if notify { delegate?.paneNeedsAttention(self) }
        if StateLabel.isAnimated(machine.state) { header.time = now }
    }

    /// O painel ganhou o foco do teclado.
    func focused() {
        let before = machine.state
        machine.focused(now: clock())
        if machine.state != before { changed() }
    }

    /// O painel mudou de lugar ou de tamanho por troca de layout.
    func layoutChanged() {
        machine.layoutChanged(now: clock())
    }

    /// Relê as últimas linhas úteis do terminal. Devolve true quando a prévia mudou.
    @discardableResult
    func refreshPreview(now: Double, force: Bool = false) -> Bool {
        let interval = machine.lastChange > previewAt ? 0.5 : 2.0
        guard force || now - previewAt > interval else { return false }
        previewAt = now
        let lines = PreviewLines.useful(terminal.linesAboveCursor())
        guard lines != preview else { return false }
        preview = lines
        return true
    }

    func rename(_ newName: String) {
        guard newName != name else { return }
        name = newName
        changed()
    }

    func apply(_ appearance: TerminalAppearance) {
        terminalAppearance = appearance
        theme = appearance.theme
        header.theme = appearance.theme
        zoomButton.theme = appearance.theme
        closeButton.theme = appearance.theme
        terminal.apply(appearance)
    }

    private func changed() {
        header.snapshot = snapshot
        needsDisplay = true
        delegate?.paneDidChange(self)
    }

    /// Menu do cabeçalho. Mostra só os nomes das variáveis removidas.
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionItem("Renomear…") { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } })
        menu.addItem(actionItem("Zoom") { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } })
        menu.addItem(actionItem("Fechar") { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } })
        menu.addItem(.separator())
        // Sem `claude` o painel é o shell de login, que relê o rc e devolve o que saiu do ambiente:
        // o menu não afirma uma remoção que não vale ali.
        guard launch.claudePath != nil else {
            let unfiltered = NSMenuItem(title: Self.unfilteredShell, action: nil, keyEquivalent: "")
            unfiltered.isEnabled = false
            menu.addItem(unfiltered)
            return menu
        }
        let title = removedVariables.isEmpty
            ? "Nenhuma variável removida"
            : "Variáveis removidas (\(removedVariables.count))"
        let removed = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        removed.isEnabled = !removedVariables.isEmpty
        if !removedVariables.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for variable in removedVariables {
                let item = NSMenuItem(title: variable, action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
            removed.submenu = submenu
        }
        menu.addItem(removed)
        return menu
    }

    private func actionItem(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuHandler(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = handler
        return item
    }

    @objc private func runMenuHandler(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    // MARK: desenho

    private var headerBottom: Int { Self.border + AgentHeaderView.height + 2 }

    override func layout() {
        super.layout()
        let width = Int(bounds.width), height = Int(bounds.height)
        let border = Self.border
        let zoomWidth = zoomButton.fittingWidth, closeWidth = closeButton.fittingWidth
        header.frame = NSRect(x: border, y: border, width: max(0, width - 2 * border - zoomWidth - closeWidth),
                              height: AgentHeaderView.height)
        zoomButton.frame = NSRect(x: width - border - closeWidth - zoomWidth, y: border, width: zoomWidth,
                                  height: AgentHeaderView.height)
        closeButton.frame = NSRect(x: width - border - closeWidth, y: border, width: closeWidth,
                                   height: AgentHeaderView.height)
        let top = headerBottom + (bypassesPermissions ? Self.stripHeight : 0) + 4
        terminal.frame = NSRect(x: border + 6, y: top, width: max(1, width - 2 * border - 12),
                                height: max(1, height - top - border - 4))
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        let edge: RGB
        switch machine.state {
        case .exited: edge = theme.red
        case .done: edge = theme.yellow
        default: edge = isFocused ? theme.accent : theme.bg3
        }
        Pixel.frame(context, 0, 0, width, height, thickness: Self.border, edge)
        Pixel.fill(context, Self.border, headerBottom - 2, width - 2 * Self.border, 2, theme.shadow)
        if bypassesPermissions {
            let label = "SEM PERMISSOES"
            Pixel.fill(context, Self.border, headerBottom, width - 2 * Self.border, Self.stripHeight, theme.red)
            Pixel.text(context, label, (width - PixelFont.textWidth(label, scale: 1)) / 2,
                       headerBottom + (Self.stripHeight - 7) / 2, scale: 1, theme.bg)
        }
    }
}
