import AppKit
import ClarkCore

/// Janela do CLARK: barra superior, modos foco e grade, zoom, atalhos, salvar e restaurar.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, AgentPaneDelegate {
    static let margin: CGFloat = 6
    static let fontStep = 0.1
    /// De quanto em quanto tempo o consumo do plano é relido, em segundos.
    static let usageInterval = 60.0

    private(set) var panes: [AgentPaneView] = []
    /// Agente do painel principal no modo foco.
    private(set) var mainPane: AgentPaneView?
    /// Agente cujo terminal está com o teclado.
    private(set) var focusedPane: AgentPaneView?
    private(set) var zoomedPane: AgentPaneView?
    private(set) var layoutMode: String
    private(set) var fontScale: Double
    private(set) var launch: AgentLaunch?
    let warnings = WarningBarView()
    let sidebar = SidebarView()
    let topBar = TopBarView()
    /// O app está na frente. Trocado nos testes, que rodam sem app ativo.
    var isAppActive: () -> Bool = { NSApplication.shared.isActive }
    /// A janela está com o teclado. Trocado nos testes, que rodam sem janela na tela.
    lazy var isWindowKey: () -> Bool = { [weak self] in self?.window?.isKeyWindow ?? false }
    /// Hora do relógio de parede, em segundos desde 1970. Trocada nos testes.
    var wallClock: () -> Double = { Date().timeIntervalSince1970 }
    /// Pasta de verdade de cada projeto aberto nesta execução, com a hora: os mais usados da cascata
    /// `Projeto` contam a abertura antes de o Claude Code gravar a conversa. Fica só na memória.
    private var openedProjects: [String: Date] = [:]
    /// Janela do diff, criada no primeiro pedido.
    private(set) var diffPanel: DiffWindowController?
    /// Nome com que a janela do diff guarda posição e tamanho. nil: não guarda.
    var diffAutosaveName: String?
    /// Põe uma janela auxiliar na tela. Trocado nos testes, que não abrem janela.
    var present: (NSWindowController) -> Void = { $0.showWindow(nil) }
    /// Quem mostra o menu do + AGENT.
    let pixelMenu = PixelMenu()
    /// Campo do "Digitar pasta…" do + AGENT, enquanto está aberto.
    private(set) var folderField: NSTextField?
    /// O que o agente da pasta digitada roda: o campo foi aberto pelo + AGENT ou pelo submenu Codex.
    private var folderTool = AgentTool.claude

    private var config: ClarkConfig
    private let store: ConfigStore
    private let home: String
    private let notifier: Notifying
    private let clock: () -> Double
    private let theme: Theme
    private let root = FlippedView()
    private let stage = FlippedView()
    private let emptyView = EmptyStateView()
    private var cards: [ObjectIdentifier: AgentCardView] = [:]
    private var timer: Timer?
    private var responderObservation: NSKeyValueObservation?
    private var activationObserver: NSObjectProtocol?
    private var renamePopover: NSPopover?
    private var folderPopover: NSPopover?
    private weak var renameTarget: AgentPaneView?
    /// O campo do popover está editando o apelido do projeto, não o nome do agente.
    private var renamesProject = false
    private var saveFailureWarned = false
    private var lastTitle = ""
    private var lastBadge = -1
    private var lastBlink = -1
    /// Quando o consumo do plano foi lido pela última vez, no relógio dos tiques.
    private var lastUsageRead: Double?

    init(config: ClarkConfig, store: ConfigStore, home: String, notifier: Notifying,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.config = config
        self.store = store
        self.home = home
        self.notifier = notifier
        self.clock = clock
        layoutMode = config.layout
        fontScale = config.fontScale
        theme = Theme.named(config.theme)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.title = "CLARK"
        window.backgroundColor = theme.bg.nsColor
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildViews(in: window)
        responderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            self?.firstResponderChanged()
        }
        // Voltar ao CLARK é o sinal de que algo pode ter mudado por fora: um commit no terminal, um editor.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDiffs()
            self?.refreshUsage()
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        notifier.onOpen = { [weak self] sessionID in
            guard let self, let pane = self.panes.first(where: { $0.sessionID == sessionID }) else { return }
            self.select(pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private var terminalAppearance: TerminalAppearance {
        TerminalAppearance(theme: theme, fontName: config.fontName, fontSize: config.fontSize * fontScale)
    }

    private func buildViews(in window: NSWindow) {
        root.frame = window.contentLayoutRect
        root.onLayout = { [weak self] in self?.layoutContent() }
        window.contentView = root
        for view in [topBar, warnings, sidebar, emptyView] as [PixelView] { view.theme = theme }
        [stage, emptyView, sidebar, warnings, topBar].forEach(root.addSubview)
        topBar.layoutButton.onClick = { [weak self] in self?.toggleLayout(nil) }
        topBar.addButton.onClick = { [weak self] in self?.newAgent(nil) }
        sidebar.closeAllButton.onClick = { [weak self] in self?.closeAllAgents(nil) }
        emptyView.onAdd = { [weak self] count in self?.addAgents(count) }
        warnings.onChange = { [weak self] in self?.layoutContent() }
        updateButtonTitles()
        layoutContent()
    }

    // MARK: início e fim

    /// Chamado uma vez, quando o ambiente do shell já foi lido.
    /// - Parameter openGlobalWhenEmpty: sem agente salvo nem pedido na linha de comando, abre um no `GLOBAL`.
    func start(launch: AgentLaunch, options: CLIOptions, startupWarnings: [String] = [],
               openGlobalWhenEmpty: Bool = true) {
        self.launch = launch
        startupWarnings.forEach(warnings.add)
        launch.resolver.warnings.forEach(warnings.add)
        if launch.claudePath == nil { warnings.add("claude nao encontrado: os agentes abrem o shell") }
        // `clark PASTA` abre os agentes pedidos nela; sozinho, sem `-n`, é um agente na pasta.
        // Se a pasta não existe, o agente pedido abre no GLOBAL, com o aviso.
        var requested = options.count
        var requestedDirectory = home
        if let directory = options.directory {
            requested = max(1, requested)
            if PathTools.isDirectory(directory) {
                requestedDirectory = directory
            } else {
                warnings.add("pasta nao encontrada: abrindo no GLOBAL")
            }
        }
        emptyView.isLoading = false
        updateButtonTitles()

        var created: [AgentPaneView] = []
        if !options.fresh {
            for saved in config.agents {
                let directory = saved.cwd ?? home
                // A pasta sumiu (uma worktree apagada): o agente abre na home, e a conversa antiga,
                // que é da outra pasta, não é retomada de lá.
                let vanished = !PathTools.isDirectory(directory)
                if vanished { warnings.add("pasta de agente sumiu: abriu na home, conversa nova") }
                let reused = saved.sessionID.map { id in panes.contains { $0.sessionID == id } } ?? false
                let name = saved.name.flatMap(AgentNaming.sanitized)
                    ?? AgentNaming.automaticName(existing: panes.map(\.name), tool: saved.tool)
                if let pane = makePane(name: name, directory: directory,
                                       sessionID: reused || vanished ? nil : saved.sessionID, tone: saved.tone,
                                       tool: saved.tool) {
                    created.append(pane)
                }
            }
            if panes.indices.contains(config.mainAgent) { mainPane = panes[config.mainAgent] }
        }
        // Nada salvo e nada pedido: o CLARK abre pronto para usar, com um agente no GLOBAL.
        if requested == 0, panes.isEmpty, openGlobalWhenEmpty { requested = 1 }
        for _ in 0..<requested {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name)),
                                      directory: requestedDirectory, sessionID: nil, tone: nil) else { break }
            created.append(pane)
            mainPane = pane
        }
        relayout()
        settleLayout()
        open(created)
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    /// Abre os processos dos painéis novos e, em quem começa conversa nova num projeto, o resumo da
    /// última sessão. As conversas dos agentes abertos ficam de fora: não são "a última".
    private func open(_ created: [AgentPaneView]) {
        created.forEach { $0.spawn() }
        let running = Set(panes.map(\.sessionID))
        created.forEach { $0.loadDigest(excluding: running) }
    }

    /// Quantos agentes ainda têm processo vivo.
    var liveAgentCount: Int { panes.filter { $0.state != .exited }.count }

    /// Grava a lista de agentes e encerra os processos. Chamado ao sair do app.
    func shutdown() {
        persist()
        timer?.invalidate()
        timer = nil
        responderObservation = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        diffPanel?.close()
        diffPanel = nil
        pixelMenu.close()
        panes.forEach { $0.shutdown() }
    }

    func persist() {
        // Antes do `start` a lista em memória está vazia: gravar apagaria os agentes salvos.
        guard launch != nil else { return }
        config.layout = layoutMode
        config.fontScale = fontScale
        config.agents = panes.map {
            SavedAgent(name: $0.name, cwd: $0.directory, sessionID: $0.sessionID, tone: $0.tone, tool: $0.tool)
        }
        config.mainAgent = mainPane.flatMap { main in panes.firstIndex { $0 === main } } ?? 0
        // Falha de gravação não interrompe nada: o estado em memória segue valendo, e fica o aviso.
        // Um aviso por sessão: dispensado, ele não volta a cada gravação que falha.
        do {
            try store.save(config)
        } catch {
            guard !saveFailureWarned else { return }
            saveFailureWarned = true
            warnings.add("config.json nao gravado: os agentes nao voltam ao reabrir")
        }
    }

    // MARK: agentes

    /// Cria o painel sem abrir o processo: o `spawn` vem depois do layout, com o terminal já no tamanho certo.
    private func makePane(name: String, directory: String, sessionID: String?, tone: Int?,
                          tool: AgentTool = .claude) -> AgentPaneView? {
        guard let launch, panes.count < ClarkConfig.maxAgents else { return nil }
        let company = launch.company(forDirectory: directory)
        let usedTones = panes.filter { $0.company.name == company.name }.map(\.tone)
        let pane = AgentPaneView(name: name, directory: directory, sessionID: sessionID ?? SessionLocator.newID(),
                                 tone: tone ?? AgentNaming.freeTone(used: usedTones), launch: launch,
                                 tool: tool, nicknames: config.projectNames, appearance: terminalAppearance, clock: clock)
        pane.delegate = self
        panes.append(pane)
        stage.addSubview(pane)
        let card = AgentCardView(snapshot: pane.snapshot)
        card.onSelect = { [weak self, weak pane] in
            if let self, let pane { self.select(pane) }
        }
        card.onClose = { [weak self, weak pane] in
            if let self, let pane { self.close(pane) }
        }
        cards[ObjectIdentifier(pane)] = card
        return pane
    }

    /// Abre agentes novos. Sem pasta, abrem no `GLOBAL` (a home), fora de projeto.
    func addAgents(_ count: Int, in directory: String? = nil, tool: AgentTool = .claude) {
        guard launch != nil else { return }
        var created: [AgentPaneView] = []
        for _ in 0..<max(0, count) {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name), tool: tool),
                                      directory: directory ?? home, sessionID: nil, tone: nil, tool: tool) else { break }
            created.append(pane)
        }
        if created.count < count {
            warnings.add("limite de \(ClarkConfig.maxAgents) agentes: feche um para abrir outro")
        }
        guard let last = created.last else { return }
        mainPane = last
        if zoomedPane != nil { zoomedPane = last }
        relayout()
        settleLayout()
        open(created)
        focusTerminal(of: last)
        persist()
    }

    func close(_ pane: AgentPaneView) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        pane.delegate = nil
        diffPanel?.paneClosed(pane)
        pane.shutdown()
        pane.removeFromSuperview()
        panes.remove(at: index)
        cards[ObjectIdentifier(pane)] = nil
        if zoomedPane === pane { zoomedPane = nil }
        if focusedPane === pane { focusedPane = nil }
        if mainPane === pane { mainPane = panes.isEmpty ? nil : panes[min(index, panes.count - 1)] }
        relayout()
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    /// Traz o agente para o painel principal e põe o teclado no terminal dele (`select` do original).
    func select(_ pane: AgentPaneView) {
        guard panes.contains(where: { $0 === pane }) else { return }
        mainPane = pane
        if zoomedPane != nil { zoomedPane = pane }
        if zoomedPane != nil || layoutMode == "focus" { relayout() }
        focusTerminal(of: pane)
        persist()
    }

    func toggleZoom(of pane: AgentPaneView) {
        zoomedPane = zoomedPane === pane ? nil : pane
        if zoomedPane != nil { mainPane = pane }
        relayout()
        focusTerminal(of: pane)
    }

    func applyRename(_ pane: AgentPaneView, text: String) {
        guard let name = AgentNaming.sanitized(text) else { return }
        pane.rename(name)
        persist()
    }

    /// Dá, troca ou tira o apelido do projeto do agente. O apelido fica na pasta que dá o nome ao
    /// projeto (o repositório), e vale para todo agente aberto nela. Texto vazio, ou igual ao nome da
    /// pasta arrumado, tira o apelido.
    func applyNickname(_ pane: AgentPaneView, text: String) {
        guard let launch,
              let path = launch.namedPath(forDirectory: pane.directory, nicknames: config.projectNames) else { return }
        // A mesma pasta pode estar no arquivo escrita de outro jeito (com `~`, por um link).
        var names = config.projectNames.filter { launch.canonical($0.key) != path }
        let folder = PathTools.components(path).last.map(ProjectNaming.tidy)
        if let nickname = ProjectNaming.sanitizedNickname(text), nickname != folder { names[path] = nickname }
        guard names != config.projectNames else { return }
        config.projectNames = names
        panes.forEach { $0.updateProject(nicknames: names) }
        refreshCards()
        persist()
    }

    // MARK: diff

    /// A janela do diff, mostrando o agente. Não a põe na tela.
    func diffPanel(for pane: AgentPaneView) -> DiffWindowController {
        let panel = diffPanel ?? {
            let created = DiffWindowController(theme: theme, home: home)
            if let diffAutosaveName { created.window?.setFrameAutosaveName(diffAutosaveName) }
            return created
        }()
        diffPanel = panel
        panel.attach(to: pane)
        return panel
    }

    /// Abre a janela do diff no agente, com uma leitura nova do repositório.
    /// - Parameter path: arquivo que a janela já abre mostrando. Sem ele, o que estava escolhido ou o primeiro.
    private func presentDiff(of pane: AgentPaneView, path: String? = nil) {
        let panel = diffPanel(for: pane)
        if let path { panel.select(path: path) }
        pane.diff.refresh()
        present(panel)
    }

    func refreshDiffs() {
        panes.forEach { $0.diff.refresh() }
    }

    /// Relê o consumo do plano do arquivo que o AiUsageBar mantém. Sem ele, a barra fica sem o medidor.
    func refreshUsage() {
        lastUsageRead = clock()
        topBar.usage = UsageMeter.read(path: UsageMeter.path(home: home), now: wallClock())
    }

    func setFontScale(_ scale: Double) {
        let range = ClarkConfig.fontScaleRange
        let clamped = (min(range.upperBound, max(range.lowerBound, scale)) * 100).rounded() / 100
        guard clamped != fontScale else { return }
        fontScale = clamped
        for pane in panes {
            pane.apply(terminalAppearance)
            pane.layoutChanged()
        }
        persist()
    }

    // MARK: projetos

    static let companyFolderTitle = "Pasta da empresa"
    static let otherFoldersTitle = "Outras pastas"
    static let worktreesTitle = "Worktrees"
    static let otherFolderTitle = "Outra pasta…"
    static let mostUsedTitle = "Mais usados"
    static let companiesTitle = "Empresas"
    static let agentProjectTitle = "Projeto"
    static let typedFolderTitle = "Digitar pasta…"
    static let codexTitle = "Codex"

    /// Cascata `Projeto` do + AGENT e do ⌘D, relida do disco a cada abertura: os projetos mais usados,
    /// uma empresa por linha com os projetos dela a um clique e as pastas apelidadas fora de toda
    /// empresa.
    func projectMenu() -> NSMenu {
        let menu = NSMenu(title: Self.agentProjectTitle)
        let groups = launch?.projectGroups(nicknames: config.projectNames) ?? []
        let companies = groups.filter { !$0.folders.isEmpty }.map(companyItem)
        Self.fill(menu, with: [
            mostUsedItems(groups),
            companies.isEmpty ? [] : [.sectionHeader(title: Self.companiesTitle)] + companies,
            groups.filter { $0.folders.isEmpty }.flatMap(\.nicknamed).map(projectItem),
        ])
        return menu
    }

    /// Bloco de cima do menu: as pastas em que o Claude Code mais foi usado, entre tudo o que o menu
    /// oferece nas empresas e nas apelidadas, juntas sob o nome da empresa. A empresa do mais usado vem
    /// primeiro. A home não entra na conta: é o `GLOBAL` do + AGENT.
    private func mostUsedItems(_ groups: [ProjectGroup]) -> [NSMenuItem] {
        guard let launch else { return [] }
        // Pela pasta de verdade: é por ela que o Claude Code guarda a conversa de quem entrou por um link.
        var offered: [String: (title: String, path: String, group: Int)] = [:]
        var order: [String] = []
        func offer(_ title: String, _ path: String, group: Int) {
            let real = launch.canonical(path)
            guard offered[real] == nil else { return }
            offered[real] = (title, path, group)
            order.append(real)
        }
        for (index, group) in groups.enumerated() {
            let deep = group.sections.flatMap { ($0.folder.map { [$0] } ?? []) + $0.projects }
            for entry in group.nicknamed + group.projects + deep + group.worktrees + group.others {
                offer(entry.name, entry.path, group: index)
            }
            for folder in group.folders {
                let title = group.folders.count == 1 ? Self.companyFolderTitle : PathTools.short(folder, home: home)
                offer(title, folder, group: index)
            }
        }
        let configDir = SessionLocator.configDir(environment: launch.baseEnvironment, home: launch.home)
        let now = Date(timeIntervalSince1970: wallClock())
        // As conversas do Codex contam junto: o projeto é o mesmo, seja qual for o programa.
        let codex = launch.codexPath == nil ? [:] : CodexSessions.usage(
            codexHome: CodexSessions.home(environment: launch.baseEnvironment, home: launch.home), now: now,
            canonicalize: launch.canonical)
        let used = ProjectUsage.mostUsed(order, configDir: configDir, now: now, opened: openedProjects, extra: codex)
            .compactMap { offered[$0] }
        guard !used.isEmpty else { return [] }
        var items = [NSMenuItem.sectionHeader(title: Self.mostUsedTitle)]
        var seen: Set<Int> = []
        for index in used.map(\.group) where seen.insert(index).inserted {
            // Sob o nome da empresa, dois projetos `Api` não se confundem. A apelidada fora de toda
            // empresa não tem nome em cima nem recuo.
            let company = !groups[index].folders.isEmpty
            if company { items.append(companyLabel(groups[index])) }
            for suggestion in used where suggestion.group == index {
                let item = projectItem(suggestion.title, path: suggestion.path)
                item.indentationLevel = company ? 1 : 0
                items.append(item)
            }
        }
        return items
    }

    /// Os blocos que têm item, com um separador entre eles.
    private static func fill(_ menu: NSMenu, with blocks: [[NSMenuItem]]) {
        for block in blocks where !block.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            block.forEach(menu.addItem)
        }
    }

    private func projectItem(_ title: String, path: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openProject(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = path
        item.toolTip = PathTools.short(path, home: home)
        return item
    }

    private func projectItem(_ entry: ProjectEntry) -> NSMenuItem {
        projectItem(entry.name, path: entry.path)
    }

    /// Linha que abre um submenu com os blocos que têm item.
    private static func submenuItem(_ title: String, blocks: [[NSMenuItem]]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        fill(submenu, with: blocks)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }

    /// Linha de uma empresa, em maiúsculas e com o quadradinho da cor dela, como a etiqueta no
    /// cabeçalho do agente. O submenu traz, de cima para baixo: os projetos apelidados, os do
    /// primeiro nível, um grupo por pasta que guarda projetos mais fundos, as worktrees, as pastas
    /// que não são projeto e a pasta da própria empresa. O clique na linha abre o agente na pasta da
    /// empresa; o cursor e a seta abrem o submenu.
    private func companyItem(_ group: ProjectGroup) -> NSMenuItem {
        let item = companyEntries(group, title: group.name.uppercased())
        item.image = swatch(group)
        // Com mais de uma pasta não há uma só para abrir: fica só o submenu.
        if item.hasSubmenu, group.folders.count == 1 {
            item.action = #selector(openProject(_:))
            item.target = self
            item.representedObject = group.folders[0]
            item.toolTip = PathTools.short(group.folders[0], home: home)
        }
        return item
    }

    /// Nome da empresa sobre os projetos dela nos mais usados: a mesma cara da linha da empresa,
    /// apagada, porque não é uma escolha.
    private func companyLabel(_ group: ProjectGroup) -> NSMenuItem {
        let label = NSMenuItem(title: group.name.uppercased(), action: nil, keyEquivalent: "")
        label.isEnabled = false
        label.image = swatch(group)
        return label
    }

    /// Quadradinho da cor da empresa, como a etiqueta no cabeçalho do agente.
    private func swatch(_ group: ProjectGroup) -> NSImage? {
        guard let launch, let folder = group.folders.first else { return nil }
        return PixelMenuView.swatch(launch.company(forDirectory: folder).color)
    }

    private func companyEntries(_ group: ProjectGroup, title: String) -> NSMenuItem {
        // Empresa de uma pasta só, sem nada dentro para escolher, abre direto.
        if group.isBare, group.folders.count == 1 { return projectItem(title, path: group.folders[0]) }
        var folders: [NSMenuItem] = []
        if !group.worktrees.isEmpty {
            folders.append(Self.submenuItem(Self.worktreesTitle, blocks: [group.worktrees.map(projectItem)]))
        }
        if !group.others.isEmpty {
            folders.append(Self.submenuItem(Self.otherFoldersTitle, blocks: [group.others.map(projectItem)]))
        }
        if group.folders.count == 1 {
            folders.append(projectItem(Self.companyFolderTitle, path: group.folders[0]))
        } else {
            folders += group.folders.map { projectItem(PathTools.short($0, home: home), path: $0) }
        }
        return Self.submenuItem(title, blocks: [
            group.nicknamed.map(projectItem),
            group.projects.map(projectItem) + group.sections.map(sectionItem),
            folders,
        ])
    }

    /// Grupo dos projetos de uma pasta. Quando a própria pasta é um projeto, ela vem em cima.
    private func sectionItem(_ section: ProjectSection) -> NSMenuItem {
        let holder = Self.submenuItem(section.title, blocks: [
            section.folder.map { [projectItem($0)] } ?? [], section.projects.map(projectItem),
        ])
        holder.toolTip = PathTools.short(section.path, home: home)
        return holder
    }

    /// Menu do + AGENT, do ⌘N e do ⌘D: onde o agente novo abre. O `GLOBAL`, a cascata `Projeto`, que
    /// some quando não há nenhum, uma pasta digitada, qualquer pasta escolhida no Finder e, com o
    /// `codex` instalado, tudo isso de novo no submenu Codex.
    func agentMenu() -> NSMenu { agentMenu(codex: true) }

    private func agentMenu(codex: Bool) -> NSMenu {
        let menu = NSMenu(title: "Novo agente")
        menu.addItem(projectItem(ProjectNaming.global, path: home))
        let projects = projectMenu()
        if !projects.items.isEmpty {
            let holder = NSMenuItem(title: Self.agentProjectTitle, action: nil, keyEquivalent: "")
            holder.submenu = projects
            menu.addItem(holder)
        }
        for (title, action) in [(Self.typedFolderTitle, #selector(typeFolder(_:))),
                                (Self.otherFolderTitle, #selector(chooseFolder(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if codex, let item = codexItem() {
            menu.addItem(.separator())
            menu.addItem(item)
        }
        return menu
    }

    /// O mesmo menu, abrindo o agente com o Codex. Sem o `codex` instalado, não aparece.
    private func codexItem() -> NSMenuItem? {
        guard launch?.codexPath != nil else { return nil }
        let menu = NSMenu(title: Self.codexTitle)
        let source = agentMenu(codex: false)
        for item in source.items {
            source.removeItem(item)
            menu.addItem(item)
        }
        Self.retarget(menu)
        let holder = NSMenuItem(title: Self.codexTitle, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    /// Troca as ações do menu pelas que abrem o agente com o Codex.
    private static func retarget(_ menu: NSMenu) {
        let codex: [Selector: Selector] = [
            #selector(openProject(_:)): #selector(openCodexProject(_:)),
            #selector(typeFolder(_:)): #selector(typeCodexFolder(_:)),
            #selector(chooseFolder(_:)): #selector(chooseCodexFolder(_:)),
        ]
        for item in menu.items {
            if let action = item.action, let replacement = codex[action] { item.action = replacement }
            if let submenu = item.submenu { retarget(submenu) }
        }
    }

    /// Abre um agente na pasta digitada no + AGENT. Aceita `~` e caminho relativo à pasta do agente em
    /// foco. Texto vazio não abre nada.
    func openTypedFolder(_ text: String, tool: AgentTool = .claude) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        openAgent(in: PathTools.absolute(typed, base: currentPane?.directory ?? home, home: home), tool: tool)
    }

    /// Abre um agente na pasta do projeto.
    func openAgent(in directory: String, tool: AgentTool = .claude) {
        guard let launch else { return }
        guard PathTools.isDirectory(directory) else {
            warnings.add("pasta nao encontrada: nada foi aberto")
            return
        }
        openedProjects[launch.canonical(directory)] = Date(timeIntervalSince1970: wallClock())
        addAgents(1, in: directory, tool: tool)
    }

    /// Agente sobre o qual os atalhos agem.
    var currentPane: AgentPaneView? {
        if let zoomedPane { return zoomedPane }
        return layoutMode == "focus" ? mainPane : (focusedPane ?? mainPane)
    }

    private func focusTerminal(of pane: AgentPaneView) {
        window?.makeFirstResponder(pane.terminal)
    }

    private func firstResponderChanged() {
        var view = window?.firstResponder as? NSView
        while let current = view, !(current is AgentPaneView) { view = current.superview }
        guard let pane = view as? AgentPaneView, pane !== focusedPane else { return }
        focusedPane = pane
        for other in panes { other.isFocused = other === pane }
        pane.focused()
        if layoutMode == "grid", zoomedPane == nil, mainPane !== pane {
            mainPane = pane
            refreshCards()
        }
    }

    // MARK: layout

    /// Refaz o layout depois de uma mudança na lista de agentes, no modo ou no zoom.
    func relayout() {
        if let main = mainPane, !panes.contains(where: { $0 === main }) { mainPane = nil }
        if mainPane == nil { mainPane = focusedPane ?? panes.first }
        sidebar.setCards(panes.compactMap { cards[ObjectIdentifier($0)] })
        layoutContent()
        let now = clock()
        for pane in panes {
            if !pane.isHidden { pane.layoutChanged() }
            pane.refreshPreview(now: now, force: true)
        }
        refreshCards()
        refreshChrome()
    }

    /// Fecha o layout pendente antes de abrir processos: o terminal já nasce com as colunas
    /// e linhas finais, e o agente não recebe um redimensionamento logo na largada.
    private func settleLayout() {
        for pane in panes { pane.needsLayout = true }
        root.layoutSubtreeIfNeeded()
    }

    /// Painéis que aparecem no layout atual.
    var visiblePanes: [AgentPaneView] {
        if let zoomedPane { return [zoomedPane] }
        if layoutMode == "focus" { return mainPane.map { [$0] } ?? [] }
        return panes
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        topBar.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(TopBarView.height))
        var top = CGFloat(TopBarView.height)
        warnings.isHidden = warnings.messages.isEmpty
        if !warnings.isHidden {
            warnings.frame = NSRect(x: 0, y: top, width: width, height: CGFloat(WarningBarView.height))
            top += CGFloat(WarningBarView.height)
        }
        let body = NSRect(x: 0, y: top, width: width, height: max(0, height - top))
        emptyView.frame = body
        emptyView.isHidden = !panes.isEmpty
        let showSidebar = layoutMode == "focus" && zoomedPane == nil && panes.count > 1
        let sidebarWidth = showSidebar ? CGFloat(SidebarView.width) : 0
        sidebar.isHidden = !showSidebar
        sidebar.frame = NSRect(x: body.maxX - sidebarWidth, y: body.minY, width: sidebarWidth, height: body.height)
        stage.isHidden = panes.isEmpty
        stage.frame = NSRect(x: 0, y: body.minY, width: max(0, body.width - sidebarWidth), height: body.height)

        let margin = Self.margin
        let area = NSRect(x: margin, y: margin, width: max(1, stage.bounds.width - 2 * margin),
                          height: max(1, stage.bounds.height - 2 * margin))
        let visible = visiblePanes
        if layoutMode == "grid" && zoomedPane == nil {
            // As colunas saem da proporção da janela inteira, como no original.
            let columns = GridLayout.columns(count: visible.count, width: Double(width), height: Double(height))
            let frames = GridLayout.frames(count: visible.count, columns: columns, width: Double(area.width),
                                           height: Double(area.height), spacing: Double(margin))
            for (pane, frame) in zip(visible, frames) {
                setFrame(pane, NSRect(x: area.minX + CGFloat(frame.x), y: area.minY + CGFloat(frame.y),
                                      width: CGFloat(frame.width), height: CGFloat(frame.height)))
            }
        } else {
            // Os painéis ocultos ficam do tamanho do principal: trocar de agente não muda as colunas do terminal.
            for pane in panes { setFrame(pane, area) }
        }
        for pane in panes {
            let hidden = !visible.contains { $0 === pane }
            if pane.isHidden != hidden { pane.isHidden = hidden }
        }
    }

    private func setFrame(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
    }

    private func refreshCards() {
        let active = zoomedPane ?? mainPane
        for (index, pane) in panes.enumerated() {
            guard let card = cards[ObjectIdentifier(pane)] else { continue }
            card.index = index + 1
            card.isActive = pane === active
            card.snapshot = pane.snapshot
        }
    }

    private func refreshChrome() {
        let states = panes.map(\.state)
        topBar.stats = AgentStats(states: states)
        let done = states.filter { $0 == .done }.count
        let title = (done > 0 ? "(\(done)) " : "") + "CLARK — \(panes.count) agentes"
        if title != lastTitle {
            lastTitle = title
            window?.title = title
        }
        if done != lastBadge {
            lastBadge = done
            notifier.setBadge(done)
        }
    }

    private func updateButtonTitles() {
        topBar.layoutButton.title = layoutMode == "focus" ? "FOCO" : "GRADE"
        topBar.needsLayout = true
        topBar.needsDisplay = true
    }

    /// Tique de 100 ms: estados, prévias dos cards e animações do que está visível.
    func tick() {
        let now = clock()
        for pane in panes { pane.tick(now: now) }
        if !sidebar.isHidden {
            for pane in panes {
                guard let card = cards[ObjectIdentifier(pane)] else { continue }
                if pane.refreshPreview(now: now) { card.snapshot = pane.snapshot }
                if StateLabel.isAnimated(pane.state) { card.time = now }
            }
        }
        let blink = Int(now * 2)
        if panes.isEmpty && blink != lastBlink { emptyView.time = now }
        lastBlink = blink
        if lastUsageRead.map({ now - $0 >= Self.usageInterval }) ?? true { refreshUsage() }
        refreshChrome()
    }

    // MARK: AgentPaneDelegate

    func paneIsWatched(_ pane: AgentPaneView) -> Bool {
        pane === focusedPane && !pane.isHidden && isWindowKey() && isAppActive()
    }

    func paneNeedsAttention(_ pane: AgentPaneView) {
        if !isAppActive() { notifier.agentDone(name: pane.name, place: pane.place, sessionID: pane.sessionID) }
    }

    func paneDidChange(_ pane: AgentPaneView) {
        cards[ObjectIdentifier(pane)]?.snapshot = pane.snapshot
        diffPanel?.paneDidChange(pane)
        refreshChrome()
    }

    func paneSessionDidChange(_ pane: AgentPaneView) { persist() }

    func paneSessionsInUse(_ pane: AgentPaneView) -> Set<String> {
        Set(panes.filter { $0 !== pane }.map(\.sessionID))
    }

    func paneRequestsDiff(_ pane: AgentPaneView) { presentDiff(of: pane) }
    func paneRequestsDiff(_ pane: AgentPaneView, path: String) { presentDiff(of: pane, path: path) }
    func paneRequestsSelect(_ pane: AgentPaneView) { select(pane) }
    func paneRequestsZoom(_ pane: AgentPaneView) { toggleZoom(of: pane) }
    func paneRequestsClose(_ pane: AgentPaneView) { close(pane) }

    func paneRequestsSibling(_ pane: AgentPaneView) { addAgents(1, in: pane.directory, tool: pane.tool) }

    func paneRequestsRename(_ pane: AgentPaneView) {
        presentNameField(for: pane, text: pane.name, placeholder: "Nome do agente", project: false)
    }

    func paneRequestsNickname(_ pane: AgentPaneView) {
        guard !pane.isGlobal else { return }
        presentNameField(for: pane, text: pane.project, placeholder: "Apelido (vazio: o nome da pasta)",
                         project: true)
    }

    /// Campo de texto num popover sob o cabeçalho do agente: o nome dele ou o apelido do projeto.
    private func presentNameField(for pane: AgentPaneView, text: String, placeholder: String, project: Bool) {
        renamePopover?.close()
        let (popover, field) = fieldPopover(text: text, placeholder: placeholder, width: 240,
                                            action: #selector(commitRename(_:)))
        renamePopover = popover
        renameTarget = pane
        renamesProject = project
        popover.show(relativeTo: pane.header.bounds, of: pane.header, preferredEdge: .maxY)
        field.selectText(nil)
    }

    /// Popover com um campo de texto que só confirma no Enter: clicar fora fecha sem fazer nada.
    private func fieldPopover(text: String, placeholder: String, width: CGFloat,
                              action: Selector) -> (NSPopover, NSTextField) {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 10, y: 10, width: width, height: 24)
        field.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        field.target = self
        field.action = action
        field.cell?.sendsActionOnEndEditing = false
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: width + 20, height: 44))
        content.view.addSubview(field)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        return (popover, field)
    }

    @objc private func commitRename(_ sender: NSTextField) {
        renamePopover?.close()
        renamePopover = nil
        guard let pane = renameTarget else { return }
        if renamesProject {
            applyNickname(pane, text: sender.stringValue)
        } else {
            applyRename(pane, text: sender.stringValue)
        }
        focusTerminal(of: pane)
    }

    // MARK: janela

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Fechar a janela é sair do app, e a saída pede confirmação com agentes vivos.
        NSApplication.shared.terminate(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusedPane?.focused()
    }

    // MARK: menu

    /// ⌘N e + AGENT: pergunta onde o agente abre, num menu logo abaixo do botão.
    @objc func newAgent(_ sender: Any?) {
        guard launch != nil else { return }
        pixelMenu.theme = theme
        pixelMenu.show(agentMenu(), below: topBar.addButton)
    }

    /// "Digitar pasta…" do + AGENT: campo de texto sob o botão. O Enter abre o agente na pasta.
    @objc func typeFolder(_ sender: Any?) { typeFolder(tool: .claude) }

    /// "Digitar pasta…" do submenu Codex.
    @objc func typeCodexFolder(_ sender: Any?) { typeFolder(tool: .codex) }

    private func typeFolder(tool: AgentTool) {
        guard launch != nil else { return }
        folderTool = tool
        folderPopover?.close()
        let (popover, field) = fieldPopover(text: "", placeholder: "Pasta: ~/Projetos/... ou relativa",
                                            width: 360, action: #selector(commitTypedFolder(_:)))
        folderPopover = popover
        folderField = field
        // O botão é flipped: `maxY` é a borda de baixo.
        popover.show(relativeTo: topBar.addButton.bounds, of: topBar.addButton, preferredEdge: .maxY)
        field.selectText(nil)
    }

    @objc private func commitTypedFolder(_ sender: NSTextField) {
        folderPopover?.close()
        folderPopover = nil
        folderField = nil
        openTypedFolder(sender.stringValue, tool: folderTool)
    }

    /// Mais um agente na pasta do agente atual.
    @objc func newSiblingAgent(_ sender: Any?) {
        if let pane = currentPane { paneRequestsSibling(pane) }
    }

    @objc func closeAgent(_ sender: Any?) {
        if let pane = currentPane {
            close(pane)
        } else {
            window?.performClose(sender)
        }
    }

    /// Botões do diálogo "Fechar agentes?", na ordem, com os agentes que cada um fecha.
    func closeAllChoices() -> [(title: String, panes: [AgentPaneView])] {
        var choices: [(title: String, panes: [AgentPaneView])] = [("Cancelar", [])]
        let current = currentPane
        let others = panes.filter { $0 !== current }
        if !others.isEmpty && others.count < panes.count {
            choices.append(("Só os outros (\(others.count))", others))
        }
        choices.append(("Todos (\(panes.count))", panes))
        return choices
    }

    @objc func closeAllAgents(_ sender: Any?) {
        guard !panes.isEmpty else { return }
        let choices = closeAllChoices()
        let alert = NSAlert()
        alert.messageText = "Fechar agentes?"
        alert.informativeText = "As conversas continuam salvas no Claude (claude --resume), "
            + "mas os agentes fechados não voltam ao reabrir o CLARK."
        choices.forEach { alert.addButton(withTitle: $0.title) }
        let choice = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(choice) else { return }
        choices[choice].panes.forEach(close)
    }

    /// ⌘D: o menu do + AGENT já dentro da cascata `Projeto`, pronto para as setas.
    @objc func chooseProject(_ sender: Any?) {
        guard launch != nil else { return }
        let menu = agentMenu()
        pixelMenu.theme = theme
        pixelMenu.show(menu, below: topBar.addButton, entering: menu.items.first { $0.hasSubmenu })
    }

    /// ⇧⌘C: numera as linhas do terminal do agente atual para escolher e copiar pelo teclado.
    /// ⌘L: conversa nova no agente em foco, sem parar o processo.
    @objc func resetContext(_ sender: Any?) {
        if currentPane?.resetContext() != true { NSSound.beep() }
    }

    @objc func copyLines(_ sender: Any?) {
        if currentPane?.terminal.beginLineSelection() != true { NSSound.beep() }
    }

    @objc func openProject(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openAgent(in: path) }
    }

    /// Pasta escolhida no submenu Codex do + AGENT.
    @objc func openCodexProject(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openAgent(in: path, tool: .codex) }
    }

    /// "Outra pasta…" do + AGENT: qualquer pasta do disco.
    @objc func chooseFolder(_ sender: Any?) { chooseFolder(tool: .claude) }

    /// "Outra pasta…" do submenu Codex.
    @objc func chooseCodexFolder(_ sender: Any?) { chooseFolder(tool: .codex) }

    private func chooseFolder(tool: AgentTool) {
        guard let window, launch != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentPane?.directory ?? home)
        panel.prompt = "Escolher"
        panel.message = "Pasta onde o agente abre"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let path = panel.url?.path { self?.openAgent(in: path, tool: tool) }
        }
    }

    @objc func toggleLayout(_ sender: Any?) {
        layoutMode = layoutMode == "focus" ? "grid" : "focus"
        zoomedPane = nil
        updateButtonTitles()
        relayout()
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    @objc func toggleZoom(_ sender: Any?) {
        if let pane = currentPane { toggleZoom(of: pane) }
    }

    @objc func nextAgent(_ sender: Any?) { step(by: 1) }
    @objc func previousAgent(_ sender: Any?) { step(by: -1) }

    private func step(by delta: Int) {
        guard panes.count > 1, let current = currentPane,
              let index = panes.firstIndex(where: { $0 === current }) else { return }
        select(panes[(index + delta + panes.count) % panes.count])
    }

    /// ⌘1 a ⌘9: o número vem na `tag` do item.
    @objc func selectAgentByNumber(_ sender: NSMenuItem) {
        guard (1...panes.count).contains(sender.tag) else { return }
        select(panes[sender.tag - 1])
    }

    @objc func renameAgent(_ sender: Any?) {
        if let pane = currentPane { paneRequestsRename(pane) }
    }

    @objc func nicknameProject(_ sender: Any?) {
        if let pane = currentPane { paneRequestsNickname(pane) }
    }

    @objc func showDiff(_ sender: Any?) {
        if let pane = currentPane { presentDiff(of: pane) }
    }

    @objc func refreshDiff(_ sender: Any?) { refreshDiffs() }

    @objc func increaseFont(_ sender: Any?) { setFontScale(fontScale + Self.fontStep) }
    @objc func decreaseFont(_ sender: Any?) { setFontScale(fontScale - Self.fontStep) }
    @objc func resetFont(_ sender: Any?) { setFontScale(1) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newAgent(_:)):
            return launch != nil && panes.count < ClarkConfig.maxAgents
        case #selector(newSiblingAgent(_:)):
            return !panes.isEmpty && panes.count < ClarkConfig.maxAgents
        case #selector(nicknameProject(_:)):
            return currentPane.map { !$0.isGlobal } ?? false
        case #selector(chooseProject(_:)), #selector(openProject(_:)), #selector(chooseFolder(_:)),
             #selector(typeFolder(_:)):
            return launch != nil
        case #selector(openCodexProject(_:)), #selector(chooseCodexFolder(_:)), #selector(typeCodexFolder(_:)):
            return launch?.codexPath != nil
            return launch != nil
        case #selector(copyLines(_:)):
            return currentPane != nil
        case #selector(resetContext(_:)):
            return currentPane?.canResetContext == true
        case #selector(closeAllAgents(_:)), #selector(toggleZoom(_:)), #selector(renameAgent(_:)),
             #selector(showDiff(_:)), #selector(refreshDiff(_:)):
            return !panes.isEmpty
        case #selector(nextAgent(_:)), #selector(previousAgent(_:)):
            return panes.count > 1
        case #selector(selectAgentByNumber(_:)):
            return menuItem.tag <= panes.count
        default:
            return true
        }
    }
}
