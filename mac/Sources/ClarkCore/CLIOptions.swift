/// Linha de comando do `clark` (`parse_args` do original).
public struct CLIOptions: Equatable, Sendable {
    public static let usage =
        "uso: clark [PASTA] [-n N] [--no-splash] [--fresh] [--version] [-- argumentos extras do claude]"
    public static let maxAgents = 16

    public var directory: String?
    /// Agentes novos a abrir, de 0 a 16.
    public var count = 0
    /// Aceito para manter a linha de comando do original. A splash só existe a partir do M3.
    public var noSplash = false
    public var fresh = false
    public var showVersion = false
    public var showHelp = false
    public var claudeArgs: [String] = []

    public init() {}

    /// - Parameter launchDirectory: pasta contra a qual uma PASTA relativa é resolvida.
    ///   O atalho `clark` passa a pasta do terminal em `--launch-dir`, porque o `open` não a preserva.
    public static func parse(_ argv: [String], launchDirectory: String, home: String) -> CLIOptions {
        var options = CLIOptions()
        var own = argv
        if let separator = argv.firstIndex(of: "--") {
            own = Array(argv[..<separator])
            options.claudeArgs = Array(argv[(separator + 1)...])
        }
        var base = launchDirectory
        var positional: String?
        var index = 0
        while index < own.count {
            let argument = own[index]
            switch argument {
            case "-h", "--help":
                options.showHelp = true
            case "--version":
                options.showVersion = true
            case "--fresh":
                options.fresh = true
            case "--no-splash":
                options.noSplash = true
            case "-n":
                if index + 1 < own.count, let count = Int(own[index + 1]) {
                    options.count = max(0, min(maxAgents, count))
                    index += 1
                } else {
                    options.count = 1
                }
            case "--launch-dir":
                if index + 1 < own.count {
                    base = own[index + 1]
                    index += 1
                }
            default:
                if !argument.hasPrefix("-") { positional = argument }
            }
            index += 1
        }
        if let positional {
            options.directory = PathTools.absolute(positional, base: base, home: home)
        }
        return options
    }
}
