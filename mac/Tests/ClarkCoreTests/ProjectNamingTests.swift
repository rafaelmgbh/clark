import XCTest
@testable import ClarkCore

final class ProjectNamingTests: XCTestCase {
    func testTidyTurnsAFolderNameIntoATitle() {
        XCTAssertEqual(ProjectNaming.tidy("meu_projeto"), "Meu Projeto")
        XCTAssertEqual(ProjectNaming.tidy("sistemas-erp"), "Sistemas Erp")
        XCTAssertEqual(ProjectNaming.tidy("api"), "Api")
        XCTAssertEqual(ProjectNaming.tidy("ERP"), "ERP", "o que já veio em maiúsculas fica")
        XCTAssertEqual(ProjectNaming.tidy("portalWeb"), "PortalWeb")
        XCTAssertEqual(ProjectNaming.tidy("v1.2"), "V1.2")
        XCTAssertEqual(ProjectNaming.tidy("__loja__-web"), "Loja Web")
        XCTAssertEqual(ProjectNaming.tidy("área_técnica"), "Área Técnica")
        XCTAssertEqual(ProjectNaming.tidy("Meu Projeto"), "Meu Projeto")
    }

    func testNameMadeOnlyOfSeparatorsStaysAsItIs() {
        XCTAssertEqual(ProjectNaming.tidy("---"), "---")
        XCTAssertEqual(ProjectNaming.tidy("_"), "_")
        XCTAssertEqual(ProjectNaming.tidy(""), "")
    }

    func testNicknameIsTrimmedAndKeptShort() {
        XCTAssertEqual(ProjectNaming.sanitizedNickname("  Compras   Acme \n"), "Compras Acme")
        XCTAssertEqual(ProjectNaming.sanitizedNickname("Loja\tdo\u{0007} João"), "Loja do João")
        XCTAssertNil(ProjectNaming.sanitizedNickname("   "))
        XCTAssertNil(ProjectNaming.sanitizedNickname("\u{0000}\u{001b}"))
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(ProjectNaming.sanitizedNickname(long)?.count, ProjectNaming.maxNicknameLength)
    }

    private let home = "/Users/eu"

    private func name(_ path: String, nicknames: [String: String] = [:], repositories: Set<String> = []) -> String {
        ProjectNaming.name(canonicalPath: path, canonicalHome: home, nicknames: nicknames,
                           isRepository: repositories.contains)
    }

    func testHomeIsGlobal() {
        XCTAssertEqual(name(home), "GLOBAL")
        XCTAssertEqual(name(home, nicknames: [home: "Casa"]), "GLOBAL",
                       "a home é sempre o GLOBAL, mesmo com apelido gravado")
    }

    func testFolderWithoutNicknameUsesItsTidiedName() {
        XCTAssertEqual(name("/Users/eu/Projetos/acme/portal_web"), "Portal Web")
        XCTAssertEqual(name("/"), "/")
    }

    func testNicknameNamesTheFolder() {
        let compras = "/Users/eu/Projetos/acme/sistemas/compras"
        XCTAssertEqual(name(compras, nicknames: [compras: "Compras Acme"]), "Compras Acme")
        XCTAssertEqual(name("/Users/eu/Projetos/acme/sistemas/compras-novo", nicknames: [compras: "Compras Acme"]),
                       "Compras Novo", "prefixo de nome não é a mesma pasta")
    }

    func testInsideARepositoryTheProjectIsTheRepository() {
        let compras = "/Users/eu/Projetos/acme/sistemas/compras"
        let vendas = "/Users/eu/Projetos/acme/sistemas/vendas"
        let nicknames = [compras: "Compras Acme", compras + "/docs": "Manual de compras"]
        XCTAssertEqual(name(compras + "/addons/x", nicknames: nicknames, repositories: [compras, vendas]),
                       "Compras Acme", "a subpasta de um repositório apelidado é o mesmo projeto")
        XCTAssertEqual(name(vendas + "/src", nicknames: nicknames, repositories: [compras, vendas]), "Vendas")
        XCTAssertEqual(name(compras + "/docs", nicknames: nicknames, repositories: [compras, vendas]),
                       "Manual de compras", "o apelido da própria pasta vem antes")
    }

    func testNicknameOfAPlainFolderDoesNotReachTheProjectsInside() {
        // A pasta que junta vários projetos pode ter apelido sem dar o nome dela a cada um.
        let sistemas = "/Users/eu/Projetos/acme/sistemas"
        let nicknames = [sistemas: "Sistemas da Acme"]
        XCTAssertEqual(name(sistemas, nicknames: nicknames), "Sistemas da Acme")
        XCTAssertEqual(name(sistemas + "/vendas", nicknames: nicknames, repositories: [sistemas + "/vendas"]),
                       "Vendas")
        XCTAssertEqual(name(sistemas + "/rascunho", nicknames: nicknames), "Rascunho")
    }

    func testVersionedHomeDoesNotNameEverything() {
        XCTAssertEqual(name("/Users/eu/solta/pasta", repositories: [home]), "Pasta")
        XCTAssertEqual(name("/tmp/fora/da-home", repositories: ["/tmp/fora"]), "Fora")
    }

    func testNicknameGoesToTheFolderThatNamesTheProject() {
        let compras = "/Users/eu/Projetos/acme/sistemas/compras"
        func named(_ path: String, nicknames: [String: String] = [:]) -> String? {
            ProjectNaming.namedPath(canonicalPath: path, canonicalHome: home, nicknames: nicknames,
                                    isRepository: [compras].contains)
        }
        XCTAssertNil(named(home), "o GLOBAL não recebe apelido")
        XCTAssertEqual(named(compras), compras)
        XCTAssertEqual(named(compras + "/addons/x"), compras, "dentro do repositório, o apelido é do repositório")
        XCTAssertEqual(named(compras + "/docs", nicknames: [compras + "/docs": "Manual"]), compras + "/docs",
                       "a pasta que já tem apelido fica com o dela")
        XCTAssertEqual(named("/Users/eu/Projetos/acme/rascunho"), "/Users/eu/Projetos/acme/rascunho")
        XCTAssertEqual(named("/"), "/")
    }

    func testNicknamesAreCanonicalizedOnce() {
        let canonical = ProjectNaming.canonical(["~/atalho": "Loja", "/x/y": "Outro", "": "vazio"]) { path in
            path == "~/atalho" ? "/real/loja" : path
        }
        XCTAssertEqual(canonical, ["/real/loja": "Loja", "/x/y": "Outro"])
    }
}
