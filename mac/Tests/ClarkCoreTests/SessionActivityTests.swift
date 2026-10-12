import XCTest
@testable import ClarkCore

final class SessionActivityTests: XCTestCase {
    private let temp = TemporaryDirectory()
    private let pid: Int32 = 4242
    /// Instante em que o processo do agente abriu, bem antes dos arquivos destes testes.
    private let spawned = Date().timeIntervalSince1970 - 60

    /// Grava o arquivo da sessão como o Claude Code grava: um objeto por processo.
    @discardableResult
    private func session(_ body: String, pid filePid: Int32? = nil) -> String {
        temp.write("sessions/\(filePid ?? pid).json", body)
    }

    private func read(since: Double? = nil) -> SessionActivity? {
        SessionActivity.read(configDir: temp.path, pid: pid, since: since ?? spawned)
    }

    func testSessionFileIsNamedAfterTheProcess() {
        XCTAssertEqual(SessionActivity.path(configDir: "/home/.claude", pid: 4242), "/home/.claude/sessions/4242.json")
    }

    func testReadsWhatTheSessionIsDoing() {
        session(#"{"pid": 4242, "sessionId": "abc", "kind": "interactive", "status": "shell", "statusUpdatedAt": 1}"#)
        XCTAssertEqual(read(), .shell)
        session(#"{"pid": 4242, "status": "busy"}"#)
        XCTAssertEqual(read(), .busy)
        session(#"{"pid": 4242, "status": "idle"}"#)
        XCTAssertEqual(read(), .idle)
    }

    func testStatusThatClarkDoesNotKnowIsNoAnswer() {
        for body in [#"{"pid": 4242, "status": "napping"}"#, #"{"pid": 4242, "status": 3}"#, #"{"pid": 4242}"#,
                     #"["shell"]"#, "shell", ""] {
            session(body)
            XCTAssertNil(read(), body)
        }
    }

    func testFileThatNamesAnotherProcessIsIgnored() {
        session(#"{"pid": 7, "status": "shell"}"#)
        XCTAssertNil(read())
        session(#"{"pid": "4242", "status": "shell"}"#)
        XCTAssertNil(read())
        session(#"{"status": "shell"}"#)
        XCTAssertNil(read())
    }

    func testFileWrittenBeforeTheProcessStartedIsALeftover() throws {
        let path = session(#"{"pid": 4242, "status": "shell"}"#)
        let written = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
        XCTAssertNil(read(since: written.timeIntervalSince1970 + 1))
        XCTAssertEqual(read(since: written.timeIntervalSince1970 - 1), .shell)
    }

    func testMissingFileIsNoAnswer() {
        XCTAssertNil(read())
        session(#"{"pid": 4243, "status": "shell"}"#, pid: 4243)
        XCTAssertNil(read())
    }

    func testFolderInThePlaceOfTheFileIsNoAnswer() {
        temp.makeDirectory("sessions/4242.json")
        XCTAssertNil(read())
    }

    /// Abrir um pipe sem ninguém do outro lado prende quem abre: o CLARK não chega a abrir.
    /// A leitura roda fora da linha principal para o teste falhar, e não travar, se ela abrir.
    func testPipeInThePlaceOfTheFileDoesNotHoldTheApp() {
        temp.makeDirectory("sessions")
        let pipe = temp.path + "/sessions/4242.json"
        XCTAssertEqual(mkfifo(pipe, 0o644), 0)

        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        let configDir = temp.path, pid = pid, since = spawned
        DispatchQueue.global().async {
            answer.value = SessionActivity.read(configDir: configDir, pid: pid, since: since)
            done.signal()
        }
        if done.wait(timeout: .now() + 2) == .timedOut {
            XCTFail("a leitura ficou presa abrindo o pipe")
            // Abrir e fechar a outra ponta dá fim de arquivo a quem ficou esperando.
            close(open(pipe, O_WRONLY | O_NONBLOCK))
            _ = done.wait(timeout: .now() + 2)
        }
        XCTAssertNil(answer.value)
    }

    func testHugeFileIsNotRead() {
        let padding = String(repeating: " ", count: SessionActivity.maxBytes)
        session(#"{"pid": 4242, "status": "shell"}"# + padding)
        XCTAssertNil(read())
        session(#"{"pid": 4242, "status": "shell"}"# + String(repeating: " ", count: 1024))
        XCTAssertEqual(read(), .shell)
    }
}

/// Resposta de uma leitura feita em outra linha de execução; o semáforo do teste ordena o acesso.
private final class Answer: @unchecked Sendable {
    var value: SessionActivity? = .shell
}
