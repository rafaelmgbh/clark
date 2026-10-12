import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// O diff ligado ao agente: leitura fora da thread principal, resumo no cabeçalho e no card.
final class AgentDiffTests: XCTestCase {
    private var fixture: ClarkFixture!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        fixture = ClarkFixture()
    }

    override func tearDown() {
        fixture.shutdown()
        fixture = nil
        super.tearDown()
    }

    /// Repositório com um commit e uma linha a mais no `a.txt`. Liga o git nos agentes do teste.
    private func repository(_ relative: String = "Projetos/acme/api") throws -> TestRepository {
        let repo = try TestRepository(at: fixture.home + "/" + relative, home: fixture.home)
        fixture.gitPath = repo.git
        repo.write("a.txt", "um\n")
        try repo.commitAll()
        repo.write("a.txt", "um\ndois\n")
        return repo
    }

    private func agent(in directory: String, of controller: MainWindowController) -> AgentPaneView {
        controller.setDefaultDirectory(directory)
        controller.addAgents(1)
        return controller.panes[controller.panes.count - 1]
    }

    /// Leva o agente a WORKING por `seconds` e deixa a saída parar.
    private func work(_ pane: AgentPaneView, in controller: MainWindowController, seconds: Double) {
        pane.terminal.onUserInput?()
        fixture.now += 1
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .working)
        fixture.now += seconds
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 1.5
        controller.tick()
    }

    // MARK: monitor

    func testRefreshReadsTheRepositoryWithoutBlockingTheCaller() throws {
        let repo = try repository()
        let monitor = DiffMonitor()
        var calls = 0
        monitor.onChange = { calls += 1 }
        monitor.configure(runner: repo.runner(), directory: repo.path)
        XCTAssertEqual(monitor.state, .unknown)

        monitor.refresh()
        XCTAssertTrue(monitor.isLoading)
        XCTAssertEqual(monitor.state, .unknown, "quem chamou não espera o git")
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        XCTAssertEqual(monitor.summary, DiffSummary(files: 1, added: 1, removed: 0))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(monitor.revision, 1)
    }

    func testRefreshAskedWhileReadingRunsOnceMore() throws {
        let repo = try repository()
        let monitor = DiffMonitor()
        monitor.configure(runner: repo.runner(), directory: repo.path)
        monitor.refresh()
        monitor.refresh()
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        XCTAssertEqual(monitor.revision, 2, "os pedidos feitos durante a leitura viram uma leitura só")
    }

    func testEveryFinishedReadCountsEvenWithTheSameList() throws {
        // O conteúdo de um arquivo pode mudar sem mudar as contagens: o painel relê pelo número da leitura.
        let repo = try repository()
        let monitor = DiffMonitor()
        var calls = 0
        monitor.onChange = { calls += 1 }
        monitor.configure(runner: repo.runner(), directory: repo.path)
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(monitor.revision, 2)
    }

    func testWithoutGitTheStateSaysSo() {
        let monitor = DiffMonitor()
        monitor.configure(runner: nil, directory: fixture.home)
        monitor.refresh()
        XCTAssertEqual(monitor.state, .noGit)
        XCTAssertFalse(monitor.isLoading)
        XCTAssertNil(monitor.summary)
    }

    func testCleanRepositoryHasNoSummary() throws {
        let repo = try repository()
        repo.write("a.txt", "um\n")
        let monitor = DiffMonitor()
        monitor.configure(runner: repo.runner(), directory: repo.path)
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        XCTAssertEqual(monitor.state, .changes(RepoChanges(root: repo.path, base: "HEAD", files: [], truncated: false)))
        XCTAssertNil(monitor.summary)
    }

    func testReadOfAPreviousFolderIsDropped() throws {
        let repo = try repository()
        let other = try TestRepository(at: fixture.home + "/Projetos/beta", home: fixture.home)
        let monitor = DiffMonitor()
        monitor.configure(runner: repo.runner(), directory: repo.path)
        monitor.refresh()
        monitor.configure(runner: other.runner(), directory: other.path)
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        XCTAssertEqual(monitor.state, .changes(RepoChanges(root: other.path, base: GitDiff.emptyTree, files: [],
                                                             truncated: false)))
        XCTAssertEqual(monitor.revision, 1, "a leitura da pasta anterior não conta")
    }

    func testFileDiffArrivesOnTheMainThread() throws {
        let repo = try repository()
        let monitor = DiffMonitor()
        monitor.configure(runner: repo.runner(), directory: repo.path)
        monitor.refresh()
        XCTAssertTrue(waitUntil { !monitor.isLoading })
        guard case .changes(let changes) = monitor.state else { return XCTFail("sem lista") }

        var received: FileDiff?
        var onMain = false
        monitor.loadDiff(of: changes.files[0]) {
            received = $0
            onMain = Thread.isMainThread
        }
        XCTAssertNil(received, "o diff do arquivo também sai fora da thread principal")
        XCTAssertTrue(waitUntil { received != nil })
        XCTAssertTrue(onMain)
        XCTAssertTrue(received?.text.contains("+dois\n") ?? false)
    }

    // MARK: agente

    func testAgentInARepositoryShowsTheSummaryOnTheHeaderAndTheCard() throws {
        let repo = try repository()
        repo.write("novo.txt", "n\n")
        let controller = fixture.started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertNil(pane.snapshot.diff, "antes da leitura não há resumo")

        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        let summary = DiffSummary(files: 2, added: 2, removed: 0)
        XCTAssertEqual(pane.snapshot.diff, summary)
        XCTAssertEqual(pane.header.snapshot.diff, summary)
        XCTAssertEqual(controller.sidebar.cards[0].snapshot.diff, summary)
    }

    func testSummaryIsReadAgainWhenTheAgentStopsWorking() throws {
        let repo = try repository()
        let controller = fixture.started()
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff?.files == 1 })
        fixture.now += 5
        controller.tick()

        repo.write("outro.txt", "x\n")
        XCTAssertFalse(waitUntil(timeout: 0.3) { pane.snapshot.diff?.files == 2 }, "sem gatilho, nada é relido")
        work(pane, in: controller, seconds: 4)
        XCTAssertNotEqual(pane.state, .working)
        XCTAssertTrue(waitUntil { pane.snapshot.diff?.files == 2 })
    }

    func testAppComingBackToTheFrontReadsEveryAgentAgain() throws {
        let repo = try repository()
        let controller = fixture.started()
        let first = agent(in: repo.path, of: controller)
        let second = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { first.snapshot.diff?.files == 1 && second.snapshot.diff?.files == 1 })

        repo.write("outro.txt", "x\n")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        XCTAssertTrue(waitUntil { first.snapshot.diff?.files == 2 && second.snapshot.diff?.files == 2 })
    }

    func testAgentOutsideARepositoryHasNoSummary() throws {
        _ = try repository()
        let controller = fixture.started()
        let pane = agent(in: fixture.temp.makeDirectory("Projetos/solta"), of: controller)
        XCTAssertTrue(waitUntil { pane.diff.state == .notRepository })
        XCTAssertNil(pane.snapshot.diff)
    }

    func testWithoutGitNothingIsRead() {
        let controller = fixture.started(agents: 1)
        XCTAssertEqual(controller.panes[0].diff.state, .noGit)
        XCTAssertFalse(controller.panes[0].diff.isLoading)
        XCTAssertNil(controller.panes[0].snapshot.diff)
    }

    func testGitOfTheDiffRunsWithTheFilteredEnvironmentOfTheAgent() throws {
        _ = try repository()
        var environment = fixture.environment
        environment["GITHUB_TOKEN"] = "segredo"
        environment["GIT_DIR"] = "/caminho/de/outro/repositorio"
        let controller = fixture.started(agents: 1, environment: environment)
        let runner = try XCTUnwrap(controller.panes[0].diff.runner)
        XCTAssertNil(runner.environment["GITHUB_TOKEN"], "o git do diff não recebe o que o agente não recebe")
        XCTAssertNil(runner.environment["GIT_DIR"])
        XCTAssertEqual(runner.environment["HOME"], fixture.home)
        XCTAssertEqual(runner.environment["CLARK_AGENT"], "AGENT 1")
    }

    func testReopenedAgentKeepsTheSummaryWhileItIsReadAgain() throws {
        let repo = try repository()
        let controller = fixture.started()
        let pane = agent(in: repo.path, of: controller)
        XCTAssertTrue(waitUntil { pane.snapshot.diff != nil })
        pane.spawn()
        XCTAssertNotNil(pane.snapshot.diff, "a pasta é a mesma: o resumo não pisca")
        XCTAssertTrue(waitUntil { !pane.diff.isLoading })
    }
}
