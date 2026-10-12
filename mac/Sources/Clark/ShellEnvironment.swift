import ClarkCore
import Foundation

/// Ambiente do shell de login, lido uma vez na abertura do app.
enum ShellEnvironment {
    struct Capture {
        let variables: [String: String]
        /// false: a captura falhou e `variables` é o ambiente do app com o `PATH` padrão.
        let captured: Bool
    }

    static let defaultShell = "/bin/zsh"
    private static let maxOutputBytes = 4 * 1024 * 1024

    /// `SHELL` do ambiente quando é um executável de caminho absoluto; senão `/bin/zsh`.
    static func shellPath(processEnvironment: [String: String]) -> String {
        guard let shell = processEnvironment["SHELL"], shell.hasPrefix("/"),
              PathTools.isExecutableFile(shell) else { return defaultShell }
        return shell
    }

    /// Roda `shell -l -i -c` imprimindo o marcador e `env -0`. Bloqueia até `timeout` segundos:
    /// chamar fora da thread principal.
    static func capture(shell: String, processEnvironment: [String: String],
                        timeout: TimeInterval = 5) -> Capture {
        guard let variables = environment(of: shell, arguments: ["-l", "-i"], startingFrom: processEnvironment,
                                          timeout: timeout) else {
            return Capture(variables: ShellEnvParser.fallback(processEnvironment: processEnvironment),
                           captured: false)
        }
        return Capture(variables: variables, captured: true)
    }

    /// Nomes com cara de segredo que um shell aberto por um agente devolve ao ambiente.
    /// O agente nasce sem eles, mas todo `$SHELL -c` relê o rc do shell (no zsh, o `~/.zshenv`),
    /// e o que o rc exporta volta. A lista sai vazia também quando a sonda falha.
    /// Bloqueia até `timeout` segundos: chamar fora da thread principal.
    static func secretsRestoredByShell(shell: String, environment: [String: String],
                                       timeout: TimeInterval = 3) -> [String] {
        let filtered = environment.filter { !EnvPolicy.isSecret($0.key) }
        guard let seen = self.environment(of: shell, arguments: [], startingFrom: filtered,
                                          timeout: timeout) else { return [] }
        return seen.keys.filter(EnvPolicy.isSecret).sorted()
    }

    /// Aviso da barra para os nomes que o rc devolve. Os do `env_allow` do topo ficam de fora,
    /// porque já valem para todos os agentes. Só nomes, nunca valores.
    static func restoredSecretsWarning(_ names: [String], globalAllow: [String]) -> String? {
        let restored = names.filter { !globalAllow.contains($0) }
        guard !restored.isEmpty else { return nil }
        let more = restored.count > 3 ? " (+\(restored.count - 3))" : ""
        return "rc do shell devolve variaveis filtradas: " + restored.prefix(3).joined(separator: ", ") + more
    }

    /// Roda `shell <arguments> -c` imprimindo o marcador e `env -0` e devolve o ambiente lido.
    /// nil: o shell não abriu, não saiu a tempo ou a saída não tem o marcador.
    private static func environment(of shell: String, arguments: [String],
                                    startingFrom environment: [String: String],
                                    timeout: TimeInterval) -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments + ["-c", ShellEnvParser.command]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let lock = NSLock()
        var output = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock()
            if output.count < maxOutputBytes { output.append(chunk) }
            lock.unlock()
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Espera o shell sair, não o fim do pipe: um processo deixado em segundo plano pelo rc
        // segura o pipe aberto e a leitura até o fim nunca voltaria.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }
        // O que o shell escreveu logo antes de sair ainda pode estar a caminho.
        for _ in 0..<10 {
            lock.lock()
            let snapshot = output
            lock.unlock()
            if let parsed = ShellEnvParser.parse(snapshot) { return parsed }
            usleep(20_000)
        }
        return nil
    }
}
