import XCTest
@testable import ClarkCore

final class ProjectUsageTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private let api = "/Users/eu/Projetos/acme/api"
    private let portal = "/Users/eu/Projetos/acme/portal"
    private let site = "/Users/eu/Projetos/beta/site"
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let day: TimeInterval = 24 * 60 * 60
    private var serial = 0

    override func setUp() {
        super.setUp()
        temp = TemporaryDirectory()
        serial = 0
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private var configDir: String { temp.path + "/.claude" }

    private func folder(_ directory: String) -> String {
        ".claude" + SessionDigestReader.projectFolder(canonicalDirectory: directory, configDir: "")
    }

    /// Grava `count` conversas na pasta do projeto, todas mexidas `age` segundos antes de `now`.
    private func conversations(_ count: Int, in directory: String, age: TimeInterval = 60) {
        for _ in 0..<count {
            serial += 1
            let id = String(format: "%08x-1111-4111-8111-111111111111", serial)
            let path = temp.write(folder(directory) + "/\(id).jsonl", "{}\n")
            try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                                                   ofItemAtPath: path)
        }
    }

    private func count(_ directory: String) -> ProjectUsage.Count? {
        ProjectUsage.count(canonicalDirectory: directory, configDir: configDir, now: now)
    }

    private func mostUsed(_ directories: [String], limit: Int = ProjectUsage.maxSuggestions) -> [String] {
        ProjectUsage.mostUsed(directories, configDir: configDir, now: now, limit: limit)
    }

    func testCountsTheConversationsOfTheFolder() {
        conversations(2, in: api, age: 3 * day)
        conversations(1, in: api, age: 600)
        conversations(4, in: site)
        XCTAssertEqual(count(api), ProjectUsage.Count(conversations: 3, latest: now.addingTimeInterval(-600)))
    }

    func testFolderNeverUsedHasNoCount() {
        XCTAssertNil(count(api))
        temp.makeDirectory(folder(api))
        XCTAssertNil(count(api), "pasta de conversas vazia")
    }

    func testConversationOlderThanTheWindowDoesNotCount() {
        conversations(3, in: api, age: ProjectUsage.window + 60)
        XCTAssertNil(count(api))
        conversations(1, in: api, age: ProjectUsage.window - 60)
        XCTAssertEqual(count(api)?.conversations, 1)
    }

    func testOnlyConversationFilesCount() {
        conversations(1, in: api)
        temp.write(folder(api) + "/anotacoes.jsonl", "{}\n")
        temp.write(folder(api) + "/aaaaaaaa-1111-4111-8111-111111111111.txt", "{}\n")
        // A pasta com nome de conversa guarda os subagentes dela: não é outra conversa.
        temp.makeDirectory(folder(api) + "/bbbbbbbb-1111-4111-8111-111111111111.jsonl")
        let outside = temp.write("fora/conversa.jsonl", "{}\n")
        try? FileManager.default.createSymbolicLink(
            atPath: temp.path + "/" + folder(api) + "/cccccccc-1111-4111-8111-111111111111.jsonl",
            withDestinationPath: outside)
        XCTAssertEqual(count(api)?.conversations, 1)
    }

    func testMostUsedComesFirst() {
        conversations(2, in: api)
        conversations(5, in: portal)
        conversations(3, in: site)
        XCTAssertEqual(mostUsed([api, portal, site]), [portal, site, api])
    }

    func testTieGoesToTheOneUsedLast() {
        conversations(2, in: api, age: 3 * day)
        conversations(2, in: portal, age: 600)
        conversations(2, in: site, age: day)
        XCTAssertEqual(mostUsed([api, portal, site]), [portal, site, api])
    }

    func testNeverUsedIsNotSuggested() {
        conversations(1, in: site)
        XCTAssertEqual(mostUsed([api, portal, site]), [site])
        XCTAssertEqual(mostUsed([api, portal]), [])
    }

    func testStopsAtTheLimit() {
        conversations(3, in: api)
        conversations(2, in: portal)
        conversations(1, in: site)
        XCTAssertEqual(mostUsed([api, portal, site], limit: 2), [api, portal])
        XCTAssertEqual(mostUsed([api, portal, site], limit: 0), [])
    }

    func testOpenedFolderCountsBeforeItsConversationIsSaved() {
        conversations(1, in: api, age: day)
        conversations(1, in: site, age: 2 * day)
        let opened = [site: now.addingTimeInterval(-60), portal: now.addingTimeInterval(-30)]
        XCTAssertEqual(ProjectUsage.mostUsed([api, portal, site], configDir: configDir, now: now, opened: opened),
                       [site, portal, api], "a pasta aberta conta uma conversa, mexida quando foi aberta")
    }

    func testOpenedFolderIsNotCountedTwiceOnceItsConversationIsSaved() {
        conversations(2, in: api)
        conversations(1, in: site, age: 10)
        let opened = [site: now.addingTimeInterval(-30)]
        XCTAssertEqual(ProjectUsage.mostUsed([api, site], configDir: configDir, now: now, opened: opened),
                       [api, site], "a conversa gravada depois da abertura é a dela")
    }

    func testSameFolderAskedTwiceIsSuggestedOnce() {
        conversations(1, in: api)
        XCTAssertEqual(mostUsed([api, api]), [api])
    }
}
