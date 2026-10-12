import XCTest
@testable import ClarkCore

final class PixelFontTests: XCTestCase {
    private let supported = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .:-!?/+><_%'()[]#*=,"

    private func points(_ text: String) -> [[Int]] {
        PixelFont.pixels(text).map { [$0.x, $0.y] }
    }

    func testNormalizeStripsAccentsAndUppercases() {
        XCTAssertEqual(PixelFont.normalize("Ação é"), "ACAO E")
        XCTAssertEqual(PixelFont.normalize("agent 1"), "AGENT 1")
        XCTAssertEqual(PixelFont.normalize("日本"), "")
    }

    func testTextWidthFollowsTheOriginalFormula() {
        XCTAssertEqual(PixelFont.textWidth("", scale: 2), 0)
        XCTAssertEqual(PixelFont.textWidth("A", scale: 1), 5)
        XCTAssertEqual(PixelFont.textWidth("AB", scale: 2), 22)
        XCTAssertEqual(PixelFont.textWidth("é", scale: 1), 5)
    }

    func testFitKeepsTextThatFits() {
        XCTAssertEqual(PixelFont.fit("agent 1", scale: 2, width: 200), "AGENT 1")
    }

    func testFitCutsWithEllipsis() {
        let cut = PixelFont.fit("ABCDEFGHIJKL", scale: 1, width: 40)
        XCTAssertEqual(cut, "ABC...")
        XCTAssertLessThanOrEqual(PixelFont.textWidth(cut, scale: 1), 40)
    }

    func testFitDropsTrailingSpaceBeforeEllipsis() {
        XCTAssertEqual(PixelFont.fit("AB  CDEFGHIJ", scale: 1, width: 40), "AB...")
    }

    func testFitWithNoRoomIsOnlyEllipsis() {
        XCTAssertEqual(PixelFont.fit("ABCDEF", scale: 1, width: 5), "...")
        XCTAssertEqual(PixelFont.fit("ABCDEF", scale: 2, width: 0), "...")
    }

    func testGlyphPixels() {
        let glyph = points("I")
        XCTAssertEqual(glyph.count, 11)
        XCTAssertEqual(glyph.filter { $0[1] == 0 }.map { $0[0] }, [1, 2, 3])
        XCTAssertTrue(points(" ").isEmpty)
        XCTAssertEqual(points("a"), points("A"))
    }

    func testSecondCharacterIsShiftedByTheAdvance() {
        let single = points("L")
        let double = points("LL")
        XCTAssertEqual(double.count, single.count * 2)
        XCTAssertEqual(Array(double.suffix(single.count)), single.map { [$0[0] + PixelFont.advance, $0[1]] })
    }

    func testUnknownCharacterUsesQuestionMark() {
        XCTAssertEqual(points("~"), points("?"))
        XCTAssertEqual(points("@"), points("?"))
    }

    func testEverySupportedGlyphFitsTheGrid() {
        for (index, character) in supported.enumerated() {
            for point in points(String(character)) {
                XCTAssertTrue((0..<PixelFont.columns).contains(point[0]), "\(character) em \(index)")
                XCTAssertTrue((0..<PixelFont.rows).contains(point[1]), "\(character) em \(index)")
            }
            if character != " " && character != "?" {
                XCTAssertNotEqual(points(String(character)), points("?"), "sem glifo: \(character)")
            }
        }
    }
}
