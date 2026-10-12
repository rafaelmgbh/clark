import ClarkCore
import Foundation
@testable import Clark

final class SpyNotifier: Notifying {
    var onOpen: ((String) -> Void)?
    private(set) var done: [String] = []
    private(set) var badges: [Int] = []

    func agentDone(name: String, sessionID: String) { done.append(name) }
    func setBadge(_ count: Int) { badges.append(count) }
}

/// Um CLARK de teste: home temporária, `ConfigStore` próprio e relógio controlado.
final class ClarkFixture {
    let temp = TemporaryDirectory()
    let notifier = SpyNotifier()
    var now = 100.0
    private(set) var controllers: [MainWindowController] = []

    var home: String { temp.path }
    lazy var store = ConfigStore(directory: temp.path + "/.config/clark")

    /// Ambiente base dos agentes, como se tivesse vindo do shell de login.
    var environment: [String: String] { ["PATH": "/usr/bin:/bin", "HOME": home] }

    func launch(claude: String? = nil, claudeArgs: [String] = [], environment: [String: String]? = nil) -> AgentLaunch {
        let home = home
        let resolver = CompanyResolver(json: store.companiesData(), palette: Theme.dark.agents,
                                       fallbackColor: Theme.dark.dim) {
            PathTools.canonical($0, base: home, home: home)
        }
        return AgentLaunch(baseEnvironment: environment ?? self.environment, claudePath: claude, shell: "/bin/sh",
                           home: home, claudeArgs: claudeArgs, resolver: resolver)
    }

    func controller(config: ClarkConfig? = nil) -> MainWindowController {
        let controller = MainWindowController(config: config ?? store.load().config, store: store, home: home,
                                              notifier: notifier) { [unowned self] in self.now }
        controllers.append(controller)
        return controller
    }

    /// Controller já iniciado, sem `claude`: os agentes abrem `/bin/sh`.
    func started(agents count: Int = 0, config: ClarkConfig? = nil, claude: String? = nil,
                 claudeArgs: [String] = [], environment: [String: String]? = nil) -> MainWindowController {
        let controller = controller(config: config)
        var options = CLIOptions()
        options.count = count
        controller.start(launch: launch(claude: claude, claudeArgs: claudeArgs, environment: environment),
                         options: options)
        return controller
    }

    /// `claude` de mentira: um script que o teste escreve.
    func fakeClaude(_ script: String) -> String {
        temp.write("bin/claude", "#!/bin/sh\n" + script + "\n", permissions: 0o755)
    }

    /// Encerra os processos dos agentes. Chamar no `tearDown`.
    func shutdown() {
        controllers.forEach { $0.shutdown() }
        controllers = []
    }
}
