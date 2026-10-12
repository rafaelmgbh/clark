import XCTest
@testable import ClarkCore

final class RGBThemeTests: XCTestCase {
    func testHexParsesWithAndWithoutHash() {
        XCTAssertEqual(RGB(hex: "#ff8000")?.hex, "#ff8000")
        XCTAssertEqual(RGB(hex: "FF8000")?.hex, "#ff8000")
    }

    func testInvalidHexIsRejected() {
        for bad in ["", "#", "#fff", "#gggggg", "#ff80000", "ff 800", "#ff80é0", "##ff800"] {
            XCTAssertNil(RGB(hex: bad), bad)
        }
    }

    func testMixAndDarkened() {
        let orange = RGB(hex: "#d97757")!
        XCTAssertEqual(orange.mix(.black, 0), orange)
        XCTAssertEqual(orange.mix(.black, 1), .black)
        XCTAssertEqual(RGB.white.darkened(0.5).hex, "#808080")
    }

    func testContrastGoesFromOneToTwentyOne() {
        XCTAssertEqual(RGB.black.luminance, 0)
        XCTAssertEqual(RGB.white.luminance, 1, accuracy: 0.0001)
        XCTAssertEqual(RGB.white.contrast(.black), 21, accuracy: 0.001)
        XCTAssertEqual(RGB.black.contrast(.white), 21, accuracy: 0.001, "a ordem não importa")
        let gray = RGB(hex: "#777777")!
        XCTAssertEqual(gray.contrast(gray), 1)
        XCTAssertEqual(gray.contrast(.white), 4.48, accuracy: 0.01)
        // O verde pesa mais que o vermelho, e o azul quase nada.
        XCTAssertGreaterThan(RGB(r: 0, g: 1, b: 0).luminance, RGB(r: 1, g: 0, b: 0).luminance)
        XCTAssertGreaterThan(RGB(r: 1, g: 0, b: 0).luminance, RGB(r: 0, g: 0, b: 1).luminance)
    }

    func testDarkThemeMatchesTheOriginalPalette() {
        let theme = Theme.dark
        XCTAssertEqual(theme.bg.hex, "#14100e")
        XCTAssertEqual(theme.bg2.hex, "#1f1915")
        XCTAssertEqual(theme.ink.hex, "#f0e6d6")
        XCTAssertEqual(theme.dim.hex, "#8a7d6e")
        XCTAssertEqual(theme.accent.hex, "#d97757")
        XCTAssertEqual(theme.yellow.hex, "#f2c14e")
        XCTAssertEqual(theme.green.hex, "#7fc86a")
        XCTAssertEqual(theme.red.hex, "#e05a4f")
        XCTAssertEqual(theme.agents.map(\.hex).first, "#d97757")
        XCTAssertEqual(theme.agents.count, 8)
        XCTAssertEqual(theme.term.count, 16)
        XCTAssertEqual(theme.term[15].hex, "#fff6e8")
    }

    func testEveryThemeNameResolves() {
        for name in Theme.names + ["neon", ""] {
            XCTAssertEqual(Theme.named(name).name, "dark", name)
        }
    }
}
