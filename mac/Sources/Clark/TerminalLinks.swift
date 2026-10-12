import AppKit
import ClarkCore
import SwiftTerm

/// Um trecho de link numa linha da tela do terminal.
struct LinkSpan: Equatable {
    /// Linha da tela: 0 é a de cima.
    var row: Int
    var columns: Range<Int>
}

/// Onde estão, na tela do terminal, os links que o ⌘-clique abre. Quem diz o que é link é o
/// detector do próprio SwiftTerm, o mesmo que o clique consulta: o sublinhado nunca promete um
/// link que o clique não abre.
enum TerminalLinks {
    /// Linhas lidas acima da tela: o link que começa lá e continua na tela é sublinhado no que
    /// aparece. O que começa mais acima fica sem sublinhado.
    static let lookback = 8
    /// Linha que o terminal quebrou em mais pedaços que isto não é procurada. A cada consulta o
    /// detector lê a linha inteira, e uma linha sem fim (um JSON de uma linha só) pesaria na tela.
    static let maxWrappedRows = 32
    /// Consultas ao detector por leitura da tela.
    static let maxProbes = 128

    /// O endereço que o clique abre: só `http` e `https`. Um link `file:` ou de outro esquema vindo
    /// da saída do agente não abre nada.
    static func webURL(_ link: String) -> URL? {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Os links da tela, de cima para baixo e da esquerda para a direita.
    static func spans(in terminal: Terminal) -> [LinkSpan] {
        var reader = LinkReader(terminal)
        return reader.spans()
    }
}

/// Uma leitura da tela. As linhas são as do buffer do terminal, que inclui o histórico.
private struct LinkReader {
    private struct Cell {
        /// Índice em `lines`.
        var row: Int
        var col: Int
    }

    private let terminal: Terminal
    private let cols: Int
    /// Linha do buffer em que a tela começa.
    private let top: Int
    /// Linha do buffer de `lines[0]`.
    private let first: Int
    /// As linhas lidas e onde acaba o texto de cada uma: o detector não lê além dali.
    private var lines: [(line: BufferLine, end: Int)] = []
    /// Células que já são de um link.
    private var taken: [[Bool]]
    private var found: [LinkSpan] = []

    init(_ terminal: Terminal) {
        self.terminal = terminal
        cols = terminal.cols
        top = terminal.getTopVisibleRow()
        first = max(0, top - TerminalLinks.lookback)
        for row in first..<(top + terminal.rows) {
            guard let line = Self.line(row, in: terminal) else { break }
            lines.append((line, min(cols, line.count, line.getTrimmedLength())))
        }
        taken = Array(repeating: Array(repeating: false, count: cols), count: lines.count)
    }

    mutating func spans() -> [LinkSpan] {
        readExplicit()
        readImplicit()
        return found.sorted { ($0.row, $0.columns.lowerBound) < ($1.row, $1.columns.lowerBound) }
    }

    private static func line(_ row: Int, in terminal: Terminal) -> BufferLine? {
        terminal.getScrollInvariantLine(row: row + terminal.buffer.totalLinesTrimmed)
    }

    private mutating func add(_ row: Int, _ columns: Range<Int>) {
        let screenRow = first + row - top
        if screenRow >= 0 { found.append(LinkSpan(row: screenRow, columns: columns)) }
    }

    // MARK: células

    /// Célula vazia conta como espaço, como no detector.
    private func character(_ cell: Cell) -> Character {
        let character = terminal.getCharacter(for: lines[cell.row].line[cell.col])
        return character == "\u{0}" ? " " : character
    }

    /// Metade direita de um caractere largo: não tem texto próprio.
    private func isSpacer(_ row: Int, _ col: Int) -> Bool {
        let line = lines[row].line
        return col > 0 && line[col - 1].width == 2 && terminal.getCharacter(for: line[col]) == "\u{0}"
    }

    /// A célula de texto seguinte, na ordem em que o detector lê: pula a metade direita do caractere
    /// largo e, no fim da linha, segue na primeira célula não branca da linha de baixo.
    private func next(_ cell: Cell) -> Cell? {
        var col = cell.col + 1
        while col < lines[cell.row].end, isSpacer(cell.row, col) { col += 1 }
        if col < lines[cell.row].end { return Cell(row: cell.row, col: col) }
        let below = cell.row + 1
        guard below < lines.count else { return nil }
        var start = Cell(row: below, col: 0)
        while start.col < lines[below].end, character(start).isWhitespace { start.col += 1 }
        return start.col < lines[below].end ? start : nil
    }

    // MARK: links explícitos

    /// O que o link explícito (OSC 8) guarda na célula: `parâmetros;endereço`.
    private func payload(_ row: Int, _ col: Int) -> String? {
        let line = lines[row].line
        if line[col].hasPayload { return line[col].getPayload() as? String }
        if isSpacer(row, col), line[col - 1].hasPayload { return line[col - 1].getPayload() as? String }
        return nil
    }

