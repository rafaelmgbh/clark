import Foundation

/// O que o Claude Code diz que uma sessão está fazendo.
///
/// O terminal não conta tudo: com o turno encerrado e um comando rodando em segundo plano, a tela
/// fica parada como a de um agente ocioso.
public enum SessionActivity: String, Equatable, Sendable {
    case busy
    case idle
    /// Turno encerrado, com comando em segundo plano ainda rodando.
    case shell
}

/// O que o CLARK tira de `<config>/sessions/<pid>.json`, o arquivo em que o Claude Code descreve a
/// sessão de um processo.
///
/// O arquivo é um detalhe interno do Claude Code: se ele sumir ou mudar de formato, o CLARK volta a
/// decidir o estado só pela saída do terminal e deixa de avisar do controle remoto.
public struct SessionReport: Equatable, Sendable {
    /// nil: o `status` gravado não é um que o CLARK conheça.
    public var activity: SessionActivity?
    /// O controle remoto (`/remote-control`) está ligado e a conversa pode seguir do celular ou do
    /// navegador. Enquanto ele dura, o arquivo guarda o nome da sessão remota em `bridgeSessionId`;
    /// ao desligar, o Claude Code grava `null` no lugar.
    public var remoteControl: Bool
    /// A conversa que o processo segue agora. `/clear` e `/resume` trocam a conversa sem trocar o
    /// processo. nil: o arquivo não traz um UUID.
    public var sessionID: String? = nil

    /// Teto do que é lido do arquivo, que tem menos de 1 KiB.
    public static let maxBytes = 64 * 1024

    public static func path(configDir: String, pid: Int32) -> String {
        "\(configDir)/sessions/\(pid).json"
    }

    /// O relato da sessão do processo `pid`. nil se o arquivo não existe, não é o esperado ou sobrou
    /// de um processo antigo que tinha o mesmo número.
    /// - Parameter since: quando o processo abriu, em segundos desde 1970.
    public static func read(configDir: String, pid: Int32, since: Double) -> SessionReport? {
        guard let data = contents(of: path(configDir: configDir, pid: pid), modifiedSince: since) else { return nil }
        return SessionReport(json: data, pid: pid)
    }

    /// O conteúdo de um arquivo comum de até `maxBytes`, gravado a partir de `since`. Uma pasta ou um
    /// pipe no lugar do arquivo não seguram a leitura.
    static func contents(of path: String, modifiedSince since: Double = 0) -> Data? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        guard modified >= since, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
    }

    /// O objeto do arquivo, se ele é da sessão do processo `pid`.
    static func object(json data: Data, pid: Int32) -> [String: Any]? {
        guard let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              session["pid"] as? Int == Int(pid) else { return nil }
        return session
    }
}

extension SessionReport {
    init?(json data: Data, pid: Int32) {
        guard let session = Self.object(json: data, pid: pid) else { return nil }
        activity = (session["status"] as? String).flatMap(SessionActivity.init(rawValue:))
        remoteControl = (session["bridgeSessionId"] as? String).map { !$0.isEmpty } ?? false
        sessionID = SessionLocator.normalized(session["sessionId"] as? String)
    }
}
