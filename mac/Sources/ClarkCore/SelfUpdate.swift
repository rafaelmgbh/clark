import Darwin
import Foundation

/// Atualização do app instalado para o último commit do repo de onde ele foi compilado.
///
/// O trabalho é do `update.sh`, que o `build.sh` põe dentro do app junto com o caminho do repo e a
/// versão de `mac/` compilada (`ClarkSourceRepo` e `ClarkSourceTree` no `Info.plist`). O atalho
/// `clark` chama o script antes de abrir o app; o app, ao fechar, deixa o script rodando: ele espera
/// o app sair, compila o `HEAD` e instala, e a próxima abertura já é a nova.
public enum SelfUpdate {
    /// O que rodar ao fechar. nil quando o app não veio de um repo, não tem o script ou a atualização
    /// está desligada (`CLARK_NO_UPDATE`).
    public static func command(bundlePath: String, info: [String: Any], pid: Int32,
                               environment: [String: String],
                               isExecutable: (String) -> Bool) -> [String]? {
        guard environment["CLARK_NO_UPDATE"]?.isEmpty ?? true,
              let repo = info["ClarkSourceRepo"] as? String, !repo.isEmpty else { return nil }
        let script = bundlePath + "/Contents/Resources/update.sh"
        guard isExecutable(script) else { return nil }
        return [script, "--app", bundlePath, "--after", String(pid)]
    }

    /// Roda `arguments` solto do app: em sessão própria, com a entrada vazia, a saída em `log`
    /// (recomeçado) e sem herdar nenhum outro arquivo aberto, em especial os terminais dos agentes.
    /// Devolve o pid, ou nil quando o programa não abriu.
    @discardableResult
    public static func spawnDetached(arguments: [String], log: String) -> pid_t? {
        guard let program = arguments.first else { return nil }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        let argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, program, &actions, &attributes, argv, environ)
        return status == 0 ? pid : nil
    }
}
