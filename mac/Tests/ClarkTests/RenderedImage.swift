import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// Desenho de uma vista num bitmap próprio, lido com a origem em cima à esquerda.
struct RenderedImage: Equatable {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    /// - Parameter dirty: desenha pelo `draw`, como o AppKit faz, pedindo só este retângulo.
    init(_ view: PixelView, width: Int, height: Int, dirty: NSRect? = nil, file: StaticString = #filePath,
         line: UInt = #line) {
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        self.init(width: width, height: height, flipped: true, file: file, line: line) { context in
            if let dirty {
                view.draw(dirty)
            } else {
                view.render(context, width: width, height: height)
            }
        }
    }

    /// Desenho de uma vista comum, com a origem embaixo, pelo `draw` dela.
    init(drawing view: NSView, width: Int, height: Int, file: StaticString = #filePath, line: UInt = #line) {
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        self.init(width: width, height: height, flipped: false, file: file, line: line) { _ in
            view.draw(view.bounds)
        }
    }

    private init(width: Int, height: Int, flipped: Bool, file: StaticString, line: UInt,
                 draw: (CGContext) -> Void) {
        self.width = width
        self.height = height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            XCTFail("não criou o bitmap", file: file, line: line)
            bytes = []
            bytesPerRow = 0
            return
        }
        if flipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.setShouldAntialias(false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        draw(context)
        NSGraphicsContext.current = previous
        bytesPerRow = context.bytesPerRow
        if let data = context.data {
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                              count: bytesPerRow * height))
        } else {
            bytes = []
        }
    }

    private static func bytes(of color: RGB) -> [Int] {
        [color.r, color.g, color.b].map { Int(($0 * 255).rounded()) }
    }

    /// O pixel tem esta cor, com folga de 1 em cada componente.
    func isColor(_ color: RGB, atX x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height, !bytes.isEmpty else { return false }
        let offset = y * bytesPerRow + x * 4
        return zip(Self.bytes(of: color), 0..<3).allSatisfy { abs(Int(bytes[offset + $0.1]) - $0.0) <= 1 }
    }

    /// Quantos pixels do retângulo têm esta cor.
    func count(_ color: RGB, x: Int = 0, y: Int = 0, width: Int? = nil, height: Int? = nil) -> Int {
        let maxX = min(self.width, x + (width ?? self.width)), maxY = min(self.height, y + (height ?? self.height))
        var total = 0
        for row in max(0, y)..<max(max(0, y), maxY) {
            for column in max(0, x)..<max(max(0, x), maxX) where isColor(color, atX: column, y: row) {
                total += 1
            }
        }
        return total
    }
}
