import AppKit
import ClarkCore

/// Janela do CLARK: barra superior, modos foco e grade, zoom, atalhos, salvar e restaurar.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, AgentPaneDelegate {
    static let margin: CGFloat = 6
    static let fontStep = 0.1

    private(set) var panes: [AgentPaneView] = []
    /// Agente do painel principal no modo foco.
    private(set) var mainPane: AgentPaneView?
    /// Agente cujo terminal está com o teclado.
    private(set) var focusedPane: AgentPaneView?
    private(set) var zoomedPane: AgentPaneView?
    private(set) var layoutMode: String
    /// Pasta do último projeto escolhido: é onde o ⌘N e o + AGENT abrem.
    private(set) var defaultDirectory: String
    private(set) var fontScale: Double
    private(set) var launch: AgentLaunch?
    let warnings = WarningBarView()
    let sidebar = SidebarView()
    let topBar = TopBarView()
    /// O app está na frente. Trocado nos testes, que rodam sem app ativo.
    var isAppActive: () -> Bool = { NSApplication.shared.isActive }
    /// A janela está com o teclado. Trocado nos testes, que rodam sem janela na tela.
    lazy var isWindowKey: () -> Bool = { [weak self] in self?.window?.isKeyWindow ?? false }
    /// Janela do diff, criada no primeiro pedido.
    private(set) var diffPanel: DiffWindowController?
    /// Nome com que a janela do diff guarda posição e tamanho. nil: não guarda.
    var diffAutosaveName: String?
    /// Põe uma janela auxiliar na tela. Trocado nos testes, que não abrem janela.
    var present: (NSWindowController) -> Void = { $0.showWindow(nil) }

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
    private weak var renameTarget: AgentPaneView?
    private var saveFailureWarned = false
    private var lastTitle = ""
    private var lastBadge = -1
    private var lastBlink = -1

    init(config: ClarkConfig, store: ConfigStore, home: String, notifier: Notifying,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.config = config
        self.store = store
        self.home = home
        self.notifier = notifier
        self.clock = clock
        layoutMode = config.layout
        fontScale = config.fontScale
        defaultDirectory = config.cwd.flatMap { PathTools.isDirectory($0) ? $0 : nil } ?? home
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
        ) { [weak self] _ in self?.refreshDiffs() }
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
        topBar.projectButton.onClick = { [weak self] in self?.chooseProject(nil) }
        topBar.layoutButton.onClick = { [weak self] in self?.toggleLayout(nil) }
        topBar.addButton.onClick = { [weak self] in self?.addAgents(1) }
        sidebar.closeAllButton.onClick = { [weak self] in self?.closeAllAgents(nil) }
        emptyView.onAdd = { [weak self] count in self?.addAgents(count) }
        warnings.onChange = { [weak self] in self?.layoutContent() }
        updateButtonTitles()
        layoutContent()
    }

    // MARK: início e fim

    /// Chamado uma vez, quando o ambiente do shell já foi lido.
    func start(launch: AgentLaunch, options: CLIOptions, startupWarnings: [String] = []) {
        self.launch = launch
        startupWarnings.forEach(warnings.add)
        launch.resolver.warnings.forEach(warnings.add)
        if launch.claudePath == nil { warnings.add("claude nao encontrado: os agentes abrem o shell") }
        if let directory = options.directory {
            if PathTools.isDirectory(directory) {
                defaultDirectory = directory
            } else {
                warnings.add("pasta nao encontrada: valendo a anterior")
            }
        }
        emptyView.isLoading = false
        updateButtonTitles()

        var created: [AgentPaneView] = []
        if !options.fresh {
            for saved in config.agents {
                let directory = saved.cwd ?? defaultDirectory
                // A pasta sumiu (uma worktree apagada): o agente abre na home, e a conversa antiga,
                // que é da outra pasta, não é retomada de lá.
                let vanished = !PathTools.isDirectory(directory)
                if vanished { warnings.add("pasta de agente sumiu: abriu na home, conversa nova") }
                let reused = saved.sessionID.map { id in panes.contains { $0.sessionID == id } } ?? false
                let name = saved.name.flatMap(AgentNaming.sanitized)
                    ?? AgentNaming.automaticName(existing: panes.map(\.name))
                if let pane = makePane(name: name, directory: directory,
                                       sessionID: reused || vanished ? nil : saved.sessionID, tone: saved.tone) {
                    created.append(pane)
                }
            }
            if panes.indices.contains(config.mainAgent) { mainPane = panes[config.mainAgent] }
        }
        for _ in 0..<options.count {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name)),
                                      directory: defaultDirectory, sessionID: nil, tone: nil) else { break }
            created.append(pane)
            mainPane = pane
        }
        relayout()
        settleLayout()
        created.forEach { $0.spawn() }
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
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
        panes.forEach { $0.shutdown() }
    }

    func persist() {
        // Antes do `start` a lista em memória está vazia: gravar apagaria os agentes salvos.
        guard launch != nil else { return }
        config.layout = layoutMode
        config.fontScale = fontScale
        config.cwd = defaultDirectory
        config.agents = panes.map {
            SavedAgent(name: $0.name, cwd: $0.directory, sessionID: $0.sessionID, tone: $0.tone)
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
    private func makePane(name: String, directory: String, sessionID: String?, tone: Int?) -> AgentPaneView? {
        guard let launch, panes.count < ClarkConfig.maxAgents else { return nil }
        let company = launch.company(forDirectory: directory)
        let usedTones = panes.filter { $0.company.name == company.name }.map(\.tone)
        let pane = AgentPaneView(name: name, directory: directory, sessionID: sessionID ?? SessionLocator.newID(),
                                 tone: tone ?? AgentNaming.freeTone(used: usedTones), launch: launch,
                                 appearance: terminalAppearance, clock: clock)
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

    func addAgents(_ count: Int) {
        var created: [AgentPaneView] = []
        for _ in 0..<max(0, count) {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name)),
                                      directory: defaultDirectory, sessionID: nil, tone: nil) else { break }
            created.append(pane)
        }
        guard let last = created.last else { return }
        mainPane = last
        if zoomedPane != nil { zoomedPane = last }
        relayout()
        settleLayout()
        created.forEach { $0.spawn() }
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
    private func presentDiff(of pane: AgentPaneView) {
        let panel = diffPanel(for: pane)
        pane.diff.refresh()
        present(panel)
    }

    func refreshDiffs() {
        panes.forEach { $0.diff.refresh() }
    }

    func setDefaultDirectory(_ directory: String) {
        guard PathTools.isDirectory(directory) else { return }
        defaultDirectory = directory
        updateButtonTitles()
        persist()
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

    /// Menu do botão PROJETO, relido do disco a cada abertura: GLOBAL, as empresas e a escolha de outra pasta.
    func projectMenu() -> NSMenu {
        let menu = NSMenu(title: "Projeto")
        menu.addItem(projectItem("GLOBAL", path: home))
        menu.addItem(.separator())
        let groups = launch?.projectGroups() ?? []
        for group in groups {
            // Empresa de uma pasta só, sem nada dentro, abre direto.
            if group.projects.isEmpty, group.folders.count == 1 {
                menu.addItem(projectItem(group.name, path: group.folders[0]))
            } else {
                menu.addItem(projectSubmenu(group.name, folders: group.folders, entries: group.projects))
            }
        }
        if !groups.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: "Outra pasta…", action: #selector(chooseFolder(_:)), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        return menu
    }

    private func projectItem(_ title: String, path: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openProject(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = path
        item.toolTip = PathTools.short(path, home: home)
        return item
    }

    /// Submenu de uma empresa ou de uma pasta de repositórios: as próprias pastas em cima, o que há dentro embaixo.
    private func projectSubmenu(_ title: String, folders: [String], entries: [ProjectEntry]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for folder in folders { submenu.addItem(projectItem(PathTools.short(folder, home: home), path: folder)) }
        if !entries.isEmpty { submenu.addItem(.separator()) }
        for entry in entries {
            submenu.addItem(entry.children.isEmpty ? projectItem(entry.name, path: entry.path)
                : projectSubmenu(entry.name, folders: [entry.path], entries: entry.children))
        }
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }

    /// Abre um agente na pasta, que passa a ser a do ⌘N e do + AGENT.
    func openAgent(in directory: String) {
        guard launch != nil else { return }
        guard PathTools.isDirectory(directory) else {
            warnings.add("pasta nao encontrada: valendo a anterior")
            return
        }
        setDefaultDirectory(directory)
        addAgents(1)
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
        topBar.projectButton.title = TopBarView.projectTitle(shortPath: PathTools.short(defaultDirectory, home: home))
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
        refreshChrome()
    }

    // MARK: AgentPaneDelegate

    func paneIsWatched(_ pane: AgentPaneView) -> Bool {
        pane === focusedPane && !pane.isHidden && isWindowKey() && isAppActive()
    }

    func paneNeedsAttention(_ pane: AgentPaneView) {
        if !isAppActive() { notifier.agentDone(name: pane.name, sessionID: pane.sessionID) }
    }

    func paneDidChange(_ pane: AgentPaneView) {
        cards[ObjectIdentifier(pane)]?.snapshot = pane.snapshot
        diffPanel?.paneDidChange(pane)
        refreshChrome()
    }

    func paneRequestsDiff(_ pane: AgentPaneView) { presentDiff(of: pane) }
    func paneRequestsSelect(_ pane: AgentPaneView) { select(pane) }
    func paneRequestsZoom(_ pane: AgentPaneView) { toggleZoom(of: pane) }
    func paneRequestsClose(_ pane: AgentPaneView) { close(pane) }

    func paneRequestsRename(_ pane: AgentPaneView) {
        let field = NSTextField(string: pane.name)
        field.frame = NSRect(x: 10, y: 10, width: 240, height: 24)
        field.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        field.target = self
        field.action = #selector(commitRename(_:))
        // Clicar fora fecha sem renomear: só o Enter confirma.
        field.cell?.sendsActionOnEndEditing = false
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        content.view.addSubview(field)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        renamePopover = popover
        renameTarget = pane
        popover.show(relativeTo: pane.header.bounds, of: pane.header, preferredEdge: .maxY)
        field.selectText(nil)
    }

    @objc private func commitRename(_ sender: NSTextField) {
        renamePopover?.close()
        renamePopover = nil
        guard let pane = renameTarget else { return }
        applyRename(pane, text: sender.stringValue)
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

    @objc func newAgent(_ sender: Any?) { addAgents(1) }

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

    @objc func chooseProject(_ sender: Any?) {
        guard launch != nil else { return }
        let button = topBar.projectButton
        projectMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc func openProject(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openAgent(in: path) }
    }

    /// "Outra pasta…" do menu PROJETO: qualquer pasta do disco.
    @objc func chooseFolder(_ sender: Any?) {
        guard let window, launch != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: defaultDirectory)
        panel.prompt = "Escolher"
        panel.message = "Pasta onde o agente abre"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let path = panel.url?.path { self?.openAgent(in: path) }
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
        case #selector(chooseProject(_:)), #selector(openProject(_:)), #selector(chooseFolder(_:)):
            return launch != nil
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
