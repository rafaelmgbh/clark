import XCTest
@testable import ClarkCore

final class ProjectCatalogTests: XCTestCase {
    private var temp: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        temp = TemporaryDirectory()
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private var home: String { temp.path }

    private func groups(_ json: String? = nil) -> [ProjectGroup] {
        let home = home
        let canonicalize: (String) -> String = { PathTools.canonical($0, base: home, home: home) }
        let resolver = CompanyResolver(json: json.map { Data($0.utf8) }, palette: Theme.dark.agents,
                                       fallbackColor: Theme.dark.dim, canonicalize: canonicalize)
        return resolver.projectGroups(canonicalize: canonicalize)
    }

    /// Pasta com um `.git` dentro, como um repositório.
    @discardableResult
    private func makeRepository(_ relative: String) -> String {
        temp.makeDirectory(relative + "/.git")
        return home + "/" + relative
    }

    func testFoldersUnderTheRootBecomeCompaniesWithTheirProjects() {
        let site = temp.makeDirectory("Projetos/beta/site")
        let api = temp.makeDirectory("Projetos/acme/api")
        let app = temp.makeDirectory("Projetos/acme/App")
        temp.makeDirectory("Projetos/vazia")

        XCTAssertEqual(groups(), [
            ProjectGroup(name: "acme", folders: [home + "/Projetos/acme"], projects: [
                ProjectEntry(name: "api", path: api), ProjectEntry(name: "App", path: app),
            ]),
            ProjectGroup(name: "beta", folders: [home + "/Projetos/beta"], projects: [
                ProjectEntry(name: "site", path: site),
            ]),
            ProjectGroup(name: "vazia", folders: [home + "/Projetos/vazia"], projects: []),
        ])
    }

    func testHiddenFoldersAndFilesStayOut() {
        temp.makeDirectory("Projetos/.oculta/x")
        temp.makeDirectory("Projetos/acme/.cache")
        temp.makeDirectory("Projetos/acme/api")
        temp.write("Projetos/acme/notas.txt", "x")
        temp.write("Projetos/solto.txt", "x")

        let found = groups()
        XCTAssertEqual(found.map(\.name), ["acme"])
        XCTAssertEqual(found.first?.projects.map(\.name), ["api"])
    }

    func testWithoutTheRootThereIsNothingToList() {
        XCTAssertEqual(groups(), [])
    }

    func testFolderThatHoldsRepositoriesListsThem() {
        let loja = makeRepository("Projetos/acme/clientes/loja")
        let rascunho = temp.makeDirectory("Projetos/acme/clientes/rascunho")
        let api = makeRepository("Projetos/acme/api")
        temp.makeDirectory("Projetos/acme/api/src")
        let docs = temp.makeDirectory("Projetos/acme/docs")
        temp.makeDirectory("Projetos/acme/docs/2026")

        XCTAssertEqual(groups().first?.projects, [
            ProjectEntry(name: "api", path: api),
            ProjectEntry(name: "clientes", path: home + "/Projetos/acme/clientes", children: [
                ProjectEntry(name: "loja", path: loja), ProjectEntry(name: "rascunho", path: rascunho),
            ]),
            ProjectEntry(name: "docs", path: docs),
        ], "repositório não abre submenu; pasta comum só abre quando guarda repositórios")
    }

    func testDeclaredCompanyGathersItsPathsUnderItsName() {
        let api = temp.makeDirectory("Projetos/acme/api")
        let antigo = temp.makeDirectory("trabalho/legado/antigo")
        temp.makeDirectory("trabalho/nao-existe-ainda")

        let found = groups("""
        {"companies": [{"name": "Acme SA", "paths": ["~/Projetos/acme", "~/trabalho/legado", "~/trabalho/sumiu"]}]}
        """)
        XCTAssertEqual(found, [
            ProjectGroup(name: "Acme SA", folders: [home + "/Projetos/acme", home + "/trabalho/legado"], projects: [
                ProjectEntry(name: "antigo", path: antigo), ProjectEntry(name: "api", path: api),
            ]),
        ], "os projetos das duas pastas saem numa lista só, por nome")
    }

    func testFolderOfAnotherCompanyIsNotListedInsideTheParent() {
        temp.makeDirectory("Projetos/acme/api")
        let painel = temp.makeDirectory("Projetos/acme/parceiro/painel")

        let found = groups("""
        {"companies": [{"name": "Parceiro", "paths": ["~/Projetos/acme/parceiro"]}]}
        """)
        XCTAssertEqual(found.map(\.name), ["acme", "Parceiro"])
        XCTAssertEqual(found[0].projects.map(\.name), ["api"], "o que abre como outra empresa não aparece na acme")
        XCTAssertEqual(found[1].folders, [home + "/Projetos/acme/parceiro"])
        XCTAssertEqual(found[1].projects, [ProjectEntry(name: "painel", path: painel)])
    }

    func testCompanyThatCoversTheRootListsTheRootOnce() {
        let api = makeRepository("Projetos/acme/api")
        temp.makeDirectory("Projetos/beta")

        let found = groups("""
        {"companies": [{"name": "Tudo", "paths": ["~/Projetos"]}]}
        """)
        XCTAssertEqual(found, [
            ProjectGroup(name: "Tudo", folders: [home + "/Projetos"], projects: [
                ProjectEntry(name: "acme", path: home + "/Projetos/acme", children: [
                    ProjectEntry(name: "api", path: api),
                ]),
                ProjectEntry(name: "beta", path: home + "/Projetos/beta"),
            ]),
        ])
    }

    func testCustomRootsAreListed() {
        let app = temp.makeDirectory("codigo/gama/app")
        temp.makeDirectory("Projetos/acme/api")

        let found = groups(#"{"roots": ["~/codigo"]}"#)
        XCTAssertEqual(found, [
            ProjectGroup(name: "gama", folders: [home + "/codigo/gama"], projects: [
                ProjectEntry(name: "app", path: app),
            ]),
        ])
    }

    func testLinkIntoAnotherCompanyIsNotListedAsThisOne() throws {
        temp.makeDirectory("Projetos/acme/api")
        temp.makeDirectory("Projetos/beta/site")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/atalho",
                                                   withDestinationPath: home + "/Projetos/beta/site")

        let found = groups()
        XCTAssertEqual(found[0].projects.map(\.name), ["api"], "o link abre como beta, não como acme")
        XCTAssertEqual(found[1].projects.map(\.name), ["site"])
    }
}
