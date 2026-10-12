import AppKit
import ClarkCore

/// Ícone do app: o dragão do CLARK numa placa escura (`make_icon_surface` do original),
/// na grade dos ícones do macOS.
enum AppIcon {
    /// Lados, em pixels, que o `.icns` leva.
    static let sizes = [16, 32, 64, 128, 256, 512, 1024]
    /// Abaixo deste lado a célula do sprite ficaria menor que um pixel.
    private static let smallestDrawn = 128

    static func png(size: Int) -> Data? {
        image(size: size).flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    static func image(size: Int, theme: Theme = .dark) -> CGImage? {
        guard size > 0 else { return nil }
        if size >= smallestDrawn {
            guard let context = bitmap(size) else { return nil }
            draw(in: context, size: size, theme: theme)
            return context.makeImage()
        }
        // Tamanho pequeno: o desenho grande, reduzido. O dragão vira uma mancha, mas não vaza da placa.
        let factor = (smallestDrawn + size - 1) / size
        guard let big = image(size: size * factor, theme: theme), let context = bitmap(size) else { return nil }
        context.interpolationQuality = .high
        context.draw(big, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }

    private static func bitmap(_ size: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func color(_ rgb: RGB, _ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    private static func rounded(_ rect: CGRect, _ radius: Double) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func draw(in context: CGContext, size: Int, theme: Theme) {
        let side = Double(size)
        // Origem em cima à esquerda, como no desenho do original.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)

        // Grade do macOS: placa de 824 num quadro de 1024, com 22,5% de raio. Fora disso o sistema
        // encolhe o ícone e o põe numa moldura cinza.
        let margin = (side * 100 / 1024).rounded()
        let width = side - 2 * margin
        let radius = width * 0.225
        let plate = CGRect(x: margin, y: margin, width: width, height: width)

        // Sombra da placa. O deslocamento da sombra não segue a inversão do eixo: negativo é para baixo.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.02,
                          color: color(.black, 0.3))
        context.addPath(rounded(plate, radius))
        context.setFillColor(color(theme.shadow))
        context.fillPath()
        context.restoreGState()

        // Placa: degradê quente, brilho laranja atrás do dragão e as linhas de um tubo de imagem.
        context.saveGState()
        context.addPath(rounded(plate, radius))
        context.clip()
        if let space = CGColorSpace(name: CGColorSpace.sRGB) {
            let warm = [color(theme.bg3.mix(theme.accent, 0.12)), color(theme.shadow)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: warm, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: margin),
                                           end: CGPoint(x: 0, y: margin + width), options: [])
            }
            let glow = [color(theme.accent, 0.38), color(theme.accent, 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
                let center = CGPoint(x: side / 2, y: side / 2)
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                           endRadius: width * 0.55, options: [])
            }
        }
        let line = max(2, size / 64)
        context.setFillColor(color(.black, 0.13))
        for y in stride(from: Int(margin), to: Int(margin + width), by: line * 2) {
            context.fill(CGRect(x: margin, y: Double(y), width: width, height: Double(line)))
        }
        context.restoreGState()

        // Bordas: filete de luz por fora, contorno escuro por dentro.
        let stroke = max(1, side / 96)
        context.setLineWidth(stroke)
        context.addPath(rounded(plate.insetBy(dx: stroke / 2, dy: stroke / 2), radius - stroke / 2))
        context.setStrokeColor(color(theme.accent.mix(.white, 0.2), 0.35))
        context.strokePath()
        context.addPath(rounded(plate.insetBy(dx: stroke * 1.5, dy: stroke * 1.5), radius - stroke * 1.5))
        context.setStrokeColor(color(theme.shadow, 0.6))
        context.strokePath()

        // O dragão, em células inteiras: duas colunas de folga de cada lado.
        let rows = Mascot.breathingFire.map(Array.init)
        let columns = rows.map(\.count).max() ?? 0
        let palette = Mascot.palette(base: theme.accent, theme: theme)
        let cell = max(1, Int(width / Double(columns + 4)))
        let left = (size - columns * cell) / 2
        let top = (size - rows.count * cell) / 2 + cell / 2
        func square(_ column: Int, _ row: Int) -> CGRect {
            CGRect(x: left + column * cell, y: top + row * cell, width: cell, height: cell)
        }

        // Sombra no chão, debaixo das patas.
        context.setFillColor(color(.black, 0.35))
        context.fillEllipse(in: CGRect(x: Double(left) + 1.0 * Double(cell),
                                       y: Double(top + rows.count * cell) - 0.5 * Double(cell),
                                       width: 13.0 * Double(cell), height: 2.2 * Double(cell)))

        context.setShouldAntialias(false)
        var filled: Set<[Int]> = []
        for (row, cells) in rows.enumerated() {
            for (column, letter) in cells.enumerated() where palette[letter] != nil { filled.insert([column, row]) }
        }
        context.setFillColor(color(theme.shadow))
        for position in filled {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]
            where !filled.contains([position[0] + dx, position[1] + dy]) {
                context.fill(square(position[0] + dx, position[1] + dy))
            }
        }
        for (row, cells) in rows.enumerated() {
            for (column, letter) in cells.enumerated() {
                guard let tint = palette[letter] else { continue }
                context.setFillColor(color(tint))
                context.fill(square(column, row))
                // Brilho no olho.
                if letter == "K" {
                    let glint = max(1, cell / 3)
                    context.setFillColor(color(.white))
                    context.fill(CGRect(x: left + column * cell, y: top + row * cell, width: glint, height: glint))
                }
            }
        }

        // Faíscas em cruz, nos vãos que o dragão deixa na placa.
        let sparks: [(x: Double, y: Double, scale: Double, tint: RGB)] = [
            (0.18, 0.20, 1.0, theme.yellow), (0.84, 0.18, 0.7, theme.ink), (0.82, 0.72, 0.6, theme.accent),
        ]
        for spark in sparks {
            let arm = max(1, Int(Double(cell) * 0.6 * spark.scale))
            let x = Int(margin + width * spark.x), y = Int(margin + width * spark.y)
            context.setFillColor(color(spark.tint, 0.9))
            context.fill(CGRect(x: x, y: y - arm, width: arm, height: arm * 3))
            context.fill(CGRect(x: x - arm, y: y, width: arm * 3, height: arm))
        }
    }
}
