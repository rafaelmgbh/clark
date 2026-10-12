import ClarkCore
import Foundation
import XCTest
@testable import Clark

/// Repositório git de verdade numa pasta do teste. Sem git na máquina, o teste é pulado.
struct TestRepository {
    let path: String
    let home: String
    let git: String

    /// Ambiente com que os agentes do teste nascem: sem nada do git de quem roda os testes.
    var agentEnvironment: [String: String] { ["PATH": "/usr/bin:/bin", "HOME": home] }

    init(at path: String, home: String) throws {
        guard let git = GitLocator.find(path: ProcessInfo.processInfo.environment["PATH"]) else {
            throw XCTSkip("git não encontrado nesta máquina")
        }
        self.path = path
        self.home = home
        self.git = git
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try run("init", "-q")
    }

    /// Roda o git do jeito comum, sem as proteções do `GitRunner`.
    @discardableResult
    func run(_ arguments: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        var environment = agentEnvironment
        for role in ["AUTHOR", "COMMITTER"] {
            environment["GIT_\(role)_NAME"] = "Teste"
            environment["GIT_\(role)_EMAIL"] = "teste@example.com"
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func write(_ relative: String, _ content: String) {
        write(relative, Data(content.utf8))
    }

    func write(_ relative: String, _ content: Data) {
        let full = path + "/" + relative
        try? FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: full, contents: content)
    }

    func commitAll(file: StaticString = #filePath, line: UInt = #line) throws {
        try run("add", "-A")
        XCTAssertEqual(try run("commit", "-q", "-m", "base"), 0, "o commit de preparo falhou", file: file, line: line)
    }

    func runner(environment: [String: String]? = nil, timeout: TimeInterval = 10) -> GitRunner {
        GitRunner(executable: git, agentEnvironment: environment ?? agentEnvironment, timeout: timeout)
    }
}
