import ClarkCore
import Foundation

/// Roda um programa e devolve o que ele escreveu, com tempo e tamanho limitados.
enum Subprocess {
    struct Result {
        let status: Int32
        let output: Data
        /// A saída passou do limite: o que veio depois foi jogado fora e o processo, encerrado.
        let truncated: Bool
    }

    /// nil: o programa não abriu ou não saiu a tempo. Bloqueia até `timeout` segundos: chamar fora
    /// da thread principal.
    static func run(executable: String, arguments: [String], environment: [String: String], directory: String,
                    timeout: TimeInterval, maxBytes: Int) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }

        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let deadline = DispatchTime.now() + timeout
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var truncated = false
        var exited = false
        // Um neto do processo pode segurar o pipe aberto: depois da saída, a leitura só espera um pouco.
        var drainUntil: DispatchTime?
        while true {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            if poll(&poller, 1, 20) > 0 {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    let room = maxBytes - output.count
                    output.append(contentsOf: buffer[0..<min(count, room)])
                    if count > room {
                        truncated = true
                        break
                    }
                    continue
                }
                if count == 0 || (errno != EINTR && errno != EAGAIN) { break }
            }
            if !exited, finished.wait(timeout: .now()) == .success {
                exited = true
                drainUntil = .now() + 0.3
            }
            if let drainUntil, DispatchTime.now() > drainUntil { break }
            if DispatchTime.now() > deadline { break }
        }
        if !exited && !truncated { exited = finished.wait(timeout: deadline) == .success }
        guard exited else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            return truncated ? Result(status: -1, output: output, truncated: true) : nil
        }
        return Result(status: process.terminationStatus, output: output, truncated: truncated)
    }
}

/// O que mudou na pasta de um agente desde o último commit.
struct RepoChanges: Equatable {
    /// Raiz do repositório. Os caminhos dos arquivos são relativos a ela.
    var root: String
    /// Contra o que o diff é feito: `HEAD`, ou a árvore vazia no repositório sem commit.
    var base: String
    var files: [DiffFile]
    /// A lista passou do limite de tamanho e está incompleta.
    var truncated: Bool

    var summary: DiffSummary { DiffSummary(files) }
}

enum DiffState: Equatable {
    /// Ainda não leu.
    case unknown
    case noGit
    case notRepository
    /// O git não abriu ou não respondeu a tempo.
    case failed
    case changes(RepoChanges)
}

/// Diff de um arquivo, em texto.
struct FileDiff: Equatable {
    var text: String
    /// O diff passou do limite e foi cortado.
    var truncated: Bool
}

/// Roda o git só para ler, na pasta de um agente. O repositório pode ser de terceiros: o que o config
/// dele consegue mandar executar fica desligado, e o processo nasce com o ambiente do próprio agente,
/// que já não tem os segredos das outras empresas.
struct GitRunner {
    /// Valem para todo comando: sem paginador, sem travas, caminho ao pé da letra, e sem monitor de
    /// arquivos nem ganchos, que são programas apontados pelo config do repositório.
    static let globalFlags = [
        "--no-pager", "--no-optional-locks", "--literal-pathspecs",
        "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never",
        "-c", "core.quotePath=false",
    ]
    /// Sem programa externo de diff nem conversor de texto, que também vêm do config do repositório.
    static let diffFlags = ["--no-renames", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=all"]
    static let listLimit = 4 * 1024 * 1024
    static let countedFileLimit = 1024 * 1024

    let executable: String
    let environment: [String: String]
    var timeout: TimeInterval
    /// Tamanho máximo do diff de um arquivo.
    var diffLimit = 1024 * 1024
    /// Quantos arquivos não rastreados têm as linhas contadas.
    var countedUntracked = 200

    init(executable: String, agentEnvironment: [String: String], timeout: TimeInterval = 10) {
        self.executable = executable
        environment = Self.environment(from: agentEnvironment)
        self.timeout = timeout
    }

    /// O ambiente do agente sem as variáveis do git, que trocariam o repositório, o config ou o programa
    /// de diff, e com as que impedem o git de perguntar, travar ou buscar na rede.
    static func environment(from agent: [String: String]) -> [String: String] {
        var environment = agent.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        return environment
    }

    private func git(_ arguments: [String], in directory: String, maxBytes: Int = listLimit) -> Subprocess.Result? {
        Subprocess.run(executable: executable, arguments: Self.globalFlags + arguments, environment: environment,
                       directory: directory, timeout: timeout, maxBytes: maxBytes)
    }

    private func line(_ result: Subprocess.Result) -> String {
        String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// Lista o que mudou no repositório inteiro da pasta, rastreado ou não. Bloqueia: chamar fora da
    /// thread principal.
    func changes(in directory: String) -> DiffState {
        guard let top = git(["rev-parse", "--show-toplevel"], in: directory) else { return .failed }
        let root = line(top)
        guard top.status == 0, root.hasPrefix("/") else { return .notRepository }

        guard let head = git(["rev-parse", "--verify", "--quiet", "HEAD"], in: root) else { return .failed }
        var base = "HEAD"
        if head.status != 0 {
            // Repositório sem commit: o diff é contra a árvore vazia, e tudo aparece como novo.
            let empty = git(["hash-object", "-t", "tree", "/dev/null"], in: root).map(line) ?? ""
            base = empty.isEmpty ? GitDiff.emptyTree : empty
        }

        guard let tracked = git(["diff", "--raw", "--numstat", "-z"] + Self.diffFlags + [base, "--"], in: root),
              let others = git(["ls-files", "--others", "--exclude-standard", "-z"], in: root) else { return .failed }
        let untracked = GitDiff.parseUntracked(others.output).enumerated().map { index, path in
            let lines = index < countedUntracked ? Self.lineCount(ofFile: root + "/" + path) : nil
            return DiffFile(path: path, status: .untracked, added: lines, removed: lines == nil ? nil : 0)
        }
        return .changes(RepoChanges(root: root, base: base,
                                    files: GitDiff.merged(GitDiff.parseChanges(tracked.output), untracked: untracked),
                                    truncated: tracked.truncated || others.truncated))
    }

    /// Linhas de um arquivo comum e pequeno. Link não é seguido: o destino pode estar fora do repositório.
    private static func lineCount(ofFile path: String) -> Int? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= countedFileLimit,
              let content = FileManager.default.contents(atPath: path) else { return nil }
        return GitDiff.lineCount(content)
    }

    /// Diff de um arquivo da lista. nil: o git não abriu ou não respondeu a tempo. Bloqueia: chamar fora
    /// da thread principal.
    func diff(of file: DiffFile, in changes: RepoChanges) -> FileDiff? {
        // O não rastreado não está na base: o diff é do arquivo contra o nada.
        let arguments = file.status == .untracked
            ? ["diff"] + Self.diffFlags + ["--no-index", "--", "/dev/null", file.path]
            : ["diff"] + Self.diffFlags + [changes.base, "--", file.path]
        guard let result = git(arguments, in: changes.root, maxBytes: diffLimit) else { return nil }
        var output = result.output
        // Cortada no limite, a última linha veio pela metade, talvez no meio de um caractere: ela sai.
        if result.truncated, let newline = output.lastIndex(of: UInt8(ascii: "\n")) {
            output = output.prefix(through: newline)
        }
        return FileDiff(text: String(decoding: output, as: UTF8.self), truncated: result.truncated)
    }
}
