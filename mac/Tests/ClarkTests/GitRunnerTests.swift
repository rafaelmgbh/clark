import ClarkCore
import XCTest
@testable import Clark

/// O `GitRunner` contra o git de verdade, em repositórios temporários.
final class GitRunnerTests: XCTestCase {
    private var temp: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        temp = TemporaryDirectory()
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private func repository(_ name: String = "repo") throws -> TestRepository {
        try TestRepository(at: temp.path + "/" + name, home: temp.makeDirectory("home"))
    }

    private func changes(_ state: DiffState, file: StaticString = #filePath, line: UInt = #line) throws -> RepoChanges {
        guard case .changes(let changes) = state else {
            XCTFail("esperava a lista de mudanças, veio \(state)", file: file, line: line)
            throw XCTSkip("sem lista de mudanças")
        }
        return changes
    }

    // MARK: lista

    func testChangesListTrackedAndUntrackedFilesFromASubfolder() throws {
        let repo = try repository()
        repo.write("a.txt", "um\ndois\ntres\n")
        repo.write("b.txt", "x\ny\n")
        repo.write(".gitignore", "ignorado.log\n")
        try repo.commitAll()
        repo.write("a.txt", "um\nDOIS\ntres\nquatro\n")
        try FileManager.default.removeItem(atPath: repo.path + "/b.txt")
        repo.write("bin.dat", Data([0x89, 0x50, 0x00, 0x01, 0x0a]))
        repo.write("novo.txt", "n1\nn2\n")
        repo.write("sub/com espaço.txt", "s\n")
        repo.write("ignorado.log", "nada\n")

        let found = try changes(repo.runner().changes(in: repo.path + "/sub"))
        XCTAssertEqual(found.root, repo.path)
        XCTAssertEqual(found.base, "HEAD")
        XCTAssertEqual(found.files, [
            DiffFile(path: "a.txt", status: .modified, added: 2, removed: 1),
            DiffFile(path: "b.txt", status: .deleted, added: 0, removed: 2),
            DiffFile(path: "bin.dat", status: .untracked, added: nil, removed: nil),
            DiffFile(path: "novo.txt", status: .untracked, added: 2, removed: 0),
            DiffFile(path: "sub/com espaço.txt", status: .untracked, added: 1, removed: 0),
        ])
        XCTAssertFalse(found.truncated)
        XCTAssertEqual(found.summary.label, "+5 -3 5 ARQ")
    }

