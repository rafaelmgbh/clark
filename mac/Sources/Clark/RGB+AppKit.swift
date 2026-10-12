import AppKit
import ClarkCore

/// Cores do tema nos tipos do AppKit e do CoreGraphics.
extension RGB {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}
