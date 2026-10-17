import Foundation

/// Escolha de linhas do terminal pelo teclado (⇧⌘C): as linhas da tela ganham número, o número
/// digitado ou as setas escolhem, o Shift estende para várias.
public struct LinePicker: Equatable, Sendable {
    /// Linha da tela como o terminal guarda.
    public struct Row: Equatable, Sendable {
        /// Linha no buffer, contada do começo do histórico: não muda quando a tela rola.
        public var index: Int
        public var text: String
        /// Continuação da linha de cima, que o terminal quebrou por largura.
        public var isWrapped: Bool

        public init(index: Int, text: String, isWrapped: Bool) {
            self.index = index
            self.text = text
            self.isWrapped = isWrapped
        }
    }

    /// Uma linha numerada: a frase inteira, mesmo quebrada em várias linhas da tela.
    public struct Line: Equatable, Sendable {
        public var rows: ClosedRange<Int>
        public var text: String

        public init(rows: ClosedRange<Int>, text: String) {
            self.rows = rows
            self.text = text
        }
    }

    /// As linhas com texto, de cima para baixo. A linha em branco não ganha número.
    public static func lines(_ rows: [Row]) -> [Line] {
        var lines: [Line] = []
        var current: Line?
        func close() {
            if let line = current, !line.text.allSatisfy(\.isWhitespace) { lines.append(line) }
            current = nil
        }
        for row in rows {
            if row.isWrapped, let line = current {
                current = Line(rows: line.rows.lowerBound...row.index, text: line.text + row.text)
            } else {
                close()
                current = Line(rows: row.index...row.index, text: row.text)
            }
        }
        close()
        return lines
    }

    public let lines: [Line]
    private var anchor: Int
    private var cursor: Int
    /// Algarismos digitados do número em curso.
    public private(set) var typed = ""

    /// Começa na última linha, a mais perto do prompt. nil sem nenhuma linha.
    public init?(lines: [Line]) {
        guard !lines.isEmpty else { return nil }
        self.lines = lines
        anchor = lines.count - 1
        cursor = anchor
    }

    /// Índices das linhas escolhidas.
    public var selected: ClosedRange<Int> { min(anchor, cursor)...max(anchor, cursor) }

    /// O que vai para a área de transferência: uma linha por escolhida.
    public var text: String { lines[selected].map(\.text).joined(separator: "\n") }

    /// Seta: anda `offset` linhas. Com o Shift, estende a escolha até lá.
    public mutating func move(by offset: Int, extending: Bool = false) {
        typed = ""
        cursor = min(lines.count - 1, max(0, cursor + offset))
        if !extending { anchor = cursor }
    }

    /// Algarismo digitado: continua o número em curso; se a linha não existe, começa outro.
    public mutating func type(_ digit: Int) {
        for candidate in [typed + String(digit), String(digit)] {
            if let number = Int(candidate), (1...lines.count).contains(number) {
                typed = candidate
                anchor = number - 1
                cursor = anchor
                return
            }
        }
        typed = ""
    }
}
