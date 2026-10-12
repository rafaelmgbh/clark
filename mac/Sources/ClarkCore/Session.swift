import Foundation

/// Identificador de conversa do Claude Code e a decisão entre retomar e começar.
public enum SessionLocator {
    /// UUID no formato 8-4-4-4-12 em hexadecimal.
    public static func isValidUUID(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                if byte != UInt8(ascii: "-") { return false }
            } else if !((48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)) {
                return false
            }
        }
        return true
    }

    /// UUID em minúsculas, ou nil quando o texto não é um UUID. É a única forma de um
    /// `session_id` do config chegar ao argv.
    public static func normalized(_ text: String?) -> String? {
        guard let text, isValidUUID(text) else { return nil }
        return text.lowercased()
    }

    public static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Pasta de configuração do Claude Code, respeitando `CLAUDE_CONFIG_DIR` do ambiente do agente.
    public static func configDir(environment: [String: String], home: String) -> String {
        if let directory = environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty {
            return PathTools.expandTilde(directory, home: home)
        }
        return home + "/.claude"
    }

    /// A conversa só pode ser retomada depois que o claude grava `<projects>/*/<id>.jsonl`.
    public static func sessionExists(_ id: String, configDir: String) -> Bool {
        guard let id = normalized(id) else { return false }
        let projects = configDir + "/projects"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return false }
        return entries.contains { FileManager.default.fileExists(atPath: "\(projects)/\($0)/\(id).jsonl") }
    }
}

/// Argumentos do `claude` de um agente.
public struct ClaudeCommand: Equatable, Sendable {
    /// Flags que já escolhem a conversa; com elas o CLARK não acrescenta a sua.
    public static let sessionFlags: Set<String> = ["-c", "--continue", "-r", "--resume", "--session-id"]

    /// Argumentos sem o executável.
    public let arguments: [String]
    /// O agente roda sem pedir permissão: o painel mostra a faixa `SEM PERMISSOES`.
    public let bypassesPermissions: Bool

    public static func build(extraArgs: [String], sessionID: String, sessionExists: Bool) -> ClaudeCommand {
        var arguments = extraArgs
        if !hasSessionFlag(extraArgs) {
            arguments += [sessionExists ? "--resume" : "--session-id", sessionID]
        }
        return ClaudeCommand(arguments: arguments, bypassesPermissions: bypassesPermissions(extraArgs))
    }

    public static func hasSessionFlag(_ args: [String]) -> Bool {
        args.contains { argument in
            let flag = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return sessionFlags.contains(String(flag))
        }
    }

    public static func bypassesPermissions(_ args: [String]) -> Bool {
        for (index, argument) in args.enumerated() {
            if argument == "--dangerously-skip-permissions" { return true }
            if argument == "--permission-mode=bypassPermissions" { return true }
            if argument == "--permission-mode", index + 1 < args.count, args[index + 1] == "bypassPermissions" {
                return true
            }
        }
        return false
    }
}

public enum ClaudeLocator {
    /// Procura o `claude` no `PATH` capturado e depois nos lugares de instalação conhecidos.
    /// Entradas relativas do `PATH` são ignoradas.
    public static func find(path: String?, home: String,
                            isExecutable: (String) -> Bool = PathTools.isExecutableFile) -> String? {
        var candidates: [String] = []
        for directory in (path ?? "").split(separator: ":") where directory.hasPrefix("/") {
            candidates.append("\(directory)/claude")
        }
        candidates += ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                       "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first(where: isExecutable)
    }
}