    func testCleanRepositoryHasNoFiles() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        XCTAssertEqual(try changes(repo.runner().changes(in: repo.path)).files, [])
    }

    func testStagedChangesCountToo() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        repo.write("a.txt", "um\ndois\n")
        repo.write("novo.txt", "n\n")
        try repo.run("add", "-A")
        XCTAssertEqual(try changes(repo.runner().changes(in: repo.path)).files, [
            DiffFile(path: "a.txt", status: .modified, added: 1, removed: 0),
            DiffFile(path: "novo.txt", status: .added, added: 1, removed: 0),
        ])
    }

    func testRepositoryWithoutCommitsShowsEverythingAsNew() throws {
        let repo = try repository()
        repo.write("preparado.txt", "a\nb\n")
        try repo.run("add", "preparado.txt")
        repo.write("solto.txt", "c\n")

        let runner = repo.runner()
        let found = try changes(runner.changes(in: repo.path))
        XCTAssertNotEqual(found.base, "HEAD")
        XCTAssertEqual(found.files, [
            DiffFile(path: "preparado.txt", status: .added, added: 2, removed: 0),
            DiffFile(path: "solto.txt", status: .untracked, added: 1, removed: 0),
        ])
        XCTAssertTrue(try XCTUnwrap(runner.diff(of: found.files[0], in: found)).text.contains("+a\n+b\n"))
    }

    func testFolderOutsideARepository() throws {
        let repo = try repository()
        XCTAssertEqual(repo.runner().changes(in: temp.makeDirectory("solta")), .notRepository)
    }

    func testUntrackedLinkIsNotFollowed() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        let outside = temp.write("fora/segredo.txt", "linha-de-fora-1\nlinha-de-fora-2\n")
        try FileManager.default.createSymbolicLink(atPath: repo.path + "/atalho", withDestinationPath: outside)

        let runner = repo.runner()
        let found = try changes(runner.changes(in: repo.path))
        XCTAssertEqual(found.files, [DiffFile(path: "atalho", status: .untracked, added: nil, removed: nil)])
        let text = try XCTUnwrap(runner.diff(of: found.files[0], in: found)).text
        XCTAssertFalse(text.contains("linha-de-fora"), "o diff do link mostra o destino, não o conteúdo")
    }

    func testOnlyTheFirstUntrackedFilesAreCounted() throws {
        let repo = try repository()
        for name in ["a", "b", "c"] { repo.write("\(name).txt", "1\n2\n") }
        var runner = repo.runner()
        runner.countedUntracked = 2
        XCTAssertEqual(try changes(runner.changes(in: repo.path)).files.map(\.added), [2, 2, nil])
    }

    // MARK: diff de um arquivo

    func testDiffOfTrackedAndUntrackedFiles() throws {
        let repo = try repository()
        repo.write("a.txt", "um\ndois\ntres\n")
        repo.write(":estranho*.txt", "antes\n")
        try repo.commitAll()
        repo.write("a.txt", "um\nDOIS\ntres\n")
        repo.write(":estranho*.txt", "depois\n")
        repo.write("sub/novo arquivo.txt", "n1\nn2\n")

        let runner = repo.runner()
        let found = try changes(runner.changes(in: repo.path))
        XCTAssertEqual(found.files.map(\.path), [":estranho*.txt", "a.txt", "sub/novo arquivo.txt"])

        let tracked = try XCTUnwrap(runner.diff(of: found.files[1], in: found))
        XCTAssertTrue(tracked.text.contains("@@"))
        XCTAssertTrue(tracked.text.contains("-dois\n+DOIS\n"), tracked.text)
        XCTAssertFalse(tracked.truncated)

        // O caminho vale ao pé da letra: `:` e `*` não viram padrão que pegaria os outros arquivos.
        let odd = try XCTUnwrap(runner.diff(of: found.files[0], in: found))
        XCTAssertTrue(odd.text.contains("-antes\n+depois\n"), odd.text)
        XCTAssertFalse(odd.text.contains("DOIS"))

        let untracked = try XCTUnwrap(runner.diff(of: found.files[2], in: found))
        XCTAssertTrue(untracked.text.contains("+++ b/sub/novo arquivo.txt"), untracked.text)
        XCTAssertTrue(untracked.text.contains("+n1\n+n2\n"), untracked.text)
    }

    func testLongDiffIsCut() throws {
        let repo = try repository()
        repo.write("grande.txt", "x\n")
        try repo.commitAll()
        repo.write("grande.txt", (1...5000).map { "linha \($0)\n" }.joined())

        var runner = repo.runner()
        runner.diffLimit = 2000
        let found = try changes(runner.changes(in: repo.path))
        let diff = try XCTUnwrap(runner.diff(of: found.files[0], in: found))
        XCTAssertTrue(diff.truncated)
        XCTAssertLessThanOrEqual(diff.text.utf8.count, 2000)
        XCTAssertTrue(diff.text.contains("+linha 1\n"))
        XCTAssertTrue(diff.text.hasSuffix("\n"), "o corte cai no fim de uma linha, não no meio")
        XCTAssertFalse(diff.text.contains("\u{FFFD}"))
    }

    // MARK: segurança

    func testHostileRepositoryConfigRunsNothing() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        repo.write(".gitattributes", "*.txt diff=mal\n")
        try repo.commitAll()
        repo.write("a.txt", "dois\n")
        repo.write("novo.txt", "n\n")

        let marker = temp.path + "/rodou"
        let script = temp.write("mal.sh", "#!/bin/sh\necho x >> '\(marker)'\nexit 0\n", permissions: 0o755)
        try repo.run("config", "core.fsmonitor", script)
        try repo.run("config", "diff.external", script)
        try repo.run("config", "diff.mal.textconv", script)
        try repo.run("config", "core.pager", script)

        // Sem as proteções, o config do repositório roda o script: a armadilha está armada.
        try repo.run("diff", "HEAD")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker), "a armadilha do teste não disparou")
        try FileManager.default.removeItem(atPath: marker)

        let runner = repo.runner()
        let found = try changes(runner.changes(in: repo.path))
        XCTAssertEqual(found.files.map(\.path), ["a.txt", "novo.txt"])
        for file in found.files {
            XCTAssertNotNil(runner.diff(of: file, in: found))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "o config do repositório rodou um comando")
    }

    func testInheritedGitVariablesDoNotRedirectTheRepository() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        repo.write("a.txt", "dois\n")
        let other = try repository("outro")

        var environment = repo.agentEnvironment
        environment["GIT_DIR"] = other.path + "/.git"
        environment["GIT_WORK_TREE"] = other.path
        environment["GIT_EXTERNAL_DIFF"] = "/usr/bin/false"
        let found = try changes(repo.runner(environment: environment).changes(in: repo.path))
        XCTAssertEqual(found.root, repo.path)
        XCTAssertEqual(found.files.map(\.path), ["a.txt"])

        let cleaned = GitRunner.environment(from: environment)
        XCTAssertEqual(cleaned.keys.filter { $0.hasPrefix("GIT_") }.sorted(),
                       ["GIT_NO_LAZY_FETCH", "GIT_OPTIONAL_LOCKS", "GIT_TERMINAL_PROMPT"])
        XCTAssertEqual(cleaned["HOME"], repo.home)
    }

    // MARK: falhas

    func testGitThatHangsGivesUp() {
        let slow = temp.write("bin/git", "#!/bin/sh\nexec sleep 30\n", permissions: 0o755)
        let runner = GitRunner(executable: slow, agentEnvironment: ["PATH": "/usr/bin:/bin"], timeout: 0.3)
        let start = Date()
        XCTAssertEqual(runner.changes(in: temp.path), .failed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testMissingExecutableFails() {
        let runner = GitRunner(executable: temp.path + "/nao-existe", agentEnvironment: [:])
        XCTAssertEqual(runner.changes(in: temp.path), .failed)
    }

    func testOutputBeyondTheLimitIsCutAndTheProcessStops() throws {
        let noisy = temp.write("bin/barulho", "#!/bin/sh\nexec yes linha\n", permissions: 0o755)
        let start = Date()
        let result = try XCTUnwrap(Subprocess.run(executable: noisy, arguments: [], environment: [:],
                                                  directory: temp.path, timeout: 5, maxBytes: 10_000))
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.output.count, 10_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4, "o processo é encerrado, não esperado até o tempo acabar")
    }

    func testSubprocessReturnsTheStatusAndTheWholeOutput() throws {
        let script = temp.write("bin/ok", "#!/bin/sh\nprintf 'a\\0b'\nexit 3\n", permissions: 0o755)
        let result = try XCTUnwrap(Subprocess.run(executable: script, arguments: [], environment: [:],
                                                  directory: temp.path, timeout: 5, maxBytes: 100))
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.output, Data([0x61, 0x00, 0x62]))
        XCTAssertFalse(result.truncated)
    }
}
