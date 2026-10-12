import AppKit
import ClarkCore
import XCTest
@testable import Clark

final class AppIconTests: XCTestCase {
    private let theme = Theme.dark

    /// Pixels do ícone em RGBA, com a origem em cima à esquerda.
    private struct Pixels {
        let size: Int
        private let bytes: [UInt8]

        init?(size: Int) {
            guard let image = AppIcon.image(size: size), image.width == size, image.height == size,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            self.size = size
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                              count: size * size * 4))
        }

        func component(_ index: Int, _ x: Int, _ y: Int) -> Int { Int(bytes[(y * size + x) * 4 + index]) }
        func alpha(_ x: Int, _ y: Int) -> Int { component(3, x, y) }

        /// Pixel opaco desta cor, com folga de 1 em cada componente.
        func isColor(_ color: RGB, _ point: (x: Int, y: Int)) -> Bool {
            let wanted = [color.r, color.g, color.b].map { Int(($0 * 255).rounded()) }
            return alpha(point.x, point.y) == 255
                && wanted.enumerated().allSatisfy { abs(component($0.offset, point.x, point.y) - $0.element) <= 1 }
        }
    }

    func testEverySizeIsASquareWithTransparentCorners() throws {
        for size in AppIcon.sizes {
            let pixels = try XCTUnwrap(Pixels(size: size), "tamanho \(size)")
            for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
                XCTAssertEqual(pixels.alpha(x, y), 0, "canto do ícone de \(size)")
            }
            XCTAssertEqual(pixels.alpha(size / 2, size / 2), 255, "meio do ícone de \(size)")
        }
        XCTAssertEqual(AppIcon.sizes, [16, 32, 64, 128, 256, 512, 1024], "os tamanhos que o .icns leva")
    }

    func testPlateFollowsTheMacIconGrid() throws {
        // Placa de 824 num quadro de 1024, como os ícones do sistema: fora dela só a sombra, embaixo.
        let pixels = try XCTUnwrap(Pixels(size: 1024))
        for (x, y) in [(512, 104), (104, 512), (919, 512), (512, 919)] {
            XCTAssertEqual(pixels.alpha(x, y), 255, "dentro da placa: \(x), \(y)")
        }
        for (x, y) in [(512, 60), (60, 512), (963, 512), (112, 112)] {
            XCTAssertEqual(pixels.alpha(x, y), 0, "fora da placa: \(x), \(y)")
        }
        XCTAssertGreaterThan(pixels.alpha(512, 932), 0, "sombra embaixo da placa")
        XCTAssertLessThan(pixels.alpha(512, 932), 255)
    }

    func testDragonUsesTheAccentColorAndBreathesFire() throws {
        let pixels = try XCTUnwrap(Pixels(size: 1024))
        // Sprite de 20 por 12 células de 34 px, com o canto em (172, 325).
        func cell(_ column: Int, _ row: Int) -> (x: Int, y: Int) { (172 + column * 34 + 17, 325 + row * 34 + 17) }
        XCTAssertTrue(pixels.isColor(theme.accent, cell(9, 3)), "cabeça")
        XCTAssertTrue(pixels.isColor(theme.accent.mix(.white, 0.3), cell(7, 7)), "barriga")
        XCTAssertTrue(pixels.isColor(theme.accent.mix(.black, 0.3), cell(1, 1)), "asa levantada")
        XCTAssertTrue(pixels.isColor(theme.shadow, cell(13, 2)), "olho")
        XCTAssertTrue(pixels.isColor(RGB(hex: "#ff6b35")!, cell(15, 4)), "fogo na boca")
        XCTAssertTrue(pixels.isColor(theme.yellow, cell(16, 4)), "fogo")
        XCTAssertTrue(pixels.isColor(theme.shadow, cell(8, 3)), "contorno em volta do dragão")
        XCTAssertTrue(pixels.isColor(.white, (172 + 13 * 34 + 3, 325 + 2 * 34 + 3)), "brilho no olho")
    }

    func testTinyIconKeepsTheDragonInsideThePlate() throws {
        // A 16 px não cabe uma célula por pixel: o desenho grande é reduzido, em vez de vazar do quadro.
        let pixels = try XCTUnwrap(Pixels(size: 16))
        for y in 0..<16 {
            XCTAssertEqual(pixels.alpha(0, y), 0, "coluna da esquerda, linha \(y)")
            XCTAssertEqual(pixels.alpha(15, y), 0, "coluna da direita, linha \(y)")
        }
        var orange = 0
        for y in 0..<16 {
            for x in 0..<16 where pixels.component(0, x, y) > 150 && pixels.component(2, x, y) < 120 { orange += 1 }
        }
        XCTAssertGreaterThan(orange, 3, "o dragão ainda aparece")
    }

    func testPNGHasTheRequestedSize() throws {
        let data = try XCTUnwrap(AppIcon.png(size: 64))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual([image.pixelsWide, image.pixelsHigh], [64, 64])
        XCTAssertTrue(image.hasAlpha)
    }
}
