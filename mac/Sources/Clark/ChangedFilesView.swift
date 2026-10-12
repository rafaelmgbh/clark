import AppKit
import ClarkCore

/// Coluna dos arquivos alterados do agente, ao lado do terminal: os arquivos do diff agrupados pelo que
/// aconteceu com cada um. Clicar num arquivo pede o diff dele.
final class ChangedFilesView: PixelView {
    static let width = 264
    static let headHeight = 24
    /// Risco que separa a coluna do terminal.
    static let edge = 2
    // O que aparece no lugar da lista. Só ASCII em maiúsculas, que é o que a fonte de pixels tem.
    static let reading = "LENDO..."
    static let noGit = "GIT NAO ENCONTRADO"
    static let notRepository = "FORA DE REPOSITORIO GIT"
    static let failed = "O GIT NAO RESPONDEU"
    static let clean = "NADA MUDOU"
    /// Ao lado do título, quando a lista passou do limite de tamanho.
    static let cutNote = "INCOMPLETA"

    /// Última leitura do repositório do agente.
    var state = DiffState.unknown {
        didSet {
            guard state != oldValue else { return }
            list.rows = ChangedFiles.rows(changes?.files ?? [])
            scroll.isHidden = message != nil
            needsLayout = true
            needsDisplay = true
        }
    }
    var onSelect: ((DiffFile) -> Void)? {
        get { list.onSelect }
        set { list.onSelect = newValue }
    }
    var onRefresh: (() -> Void)?
    var onClose: (() -> Void)?

    let refreshButton = PixelButton(title: "R", style: .mini, toolTip: "Reler os arquivos (⌘R)")
    let closeButton = PixelButton(title: "X", style: .miniClose, toolTip: "Fechar a lista")
    let list = ChangedFilesListView()
    private let scroll = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        scroll.isHidden = true
        refreshButton.onClick = { [weak self] in self?.onRefresh?() }
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(scroll)
        addSubview(refreshButton)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet {
            refreshButton.theme = theme
            closeButton.theme = theme
            list.theme = theme
        }
    }

    private var changes: RepoChanges? {
        if case .changes(let changes) = state { return changes }
        return nil
    }

    var title: String {
        changes.map { "ALTERADOS \(DiffSummary.short($0.files.count))" } ?? "ALTERADOS"
    }

    /// Aviso que fica no lugar da lista. nil quando há arquivo para listar.
    var message: String? {
        switch state {
        case .unknown: return Self.reading
        case .noGit: return Self.noGit
        case .notRepository: return Self.notRepository
        case .failed: return Self.failed
        case .changes(let changes): return changes.files.isEmpty ? Self.clean : nil
        }
    }

    override func layout() {
        super.layout()
        let width = Int(bounds.width), height = Int(bounds.height)
        let closeWidth = closeButton.fittingWidth, refreshWidth = refreshButton.fittingWidth
        closeButton.frame = NSRect(x: width - closeWidth, y: 0, width: closeWidth, height: Self.headHeight)
        refreshButton.frame = NSRect(x: width - closeWidth - refreshWidth, y: 0, width: refreshWidth,
                                     height: Self.headHeight)
        let bodyWidth = max(0, width - Self.edge), bodyHeight = max(0, height - Self.headHeight)
        scroll.frame = NSRect(x: Self.edge, y: Self.headHeight, width: bodyWidth, height: bodyHeight)
        list.frame = NSRect(x: 0, y: 0, width: bodyWidth, height: max(list.contentHeight, bodyHeight))
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        Pixel.fill(context, 0, 0, Self.edge, height, theme.shadow)
        Pixel.fill(context, Self.edge, 0, width - Self.edge, Self.headHeight, theme.bg2)
        let textY = (Self.headHeight - 7) / 2
        Pixel.text(context, title, 12, textY, scale: 1, theme.dim)
        if changes?.truncated == true {
            Pixel.text(context, Self.cutNote, 12 + PixelFont.textWidth(title, scale: 1) + 10, textY, scale: 1,
                       theme.yellow)
        }
        if let message {
            Pixel.text(context, PixelFont.fit(message, scale: 1, width: width - 24), 12, Self.headHeight + 12,
                       scale: 1, theme.dim)
        }
    }
}

/// As linhas da coluna: o título de cada grupo e os arquivos dele.
final class ChangedFilesListView: PixelView {
    static let groupHeight = 22
    /// Arquivo com a pasta embaixo do nome.
    static let fileHeight = 34
    /// Arquivo da raiz do repositório: só o nome.
    static let rootFileHeight = 20

