import AppKit
import ClarkCore
import XCTest
@testable import Clark

final class ClarkMainTests: XCTestCase {
    private func options(_ arguments: [String]) -> CLIOptions {
        CLIOptions.parse(arguments, launchDirectory: "/tmp", home: "/tmp")
    }

    func testVersionAndHelpAnswerWithoutOpeningTheWindow() {
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["--version"])), "clark \(ClarkVersion.current)")
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["--help"])), CLIOptions.usage)
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["-h"])), CLIOptions.usage)
    }

    func testEverythingElseOpensTheWindow() {
        XCTAssertNil(ClarkMain.immediateOutput(for: options([])))
        XCTAssertNil(ClarkMain.immediateOutput(for: options(["-n", "2", "--fresh"])))
        // Depois do `--` a opção é do claude, não do CLARK.
        XCTAssertNil(ClarkMain.immediateOutput(for: options(["--", "--version"])))
    }

    func testExportIconWritesThePNGInsteadOfOpeningTheWindow() throws {
        let temp = TemporaryDirectory()
        let path = temp.path + "/icone.png"
        XCTAssertNil(ClarkMain.exportIcon(for: options([])), "sem a opção, o app abre")
        XCTAssertEqual(ClarkMain.exportIcon(for: options(["--export-icon", path, "--icon-size", "32"])), 0)
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: path))))
        XCTAssertEqual([image.pixelsWide, image.pixelsHigh], [32, 32])
    }

    func testExportIconFailsWhenTheFileCannotBeWritten() {
        let temp = TemporaryDirectory()
        XCTAssertEqual(ClarkMain.exportIcon(for: options(["--export-icon", temp.path + "/nao-existe/icone.png"])), 1)
    }
}
