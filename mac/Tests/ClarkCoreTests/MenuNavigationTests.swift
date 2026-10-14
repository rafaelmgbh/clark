import XCTest
@testable import ClarkCore

final class MenuNavigationTests: XCTestCase {
    /// Cabeçalho, duas linhas, separador, uma linha.
    private let rows = [false, true, true, false, true]

    func testArrowsSkipHeadersAndSeparators() {
        XCTAssertEqual(MenuNavigation.next(from: 1, step: 1, selectable: rows), 2)
        XCTAssertEqual(MenuNavigation.next(from: 2, step: 1, selectable: rows), 4, "pula o separador")
        XCTAssertEqual(MenuNavigation.next(from: 4, step: -1, selectable: rows), 2)
    }

    func testArrowsWrapAround() {
        XCTAssertEqual(MenuNavigation.next(from: 4, step: 1, selectable: rows), 1, "do fim volta ao começo")
        XCTAssertEqual(MenuNavigation.next(from: 1, step: -1, selectable: rows), 4, "do começo vai ao fim")
    }

    func testWithoutSelectionDownStartsAtTheTopAndUpAtTheBottom() {
        XCTAssertEqual(MenuNavigation.next(from: nil, step: 1, selectable: rows), 1)
        XCTAssertEqual(MenuNavigation.next(from: nil, step: -1, selectable: rows), 4)
    }

    func testNothingToSelect() {
        XCTAssertNil(MenuNavigation.next(from: nil, step: 1, selectable: []))
        XCTAssertNil(MenuNavigation.next(from: 0, step: 1, selectable: [false, false]))
    }

    func testOnlyOneSelectableRowStaysWhereItIs() {
        XCTAssertEqual(MenuNavigation.next(from: 1, step: 1, selectable: [false, true, false]), 1)
    }

    func testSelectionOutsideTheListCountsAsNone() {
        XCTAssertEqual(MenuNavigation.next(from: 9, step: 1, selectable: rows), 1)
    }

    func testScrollMovesOnlyEnoughToShowTheRow() {
        // Janela de 100 pontos sobre o conteúdo, rolada em 50: mostra de 50 a 150.
        XCTAssertEqual(MenuNavigation.scroll(showing: 60, height: 22, offset: 50, visible: 100), 50, "já aparece")
        XCTAssertEqual(MenuNavigation.scroll(showing: 30, height: 22, offset: 50, visible: 100), 30, "acima: sobe até ela")
        XCTAssertEqual(MenuNavigation.scroll(showing: 140, height: 22, offset: 50, visible: 100), 62,
                       "abaixo: desce até o fim dela")
    }
}
