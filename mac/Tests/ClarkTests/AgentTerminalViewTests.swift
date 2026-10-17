import ClarkCore
import SwiftTerm
import XCTest
@testable import Clark

final class AgentTerminalViewTests: XCTestCase {
    private let environment = ["TERM=xterm-256color", "PATH=/usr/bin:/bin"]

    private func makeView() -> AgentTerminalView {
        let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        // Relógio parado: a leitura dos links nunca parece cara, e uma máquina lenta não esconde o
        // sublinhado no meio de um teste. Os testes do custo da leitura trocam o relógio.
        view.uptime = { 0 }
        return view
    }

    /// Roda o script até o fim e devolve o terminal.
    private func run(_ script: String, configure: (AgentTerminalView) -> Void = { _ in }) -> AgentTerminalView {
        let view = makeView()
        let exited = expectation(description: "processo terminou")
        configure(view)
        let previous = view.onExit
        view.onExit = { code in
            previous?(code)
            exited.fulfill()
        }
        view.startProcess(executable: "/bin/sh", args: ["-c", script], environment: environment,
                          currentDirectory: "/")
        wait(for: [exited], timeout: 10)
        return view
    }

    func testOutputBellAndExitReachTheHooks() {
        var outputs = 0, bells = 0, inputs = 0
        var code: Int32?
        let view = run("printf 'ola\\nmundo\\n\\a'; exit 3") { view in
            view.onOutput = { outputs += 1 }
            view.onBell = { bells += 1 }
            view.onUserInput = { inputs += 1 }
            view.onExit = { code = $0 }
        }
        XCTAssertGreaterThan(outputs, 0)
        XCTAssertEqual(bells, 1)
        XCTAssertEqual(inputs, 0)
        XCTAssertEqual(code, 3)
        XCTAssertTrue(view.hasExited)
        XCTAssertEqual(view.linesAboveCursor(), ["ola", "mundo"])
    }

    func testTerminalRepliesAreNotUserInput() {
        var inputs = 0
        // ESC[6n pede a posição do cursor: o emulador responde sozinho, sem tecla do usuário.
        _ = run("printf '\\033[6n'; sleep 0.3") { view in view.onUserInput = { inputs += 1 } }
        XCTAssertEqual(inputs, 0)
    }

    func testTypingCountsAsInputAndEnterAfterExitAsksRestart() {
        var inputs = 0, restarts = 0
        let view = makeView()
        let exited = expectation(description: "processo terminou")
        view.onUserInput = { inputs += 1 }
        view.onRestartRequested = { restarts += 1 }
        view.onExit = { _ in exited.fulfill() }
        view.startProcess(executable: "/bin/sh", args: ["-c", "read x; exit 0"], environment: environment,
                          currentDirectory: "/")
        view.send(txt: "a\r")
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(inputs, 1)

        view.send(txt: "x")
        XCTAssertEqual(restarts, 0, "só o Enter reabre")
        view.send(txt: "\r")
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(inputs, 1, "tecla em GAME OVER não é entrada do agente")
    }

    func testMarkExitedMakesEnterAskRestartWithoutAProcess() {
        var restarts = 0
        let view = makeView()
        view.onRestartRequested = { restarts += 1 }
        view.markExited()
        view.send(txt: "\r")
        XCTAssertEqual(restarts, 1)
    }

