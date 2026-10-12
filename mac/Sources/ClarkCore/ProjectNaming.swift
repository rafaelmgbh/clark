import Foundation

/// Nome de projeto que o menu, o cabeçalho e o card mostram: o apelido dado pelo usuário
/// ou o nome da pasta arrumado.
public enum ProjectNaming {
    /// Nome do agente aberto na home, fora de qualquer projeto.
    public static let global = "GLOBAL"
    public static let maxNicknameLength = 40

    /// `meu_projeto` -> "Meu Projeto". Só a primeira letra de cada palavra muda: `ERP` e `portalWeb` ficam.
    public static func tidy(_ folder: String) -> String {
        let words = folder.split { $0 == "_" || $0 == "-" || $0.isWhitespace }
        guard !words.isEmpty else { return folder }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Apelido digitado pelo usuário: sem caracteres de controle, espaços juntos, tamanho limitado.
    /// nil quando não sobra nada.
    public static func sanitizedNickname(_ text: String) -> String? {
        let spaced = String(text.unicodeScalars.map { scalar -> Character in
            scalar.properties.isWhitespace ? " " : Character(scalar)
        })
        let visible = spaced.unicodeScalars.filter { $0.properties.generalCategory != .control }
        let words = String(String.UnicodeScalarView(visible)).split(separator: " ")
        let joined = String(words.joined(separator: " ").prefix(maxNicknameLength))
            .trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    /// Os apelidos do `config.json` com a chave no formato que `name` e o catálogo comparam.
    public static func canonical(_ nicknames: [String: String],
                                 canonicalize: (String) -> String) -> [String: String] {
        var result: [String: String] = [:]
        for (path, name) in nicknames where !path.isEmpty { result[canonicalize(path)] = name }
        return result
    }

    /// Pasta que dá o nome ao projeto de `canonicalPath`, e que recebe o apelido digitado no menu do
    /// agente: a própria pasta quando ela tem apelido, o repositório em que está, ou ela mesma.
    /// nil na home, que é sempre o `GLOBAL`.
    /// O apelido de uma pasta comum não passa para as de dentro: ela pode guardar vários projetos.
    /// - Parameters:
    ///   - nicknames: já passados por `canonical`.
    ///   - isRepository: diz se o caminho é a raiz de um repositório git.
    public static func namedPath(canonicalPath: String, canonicalHome: String, nicknames: [String: String],
                                 isRepository: (String) -> Bool) -> String? {
        if canonicalPath == canonicalHome { return nil }
        if nicknames[canonicalPath] != nil { return canonicalPath }
        var components = PathTools.components(canonicalPath)
        while !components.isEmpty {
            let path = "/" + components.joined(separator: "/")
            // A home versionada não dá o nome dela a tudo o que há dentro.
            if path == canonicalHome { break }
            if isRepository(path) { return path }
            components.removeLast()
        }
        return canonicalPath
    }

    /// Onde um agente trabalha, numa linha: `Empresa › Projeto`. O projeto com o nome da empresa não
    /// se repete, e o `GLOBAL` não entra: fora de toda empresa fica só o projeto, e na home, nada.
    public static func place(project: String, company: String, isGlobal: Bool) -> String {
        guard !isGlobal else { return "" }
        let company = company == global ? "" : company
        if project.isEmpty || project.uppercased() == company.uppercased() { return company }
        return company.isEmpty ? project : company + ProjectCatalog.trailSeparator + project
    }

    /// Nome do projeto de uma pasta: `GLOBAL` na home; senão o apelido da pasta de `namedPath`
    /// ou o nome dela arrumado.
    public static func name(canonicalPath: String, canonicalHome: String, nicknames: [String: String],
                            isRepository: (String) -> Bool) -> String {
        guard let path = namedPath(canonicalPath: canonicalPath, canonicalHome: canonicalHome,
                                   nicknames: nicknames, isRepository: isRepository) else { return global }
        if let nickname = nicknames[path] { return nickname }
        return PathTools.components(path).last.map(tidy) ?? "/"
    }
}
