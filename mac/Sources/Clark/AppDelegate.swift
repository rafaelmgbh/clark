import AppKit
import ClarkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: CLIOptions
    private let home: String
    private let notifier = Notifier()
    private var controller: MainWindowController?

    init(options: CLIOptions, home: String) {
        self.options = options
        self.home = home
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateRunningInstance() {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.build()
        notifier.start()

        let store = ConfigStore(directory: ConfigStore.defaultDirectory(home: home))
        let loaded = store.load()
        let controller = MainWindowController(config: loaded.config, store: store, home: home, notifier: notifier)
        self.controller = controller
        controller.window?.setFrameAutosaveName("ClarkMainWindow")
        controller.diffAutosaveName = "ClarkDiff"
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        let processEnvironment = ProcessInfo.processInfo.environment
        let shell = ShellEnvironment.shellPath(processEnvironment: processEnvironment)
        let options = options, home = home
        let companies = store.companiesData()
        DispatchQueue.global(qos: .userInitiated).async {
            let capture = ShellEnvironment.capture(shell: shell, processEnvironment: processEnvironment)
            // O que o rc do shell devolve a um agente que nasceu sem a variável.
            let restored = ShellEnvironment.secretsRestoredByShell(shell: shell, environment: capture.variables)
            DispatchQueue.main.async {
                var warnings: [String] = []
                if let warning = loaded.warning { warnings.append(warning) }
                if !capture.captured { warnings.append("ambiente do shell nao lido: valendo o PATH padrao") }
                let palette = Theme.named(loaded.config.theme)
                let resolver = CompanyResolver(json: companies, palette: palette.agents, fallbackColor: palette.dim) {
                    PathTools.canonical($0, base: home, home: home)
                }
                if let warning = ShellEnvironment.restoredSecretsWarning(restored,
                                                                         globalAllow: resolver.globalEnvAllow) {
                    warnings.append(warning)
                }
                let launch = AgentLaunch(
                    baseEnvironment: capture.variables,
                    claudePath: ClaudeLocator.find(path: capture.variables["PATH"], home: home),
                    gitPath: GitLocator.find(path: capture.variables["PATH"]),
                    shell: shell, home: home, claudeArgs: options.claudeArgs, resolver: resolver)
                controller.start(launch: launch, options: options, startupWarnings: warnings)
            }
        }
    }

    /// Já existe um CLARK aberto: traz a janela dele para a frente em vez de abrir outro,
    /// porque dois apps gravariam o mesmo `config.json`.
    private func activateRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard let other = others.first else { return false }
        other.activate(options: [.activateAllWindows])
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.liveAgentCount > 0 else { return .terminateNow }
        let count = controller.liveAgentCount
        let alert = NSAlert()
        alert.messageText = "Sair do CLARK?"
        alert.informativeText = (count == 1 ? "1 agente ainda está rodando." : "\(count) agentes ainda estão rodando.")
            + " As conversas ficam salvas e voltam ao reabrir."
        alert.addButton(withTitle: "Sair")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}

enum ClarkMain {
    /// Resposta das opções que imprimem e saem, sem abrir a janela.
    static func immediateOutput(for options: CLIOptions) -> String? {
        if options.showVersion { return "clark \(ClarkVersion.current)" }
        if options.showHelp { return CLIOptions.usage }
        return nil
    }

    /// `--export-icon`: grava o PNG e devolve o código de saída. nil quando a opção não veio.
    static func exportIcon(for options: CLIOptions) -> Int32? {
        guard let path = options.exportIcon else { return nil }
        guard let png = AppIcon.png(size: options.iconSize),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else {
            FileHandle.standardError.write(Data("clark: o ícone não foi gravado em \(path)\n".utf8))
            return 1
        }
        return 0
    }

    static func run() {
        let home = NSHomeDirectory()
        var launchDirectory = FileManager.default.currentDirectoryPath
        // Aberto pelo Finder, o app nasce na raiz do disco.
        if launchDirectory == "/" { launchDirectory = home }
        let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()),
                                       launchDirectory: launchDirectory, home: home)
        if let text = immediateOutput(for: options) {
            print(text)
            return
        }
        if let status = exportIcon(for: options) {
            if status != 0 { exit(status) }
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate(options: options, home: home)
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        // O `delegate` de NSApplication é fraco: o `withExtendedLifetime` segura o objeto até o fim.
        withExtendedLifetime(delegate) { application.run() }
    }
}
