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

    /// Worktree de `main`: pasta com um arquivo `.git` que aponta para dentro do repositório principal.
    @discardableResult
    private func makeWorktree(_ relative: String, of main: String) -> String {
        let name = (relative as NSString).lastPathComponent
        temp.write(relative + "/.git", "gitdir: \(main)/.git/worktrees/\(name)\n")
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
            ProjectSection(title: "Sistemas Erp", path: grupo, folder: ProjectEntry(name: "Sistemas Erp", path: grupo),
                           projects: [
                               ProjectEntry(name: "Compras", path: compras), ProjectEntry(name: "Rh", path: rh),
                               ProjectEntry(name: "Vendas", path: vendas),
                           ]),
        ], "a pasta-grupo abre de dentro do grupo dela; `projects` não vira nome e `sistemas` ficou sem projeto")
        XCTAssertEqual(found.first?.others, [ProjectEntry(name: "Sistemas", path: home + "/Projetos/acme/sistemas")])
    }

    func testProjectThatHoldsProjectsOpensFromItsOwnGroup() {
        let suite = temp.makeDirectory("Projetos/acme/suite")
        temp.write("Projetos/acme/suite/CLAUDE.md", "# contexto")
        let nucleo = makeRepository("Projetos/acme/suite/nucleo")
        let api = makeRepository("Projetos/acme/api")

        let found = groups()
        XCTAssertEqual(found.first?.projects, [ProjectEntry(name: "Api", path: api)],
                       "o projeto que guarda projetos não aparece duas vezes, uma solto e outra como grupo")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Suite", path: suite, folder: ProjectEntry(name: "Suite", path: suite),
                           projects: [ProjectEntry(name: "Nucleo", path: nucleo)]),
        ])

        let nicknamed = groups(nicknames: [suite: "Suíte"])
        XCTAssertEqual(nicknamed.first?.nicknamed, [ProjectEntry(name: "Suíte", path: suite)])
        XCTAssertEqual(nicknamed.first?.sections, [
            ProjectSection(title: "Suite", path: suite, projects: [ProjectEntry(name: "Nucleo", path: nucleo)]),
        ], "com apelido ela já está no topo da empresa")
    }

    func testProjectWhoseOnlyChildBecameAGroupStaysAProject() {
        let fora = temp.makeDirectory("Projetos/acme/fora")
        temp.write("Projetos/acme/fora/CLAUDE.md", "# contexto")
        let dentro = temp.makeDirectory("Projetos/acme/fora/dentro")
        temp.write("Projetos/acme/fora/dentro/AGENTS.md", "# contexto")
        let api = makeRepository("Projetos/acme/fora/dentro/api")

        let found = groups()
        XCTAssertEqual(found.first?.projects, [ProjectEntry(name: "Fora", path: fora)],
                       "o grupo que ficou vazio some, e a pasta dele continua um projeto comum")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Dentro", path: dentro, folder: ProjectEntry(name: "Dentro", path: dentro),
                           projects: [ProjectEntry(name: "Api", path: api)]),
        ])
    }

    func testGroupTakesTheNameOfItsFolderAndOuterFoldersOnlyTellTwinsApart() {
        let loja = makeRepository("Projetos/acme/clientes/loja")
        let vendas = makeRepository("Projetos/acme/clientes/erp/vendas")
        let compras = makeRepository("Projetos/acme/parceiros/erp/compras")
        let fundo = makeRepository("Projetos/acme/a/b/c/fundo")

        XCTAssertEqual(groups().first?.sections, [
            ProjectSection(title: "C", path: home + "/Projetos/acme/a/b/c",
                           projects: [ProjectEntry(name: "Fundo", path: fundo)]),
            ProjectSection(title: "Clientes", path: home + "/Projetos/acme/clientes",
                           projects: [ProjectEntry(name: "Loja", path: loja)]),
            ProjectSection(title: "Clientes › Erp", path: home + "/Projetos/acme/clientes/erp",
                           projects: [ProjectEntry(name: "Vendas", path: vendas)]),
            ProjectSection(title: "Parceiros › Erp", path: home + "/Projetos/acme/parceiros/erp",
                           projects: [ProjectEntry(name: "Compras", path: compras)]),
        ], "o nome é o da pasta, na ordem do menu; o caminho de fora só entra quando dois se confundem")
    }

    func testFolderThatOnlyOrganizesDoesNotNameTheGroup() {
        let compras = makeRepository("Projetos/acme/erp/projects/compras")
        let nucleo = makeRepository("Projetos/acme/erp/nucleo")
        let site = makeRepository("Projetos/acme/apps/site")

        XCTAssertEqual(groups().first?.sections, [
            ProjectSection(title: "Apps", path: home + "/Projetos/acme/apps",
                           projects: [ProjectEntry(name: "Site", path: site)]),
            ProjectSection(title: "Erp", path: home + "/Projetos/acme/erp",
                           projects: [ProjectEntry(name: "Compras", path: compras),
                                      ProjectEntry(name: "Nucleo", path: nucleo)]),
        ], "`projects` some do nome e junta com o que está ao lado dela; sozinha, `apps` é o nome que há")
    }

    func testTwoGroupsThatEndUpWithTheSameNameShowTheWholeWay() {
        let um = makeRepository("Projetos/acme/erp/um")
        let dois = makeRepository("Projetos/acme/projects/erp/dois")

        XCTAssertEqual(groups().first?.sections, [
            ProjectSection(title: "Erp", path: home + "/Projetos/acme/erp",
                           projects: [ProjectEntry(name: "Um", path: um)]),
            ProjectSection(title: "Projects › Erp", path: home + "/Projetos/acme/projects/erp",
                           projects: [ProjectEntry(name: "Dois", path: dois)]),
        ], "pastas diferentes não se misturam por terem o mesmo nome")
    }

    func testWorktreesAreListedApartFromTheProjects() {
        let api = makeRepository("Projetos/acme/api")
        let chamado = makeWorktree("Projetos/acme/api-431", of: api)
        makeRepository("Projetos/acme/api-431/libs/interna")
        let erp = makeRepository("Projetos/acme/sistemas/erp")
        let ajuste = makeWorktree("Projetos/acme/sistemas/erp-ajuste", of: erp)

        let found = groups()
        XCTAssertEqual(found.first?.projects, [ProjectEntry(name: "Api", path: api)],
                       "a worktree é um branch do projeto, não outro projeto; a busca não entra nela")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "Sistemas", path: home + "/Projetos/acme/sistemas",
                           projects: [ProjectEntry(name: "Erp", path: erp)]),
        ])
        XCTAssertEqual(found.first?.worktrees, [
            ProjectEntry(name: "Api 431", path: chamado), ProjectEntry(name: "Erp Ajuste", path: ajuste),
        ], "as de todos os níveis saem juntas")
        XCTAssertEqual(found.first?.others.map(\.name), ["Sistemas"])
    }

    func testCompanyWithOnlyWorktreesIsNotBare() {
        makeWorktree("Projetos/acme/api-431", of: "/outro/disco/api")

        XCTAssertEqual(groups().first?.worktrees.map(\.name), ["Api 431"])
        XCTAssertEqual(groups().first?.isBare, false)
    }

    func testGitFileThatIsNotAWorktreeIsStillAProject() {
        // Submódulo e clone com a pasta do git em outro lugar também têm o `.git` em arquivo.
        temp.write("Projetos/acme/modulo/.git", "gitdir: ../.git/modules/modulo\n")
        temp.write("Projetos/acme/separado/.git", "gitdir: /Volumes/git/separado.git\n")
        temp.write("Projetos/acme/estranho/.git", "nada do que se espera\n")
        temp.write("Projetos/acme/vazio/.git", "")

        let found = groups()
        XCTAssertEqual(found.first?.projects.map(\.name), ["Estranho", "Modulo", "Separado", "Vazio"])
        XCTAssertEqual(found.first?.worktrees, [])
    }

    func testNicknamedWorktreeStaysWithTheNicknamed() {
        let api = makeRepository("Projetos/acme/api")
        let chamado = makeWorktree("Projetos/acme/api-431", of: api)

        let found = groups(nicknames: [chamado: "Chamado 431"])
        XCTAssertEqual(found.first?.nicknamed, [ProjectEntry(name: "Chamado 431", path: chamado)])
        XCTAssertEqual(found.first?.worktrees, [], "o apelidado não aparece duas vezes")
    }

    func testSearchStopsAtARepositoryAndAtFourLevels() {
        makeRepository("Projetos/acme/api")
        makeRepository("Projetos/acme/api/libs/interna")
        let fundo = makeRepository("Projetos/acme/a/b/c/d")
        makeRepository("Projetos/acme/a/b/c/x/fundo-demais")

        let found = groups()
        XCTAssertEqual(found.first?.projects.map(\.name), ["Api"], "o que está dentro de um repositório é dele")
        XCTAssertEqual(found.first?.sections, [
            ProjectSection(title: "C", path: home + "/Projetos/acme/a/b/c",
                           projects: [ProjectEntry(name: "D", path: fundo)]),
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
            ProjectSection(title: "Sistemas", path: home + "/Projetos/acme/sistemas",
                           projects: [ProjectEntry(name: "Vendas", path: vendas)]),
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
                         sections: [ProjectSection(title: "Acme", path: home + "/Projetos/acme",
                                                   projects: [ProjectEntry(name: "Api", path: api)])],
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
            ProjectSection(title: "Grupo", path: home + "/Projetos/acme/grupo",
                           projects: [ProjectEntry(name: "Api", path: api)]),
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
            ProjectSection(title: "Perto", path: home + "/Projetos/acme/perto",
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
