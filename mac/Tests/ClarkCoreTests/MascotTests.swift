import XCTest
@testable import ClarkCore

final class MascotTests: XCTestCase {
    func testFireBreathingPoseIsAGridOfKnownCells() {
        let rows = Mascot.breathingFire
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(Set(rows.map(\.count)), [20], "todas as linhas com a mesma largura")
        XCTAssertEqual(Set(rows.joined()), Set(".ODHKFY"))
        XCTAssertEqual(rows.joined().filter { $0 == "K" }.count, 1, "um olho só: o dragão está de perfil")
    }

    func testOnlyTheFireGoesPastTheBody() {
        for row in Mascot.breathingFire {
            // A boca é a coluna 15: a primeira chama fica nela, no lugar do focinho.
            XCTAssertTrue(row.prefix(15).allSatisfy { !"FY".contains($0) }, "fogo dentro do corpo: \(row)")
            XCTAssertTrue(row.dropFirst(16).allSatisfy { ".FY".contains($0) }, "corpo fora das 16 colunas: \(row)")
        }
        XCTAssertEqual(Mascot.breathingFire[4], "..DDD....OOOOODFYYFY", "o fogo sai da boca")
    }

    func testPaletteShadesTheBaseColor() {
        let theme = Theme.dark
        let palette = Mascot.palette(base: theme.accent, theme: theme)
        XCTAssertEqual(Set(palette.keys), Set("ODHKFY"), "o vazio não tem cor")
        XCTAssertEqual(palette["O"], theme.accent)
        XCTAssertEqual(palette["H"], theme.accent.mix(.white, 0.3))
        XCTAssertEqual(palette["D"], theme.accent.mix(.black, 0.3))
        XCTAssertEqual(palette["K"], theme.shadow)
        XCTAssertEqual(palette["F"], RGB(hex: "#ff6b35"))
        XCTAssertEqual(palette["Y"], theme.yellow)
    }
}
