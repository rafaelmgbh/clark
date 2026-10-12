import Foundation

/// Ambiente final de um agente e os nomes que ficaram de fora por parecerem segredo.
public struct AgentEnvironment: Equatable, Sendable {
    public let variables: [String: String]
    /// Só nomes, em ordem alfabética. Valores nunca saem daqui.
    public let removed: [String]

    /// Formato `NOME=valor` que o `LocalProcess` do SwiftTerm espera.
    public var asArray: [String] {
        variables.map { "\($0.key)=\($0.value)" }.sorted()
    }
}

public enum EnvPolicy {
    /// Variáveis de sessão do Claude Code que abriu o CLARK (`PARENT_SESSION_VARS` do original).
    /// Se chegassem ao agente, ele se acharia uma subsessão. Nunca voltam, nem por `env_allow`.
    public static let parentSessionVars = [
        "CLAUDECODE", "CLAUDE_PID", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH",
        "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
    ]

    /// Nomes com cara de segredo, comparados sem diferenciar maiúsculas. `*` casa com qualquer trecho.
    /// As formas curtas (`_PASS`, `_PWD`, `_PAT`) só valem no fim do nome e com o `_`: `PWD` e `PATH` ficam.
    public static let secretPatterns = [
        "*KEY*", "*TOKEN*", "*SECRET*", "*PASSWORD*", "*PASSWD*", "*CREDENTIAL*",
        "AWS_*", "PG*", "*_DSN", "DATABASE_URL", "*_PASS", "*_PWD", "*_PAT",
    ]

    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.utf8.first else { return false }
        func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
        func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        return isLetter(first) && name.utf8.allSatisfy { isLetter($0) || isDigit($0) }
    }

    public static func matches(_ name: String, pattern: String) -> Bool {
        let text = Array(name.lowercased().utf8)
        let glob = Array(pattern.lowercased().utf8)
        let star = UInt8(ascii: "*")
        var textIndex = 0, globIndex = 0, lastStar = -1, resume = 0
        while textIndex < text.count {
            if globIndex < glob.count, glob[globIndex] == star {
                lastStar = globIndex
                resume = textIndex
                globIndex += 1
            } else if globIndex < glob.count, glob[globIndex] == text[textIndex] {
                textIndex += 1
                globIndex += 1
            } else if lastStar >= 0 {
                globIndex = lastStar + 1
                resume += 1
                textIndex = resume
            } else {
                return false
            }
        }
        while globIndex < glob.count, glob[globIndex] == star { globIndex += 1 }
        return globIndex == glob.count
    }

    public static func isSecret(_ name: String) -> Bool {
        secretPatterns.contains { matches(name, pattern: $0) }
    }

    /// Ambiente base + empresa -> ambiente do agente.
    /// Ordem: saem as variáveis de sessão do pai; saem os nomes com cara de segredo, menos os
    /// liberados em `env_allow` (global e da empresa); entram as variáveis do próprio CLARK.
    public static func apply(base: [String: String], globalAllow: [String], company: Company,
                             agentName: String) -> AgentEnvironment {
        var variables = base
        for name in parentSessionVars { variables[name] = nil }
        let allowed = Set(globalAllow).union(company.envAllow).subtracting(parentSessionVars)
        var removed: [String] = []
        for name in base.keys where variables[name] != nil && isSecret(name) && !allowed.contains(name) {
            variables[name] = nil
            removed.append(name)
        }
        variables["TERM"] = "xterm-256color"
        variables["COLORTERM"] = "truecolor"
        variables["CLARK_AGENT"] = agentName
        variables["CLARK_COMPANY"] = company.name
        return AgentEnvironment(variables: variables, removed: removed.sorted())
    }
}
