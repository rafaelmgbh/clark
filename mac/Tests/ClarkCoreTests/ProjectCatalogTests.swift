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

    private func groups(_ json: String? = nil, nicknames: [String: String] = [:],
                        maxListings: Int = ProjectCatalog.maxListings) -> [ProjectGroup] {
        let home = home
        let canonicalize: (String) -> String = { PathTools.canonical($0, base: home, home: home) }
        let resolver = CompanyResolver(json: json.map { Data($0.utf8) }, palette: Theme.dark.agents,
                                       fallbackColor: Theme.dark.dim, canonicalize: canonicalize)
        return resolver.projectGroups(canonicalize: canonicalize, nicknames: nicknames, maxListings: maxListings)
    }

    /// Pasta com um `.git` dentro, como um repositório.
    @discardableResult
    private func makeRepository(_ relative: String) -> String {
        temp.makeDirectory(relative + "/.git")
        return home + "/" + relative
    }

    func testRepositoriesUnderTheCompanyAreItsProjects() {
        let site = makeRepository("Projetos/beta/site")
        let api = makeRepository("Projetos/acme/api")
        let app = makeRepository("Projetos/acme/portal_web")
        let docs = temp.makeDirectory("Projetos/acme/docs")
        temp.makeDirectory("Projetos/vazia")

        XCTAssertEqual(groups(), [
            ProjectGroup(name: "acme", folders: [home + "/Projetos/acme"],
                         projects: [ProjectEntry(name: "Api", path: api), ProjectEntry(name: "Portal Web", path: app)],
                         others: [ProjectEntry(name: "Docs", path: docs)]),
            ProjectGroup(name: "beta", folders: [home + "/Projetos/beta"],
                         projects: [ProjectEntry(name: "Site", path: site)]),
            ProjectGroup(name: "vazia", folders: [home + "/Projetos/vazia"]),
        ], "repositório é projeto; pasta comum do primeiro nível fica em `others`")
    }

    func testFolderWithAnAIMarkerIsAProjectAndStillOpensUp() {
        // A pasta-grupo guarda o contexto de IA de todos os projetos de dentro: é projeto e continua abrindo.
        let grupo = temp.makeDirectory("Projetos/acme/sistemas/sistemas-erp")
        temp.write("Projetos/acme/sistemas/sistemas-erp/CLAUDE.md", "# contexto")
        let compras = makeRepository("Projetos/acme/sistemas/sistemas-erp/projects/compras")
        let vendas = temp.makeDirectory("Projetos/acme/sistemas/sistemas-erp/projects/vendas")
        temp.write("Projetos/acme/sistemas/sistemas-erp/projects/vendas/AGENTS.md", "# contexto")
        let rh = temp.makeDirectory("Projetos/acme/sistemas/sistemas-erp/projects/rh")
        temp.makeDirectory("Projetos/acme/sistemas/sistemas-erp/projects/rh/.claude")
        temp.makeDirectory("Projetos/acme/sistemas/sistemas-erp/projects/rascunho")

        let found = groups()
        XCTAssertEqual(found.first?.projects, [])
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Sistemas", projects: [ProjectEntry(name: "Sistemas Erp", path: grupo)]),
            ProjectSection(title: "Sistemas › Sistemas Erp › Projects", projects: [
                ProjectEntry(name: "Compras", path: compras), ProjectEntry(name: "Rh", path: rh),
                ProjectEntry(name: "Vendas", path: vendas),
            ]),
        ])
        XCTAssertEqual(found.first?.others, [ProjectEntry(name: "Sistemas", path: home + "/Projetos/acme/sistemas")])
    }

    func testSearchStopsAtARepositoryAndAtFourLevels() {
        makeRepository("Projetos/acme/api")
        makeRepository("Projetos/acme/api/libs/interna")
        let fundo = makeRepository("Projetos/acme/a/b/c/d")
        makeRepository("Projetos/acme/a/b/c/x/fundo-demais")

        let found = groups()
        XCTAssertEqual(found.first?.projects.map(\.name), ["Api"], "o que está dentro de um repositório é dele")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "A › B › C", projects: [ProjectEntry(name: "D", path: fundo)]),
        ], "o quarto nível entra; o quinto não")
    }

    func testHiddenAndDependencyFoldersStayOut() {
        temp.makeDirectory("Projetos/.oculta/x")
        temp.makeDirectory("Projetos/acme/.cache")
        makeRepository("Projetos/acme/node_modules/pacote")
        makeRepository("Projetos/acme/web/vendor/lib")
        makeRepository("Projetos/acme/api")
        temp.write("Projetos/acme/notas.txt", "x")
        temp.write("Projetos/solto.txt", "x")

        let found = groups()
        XCTAssertEqual(found.map(\.name), ["acme"])
        XCTAssertEqual(found.first?.projects.map(\.name), ["Api"])
        XCTAssertEqual(found.first?.sections, [])
        XCTAssertEqual(found.first?.others.map(\.name), ["Web"])
    }

    func testCompanyThatIsARepositoryIsNotOpenedUp() {
        makeRepository("Projetos/solo")
        temp.makeDirectory("Projetos/solo/src")
        makeRepository("Projetos/solo/libs/interna")

        XCTAssertEqual(groups(), [ProjectGroup(name: "solo", folders: [home + "/Projetos/solo"])],
                       "o repositório direto na raiz abre inteiro, sem listar o que há dentro")
        XCTAssertEqual(groups().first?.isBare, true)
    }

    func testWithoutTheRootThereIsNothingToList() {
        XCTAssertEqual(groups(), [])
    }

    func testSearchGivesUpWhenTheTreeIsTooBig() {
        makeRepository("Projetos/acme/api")
        makeRepository("Projetos/acme/clientes/loja")

        // Uma leitura só: a pasta da empresa. O que está mais fundo fica para o "Outra pasta…".
        let found = groups(maxListings: 1)
        XCTAssertEqual(found.first?.projects.map(\.name), ["Api"])
        XCTAssertEqual(found.first?.sections, [])
        XCTAssertEqual(found.first?.others.map(\.name), ["Clientes"])
        XCTAssertEqual(groups().first?.sections.map(\.title), ["Clientes"])
    }

    func testNicknamedProjectsComeFirstUnderTheirNickname() {
        let compras = makeRepository("Projetos/acme/sistemas/compras")
        let vendas = makeRepository("Projetos/acme/sistemas/vendas")
        let api = makeRepository("Projetos/acme/api")
        let fundo = temp.makeDirectory("Projetos/acme/a/b/c/d/e/f")
        let docs = temp.makeDirectory("Projetos/acme/docs")

        let found = groups(nicknames: [compras: "Compras Acme", api: "API central", fundo: "Bem fundo",
                                       docs: "Manuais", home + "/Projetos/acme/sumiu": "Fantasma"])
        XCTAssertEqual(found.first?.nicknamed, [
            ProjectEntry(name: "API central", path: api), ProjectEntry(name: "Bem fundo", path: fundo),
            ProjectEntry(name: "Compras Acme", path: compras), ProjectEntry(name: "Manuais", path: docs),
        ], "apelido vale para qualquer pasta que existe, a qualquer profundidade")
        XCTAssertEqual(found.first?.projects, [], "o apelidado não aparece duas vezes")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Sistemas", projects: [ProjectEntry(name: "Vendas", path: vendas)]),
        ])
        XCTAssertEqual(found.first?.others.map(\.name), ["A", "Sistemas"])
    }

    func testNicknamedFolderOutsideEveryCompanyGoesToTheFallbackGroup() {
        makeRepository("Projetos/acme/api")
        let notas = temp.makeDirectory("Documentos/notas")

        let found = groups(nicknames: [notas: "Minhas notas"])
        XCTAssertEqual(found.map(\.name), ["acme", CompanyResolver.fallbackName])
        XCTAssertEqual(found.last, ProjectGroup(name: CompanyResolver.fallbackName, folders: [],
                                                nicknamed: [ProjectEntry(name: "Minhas notas", path: notas)]))
    }

    func testDeclaredCompanyGathersItsPathsUnderItsName() {
        let api = makeRepository("Projetos/acme/api")
        let antigo = makeRepository("trabalho/legado/antigo")
        temp.makeDirectory("trabalho/nao-existe-ainda")

        let found = groups("""
        {"companies": [{"name": "Acme SA", "paths": ["~/Projetos/acme", "~/trabalho/legado", "~/trabalho/sumiu"]}]}
        """)
        XCTAssertEqual(found, [
            ProjectGroup(name: "Acme SA", folders: [home + "/Projetos/acme", home + "/trabalho/legado"], projects: [
                ProjectEntry(name: "Antigo", path: antigo), ProjectEntry(name: "Api", path: api),
            ]),
        ], "os projetos das duas pastas saem numa lista só, por nome")
    }

    func testFolderOfAnotherCompanyIsNotListedInsideTheParent() {
        makeRepository("Projetos/acme/api")
        let painel = makeRepository("Projetos/acme/parceiro/painel")

        let found = groups("""
        {"companies": [{"name": "Parceiro", "paths": ["~/Projetos/acme/parceiro"]}]}
        """)
        XCTAssertEqual(found.map(\.name), ["acme", "Parceiro"])
        XCTAssertEqual(found[0].projects.map(\.name), ["Api"], "o que abre como outra empresa não aparece na acme")
        XCTAssertEqual(found[0].sections, [])
        XCTAssertEqual(found[0].others, [])
        XCTAssertEqual(found[1].folders, [home + "/Projetos/acme/parceiro"])
        XCTAssertEqual(found[1].projects, [ProjectEntry(name: "Painel", path: painel)])
    }

    func testCompanyThatCoversTheRootListsTheRootOnce() {
        let api = makeRepository("Projetos/acme/api")
        temp.makeDirectory("Projetos/beta")

        let found = groups("""
        {"companies": [{"name": "Tudo", "paths": ["~/Projetos"]}]}
        """)
        XCTAssertEqual(found, [
            ProjectGroup(name: "Tudo", folders: [home + "/Projetos"],
                         sections: [ProjectSection(title: "Acme", projects: [ProjectEntry(name: "Api", path: api)])],
                         others: [ProjectEntry(name: "Acme", path: home + "/Projetos/acme"),
                                  ProjectEntry(name: "Beta", path: home + "/Projetos/beta")]),
        ])
    }

    func testCustomRootsAreListed() {
        let app = makeRepository("codigo/gama/app")
        makeRepository("Projetos/acme/api")

        let found = groups(#"{"roots": ["~/codigo"]}"#)
        XCTAssertEqual(found, [
            ProjectGroup(name: "gama", folders: [home + "/codigo/gama"], projects: [
                ProjectEntry(name: "App", path: app),
            ]),
        ])
    }

    func testLinkIntoAnotherCompanyIsNotListedAsThisOne() throws {
        makeRepository("Projetos/acme/api")
        makeRepository("Projetos/beta/site")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/atalho",
                                                   withDestinationPath: home + "/Projetos/beta/site")

        let found = groups()
        XCTAssertEqual(found[0].projects.map(\.name), ["Api"], "o link abre como beta, não como acme")
        XCTAssertEqual(found[1].projects.map(\.name), ["Site"])
    }

    func testLinkBackToAnAncestorDoesNotLoop() throws {
        let api = makeRepository("Projetos/acme/grupo/api")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/grupo/volta",
                                                   withDestinationPath: home + "/Projetos/acme")

        XCTAssertEqual(groups().first?.sections, [
            ProjectSection(title: "Grupo", projects: [ProjectEntry(name: "Api", path: api)]),
        ])
    }

    func testLinkToAProjectOfTheSameCompanyIsListedOnce() throws {
        let api = makeRepository("Projetos/acme/api")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/zz-atalho", withDestinationPath: api)

        XCTAssertEqual(groups().first?.projects, [ProjectEntry(name: "Api", path: api)],
                       "a mesma pasta por dois caminhos é um projeto só")
    }

    func testProjectReachedThroughALinkIsKnownByItsRealPath() throws {
        let portal = makeRepository("Projetos/acme/a/b/c/portal")
        makeRepository("Projetos/acme/a/b/c/site")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/perto",
                                                   withDestinationPath: home + "/Projetos/acme/a/b/c")

        let found = groups(nicknames: [portal: "Portal"])
        XCTAssertEqual(found.first?.nicknamed, [ProjectEntry(name: "Portal", path: portal)])
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Perto",
                           projects: [ProjectEntry(name: "Site", path: home + "/Projetos/acme/perto/site")]),
        ], "o apelidado não volta pela pasta do link, e a pasta de verdade não repete a do link")
    }

    func testFilesAndLinksToFilesAreNotFolders() throws {
        makeRepository("Projetos/acme/api")
        temp.write("Projetos/acme/notas.txt", "x")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/atalho.txt",
                                                   withDestinationPath: home + "/Projetos/acme/notas.txt")
        try FileManager.default.createSymbolicLink(atPath: home + "/Projetos/acme/quebrado",
                                                   withDestinationPath: home + "/Projetos/acme/sumiu")

        let found = groups()
        XCTAssertEqual(found.first?.projects.map(\.name), ["Api"])
        XCTAssertEqual(found.first?.others, [])
    }
}
