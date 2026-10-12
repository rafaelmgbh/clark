import AppKit

/// Barra de menus. Os itens sem alvo sobem pela cadeia de resposta até o `MainWindowController`.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("CLARK", [
            item("Sobre o CLARK", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Ocultar o CLARK", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar os outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Sair do CLARK", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Arquivo", [
            item("Novo agente", #selector(MainWindowController.newAgent(_:)), "n"),
            item("Trocar pasta…", #selector(MainWindowController.chooseFolder(_:)), "d"),
            .separator(),
            item("Fechar agente", #selector(MainWindowController.closeAgent(_:)), "w"),
            item("Fechar todos…", #selector(MainWindowController.closeAllAgents(_:)), ""),
        ]))
        main.addItem(submenu("Editar", [
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Colar", #selector(NSText.paste(_:)), "v"),
            item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
        ]))
        // O `=` invisível faz o ⌘+ funcionar sem o Shift nos teclados em que o + fica na tecla do =.
        let plainPlus = item("Aumentar a fonte", #selector(MainWindowController.increaseFont(_:)), "=")
        plainPlus.isHidden = true
        plainPlus.allowsKeyEquivalentWhenHidden = true
        main.addItem(submenu("Visualizar", [
            item("Alternar foco e grade", #selector(MainWindowController.toggleLayout(_:)), "l"),
            item("Zoom no agente", #selector(MainWindowController.toggleZoom(_:)), "\r"),
            .separator(),
            item("Aumentar a fonte", #selector(MainWindowController.increaseFont(_:)), "+"),
            plainPlus,
            item("Diminuir a fonte", #selector(MainWindowController.decreaseFont(_:)), "-"),
            item("Tamanho original", #selector(MainWindowController.resetFont(_:)), "0"),
        ]))
        var agents: [NSMenuItem] = [
            item("Agente anterior", #selector(MainWindowController.previousAgent(_:)), "{"),
            item("Próximo agente", #selector(MainWindowController.nextAgent(_:)), "}"),
            item("Renomear…", #selector(MainWindowController.renameAgent(_:)), ""),
            .separator(),
        ]
        for number in 1...9 {
            let entry = item("Agente \(number)", #selector(MainWindowController.selectAgentByNumber(_:)), "\(number)")
            entry.tag = number
            agents.append(entry)
        }
        main.addItem(submenu("Agentes", agents))
        let window = submenu("Janela", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom da janela", #selector(NSWindow.performZoom(_:)), ""),
        ])
        NSApplication.shared.windowsMenu = window.submenu
        main.addItem(window)
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }
}
