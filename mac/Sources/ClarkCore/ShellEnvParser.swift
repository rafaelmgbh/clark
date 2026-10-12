import Foundation

/// Leitura da saída do shell de login: `<lixo do rc>MARCADOR\0NOME=valor\0NOME=valor\0`.
public enum ShellEnvParser {
    public static let marker = "__CLARK_ENV_BEGIN__"
    /// Comando passado a `$SHELL -l -i -c`. O marcador separa o que o rc imprimir do ambiente.
    public static let command = "printf '%s\\0' \(marker); /usr/bin/env -0"
    /// `PATH` usado quando a captura falha.
    public static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    /// Variáveis que só descrevem o shell da captura e não valem para o agente.
    static let transient: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_"]

    /// Devolve nil quando o marcador não aparece ou não há `PATH`: captura inválida.
    public static func parse(_ data: Data) -> [String: String]? {
        guard let start = data.range(of: Data((marker + "\0").utf8)) else { return nil }
        var variables: [String: String] = [:]
        for entry in data[start.upperBound...].split(separator: 0) {
            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")), equals > entry.startIndex,
                  let name = String(data: entry[entry.startIndex..<equals], encoding: .utf8),
                  let value = String(data: entry[entry.index(after: equals)...], encoding: .utf8) else { continue }
            if transient.contains(name) { continue }
            variables[name] = value
        }
        guard let path = variables["PATH"], !path.isEmpty else { return nil }
        return variables
    }

    /// Ambiente do próprio app com um `PATH` padrão, para quando a captura falha.
    public static func fallback(processEnvironment: [String: String]) -> [String: String] {
        var variables = processEnvironment
        for name in transient { variables[name] = nil }
        variables["PATH"] = defaultPath
        return variables
    }
}
