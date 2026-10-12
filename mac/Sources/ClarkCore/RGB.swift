import Foundation

/// Cor em componentes de 0 a 1, sem depender de AppKit.
public struct RGB: Equatable, Hashable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 1, g: 1, b: 1)

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Aceita `#rrggbb` ou `rrggbb`. Qualquer outra forma devolve nil.
    public init?(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        let bytes = Array(digits.utf8)
        guard bytes.count == 6 else { return nil }
        var values: [Double] = []
        for i in stride(from: 0, to: 6, by: 2) {
            guard let high = RGB.nibble(bytes[i]), let low = RGB.nibble(bytes[i + 1]) else { return nil }
            values.append(Double(high * 16 + low) / 255)
        }
        self.init(r: values[0], g: values[1], b: values[2])
    }

    private static func nibble(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: return Int(byte) - 48
        case 65...70: return Int(byte) - 55
        case 97...102: return Int(byte) - 87
        default: return nil
        }
    }

    /// Interpolação linear: `t = 0` devolve esta cor, `t = 1` devolve `other`.
    public func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public func darkened(_ t: Double) -> RGB {
        mix(.black, t)
    }

    /// Luminância relativa (WCAG): 0 no preto, 1 no branco.
    public var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contraste entre as duas cores (WCAG): de 1, iguais, a 21, preto no branco.
    public func contrast(_ other: RGB) -> Double {
        let high = max(luminance, other.luminance), low = min(luminance, other.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    public var hex: String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}
