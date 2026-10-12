import Foundation

/// O que o Claude Code diz que uma sessão está fazendo, em `<config>/sessions/<pid>.json`.
///
/// O terminal não conta tudo: com o turno encerrado e um comando rodando em segundo plano, a tela
/// fica parada como a de um agente ocioso. O arquivo é um detalhe interno do Claude Code: se ele
/// sumir ou mudar de formato, o CLARK volta a decidir só pela saída do terminal.
public enum SessionActivity: String, Equatable, Sendable {
    case busy
    case idle
    /// Turno encerrado, com comando em segundo plano ainda rodando.
    case shell

    /// Teto do que é lido do arquivo, que tem menos de 1 KiB.
    public static let maxBytes = 64 * 1024

    public static func path(configDir: String, pid: Int32) -> String {
        "\(configDir)/sessions/\(pid).json"
    }

    /// Estado da sessão do processo `pid`. nil se o arquivo não existe, não é o esperado ou sobrou de
    /// um processo antigo que tinha o mesmo número.
    /// - Parameter since: quando o processo abriu, em segundos desde 1970.
    public static func read(configDir: String, pid: Int32, since: Double) -> SessionActivity? {
        let path = path(configDir: configDir, pid: pid)
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        guard modified >= since, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return SessionActivity(json: data, pid: pid)
    }

    init?(json data: Data, pid: Int32) {
        guard let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              session["pid"] as? Int == Int(pid), let status = session["status"] as? String else { return nil }
        self.init(rawValue: status)
    }
}
