import AppKit
import ClarkCore

/// Janela do diff de um agente: à esquerda os arquivos mudados, à direita o diff do escolhido.
/// É uma só no app. Pedir o diff de outro agente troca o conteúdo dela.
final class DiffWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
    NSSplitViewDelegate {
    static let reading = "Lendo o repositório…"
    static let noGit = "git não encontrado no PATH."
    static let notRepository = "Esta pasta não é um repositório git."
    static let failed = "O git falhou ou não respondeu a tempo."
    static let clean = "Nada mudou desde o último commit."
    static let noText = "(sem diferença de texto)"
    static let cutNote = "… diff cortado: grande demais para mostrar inteiro"
    /// Limites do que vai para a tela. O tamanho em bytes já vem limitado pelo `GitRunner`.
    static let lineLimit = 20_000
    static let lineLength = 2_000
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private static let statusColumn = NSUserInterfaceItemIdentifier("status")
    private static let pathColumn = NSUserInterfaceItemIdentifier("path")
    private static let countsColumn = NSUserInterfaceItemIdentifier("counts")

    /// Agente mostrado. nil com a janela fechada.
    private(set) weak var pane: AgentPaneView?
    private(set) var files: [DiffFile] = []
    /// Arquivo escolhido. Guardado pelo caminho: a linha dele na tabela muda a cada leitura.
    private(set) var selectedPath: String?
    let table = NSTableView()
    let subtitle = NSTextField(labelWithString: "")
    /// O que está na área do diff: o diff do arquivo ou o aviso do estado.
    var text: String { textView.string }

    private let theme: Theme
    private let home: String
    private let tableScroll = NSScrollView()
    private let textView = NSTextView(usingTextLayoutManager: false)
    private let textScroll = NSScrollView()
    /// Leitura do repositório que está na tela.
    private var shownRevision: Int?
    /// Arquivo cujo diff está na tela.
    private var shownPath: String?
    /// Número do último diff pedido: a resposta de um pedido anterior é descartada.
    private var request = 0
    private var isReloading = false

    init(theme: Theme, home: String) {
        self.theme = theme
        self.home = home
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        panel.title = "Diff"
        // Painel comum, não flutuante: fica atrás do CLARK quando o CLARK ganha o clique, e não vira a
        // janela principal, então os atalhos do menu continuam chegando no `MainWindowController`.
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 520, height: 300)
        panel.backgroundColor = theme.bg2.nsColor
        let luminance = 0.299 * theme.bg.r + 0.587 * theme.bg.g + 0.114 * theme.bg.b
        panel.appearance = NSAppearance(named: luminance > 0.5 ? .aqua : .darkAqua)
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        buildViews(in: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private func buildViews(in window: NSWindow) {
        let size = window.contentLayoutRect.size
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        // A faixa do subtítulo não depende do fundo da janela para ficar na cor do tema.
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bg2.cgColor
        let barHeight: CGFloat = 26

        subtitle.frame = NSRect(x: 10, y: size.height - barHeight + 5, width: size.width - 20, height: 16)
        subtitle.autoresizingMask = [.width, .minYMargin]
        subtitle.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = theme.dim.nsColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        content.addSubview(subtitle)

        for (identifier, width) in [(Self.statusColumn, 16), (Self.pathColumn, 190), (Self.countsColumn, 86)] {
            let column = NSTableColumn(identifier: identifier)
            column.width = CGFloat(width)
            // Só o caminho estica com a lista.
            if identifier == Self.pathColumn {
                column.resizingMask = .autoresizingMask
            } else {
                column.resizingMask = []
                column.minWidth = CGFloat(width)
                column.maxWidth = CGFloat(width)
            }
            table.addTableColumn(column)
        }
        table.headerView = nil
        table.rowHeight = 18
        table.intercellSpacing = NSSize(width: 6, height: 2)
        table.style = .fullWidth
        table.backgroundColor = theme.bg2.nsColor
        table.allowsMultipleSelection = false
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        tableScroll.frame = NSRect(x: 0, y: 0, width: 320, height: size.height - barHeight)
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.drawsBackground = false

        // Linha comprida não quebra: o diff rola para o lado.
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.backgroundColor = theme.bg.nsColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textScroll.frame = NSRect(x: 321, y: 0, width: size.width - 321, height: size.height - barHeight)
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.backgroundColor = theme.bg.nsColor

        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - barHeight))
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        split.delegate = self
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(textScroll)
        content.addSubview(split)
        window.contentView = content
        // Sem isto a divisória é posta antes de a divisão arrumar os dois lados, e o diff fica estreito.
        split.adjustSubviews()
        split.setPosition(320, ofDividerAt: 0)
        window.initialFirstResponder = table
    }

    /// A lista guarda a largura; quem estica e encolhe com a janela é o diff.
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== tableScroll
    }

    // MARK: agente

    /// Passa a mostrar o diff do agente. Não põe a janela na tela.
    func attach(to pane: AgentPaneView) {
        if pane !== self.pane {
            reset()
            self.pane = pane
        }
        sync()
    }

    /// Nome, estado ou diff do agente mudaram.
    func paneDidChange(_ changed: AgentPaneView) {
        if changed === pane { sync() }
    }

    func paneClosed(_ closed: AgentPaneView) {
        guard closed === pane else { return }
        reset()
        close()
    }

    /// O ⌘W, com esta janela na frente, fecha a janela e não o agente.
    @objc func closeAgent(_ sender: Any?) {
        close()
    }

    /// Fechada, a janela larga o agente: ninguém lê diff para uma janela que não está na tela.
    func windowWillClose(_ notification: Notification) {
        reset()
    }

    private func reset() {
        pane = nil
        request += 1
        shownRevision = nil
        shownPath = nil
        selectedPath = nil
        setFiles([])
        textView.textStorage?.setAttributedString(NSAttributedString())
        subtitle.stringValue = ""
    }

    /// Títulos sempre; lista e diff só quando houve leitura nova do repositório.
    private func sync() {
        guard let pane else { return }
        window?.title = "Diff — \(pane.name)"
        let monitor = pane.diff
        var parts = [pane.snapshot.path]
        if case .changes(let changes) = monitor.state {
            // O diff é do repositório inteiro, mesmo com o agente numa subpasta.
            parts = [PathTools.short(changes.root, home: home)]
            if changes.truncated { parts.append("lista incompleta") }
        }
        if let summary = monitor.summary { parts.append(summary.label) }
        subtitle.stringValue = parts.joined(separator: "  ·  ")

        guard monitor.revision != shownRevision else { return }
        shownRevision = monitor.revision
        switch monitor.state {
        case .unknown: show(message: Self.reading)
        case .noGit: show(message: Self.noGit)
        case .notRepository: show(message: Self.notRepository)
        case .failed: show(message: Self.failed)
        case .changes(let changes):
            guard !changes.files.isEmpty else { return show(message: Self.clean) }
            setFiles(changes.files)
            loadSelected()
        }
    }

    // MARK: lista

    /// Troca a lista e mantém o arquivo escolhido. Se ele saiu da lista, vale o primeiro.
    private func setFiles(_ newFiles: [DiffFile]) {
        files = newFiles
        let row = selectedPath.flatMap { path in files.firstIndex { $0.path == path } } ?? (files.isEmpty ? nil : 0)
        selectedPath = row.map { files[$0].path }
        isReloading = true
        table.reloadData()
        if let row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        isReloading = false
    }

    /// Escolhe o arquivo pelo caminho, como se tivesse sido clicado na lista. Com a lista ainda por
    /// chegar, a escolha vale para a leitura que vem. Caminho que a lista não tem não muda nada.
    func select(path: String) {
        guard let row = files.firstIndex(where: { $0.path == path }) else {
            if files.isEmpty { selectedPath = path }
            return
        }
        selectedPath = path
        isReloading = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isReloading = false
        table.scrollRowToVisible(row)
        loadSelected()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        files.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, files.indices.contains(row) else { return nil }
        let file = files[row]
        let label = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField ?? makeLabel(identifier)
        switch identifier {
        case Self.statusColumn:
            label.stringValue = file.status.rawValue
            label.textColor = Self.color(of: file.status, theme: theme).nsColor
        case Self.pathColumn:
            label.stringValue = file.path
            label.textColor = theme.ink.nsColor
            label.toolTip = file.path
        default:
            label.attributedStringValue = counts(of: file)
        }
        return label
    }

    private func makeLabel(_ identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.identifier = identifier
        label.font = Self.font
        // O fim do caminho, que é o nome do arquivo, é o que fica quando não cabe.
        label.lineBreakMode = identifier == Self.pathColumn ? .byTruncatingHead : .byClipping
        return label
    }

    static func color(of status: DiffStatus, theme: Theme) -> RGB {
        switch status {
        case .added, .untracked: return theme.green
        case .deleted: return theme.red
        case .modified: return theme.yellow
        }
    }

    /// `+12 -3` à direita. Sem contagem (binário, link, não rastreado além do limite) fica o traço.
    private func counts(of file: DiffFile) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.lineBreakMode = .byClipping
        func part(_ text: String, _ color: RGB) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: color.nsColor,
                                                          .paragraphStyle: style])
        }
        guard let added = file.added, let removed = file.removed else { return part("—", theme.dim) }
        let result = NSMutableAttributedString()
        result.append(part("+" + DiffSummary.short(added), theme.green))
        result.append(part(" -" + DiffSummary.short(removed), theme.red))
        return result
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading, files.indices.contains(table.selectedRow) else { return }
        selectedPath = files[table.selectedRow].path
        loadSelected()
    }

    // MARK: diff

    private func loadSelected() {
        guard let pane, let file = files.first(where: { $0.path == selectedPath }) else { return }
        request += 1
        let request = request
        pane.diff.loadDiff(of: file) { [weak self] diff in
            guard let self, self.request == request else { return }
            self.show(diff.map { Self.attributed($0, theme: self.theme) } ?? Self.message(Self.failed, theme: self.theme),
                      path: file.path)
        }
    }

    private func show(message: String) {
        request += 1
        selectedPath = nil
        setFiles([])
        show(Self.message(message, theme: theme), path: nil)
    }

    /// Põe o texto na tela. O mesmo arquivo relido fica onde o leitor estava; outro arquivo começa do topo.
    private func show(_ content: NSAttributedString, path: String?) {
        let sameFile = path != nil && path == shownPath
        shownPath = path
        if sameFile && content.string == textView.string { return }
        let origin = textScroll.contentView.bounds.origin
        textView.textStorage?.setAttributedString(content)
        if sameFile, let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
            textView.scroll(origin)
        } else {
            textView.scroll(.zero)
        }
    }

    static func message(_ text: String, theme: Theme) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.dim.nsColor])
    }

    /// O diff com uma cor por tipo de linha, cortado nos limites da tela.
    static func attributed(_ diff: FileDiff, theme: Theme, lineLimit: Int = lineLimit,
                           lineLength: Int = lineLength) -> NSAttributedString {
        let lines = GitDiff.lines(of: diff.text)
        guard !lines.isEmpty else { return message(noText, theme: theme) }
        let colors: [DiffLine.Kind: NSColor] = [
            .header: theme.dim.nsColor, .hunk: theme.accent.nsColor, .added: theme.green.nsColor,
            .removed: theme.red.nsColor, .context: theme.ink.nsColor, .note: theme.dim.nsColor,
        ]
        let result = NSMutableAttributedString()
        func append(_ text: String, _ color: NSColor) {
            result.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color]))
        }
        for line in lines.prefix(lineLimit) {
            let text = line.text.count > lineLength ? String(line.text.prefix(lineLength)) + "…" : line.text
            append(text, colors[line.kind] ?? theme.ink.nsColor)
        }
        if diff.truncated || lines.count > lineLimit { append(cutNote, theme.yellow.nsColor) }
        return result
    }
}
