import AppKit
import ClarkCore
import SwiftTerm

/// Números das linhas da tela, por cima do terminal, enquanto o ⇧⌘C escolhe o que copiar. Fica com
/// o teclado até copiar ou sair: o `keyDown` do SwiftTerm não pode ser trocado fora dele.
final class LineNumbersView: NSView {
    var picker: LinePicker? { didSet { if picker != oldValue { needsDisplay = true } } }
    /// Linha do buffer, contada do começo do histórico, que está no topo da tela.
    var top = 0 { didSet { if top != oldValue { needsDisplay = true } } }
    var rows = 0 { didSet { if rows != oldValue { needsDisplay = true } } }
    var cell = CGSize.zero { didSet { if cell != oldValue { needsDisplay = true } } }
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) { didSet { needsDisplay = true } }
    var theme = Theme.dark { didSet { needsDisplay = true } }
    /// Para onde vai o texto copiado. Trocado nos testes.
    var pasteboard = NSPasteboard.general
    /// O modo acabou, copiando ou não: o terminal pega o teclado de volta.
    var onFinish: (() -> Void)?

    var isPicking: Bool { picker != nil }

    // O clique é do terminal: ele pega o teclado, e o modo acaba.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { isPicking }

    override func resignFirstResponder() -> Bool {
        if isPicking { finish(copying: false) }
        return true
    }

    func finish(copying: Bool) {
        guard let picker else { return }
        if copying {
            pasteboard.clearContents()
            pasteboard.setString(picker.text, forType: .string)
        }
        self.picker = nil
        isHidden = true
        onFinish?()
    }

    @objc func copy(_ sender: Any?) {
        finish(copying: true)
    }

    override func keyDown(with event: NSEvent) {
        guard picker != nil else { return super.keyDown(with: event) }
        let extending = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: finish(copying: false)
        case 36, 76: finish(copying: true)
        case 126: picker?.move(by: -1, extending: extending)
        case 125: picker?.move(by: 1, extending: extending)
        default:
            if !event.modifierFlags.contains(.command), let typed = event.charactersIgnoringModifiers,
               typed.count == 1, let digit = typed.first?.wholeNumberValue {
                picker?.type(digit)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let picker, cell.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let digits = String(picker.lines.count).count
        let badgeWidth = CGFloat(digits + 1) * cell.width
        let visible = top..<(top + rows)
        // O terminal desenha de cima para baixo numa vista com a origem embaixo.
        func rect(_ row: Int, width: CGFloat) -> CGRect {
            CGRect(x: 0, y: bounds.height - CGFloat(row - top + 1) * cell.height, width: width, height: cell.height)
        }
        for (index, line) in picker.lines.enumerated() {
            let first = max(line.rows.lowerBound, top)
            guard visible.contains(first) else { continue }
            let chosen = picker.selected.contains(index)
            if chosen {
                context.setFillColor(theme.accent.nsColor.withAlphaComponent(0.25).cgColor)
                for row in first...min(line.rows.upperBound, visible.upperBound - 1) {
                    context.fill(rect(row, width: bounds.width))
                }
            }
            let badge = rect(first, width: badgeWidth)
            context.setFillColor((chosen ? theme.accent : theme.bg2).cgColor)
            context.fill(badge)
            let label = String(index + 1)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: (chosen ? theme.onAccent : theme.dim).nsColor,
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: CGPoint(x: badge.maxX - size.width - cell.width / 2,
                                                 y: badge.midY - size.height / 2),
                                     withAttributes: attributes)
        }
    }
}

extension AgentTerminalView {
    /// Linhas da tela, com as de cima da tela que a primeira continua: a frase que começou acima é
    /// copiada inteira.
    func screenRows() -> [LinePicker.Row] {
        let terminal = getTerminal()
        let top = terminal.getTopVisibleRow() + terminal.buffer.totalLinesTrimmed
        var start = top
        while top - start < TerminalLinks.maxWrappedRows,
              terminal.getScrollInvariantLine(row: start)?.isWrapped == true {
            start -= 1
        }
        let last = top + terminal.rows
        var rows: [LinePicker.Row] = []
        for index in start..<last {
            guard let line = terminal.getScrollInvariantLine(row: index) else { continue }
            let continues = terminal.getScrollInvariantLine(row: index + 1)?.isWrapped == true && index + 1 < last
            // A linha que segue na de baixo vai até a borda: o espaço do fim é do texto.
            let text = line.translateToString(trimRight: !continues, skipNullCellsFollowingWide: true) {
                let character = terminal.getCharacter(for: $0)
                return character == "\u{0}" ? " " : character
            }
            rows.append(LinePicker.Row(index: index, text: text, isWrapped: line.isWrapped && index > start))
        }
        return rows
    }

    /// ⇧⌘C: numera as linhas da tela e passa o teclado para a escolha. false sem nada a escolher.
    @discardableResult
    func beginLineSelection() -> Bool {
        guard let picker = LinePicker(lines: LinePicker.lines(screenRows())) else { return false }
        lineNumbers.picker = picker
        refreshLineNumbers()
        lineNumbers.isHidden = false
        window?.makeFirstResponder(lineNumbers)
        return true
    }

    /// Acompanha a tela: os números andam junto com o texto quando ela rola.
    func refreshLineNumbers() {
        guard lineNumbers.isPicking else { return }
        let terminal = getTerminal()
        lineNumbers.top = terminal.getTopVisibleRow() + terminal.buffer.totalLinesTrimmed
        lineNumbers.rows = terminal.rows
        lineNumbers.cell = lineCell
        lineNumbers.font = font
    }
}
