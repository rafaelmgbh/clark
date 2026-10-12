import XCTest
@testable import ClarkCore

final class SessionLocatorTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    func testValidUUID() {
        XCTAssertTrue(SessionLocator.isValidUUID(id))
        XCTAssertTrue(SessionLocator.isValidUUID(id.uppercased()))
        XCTAssertTrue(SessionLocator.isValidUUID(SessionLocator.newID()))
    }

    func testInvalidUUID() {
        let bad = ["", "abc", id + "0", String(id.dropLast()), "{" + id.dropFirst().dropLast() + "}",
                   id.replacingOccurrences(of: "-", with: "_"), "0f8fad5bd-9cb-469f-a165-70867728950e",
                   "0f8fad5b-d9cb-469f-a165-7086772895zz", id + "\n", "--dangerously-skip-permissions",
                   "../../../etc/passwd-aaaaaaaaaaaaaaaaaaaa"]
        for text in bad { XCTAssertFalse(SessionLocator.isValidUUID(text), text) }
    }

    func testNormalizedLowercasesAndRejects() {
        XCTAssertEqual(SessionLocator.normalized(id.uppercased()), id)
        XCTAssertNil(SessionLocator.normalized("nao-e-uuid"))
        XCTAssertNil(SessionLocator.normalized(nil))
    }

    func testNewIDIsLowercaseAndUnique() {
        let first = SessionLocator.newID()
        XCTAssertEqual(first, first.lowercased())
        XCTAssertNotEqual(first, SessionLocator.newID())
    }

    func testConfigDirRespectsClaudeConfigDir() {
        XCTAssertEqual(SessionLocator.configDir(environment: [:], home: "/Users/eu"), "/Users/eu/.claude")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": ""], home: "/Users/eu"), "/Users/eu/.claude")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": "/x/y"], home: "/Users/eu"), "/x/y")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": "~/alt"], home: "/Users/eu"), "/Users/eu/alt")
    }

    func testSessionExistsOnlyWithTheTranscriptOnDisk() {
        let temp = TemporaryDirectory()
        XCTAssertFalse(SessionLocator.sessionExists(id, configDir: temp.path), "sem a pasta projects")
        temp.write("projects/-Users-eu-Projetos-A/\(id).jsonl", "{}\n")
        temp.makeDirectory("projects/-Users-eu-Projetos-B")
        XCTAssertTrue(SessionLocator.sessionExists(id, configDir: temp.path))
        XCTAssertTrue(SessionLocator.sessionExists(id.uppercased(), configDir: temp.path))
        XCTAssertFalse(SessionLocator.sessionExists(SessionLocator.newID(), configDir: temp.path))
    }

    func testInvalidIDNeverTouchesTheDisk() {
        let temp = TemporaryDirectory()
        temp.write("projects/p/segredo.jsonl", "{}")
        XCTAssertFalse(SessionLocator.sessionExists("segredo", configDir: temp.path))
        XCTAssertFalse(SessionLocator.sessionExists("../p/segredo", configDir: temp.path + "/projects"))
    }
}

final class ClaudeCommandTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    func testNewConversationUsesSessionID() {
        let command = ClaudeCommand.build(extraArgs: [], sessionID: id, sessionExists: false)
        XCTAssertEqual(command.arguments, ["--session-id", id])
        XCTAssertFalse(command.bypassesPermissions)
    }

    func testExistingConversationUsesResume() {
        let command = ClaudeCommand.build(extraArgs: ["--model", "opus"], sessionID: id, sessionExists: true)
        XCTAssertEqual(command.arguments, ["--model", "opus", "--resume", id])
    }

    func testSessionFlagsInTheExtrasSuppressOurs() {
        for extras in [["-c"], ["--continue"], ["-r", "abc"], ["--resume"], ["--resume=abc"],
                       ["--session-id", "abc"], ["--session-id=abc"], ["--model", "opus", "-c"]] {
            let command = ClaudeCommand.build(extraArgs: extras, sessionID: id, sessionExists: true)
            XCTAssertEqual(command.arguments, extras, "\(extras)")
        }
    }

    func testLookAlikeFlagsDoNotCount() {
        for extras in [["--resumed"], ["--continue-on-error"], ["-cx"], ["--model", "c"]] {
            XCTAssertFalse(ClaudeCommand.hasSessionFlag(extras), "\(extras)")
        }
    }

    func testDetectsPermissionBypass() {
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--dangerously-skip-permissions"]))
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--model", "opus", "--permission-mode", "bypassPermissions"]))
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--permission-mode=bypassPermissions"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions([]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode", "plan"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode=acceptEdits"]))
        let command = ClaudeCommand.build(extraArgs: ["--dangerously-skip-permissions"], sessionID: id, sessionExists: false)
        XCTAssertTrue(command.bypassesPermissions)
        XCTAssertEqual(command.arguments, ["--dangerously-skip-permissions", "--session-id", id])
    }
}

final class ClaudeLocatorTests: XCTestCase {
    func testFindsInThePathFirst() {
        let found = ClaudeLocator.find(path: "/a:/b:/c", home: "/Users/eu") { $0 == "/b/claude" || $0 == "/Users/eu/.local/bin/claude" }
        XCTAssertEqual(found, "/b/claude")
    }

    func testRelativePathEntriesAreIgnored() {
        let found = ClaudeLocator.find(path: "rel:.::bin", home: "/Users/eu") { !$0.hasPrefix("/") }
        XCTAssertNil(found)
    }

    func testFallsBackToKnownLocationsInOrder() {
        let candidates = ["/Users/eu/.local/bin/claude", "/Users/eu/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for (index, expected) in candidates.enumerated() {
            let available = Set(candidates[index...])
            XCTAssertEqual(ClaudeLocator.find(path: nil, home: "/Users/eu") { available.contains($0) }, expected)
        }
        XCTAssertNil(ClaudeLocator.find(path: "/a", home: "/Users/eu") { _ in false })
    }
}
