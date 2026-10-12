import Foundation

/// Pasta que o menu PROJETO oferece.
public struct ProjectEntry: Equatable, Sendable {
    /// Apelido dado pelo usuário ou o nome da pasta arrumado.
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Projetos que estão na mesma pasta, abaixo do primeiro nível da empresa.
public struct ProjectSection: Equatable, Sendable {
    /// Caminho da pasta dentro da empresa, com os nomes arrumados: "Sistemas › Erp".
    public let title: String
    public let projects: [ProjectEntry]

    public init(title: String, projects: [ProjectEntry]) {
        self.title = title
        self.projects = projects
    }
}

/// Uma empresa com o que o menu PROJETO lista dela.
public struct ProjectGroup: Equatable, Sendable {
    public let name: String
    /// Pastas da empresa: uma na detecção automática, uma por `path` que existe no `companies.json`.
    /// Vazio no grupo que só junta pastas apelidadas fora de toda empresa.
    public let folders: [String]
    /// Pastas com apelido, a qualquer profundidade. Não se repetem nas outras listas.
    public let nicknamed: [ProjectEntry]
    /// Projetos do primeiro nível da empresa.
    public let projects: [ProjectEntry]
    /// Projetos mais fundos, juntos pela pasta em que estão.
    public let sections: [ProjectSection]
    /// Pastas do primeiro nível que não são projeto.
    public let others: [ProjectEntry]

    public init(name: String, folders: [String], nicknamed: [ProjectEntry] = [], projects: [ProjectEntry] = [],
                sections: [ProjectSection] = [], others: [ProjectEntry] = []) {
        self.name = name
        self.folders = folders
        self.nicknamed = nicknamed
        self.projects = projects
        self.sections = sections
        self.others = others
    }

    /// Sem nada para escolher além das próprias pastas.
    public var isBare: Bool { nicknamed.isEmpty && projects.isEmpty && sections.isEmpty && others.isEmpty }
}

extension CompanyResolver {
    /// Empresas e projetos que existem no disco agora. Projeto é a pasta com repositório git ou com
    /// contexto de IA (`CLAUDE.md`, `AGENTS.md`, `.claude`), procurada até `ProjectCatalog.maxDepth`
    /// níveis abaixo da pasta da empresa; a busca não entra em repositório nem em pasta de dependências.
    /// Tudo o que aparece numa empresa abre como agente dela; a pasta que `resolve` daria a outra
    /// empresa fica de fora.
    /// - Parameters:
    ///   - canonicalize: a mesma função passada ao init.
    ///   - nicknames: caminho -> apelido, como está no `config.json`.
    ///   - maxListings: quantas pastas a busca lê antes de desistir do que está mais fundo.
    public func projectGroups(canonicalize: (String) -> String, nicknames: [String: String] = [:],
                              maxListings: Int = ProjectCatalog.maxListings) -> [ProjectGroup] {
        let nicknames = ProjectNaming.canonical(nicknames, canonicalize: canonicalize)
        var byCompany: [String: [(path: String, canonical: String, components: [String])]] = [:]
        var candidatesSeen: Set<String> = []
        let candidates = rootPaths.flatMap(ProjectCatalog.subfolders) + declaredPaths.filter(PathTools.isDirectory)
        for path in candidates {
            let canonical = canonicalize(path)
            guard candidatesSeen.insert(canonical).inserted else { continue }
            byCompany[resolve(canonicalPath: canonical).name, default: []]
                .append((path, canonical, PathTools.components(canonical)))
        }

        var found: [String: ProjectCatalog.Found] = [:]
        var seen: Set<String> = []
        var queue: [ProjectCatalog.Node] = []
        for name in byCompany.keys.sorted(by: ProjectCatalog.inOrder) {
            let all = byCompany[name] ?? []
            // Uma pasta dentro de outra da mesma empresa já aparece na busca da de fora.
            let folders = all.filter { folder in
                !all.contains { $0.components.count < folder.components.count
                    && PathTools.hasPrefix(folder.components, $0.components) }
            }.sorted { ProjectCatalog.inOrder($0.path, $1.path) }
            found[name, default: ProjectCatalog.Found()].folders = folders.map(\.path)
            for folder in folders {
                seen.insert(folder.canonical)
                // A empresa que é ela mesma um repositório abre inteira: o que há dentro é dela.
                if !ProjectCatalog.isRepository(folder.path) {
                    queue.append(ProjectCatalog.Node(company: name, path: folder.path, canonical: folder.canonical,
                                                     trail: []))
                }
            }
        }

        // Em largura: se a árvore for grande demais, o que fica de fora é o mais fundo, em todas as empresas.
        var next = 0
        while next < queue.count, next < maxListings {
            let node = queue[next]
            next += 1
            for child in ProjectCatalog.children(of: node.path) {
                let folder = child.name
                let path = child.path
                if ProjectCatalog.skipped.contains(folder) { continue }
                // Só o link precisa do disco para dizer onde fica: a pasta comum fica no pai dela.
                let canonical = child.isLink ? canonicalize(path) : ProjectCatalog.join(node.canonical, folder)
                guard resolve(canonicalPath: canonical).name == node.company,
                      seen.insert(canonical).inserted else { continue }
                let level = node.trail.count + 1
                let isRepository = ProjectCatalog.isRepository(path)
                let entry = ProjectEntry(name: ProjectNaming.tidy(folder), path: path)
                if nicknames[canonical] == nil {
                    if isRepository || ProjectCatalog.hasAIContext(path) {
                        if level == 1 {
                            found[node.company]?.projects.append(entry)
                        } else {
                            found[node.company]?.sections[node.trail, default: []].append(entry)
                        }
                    } else if level == 1 {
                        found[node.company]?.others.append(entry)
                    }
                }
                if !isRepository, level < ProjectCatalog.maxDepth {
                    queue.append(ProjectCatalog.Node(company: node.company, path: path, canonical: canonical,
                                                     trail: node.trail + [entry.name]))
                }
            }
        }

        for (path, name) in nicknames where PathTools.isDirectory(path) {
            found[resolve(canonicalPath: path).name, default: ProjectCatalog.Found()].nicknamed
                .append(ProjectEntry(name: name, path: path))
        }

        let groups = found.map { name, group in
            ProjectGroup(name: name, folders: group.folders,
                         nicknamed: group.nicknamed.sorted(by: ProjectCatalog.entriesInOrder),
                         projects: group.projects.sorted(by: ProjectCatalog.entriesInOrder),
                         sections: group.sections.keys.sorted(by: ProjectCatalog.trailsInOrder).map { trail in
                             ProjectSection(title: trail.joined(separator: ProjectCatalog.trailSeparator),
                                            projects: (group.sections[trail] ?? [])
                                                .sorted(by: ProjectCatalog.entriesInOrder))
                         },
                         others: group.others.sorted(by: ProjectCatalog.entriesInOrder))
        }
        // O grupo das pastas soltas vem por último: não é uma empresa.
        return groups.sorted { first, second in
            let firstIsFallback = first.name == Self.fallbackName && first.folders.isEmpty
            let secondIsFallback = second.name == Self.fallbackName && second.folders.isEmpty
            if firstIsFallback != secondIsFallback { return secondIsFallback }
            return ProjectCatalog.inOrder(first.name, second.name)
        }
    }
}

public enum ProjectCatalog {
    /// Níveis abaixo da pasta da empresa em que um projeto ainda é encontrado.
    public static let maxDepth = 4
    /// Pastas lidas numa busca. Uma árvore comum fica bem abaixo disso.
    public static let maxListings = 4000
    static let trailSeparator = " › "
    /// Pastas de dependências e de saída de build: grandes e sem projeto do usuário dentro.
    static let skipped: Set<String> = [
        "node_modules", "vendor", "venv", "dist", "build", "target", "__pycache__", "Pods", "DerivedData",
    ]

