import AppKit
import ClarkCore

/// O que todo agente precisa para abrir o processo. Montado uma vez, depois da captura do ambiente.
struct AgentLaunch {
    var baseEnvironment: [String: String]
    /// nil: o `claude` não foi encontrado e o painel abre o shell com o aviso.
    var claudePath: String?
    /// nil: o `codex` não foi encontrado, e o agente Codex abre o shell com o aviso.
    var codexPath: String? = nil
    /// nil: sem git na máquina, e nenhum agente mostra diff.
    var gitPath: String? = nil
    var shell: String
    var home: String
    /// Argumentos extras vindos de `clark -- <args>`.
    var claudeArgs: [String]
    var resolver: CompanyResolver

    /// Caminho do programa que o agente roda. nil: não está instalado.
    func executable(for tool: AgentTool) -> String? {
        switch tool {
        case .claude: claudePath
        case .codex: codexPath
        }
    }

    /// A pasta pedida quando existe; senão a home.
    func usableDirectory(_ directory: String) -> String {
        PathTools.isDirectory(directory) ? directory : home
    }

    func canonical(_ path: String) -> String {
        PathTools.canonical(path, base: home, home: home)
    }

    func company(forDirectory directory: String) -> Company {
        resolver.resolve(canonicalPath: canonical(usableDirectory(directory)))
    }

    /// Empresas e projetos que existem no disco agora, para a cascata `Projeto` do + AGENT.
    /// - Parameter nicknames: caminho -> apelido, como está no `config.json`.
    func projectGroups(nicknames: [String: String] = [:]) -> [ProjectGroup] {
        resolver.projectGroups(canonicalize: canonical, nicknames: nicknames)
    }

    /// A pasta é a home: o agente é do `GLOBAL`, fora de projeto e de empresa.
    func isGlobal(_ directory: String) -> Bool {
        canonical(usableDirectory(directory)) == canonical(home)
    }

    /// Pasta que dá o nome ao projeto do agente e que guarda o apelido dele. nil no `GLOBAL`.
    func namedPath(forDirectory directory: String, nicknames: [String: String]) -> String? {
        ProjectNaming.namedPath(canonicalPath: canonical(usableDirectory(directory)), canonicalHome: canonical(home),
                                nicknames: ProjectNaming.canonical(nicknames, canonicalize: canonical),
                                isRepository: ProjectCatalog.isRepository)
    }

    /// `GLOBAL`, o apelido do projeto ou o nome da pasta arrumado.
    func projectName(forDirectory directory: String, nicknames: [String: String]) -> String {
        ProjectNaming.name(canonicalPath: canonical(usableDirectory(directory)), canonicalHome: canonical(home),
                           nicknames: ProjectNaming.canonical(nicknames, canonicalize: canonical),
                           isRepository: ProjectCatalog.isRepository)
    }
}

protocol AgentPaneDelegate: AnyObject {
    /// O painel está com o foco e a janela está ativa.
    func paneIsWatched(_ pane: AgentPaneView) -> Bool
    /// O agente terminou e ninguém está olhando.
    func paneNeedsAttention(_ pane: AgentPaneView)
    /// Estado, nome ou prévia mudaram.
    func paneDidChange(_ pane: AgentPaneView)
    /// O agente passou a seguir outra conversa: é ela que volta ao reabrir.
    func paneSessionDidChange(_ pane: AgentPaneView)
    func paneRequestsSelect(_ pane: AgentPaneView)
    func paneRequestsZoom(_ pane: AgentPaneView)
    func paneRequestsClose(_ pane: AgentPaneView)
    func paneRequestsRename(_ pane: AgentPaneView)
    /// Dar, trocar ou tirar o apelido do projeto do agente.
    func paneRequestsNickname(_ pane: AgentPaneView)
    /// Mais um agente na mesma pasta.
    func paneRequestsSibling(_ pane: AgentPaneView)
    func paneRequestsDiff(_ pane: AgentPaneView)
    /// A janela do diff já no arquivo, escolhido na coluna dos arquivos alterados.
    func paneRequestsDiff(_ pane: AgentPaneView, path: String)
}

