import XCTest
@testable import ClarkCore

final class LinePickerTests: XCTestCase {
    private func row(_ index: Int, _ text: String, wrapped: Bool = false) -> LinePicker.Row {
        LinePicker.Row(index: index, text: text, isWrapped: wrapped)
    }

    func testWrappedRowsJoinIntoOneLine() {
        let lines = LinePicker.lines([
            row(10, "git commit -m 'uma mensagem que o termi"),
            row(11, "nal quebrou'", wrapped: true),
            row(12, "pronto"),
        ])
        XCTAssertEqual(lines.map(\.text), ["git commit -m 'uma mensagem que o terminal quebrou'", "pronto"])
        XCTAssertEqual(lines.map(\.rows), [10...11, 12...12])
    }

    func testBlankLinesAreNotNumbered() {
        let lines = LinePicker.lines([row(0, "um"), row(1, "   "), row(2, ""), row(3, "dois")])
        XCTAssertEqual(lines.map(\.text), ["um", "dois"])
    }

    func testRowContinuingTheLineAboveTheScreenStartsALine() {
        let lines = LinePicker.lines([row(5, "fim da frase", wrapped: true), row(6, "outra")])
        XCTAssertEqual(lines.map(\.text), ["fim da frase", "outra"])
    }

    private func picker(_ count: Int) -> LinePicker {
        LinePicker(lines: (0..<count).map { LinePicker.Line(rows: $0...$0, text: "linha \($0 + 1)") })!
    }

    func testNoLineNoPicker() {
        XCTAssertNil(LinePicker(lines: []))
    }

    func testStartsOnTheLastLine() {
        let picker = picker(5)
        XCTAssertEqual(picker.selected, 4...4, "a mais perto do prompt")
        XCTAssertEqual(picker.text, "linha 5")
    }

    func testArrowsMoveAndShiftExtends() {
        var picker = picker(5)
        picker.move(by: -1)
        XCTAssertEqual(picker.selected, 3...3)
        picker.move(by: -1, extending: true)
        picker.move(by: -1, extending: true)
        XCTAssertEqual(picker.selected, 1...3)
        XCTAssertEqual(picker.text, "linha 2\nlinha 3\nlinha 4")
        picker.move(by: -9)
        XCTAssertEqual(picker.selected, 0...0, "para na primeira")
        picker.move(by: 9, extending: true)
        XCTAssertEqual(picker.selected, 0...4, "e na última")
    }

    func testTypedNumberJumpsToTheLine() {
        var picker = picker(15)
        picker.type(1)
        XCTAssertEqual(picker.selected, 0...0)
        picker.type(2)
        XCTAssertEqual(picker.selected, 11...11, "1 e 2 é a 12")
        XCTAssertEqual(picker.typed, "12")
        picker.type(7)
        XCTAssertEqual(picker.selected, 6...6, "127 não existe: o 7 começa outro número")
        XCTAssertEqual(picker.typed, "7")
    }

    func testTypedNumberThatDoesNotExistKeepsTheSelection() {
        var picker = picker(3)
        picker.type(0)
        XCTAssertEqual(picker.selected, 2...2)
        XCTAssertEqual(picker.typed, "")
        picker.type(9)
        XCTAssertEqual(picker.selected, 2...2)
    }

    func testArrowAfterTypingStartsANewNumber() {
        var picker = picker(15)
        picker.type(1)
        picker.move(by: 1)
        XCTAssertEqual(picker.typed, "")
        picker.type(2)
        XCTAssertEqual(picker.selected, 1...1)
    }

    func testShiftArrowExtendsFromTheTypedLine() {
        var picker = picker(9)
        picker.type(3)
        picker.move(by: 1, extending: true)
        XCTAssertEqual(picker.selected, 2...3)
    }
}
