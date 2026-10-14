import XCTest
@testable import ClarkCore

/// Ao fechar, o CLARK deixa rodando o `update.sh` que vem dentro dele, para que a próxima abertura
/// já seja a do último commit do repo de onde ele foi compilado.
final class SelfUpdateTests: XCTestCase {
    private let temp = TemporaryDirectory()
    private let bundle = "/Users/eu/Applications/Clark.app"
    private let script = "/Users/eu/Applications/Clark.app/Contents/Resources/update.sh"
    private let info: [String: Any] = ["ClarkSourceRepo": "/Users/eu/clark", "ClarkSourceTree": "abc"]

    private func command(info: [String: Any]? = nil, environment: [String: String] = [:],
                         executable: Bool = true) -> [String]? {
        SelfUpdate.command(bundlePath: bundle, info: info ?? self.info, pid: 4242,
                           environment: environment) { $0 == self.script && executable }
    }

    func testAppBuiltFromARepoLeavesTheUpdateRunning() {
        XCTAssertEqual(command(), [script, "--app", bundle, "--after", "4242"])
    }

    func testAppBuiltOutsideARepoHasNothingToUpdateFrom() {
        XCTAssertNil(command(info: [:]))
        XCTAssertNil(command(info: ["ClarkSourceRepo": ""]))
        XCTAssertNil(command(info: ["ClarkSourceRepo": 7]))
    }

    func testAppWithoutTheScriptDoesNotUpdate() {
        XCTAssertNil(command(executable: false))
    }

    func testUpdateCanBeTurnedOff() {
        XCTAssertNil(command(environment: ["CLARK_NO_UPDATE": "1"]))
        XCTAssertNotNil(command(environment: ["CLARK_NO_UPDATE": ""]))
    }

    // MARK: o processo solto

    private func spawn(_ shell: String, log: String) -> pid_t? {
        SelfUpdate.spawnDetached(arguments: ["/bin/sh", "-c", shell], log: log)
    }

    private func wait(for pid: pid_t) {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    func testDetachedProcessWritesToTheLog() throws {
        let log = temp.path + "/update.log"
        try "velho\n".write(toFile: log, atomically: true, encoding: .utf8)
        let pid = try XCTUnwrap(spawn("echo saiu; echo erro >&2", log: log))
        wait(for: pid)
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "saiu\nerro\n", "o log recomeça a cada vez")
    }

    /// Numa sessão própria, o processo sobrevive ao app e não leva o sinal de quem fecha o grupo do app.
    func testDetachedProcessRunsInItsOwnSession() throws {
        let log = temp.path + "/update.log"
        let pid = try XCTUnwrap(spawn("sleep 5", log: log))
        defer { kill(pid, SIGKILL); wait(for: pid) }
        XCTAssertEqual(getsid(pid), pid)
    }

    /// Os terminais dos agentes ficam abertos no app: herdados, o `claude` de cada agente seguiria
    /// vivo enquanto a atualização roda, sem receber o aviso de que o terminal fechou.
    func testDetachedProcessDoesNotInheritTheAppFiles() throws {
        let log = temp.path + "/update.log"
        let open = Darwin.open(temp.path + "/aberto", O_WRONLY | O_CREAT, 0o644)
        XCTAssertGreaterThan(open, 2)
        defer { close(open) }
        let pid = try XCTUnwrap(spawn("if [ -e /dev/fd/\(open) ]; then echo herdou; else echo limpo; fi", log: log))
        wait(for: pid)
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "limpo\n")
    }

    func testMissingProgramIsNotStarted() {
        XCTAssertNil(SelfUpdate.spawnDetached(arguments: [temp.path + "/nao-existe"], log: temp.path + "/update.log"))
        XCTAssertNil(SelfUpdate.spawnDetached(arguments: [], log: temp.path + "/update.log"))
    }
}
