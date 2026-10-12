import XCTest
@testable import ClarkCore

final class GridLayoutTests: XCTestCase {
    func testColumnsMatchTheOriginal() {
        XCTAssertEqual(GridLayout.columns(count: 0, width: 1360, height: 700), 0)
        // até 3 painéis numa janela larga ficam lado a lado
        XCTAssertEqual(GridLayout.columns(count: 1, width: 1360, height: 700), 1)
        XCTAssertEqual(GridLayout.columns(count: 2, width: 1360, height: 700), 2)
        XCTAssertEqual(GridLayout.columns(count: 3, width: 1360, height: 700), 3)
        // janela estreita ou mais de 3: teto da raiz quadrada
        XCTAssertEqual(GridLayout.columns(count: 2, width: 800, height: 800), 2)
        XCTAssertEqual(GridLayout.columns(count: 3, width: 800, height: 800), 2)
        let expected = [4: 2, 5: 3, 6: 3, 7: 3, 8: 3, 9: 3, 10: 4, 11: 4, 12: 4, 13: 4, 14: 4, 15: 4, 16: 4]
        for (count, columns) in expected {
            XCTAssertEqual(GridLayout.columns(count: count, width: 1360, height: 700), columns, "\(count)")
        }
    }

    func testZeroHeightDoesNotDivideByZero() {
        XCTAssertEqual(GridLayout.columns(count: 2, width: 1360, height: 0), 2)
    }

    func testLastCellTakesTheRestOfTheRow() {
        XCTAssertEqual(GridLayout.cells(count: 5, columns: 3), [
            .init(row: 0, column: 0, span: 1), .init(row: 0, column: 1, span: 1), .init(row: 0, column: 2, span: 1),
            .init(row: 1, column: 0, span: 1), .init(row: 1, column: 1, span: 2),
        ])
        XCTAssertEqual(GridLayout.cells(count: 3, columns: 2).last, .init(row: 1, column: 0, span: 2))
        XCTAssertEqual(GridLayout.cells(count: 4, columns: 2).last, .init(row: 1, column: 1, span: 1))
        XCTAssertTrue(GridLayout.cells(count: 0, columns: 3).isEmpty)
        XCTAssertTrue(GridLayout.cells(count: 3, columns: 0).isEmpty)
    }

    func testFrames() {
        XCTAssertEqual(GridLayout.frames(count: 2, columns: 2, width: 206, height: 100, spacing: 6), [
            .init(x: 0, y: 0, width: 100, height: 100), .init(x: 106, y: 0, width: 100, height: 100),
        ])
        XCTAssertEqual(GridLayout.frames(count: 3, columns: 2, width: 206, height: 206, spacing: 6).last,
                       .init(x: 0, y: 106, width: 206, height: 100))
        XCTAssertTrue(GridLayout.frames(count: 0, columns: 0, width: 100, height: 100, spacing: 6).isEmpty)
    }

    func testEveryPanelFitsFromOneToSixteen() {
        for count in 1...16 {
            let columns = GridLayout.columns(count: count, width: 1360, height: 700)
            let cells = GridLayout.cells(count: count, columns: columns)
            let frames = GridLayout.frames(count: count, columns: columns, width: 1360, height: 700, spacing: 6)
            XCTAssertEqual(cells.count, count)
            XCTAssertEqual(cells.last.map { $0.column + $0.span }, columns, "\(count)")
            XCTAssertEqual(frames.count, count)
            for frame in frames {
                XCTAssertGreaterThanOrEqual(frame.width, 1)
                XCTAssertGreaterThanOrEqual(frame.height, 1)
                XCTAssertLessThanOrEqual(frame.x + frame.width, 1360, "\(count)")
                XCTAssertLessThanOrEqual(frame.y + frame.height, 700, "\(count)")
            }
        }
    }

    func testTinyAreaNeverProducesEmptyFrames() {
        for frame in GridLayout.frames(count: 16, columns: 4, width: 10, height: 10, spacing: 6) {
            XCTAssertGreaterThanOrEqual(frame.width, 1)
            XCTAssertGreaterThanOrEqual(frame.height, 1)
        }
    }
}
