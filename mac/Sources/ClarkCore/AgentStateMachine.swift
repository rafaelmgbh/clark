public enum AgentState: String, Sendable, CaseIterable {
    case boot = "BOOT"
    case working = "WORKING"
    case idle = "IDLE"
    case done = "DONE"
    /// Parado, com um comando do Claude Code rodando em segundo plano.
    case shell = "SHELL"
    case exited = "EXITED"
}

/// Estado de um agente a partir dos eventos do terminal. Porta de `AgentPane.update`,
/// `_attention`, `_on_commit`, `_on_contents` e `_on_focus` do original, com o relógio injetado.
public struct AgentStateMachine: Sendable {
    /// Saída a menos disso de uma tecla é eco da digitação, não trabalho.
    public static let inputQuiet = 0.3
    /// Houve saída há menos disso: o agente está trabalhando.
    public static let workingWindow = 1.0
    /// Trabalho mais curto que isso termina em IDLE, sem aviso.
    public static let minWork = 2.5
    public static let bootTime = 2.0
    public static let focusMute = 0.3
    public static let resizeMute = 0.5
    public static let layoutMute = 0.8

    public private(set) var state: AgentState = .boot
    public private(set) var hasInput = false
    /// O Claude Code diz que a sessão tem comando em segundo plano rodando.
    public private(set) var hasBackgroundShell = false
    /// Momento da última saída que contou como atividade.
    public private(set) var lastChange = -Double.infinity
    private var spawnTime: Double
    private var lastInput = -Double.infinity
    private var muteUntil = -Double.infinity
    private var workStart: Double?

    public init(now: Double) {
        spawnTime = now
    }

    /// O processo foi (re)aberto.
    public mutating func spawned(now: Double) {
        state = .boot
        spawnTime = now
        hasInput = false
        hasBackgroundShell = false
        workStart = nil
    }

    /// Ignora a saída do terminal pelos próximos `seconds`.
    public mutating func mute(_ seconds: Double, now: Double) {
        muteUntil = max(muteUntil, now + seconds)
    }

    public mutating func userInput(now: Double) {
        lastInput = now
        hasInput = true
        if state == .done { state = resting }
    }

    public mutating func output(now: Double) {
        if now < muteUntil || now - lastInput < Self.inputQuiet { return }
        lastChange = now
    }

    public mutating func focused(now: Double) {
        mute(Self.focusMute, now: now)
        if state == .done { state = resting }
    }

    public mutating func resized(now: Double) {
        mute(Self.resizeMute, now: now)
    }

    public mutating func layoutChanged(now: Double) {
        mute(Self.layoutMute, now: now)
    }

    /// Sino do terminal. Devolve true quando o agente deve notificar.
    @discardableResult
    public mutating func bell(watched: Bool) -> Bool {
        attention(watched: watched)
    }

    /// Tique de 100 ms. Devolve true quando o agente deve notificar.
    @discardableResult
    public mutating func tick(now: Double, watched: Bool) -> Bool {
        if state == .exited { return false }
        if now - lastChange < Self.workingWindow {
            if state != .working {
                state = .working
                workStart = now
            }
            return false
        }
        if state == .working {
            let worked = now - (workStart ?? now)
            workStart = nil
            if hasInput && worked > Self.minWork && !watched {
                return attention(watched: watched)
            }
            state = resting
            return false
        }
        if state == .boot && now - spawnTime > Self.bootTime {
            state = resting
        }
        return false
    }

    /// O que a saída do terminal não mostra: sobrou, ou não, comando rodando em segundo plano.
    public mutating func backgroundShell(_ running: Bool) {
        hasBackgroundShell = running
        if state == .idle || state == .shell { state = resting }
    }

    public mutating func exited() {
        state = .exited
        workStart = nil
    }

    private mutating func attention(watched: Bool) -> Bool {
        if watched || state == .exited {
            if state == .working { state = resting }
            return false
        }
        state = .done
        return true
    }

    /// Estado de quem não está trabalhando nem pedindo atenção.
    private var resting: AgentState { hasBackgroundShell ? .shell : .idle }
}
