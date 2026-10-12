import Foundation

public struct Company: Equatable, Sendable {
    public let name: String
    public let color: RGB
    /// Variáveis com cara de segredo que esta empresa pode receber.
    public let envAllow: [String]

    public init(name: String, color: RGB, envAllow: [String]) {
        self.name = name
        self.color = color
        self.envAllow = envAllow
    }
}

/// Caminho -> empresa, a partir do `companies.json` (opcional).
/// 1. `paths` explícitos, vencendo o prefixo mais longo;
/// 2. primeira pasta abaixo de uma das `roots`;
/// 3. `AVULSO`.
/// Só o passo 1 dá `env_allow`: uma empresa detectada pela pasta nunca libera variável.
public struct CompanyResolver: Sendable {
    public static let fallbackName = "AVULSO"
    public static let defaultRoots = ["~/Projetos"]
    /// Agentes da mesma empresa escurecem nestes passos: 0, 15, 30 e 45%.
    public static let toneStep = 0.15
    public static let toneCount = 4

    public let globalEnvAllow: [String]
    /// Problemas encontrados no arquivo. Nunca trazem o valor inválido, que pode ser um segredo colado por engano.
    public let warnings: [String]

    private struct Rule: Sendable {
        let prefix: [String]
        let company: Company
        /// Posição da empresa na lista do arquivo, a partir de 1. Só para os avisos.
        let position: Int
    }

    private let rules: [Rule]
    private let roots: [[String]]
    private let palette: [RGB]
    private let fallbackColor: RGB

    /// - Parameters:
    ///   - json: conteúdo do `companies.json`, ou nil quando o arquivo não existe.
    ///   - canonicalize: transforma um caminho do arquivo no mesmo formato dos caminhos passados a `resolve`.
    public init(json: Data?, palette: [RGB], fallbackColor: RGB, canonicalize: (String) -> String) {
        self.palette = palette
        self.fallbackColor = fallbackColor
        var warnings: [String] = []
        var rootPaths = Self.defaultRoots
        var globalAllow: [String] = []
        var rules: [Rule] = []

        if let json {
            if let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] {
                if let raw = object["roots"] {
                    if let list = raw as? [Any] {
                        rootPaths = list.compactMap { $0 as? String }.filter { !$0.isEmpty }
                    } else {
                        warnings.append("companies.json: roots precisa ser uma lista")
                    }
                }
                globalAllow = Self.parseNames(object["env_allow"], label: "env_allow", warnings: &warnings)
                if let raw = object["companies"] {
                    if let list = raw as? [Any] {
                        for (index, item) in list.enumerated() {
                            rules += Self.parseCompany(item, position: index + 1, palette: palette,
                                                fallbackColor: fallbackColor, canonicalize: canonicalize,
                                                warnings: &warnings)
                        }
                    } else {
                        warnings.append("companies.json: companies precisa ser uma lista")
                    }
                }
            } else {
                warnings.append("companies.json invalido: valendo a deteccao automatica")
            }
        }

        var roots: [[String]] = []
        for path in rootPaths {
            let components = PathTools.components(canonicalize(path))
            if components.isEmpty {
                warnings.append("companies.json: a raiz do disco nao pode ser uma root")
            } else {
                roots.append(components)
            }
        }
        // Um path igual a uma root, ou acima dela, engole as pastas das outras empresas:
        // o `env_allow` dessa empresa chegaria aos agentes de todas. A regra segue valendo; fica o aviso.
        for rule in rules where roots.contains(where: { PathTools.hasPrefix($0, rule.prefix) }) {
            let warning = "companies.json: path da empresa \(rule.position) cobre uma root inteira"
            if !warnings.contains(warning) { warnings.append(warning) }
        }
        self.rules = rules
        self.roots = roots
        self.globalEnvAllow = globalAllow
        self.warnings = warnings
    }

    /// As `roots` e os `paths` declarados, como caminhos. Servem ao catálogo de projetos.
    var rootPaths: [String] { roots.map { "/" + $0.joined(separator: "/") } }
    var declaredPaths: [String] { rules.map { "/" + $0.prefix.joined(separator: "/") } }

    /// `canonicalPath` precisa ter passado pela mesma `canonicalize` do init.
    public func resolve(canonicalPath: String) -> Company {
        let components = PathTools.components(canonicalPath)
        var best: Rule?
        for rule in rules where PathTools.hasPrefix(components, rule.prefix) {
            if rule.prefix.count > (best?.prefix.count ?? -1) { best = rule }
        }
        if let best { return best.company }

        var bestRoot: [String]?
        for root in roots where components.count > root.count && PathTools.hasPrefix(components, root) {
            if root.count > (bestRoot?.count ?? -1) { bestRoot = root }
        }
        if let bestRoot {
            let name = components[bestRoot.count]
            return Company(name: name, color: Self.color(for: name, palette: palette, fallback: fallbackColor),
                           envAllow: [])
        }
        return Company(name: Self.fallbackName, color: fallbackColor, envAllow: [])
    }

    /// Índice estável (FNV-1a de 32 bits) para escolher a cor de um nome. Não muda entre execuções.
    public static func stableIndex(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in name.precomposedStringWithCanonicalMapping.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }

    /// Cor do N-ésimo agente da mesma empresa.
    public static func tone(_ base: RGB, index: Int) -> RGB {
        let step = ((index % toneCount) + toneCount) % toneCount
        return base.darkened(Double(step) * toneStep)
    }

    private static func color(for name: String, palette: [RGB], fallback: RGB) -> RGB {
        palette.isEmpty ? fallback : palette[stableIndex(name, count: palette.count)]
    }

    private static func parseCompany(_ item: Any, position: Int, palette: [RGB], fallbackColor: RGB,
                              canonicalize: (String) -> String, warnings: inout [String]) -> [Rule] {
        guard let entry = item as? [String: Any],
              let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            warnings.append("companies.json: empresa \(position) sem nome, ignorada")
            return []
        }
        let paths = (entry["paths"] as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        if paths.isEmpty {
            warnings.append("companies.json: empresa \(position) sem paths, ignorada")
            return []
        }
        var color = Self.color(for: name, palette: palette, fallback: fallbackColor)
        if let raw = entry["color"] {
            if let text = raw as? String, let parsed = RGB(hex: text) {
                color = parsed
            } else {
                warnings.append("companies.json: cor invalida na empresa \(position)")
            }
        }
        let allow = parseNames(entry["env_allow"], label: "env_allow da empresa \(position)", warnings: &warnings)
        let company = Company(name: name, color: color, envAllow: allow)
        var rules: [Rule] = []
        for path in paths {
            let components = PathTools.components(canonicalize(path))
            if components.isEmpty {
                warnings.append("companies.json: a raiz do disco nao pode ser path da empresa \(position)")
            } else {
                rules.append(Rule(prefix: components, company: company, position: position))
            }
        }
        return rules
    }

    private static func parseNames(_ raw: Any?, label: String, warnings: inout [String]) -> [String] {
        guard let raw else { return [] }
        guard let list = raw as? [Any] else {
            warnings.append("companies.json: \(label) precisa ser uma lista")
            return []
        }
        var names: [String] = []
        for item in list {
            guard let name = item as? String, EnvPolicy.isValidName(name) else {
                warnings.append("companies.json: nome de variavel invalido em \(label)")
                continue
            }
            if EnvPolicy.parentSessionVars.contains(name) {
                warnings.append("companies.json: \(name) nunca e liberada")
                continue
            }
            names.append(name)
        }
        return names
    }
}
