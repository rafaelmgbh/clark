/// Paleta de um tema, portada de `THEMES` do original.
/// No M1 só existe `dark`; `white` e `magick` entram no M3.
public struct Theme: Sendable {
    /// Nomes aceitos no `config.json`.
    public static let names = ["dark", "white", "magick"]

    public let name: String
    public let bg: RGB
    public let bg2: RGB
    public let bg3: RGB
    public let bg4: RGB
    public let bg5: RGB
    public let shadow: RGB
    public let ink: RGB
    public let dim: RGB
    public let accent: RGB
    public let accentHi: RGB
    public let accentLo: RGB
    public let onAccent: RGB
    public let yellow: RGB
    public let green: RGB
    public let red: RGB
    /// Cores de empresa para a detecção automática.
    public let agents: [RGB]
    /// As 16 cores ANSI do terminal.
    public let term: [RGB]

    public static let dark = Theme(
        name: "dark",
        bg: hex("#14100e"), bg2: hex("#1f1915"), bg3: hex("#2a221d"), bg4: hex("#3a2f28"), bg5: hex("#4a3c33"),
        shadow: hex("#0a0807"), ink: hex("#f0e6d6"), dim: hex("#8a7d6e"),
        accent: hex("#d97757"), accentHi: hex("#e88a6a"), accentLo: hex("#b85c3e"), onAccent: hex("#14100e"),
        yellow: hex("#f2c14e"), green: hex("#7fc86a"), red: hex("#e05a4f"),
        agents: ["#d97757", "#5fb3b3", "#9b7bd8", "#7fc86a", "#f2c14e", "#e07aa8", "#5e9be0", "#e05a4f"].map(hex),
        term: ["#1a1410", "#e05a4f", "#7fc86a", "#f2c14e", "#5e9be0", "#b48ead", "#5fb3b3", "#d9cbb8",
               "#6b5f53", "#ff7a6b", "#a4e08f", "#ffd97a", "#8bb8f0", "#d7a8e0", "#8fd6d6", "#fff6e8"].map(hex)
    )

    /// Tema pelo nome do config. Enquanto só `dark` existe, todo nome devolve `dark`.
    public static func named(_ name: String) -> Theme {
        .dark
    }

    private static func hex(_ value: String) -> RGB {
        RGB(hex: value)!
    }
}
