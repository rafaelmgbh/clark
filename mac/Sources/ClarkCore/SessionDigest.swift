import Foundation

/// O que ficou da última conversa do Claude Code numa pasta: título, último pedido e o começo
/// da última resposta. Sai do arquivo da conversa, sem chamar modelo nenhum.
public struct SessionDigest: Equatable, Sendable {
    public enum Kind: Sendable {
        case prompt, answer, pending
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Linhas do corpo, fora o título.
    public static let maxBodyLines = 3

    public var title: String?
    public var prompt: String?
    /// Começo da última resposta, sem markdown.
    public var answer: [String]
    /// Linha da última resposta que fala do que ficou por fazer.
    public var pending: String?
    public var date: Date

    public init(title: String?, prompt: String?, answer: [String] = [], pending: String? = nil, date: Date) {
        self.title = title
        self.prompt = prompt
        self.answer = answer
        self.pending = pending
        self.date = date
    }

    /// O pedido, a resposta e a pendência, nessa ordem. A pendência tira o lugar de uma linha da resposta.
    public var body: [Line] {
        var lines: [Line] = []
        if let prompt { lines.append(Line(.prompt, "Pedido: " + prompt)) }
        let room = Self.maxBodyLines - lines.count - (pending == nil ? 0 : 1)
        lines += answer.prefix(max(0, room)).map { Line(.answer, $0) }
        if let pending { lines.append(Line(.pending, "Pendente: " + pending)) }
        return lines
    }

    /// `HOJE 09:07`, `ONTEM 23:40`, `03/10 09:07` ou `31/12/2025`. Só o que a fonte pixel desenha.
    public func when(now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let time = Self.two(parts.hour) + ":" + Self.two(parts.minute)
        if calendar.isDate(date, inSameDayAs: now) { return "HOJE " + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "ONTEM " + time
        }
        let day = Self.two(parts.day) + "/" + Self.two(parts.month)
        if parts.year == calendar.component(.year, from: now) { return day + " " + time }
        return day + "/" + String(parts.year ?? 0)
    }

    private static func two(_ value: Int?) -> String {
        let text = String(value ?? 0)
        return text.count < 2 ? "0" + text : text
    }
}

/// Acha a conversa mais nova de uma pasta e tira o resumo do fim do arquivo.
public enum SessionDigestReader {
    /// Quanto do fim do arquivo é lido. O título e o último pedido são regravados perto do fim.
    public static let tailBytes = 256 * 1024
    public static let maxLineLength = 160
    public static let answerLines = 2
    /// Conversas tentadas, da mais nova para a mais antiga, até uma ter o que mostrar.
    public static let maxCandidates = 5

    /// Pasta em que o Claude Code guarda as conversas de um diretório: o caminho com tudo o que não
    /// é letra ou número ASCII trocado por traço, unidade a unidade do UTF-16, como ele faz.
    public static func projectFolder(canonicalDirectory: String, configDir: String) -> String {
        var slug = ""
        for unit in canonicalDirectory.utf16 {
            let keep = (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit)
            slug.append(keep ? Character(UnicodeScalar(UInt8(unit))) : "-")
        }
        return configDir + "/projects/" + slug
    }

    /// Resumo da conversa mais nova da pasta que tenha o que mostrar. nil sem conversa anterior.
    /// - Parameter excluding: conversas que não contam, como a do próprio agente.
    public static func latest(canonicalDirectory: String, configDir: String, excluding: Set<String> = [],
                              tailBytes: Int = SessionDigestReader.tailBytes) -> SessionDigest? {
        let folder = projectFolder(canonicalDirectory: canonicalDirectory, configDir: configDir)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return nil }
        let excluded = Set(excluding.map { $0.lowercased() })
        var candidates: [(path: String, date: Date)] = []
        for name in names where name.hasSuffix(".jsonl") {
            guard let id = SessionLocator.normalized(String(name.dropLast(6))), !excluded.contains(id) else { continue }
            let path = folder + "/" + name
            // Os atributos são os do próprio item: um link para fora da pasta não é seguido.
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let date = attributes[.modificationDate] as? Date else { continue }
            candidates.append((path, date))
        }
        candidates.sort { ($0.date, $0.path) > ($1.date, $1.path) }
        for candidate in candidates.prefix(maxCandidates) {
            if let digest = read(candidate.path, date: candidate.date, tailBytes: tailBytes) { return digest }
        }
        return nil
    }

