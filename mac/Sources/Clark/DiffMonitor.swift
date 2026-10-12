import ClarkCore
import Foundation

/// O diff da pasta de um agente: lê fora da thread principal e guarda o último resultado.
final class DiffMonitor {
    /// Uma leitura por vez no app inteiro: vários agentes no mesmo repositório não disputam o disco.
    private static let listQueue = DispatchQueue(label: "clark.diff.list", qos: .utility)
    /// O diff de um arquivo tem alguém esperando para ler: não fica atrás das listas.
    private static let fileQueue = DispatchQueue(label: "clark.diff.file", qos: .userInitiated)

    /// Uma leitura terminou. Chamado na thread principal.
    var onChange: (() -> Void)?
    private(set) var runner: GitRunner?
    private(set) var state = DiffState.unknown
    /// Leituras concluídas. Sobe mesmo quando a lista veio igual: o conteúdo de um arquivo pode ter
    /// mudado sem mudar as contagens.
    private(set) var revision = 0
    private var directory: String?
    /// Troca com a pasta: o que chegar de uma leitura da pasta anterior é descartado.
    private var generation = 0
    private var reading = false
    private var pending = false

    var isLoading: Bool { reading }

    /// Totais para o cabeçalho e o card. nil sem lista ou com o repositório limpo.
    var summary: DiffSummary? {
        guard case .changes(let changes) = state, !changes.files.isEmpty else { return nil }
        return changes.summary
    }

    /// Diz onde ler e com que git. Na mesma pasta o último resultado continua valendo até a próxima leitura.
    func configure(runner: GitRunner?, directory: String) {
        let moved = directory != self.directory || (runner == nil) != (self.runner == nil)
        self.runner = runner
        self.directory = directory
        guard moved else { return }
        generation += 1
        state = runner == nil ? .noGit : .unknown
    }

    /// Pede uma leitura. Os pedidos feitos enquanto outra está em curso viram uma leitura só, logo depois.
    func refresh() {
        guard let runner, let directory else { return }
        guard !reading else {
            pending = true
            return
        }
        reading = true
        let generation = generation
        Self.listQueue.async { [weak self] in
            let state = runner.changes(in: directory)
            DispatchQueue.main.async { self?.finished(state, generation: generation) }
        }
    }

    private func finished(_ state: DiffState, generation: Int) {
        let current = generation == self.generation
        let again = pending || !current
        reading = false
        pending = false
        if current {
            self.state = state
            revision += 1
        }
        if again { refresh() }
        if current { onChange?() }
    }

    /// Diff de um arquivo da lista atual. A resposta chega depois, na thread principal. nil: sem lista,
    /// ou o git não respondeu.
    func loadDiff(of file: DiffFile, completion: @escaping (FileDiff?) -> Void) {
        guard let runner, case .changes(let changes) = state else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        Self.fileQueue.async {
            let diff = runner.diff(of: file, in: changes)
            DispatchQueue.main.async { completion(diff) }
        }
    }
}
