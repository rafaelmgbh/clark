import XCTest
@testable import ClarkCore

final class SessionDigestTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private let directory = "/Users/eu/Projetos/acme/api"
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        temp = TemporaryDirectory()
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private var configDir: String { temp.path + "/.claude" }

    private func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func title(_ text: String) -> String { json(["type": "ai-title", "aiTitle": text, "sessionId": "x"]) }
    private func prompt(_ text: String) -> String { json(["type": "last-prompt", "lastPrompt": text, "leafUuid": "y"]) }

    private func assistant(_ blocks: [[String: Any]], sidechain: Bool = false) -> String {
        json(["type": "assistant", "isSidechain": sidechain, "message": ["role": "assistant", "content": blocks]])
    }

    private func answer(_ text: String, sidechain: Bool = false) -> String {
        assistant([["type": "text", "text": text]], sidechain: sidechain)
    }

    private func typed(_ content: Any, meta: Bool = false) -> String {
        json(["type": "user", "isMeta": meta, "message": ["role": "user", "content": content]])
    }

    /// Grava a conversa na pasta do projeto, com a data de modificação `age` segundos antes de `base`.
    @discardableResult
    private func write(_ id: String, _ lines: [String], age: TimeInterval = 0, in folder: String? = nil) -> String {
        let project = folder ?? directory
        let slug = SessionDigestReader.projectFolder(canonicalDirectory: project, configDir: "")
        let path = temp.write(".claude" + slug + "/\(id).jsonl", lines.map { $0 + "\n" }.joined())
        try? FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(-age)], ofItemAtPath: path)
        return path
    }

    private func latest(excluding: Set<String> = [], tailBytes: Int = SessionDigestReader.tailBytes) -> SessionDigest? {
        SessionDigestReader.latest(canonicalDirectory: directory, configDir: configDir, excluding: excluding,
                                   tailBytes: tailBytes)
    }

    private let first = "11111111-1111-4111-8111-111111111111"
    private let second = "22222222-2222-4222-8222-222222222222"
    private let third = "33333333-3333-4333-8333-333333333333"

    // MARK: pasta

    func testProjectFolderFollowsTheClaudeCodeSlug() {
        XCTAssertEqual(SessionDigestReader.projectFolder(canonicalDirectory: "/Users/eu/Projetos/acme_app/v1.2",
                                                         configDir: "/c"),
                       "/c/projects/-Users-eu-Projetos-acme-app-v1-2")
        XCTAssertEqual(SessionDigestReader.projectFolder(canonicalDirectory: "/Users/eu/área técnica", configDir: "/c"),
                       "/c/projects/-Users-eu--rea-t-cnica", "o que não é letra ou número ASCII vira traço")
    }

    // MARK: leitura

    func testDigestBringsTitlePromptAndTheStartOfTheLastAnswer() {
        write(first, [
            typed("arruma o login"),
            answer("Vou olhar o middleware."),
            title("Corrigir o login da API"),
            answer("Corrigi a validade do token.\nOs 42 testes passam.\nTerceira linha que não entra."),
            prompt("roda os testes de novo"),
        ])
        XCTAssertEqual(latest(), SessionDigest(
            title: "Corrigir o login da API", prompt: "roda os testes de novo",
            answer: ["Corrigi a validade do token.", "Os 42 testes passam."], date: base))
    }

    func testAnswerLosesTheMarkdown() {
        write(first, [answer("""
        ## Resumo

        - **Login** corrigido em `auth.py`
        1. Veja [o relatório](https://exemplo.test/r) antes
        ```swift
        let ignorado = true
        ```
        > citação
        | Arquivo | Linhas |
        |---------|--------|
        ---
        """)])
        XCTAssertEqual(latest()?.answer, ["Resumo", "Login corrigido em auth.py"])
        write(first, [answer("1. Veja [o relatório](https://exemplo.test/r) antes\n> citação\n| Arquivo | Linhas |\n|---|---|")])
        XCTAssertEqual(latest()?.answer, ["Veja o relatório antes", "citação"])
        write(first, [answer("| Arquivo | Linhas |\n|---|---|\n***\n")])
        XCTAssertEqual(latest()?.answer, ["Arquivo Linhas"], "a régua e o separador de tabela ficam de fora")
    }

    func testPendingLineIsPickedFromTheAnswer() {
        write(first, [answer("Deploy feito.\nTudo verde.\nMais um detalhe.\nFicou pendente a rotação da chave.")])
        XCTAssertEqual(latest()?.answer, ["Deploy feito.", "Tudo verde."])
        XCTAssertEqual(latest()?.pending, "Ficou pendente a rotação da chave.")

        write(first, [answer("Falta rodar a migração.\nO resto está pronto.\nE mais isto.")])
        XCTAssertEqual(latest()?.pending, "Falta rodar a migração.")
        XCTAssertEqual(latest()?.answer, ["O resto está pronto.", "E mais isto."], "a pendência não aparece duas vezes")

        write(first, [answer("Feito.\n- [x] testes\n- [ ] publicar a versão")])
        XCTAssertEqual(latest()?.pending, "publicar a versão", "caixa desmarcada é pendência")
        XCTAssertEqual(latest()?.answer, ["Feito.", "testes"])

        write(first, [answer("Terminei o ajuste.\nQuer que eu rode os testes?")])
        XCTAssertEqual(latest()?.pending, "Quer que eu rode os testes?", "a pergunta do fim ficou sem resposta")

        write(first, [answer("Todo o asfalto foi refeito.\nNada mais.")])
        XCTAssertNil(latest()?.pending, "`todo` e `asfalto` não são pendência")

        write(first, [answer("Próximos passos: abrir o PR.\nAINDA NÃO commitei.")])
        XCTAssertEqual(latest()?.pending, "Próximos passos: abrir o PR.")
    }

    func testSayingThereIsNothingPendingIsNotAPending() {
        let summary = SessionDigestReader.summarize("Tudo aplicado.\n\nSem pendências.")
        XCTAssertNil(summary.pending, "a frase cita a pendência para dizer que não há")
        XCTAssertEqual(summary.lines, ["Tudo aplicado.", "Sem pendências."])
        for line in ["Nenhuma pendência.", "Não há pendências", "Nada pendente por aqui", "Não falta nada",
                     "No pending items", "Nothing remaining"] {
            XCTAssertFalse(SessionDigestReader.mentionsPending(line), line)
        }
        XCTAssertTrue(SessionDigestReader.mentionsPending("Pendência: rodar a migração"))
        XCTAssertTrue(SessionDigestReader.mentionsPending("Falta rodar a migração"))
    }

    func testOnlyTheMainConversationCounts() {
        write(first, [
            answer("Resposta de verdade."),
            answer("Resposta do subagente.", sidechain: true),
            assistant([["type": "thinking", "thinking": "pensando"], ["type": "tool_use", "name": "Bash"]]),
            assistant([["type": "text", "text": "   "]]),
            typed("pedido digitado"),
            typed([["type": "tool_result", "content": "saída de ferramenta"]]),
            typed("<command-name>/clear</command-name>"),
            typed("aviso do app", meta: true),
        ])
        XCTAssertEqual(latest(), SessionDigest(title: nil, prompt: "pedido digitado", answer: ["Resposta de verdade."],
                                               date: base),
                       "sem `last-prompt`, vale a última mensagem digitada")

        write(first, [typed([["type": "text", "text": "pedido em blocos\ncom duas linhas"]]), prompt("o mais recente")])
        XCTAssertEqual(latest()?.prompt, "o mais recente")
        write(first, [typed([["type": "text", "text": "pedido em blocos\ncom duas linhas"]])])
        XCTAssertEqual(latest()?.prompt, "pedido em blocos", "só a primeira linha do pedido")
    }

    func testBrokenLinesAreSkipped() {
        var data = Data("isto não é json\n{\"type\": 3}\n[1, 2]\n".utf8)
        data.append(contentsOf: [0xff, 0xfe, 0x0a])
        data.append(Data((title("Título bom") + "\n\n").utf8))
        XCTAssertEqual(SessionDigestReader.digest(data, startsMidLine: false, date: base),
                       SessionDigest(title: "Título bom", prompt: nil, date: base))
        XCTAssertNil(SessionDigestReader.digest(Data("lixo\n".utf8), startsMidLine: false, date: base))
        XCTAssertNil(SessionDigestReader.digest(Data(), startsMidLine: false, date: base))
    }

    func testTextIsCleanedAndKeptShort() {
        let long = String(repeating: "a", count: 500)
        write(first, [title("  Título\tcom\u{0007}   espaços \u{001b}[31m "), prompt(long), answer(long + "\nfim")])
        let digest = latest()
        XCTAssertEqual(digest?.title, "Título com espaços [31m")
        XCTAssertEqual(digest?.prompt?.count, SessionDigestReader.maxLineLength)
        XCTAssertEqual(digest?.prompt?.last, "…")
        XCTAssertEqual(digest?.answer.first?.count, SessionDigestReader.maxLineLength)
        XCTAssertEqual(digest?.answer.last, "fim")
    }

    // MARK: escolha da conversa

    func testLatestIsTheNewestConversationOfThatFolder() {
        write(first, [title("Antiga")], age: 300)
        write(second, [title("Nova")], age: 10)
        write(third, [title("De outro projeto")], age: 0, in: "/Users/eu/Projetos/beta/site")
        temp.write(".claude" + SessionDigestReader.projectFolder(canonicalDirectory: directory, configDir: "")
            + "/anotacoes.jsonl", title("Sem nome de conversa") + "\n")
        XCTAssertEqual(latest()?.title, "Nova")
        XCTAssertEqual(latest()?.date, base.addingTimeInterval(-10))
        XCTAssertEqual(latest(excluding: [second])?.title, "Antiga", "a conversa do próprio agente não conta")
        XCTAssertEqual(latest(excluding: [second.uppercased()])?.title, "Antiga")
        XCTAssertNil(latest(excluding: [first, second]))
    }

    func testConversationWithNothingToShowGivesWayToThePreviousOne() {
        write(first, [title("Com conteúdo")], age: 300)
        write(second, [json(["type": "system", "subtype": "local_command"])], age: 10)
        XCTAssertEqual(latest()?.title, "Com conteúdo")
    }

    func testFolderWithoutConversationsHasNoDigest() {
        XCTAssertNil(latest())
        temp.makeDirectory(".claude/projects")
        XCTAssertNil(latest())
        write(first, [])
        XCTAssertNil(latest(), "arquivo vazio")
    }

    func testOnlyTheEndOfABigConversationIsRead() {
        let filler = (0..<200).map { _ in answer(String(repeating: "x", count: 100)) }
        write(first, [title("Título lá do começo")] + filler + [prompt("pedido do fim"), answer("Resposta do fim.")])
        let digest = latest(tailBytes: 2048)
        XCTAssertNil(digest?.title, "o que ficou antes do corte não é lido")
        XCTAssertEqual(digest?.prompt, "pedido do fim")
        XCTAssertEqual(digest?.answer, ["Resposta do fim."])
        XCTAssertEqual(latest()?.title, "Título lá do começo")

        // O corte cai no meio de uma linha: o pedaço não vira resposta.
        let cut = SessionDigestReader.digest(Data((String(answer("Linha partida.").dropFirst(5)) + "\n"
                + answer("Linha inteira.") + "\n").utf8), startsMidLine: true, date: base)
        XCTAssertEqual(cut?.answer, ["Linha inteira."])
    }

    // MARK: apresentação

    func testBodyHasThePromptTheAnswerAndThePending() {
        let full = SessionDigest(title: "T", prompt: "roda os testes", answer: ["Rodei.", "Tudo verde."],
                                 pending: "falta o deploy", date: base)
        XCTAssertEqual(full.body, [
            SessionDigest.Line(.prompt, "Pedido: roda os testes"), SessionDigest.Line(.answer, "Rodei."),
            SessionDigest.Line(.pending, "Pendente: falta o deploy"),
        ], "três linhas: a pendência tira o lugar da segunda linha da resposta")
        XCTAssertEqual(SessionDigest(title: "T", prompt: nil, answer: ["Rodei.", "Tudo verde."], date: base).body,
                       [SessionDigest.Line(.answer, "Rodei."), SessionDigest.Line(.answer, "Tudo verde.")])
        XCTAssertEqual(SessionDigest(title: "T", prompt: nil, date: base).body, [])
    }

    func testWhenIsRelativeToToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour,
                                                             minute: minute)))
        }
        let now = try date(2026, 10, 12, 8, 30)
        func when(_ date: Date) -> String {
            SessionDigest(title: "T", prompt: nil, date: date).when(now: now, calendar: calendar)
        }
        XCTAssertEqual(when(try date(2026, 10, 12, 0, 5)), "HOJE 00:05")
        XCTAssertEqual(when(try date(2026, 10, 11, 23, 40)), "ONTEM 23:40")
        XCTAssertEqual(when(try date(2026, 10, 3, 9, 7)), "03/10 09:07")
        XCTAssertEqual(when(try date(2025, 12, 31, 18, 0)), "31/12/2025")
        XCTAssertEqual(PixelFont.normalize(when(try date(2026, 10, 3, 9, 7))), "03/10 09:07", "cabe na fonte pixel")
    }
}