/// Painel de um agente: moldura, cabeçalho, faixa de aviso, resumo da última sessão e o terminal.
final class AgentPaneView: PixelView {
    static let border = 3
    static let stripHeight = 16
    /// Largura que o terminal tem de manter para a coluna dos arquivos alterados caber ao lado dele.
    static let minTerminalWidth = 320
    static let gameOver = "\r\n\r\n\u{1b}[1;41;97m  GAME OVER  \u{1b}[0m  "
        + "\u{1b}[2mENTER = continue?  CMD+W = sair\u{1b}[0m\r\n"
    static let missingClaude = "\r\n\u{1b}[1;31m  claude nao encontrado no PATH.\u{1b}[0m "
        + "Instale o Claude Code e reabra o CLARK.\r\n\r\n"
    static let missingCodex = "\r\n\u{1b}[1;31m  codex nao encontrado no PATH.\u{1b}[0m "
        + "Instale o Codex e reabra o CLARK.\r\n\r\n"
    static let launchFailed = "\r\n\u{1b}[1;31m  falha ao iniciar o processo.\u{1b}[0m\r\n"
    static let unfilteredShell = "Sem o programa do agente: o shell relê o rc e o filtro de variáveis não vale"
    /// As conversas são lidas fora da thread principal: um arquivo grande não trava a janela.
    private static let digestQueue = DispatchQueue(label: "clark.digest", qos: .utility)

