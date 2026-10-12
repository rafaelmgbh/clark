import ClarkCore
import XCTest
@testable import Clark

final class ShellEnvironmentTests: XCTestCase {
    private let temp = TemporaryDirectory()
    private let base = ["PATH": "/usr/bin:/bin", "CLARK_TESTE": "valor com espaço"]

    /// Um "shell" que é um script: recebe `-l -i -c <comando>` como o shell de verdade.
    private func fakeShell(_ body: String) -> String {
        temp.write("shell-\(UUID().uuidString)", "#!/bin/sh\n" + body + "\n", permissions: 0o755)
    }

    func testCapturesTheEnvironmentOfTheShell() {
        let capture = ShellEnvironment.capture(shell: "/bin/sh", processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
        XCTAssertNotNil(capture.variables["PATH"])
        XCTAssertNil(capture.variables["SHLVL"], "variável que só descreve o shell da captura não passa")
    }

    func testVariablesSetByTheProfileAreCaptured() {
        let shell = fakeShell("export SO_DO_PERFIL=sim\neval \"$4\"")
        let capture = ShellEnvironment.capture(shell: shell, processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertEqual(capture.variables["SO_DO_PERFIL"], "sim")
    }

    func testNoiseBeforeTheMarkerIsIgnored() {
        let shell = fakeShell("echo 'bem-vindo ao shell'\necho 'FALSA=1'\neval \"$4\"")
        let capture = ShellEnvironment.capture(shell: shell, processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertNil(capture.variables["FALSA"])
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
    }

    func testMissingShellFallsBack() {
        let capture = ShellEnvironment.capture(shell: temp.path + "/nao-existe", processEnvironment: base)
        XCTAssertFalse(capture.captured)
        XCTAssertEqual(capture.variables["PATH"], ShellEnvParser.defaultPath)
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
    }

    func testOutputWithoutTheMarkerFallsBack() {
        let capture = ShellEnvironment.capture(shell: fakeShell("echo oi"), processEnvironment: base)
        XCTAssertFalse(capture.captured)
        XCTAssertEqual(capture.variables["PATH"], ShellEnvParser.defaultPath)
    }

    func testShellThatNeverExitsTimesOut() {
        let started = Date()
        let capture = ShellEnvironment.capture(shell: fakeShell("exec sleep 30"), processEnvironment: base,
                                               timeout: 0.5)
        XCTAssertFalse(capture.captured)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testBackgroundChildHoldingThePipeDoesNotBlock() {
        // O `sleep` herda a saída do shell e segura o pipe aberto depois que o shell sai.
        let started = Date()
        let capture = ShellEnvironment.capture(shell: fakeShell("sleep 4 &\neval \"$4\""), processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    // MARK: o que o rc devolve

    func testSecretExportedByTheShellRcIsReported() {
        // O agente nasce sem a variável, mas o rc lido por todo `$SHELL -c` a exporta de novo.
        let shell = fakeShell("export ACME_API_KEY=segredo-acme\nexport SO_DO_RC=sim\neval \"$2\"")
        // O que o agente não recebe não conta como devolvido: o `GITHUB_TOKEN` sai antes da sonda.
        let environment = base.merging(["GITHUB_TOKEN": "segredo"]) { $1 }
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: shell, environment: environment),
                       ["ACME_API_KEY"])
    }

    func testZshenvIsReadByEveryZshCommandAndZshrcIsNot() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/bin/zsh"), "sem zsh")
        temp.write("home/.zshenv", "export ACME_API_KEY=segredo-acme\n")
        temp.write("home/.zshrc", "export BETA_API_KEY=segredo-beta\n")
        let environment = ["PATH": "/usr/bin:/bin", "HOME": temp.path + "/home"]
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: "/bin/zsh", environment: environment),
                       ["ACME_API_KEY"])
    }

    func testShellThatRestoresNothingOrFailsReportsNothing() {
        let environment = base.merging(["GITHUB_TOKEN": "segredo"]) { $1 }
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: "/bin/sh", environment: environment), [])
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: temp.path + "/nao-existe",
                                                               environment: environment), [])
    }

    func testRestoredSecretsWarningListsNamesAndSkipsTheGlobalAllow() {
        XCTAssertNil(ShellEnvironment.restoredSecretsWarning([], globalAllow: []))
        XCTAssertNil(ShellEnvironment.restoredSecretsWarning(["GH_TOKEN"], globalAllow: ["GH_TOKEN"]),
                     "o `env_allow` do topo já libera a variável para todos os agentes")
        XCTAssertEqual(ShellEnvironment.restoredSecretsWarning(["ACME_API_KEY", "GH_TOKEN"], globalAllow: ["GH_TOKEN"]),
                       "rc do shell devolve variaveis filtradas: ACME_API_KEY")
        XCTAssertEqual(
            ShellEnvironment.restoredSecretsWarning(["A_KEY", "B_KEY", "C_KEY", "D_KEY", "E_KEY"], globalAllow: []),
            "rc do shell devolve variaveis filtradas: A_KEY, B_KEY, C_KEY (+2)")
    }

    func testShellPathAcceptsOnlyAbsoluteExecutables() {
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/bin/sh"]), "/bin/sh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: [:]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "zsh"]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/nao/existe/zsh"]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/etc/hosts"]), "/bin/zsh",
                       "arquivo sem permissão de execução não é shell")
    }
}
