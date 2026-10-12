// O tema só tem construtor dentro do núcleo.
@testable import ClarkCore

extension Theme {
    /// Um tema que não é o `dark`, para conferir que a troca de tema chega aonde deve.
    static let swapped = Theme(name: "outro", bg: dark.bg2, bg2: dark.bg, bg3: dark.bg3, bg4: dark.bg4, bg5: dark.bg5,
                               shadow: dark.shadow, ink: dark.ink, dim: dark.dim, accent: dark.accent,
                               accentHi: dark.accentHi, accentLo: dark.accentLo, onAccent: dark.onAccent,
                               yellow: dark.yellow, green: dark.green, red: dark.red, agents: dark.agents,
                               term: dark.term)
}
