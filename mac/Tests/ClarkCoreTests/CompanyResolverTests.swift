import XCTest
@testable import ClarkCore

final class CompanyResolverTests: XCTestCase {
    private let home = "/Users/eu"
    private let palette = Theme.dark.agents
    private let fallback = Theme.dark.dim

    private func resolver(_ json: String?) -> CompanyResolver {
        CompanyResolver(json: json.map { Data($0.utf8) }, palette: palette, fallbackColor: fallback) {
            PathTools.absolute($0, base: "/", home: self.home)
        }
    }

    func testWithoutFileTheFirstFolderUnderProjetosIsTheCompany() {
        let resolver = resolver(nil)
        let company = resolver.resolve(canonicalPath: "/Users/eu/Projetos/EmpresaA/api/src")
        XCTAssertEqual(company.name, "EmpresaA")
        XCTAssertEqual(company.color, palette[CompanyResolver.stableIndex("EmpresaA", count: palette.count)])
        XCTAssertEqual(company.envAllow, [])
        XCTAssertTrue(resolver.warnings.isEmpty)
        XCTAssertTrue(resolver.globalEnvAllow.isEmpty)
    }

    func testOutsideTheRootsIsAvulso() {
        let resolver = resolver(nil)
        for path in ["/Users/eu/Projetos", "/Users/eu/Documents/x", "/", "/Users/eu/ProjetosX/y"] {
            let company = resolver.resolve(canonicalPath: path)
            XCTAssertEqual(company.name, CompanyResolver.fallbackName, path)
            XCTAssertEqual(company.color, fallback, path)
        }
    }

