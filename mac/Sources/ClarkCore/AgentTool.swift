import Foundation

/// O programa que o agente roda no terminal. O Claude Code é o padrão; o Codex abre o mesmo painel,
/// sem o que o CLARK lê das conversas do Claude Code (retomar, segundo plano, estado pelo arquivo,
/// resumo da última sessão).
public enum AgentTool: String, CaseIterable, Sendable {
    case claude
    case codex

    /// Começo do nome automático: `AGENT 1`, `CODEX 1`.
    public var namePrefix: String {
        switch self {
        case .claude: "AGENT"
        case .codex: "CODEX"
        }
    }
}

public enum CodexLocator {
    /// Procura o `codex` no `PATH` capturado e depois nos lugares de instalação conhecidos.
    /// Entradas relativas do `PATH` são ignoradas.
    public static func find(path: String?, home: String,
                            isExecutable: (String) -> Bool = PathTools.isExecutableFile) -> String? {
        var candidates: [String] = []
        for directory in (path ?? "").split(separator: ":") where directory.hasPrefix("/") {
            candidates.append("\(directory)/codex")
        }
        candidates += ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first(where: isExecutable)
    }
}
