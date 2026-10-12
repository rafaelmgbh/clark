import XCTest
@testable import ClarkCore

final class CLIOptionsTests: XCTestCase {
    private func parse(_ argv: String...) -> CLIOptions {
        CLIOptions.parse(argv, launchDirectory: "/work", home: "/Users/eu")
    }

    func testNoArguments() {
        XCTAssertEqual(parse(), CLIOptions())
        XCTAssertNil(parse().directory)
        XCTAssertEqual(parse().count, 0)
    }

    func testDirectoryIsResolvedAgainstTheLaunchDirectory() {
        XCTAssertEqual(parse("proj").directory, "/work/proj")
        XCTAssertEqual(parse(".").directory, "/work")
        XCTAssertEqual(parse("../x").directory, "/x")
        XCTAssertEqual(parse("/abs/x").directory, "/abs/x")
        XCTAssertEqual(parse("~/Projetos/A").directory, "/Users/eu/Projetos/A")
    }

    func testLaunchDirFlagComesFromTheShortcut() {
        XCTAssertEqual(parse("--launch-dir", "/term", "proj").directory, "/term/proj")
        XCTAssertEqual(parse("proj", "--launch-dir", "/term").directory, "/term/proj")
        XCTAssertNil(parse("--launch-dir", "/term").directory, "sem PASTA, a pasta do terminal não vira o padrão")
        XCTAssertNil(parse("--launch-dir").directory)
    }

    func testCountIsClamped() {
        XCTAssertEqual(parse("-n", "3").count, 3)
        XCTAssertEqual(parse("-n", "99").count, 16)
        XCTAssertEqual(parse("-n", "-2").count, 0)
        XCTAssertEqual(parse("-n").count, 1)
        let mixed = parse("-n", "proj")
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(mixed.directory, "/work/proj")
    }

    func testFlags() {
        let options = parse("--fresh", "--no-splash", "--version", "-h")
        XCTAssertTrue(options.fresh)
        XCTAssertTrue(options.noSplash)
        XCTAssertTrue(options.showVersion)
        XCTAssertTrue(options.showHelp)
        XCTAssertTrue(parse("--help").showHelp)
    }

    func testEverythingAfterDoubleDashGoesToClaude() {
        let options = parse("-n", "2", "proj", "--", "--model", "opus", "--fresh", "--", "x")
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.directory, "/work/proj")
        XCTAssertFalse(options.fresh)
        XCTAssertEqual(options.claudeArgs, ["--model", "opus", "--fresh", "--", "x"])
        XCTAssertEqual(parse("--").claudeArgs, [])
    }

    func testUnknownFlagsAreIgnored() {
        let options = parse("--bogus", "-x", "-psn_0_12345")
        XCTAssertEqual(options, CLIOptions())
    }
}

final class AgentNamingTests: XCTestCase {
    func testAutomaticNumber() {
        XCTAssertEqual(AgentNaming.automaticNumber("AGENT 3"), 3)
        XCTAssertEqual(AgentNaming.automaticNumber("AGENT 12"), 12)
        for name in ["AGENT", "AGENT ", "AGENT x", "AGENT 3 ", "agent 3", "AGENT 1234567", "AGENT -1", "MEU AGENT 1"] {
            XCTAssertNil(AgentNaming.automaticNumber(name), name)
        }
    }

    func testAutomaticNameTakesTheLowestFreeNumber() {
        XCTAssertEqual(AgentNaming.automaticName(existing: []), "AGENT 1")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["AGENT 1", "AGENT 3"]), "AGENT 2")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["API", "AGENT 1"]), "AGENT 2")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["AGENT 2"]), "AGENT 1")
    }

    func testSanitized() {
        XCTAssertEqual(AgentNaming.sanitized("  api façade  "), "API FACADE")
        XCTAssertEqual(AgentNaming.sanitized("a\u{1b}[31mb\n"), "A[31MB")
        XCTAssertEqual(AgentNaming.sanitized("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJKLMNOPQRST")
        XCTAssertEqual(AgentNaming.sanitized("ABCDEFGHIJKLMNOPQRS TUV"), "ABCDEFGHIJKLMNOPQRS")
        for empty in ["", "   ", "日本", "\n\t"] { XCTAssertNil(AgentNaming.sanitized(empty), empty) }
    }

    func testFreeTone() {
        XCTAssertEqual(AgentNaming.freeTone(used: []), 0)
        XCTAssertEqual(AgentNaming.freeTone(used: [0]), 1)
        XCTAssertEqual(AgentNaming.freeTone(used: [1, 0, 3]), 2)
        XCTAssertEqual(AgentNaming.freeTone(used: [0, 1, 2, 3]), 0)
        XCTAssertEqual(AgentNaming.freeTone(used: [0, 1, 2, 3, 0]), 1)
    }
}

final class PreviewLinesTests: XCTestCase {
    func testKeepsTheLastTwoUsefulLines() {
        let lines = ["primeira", "", "  segunda  ", "╭──────────╮", "│ terceira │", "╰──────────╯", "   ", "> "]
        XCTAssertEqual(PreviewLines.useful(lines), ["segunda", "terceira"])
    }

    func testFrameOnlyAndEmptyLinesAreDropped() {
        XCTAssertEqual(PreviewLines.useful(["───", "│ │", "❯", "· • *", ""]), [])
        XCTAssertEqual(PreviewLines.useful([]), [])
    }

    func testLimit() {
        XCTAssertEqual(PreviewLines.useful(["a", "b", "c"], limit: 1), ["c"])
        XCTAssertEqual(PreviewLines.useful(["a"], limit: 2), ["a"])
    }
}
