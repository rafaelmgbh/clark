import Foundation

/// Quanto uma pasta foi usada no Claude Code, pelas conversas que ele guarda dela. Nada é gravado
/// pelo CLARK: a conta vale também para o que foi aberto fora dele.
public enum ProjectUsage {
    /// Conversa parada há mais tempo que isto não conta. É o prazo em que o Claude Code apaga as
    /// conversas por padrão: quem guarda por mais tempo não fica com um projeto antigo no topo para sempre.
    public static let window: TimeInterval = 30 * 24 * 60 * 60
    /// Quantos projetos a cascata `Projeto` sugere.
    public static let maxSuggestions = 5

    public struct Count: Equatable, Sendable {
        public let conversations: Int
        /// Quando a conversa mais nova foi mexida.
        public let latest: Date

        public init(conversations: Int, latest: Date) {
            self.conversations = conversations
            self.latest = latest
        }
    }

    /// Conversas da pasta mexidas dentro da janela. nil sem nenhuma.
    public static func count(canonicalDirectory: String, configDir: String, now: Date,
                             window: TimeInterval = ProjectUsage.window) -> Count? {
        let folder = URL(fileURLWithPath: SessionDigestReader.projectFolder(canonicalDirectory: canonicalDirectory,
                                                                           configDir: configDir), isDirectory: true)
        // As datas vêm junto com a lista: uma leitura por pasta, não uma por conversa.
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder,
                                                                       includingPropertiesForKeys: Array(keys)) else {
            return nil
        }
        let oldest = now.addingTimeInterval(-window)
        var conversations = 0
        var latest = Date.distantPast
        for file in files where file.pathExtension == "jsonl" {
            // Os valores são os do próprio item: um link para fora da pasta não é seguido.
            guard SessionLocator.normalized(file.deletingPathExtension().lastPathComponent) != nil,
                  let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let date = values.contentModificationDate, date >= oldest else { continue }
            conversations += 1
            latest = max(latest, date)
        }
        return conversations == 0 ? nil : Count(conversations: conversations, latest: latest)
    }

    /// As pastas mais usadas, da mais usada para a menos. No empate vem antes a usada por último.
    /// A pasta sem conversa na janela fica de fora.
    public static func mostUsed(_ canonicalDirectories: [String], configDir: String, now: Date,
                                limit: Int = ProjectUsage.maxSuggestions) -> [String] {
        var seen: Set<String> = []
        var used: [(path: String, count: Count)] = []
        for path in canonicalDirectories where seen.insert(path).inserted {
            if let count = count(canonicalDirectory: path, configDir: configDir, now: now) {
                used.append((path, count))
            }
        }
        used.sort { one, other in
            if one.count.conversations != other.count.conversations {
                return one.count.conversations > other.count.conversations
            }
            if one.count.latest != other.count.latest { return one.count.latest > other.count.latest }
            return one.path < other.path
        }
        return used.prefix(limit).map(\.path)
    }
}