    func testExitCodeComesFromTheWaitStatus() {
        XCTAssertNil(AgentTerminalView.exitCode(fromWaitStatus: nil))
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 0), 0)
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 3 << 8), 3)
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 255 << 8), 255)
    }

    func testOnlyWebLinksOpen() {
        var opened: [String] = []
        let view = makeView()
        view.openURL = { opened.append($0.absoluteString) }
        for link in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "ssh://host",
                     "", "sem esquema", "/bin/sh"] {
            view.requestOpenLink(source: view, link: link, params: [:])
        }
        XCTAssertEqual(opened, [])

        view.requestOpenLink(source: view, link: "https://example.com/a?b=1", params: [:])
        view.requestOpenLink(source: view, link: "HTTP://example.com", params: [:])
        XCTAssertEqual(opened, ["https://example.com/a?b=1", "HTTP://example.com"])
    }

    // MARK: links sublinhados

    func testLinkInTheOutputIsUnderlined() {
        let view = run("printf 'veja https://example.com/a\\n'")
        XCTAssertTrue(waitUntil(timeout: 5) { view.linkUnderlines.spans == [LinkSpan(row: 0, columns: 5..<26)] })
    }

    func testUnderlinesAreRedoneWhenTheScreenChanges() {
        let view = makeView()
        view.feed(text: "https://example.com/a")
        XCTAssertTrue(waitUntil(timeout: 5) { view.linkUnderlines.spans == [LinkSpan(row: 0, columns: 0..<21)] })
        // Apaga a linha: o sublinhado some com o texto.
        view.feed(text: "\r\u{1b}[2K")
        XCTAssertTrue(waitUntil(timeout: 5) { view.linkUnderlines.spans.isEmpty })
    }

    func testUnderlinesFollowTheScroll() {
        let view = makeView()
        view.resize(cols: 40, rows: 4)
        view.feed(text: "https://example.com/a\r\n1\r\n2\r\n3\r\n4\r\n5")
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [])
        view.scrollTo(row: 0)
        XCTAssertEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<21)])
    }

    func testUnderlinesFollowTheCellsAndTheTheme() {
        let view = makeView()
        view.linkUnderlines.color = .black
        view.apply(TerminalAppearance(theme: .dark, fontName: "Menlo", fontSize: 15))
        let metrics = view.linkUnderlines.metrics
        XCTAssertGreaterThan(metrics.cell.width, 0)
        XCTAssertEqual(metrics.cell.width, view.caretFrame.width)
        XCTAssertEqual(metrics.cell.height * CGFloat(view.getTerminal().rows), view.getOptimalFrameSize().height,
                       accuracy: 0.01)
        // O traço fica no pé da célula, abaixo da linha de base do texto.
        XCTAssertGreaterThan(metrics.offset, 0)
        XCTAssertLessThan(metrics.offset, ceil(view.font.leading - view.font.descender))
        XCTAssertGreaterThanOrEqual(metrics.thickness, 1)
        XCTAssertEqual(view.linkUnderlines.color, Theme.dark.term[4])

        view.apply(TerminalAppearance(theme: .dark, fontName: "Menlo", fontSize: 22))
        XCTAssertGreaterThan(view.linkUnderlines.metrics.cell.width, metrics.cell.width, "a fonte cresceu")
    }

    func testUnderlinesCoverTheWholeTerminal() {
        let view = makeView()
        XCTAssertTrue(view.linkUnderlines.superview === view)
        XCTAssertTrue(view.subviews.first === view.linkUnderlines, "por baixo do cursor e da barra de rolagem")
        XCTAssertEqual(view.linkUnderlines.frame, view.bounds)
        view.setFrameSize(NSSize(width: 900, height: 500))
        XCTAssertEqual(view.linkUnderlines.frame, view.bounds)
    }

    func testUnderlinesAreRedoneWhenTheTerminalIsResized() {
        let view = makeView()
        view.getTerminal().feed(text: "https://example.com/" + String(repeating: "a", count: 40))
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<60)])
        // Mais estreito, o texto muda de lugar, e o sublinhado acompanha na hora.
        view.setFrameSize(NSSize(width: 300, height: 400))
        XCTAssertLessThan(view.getTerminal().cols, 60)
        XCTAssertNotEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<60)])
        XCTAssertEqual(view.linkUnderlines.spans, TerminalLinks.spans(in: view.getTerminal()))
    }

    func testCheapReadingOfTheLinksHasNoWait() {
        let view = makeView()
        var now: TimeInterval = 100
        view.uptime = { defer { now += 0.001 }; return now }
        view.feed(text: "https://example.com/a")
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<21)])
        view.feed(text: "b")
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<22)])
    }

    func testReadingOfTheLinksThatCostsTooMuchIsSpacedOut() {
        let view = makeView()
        // Deixa passar o redesenho que a criação da vista agenda. Daqui em diante o texto entra direto
        // no emulador: nenhum redesenho fica agendado, e só o próprio terminal pode voltar a ler os links.
        waitUntil(timeout: 0.1) { false }
        var now: TimeInterval = 100, step: TimeInterval = 0.005
        // Cada consulta ao relógio anda um passo: a leitura que consulta no começo e no fim custou um passo.
        view.uptime = { defer { now += step }; return now }
        view.getTerminal().feed(text: "https://example.com/a")
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [LinkSpan(row: 0, columns: 0..<21)])

        // Cedo demais: em vez de um sublinhado velho no lugar errado, nenhum.
        view.getTerminal().feed(text: "b")
        view.refreshLinkUnderlines()
        XCTAssertEqual(view.linkUnderlines.spans, [])

        // Passado o prazo ele volta sozinho, já com o texto novo.
        now = 200
        step = 0
        XCTAssertTrue(waitUntil(timeout: 5) { view.linkUnderlines.spans == [LinkSpan(row: 0, columns: 0..<22)] })
    }

    func testClipboardReplyNeverReachesTheProcess() {
        let view = makeView()
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf pronto; read x"], environment: environment,
                          currentDirectory: "/")
        let terminal = view.getTerminal()
        func firstLine() -> String { terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? "" }
        XCTAssertTrue(waitUntil { firstLine() == "pronto" })

        // O que o SwiftTerm manda ao processo quando a saída pede `ESC ] 52 ; c ; ?`:
        // o clipboard do usuário em base64. O tty ecoa o que chega, então dá para ver se passou.
        view.send(source: terminal, data: Array("\u{1b}]52;c;c2VncmVkbw==\u{1b}\\".utf8)[...])
        view.send(source: terminal, data: Array("eco".utf8)[...])
        XCTAssertTrue(waitUntil { firstLine().hasSuffix("eco") })
        XCTAssertEqual(firstLine(), "prontoeco")
        ProcessReaper.hangUp(view.process.shellPid, grace: 0.3)
    }

    func testOnlyTheClipboardReplyIsDropped() {
        func isClipboardReply(_ bytes: [UInt8]) -> Bool { AgentTerminalView.isClipboardReply(bytes[...]) }
        XCTAssertTrue(isClipboardReply(Array("\u{1b}]52;c;c2VncmVkbw==\u{1b}\\".utf8)))
        XCTAssertTrue(isClipboardReply(Array("\u{1b}]52;;\u{1b}\\".utf8)), "clipboard vazio")
        XCTAssertTrue(isClipboardReply([0x9d] + Array("52;c;c2VncmVkbw==".utf8) + [0x9c]), "controles de 8 bits")

        XCTAssertFalse(isClipboardReply(Array("\u{1b}[5;1R".utf8)), "posição do cursor")
        XCTAssertFalse(isClipboardReply(Array("\u{1b}]11;rgb:0d0d/1111/1717\u{1b}\\".utf8)), "cor de fundo")
        XCTAssertFalse(isClipboardReply(Array("\u{1b}]520;x\u{1b}\\".utf8)))
        XCTAssertFalse(isClipboardReply(Array("52;c;c2VncmVkbw==".utf8)))
        XCTAssertFalse(isClipboardReply([]))
        XCTAssertFalse(isClipboardReply([0x1b]))
    }

    func testApplySetsFontAndColors() {
        let view = makeView()
        view.apply(TerminalAppearance(theme: .dark, fontName: "Menlo", fontSize: 15))
        XCTAssertEqual(view.font.pointSize, 15)
        XCTAssertEqual(view.font.familyName, "Menlo")
        XCTAssertEqual(view.nativeBackgroundColor, Theme.dark.bg.nsColor)

        view.apply(TerminalAppearance(theme: .dark, fontName: "Fonte Que Nao Existe", fontSize: 11))
        XCTAssertEqual(view.font.pointSize, 11, "fonte desconhecida cai na monoespaçada do sistema")
    }

    func testHangUpKillsAProcessThatIgnoresSIGHUP() {
        let view = makeView()
        view.startProcess(executable: "/bin/sh", args: ["-c", "trap '' HUP; printf pronto; read x"],
                          environment: environment, currentDirectory: "/")
        XCTAssertTrue(waitUntil { view.linesAboveCursor().isEmpty && view.getTerminal().getCursorLocation().x == 6 })
        let pid = view.process.shellPid
        XCTAssertEqual(kill(pid, 0), 0)

        ProcessReaper.hangUp(pid, grace: 0.3)
        // Um zumbi ainda responde ao sinal 0: sumir da tabela prova que o filho foi recolhido.
        XCTAssertTrue(waitUntil(timeout: 5) { kill(pid, 0) != 0 })
    }

    func testHangUpIgnoresInvalidPids() {
        ProcessReaper.hangUp(0)
        ProcessReaper.hangUp(1)
        ProcessReaper.hangUp(-1)
    }

    // MARK: ⇧⌘C

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    /// Terminal numa janela, com o texto já na tela e a cópia num pasteboard só do teste.
    private func picking(_ text: String) -> (AgentTerminalView, NSWindow, NSPasteboard) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: true)
        let view = makeView()
        window.contentView = view
        view.feed(text: text)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("clark-linhas-\(UUID().uuidString)"))
        view.lineNumbers.pasteboard = pasteboard
        window.makeFirstResponder(view)
        return (view, window, pasteboard)
    }

    func testCopyLinesNumbersTheScreenAndCopiesTheChosenOne() {
        let (view, window, pasteboard) = picking("um\r\n\r\ndois\r\ntres")
        XCTAssertTrue(view.beginLineSelection())
        XCTAssertEqual(view.lineNumbers.picker?.lines.map(\.text), ["um", "dois", "tres"], "a linha em branco fica sem número")
        XCTAssertTrue(window.firstResponder === view.lineNumbers, "o teclado é da escolha")
        XCTAssertFalse(view.lineNumbers.isHidden)
        view.lineNumbers.keyDown(with: key(18, "1"))
        view.lineNumbers.keyDown(with: key(125, modifiers: .shift))
        view.lineNumbers.keyDown(with: key(36))
        XCTAssertEqual(pasteboard.string(forType: .string), "um\ndois")
        XCTAssertTrue(window.firstResponder === view, "volta para a linha de digitação do agente")
        XCTAssertTrue(view.lineNumbers.isHidden)
    }

    func testWrappedLineIsCopiedWhole() {
        let long = String(repeating: "abcdefghij", count: 12)
        let (view, _, pasteboard) = picking(long + "\r\nfim")
        XCTAssertTrue(view.beginLineSelection())
        view.lineNumbers.keyDown(with: key(126))
        view.lineNumbers.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), long, "o terminal quebrou por largura: é uma linha só")
    }

    func testEscapeAndClickLeaveWithoutCopying() {
        let (view, window, pasteboard) = picking("um\r\ndois")
        pasteboard.clearContents()
        XCTAssertTrue(view.beginLineSelection())
        view.lineNumbers.keyDown(with: key(53))
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue(window.firstResponder === view)

        XCTAssertTrue(view.beginLineSelection())
        // O clique do mouse dá o teclado ao terminal.
        window.makeFirstResponder(view)
        XCTAssertFalse(view.lineNumbers.isPicking)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testEmptyScreenHasNothingToPick() {
        let (view, window, _) = picking("")
        XCTAssertFalse(view.beginLineSelection())
        XCTAssertTrue(window.firstResponder === view)
    }
}
