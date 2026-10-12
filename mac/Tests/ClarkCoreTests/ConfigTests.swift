import XCTest
@testable import ClarkCore

final class ClarkConfigTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private func parse(_ json: String) -> ClarkConfig {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertNotNil(object, json)
        return ClarkConfig(json: object ?? [:])
    }

    func testDefaults() {
        let config = parse("{}")
        XCTAssertEqual(config.theme, "dark")
        XCTAssertEqual(config.layout, "focus")
        XCTAssertEqual(config.fontName, "Menlo")
        XCTAssertEqual(config.fontSize, 12)
        XCTAssertEqual(config.fontScale, 1)
        XCTAssertTrue(config.dragons)
        XCTAssertTrue(config.queueVisible)
        XCTAssertNil(config.cwd)
        XCTAssertNil(config.skillsDir)
        XCTAssertEqual(config.mainAgent, 0)
        XCTAssertTrue(config.agents.isEmpty)
        XCTAssertEqual(config.projectNames, [:])
    }

    func testValidValues() {
        let config = parse("""
        {"theme": "magick", "layout": "grid", "font": "JetBrains Mono 14", "font_scale": 1.5,
         "dragons": false, "queue_visible": false, "cwd": "~/Projetos", "skills_dir": "~/skills", "main_agent": 1,
         "agents": [{"name": "API", "cwd": "/a", "session_id": "\(id.uppercased())", "color": 2},
                    {"name": "AGENT 2", "cwd": "/b", "session_id": "\(id)", "color": 0}]}
        """)
        XCTAssertEqual(config.theme, "magick")
        XCTAssertEqual(config.layout, "grid")
        XCTAssertEqual(config.fontName, "JetBrains Mono")
        XCTAssertEqual(config.fontSize, 14)
        XCTAssertEqual(config.fontScale, 1.5)
        XCTAssertFalse(config.dragons)
        XCTAssertFalse(config.queueVisible)
        XCTAssertEqual(config.cwd, "~/Projetos")
        XCTAssertEqual(config.skillsDir, "~/skills")
        XCTAssertEqual(config.mainAgent, 1)
        XCTAssertEqual(config.agents, [SavedAgent(name: "API", cwd: "/a", sessionID: id, tone: 2),
                                       SavedAgent(name: "AGENT 2", cwd: "/b", sessionID: id, tone: 0)])
    }

    func testInvalidFieldsFallBackOneByOne() {
        let config = parse("""
        {"theme": "neon", "layout": 3, "font": "Menlo", "font_scale": "grande", "dragons": 0,
         "queue_visible": "nao", "cwd": 7, "skills_dir": "", "main_agent": -1, "agents": "nenhum"}
        """)
        XCTAssertEqual(config.theme, "dark")
        XCTAssertEqual(config.layout, "focus")
        XCTAssertEqual(config.fontName, "Menlo")
        XCTAssertEqual(config.fontSize, 12)
        XCTAssertEqual(config.fontScale, 1)
        XCTAssertTrue(config.dragons, "0 não é booleano")
        XCTAssertTrue(config.queueVisible)
        XCTAssertNil(config.cwd)
        XCTAssertNil(config.skillsDir)
        XCTAssertEqual(config.mainAgent, 0)
        XCTAssertTrue(config.agents.isEmpty)
    }

    func testNumbersAndBooleansAreNotInterchangeable() {
        XCTAssertEqual(parse(#"{"font_scale": true}"#).fontScale, 1)
        XCTAssertEqual(parse(#"{"main_agent": true}"#).mainAgent, 0)
        XCTAssertEqual(parse(#"{"main_agent": 1.5}"#).mainAgent, 0)
        XCTAssertEqual(parse(#"{"main_agent": 1e30}"#).mainAgent, 0)
        XCTAssertTrue(parse(#"{"dragons": 1}"#).dragons)
        XCTAssertTrue(parse(#"{"dragons": "false"}"#).dragons)
    }

    func testFontScaleIsClamped() {
        XCTAssertEqual(parse(#"{"font_scale": 99}"#).fontScale, 2.5)
        XCTAssertEqual(parse(#"{"font_scale": 0.1}"#).fontScale, 0.6)
        XCTAssertEqual(parse(#"{"font_scale": -3}"#).fontScale, 0.6)
    }

    func testFontNeedsANameAndASaneSize() {
        for bad in ["Menlo", "12", "Menlo 900", "Menlo 2", "Menlo doze", "", "Menlo -12"] {
            let config = parse(#"{"font": "\#(bad)"}"#)
            XCTAssertEqual(config.fontName, "Menlo", bad)
            XCTAssertEqual(config.fontSize, 12, bad)
        }
        let config = parse(#"{"font": "SF Mono 13.5"}"#)
        XCTAssertEqual(config.fontName, "SF Mono")
        XCTAssertEqual(config.fontSize, 13.5)
    }

    func testAgentsAreValidatedFieldByField() {
        let config = parse("""
        {"agents": [{"name": 5, "cwd": "", "session_id": "--dangerously-skip-permissions", "color": "azul"},
                    "texto", 3, {"color": 6}, {"color": -1}, {"session_id": 12}]}
        """)
        XCTAssertEqual(config.agents, [SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: 2),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: 1),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil)])
    }

    func testProjectNamesKeepOnlyTextForAPath() {
        let config = parse("""
        {"project_names": {"/a/compras": "Compras Acme", "/a/vazio": "", "/a/numero": 7, "": "sem pasta",
                           "/a/espacos": "   ", "/a/longo": "  Loja   do  João  "}}
        """)
        XCTAssertEqual(config.projectNames, ["/a/compras": "Compras Acme", "/a/longo": "Loja do João"])
        XCTAssertEqual(parse(#"{"project_names": ["lista"]}"#).projectNames, [:])
        XCTAssertEqual(parse(#"{"project_names": "texto"}"#).projectNames, [:])
    }

    func testAtMostSixteenAgents() {
        let entries = Array(repeating: #"{"name": "A"}"#, count: 20).joined(separator: ",")
        XCTAssertEqual(parse(#"{"agents": [\#(entries)]}"#).agents.count, 16)
    }

    func testUnknownKeysSurviveTheRoundTrip() throws {
        var config = parse(#"{"theme": "white", "auto_trust": true, "todos": [{"text": "x"}], "novo": {"a": 1}}"#)
        config.layout = "grid"
        let object = config.jsonObject()
        XCTAssertEqual(object["theme"] as? String, "white")
        XCTAssertEqual(object["layout"] as? String, "grid")
        XCTAssertEqual(object["auto_trust"] as? Bool, true)
        XCTAssertEqual((object["todos"] as? [[String: String]])?.first?["text"], "x")
        XCTAssertEqual((object["novo"] as? [String: Int])?["a"], 1)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object))
    }

    func testJSONObjectShape() {
        var config = ClarkConfig()
        config.fontScale = 1.2345
        config.fontSize = 12.5
        config.agents = [SavedAgent(name: "API", cwd: "/a", sessionID: id, tone: 1),
                         SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil)]
        let object = config.jsonObject()
        XCTAssertEqual(object["font"] as? String, "Menlo 12.5")
        XCTAssertEqual(object["font_scale"] as? Double, 1.23)
        XCTAssertNil(object["cwd"], "campo vazio não vai para o arquivo")
        XCTAssertNil(object["skills_dir"])
        let agents = object["agents"] as? [[String: Any]]
        XCTAssertEqual(agents?.count, 2)
        XCTAssertEqual(agents?[0]["name"] as? String, "API")
        XCTAssertEqual(agents?[0]["session_id"] as? String, id)
        XCTAssertEqual(agents?[0]["color"] as? Int, 1)
        XCTAssertEqual(agents?[1].isEmpty, true)
        XCTAssertEqual(ClarkConfig(json: object).agents, config.agents)
        XCTAssertEqual((ClarkConfig().jsonObject()["font"] as? String), "Menlo 12")
        XCTAssertNil(object["project_names"], "sem apelido, a chave não vai para o arquivo")
    }

    func testProjectNamesSurviveTheRoundTrip() {
        var config = ClarkConfig()
        config.projectNames = ["/a/compras": "Compras Acme"]
        let object = config.jsonObject()
        XCTAssertEqual(object["project_names"] as? [String: String], ["/a/compras": "Compras Acme"])
        XCTAssertEqual(ClarkConfig(json: object).projectNames, config.projectNames)
        XCTAssertNil(ClarkConfig(json: object).unknown["project_names"], "chave conhecida não fica em `unknown`")
    }
}

final class ConfigStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_791_720_000)

    private func store(_ temp: TemporaryDirectory, _ folder: String = "clark") -> ConfigStore {
        ConfigStore(directory: temp.path + "/" + folder, now: { self.fixedDate })
    }

    private func read(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func testDefaultDirectory() {
        XCTAssertEqual(ConfigStore.defaultDirectory(home: "/Users/eu"), "/Users/eu/.config/clark")
    }

    func testLoadWithoutFileGivesDefaults() {
        let temp = TemporaryDirectory()
        let loaded = store(temp).load()
        XCTAssertEqual(loaded.config.theme, "dark")
        XCTAssertNil(loaded.warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path + "/clark"), "ler não cria nada")
    }

    func testSaveCreatesPrivateDirectoryAndFile() throws {
        let temp = TemporaryDirectory()
        let store = store(temp)
        var config = ClarkConfig()
        config.layout = "grid"
        try store.save(config)
        XCTAssertEqual(temp.permissions("clark"), 0o700)
        XCTAssertEqual(temp.permissions("clark/config.json"), 0o600)
        XCTAssertEqual(read(store.configPath)?["layout"] as? String, "grid")
        XCTAssertEqual(store.load().config.layout, "grid")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory)
        XCTAssertEqual(leftovers, ["config.json"], "sem temporário esquecido")
    }

    func testSaveTightensAnOpenFileAndDirectory() throws {
        let temp = TemporaryDirectory()
        temp.write("clark/config.json", #"{"theme": "white"}"#, permissions: 0o644)
        chmod(temp.path + "/clark", 0o755)
        let store = store(temp)
        let config = store.load().config
        XCTAssertEqual(config.theme, "white")
        try store.save(config)
        XCTAssertEqual(temp.permissions("clark"), 0o700)
        XCTAssertEqual(temp.permissions("clark/config.json"), 0o600)
    }

    func testInvalidFileIsSetAsideBeforeTheFirstSave() throws {
        let temp = TemporaryDirectory()
        temp.write("clark/config.json", "{ isto nao e json")
        let store = store(temp)
        let loaded = store.load()
        XCTAssertNotNil(loaded.warning)
        XCTAssertEqual(loaded.config.theme, "dark")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory), ["config.json"],
                       "só a gravação põe o arquivo de lado")

        try store.save(loaded.config)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory).sorted()
        XCTAssertEqual(names.count, 2)
        let quarantined = try XCTUnwrap(names.first { $0.hasPrefix("config.json.invalido-") })
        XCTAssertEqual(try String(contentsOfFile: store.directory + "/" + quarantined, encoding: .utf8), "{ isto nao e json")
        XCTAssertNotNil(read(store.configPath))

        try store.save(loaded.config)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory).count, 2,
                       "a quarentena acontece uma vez")
    }

    func testQuarantineNeverOverwritesAnOlderOne() throws {
        let temp = TemporaryDirectory()
        for _ in 0..<2 {
            temp.write("clark/config.json", "[1, 2, 3]")
            let store = store(temp)
            XCTAssertNotNil(store.load().warning, "lista no topo não é config")
            try store.save(ClarkConfig())
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.path + "/clark")
        XCTAssertEqual(names.filter { $0.contains(".invalido-") }.count, 2)
        XCTAssertEqual(names.filter { $0.hasSuffix("-2") }.count, 1)
    }

    func testSaveThroughASymlinkKeepsTheLink() throws {
        let temp = TemporaryDirectory()
        let real = temp.write("dotfiles/clark.json", #"{"theme": "white"}"#)
        temp.makeDirectory("clark")
        let store = store(temp)
        try FileManager.default.createSymbolicLink(atPath: store.configPath, withDestinationPath: real)
        var config = store.load().config
        XCTAssertEqual(config.theme, "white")
        config.layout = "grid"
        try store.save(config)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: store.configPath), real)
        XCTAssertEqual(read(real)?["layout"] as? String, "grid")
        XCTAssertEqual(temp.permissions("dotfiles/clark.json"), 0o600)
    }

    func testCompaniesFileIsReadAndNeverWritten() throws {
        let temp = TemporaryDirectory()
        let store = store(temp)
        XCTAssertNil(store.companiesData())
        try store.save(ClarkConfig())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.companiesPath))
        temp.write("clark/companies.json", #"{"roots": ["~/work"]}"#)
        XCTAssertEqual(store.companiesData(), Data(#"{"roots": ["~/work"]}"#.utf8))
    }

    func testSaveFailureThrows() {
        let temp = TemporaryDirectory()
        temp.write("clark", "sou um arquivo, não uma pasta")
        XCTAssertThrowsError(try store(temp).save(ClarkConfig()))
    }
}
