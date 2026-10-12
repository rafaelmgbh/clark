/// Dragão mascote do CLARK em pixel art, de perfil e olhando para a direita (`mascot_rows` do original).
/// Cada letra é uma célula: O corpo, H barriga e topo da cabeça, D asa e chifres, K olho, F e Y fogo.
public enum Mascot {
    /// Pose do ícone: asas levantadas, cuspindo fogo. As outras poses chegam com o mascote animado, no M3.
    public static let breathingFire = [
        "D.........D..D......",
        "DD.......HHHHHH.....",
        ".DD......OOOOKOO....",
        ".DDD.....OOOOOOO.Y..",
        "..DDD....OOOOODFYYFY",
        "...DDD..OOOOO....FY.",
        "....DDOOOOOO........",
        "...DDOHHHHOO........",
        "OO..OOHHHHOO........",
        ".OOOOOOOOOOO........",
        "....DD...DD.........",
        "....DD...DD.........",
    ]

    /// Cor de cada letra do sprite (`sprite_pal` do original). O `.` é vazio e fica de fora.
    public static func palette(base: RGB, theme: Theme) -> [Character: RGB] {
        ["O": base, "H": base.mix(.white, 0.3), "D": base.mix(.black, 0.3), "K": theme.shadow,
         "F": RGB(r: 1, g: 107.0 / 255, b: 53.0 / 255), "Y": theme.yellow]
    }
}
