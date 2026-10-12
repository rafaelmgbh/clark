import Foundation

public enum AgentNaming {
    public static let maxLength = 20

    /// `"AGENT 3"` -> 3. Qualquer outro nome devolve nil.
    public static func automaticNumber(_ name: String) -> Int? {
        let prefix = "AGENT "
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.utf8.count <= 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(digits)
    }

    /// Menor número livre: fechou o AGENT 2, o próximo volta a ser AGENT 2.
    public static func automaticName(existing: [String]) -> String {
        let used = Set(existing.compactMap(automaticNumber))
        var number = 1
        while used.contains(number) { number += 1 }
        return "AGENT \(number)"
    }

    /// Nome digitado: vira ASCII maiúsculo (a fonte pixel não tem acentos), sem espaços nas
    /// pontas, com até 20 caracteres. Vazio devolve nil.
    public static func sanitized(_ raw: String) -> String? {
        let printable = PixelFont.normalize(raw).unicodeScalars.filter { $0.value >= 32 && $0.value < 127 }
        let trimmed = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        let cut = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }

    /// Menor passo de cor ainda não usado pelos agentes da mesma empresa.
    public static func freeTone(used: [Int]) -> Int {
        (0..<CompanyResolver.toneCount).first { !used.contains($0) } ?? used.count % CompanyResolver.toneCount
    }
}

public enum PreviewLines {
    private static let edges = CharacterSet(charactersIn: "│┃|")
    private static let frame = Set("─━═╭╮╰╯┌┐└┘│┃>❯·•* ".unicodeScalars)

    /// Últimas linhas úteis do terminal para o card: sem moldura, sem linha vazia (`refresh_preview` do original).
    public static func useful(_ lines: [String], limit: Int = 2) -> [String] {
        var useful: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: edges)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.unicodeScalars.allSatisfy({ frame.contains($0) }) { continue }
            useful.append(line)
        }
        return Array(useful.suffix(limit))
    }
}
