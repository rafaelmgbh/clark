import Foundation

/// Pasta que o menu PROJETO oferece.
public struct ProjectEntry: Equatable, Sendable {
    public let name: String
    public let path: String
    /// Preenchido quando a pasta não é um repositório git e guarda repositórios: ela vira um submenu.
    public let children: [ProjectEntry]

    public init(name: String, path: String, children: [ProjectEntry] = []) {
        self.name = name
        self.path = path
        self.children = children
    }
}

/// Uma empresa com as pastas que o menu PROJETO lista.
public struct ProjectGroup: Equatable, Sendable {
    public let name: String
    /// Pastas da empresa: uma na detecção automática, uma por `path` que existe no `companies.json`.
    public let folders: [String]
    public let projects: [ProjectEntry]

    public init(name: String, folders: [String], projects: [ProjectEntry]) {
        self.name = name
        self.folders = folders
        self.projects = projects
    }
}

extension CompanyResolver {
    /// Empresas e projetos que existem no disco agora: as subpastas das `roots` e os `paths` declarados.
    /// Tudo o que aparece numa empresa abre como agente dela; a pasta que `resolve` daria a outra
    /// empresa fica de fora.
    /// - Parameter canonicalize: a mesma função passada ao init.
    public func projectGroups(canonicalize: (String) -> String) -> [ProjectGroup] {
        var byCompany: [String: [(path: String, components: [String])]] = [:]
        var seen: Set<String> = []
        let candidates = rootPaths.flatMap(ProjectCatalog.subfolders) + declaredPaths.filter(PathTools.isDirectory)
        for path in candidates {
            let canonical = canonicalize(path)
            guard seen.insert(canonical).inserted else { continue }
            byCompany[resolve(canonicalPath: canonical).name, default: []]
                .append((path, PathTools.components(canonical)))
        }
        let groups = byCompany.map { name, all in
            // Uma pasta dentro de outra da mesma empresa já aparece como projeto da de fora.
            let folders = all.filter { folder in
                !all.contains { $0.components.count < folder.components.count
                    && PathTools.hasPrefix(folder.components, $0.components) }
            }.map(\.path).sorted(by: ProjectCatalog.inOrder)
            let projects = folders.flatMap(ProjectCatalog.subfolders)
                .compactMap { entry($0, company: name, canonicalize: canonicalize, nested: false) }
                .sorted { first, second in
                    first.name == second.name ? ProjectCatalog.inOrder(first.path, second.path)
                        : ProjectCatalog.inOrder(first.name, second.name)
                }
            return ProjectGroup(name: name, folders: folders, projects: projects)
        }
        return groups.sorted { ProjectCatalog.inOrder($0.name, $1.name) }
    }

    private func entry(_ path: String, company: String, canonicalize: (String) -> String,
                       nested: Bool) -> ProjectEntry? {
        guard resolve(canonicalPath: canonicalize(path)).name == company else { return nil }
        var children: [ProjectEntry] = []
        // Um nível só: a pasta de dentro de uma pasta de repositórios nunca abre outro submenu.
        if !nested, !ProjectCatalog.isRepository(path) {
            let inside = ProjectCatalog.subfolders(of: path)
            if inside.contains(where: ProjectCatalog.isRepository) {
                children = inside.compactMap { entry($0, company: company, canonicalize: canonicalize, nested: true) }
            }
        }
        return ProjectEntry(name: (path as NSString).lastPathComponent, path: path, children: children)
    }
}

enum ProjectCatalog {
    /// Subpastas visíveis, com o caminho inteiro, na ordem do Finder. Pasta que não dá para ler devolve vazio.
    static func subfolders(of path: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted(by: inOrder)
            .map { path + "/" + $0 }.filter(PathTools.isDirectory)
    }

    /// Tem `.git`: pasta num clone, arquivo numa worktree.
    static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    /// Ordem do Finder: sem diferenciar maiúsculas e com `v2` antes de `v10`.
    static func inOrder(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }
}
