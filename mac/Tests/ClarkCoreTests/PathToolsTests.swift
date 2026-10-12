import XCTest
@testable import ClarkCore

final class PathToolsTests: XCTestCase {
    private let home = "/Users/eu"

    func testExpandTilde() {
        XCTAssertEqual(PathTools.expandTilde("~", home: home), "/Users/eu")
        XCTAssertEqual(PathTools.expandTilde("~/x/y", home: home), "/Users/eu/x/y")
        XCTAssertEqual(PathTools.expandTilde("~outro/x", home: home), "~outro/x")
        XCTAssertEqual(PathTools.expandTilde("/a/~", home: home), "/a/~")
    }

    func testAbsoluteCollapsesDotsAndResolvesRelative() {
        XCTAssertEqual(PathTools.absolute("a/../b/./c", base: "/base", home: home), "/base/b/c")
        XCTAssertEqual(PathTools.absolute("/a//b/", base: "/base", home: home), "/a/b")
        XCTAssertEqual(PathTools.absolute("/../..", base: "/base", home: home), "/")
        XCTAssertEqual(PathTools.absolute("~/p", base: "/base", home: home), "/Users/eu/p")
        XCTAssertEqual(PathTools.absolute(".", base: "/base/x", home: home), "/base/x")
        XCTAssertEqual(PathTools.absolute("", base: "/base/x", home: home), "/base/x")
    }

    func testCanonicalResolvesLinksAndKeepsMissingPaths() {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("real/projeto")
        let link = temp.path + "/atalho"
        XCTAssertNoThrow(try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: temp.path + "/real"))
        XCTAssertEqual(PathTools.canonical(link + "/projeto", base: "/", home: home), real)
        XCTAssertEqual(PathTools.canonical("projeto", base: temp.path + "/real", home: home), real)
        XCTAssertEqual(PathTools.canonical("/nao/existe/../aqui", base: "/", home: home), "/nao/aqui")
    }

    func testCanonicalUsesTheCaseStoredOnDisk() throws {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("Projetos/EmpresaA")
        let lower = temp.path + "/projetos/empresaa"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: lower), "volume diferencia maiúsculas")
        XCTAssertEqual(PathTools.canonical(lower, base: "/", home: home), real)
    }

    func testCanonicalResolvesTheExistingPartOfAMissingPath() {
        // A pasta ainda não existe: o que existe acima dela é resolvido, e o resto fica como foi escrito.
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("real/projeto")
        XCTAssertNoThrow(try FileManager.default.createSymbolicLink(atPath: temp.path + "/atalho",
                                                                    withDestinationPath: temp.path + "/real"))
        XCTAssertEqual(PathTools.canonical(temp.path + "/atalho/projeto/novo/src", base: "/", home: home),
                       real + "/novo/src")
        XCTAssertEqual(PathTools.canonical(temp.path + "/atalho/outro", base: "/", home: home),
                       temp.path + "/real/outro")
    }

    func testCanonicalUsesTheCaseStoredOnDiskForTheExistingPartOfAMissingPath() throws {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("Projetos/EmpresaA")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: temp.path + "/projetos/empresaa"),
                          "volume diferencia maiúsculas")
        XCTAssertEqual(PathTools.canonical(temp.path + "/projetos/empresaa/Novo", base: "/", home: home),
                       real + "/Novo")
    }

    func testPrefixIsComparedByComponent() {
        XCTAssertEqual(PathTools.components("/a//b/c/"), ["a", "b", "c"])
        XCTAssertTrue(PathTools.components("/").isEmpty)
        XCTAssertTrue(PathTools.hasPrefix(["a", "b", "c"], ["a", "b"]))
        XCTAssertTrue(PathTools.hasPrefix(["a", "b"], ["a", "b"]))
        XCTAssertFalse(PathTools.hasPrefix(["a", "bc"], ["a", "b"]))
        XCTAssertFalse(PathTools.hasPrefix(["a"], ["a", "b"]))
    }

    func testShort() {
        XCTAssertEqual(PathTools.short("/Users/eu", home: home), "~")
        XCTAssertEqual(PathTools.short("/Users/eu/x/y", home: home), "~/x/y")
        XCTAssertEqual(PathTools.short("/Users/eu2/x", home: home), "/Users/eu2/x")
        XCTAssertEqual(PathTools.short("/opt/x", home: home), "/opt/x")
    }

    func testDirectoryAndExecutableChecks() {
        XCTAssertTrue(PathTools.isDirectory("/bin"))
        XCTAssertFalse(PathTools.isDirectory("/bin/sh"))
        XCTAssertFalse(PathTools.isDirectory("/nao/existe"))
        XCTAssertTrue(PathTools.isExecutableFile("/bin/sh"))
        XCTAssertFalse(PathTools.isExecutableFile("/bin"), "pasta não é executável")
        XCTAssertFalse(PathTools.isExecutableFile("/etc/hosts"))
    }
}
