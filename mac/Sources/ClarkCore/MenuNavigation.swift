/// Contas do teclado num menu desenhado pelo app.
public enum MenuNavigation {
    /// A linha que a seta alcança a partir de `current`: `step` 1 desce, -1 sobe, e no fim dá a volta.
    /// Sem linha atual, descer começa na primeira e subir, na última. nil quando nenhuma linha pode
    /// ser escolhida.
    /// - Parameter selectable: por linha, se ela pode ser escolhida. Cabeçalho e separador não podem.
    public static func next(from current: Int?, step: Int, selectable: [Bool]) -> Int? {
        let count = selectable.count
        guard count > 0, step != 0 else { return nil }
        let direction = step > 0 ? 1 : -1
        var index = current.flatMap { selectable.indices.contains($0) ? $0 : nil } ?? (direction > 0 ? -1 : count)
        for _ in 0..<count {
            index = (index + direction + count) % count
            if selectable[index] { return index }
        }
        return nil
    }

    /// Rolagem que deixa à vista a linha de `height` pontos que começa em `top`, mexendo o mínimo.
    /// - Parameters:
    ///   - offset: a rolagem atual.
    ///   - visible: quantos pontos do conteúdo aparecem.
    public static func scroll(showing top: Int, height: Int, offset: Int, visible: Int) -> Int {
        if top < offset { return top }
        if top + height > offset + visible { return top + height - visible }
        return offset
    }
}