    private static func read(_ path: String, date: Date, tailBytes: Int) -> SessionDigest? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let length = UInt64(max(0, tailBytes))
        let start = size > length ? size - length : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        return digest(data, startsMidLine: start > 0, date: date)
    }

    /// Resumo de um trecho do arquivo da conversa, uma linha JSON por registro. nil quando não há
    /// título, pedido nem resposta.
    /// - Parameter startsMidLine: o trecho começa no meio de um registro, que é descartado.
    public static func digest(_ data: Data, startsMidLine: Bool, date: Date) -> SessionDigest? {
        var data = data
        if startsMidLine {
            guard let lineEnd = data.firstIndex(of: 0x0a) else { return nil }
            data = data[data.index(after: lineEnd)...]
        }
        var title: String?, lastPrompt: String?, typed: String?
        var answer: [String] = [], pending: String?
        for line in data.split(separator: 0x0a) {
            guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let type = record["type"] as? String else { continue }
            switch type {
            case "ai-title":
                if let text = firstLine(record["aiTitle"] as? String) { title = text }
            case "last-prompt":
                if let text = firstLine(record["lastPrompt"] as? String) { lastPrompt = text }
            case "assistant", "user":
                // Fora ficam os subagentes e os avisos que o próprio Claude Code injeta.
                if record["isSidechain"] as? Bool == true || record["isMeta"] as? Bool == true { continue }
                guard let message = record["message"] as? [String: Any] else { continue }
                let text = Self.text(of: message["content"])
                if type == "assistant" {
                    let summary = summarize(text)
                    if !summary.lines.isEmpty || summary.pending != nil {
                        answer = summary.lines
                        pending = summary.pending
                    }
                } else if let line = firstLine(text), !line.hasPrefix("<"), !line.hasPrefix("[Request interrupted") {
                    typed = line
                }
            default:
                continue
            }
        }
        let prompt = lastPrompt ?? typed
        if title == nil, prompt == nil, answer.isEmpty, pending == nil { return nil }
        return SessionDigest(title: title, prompt: prompt, answer: answer, pending: pending, date: date)
    }

    /// Texto de uma mensagem: a string, ou os blocos `text` juntos. Ferramenta e raciocínio ficam de fora.
    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }.joined(separator: "\n")
    }

    /// Uma linha de texto de tela: sem caractere de controle, espaços juntos, tamanho limitado.
    static func clean(_ text: String) -> String? {
        let spaced = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            scalar.properties.isWhitespace ? " " : scalar
        }.filter { $0.properties.generalCategory != .control }
        let joined = String(String.UnicodeScalarView(spaced)).split(separator: " ").joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return joined.count > maxLineLength ? joined.prefix(maxLineLength - 1) + "…" : joined
    }

    private static func firstLine(_ text: String?) -> String? {
        for line in (text ?? "").split(whereSeparator: \.isNewline) {
            if let cleaned = clean(String(line)) { return cleaned }
        }
        return nil
    }

    // MARK: resposta

    /// As primeiras linhas da resposta sem markdown e, à parte, a linha que fala de pendência.
    static func summarize(_ text: String) -> (lines: [String], pending: String?) {
        var lines: [(text: String, unchecked: Bool)] = []
        var insideCode = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCode.toggle()
                continue
            }
            if insideCode { continue }
            guard let line = plain(trimmed) else { continue }
            lines.append(line)
        }
        var pendingIndex = lines.firstIndex { $0.unchecked || mentionsPending($0.text) }
        // A pergunta no fim da resposta ficou sem resposta.
        if pendingIndex == nil, let last = lines.last, last.text.hasSuffix("?") { pendingIndex = lines.count - 1 }
        let pending = pendingIndex.map { lines.remove(at: $0).text }
        return (lines.prefix(answerLines).map(\.text), pending)
    }

    /// Linha de markdown como texto corrido. nil para o que não é texto: régua, separador de tabela.
    private static func plain(_ line: String) -> (text: String, unchecked: Bool)? {
        if line.isEmpty { return nil }
        let marks = line.filter { !$0.isWhitespace }
        if marks.count >= 3, marks.allSatisfy({ "-*_".contains($0) }), Set(marks).count == 1 { return nil }
        if marks.contains("-"), marks.allSatisfy({ "|-:".contains($0) }) { return nil }

        var text = Substring(line)
        var unchecked = false
        while text.hasPrefix(">") { text = text.dropFirst().drop(while: \.isWhitespace) }
        if text.hasPrefix("#") {
            text = text.drop(while: { $0 == "#" }).drop(while: \.isWhitespace)
        } else if let item = listItem(text) {
            text = item
            for (box, open) in [("[ ]", true), ("[x]", false), ("[X]", false)] where text.hasPrefix(box) {
                unchecked = open
                text = text.dropFirst(box.count).drop(while: \.isWhitespace)
            }
        }
        var result = String(text)
        if result.hasPrefix("|") {
            result = result.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        // `[texto](destino)` e `![imagem](destino)` ficam só com o texto.
        result = result.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "~~", "`"] { result = result.replacingOccurrences(of: mark, with: "") }
        guard let cleaned = clean(result) else { return nil }
        return (cleaned, unchecked)
    }

    /// O texto depois do marcador de lista (`- `, `* `, `+ `, `1. `, `2) `). nil quando a linha não é item.
    private static func listItem(_ text: Substring) -> Substring? {
        var rest = text
        if let first = rest.first, "-*+".contains(first) {
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, digits.count <= 3 else { return nil }
            rest = rest.dropFirst(digits.count)
            guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
            rest = rest.dropFirst()
        }
        guard let space = rest.first, space.isWhitespace else { return nil }
        return rest.drop(while: \.isWhitespace)
    }

    private static let pendingWords: Set<String> = [
        "pendente", "pendentes", "pendencia", "pendencias", "falta", "faltam", "faltou", "faltando",
        "aguardando", "pending", "remaining",
    ]
    private static let pendingPairs: Set<String> = [
        "proximo passo", "proximos passos", "ainda nao", "next step", "next steps",
    ]
    /// Frases que citam a pendência para dizer que não há nenhuma.
    private static let nothingPending = [
        "sem pendenc", "nenhuma pendenc", "nao ha pendenc", "nada pendente", "nao falta", "nada falta",
        "no pending", "nothing pending", "nothing remaining",
    ]

    /// A linha fala do que ficou por fazer. Palavra inteira: `asfalto` não é `falta`, e `Todo o` não é `TODO`.
    static func mentionsPending(_ line: String) -> Bool {
        let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if nothingPending.contains(where: folded.contains) { return false }
        if line.split(whereSeparator: { !$0.isLetter }).contains("TODO") { return true }
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: pendingWords.contains) { return true }
        return zip(words, words.dropFirst()).contains { pendingPairs.contains($0 + " " + $1) }
    }
}