    private(set) var name: String
    private(set) var directory: String
    /// `GLOBAL`, o apelido do projeto ou o nome da pasta arrumado.
    private(set) var project: String
    /// Aberto na home: fora de projeto e de empresa.
    let isGlobal: Bool
    /// O que o agente roda: o Claude Code ou o Codex.
    let tool: AgentTool
    /// A conversa que o `claude` do agente segue. Muda com `/clear` e `/resume` e quando a conversa
    /// vai para segundo plano.
    private(set) var sessionID: String
    /// Passo de escurecimento da cor da empresa.
    let tone: Int
    let company: Company
    private(set) var machine: AgentStateMachine
    private(set) var terminal: AgentTerminalView
    private(set) var preview: [String] = []
    /// Nomes das variáveis que a política de ambiente tirou deste agente. Nunca os valores.
    private(set) var removedVariables: [String] = []
    private(set) var bypassesPermissions = false
    /// O controle remoto do Claude Code está ligado na sessão deste agente.
    private(set) var remoteControl = false
    /// O `claude` abriu sem conversa para retomar. Só aí o resumo da última sessão interessa.
    private(set) var startedNewConversation = false
    /// O que mudou no repositório da pasta do agente.
    let diff = DiffMonitor()
    weak var delegate: AgentPaneDelegate?
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }

    let header: AgentHeaderView
    let digestView = SessionDigestView()
    /// Arquivos alterados no repositório, ao lado do terminal.
    let changedFiles = ChangedFilesView()
    /// A coluna dos arquivos alterados foi pedida. Num painel estreito ela fica escondida até caber.
    private(set) var showsChangedFiles = false
    private let zoomButton = PixelButton(title: "[ ]", style: .mini, toolTip: "Zoom (⌘↩)")
    private let closeButton = PixelButton(title: "X", style: .miniClose, toolTip: "Fechar (⌘W)")
    private let launch: AgentLaunch
    private var terminalAppearance: TerminalAppearance
    /// De quanto em quanto tempo o agente relê o que o Claude Code diz da sessão.
    static let activityInterval = 1.0
    private let clock: () -> Double
    private var activityAt = -Double.infinity
    private var remoteAt = -Double.infinity
    /// Quando o processo abriu, em segundos desde 1970. Arquivo de sessão mais velho é de outro processo.
    private var spawnedAt = 0.0
    private var previewAt = -Double.infinity
    /// Estado na última vez em que o painel avisou que mudou.
    private var reportedState = AgentState.boot
    /// Pasta de configuração do Claude deste agente, conhecida a partir do `spawn`.
    private var claudeConfigDir: String?
    /// O job em segundo plano que o processo do agente mostra, quando ele abriu com `claude attach`.
    private var attachedJob: String?
    /// Até quando, depois da saída, o anúncio de conversa mandada para segundo plano é procurado.
    private var handoffUntil = -Double.infinity
    private var handoffAt = -Double.infinity
    /// Por quanto tempo, depois da saída, o job anunciado é esperado.
    static let handoffWindow = 30.0
    private var digestGeneration = 0

    var color: RGB { CompanyResolver.tone(company.color, index: tone) }
    /// Onde o agente trabalha, para o aviso de pronto: `Empresa › Projeto`. Vazio no `GLOBAL`.
    var place: String { ProjectNaming.place(project: project, company: company.name, isGlobal: isGlobal) }
    var state: AgentState { machine.state }
    /// Resumo da última sessão, enquanto está na tela.
    var digest: SessionDigest? { digestView.digest }

    var snapshot: AgentSnapshot {
        AgentSnapshot(name: name, project: project, company: isGlobal ? "" : company.name, color: color,
                      companyColor: company.color, path: PathTools.short(directory, home: launch.home),
                      state: machine.state, preview: preview, diff: diff.summary, remoteControl: remoteControl)
    }

    /// - Parameter nicknames: caminho -> apelido, como está no `config.json`.
    init(name: String, directory: String, sessionID: String, tone: Int, launch: AgentLaunch,
         tool: AgentTool = .claude, nicknames: [String: String] = [:], appearance: TerminalAppearance,
         clock: @escaping () -> Double) {
        self.name = name
        self.tool = tool
        self.directory = launch.usableDirectory(directory)
        project = launch.projectName(forDirectory: directory, nicknames: nicknames)
        isGlobal = launch.isGlobal(directory)
        self.sessionID = sessionID
        self.tone = tone
        self.launch = launch
        terminalAppearance = appearance
        self.clock = clock
        company = launch.company(forDirectory: directory)
        machine = AgentStateMachine(now: clock())
        terminal = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        header = AgentHeaderView(snapshot: AgentSnapshot(name: name, company: "", color: .black,
                                                         companyColor: .black, path: "", state: .boot))
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 450))
        theme = appearance.theme
        header.theme = appearance.theme
        header.snapshot = snapshot
        header.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsSelect($0) } }
        header.onDoubleClick = { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } }
        header.onBadgeClick = { [weak self] in self?.toggleChangedFiles() }
        header.menuProvider = { [weak self] in self?.contextMenu() }
        zoomButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } }
        closeButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } }
        diff.onChange = { [weak self] in self?.changed() }
        digestView.theme = appearance.theme
        digestView.isHidden = true
        digestView.onDismiss = { [weak self] in self?.dismissDigest() }
        changedFiles.theme = appearance.theme
        changedFiles.isHidden = true
        changedFiles.onRefresh = { [weak self] in self?.diff.refresh() }
        changedFiles.onClose = { [weak self] in self?.setChangedFiles(shown: false) }
        changedFiles.onSelect = { [weak self] file in
            self.map { $0.delegate?.paneRequestsDiff($0, path: file.path) }
        }
        addSubview(header)
        addSubview(zoomButton)
        addSubview(closeButton)
        addSubview(digestView)
        addSubview(changedFiles)
        install(terminal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    // MARK: processo

    /// Abre o `claude` ou o `codex` (ou o shell, sem o programa) no terminal atual.
    func spawn() {
        let now = clock()
        let environment = EnvPolicy.apply(base: launch.baseEnvironment, globalAllow: launch.resolver.globalEnvAllow,
                                          company: company, agentName: name)
        removedVariables = environment.removed
        machine.spawned(now: now)
        spawnedAt = Date().timeIntervalSince1970
        handoffUntil = -.infinity
        handoffAt = -.infinity
        attachedJob = nil
        if tool == .claude, let claude = launch.claudePath {
            let configDir = SessionLocator.configDir(environment: environment.variables, home: launch.home)
            let command: ClaudeCommand
            // A conversa segue em segundo plano: reabrir com `--resume` abriria uma cópia dela.
            if !ClaudeCommand.hasSessionFlag(launch.claudeArgs),
               let background = BackgroundSession.live(configDir: configDir, sessionID: sessionID) {
                command = ClaudeCommand.attach(jobID: background.jobID, extraArgs: launch.claudeArgs)
                attachedJob = background.jobID
                startedNewConversation = false
            } else {
                let sessionExists = SessionLocator.sessionExists(sessionID, configDir: configDir)
                command = ClaudeCommand.build(extraArgs: launch.claudeArgs, sessionID: sessionID,
                                              sessionExists: sessionExists)
                startedNewConversation = !sessionExists
            }
            claudeConfigDir = configDir
            bypassesPermissions = command.bypassesPermissions
            terminal.startProcess(executable: claude, args: command.arguments, environment: environment.asArray,
                                  currentDirectory: directory)
        } else if tool == .codex, let codex = launch.codexPath {
            // O que o CLARK lê do disco é das conversas do Claude Code: no Codex fica desligado.
            claudeConfigDir = nil
            startedNewConversation = false
            bypassesPermissions = false
            terminal.startProcess(executable: codex, args: [], environment: environment.asArray,
                                  currentDirectory: directory)
        } else {
            claudeConfigDir = nil
            startedNewConversation = false
            bypassesPermissions = false
            terminal.feed(text: tool == .codex ? Self.missingCodex : Self.missingClaude)
            terminal.startProcess(executable: launch.shell, args: ["-l"], environment: environment.asArray,
                                  currentDirectory: directory)
        }
        if !terminal.process.running && !terminal.hasExited {
            terminal.feed(text: Self.launchFailed)
            terminal.markExited()
            machine.exited()
        }
        // O git do diff nasce com o ambiente já filtrado do agente: não recebe o que o agente não recebe.
        diff.configure(runner: launch.gitPath.map { GitRunner(executable: $0, agentEnvironment: environment.variables) },
                       directory: directory)
        diff.refresh()
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
            // Começou a digitar: o resumo já foi lido e devolve o espaço ao terminal.
            self.dismissDigest()
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
            // Morto à força, o processo deixa o arquivo de sessão para trás: quem saiu não é remoto.
            self.remoteControl = false
            self.handoffUntil = self.clock() + Self.handoffWindow
            self.followHandoff(now: self.clock())
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
        let before = machine.state, remoteBefore = remoteControl
        // Antes do tique da máquina: com a tela parada, quem decide é o que o Claude Code diz agora.
        refreshSession(now: now)
        followHandoff(now: now)
        let notify = machine.tick(now: now, watched: delegate?.paneIsWatched(self) ?? false)
        if machine.state != before || remoteControl != remoteBefore { changed() }
        if notify { delegate?.paneNeedsAttention(self) }
        if StateLabel.isAnimated(machine.state) { header.time = now }
    }

    /// Relê o que o Claude Code diz da sessão. Com a tela parada, o terminal não mostra se o turno
    /// acabou, se sobrou comando rodando em segundo plano ou se um agente em segundo plano segue
    /// trabalhando: o arquivo é lido na hora em que a saída para e, dali em diante, uma vez por
    /// segundo. Com saída, o terminal basta para o estado, mas o controle remoto só o arquivo conta:
    /// ele é relido no mesmo ritmo.
    private func refreshSession(now: Double) {
        guard let configDir = claudeConfigDir, machine.state != .exited else { return }
        let quiet = machine.isQuiet(now: now) && now - activityAt >= Self.activityInterval
        guard quiet || now - remoteAt >= Self.activityInterval else { return }
        let report = SessionReport.read(configDir: configDir, pid: terminal.process.shellPid, since: spawnedAt)
        if quiet { activityAt = now }
        remoteAt = now
        machine.backgroundShell(report?.activity == .shell)
        machine.sessionBusy(report?.activity == .busy)
        remoteControl = report?.remoteControl ?? false
        // Pelo `attach`, o processo do agente só mostra o job: a conversa é a do arquivo do job.
        if let job = attachedJob {
            if let background = BackgroundSession.live(configDir: configDir, jobID: job) { adopt(background.sessionID) }
        } else if let id = report?.sessionID {
            adopt(id)
        }
    }

    /// Depois da saída, procura na tela o anúncio da conversa mandada para segundo plano e passa a
    /// seguir o job. O processo em segundo plano pode gravar o arquivo dele depois que o `claude` do
    /// agente sai: a procura se repete uma vez por segundo, por `handoffWindow` segundos.
    private func followHandoff(now: Double) {
        guard let configDir = claudeConfigDir, machine.state == .exited, now <= handoffUntil,
              now - handoffAt >= Self.activityInterval else { return }
        handoffAt = now
        guard let job = BackgroundSession.handoff(in: terminal.linesAboveCursor()),
              let background = BackgroundSession.live(configDir: configDir, jobID: job) else { return }
        handoffUntil = -.infinity
        adopt(background.sessionID)
    }

    private func adopt(_ id: String) {
        guard id != sessionID else { return }
        sessionID = id
        delegate?.paneSessionDidChange(self)
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

    /// Os apelidos mudaram: o nome do projeto é recalculado.
    func updateProject(nicknames: [String: String]) {
        let updated = launch.projectName(forDirectory: directory, nicknames: nicknames)
        guard updated != project else { return }
        project = updated
        changed()
    }

    // MARK: resumo da última sessão

    /// Procura a conversa anterior da pasta e mostra o resumo dela. Só vale para o agente que começa
    /// conversa nova num projeto: a conversa retomada já conta a própria história, e o `GLOBAL`
    /// junta assuntos demais para um resumo dizer algo.
    /// - Parameter excluding: conversas dos agentes abertos, que não são "a última sessão".
    func loadDigest(excluding: Set<String>) {
        guard !isGlobal, startedNewConversation, let configDir = claudeConfigDir else { return }
        digestGeneration += 1
        let generation = digestGeneration
        let directory = launch.canonical(directory)
        Self.digestQueue.async { [weak self] in
            let digest = SessionDigestReader.latest(canonicalDirectory: directory, configDir: configDir,
                                                    excluding: excluding)
            DispatchQueue.main.async {
                guard let self, generation == self.digestGeneration else { return }
                self.show(digest)
            }
        }
    }

    /// Tira o resumo da tela e cancela a leitura em curso.
    func dismissDigest() {
        digestGeneration += 1
        show(nil)
    }

    private func show(_ digest: SessionDigest?) {
        guard digest != digestView.digest else { return }
        digestView.digest = digest
        digestView.isHidden = digest == nil
        // O terminal muda de altura: o redesenho do agente não conta como trabalho.
        machine.layoutChanged(now: clock())
        needsLayout = true
        needsDisplay = true
    }

    /// Abre ou fecha a coluna dos arquivos alterados. Num painel estreito demais para ela, abre a janela
    /// do diff, que mostra a mesma lista.
    func toggleChangedFiles() {
        if showsChangedFiles {
            setChangedFiles(shown: false)
        } else if changedFilesFit {
            setChangedFiles(shown: true)
        } else {
            delegate?.paneRequestsDiff(self)
        }
    }

    private func setChangedFiles(shown: Bool) {
        guard shown != showsChangedFiles else { return }
        showsChangedFiles = shown
        // A lista é a da última leitura, e o repositório pode ter mudado desde então.
        if shown { diff.refresh() }
        // O terminal muda de largura: o redesenho do agente não conta como trabalho.
        machine.layoutChanged(now: clock())
        needsLayout = true
    }

    /// O terminal não fica mais estreito que o mínimo para dar lugar à coluna.
    private var changedFilesFit: Bool {
        Int(bounds.width) - 2 * Self.border - 12 - ChangedFilesView.width >= Self.minTerminalWidth
    }

    func apply(_ appearance: TerminalAppearance) {
        terminalAppearance = appearance
        theme = appearance.theme
        header.theme = appearance.theme
        digestView.theme = appearance.theme
        changedFiles.theme = appearance.theme
        zoomButton.theme = appearance.theme
        closeButton.theme = appearance.theme
        terminal.apply(appearance)
    }

    private func changed() {
        // O agente parou de trabalhar: é a hora em que os arquivos acabaram de mudar.
        if reportedState == .working && machine.state != .working { diff.refresh() }
        reportedState = machine.state
        header.snapshot = snapshot
        changedFiles.state = diff.state
        needsDisplay = true
        delegate?.paneDidChange(self)
    }

    /// Menu do cabeçalho. Mostra só os nomes das variáveis removidas.
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionItem("Renomear…") { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } })
        // O `GLOBAL` não é projeto: não tem apelido.
        let nickname = actionItem("Apelidar projeto…") { [weak self] in
            self.map { $0.delegate?.paneRequestsNickname($0) }
        }
        nickname.isEnabled = !isGlobal
        menu.addItem(nickname)
        menu.addItem(actionItem("Zoom") { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } })
        menu.addItem(actionItem("Ver diff") { [weak self] in self.map { $0.delegate?.paneRequestsDiff($0) } })
        // O resumo do cabeçalho, que abre a coluna com um clique, some quando o cabeçalho é estreito.
        let files = actionItem("Arquivos alterados") { [weak self] in self?.toggleChangedFiles() }
        files.state = showsChangedFiles ? .on : .off
        menu.addItem(files)
        menu.addItem(actionItem("Novo agente nesta pasta") { [weak self] in
            self.map { $0.delegate?.paneRequestsSibling($0) }
        })
        menu.addItem(actionItem("Fechar") { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } })
        menu.addItem(.separator())
        // Sem o programa o painel é o shell de login, que relê o rc e devolve o que saiu do ambiente:
        // o menu não afirma uma remoção que não vale ali.
        guard launch.executable(for: tool) != nil else {
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
    private var digestHeight: Int { digestView.digest.map(SessionDigestView.height) ?? 0 }

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
        let stripBottom = headerBottom + (bypassesPermissions ? Self.stripHeight : 0)
        digestView.frame = NSRect(x: border, y: stripBottom, width: max(0, width - 2 * border), height: digestHeight)
        let bodyTop = stripBottom + digestHeight
        let column = showsChangedFiles && changedFilesFit ? ChangedFilesView.width : 0
        changedFiles.isHidden = column == 0
        changedFiles.frame = NSRect(x: width - border - column, y: bodyTop, width: column,
                                    height: max(0, height - border - bodyTop))
        let top = bodyTop + 4
        terminal.frame = NSRect(x: border + 6, y: top, width: max(1, width - 2 * border - 12 - column),
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