    func testLongestExplicitPrefixWins() {
        let resolver = resolver("""
        {"companies": [
          {"name": "A", "paths": ["~/Projetos/A"], "color": "#5fb3b3", "env_allow": ["A_API_KEY"]},
          {"name": "B", "paths": ["~/Projetos/A/sub", "/opt/b"]}
        ]}
        """)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/sub/x").name, "B")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/opt/b").name, "B")
        let a = resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/outro")
        XCTAssertEqual(a.name, "A")
        XCTAssertEqual(a.color.hex, "#5fb3b3")
        XCTAssertEqual(a.envAllow, ["A_API_KEY"])
        XCTAssertTrue(resolver.warnings.isEmpty)
    }

    func testExplicitPrefixStopsAtTheFolderBoundary() {
        let resolver = resolver(#"{"companies": [{"name": "A", "paths": ["~/Projetos/A"], "env_allow": ["A_KEY"]}]}"#)
        let other = resolver.resolve(canonicalPath: "/Users/eu/Projetos/AB/api")
        XCTAssertEqual(other.name, "AB")
        XCTAssertEqual(other.envAllow, [])
    }

    func testDetectedCompanyNeverInheritsEnvAllowByName() {
        let resolver = resolver(#"{"companies": [{"name": "X", "paths": ["~/work/x"], "env_allow": ["X_KEY"]}]}"#)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/x/api").envAllow, ["X_KEY"])
        let detected = resolver.resolve(canonicalPath: "/Users/eu/Projetos/X/api")
        XCTAssertEqual(detected.name, "X")
        XCTAssertEqual(detected.envAllow, [])
    }

    func testCustomRootsAndTheDeepestRootWins() {
        let resolver = resolver(#"{"roots": ["~/work", "~/work/clientes"]}"#)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/clientes/acme/api").name, "acme")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/interno/api").name, "interno")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A").name, CompanyResolver.fallbackName)
    }

    func testCompanyPathThatCoversARootWarns() {
        // `~` ou a própria root como path: a empresa engole as pastas de todas as outras,
        // e o `env_allow` dela chega aos agentes de qualquer uma.
        let resolver = resolver("""
        {"roots": ["~/Projetos", "~/work"], "companies": [
          {"name": "Tudo", "paths": ["~", "~/Projetos"], "env_allow": ["TUDO_KEY"]},
          {"name": "A", "paths": ["~/Projetos/A"]},
          {"name": "W", "paths": ["~/work"]}
        ]}
        """)
        XCTAssertEqual(resolver.warnings, [
            "companies.json: path da empresa 1 cobre uma root inteira",
            "companies.json: path da empresa 3 cobre uma root inteira",
        ])
        // O aviso não muda a regra: o path explícito continua valendo.
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/B/api").envAllow, ["TUDO_KEY"])
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/api").name, "A")
    }

    func testBrokenEntriesAreIgnoredWithWarnings() {
        let resolver = resolver("""
        {"roots": "~/Projetos", "env_allow": "X", "companies": [
          {"paths": ["~/a"]},
          {"name": "  ", "paths": ["~/b"]},
          {"name": "SemPasta"},
          {"name": "Raiz", "paths": ["/"]},
          {"name": "Cor", "paths": ["~/cor"], "color": "vermelho"},
          "texto"
        ]}
        """)
        XCTAssertEqual(resolver.warnings.count, 8)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/a").name, CompanyResolver.fallbackName)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/etc").name, CompanyResolver.fallbackName)
        let colored = resolver.resolve(canonicalPath: "/Users/eu/cor")
        XCTAssertEqual(colored.name, "Cor")
        XCTAssertEqual(colored.color, palette[CompanyResolver.stableIndex("Cor", count: palette.count)])
        // roots inválido mantém o padrão
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/Z/x").name, "Z")
    }

    func testRootOfTheDiskIsNeverARoot() {
        let resolver = resolver(#"{"roots": ["/"]}"#)
        XCTAssertEqual(resolver.warnings.count, 1)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/etc/x").name, CompanyResolver.fallbackName)
    }

    func testInvalidJSONKeepsAutomaticDetection() {
        for bad in ["{", "[]", "", "42"] {
            let resolver = resolver(bad)
            XCTAssertEqual(resolver.warnings.count, 1, bad)
            XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/x").name, "A", bad)
        }
    }

    func testEnvAllowKeepsOnlyValidNamesAndWarningsNeverEchoValues() {
        let resolver = resolver("""
        {"env_allow": ["OK_NAME", "sk-segredo colado", 3, "CLAUDECODE"],
         "companies": [{"name": "A", "paths": ["~/a"], "env_allow": ["A_KEY", "tambem-segredo", "CLAUDE_CODE_SESSION_ID"]}]}
        """)
        XCTAssertEqual(resolver.globalEnvAllow, ["OK_NAME"])
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/a").envAllow, ["A_KEY"])
        XCTAssertEqual(resolver.warnings.count, 5)
        let text = resolver.warnings.joined(separator: "\n")
        XCTAssertFalse(text.contains("segredo"))
    }

    func testStableIndexDoesNotChangeBetweenRuns() {
        XCTAssertEqual(CompanyResolver.stableIndex("a", count: 8), 4)
        XCTAssertEqual(CompanyResolver.stableIndex("", count: 8), 5)
        XCTAssertEqual(CompanyResolver.stableIndex("qualquer", count: 0), 0)
        let precomposed = "Ação".precomposedStringWithCanonicalMapping
        let decomposed = "Ação".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(precomposed.utf8), Array(decomposed.utf8))
        XCTAssertEqual(CompanyResolver.stableIndex(precomposed, count: 8),
                       CompanyResolver.stableIndex(decomposed, count: 8))
    }

    func testEmptyPaletteUsesTheFallbackColor() {
        let resolver = CompanyResolver(json: nil, palette: [], fallbackColor: fallback) {
            PathTools.absolute($0, base: "/", home: self.home)
        }
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/x").color, fallback)
    }

    func testToneDarkensInFourSteps() {
        let base = RGB(hex: "#5fb3b3")!
        XCTAssertEqual(CompanyResolver.tone(base, index: 0), base)
        XCTAssertEqual(CompanyResolver.tone(base, index: 1), base.darkened(0.15))
        XCTAssertEqual(CompanyResolver.tone(base, index: 3), base.darkened(0.15 * 3))
        XCTAssertEqual(CompanyResolver.tone(base, index: 4), base)
        XCTAssertEqual(CompanyResolver.tone(base, index: -1), base.darkened(0.15 * 3))
    }
}