    /// O que a busca juntou de uma empresa.
    struct Found {
        var folders: [String] = []
        var nicknamed: [ProjectEntry] = []
        var projects: [ProjectEntry] = []
        /// Chave: os nomes arrumados das pastas entre a empresa e os projetos.
        var sections: [[String]: [ProjectEntry]] = [:]
        var others: [ProjectEntry] = []
    }

    /// Pasta que a busca ainda vai ler.
    struct Node {
        let company: String
        let path: String
        /// O caminho de verdade, sem link no meio.
        let canonical: String
        let trail: [String]
    }

    /// Subpasta de uma pasta lida.
    struct Child {
        let name: String
        let path: String
        /// É link, ou o disco não disse o tipo: o caminho de verdade pode não ser o do pai mais o nome.
        let isLink: Bool
    }

    /// Subpastas visíveis, na ordem do Finder. Pasta que não dá para ler devolve vazio.
    /// O tipo de cada entrada vem da própria listagem; só link (e disco que não informa o tipo) custa
    /// uma consulta a mais. Numa árvore grande, consultar entrada por entrada era o que pesava no menu.
    static func children(of path: String) -> [Child] {
        guard let directory = opendir(path) else { return [] }
        defer { closedir(directory) }
        var children: [Child] = []
        while let entry = readdir(directory) {
            let type = Int32(entry.pointee.d_type)
            guard type == DT_DIR || type == DT_LNK || type == DT_UNKNOWN else { continue }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name.hasPrefix(".") { continue }
            let child = path + "/" + name
            if type != DT_DIR, !PathTools.isDirectory(child) { continue }
            children.append(Child(name: name, path: child, isLink: type != DT_DIR))
        }
        return children.sorted { inOrder($0.name, $1.name) }
    }

    /// Subpastas visíveis, com o caminho inteiro, na ordem do Finder.
    static func subfolders(of path: String) -> [String] {
        children(of: path).map(\.path)
    }

    /// `pasta/nome`, sem dobrar a barra quando a pasta é a raiz do disco.
    static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    /// Tem `.git`: pasta num clone, arquivo numa worktree.
    public static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    /// Tem instruções para um agente de IA: alguém já trabalha com um agente nesta pasta.
    static func hasAIContext(_ path: String) -> Bool {
        ["CLAUDE.md", "AGENTS.md", ".claude"].contains { FileManager.default.fileExists(atPath: path + "/" + $0) }
    }

    /// Ordem do Finder: sem diferenciar maiúsculas e com `v2` antes de `v10`.
    static func inOrder(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    static func entriesInOrder(_ first: ProjectEntry, _ second: ProjectEntry) -> Bool {
        first.name == second.name ? inOrder(first.path, second.path) : inOrder(first.name, second.name)
    }

    /// A pasta de fora antes das de dentro; irmãs na ordem do Finder.
    static func trailsInOrder(_ first: [String], _ second: [String]) -> Bool {
        for (one, other) in zip(first, second) where one != other { return inOrder(one, other) }
        return first.count < second.count
    }
}
