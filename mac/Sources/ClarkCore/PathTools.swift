import Foundation

public enum PathTools {
    public static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// Caminho absoluto sem `.` nem `..`. Relativo é resolvido a partir de `base`.
    public static func absolute(_ path: String, base: String, home: String) -> String {
        let expanded = expandTilde(path, home: home)
        let joined = expanded.hasPrefix("/") ? expanded : base + "/" + expanded
        var parts: [Substring] = []
        for part in joined.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Como `absolute`, com a parte que existe trocada pelo caminho real: links resolvidos e
    /// a caixa gravada no disco. Assim `~/projetos/x` e `~/Projetos/X` dão a mesma resposta
    /// num disco que não diferencia maiúsculas, e um link para outra pasta conta como a pasta de destino.
    /// O trecho que ainda não existe fica como foi escrito: uma regra sobre uma pasta que só nasce
    /// depois continua casando com ela.
    public static func canonical(_ path: String, base: String, home: String) -> String {
        var existing = components(absolute(path, base: base, home: home))
        var missing: [String] = []
        while true {
            if let real = realpath("/" + existing.joined(separator: "/"), nil) {
                defer { free(real) }
                return "/" + (components(String(cString: real)) + missing.reversed()).joined(separator: "/")
            }
            // `realpath("/")` sempre responde: o laço acaba antes de `existing` esvaziar.
            guard let last = existing.popLast() else { return "/" + missing.reversed().joined(separator: "/") }
            missing.append(last)
        }
    }

    public static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    public static func hasPrefix(_ path: [String], _ prefix: [String]) -> Bool {
        path.count >= prefix.count && Array(path.prefix(prefix.count)) == prefix
    }

    /// `~/x` no lugar de `/Users/eu/x` (`short_path` do original).
    public static func short(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func isExecutableFile(_ path: String) -> Bool {
        !isDirectory(path) && FileManager.default.isExecutableFile(atPath: path)
    }
}
