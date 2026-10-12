import Foundation

/// Consumo do plano do Claude, mostrado na barra superior.
///
/// O CLARK não consulta a rede nem guarda credencial para isso: lê o arquivo que o AiUsageBar
/// (https://github.com/rafaelmgbh/ai-usage-bar) mantém no cache dele, só com os percentuais e as horas
/// de renovação. Sem o arquivo, ou com ele velho demais, não há medidor.
public struct UsageMeter: Equatable, Sendable {
    public enum Level: Equatable, Sendable { case ok, warn, critical }

    /// Uma janela do plano: a de 5 horas ou a de 7 dias.
    public struct Gauge: Equatable, Sendable {
        /// `5H` ou `7D`.
        public let label: String
        /// nil: a janela renovou depois de uma leitura velha, e o consumo de agora não é conhecido.
        public let percent: Int?
        /// Segundos até a janela renovar.
        public let resetsIn: Double?

        public init(label: String, percent: Int?, resetsIn: Double?) {
            self.label = label
            self.percent = percent
            self.resetsIn = resetsIn
        }

        /// Mesmos cortes do AiUsageBar.
        public var level: Level {
            guard let percent else { return .ok }
            if percent >= 95 { return .critical }
            return percent >= 80 ? .warn : .ok
        }

        public var text: String { percent.map { "\($0)%" } ?? "--" }

        /// Quantos dos `total` blocos da barra ficam acesos: qualquer consumo acende um, e a barra só
        /// enche em 100%.
        public func filled(of total: Int) -> Int {
            guard let percent, percent > 0 else { return 0 }
            return min(total, max(1, percent * total / 100))
        }
    }

    /// Item do Keychain da conta padrão do Claude Code, que é a chave dela no arquivo.
    public static let defaultAccount = "Claude Code-credentials"
    /// Idade a partir da qual a leitura aparece apagada. O AiUsageBar relê a cada 5 minutos.
    public static let staleAfter = 15.0 * 60
    /// Idade a partir da qual a leitura não é mostrada: é sobra de um AiUsageBar que não roda mais.
    public static let expiresAfter = 24.0 * 3600
    /// Teto do que é lido do arquivo, que tem menos de 1 KiB por conta.
    public static let maxBytes = 64 * 1024

    private static let windows = [(key: "fiveHour", label: "5H"), (key: "sevenDay", label: "7D")]

    public let gauges: [Gauge]
    /// Segundos desde que o AiUsageBar leu o consumo.
    public let age: Double

    public var isStale: Bool { age > Self.staleAfter }

    public init(gauges: [Gauge], age: Double) {
        self.gauges = gauges
        self.age = age
    }

    public static func path(home: String) -> String {
        home + "/Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json"
    }

    /// Lê o arquivo de consumo. nil se ele não existe, não é o esperado ou está velho demais.
    /// - Parameter now: segundos desde 1970.
    public static func read(path: String, now: Double) -> UsageMeter? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return UsageMeter(json: data, now: now)
    }

    /// O arquivo tem uma entrada por conta. Vale a da conta padrão do Claude Code; sem ela, a lida por último.
    public init?(json data: Data, now: Double) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entries = root.compactMap { name, value -> (name: String, fetched: Double, body: [String: Any])? in
            guard let body = value as? [String: Any], let fetched = Self.number(body["fetchedAt"]) else { return nil }
            return (name, fetched, body)
        }
        guard let entry = entries.first(where: { $0.name == Self.defaultAccount })
            ?? entries.max(by: { ($0.fetched, $0.name) < ($1.fetched, $1.name) }) else { return nil }
        let age = max(0, now - entry.fetched)
        guard age <= Self.expiresAfter else { return nil }

        var gauges: [Gauge] = []
        for window in Self.windows {
            guard let body = entry.body[window.key] as? [String: Any],
                  let percent = Self.number(body["percent"]) else { continue }
            let resets = Self.number(body["resetsAt"])
            if let resets, resets <= now {
                // A janela renovou depois da leitura. Com a leitura fresca, ela acabou de zerar; com a
                // leitura velha, o que foi gasto desde então ninguém leu.
                gauges.append(Gauge(label: window.label, percent: age > Self.staleAfter ? nil : 0, resetsIn: nil))
            } else {
                gauges.append(Gauge(label: window.label, percent: Int(min(999, max(0, percent)).rounded()),
                                    resetsIn: resets.map { $0 - now }))
            }
        }
        guard !gauges.isEmpty else { return nil }
        self.gauges = gauges
        self.age = age
    }

    /// Número do JSON. `true` e `false` também chegam como `NSNumber`, e não contam.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    /// `4h29m`, `3d3h`, `12m`.
    public static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h" + String(format: "%02dm", minutes) }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    /// Texto da dica: cada janela com a renovação, e de quando é a leitura.
    public var summary: String {
        var lines = ["Consumo do plano Claude"]
        for gauge in gauges {
            var line = gauge.label.lowercased() + ": "
            if gauge.percent == nil {
                line += "renovou depois da última leitura"
            } else {
                line += gauge.text
                if let resetsIn = gauge.resetsIn { line += " · renova em " + Self.duration(resetsIn) }
            }
            lines.append(line)
        }
        let when: String
        if age < 60 {
            when = "agora"
        } else if age < 3600 {
            when = "há \(Int(age) / 60) min"
        } else {
            when = "há \(Int(age) / 3600)h"
        }
        lines.append("Lido \(when) pelo AiUsageBar" + (isStale ? " (desatualizado)" : ""))
        return lines.joined(separator: "\n")
    }
}
