import Foundation

/// Um agente gravado no `config.json`. Campo inválido vira nil e quem restaura decide o padrão.
public struct SavedAgent: Equatable, Sendable {
    public var name: String?
    public var cwd: String?
    public var sessionID: String?
    /// Passo de escurecimento da cor da empresa (campo `color` do arquivo).
    public var tone: Int?

    public init(name: String?, cwd: String?, sessionID: String?, tone: Int?) {
        self.name = name
        self.cwd = cwd
        self.sessionID = sessionID
        self.tone = tone
    }
}

/// Conteúdo do `config.json`. Cada campo inválido cai no padrão; chave desconhecida é preservada.
public struct ClarkConfig {
    public static let fontScaleRange = 0.6...2.5
    public static let fontSizeRange = 6.0...48.0
    public static let maxAgents = 16
    public static let layouts = ["focus", "grid"]

    public var theme = "dark"
    public var layout = "focus"
    public var fontName = "Menlo"
    public var fontSize = 12.0
    public var fontScale = 1.0
    public var dragons = true
    public var queueVisible = true
    public var cwd: String?
    public var skillsDir: String?
    public var mainAgent = 0
    public var agents: [SavedAgent] = []
    /// Apelidos dados pelo usuário: caminho da pasta -> nome do projeto no menu, no cabeçalho e no card.
    public var projectNames: [String: String] = [:]
    /// Chaves que esta versão não conhece: voltam para o arquivo como vieram.
    public var unknown: [String: Any] = [:]

    private static let knownKeys: Set<String> = [
        "theme", "layout", "font", "font_scale", "dragons", "queue_visible",
        "cwd", "skills_dir", "main_agent", "agents", "project_names",
    ]

    public init() {}

    public init(json object: [String: Any]) {
        if let value = object["theme"] as? String, Theme.names.contains(value) { theme = value }
        if let value = object["layout"] as? String, Self.layouts.contains(value) { layout = value }
        if let value = object["font"] as? String, let font = Self.parseFont(value) {
            fontName = font.name
            fontSize = font.size
        }
        if let value = Self.number(object["font_scale"]) {
            fontScale = min(Self.fontScaleRange.upperBound, max(Self.fontScaleRange.lowerBound, value))
        }
        if let value = Self.bool(object["dragons"]) { dragons = value }
        if let value = Self.bool(object["queue_visible"]) { queueVisible = value }
        cwd = Self.text(object["cwd"])
        skillsDir = Self.text(object["skills_dir"])
        if let value = Self.integer(object["main_agent"]), value >= 0 { mainAgent = value }
        if let list = object["agents"] as? [Any] {
            agents = list.compactMap { $0 as? [String: Any] }.prefix(Self.maxAgents).map { entry in
                SavedAgent(name: Self.text(entry["name"]), cwd: Self.text(entry["cwd"]),
                           sessionID: SessionLocator.normalized(entry["session_id"] as? String),
                           tone: Self.integer(entry["color"]).map { abs($0) % CompanyResolver.toneCount })
            }
        }
        if let names = object["project_names"] as? [String: Any] {
            for (path, value) in names where !path.isEmpty {
                if let text = value as? String, let name = ProjectNaming.sanitizedNickname(text) {
                    projectNames[path] = name
                }
            }
        }
        unknown = object.filter { !Self.knownKeys.contains($0.key) }
    }

    public func jsonObject() -> [String: Any] {
        var object = unknown
        object["theme"] = theme
        object["layout"] = layout
        object["font"] = "\(fontName) \(Self.format(fontSize))"
        object["font_scale"] = (fontScale * 100).rounded() / 100
        object["dragons"] = dragons
        object["queue_visible"] = queueVisible
        object["cwd"] = cwd
        object["skills_dir"] = skillsDir
        object["main_agent"] = mainAgent
        object["agents"] = agents.map { agent -> [String: Any] in
            var entry: [String: Any] = [:]
            entry["name"] = agent.name
            entry["cwd"] = agent.cwd
            entry["session_id"] = agent.sessionID
            entry["color"] = agent.tone
            return entry
        }
        object["project_names"] = projectNames.isEmpty ? nil : projectNames
        return object
    }

    /// `"Menlo 12"` -> nome e tamanho. O tamanho é o último pedaço.
    static func parseFont(_ text: String) -> (name: String, size: Double)? {
        let parts = text.split(separator: " ")
        guard parts.count >= 2, let size = Double(parts[parts.count - 1]), fontSizeRange.contains(size) else {
            return nil
        }
        return (parts.dropLast().joined(separator: " "), size)
    }

    private static func format(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(size)
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// O JSON `true` não vale como número, nem `1` como booleano.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number == number.rounded(), abs(number) < 1_000_000 else { return nil }
        return Int(number)
    }
}

/// Lê e grava `~/.config/clark/config.json` e lê `companies.json` (que o app nunca grava).
public final class ConfigStore {
    public let directory: String
    public var configPath: String { directory + "/config.json" }
    public var companiesPath: String { directory + "/companies.json" }

    private let now: () -> Date
    /// O arquivo lido era inválido e ainda não foi posto de lado.
    private var quarantinePending = false

    public init(directory: String, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    public static func defaultDirectory(home: String) -> String {
        home + "/.config/clark"
    }

    public func load() -> (config: ClarkConfig, warning: String?) {
        guard FileManager.default.fileExists(atPath: configPath) else { return (ClarkConfig(), nil) }
        guard let data = FileManager.default.contents(atPath: configPath),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            quarantinePending = true
            return (ClarkConfig(), "config.json invalido: valendo os padroes")
        }
        return (ClarkConfig(json: object), nil)
    }

    /// Conteúdo do `companies.json`, ou nil quando o arquivo não existe.
    public func companiesData() -> Data? {
        FileManager.default.contents(atPath: companiesPath)
    }

    /// Pasta `0700`, arquivo `0600`, troca atômica. O arquivo inválido encontrado no `load`
    /// é renomeado para `config.json.invalido-<data>` antes da primeira gravação.
    public func save(_ config: ClarkConfig) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        if quarantinePending {
            try manager.moveItem(atPath: configPath, toPath: quarantinePath())
            quarantinePending = false
        }
        let data = try JSONSerialization.data(withJSONObject: config.jsonObject(),
                                              options: [.prettyPrinted, .sortedKeys])
        try Self.writeAtomically(data, to: configPath)
    }

    private func quarantinePath() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(configPath).invalido-\(formatter.string(from: now()))"
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Grava num temporário criado já com `0600` e troca pelo destino com `rename`.
    /// Se o destino é um link (dotfiles), grava ao lado do arquivo real para o link continuar valendo.
    static func writeAtomically(_ data: Data, to path: String) throws {
        var target = path
        if let real = realpath(path, nil) {
            target = String(cString: real)
            free(real)
        }
        let folder = (target as NSString).deletingLastPathComponent
        let temporary = "\(folder)/.clark-tmp-\(getpid())-\(UUID().uuidString)"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        if fchmod(descriptor, 0o600) != 0 { failure = errno }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while failure == 0 && offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno != EINTR { failure = errno }
                } else {
                    offset += written
                }
            }
        }
        if failure == 0 && fsync(descriptor) != 0 { failure = errno }
        close(descriptor)
        if failure == 0 && rename(temporary, target) != 0 { failure = errno }
        if failure != 0 {
            unlink(temporary)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
