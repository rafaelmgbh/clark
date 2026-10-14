import Foundation

/// Conversa que o Claude Code mandou para segundo plano. O `claude` do agente sai e a conversa segue
/// num processo próprio, com outro id, que se reabre num terminal com `claude attach <job>`.
///
/// Como o `SessionReport`, depende de detalhes internos do Claude Code: o anúncio que ele escreve ao
/// sair e o arquivo `<config>/sessions/<pid>.json` do processo em segundo plano, com `kind: "bg"`.
/// Se eles mudarem, o agente volta a guardar a conversa de antes de ir para segundo plano.
public struct BackgroundSession: Equatable, Sendable {
    /// O id curto que o `claude attach` recebe.
    public var jobID: String
    /// A conversa que o processo em segundo plano segue.
    public var sessionID: String

    private static let announcement = "backgrounded \u{B7} "

    /// O job anunciado pelo `claude` ao mandar a conversa para segundo plano (`backgrounded · <job>`).
    /// Vale o último anúncio da tela.
    public static func handoff(in lines: [String]) -> String? {
        for line in lines.reversed() {
            let text = line.drop { $0 == " " }
            guard text.hasPrefix(announcement) else { continue }
            let job = text.dropFirst(announcement.count).prefix { $0 != " " }
            return isValidJobID(String(job)) ? String(job) : nil
        }
        return nil
    }

    /// O job vivo de id `jobID`.
    public static func live(configDir: String, jobID: String,
                            isAlive: (Int32) -> Bool = processIsAlive) -> BackgroundSession? {
        find(configDir: configDir, isAlive: isAlive) { $0.jobID == jobID }
    }

    /// O job vivo que segue a conversa `sessionID`.
    public static func live(configDir: String, sessionID: String,
                            isAlive: (Int32) -> Bool = processIsAlive) -> BackgroundSession? {
        guard let sessionID = SessionLocator.normalized(sessionID) else { return nil }
        return find(configDir: configDir, isAlive: isAlive) { $0.sessionID == sessionID }
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Letras, números, `-` e `_`, começando por letra ou número: o id vai para o argv do `claude`,
    /// e um `-` na frente viraria flag.
    static func isValidJobID(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, text.unicodeScalars.count <= 64,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return text.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

    private static func find(configDir: String, isAlive: (Int32) -> Bool,
                             where matches: (BackgroundSession) -> Bool) -> BackgroundSession? {
        let directory = configDir + "/sessions"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        for name in names.sorted() {
            guard name.hasSuffix(".json"), let pid = Int32(name.dropLast(5)), pid > 0,
                  let data = SessionReport.contents(of: "\(directory)/\(name)"),
                  let session = SessionReport.object(json: data, pid: pid),
                  session["kind"] as? String == "bg",
                  let jobID = session["jobId"] as? String, isValidJobID(jobID),
                  let sessionID = SessionLocator.normalized(session["sessionId"] as? String) else { continue }
            let found = BackgroundSession(jobID: jobID, sessionID: sessionID)
            if matches(found), isAlive(pid) { return found }
        }
        return nil
    }
}
