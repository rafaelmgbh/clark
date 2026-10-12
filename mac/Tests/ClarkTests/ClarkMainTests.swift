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
}