    var rows: [ChangedFiles.Row] = [] {
        didSet {
            guard rows != oldValue else { return }
            var top = 0
            offsets = [0] + rows.map { row in
                top += Self.height(of: row)
                return top
            }
            // A linha que estava sob o mouse pode ser outra agora.
            hovered = nil
            needsDisplay = true
        }
    }
    var onSelect: ((DiffFile) -> Void)?
    /// Linha de arquivo sob o mouse.
    private(set) var hovered: Int?
    /// Onde cada linha começa e, no fim, a altura de todas.
    private var offsets = [0]
    /// Faixa que o AppKit pediu para redesenhar. Fora do `draw`, a lista inteira.
    private var dirtyRange: ClosedRange<Int>?

    // Clicar na lista não tira o foco do terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func height(of row: ChangedFiles.Row) -> Int {
        switch row {
        case .group: return groupHeight
        case .file(let file): return ChangedFiles.split(file.path).folder.isEmpty ? rootFileHeight : fileHeight
        }
    }

    static func groupTitle(_ status: DiffStatus, count: Int) -> String {
        "\(ChangedFiles.title(status)) \(DiffSummary.short(count))"
    }

    var contentHeight: Int { offsets[rows.count] }

    func top(ofRow index: Int) -> Int { offsets[index] }

    /// Linha que passa pela altura `y`. nil fora da lista.
    func row(atY y: Int) -> Int? {
        guard y >= 0, y < contentHeight else { return nil }
        // Primeira linha que termina depois de `y`.
        var low = 0, high = rows.count - 1
        while low < high {
            let middle = (low + high) / 2
            if offsets[middle + 1] > y {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    // MARK: mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow,
                                                             .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(row(under: event)) }
    override func mouseMoved(with event: NSEvent) { setHovered(row(under: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func row(under event: NSEvent) -> Int? {
        row(atY: Int(convert(event.locationInWindow, from: nil).y))
    }

    /// Acende a linha. Só arquivo acende: título de grupo não abre nada.
    func setHovered(_ index: Int?) {
        var target: Int?
        if let index, rows.indices.contains(index), case .file = rows[index] { target = index }
        guard target != hovered else { return }
        hovered = target
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = row(under: event), case .file(let file) = rows[index] else { return }
        onSelect?(file)
    }

    // MARK: desenho

    /// Com milhares de arquivos a lista tem a altura de todos, mas só o trecho pedido é desenhado.
    override func draw(_ dirtyRect: NSRect) {
        dirtyRange = Int(dirtyRect.minY.rounded(.down))...Int(dirtyRect.maxY.rounded(.up))
        super.draw(dirtyRect)
        dirtyRange = nil
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        for (index, row) in rows.enumerated() {
            let y = offsets[index], bottom = offsets[index + 1]
            if let dirtyRange, bottom < dirtyRange.lowerBound || y > dirtyRange.upperBound { continue }
            switch row {
            case .group(let status, let count):
                Pixel.text(context, Self.groupTitle(status, count: count), 10, y + 9, scale: 1, theme.dim)
            case .file(let file):
                if hovered == index { Pixel.fill(context, 0, y, width, bottom - y, theme.bg3) }
                render(file, y: y, width: width, in: context)
            }
        }
    }

    private func render(_ file: DiffFile, y: Int, width: Int, in context: CGContext) {
        Pixel.text(context, file.status.rawValue, 10, y + 6, scale: 1,
                   DiffWindowController.color(of: file.status, theme: theme))
        let right = width - 8
        var countsWidth = PixelFont.textWidth("-", scale: 1)
        if let added = file.added, let removed = file.removed {
            let plus = "+" + DiffSummary.short(added), minus = "-" + DiffSummary.short(removed)
            countsWidth = PixelFont.textWidth(plus + " " + minus, scale: 1)
            Pixel.text(context, plus, right - countsWidth, y + 6, scale: 1, theme.green)
            Pixel.text(context, minus, right - PixelFont.textWidth(minus, scale: 1), y + 6, scale: 1, theme.red)
        } else {
            // Sem contagem: binário, link ou arquivo novo grande demais para contar.
            Pixel.text(context, "-", right - countsWidth, y + 6, scale: 1, theme.dim)
        }
        let (name, folder) = ChangedFiles.split(file.path)
        Pixel.mono(context, name, 24, y + 3, width: right - countsWidth - 8 - 24, size: 11, theme.ink,
                   truncate: .byTruncatingMiddle)
        if !folder.isEmpty {
            // O fim do caminho, que é a pasta onde o arquivo está, é o que fica quando não cabe.
            Pixel.mono(context, folder, 24, y + 18, width: right - 24, size: 9, theme.dim, truncate: .byTruncatingHead)
        }
    }
}
