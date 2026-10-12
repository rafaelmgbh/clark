import XCTest
@testable import ClarkCore

final class UsageMeterTests: XCTestCase {
    private let now = 1_000_000.0

    /// Uma janela do plano, como o AiUsageBar grava.
    private func window(_ percent: Double, resetsIn seconds: Double?) -> String {
        let resets = seconds.map { ", \"resetsAt\": \(now + $0)" } ?? ""
        return "{\"percent\": \(percent)\(resets)}"
    }

    /// Uma conta do arquivo. `age`: há quantos segundos foi lida.
    private func account(_ name: String = UsageMeter.defaultAccount, age: Double = 240,
                         fiveHour: String? = nil, sevenDay: String? = nil) -> String {
        var fields = ["\"fetchedAt\": \(now - age)"]
        if let fiveHour { fields.append("\"fiveHour\": \(fiveHour)") }
        if let sevenDay { fields.append("\"sevenDay\": \(sevenDay)") }
        return "\"\(name)\": {\(fields.joined(separator: ", "))}"
    }

    private func meter(_ accounts: String...) -> UsageMeter? {
        UsageMeter(json: Data("{\(accounts.joined(separator: ", "))}".utf8), now: now)
    }

    private func gauge(_ percent: Int?) -> UsageMeter.Gauge {
        UsageMeter.Gauge(label: "5H", percent: percent, resetsIn: nil)
    }

    func testReadsTheTwoWindowsOfThePlan() throws {
        let meter = try XCTUnwrap(meter(account(fiveHour: window(7, resetsIn: 4 * 3600 + 29 * 60),
                                                sevenDay: window(20, resetsIn: 3 * 86400 + 3 * 3600))))
        XCTAssertEqual(meter.gauges, [
            UsageMeter.Gauge(label: "5H", percent: 7, resetsIn: 4 * 3600 + 29 * 60),
            UsageMeter.Gauge(label: "7D", percent: 20, resetsIn: 3 * 86400 + 3 * 3600),
        ])
        XCTAssertEqual(meter.age, 240)
        XCTAssertFalse(meter.isStale)
    }

    func testPercentIsRoundedAndNeverNegative() throws {
        let meter = try XCTUnwrap(meter(account(fiveHour: window(12.6, resetsIn: 60),
                                                sevenDay: window(-3, resetsIn: 60))))
        XCTAssertEqual(meter.gauges.map(\.percent), [13, 0])
    }

    func testLevelFollowsThePercent() {
        XCTAssertEqual(gauge(79).level, .ok)
        XCTAssertEqual(gauge(80).level, .warn)
        XCTAssertEqual(gauge(94).level, .warn)
        XCTAssertEqual(gauge(95).level, .critical)
        XCTAssertEqual(gauge(nil).level, .ok)
    }

    func testBarLightsABlockForAnyUseAndFillsOnlyAtTheEnd() {
        XCTAssertEqual(gauge(0).filled(of: 10), 0)
        XCTAssertEqual(gauge(1).filled(of: 10), 1, "qualquer consumo acende um bloco")
        XCTAssertEqual(gauge(19).filled(of: 10), 1)
        XCTAssertEqual(gauge(20).filled(of: 10), 2)
        XCTAssertEqual(gauge(99).filled(of: 10), 9, "a barra só enche em 100%")
        XCTAssertEqual(gauge(100).filled(of: 10), 10)
        XCTAssertEqual(gauge(250).filled(of: 10), 10)
        XCTAssertEqual(gauge(nil).filled(of: 10), 0)
    }

    func testGaugeTextIsThePercentOrDashesWhenUnknown() {
        XCTAssertEqual(gauge(7).text, "7%")
        XCTAssertEqual(gauge(nil).text, "--")
    }

    func testWindowThatRenewedAfterAFreshReadingIsZero() throws {
        // Mostrar o número de antes da renovação seria mentir.
        let meter = try XCTUnwrap(meter(account(age: 300, fiveHour: window(88, resetsIn: -60),
                                                sevenDay: window(20, resetsIn: 3600))))
        XCTAssertEqual(meter.gauges[0], UsageMeter.Gauge(label: "5H", percent: 0, resetsIn: nil))
        XCTAssertEqual(meter.gauges[1].percent, 20)
    }

    func testWindowThatRenewedAfterAnOldReadingIsUnknown() throws {
        // A leitura é velha e a janela já virou: o que foi gasto desde então ninguém leu.
        let meter = try XCTUnwrap(meter(account(age: 3600, fiveHour: window(88, resetsIn: -60),
                                                sevenDay: window(20, resetsIn: 3600))))
        XCTAssertNil(meter.gauges[0].percent)
        XCTAssertNil(meter.gauges[0].resetsIn)
        XCTAssertEqual(meter.gauges[1].percent, 20, "a janela que não virou segue com o número lido")
    }

    func testOldReadingIsStaleAndAVeryOldOneIsNoMeter() throws {
        let five = window(7, resetsIn: 30 * 86400)
        XCTAssertFalse(try XCTUnwrap(meter(account(age: UsageMeter.staleAfter, fiveHour: five))).isStale)
        XCTAssertTrue(try XCTUnwrap(meter(account(age: UsageMeter.staleAfter + 1, fiveHour: five))).isStale)
        XCTAssertNotNil(meter(account(age: UsageMeter.expiresAfter, fiveHour: five)))
        XCTAssertNil(meter(account(age: UsageMeter.expiresAfter + 1, fiveHour: five)),
                     "sobra de quem já não usa o AiUsageBar não vira medidor")
    }

