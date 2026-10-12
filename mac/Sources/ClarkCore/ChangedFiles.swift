import Foundation

/// A lista de arquivos alterados que abre ao lado do terminal: os arquivos do diff, agrupados pelo que
/// aconteceu com cada um.
public enum ChangedFiles {
    public enum Row: Equatable, Sendable {
        /// Título do grupo, com quantos arquivos ele tem.
        case group(DiffStatus, count: Int)
        case file(DiffFile)
    }

    /// Ordem dos grupos: primeiro o que já existia e mudou, por último o que o git ainda não acompanha.
    public static let order: [DiffStatus] = [.modified, .added, .deleted, .untracked]

    /// Só ASCII em maiúsculas, que é o que a fonte de pixels tem.
    public static func title(_ status: DiffStatus) -> String {
        switch status {
        case .modified: return "MODIFICADOS"
        case .added: return "NOVOS"
        case .deleted: return "REMOVIDOS"
        case .untracked: return "NAO RASTREADOS"
        }
    }

    /// Linhas da lista. Dentro do grupo os arquivos ficam na ordem em que chegaram, e grupo vazio não aparece.
    public static func rows(_ files: [DiffFile]) -> [Row] {
        order.flatMap { status -> [Row] in
            let group = files.filter { $0.status == status }
            return group.isEmpty ? [] : [.group(status, count: group.count)] + group.map(Row.file)
        }
    }

    /// Nome do arquivo e a pasta dele dentro do repositório, vazia na raiz. A barra no fim, que o git põe
    /// no repositório aninhado que ele lista como pasta, fica no nome.
    public static func split(_ path: String) -> (name: String, folder: String) {
        let body = path.hasSuffix("/") ? path.dropLast() : Substring(path)
        guard let slash = body.lastIndex(of: "/") else { return (path, "") }
        return (String(path[path.index(after: slash)...]), String(path[..<slash]))
    }
}
