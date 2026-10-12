import XCTest
@testable import ClarkCore

final class GitDiffTests: XCTestCase {
    /// Saída do git escrita com `|` no lugar do byte nulo e `~` no lugar da tabulação.
    private func output(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "|", with: "\0").replacingOccurrences(of: "~", with: "\t").utf8)
    }

    // MARK: arquivos mudados

    func testChangesJoinTheStatusWithTheLineCounts() {
        let files = GitDiff.parseChanges(output(
            ":000000 100644 0000000 88768ef A|novo.txt|:100644 100644 422c2b7 0000000 M|src/um.txt|"
                + ":100644 000000 af70335 0000000 D|velho.txt|3~0~novo.txt|2~1~src/um.txt|0~7~velho.txt|"))
        XCTAssertEqual(files, [
            DiffFile(path: "novo.txt", status: .added, added: 3, removed: 0),
            DiffFile(path: "src/um.txt", status: .modified, added: 2, removed: 1),
            DiffFile(path: "velho.txt", status: .deleted, added: 0, removed: 7),
        ])
    }

    func testBinaryFileHasNoLineCount() {
        let files = GitDiff.parseChanges(output(":000000 100644 0000000 88768ef A|bin.dat|-~-~bin.dat|"))
        XCTAssertEqual(files, [DiffFile(path: "bin.dat", status: .added, added: nil, removed: nil)])
    }

    func testPathsKeepSpacesTabsAndColons() {
        let files = GitDiff.parseChanges(output(
            ":100644 100644 1111111 0000000 M|:estranho*.txt|:100644 100644 2222222 0000000 M|com espaço.txt|"
                + ":100644 100644 3333333 0000000 M|com~tab.txt|"
                + "1~0~:estranho*.txt|4~4~com espaço.txt|9~8~com~tab.txt|"))
        XCTAssertEqual(files, [
            DiffFile(path: ":estranho*.txt", status: .modified, added: 1, removed: 0),
            DiffFile(path: "com espaço.txt", status: .modified, added: 4, removed: 4),
            DiffFile(path: "com\ttab.txt", status: .modified, added: 9, removed: 8),
        ])
    }

    func testOtherStatusLettersCountAsModified() {
        let files = GitDiff.parseChanges(output(
            ":100644 120000 1111111 0000000 T|vira-link|:100644 100644 2222222 0000000 U|conflito.txt|"))
        XCTAssertEqual(files.map(\.status), [.modified, .modified])
        XCTAssertEqual(files.map(\.added), [nil, nil], "sem a linha de contagem, o arquivo entra sem números")
    }

    func testOutputCutInTheMiddleDropsTheBrokenRecord() {
        let cutInThePath = GitDiff.parseChanges(output(
            ":100644 100644 1111111 0000000 M|a.txt|:100644 100644 2222222 0000000 M|b.t"))
        XCTAssertEqual(cutInThePath, [DiffFile(path: "a.txt", status: .modified, added: nil, removed: nil)])

        let cutInTheCounts = GitDiff.parseChanges(output(
            ":100644 100644 1111111 0000000 M|a.txt|:100644 100644 2222222 0000000 M|b.txt|5~1~a.txt|7~2~b."))
        XCTAssertEqual(cutInTheCounts, [
            DiffFile(path: "a.txt", status: .modified, added: 5, removed: 1),
            DiffFile(path: "b.txt", status: .modified, added: nil, removed: nil),
        ])
    }

    func testEmptyOutputMeansNoChanges() {
        XCTAssertEqual(GitDiff.parseChanges(Data()), [])
    }

    func testUntrackedPathsComeOnePerRecord() {
        XCTAssertEqual(GitDiff.parseUntracked(output("a.txt|sub/b c.txt|:x*.txt|")), ["a.txt", "sub/b c.txt", ":x*.txt"])
        XCTAssertEqual(GitDiff.parseUntracked(output("a.txt|sub/cortad")), ["a.txt"], "o registro cortado sai")
        XCTAssertEqual(GitDiff.parseUntracked(Data()), [])
    }

    func testUntrackedFilesJoinTheListInPathOrder() {
        let files = GitDiff.merged(
            [DiffFile(path: "b.txt", status: .modified, added: 1, removed: 1),
             DiffFile(path: "z/a.txt", status: .deleted, added: 0, removed: 4)],
            untracked: [DiffFile(path: "z/0.txt", status: .untracked, added: 2, removed: 0),
                        DiffFile(path: "a.txt", status: .untracked, added: nil, removed: nil)])
        XCTAssertEqual(files.map(\.path), ["a.txt", "b.txt", "z/0.txt", "z/a.txt"])
        XCTAssertEqual(files.map(\.status), [.untracked, .modified, .untracked, .deleted])
    }

    func testLineCountOfANewFile() {
        XCTAssertEqual(GitDiff.lineCount(Data("a\nb\n".utf8)), 2)
        XCTAssertEqual(GitDiff.lineCount(Data("a\nb".utf8)), 2, "a última linha conta mesmo sem a quebra")
        XCTAssertEqual(GitDiff.lineCount(Data("\n\n".utf8)), 2)
        XCTAssertEqual(GitDiff.lineCount(Data()), 0)
        XCTAssertNil(GitDiff.lineCount(Data([0x89, 0x50, 0x00, 0x0a])), "com byte nulo é binário, como para o git")
    }

    // MARK: resumo

    func testSummaryAddsUpTheFiles() {
        let summary = DiffSummary([
            DiffFile(path: "a", status: .modified, added: 10, removed: 2),
            DiffFile(path: "b", status: .untracked, added: 5, removed: 0),
            DiffFile(path: "c.bin", status: .modified, added: nil, removed: nil),
        ])
        XCTAssertEqual(summary, DiffSummary(files: 3, added: 15, removed: 2))
        XCTAssertEqual(summary.label, "+15 -2 3 ARQ")
        XCTAssertEqual(DiffSummary([]), DiffSummary(files: 0, added: 0, removed: 0))
    }

    func testSummaryShortensBigNumbers() {
        XCTAssertEqual(DiffSummary.short(0), "0")
        XCTAssertEqual(DiffSummary.short(999), "999")
        XCTAssertEqual(DiffSummary.short(1000), "1K")
        XCTAssertEqual(DiffSummary.short(1234), "1.2K")
        XCTAssertEqual(DiffSummary.short(1999), "1.9K", "corta, não arredonda para cima")
        XCTAssertEqual(DiffSummary.short(12_345), "12K")
        XCTAssertEqual(DiffSummary.short(999_999), "999K")
        XCTAssertEqual(DiffSummary.short(1_500_000), "1.5M")
        XCTAssertEqual(DiffSummary(files: 1200, added: 15_000, removed: 0).label, "+15K -0 1.2K ARQ")
    }

    func testSummaryLabelFitsThePixelFont() {
        let label = DiffSummary(files: 1_234_567, added: 9876, removed: 54_321).label
        XCTAssertEqual(PixelFont.normalize(label), label, "só ASCII em maiúsculas")
        XCTAssertTrue(label.allSatisfy { "+-. 0123456789AKMQR".contains($0) }, label)
    }

    // MARK: linhas do diff

    func testDiffLinesAreClassified() {
        let lines = GitDiff.lines(of: """
        diff --git a/um.txt b/um.txt
        index 422c2b7..7be73ce 100644
        --- a/um.txt
        +++ b/um.txt
        @@ -1,2 +1,3 @@ func x()
         a
        -b
        +B
        \\ No newline at end of file

        """)
        XCTAssertEqual(lines.map(\.kind), [.header, .header, .header, .header, .hunk, .context, .removed, .added, .note])
        XCTAssertEqual(lines.map(\.text), [
            "diff --git a/um.txt b/um.txt", "index 422c2b7..7be73ce 100644", "--- a/um.txt", "+++ b/um.txt",
            "@@ -1,2 +1,3 @@ func x()", " a", "-b", "+B", "\\ No newline at end of file",
        ])
    }

    func testChangedLineThatLooksLikeAHeaderKeepsItsKind() {
        // Uma linha `-- comentário` removida chega como `--- comentário`.
        let lines = GitDiff.lines(of: "--- a/x.sql\n+++ b/x.sql\n@@ -1 +1 @@\n--- comentario\n+++ novo\n")
        XCTAssertEqual(lines.map(\.kind), [.header, .header, .hunk, .removed, .added])
    }

    func testEachFileStartsANewHeader() {
        let lines = GitDiff.lines(of: """
        diff --git a/a b/a
        --- a/a
        +++ b/a
        @@ -1 +1 @@
        -x
        +y
        diff --git a/b b/b
        new file mode 100644
        --- /dev/null
        +++ b/b
        @@ -0,0 +1 @@
        +z

        """)
        XCTAssertEqual(lines.map(\.kind), [.header, .header, .header, .hunk, .removed, .added,
                                           .header, .header, .header, .header, .hunk, .added])
    }

    func testBinaryNoticeAndBlankContextLine() {
        let binary = GitDiff.lines(of: "diff --git a/b.dat b/b.dat\nBinary files /dev/null and b/b.dat differ\n")
        XCTAssertEqual(binary.map(\.kind), [.header, .header])
        // Há quem tire o espaço do fim das linhas: a linha de contexto vazia chega sem nada.
        XCTAssertEqual(GitDiff.lines(of: "@@ -1,3 +1,3 @@\n a\n\n-b\n").map(\.kind), [.hunk, .context, .context, .removed])
    }

    func testCarriageReturnIsDroppedAndEmptyTextHasNoLines() {
        XCTAssertEqual(GitDiff.lines(of: "@@ -1 +1 @@\r\n+a\r\n"), [
            DiffLine(kind: .hunk, text: "@@ -1 +1 @@"), DiffLine(kind: .added, text: "+a"),
        ])
        XCTAssertEqual(GitDiff.lines(of: ""), [])
    }

    // MARK: onde está o git

    func testGitComesFromThePathInOrder() {
        let existing: Set = ["/opt/tools/bin/git", "/usr/local/bin/git"]
        XCTAssertEqual(GitLocator.find(path: "relativo:/vazio:/opt/tools/bin:/usr/local/bin") { existing.contains($0) },
                       "/opt/tools/bin/git")
        XCTAssertEqual(GitLocator.find(path: nil) { existing.contains($0) }, "/usr/local/bin/git",
                       "sem PATH, vale o lugar conhecido")
        XCTAssertNil(GitLocator.find(path: "/vazio") { _ in false })
    }

    func testSystemShimIsSwappedForTheRealGit() {
        // O /usr/bin/git é um atalho: sem as ferramentas de desenvolvedor, rodá-lo abre o diálogo de instalação.
        let tools = "/Library/Developer/CommandLineTools/usr/bin/git"
        XCTAssertEqual(GitLocator.find(path: "/usr/bin:/bin") { [GitLocator.shim, tools].contains($0) }, tools)
        XCTAssertNil(GitLocator.find(path: "/usr/bin:/bin") { $0 == GitLocator.shim },
                     "só o atalho, sem ferramentas: não há git para rodar")
        XCTAssertEqual(GitLocator.find(path: "/usr/bin:/opt/x/bin") { [GitLocator.shim, "/opt/x/bin/git"].contains($0) },
                       "/opt/x/bin/git", "sem ferramentas, o git seguinte do PATH serve")
    }
}