    func testReadingFromTheFutureCountsAsNow() throws {
        let meter = try XCTUnwrap(meter(account(age: -500, fiveHour: window(7, resetsIn: 60))))
        XCTAssertEqual(meter.age, 0)
    }

    func testPrefersTheDefaultAccountAndFallsBackToTheFreshest() throws {
        let five = { (percent: Double) in self.window(percent, resetsIn: 3600) }
        let both = try XCTUnwrap(meter(account("outra", age: 10, fiveHour: five(50)),
                                       account(age: 200, fiveHour: five(7))))
        XCTAssertEqual(both.gauges[0].percent, 7, "a conta padrão do Claude Code vence a mais recente")
        let others = try XCTUnwrap(meter(account("beta", age: 200, fiveHour: five(30)),
                                         account("acme", age: 10, fiveHour: five(50))))
        XCTAssertEqual(others.gauges[0].percent, 50)
    }

    func testMissingWindowIsLeftOutAndNoWindowIsNoMeter() throws {
        let one = try XCTUnwrap(meter(account(sevenDay: window(20, resetsIn: 3600))))
        XCTAssertEqual(one.gauges.map(\.label), ["7D"])
        XCTAssertNil(meter(account()))
    }

    func testWindowWithoutResetKeepsThePercent() throws {
        let meter = try XCTUnwrap(meter(account(fiveHour: window(7, resetsIn: nil))))
        XCTAssertEqual(meter.gauges, [UsageMeter.Gauge(label: "5H", percent: 7, resetsIn: nil)])
    }

    func testGarbageIsNoMeter() {
        let parse = { (text: String) in UsageMeter(json: Data(text.utf8), now: self.now) }
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("isto não é json"))
        XCTAssertNil(parse("[1, 2]"))
        XCTAssertNil(parse("{}"))
        XCTAssertNil(parse("{\"conta\": 3}"))
        XCTAssertNil(parse("{\"conta\": {\"fiveHour\": {\"percent\": 7}}}"), "sem a hora da leitura")
        XCTAssertNil(parse("{\"conta\": {\"fetchedAt\": \(now), \"fiveHour\": {\"percent\": \"7\"}}}"))
        XCTAssertNil(parse("{\"conta\": {\"fetchedAt\": \(now), \"fiveHour\": {\"percent\": true}}}"))
        XCTAssertNil(parse("{\"conta\": {\"fetchedAt\": true, \"fiveHour\": {\"percent\": 7}}}"))
        XCTAssertNil(parse("{\"conta\": {\"fetchedAt\": \(now), \"fiveHour\": 7}}"))
    }

    func testDurationText() {
        XCTAssertEqual(UsageMeter.duration(0), "<1m")
        XCTAssertEqual(UsageMeter.duration(59), "<1m")
        XCTAssertEqual(UsageMeter.duration(60), "1m")
        XCTAssertEqual(UsageMeter.duration(3599), "59m")
        XCTAssertEqual(UsageMeter.duration(3600), "1h00m")
        XCTAssertEqual(UsageMeter.duration(4 * 3600 + 29 * 60 + 59), "4h29m")
        XCTAssertEqual(UsageMeter.duration(86400), "1d0h")
        XCTAssertEqual(UsageMeter.duration(3 * 86400 + 3 * 3600 + 120), "3d3h")
    }

    func testSummaryTellsTheResetAndTheAgeOfTheReading() throws {
        let fresh = try XCTUnwrap(meter(account(fiveHour: window(7, resetsIn: 4 * 3600 + 29 * 60),
                                                sevenDay: window(20, resetsIn: 3 * 86400 + 3 * 3600))))
        XCTAssertEqual(fresh.summary, """
        Consumo do plano Claude
        5h: 7% · renova em 4h29m
        7d: 20% · renova em 3d3h
        Lido há 4 min pelo AiUsageBar
        """)
        let old = try XCTUnwrap(meter(account(age: 2 * 3600 + 60, fiveHour: window(88, resetsIn: -60),
                                              sevenDay: window(20, resetsIn: nil))))
        XCTAssertEqual(old.summary, """
        Consumo do plano Claude
        5h: renovou depois da última leitura
        7d: 20%
        Lido há 2h pelo AiUsageBar (desatualizado)
        """)
        let justNow = try XCTUnwrap(meter(account(age: 20, fiveHour: window(7, resetsIn: 30))))
        XCTAssertEqual(justNow.summary, """
        Consumo do plano Claude
        5h: 7% · renova em <1m
        Lido agora pelo AiUsageBar
        """)
    }

    func testPathIsTheCacheOfTheUsageBar() {
        XCTAssertEqual(UsageMeter.path(home: "/Users/ana"),
                       "/Users/ana/Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json")
    }

    func testReadsTheFileAndIgnoresAMissingOrAnOversizedOne() throws {
        let temp = TemporaryDirectory()
        let body = "{\(account(fiveHour: window(7, resetsIn: 3600)))}"
        let path = temp.write("claude-usage.json", body)
        XCTAssertEqual(try XCTUnwrap(UsageMeter.read(path: path, now: now)).gauges.map(\.percent), [7])
        XCTAssertNil(UsageMeter.read(path: temp.path + "/nao-existe.json", now: now))
        XCTAssertNil(UsageMeter.read(path: temp.path, now: now), "uma pasta no lugar do arquivo")
        // JSON válido, mas grande demais para ser o arquivo de consumo: nem é lido até o fim.
        let padding = String(repeating: " ", count: UsageMeter.maxBytes)
        let big = temp.write("grande.json", body + padding)
        XCTAssertNil(UsageMeter.read(path: big, now: now))
    }
}
