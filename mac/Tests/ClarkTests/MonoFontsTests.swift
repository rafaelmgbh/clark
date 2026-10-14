import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// A fonte monoespaçada do texto desenhado à mão. O AppKit já devolveu nil no lugar dela, e o nil
/// derrubou o app dentro do CoreText.
final class MonoFontsTests: XCTestCase {
    private let menlo = NSFont(name: "Menlo-Regular", size: 11)!
    private let menloBold = NSFont(name: "Menlo-Bold", size: 11)!

    func testFontThatCameRightIsNotAskedAgain() {
        var asked = 0
        let fonts = MonoFonts(system: { _, _ in asked += 1; return self.menloBold }, fallback: { _, _ in nil })
        XCTAssertTrue(fonts.font(size: 11, bold: true) === menloBold)
        XCTAssertTrue(fonts.font(size: 11, bold: true) === menloBold)
        XCTAssertEqual(asked, 1)
    }

    func testEachSizeAndWeightHasItsOwnFont() {
        var asked: [String] = []
        let fonts = MonoFonts(system: { size, weight in
            asked.append("\(Int(size)) \(weight == .heavy ? "heavy" : "regular")")
            return self.menlo
        }, fallback: { _, _ in nil })
        _ = fonts.font(size: 11, bold: true)
        _ = fonts.font(size: 10, bold: true)
        _ = fonts.font(size: 11, bold: false)
        _ = fonts.font(size: 11, bold: true)
        XCTAssertEqual(asked, ["11 heavy", "10 heavy", "11 regular"])
    }

    func testWithoutTheSystemFontTheFallbackIsUsedAndTheSystemIsAskedAgain() {
        var answers: [NSFont?] = [nil, menloBold]
        let fonts = MonoFonts(system: { _, _ in answers.removeFirst() }, fallback: { _, _ in self.menlo })
        XCTAssertTrue(fonts.font(size: 11, bold: true) === menlo)
        XCTAssertTrue(fonts.font(size: 11, bold: true) === menloBold)
        XCTAssertTrue(fonts.font(size: 11, bold: true) === menloBold)
    }

    func testWithoutAnyFontTheWidthIsEstimated() {
        let none = MonoFonts(system: { _, _ in nil }, fallback: { _, _ in nil })
        XCTAssertNil(none.font(size: 11, bold: true))
        XCTAssertEqual(Pixel.monoWidth("PROJETO", size: 10, bold: true, fonts: none), 42)
        XCTAssertEqual(Pixel.monoLineHeight(size: 10, bold: true, fonts: none), 12)
    }

    func testWithoutAnyFontTheTextIsStillDrawn() throws {
        let none = MonoFonts(system: { _, _ in nil }, fallback: { _, _ in nil })
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        Pixel.mono(context, "PROJETO", 0, 0, width: 80, size: 11, RGB(r: 1, g: 1, b: 1), bold: true, fonts: none)
        NSGraphicsContext.restoreGraphicsState()
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let painted = (0..<(context.bytesPerRow * 20)).contains { pixels[$0] != 0 }
        XCTAssertTrue(painted)
    }

    /// A fonte de verdade, pedida ao AppKit pelo caminho que enxerga um nil.
    func testSystemSourceGivesTheMonospacedSystemFont() throws {
        let font = try XCTUnwrap(MonoFonts.systemFont(size: 11, weight: .heavy))
        XCTAssertEqual(font.pointSize, 11)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertEqual(font.fontName, NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy).fontName)
    }

    func testFallbackIsMenloInTheRightWeight() throws {
        XCTAssertEqual(try XCTUnwrap(MonoFonts.fixedPitchFont(size: 11, weight: .heavy)).fontName, "Menlo-Bold")
        XCTAssertEqual(try XCTUnwrap(MonoFonts.fixedPitchFont(size: 11, weight: .regular)).fontName, "Menlo-Regular")
    }

    func testTheSharedFontsMeasureLikeTheSystemFont() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        let expected = Int(("PROJETO" as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
        XCTAssertEqual(Pixel.monoWidth("PROJETO", size: 11, bold: true), expected)
        XCTAssertEqual(Pixel.monoLineHeight(size: 11, bold: true),
                       Int((font.ascender - font.descender + font.leading).rounded(.up)))
    }
}
