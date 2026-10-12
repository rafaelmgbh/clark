import Foundation

/// Fonte bitmap 5x7 do original (`_FONT_SRC`), com as mesmas contas de largura e corte.
public enum PixelFont {
    public static let columns = 5
    public static let rows = 7
    /// Passo entre um caractere e o próximo, em pontos da fonte.
    public static let advance = 6

    private static let source: [Character: String] = [
        "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
        "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
        "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
        "G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
        "I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
        "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
        "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
        "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
        "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
        "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
        "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
        "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
        "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
        "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
        "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
        "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
        "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
        "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
        " ": "00000 00000 00000 00000 00000 00000 00000", ".": "00000 00000 00000 00000 00000 01100 01100",
        ":": "00000 01100 01100 00000 01100 01100 00000", "-": "00000 00000 00000 11111 00000 00000 00000",
        "!": "00100 00100 00100 00100 00100 00000 00100", "?": "01110 10001 00001 00010 00100 00000 00100",
        "/": "00001 00001 00010 00100 01000 10000 10000", "+": "00000 00100 00100 11111 00100 00100 00000",
        ">": "01000 00100 00010 00001 00010 00100 01000", "<": "00010 00100 01000 10000 01000 00100 00010",
        "_": "00000 00000 00000 00000 00000 00000 11111", "%": "11001 11001 00010 00100 01000 10011 10011",
        "'": "00100 00100 01000 00000 00000 00000 00000", "(": "00010 00100 01000 01000 01000 00100 00010",
        ")": "01000 00100 00010 00010 00010 00100 01000", "[": "01110 01000 01000 01000 01000 01000 01110",
        "]": "01110 00010 00010 00010 00010 00010 01110", "#": "01010 01010 11111 01010 11111 01010 01010",
        "*": "00000 00100 10101 01110 10101 00100 00000", "=": "00000 00000 11111 00000 11111 00000 00000",
        ",": "00000 00000 00000 00000 01100 00100 01000",
    ]

    /// Para cada caractere, as 7 linhas com os 5 pontos acesos ou apagados.
    private static let glyphs: [Unicode.Scalar: [[Bool]]] = {
        var table: [Unicode.Scalar: [[Bool]]] = [:]
        for (character, rows) in source {
            guard let scalar = character.unicodeScalars.first else { continue }
            table[scalar] = rows.split(separator: " ").map { row in row.map { $0 == "1" } }
        }
        return table
    }()

    /// Tira acentos, descarta o que não é ASCII e passa para maiúsculas (`norm` do original).
    public static func normalize(_ text: String) -> String {
        let ascii = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.isASCII }
        return String(String.UnicodeScalarView(ascii)).uppercased()
    }

    /// Largura em pixels do texto na escala dada (`text_w` do original).
    public static func textWidth(_ text: String, scale: Int) -> Int {
        max(0, normalize(text).unicodeScalars.count * advance * scale - scale)
    }

    /// Corta o texto com `...` para caber em `width` pixels (`fit_text` do original).
    public static func fit(_ text: String, scale: Int, width: Int) -> String {
        let normalized = normalize(text)
        if textWidth(normalized, scale: scale) <= width { return normalized }
        let keep = max(0, (width + scale) / (advance * scale) - 3)
        var scalars = Array(normalized.unicodeScalars.prefix(keep))
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars)) + "..."
    }

    /// Pontos acesos do texto em coordenadas da fonte (sem escala), origem no canto superior esquerdo.
    /// Caractere sem glifo usa o `?`.
    public static func pixels(_ text: String) -> [(x: Int, y: Int)] {
        var points: [(x: Int, y: Int)] = []
        let fallback = glyphs["?"]!
        for (index, scalar) in normalize(text).unicodeScalars.enumerated() {
            let glyph = glyphs[scalar] ?? fallback
            for (row, bits) in glyph.enumerated() {
                for (column, lit) in bits.enumerated() where lit {
                    points.append((x: index * advance + column, y: row))
                }
            }
        }
        return points
    }
}
