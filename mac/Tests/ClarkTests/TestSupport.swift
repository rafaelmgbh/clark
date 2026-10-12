import Foundation
import XCTest

/// Pasta temporária de um teste, apagada no fim.
final class TemporaryDirectory {
    let path: String

    init(file: StaticString = #filePath, line: UInt = #line) {
        let base = NSTemporaryDirectory() + "clark-tests-" + UUID().uuidString
        do {
            try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        } catch {
            XCTFail("não criou a pasta temporária: \(error)", file: file, line: line)
        }
        // /var é um link para /private/var: os testes comparam com o caminho real
        if let real = realpath(base, nil) {
            path = String(cString: real)
            free(real)
        } else {
            path = base
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    @discardableResult
    func makeDirectory(_ relative: String) -> String {
        let full = path + "/" + relative
        try? FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    @discardableResult
    func write(_ relative: String, _ content: String, permissions: Int = 0o644) -> String {
        let full = path + "/" + relative
        makeDirectory((relative as NSString).deletingLastPathComponent)
        FileManager.default.createFile(atPath: full, contents: Data(content.utf8),
                                       attributes: [.posixPermissions: permissions])
        return full
    }
}

/// Gira o run loop principal até a condição valer. A saída dos processos chega pela fila principal.
@discardableResult
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return true
}
