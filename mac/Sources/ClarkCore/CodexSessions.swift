import Foundation

/// O que o Codex grava das conversas: um `rollout-<hora>-<id>.jsonl` por conversa, na pasta do dia
/// (`<CODEX_HOME>/sessions/AAAA/MM/DD`). A primeira linha diz a pasta de trabalho; os eventos
/// `task_started`, `task_complete` e `turn_aborted` marcam o turno.
public enum CodexSessions {
    /// Quanto do começo do arquivo é lido para achar a pasta: ela vem logo no começo da primeira linha.
    public static let headBytes = 8 * 1024
    /// Quanto do fim do arquivo é lido para saber se o turno acabou.
    public static let tailBytes = 64 * 1024

    /// Pasta do Codex, respeitando `CODEX_HOME` do ambiente do agente.
    public static func home(environment: [String: String], home: String) -> String {
        if let directory = environment["CODEX_HOME"], !directory.isEmpty {
            return PathTools.expandTilde(directory, home: home)
        }
        return home + "/.codex"
    }

    /// O arquivo da conversa, em qualquer dia. nil quando o id não é UUID ou a conversa não existe.
    public static func path(of id: String, codexHome: String) -> String? {
        guard let id = SessionLocator.normalized(id) else { return nil }
        let root = URL(fileURLWithPath: codexHome + "/sessions", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return nil }
        for case let file as URL in files where file.lastPathComponent.hasSuffix("-\(id).jsonl") {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return file.path }
        }
        return nil
    }

    /// Pasta de trabalho da conversa, da primeira linha do arquivo.
    public static func cwd(path: String) -> String? {
        guard let head = read(path, bytes: headBytes, fromEnd: false),
              let range = head.range(of: #""cwd":"((?:[^"\\]|\\.)*)""#, options: .regularExpression) else { return nil }
        let quoted = String(head[range].dropFirst(6))
        return (try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)))
    }

    /// A conversa que o agente aberto em `since` começou na pasta: a primeira gravada lá desde então,
    /// fora as dos outros agentes abertos. O Codex não deixa escolher o id: ele é descoberto assim.
    public static func newSession(codexHome: String, directory: String, since: Date, excluding: Set<String>,
                                  now: Date, canonicalize: (String) -> String) -> String? {
        let candidates = rollouts(codexHome: codexHome, from: since, to: now)
            .filter { $0.modified >= since && !excluding.contains($0.id) }
            .sorted { ($0.created, $0.id) < ($1.created, $1.id) }
        return candidates.first { cwd(path: $0.path).map(canonicalize) == directory }?.id
    }

    /// O turno começou e ainda não acabou.
    public static func isBusy(path: String) -> Bool {
        guard let tail = read(path, bytes: tailBytes, fromEnd: true) else { return false }
        for line in tail.split(separator: "\n").reversed() where line.contains(#""type":"event_msg""#) {
            if line.contains(#""type":"task_started""#) { return true }
            if line.contains(#""type":"task_complete""#) || line.contains(#""type":"turn_aborted""#) { return false }
        }
        return false
    }

    /// Conversas por pasta mexidas dentro da janela, para os mais usados da cascata `Projeto`.
    public static func usage(codexHome: String, now: Date, window: TimeInterval = ProjectUsage.window,
                             canonicalize: (String) -> String) -> [String: ProjectUsage.Count] {
        let oldest = now.addingTimeInterval(-window)
        var counts: [String: ProjectUsage.Count] = [:]
        for rollout in rollouts(codexHome: codexHome, from: oldest, to: now) where rollout.modified >= oldest {
            guard let cwd = cwd(path: rollout.path).map(canonicalize) else { continue }
            let before = counts[cwd]
            counts[cwd] = ProjectUsage.Count(conversations: (before?.conversations ?? 0) + 1,
                                             latest: max(before?.latest ?? .distantPast, rollout.modified))
        }
        return counts
    }

    private struct Rollout {
        var id: String
        var path: String
        var created: Date
        var modified: Date
    }

    /// As conversas das pastas dos dias entre `from` e `to`, com um dia de folga de cada lado: a
    /// pasta é a do dia local de quando a conversa começou.
    private static func rollouts(codexHome: String, from: Date, to: Date) -> [Rollout] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: from.addingTimeInterval(-24 * 60 * 60))
        let last = to.addingTimeInterval(24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        var found: [Rollout] = []
        while day <= last {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = String(format: "%@/sessions/%04d/%02d/%02d", codexHome, parts.year ?? 0, parts.month ?? 0,
                                parts.day ?? 0)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: Array(keys))) ?? []
            for file in files where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") {
                // Os valores são os do próprio item: um link para fora da pasta não é seguido.
                guard let id = SessionLocator.normalized(String(file.deletingPathExtension().lastPathComponent.suffix(36))),
                      let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let modified = values.contentModificationDate else { continue }
                found.append(Rollout(id: id, path: file.path, created: values.creationDate ?? modified,
                                     modified: modified))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return found
    }

    private static func read(_ path: String, bytes: Int, fromEnd: Bool) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        if fromEnd, let size = try? handle.seekToEnd(), size > UInt64(bytes) {
            try? handle.seek(toOffset: size - UInt64(bytes))
        } else {
            try? handle.seek(toOffset: 0)
        }
        guard let data = try? handle.read(upToCount: bytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
