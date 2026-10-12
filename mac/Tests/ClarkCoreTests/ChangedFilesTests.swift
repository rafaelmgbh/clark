import XCTest
@testable import ClarkCore

final class ChangedFilesTests: XCTestCase {
    private func file(_ path: String, _ status: DiffStatus) -> DiffFile {
        DiffFile(path: path, status: status, added: 1, removed: 0)
    }

    func testGroupsComeInAFixedOrderWithTheFilesInTheOrderTheyArrived() {
        let files = [
            file("a/novo.py", .untracked), file("b/saiu.py", .deleted), file("c/mexido.py", .modified),
            file("d/criado.py", .added), file("e/outro.py", .modified), file("notas.md", .untracked),
        ]
        XCTAssertEqual(ChangedFiles.rows(files), [
            .group(.modified, count: 2), .file(files[2]), .file(files[4]),
            .group(.added, count: 1), .file(files[3]),
            .group(.deleted, count: 1), .file(files[1]),
            .group(.untracked, count: 2), .file(files[0]), .file(files[5]),
        ])
    }

    func testGroupWithoutFilesIsLeftOut() {
        let files = [file("a.txt", .modified), file("b.txt", .untracked)]
        XCTAssertEqual(ChangedFiles.rows(files), [
            .group(.modified, count: 1), .file(files[0]), .group(.untracked, count: 1), .file(files[1]),
        ])
        XCTAssertEqual(ChangedFiles.rows([]), [])
    }

    func testEveryStatusHasAGroup() {
        XCTAssertEqual(ChangedFiles.order, [.modified, .added, .deleted, .untracked])
        XCTAssertEqual(ChangedFiles.order.map(ChangedFiles.title),
                       ["MODIFICADOS", "NOVOS", "REMOVIDOS", "NAO RASTREADOS"])
    }

    func testTitlesFitThePixelFont() {
        for status in ChangedFiles.order {
            let title = ChangedFiles.title(status)
            XCTAssertEqual(PixelFont.normalize(title), title, "a fonte de pixels só tem ASCII em maiúsculas")
        }
    }

    func testPathIsSplitIntoTheNameAndTheFolder() {
        func split(_ path: String) -> [String] {
            let parts = ChangedFiles.split(path)
            return [parts.name, parts.folder]
        }
        XCTAssertEqual(split("vendas/models/pedido.py"), ["pedido.py", "vendas/models"])
        XCTAssertEqual(split("notas.md"), ["notas.md", ""], "na raiz do repositório não há pasta")
        XCTAssertEqual(split("docs/relatório final.md"), ["relatório final.md", "docs"])
        XCTAssertEqual(split(".github/workflows/ci.yml"), ["ci.yml", ".github/workflows"])
    }

    /// O git lista um repositório aninhado, que ele não acompanha, como uma pasta: `vendor/lib/`.
    func testFolderListedByGitKeepsItsSlashInTheName() {
        XCTAssertEqual(ChangedFiles.split("vendor/lib/").name, "lib/")
        XCTAssertEqual(ChangedFiles.split("vendor/lib/").folder, "vendor")
        XCTAssertEqual(ChangedFiles.split("lib/").name, "lib/")
        XCTAssertEqual(ChangedFiles.split("lib/").folder, "")
    }
}
