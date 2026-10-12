/// Contas da grade de painéis, iguais às de `_layout_grid` do original.
public enum GridLayout {
    public struct Cell: Equatable, Sendable {
        public let row: Int
        public let column: Int
        /// Quantas colunas o painel ocupa. O último painel ocupa o resto da linha.
        public let span: Int
    }

    public struct Frame: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    /// Colunas para `count` painéis numa janela de `width` por `height`.
    public static func columns(count: Int, width: Double, height: Double) -> Int {
        guard count > 0 else { return 0 }
        if count <= 3 && width / max(1, height) > 1.5 { return count }
        return Int(Double(count).squareRoot().rounded(.up))
    }

    public static func cells(count: Int, columns: Int) -> [Cell] {
        guard count > 0, columns > 0 else { return [] }
        return (0..<count).map { index in
            let column = index % columns
            return Cell(row: index / columns, column: column, span: index == count - 1 ? columns - column : 1)
        }
    }

    /// Retângulos dos painéis numa área de `width` por `height`, origem no canto superior esquerdo.
    public static func frames(count: Int, columns: Int, width: Double, height: Double, spacing: Double) -> [Frame] {
        let cells = cells(count: count, columns: columns)
        guard let last = cells.last else { return [] }
        let rows = last.row + 1
        let cellWidth = max(1, ((width - spacing * Double(columns - 1)) / Double(columns)).rounded(.down))
        let cellHeight = max(1, ((height - spacing * Double(rows - 1)) / Double(rows)).rounded(.down))
        return cells.map { cell in
            Frame(x: Double(cell.column) * (cellWidth + spacing),
                  y: Double(cell.row) * (cellHeight + spacing),
                  width: cellWidth * Double(cell.span) + spacing * Double(cell.span - 1),
                  height: cellHeight)
        }
    }
}
