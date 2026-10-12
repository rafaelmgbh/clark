import Foundation

/// O que aconteceu com um arquivo desde o último commit.
public enum DiffStatus: String, Equatable, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    /// Arquivo novo que o git ainda não acompanha.
    case untracked = "?"

    /// Letra do `git diff --raw`. Troca de tipo, conflito e o que mais vier contam como modificado.
    init(letter: Character?) {
        switch letter {
        case "A": self = .added
        case "D": self = .deleted
        default: self = .modified
        }
    }
}

/// Um arquivo mudado. As contagens são nil quando o git não conta linhas (arquivo binário).
public struct DiffFile: Equatable, Sendable {
    public var path: String
    public var status: DiffStatus
    public var added: Int?
    public var removed: Int?

    public init(path: String, status: DiffStatus, added: Int?, removed: Int?) {
        self.path = path
        self.status = status
        self.added = added
        self.removed = removed
    }
}

/// Totais que aparecem no cabeçalho e no card do agente.
public struct DiffSummary: Equatable, Sendable {
    public var files: Int
    public var added: Int
    public var removed: Int

    public init(files: Int, added: Int, removed: Int) {
        self.files = files
        self.added = added
        self.removed = removed
    }

    public init(_ files: [DiffFile]) {
        self.init(files: files.count, added: files.reduce(0) { $0 + ($1.added ?? 0) },
                  removed: files.reduce(0) { $0 + ($1.removed ?? 0) })
    }

    public var addedLabel: String { "+" + Self.short(added) }
    public var removedLabel: String { "-" + Self.short(removed) }
    public var filesLabel: String { Self.short(files) + " ARQ" }

    /// Só ASCII em maiúsculas, que é o que a fonte de pixels tem.
    public var label: String { [addedLabel, removedLabel, filesLabel].joined(separator: " ") }

    /// `1234` vira `1.2K`. Corta em vez de arredondar: o número mostrado nunca passa do real.
    public static func short(_ value: Int) -> String {
        func scaled(_ unit: Int, _ suffix: String) -> String {
            let tenths = value * 10 / unit
            if tenths >= 100 || tenths % 10 == 0 { return "\(tenths / 10)\(suffix)" }
            return "\(tenths / 10).\(tenths % 10)\(suffix)"
        }
        switch value {
        case ..<1000: return String(value)
        case ..<1_000_000: return scaled(1000, "K")
        default: return scaled(1_000_000, "M")
        }
    }
}

/// Uma linha do diff e o que ela é, para a cor.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Linhas antes do primeiro `@@` de cada arquivo (`diff --git`, `index`, `---`, `+++`, aviso de binário).
        case header
        case hunk
        case added
        case removed
        case context
        /// `\ No newline at end of file`.
        case note
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Leitura da saída do git. Nada aqui roda o git: quem roda é o app.
public enum GitDiff {
    /// Árvore vazia do git. Serve de base do diff no repositório que ainda não tem commit.
    public static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// Saída de `git diff --raw --numstat -z --no-renames`: primeiro os registros de estado
    /// (`:modo modo id id LETRA`, nulo, caminho, nulo), depois os de contagem (`mais`, tab, `menos`, tab,
    /// caminho, nulo). A ordem dos arquivos é a do git. Um registro cortado no fim da saída é descartado.
    public static func parseChanges(_ output: Data) -> [DiffFile] {
        let tokens = records(output)
        var files: [DiffFile] = []
        var position: [String: Int] = [:]
        var index = 0
        while index < tokens.count, tokens[index].hasPrefix(":") {
            guard index + 1 < tokens.count else { break }
            let path = tokens[index + 1]
            position[path] = files.count
            files.append(DiffFile(path: path, status: DiffStatus(letter: tokens[index].last),
                                  added: nil, removed: nil))
            index += 2
        }
        for token in tokens[index...] {
            let fields = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let at = position[String(fields[2])] else { continue }
            files[at].added = Int(fields[0])
            files[at].removed = Int(fields[1])
        }
        return files
    }

    /// Saída de `git ls-files --others --exclude-standard -z`: um caminho por registro.
    public static func parseUntracked(_ output: Data) -> [String] {
        records(output).filter { !$0.isEmpty }
    }

    /// Lista única em ordem de caminho.
    public static func merged(_ tracked: [DiffFile], untracked: [DiffFile]) -> [DiffFile] {
        (tracked + untracked).sorted { $0.path < $1.path }
    }

    /// Linhas de um arquivo novo, para a contagem do não rastreado. nil: binário, pela mesma régua do git
    /// (byte nulo no começo do arquivo).
    public static func lineCount(_ content: Data) -> Int? {
        if content.prefix(8000).contains(0) { return nil }
        guard let last = content.last else { return 0 }
        let newline = UInt8(ascii: "\n")
        return content.reduce(0) { $0 + ($1 == newline ? 1 : 0) } + (last == newline ? 0 : 1)
    }

    /// Classifica as linhas de um diff no formato unificado.
    public static func lines(of text: String) -> [DiffLine] {
        // Por escalar, não por caractere: `\r\n` é um caractere só e não seria cortado.
        var pieces = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        if pieces.last?.isEmpty == true { pieces.removeLast() }
        var inHunk = false
        return pieces.map { piece in
            let line = String(piece.last == "\r" ? piece.dropLast() : piece)
            if line.hasPrefix("diff --git ") {
                inHunk = false
                return DiffLine(kind: .header, text: line)
            }
            if line.hasPrefix("@@") {
                inHunk = true
                return DiffLine(kind: .hunk, text: line)
            }
            guard inHunk else { return DiffLine(kind: .header, text: line) }
            switch line.first {
            case "+": return DiffLine(kind: .added, text: line)
            case "-": return DiffLine(kind: .removed, text: line)
            case "\\": return DiffLine(kind: .note, text: line)
            default: return DiffLine(kind: .context, text: line)
            }
        }
    }

    /// Registros separados por byte nulo. O que sobra depois do último nulo é saída cortada e sai.
    private static func records(_ output: Data) -> [String] {
        var pieces = output.split(separator: 0, omittingEmptySubsequences: false)
        if !pieces.isEmpty { pieces.removeLast() }
        return pieces.map { String(decoding: $0, as: UTF8.self) }
    }
}

public enum GitLocator {
    /// Atalho do macOS: sem as ferramentas de desenvolvedor, rodá-lo abre o diálogo de instalação.
    public static let shim = "/usr/bin/git"

    static let developerTools = [
        "/var/db/xcode_select_link/usr/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    /// Procura o `git` no `PATH` capturado e depois nos lugares conhecidos. Entradas relativas do `PATH`
    /// são ignoradas, e o atalho do sistema é trocado pelo git das ferramentas de desenvolvedor.
    public static func find(path: String?, isExecutable: (String) -> Bool = PathTools.isExecutableFile) -> String? {
        var candidates: [String] = []
        for directory in (path ?? "").split(separator: ":") where directory.hasPrefix("/") {
            let candidate = "\(directory)/git"
            candidates += candidate == shim ? developerTools : [candidate]
        }
        candidates += developerTools + ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        return candidates.first(where: isExecutable)
    }
}