    private mutating func readExplicit() {
        for row in lines.indices {
            let limit = min(cols, lines[row].line.count)
            var col = 0
            while col < limit {
                guard let payload = payload(row, col) else {
                    col += 1
                    continue
                }
                var end = col + 1
                while end < limit, self.payload(row, end) == payload { end += 1 }
                // O clique aqui abre o endereço escondido, seja qual for o texto que aparece: estas
                // células não são de mais nenhum link.
                for used in col..<end { taken[row][used] = true }
                let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count > 1, TerminalLinks.webURL(String(parts[1])) != nil { add(row, col..<end) }
                col = end
            }
        }
    }

    // MARK: links no texto

    private mutating func readImplicit() {
        var probes = 0
        for row in lines.indices {
            for col in 0..<lines[row].end where !taken[row][col] {
                let start = Cell(row: row, col: col)
                guard startsWebScheme(start), !wrapsTooMuch(first + row) else { continue }
                guard probes < TerminalLinks.maxProbes else { return }
                probes += 1
                guard let link = terminal.link(at: .buffer(Position(col: col, row: first + row)),
                                               mode: .explicitAndImplicit),
                      TerminalLinks.webURL(link) != nil else { continue }
                follow(link, from: start)
            }
        }
    }

    /// A célula começa `http://` ou `https://`? Todo link da web começa assim, e a conta é barata:
    /// o detector só é consultado onde isto vale.
    private func startsWebScheme(_ start: Cell) -> Bool {
        var cell: Cell? = start
        func take(_ expected: Character) -> Bool {
            guard let current = cell, character(current) == expected else { return false }
            cell = next(current)
            return true
        }
        guard "http".allSatisfy(take) else { return false }
        _ = take("s")
        return "://".allSatisfy(take)
    }

    /// A linha é pedaço de uma que o terminal quebrou em mais de `maxWrappedRows`?
    private func wrapsTooMuch(_ row: Int) -> Bool {
        let limit = TerminalLinks.maxWrappedRows
        var count = 1
        var up = row
        while count <= limit, up > 0, Self.line(up, in: terminal)?.isWrapped == true {
            up -= 1
            count += 1
        }
        var down = row + 1
        while count <= limit, Self.line(down, in: terminal)?.isWrapped == true {
            down += 1
            count += 1
        }
        return count > limit
    }

    /// Segue o link célula a célula a partir de `start`, enquanto o texto da tela for o dele.
    private mutating func follow(_ link: String, from start: Cell) {
        var cells: [Cell] = []
        var cell: Cell? = start
        for expected in link {
            // Acabou o que foi lido: o resto do link está abaixo da tela.
            guard let current = cell else { break }
            // O link não começa aqui: é pedaço de outro, que começou acima do que foi lido.
            guard character(current) == expected else { return }
            cells.append(current)
            cell = next(current)
        }
        var runs: [LinkSpan] = []
        for cell in cells {
            let end = min(cols, cell.col + max(1, Int(lines[cell.row].line[cell.col].width)))
            // A célula de um link explícito fica de fora: o clique nela abre o endereço dele.
            for col in cell.col..<end where !taken[cell.row][col] {
                taken[cell.row][col] = true
                if let last = runs.last, last.row == cell.row, last.columns.upperBound == col {
                    runs[runs.count - 1].columns = last.columns.lowerBound..<(col + 1)
                } else {
                    runs.append(LinkSpan(row: cell.row, columns: col..<(col + 1)))
                }
            }
        }
        for run in runs { add(run.row, run.columns) }
    }
}

/// Os sublinhados dos links, por cima do terminal. O SwiftTerm não deixa trocar o desenho dele, e
/// marcar o sublinhado no buffer mudaria o texto que o agente escreveu.
final class LinkUnderlineView: NSView {
    struct Metrics: Equatable {
        /// Tamanho de uma célula do terminal.
        var cell: CGSize = .zero
        /// Do pé da linha ao meio do traço.
        var offset: CGFloat = 0
        var thickness: CGFloat = 1
    }

    var spans: [LinkSpan] = [] { didSet { if spans != oldValue { needsDisplay = true } } }
    var metrics = Metrics() { didSet { if metrics != oldValue { needsDisplay = true } } }
    var color = Theme.dark.term[4] { didSet { if color != oldValue { needsDisplay = true } } }

    // O clique, o arrasto e o menu são do terminal.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(color.cgColor)
        for span in spans {
            // O terminal desenha de cima para baixo numa vista com a origem embaixo.
            let foot = bounds.height - CGFloat(span.row + 1) * metrics.cell.height
            let line = CGRect(x: CGFloat(span.columns.lowerBound) * metrics.cell.width,
                              y: foot + metrics.offset - metrics.thickness / 2,
                              width: CGFloat(span.columns.count) * metrics.cell.width, height: metrics.thickness)
            context.fill(backingAlignedRect(line, options: .alignAllEdgesNearest))
        }
    }
}
