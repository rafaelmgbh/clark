import AppKit
import ClarkCore

/// Menu em cascata no estilo do app. Mostra um `NSMenu` qualquer em painéis sem borda, um por nível.
///
/// Os painéis nunca viram a janela principal: o terminal continua com o foco. Enquanto o menu está
/// aberto, as teclas e o clique fora dele chegam por um monitor de eventos.
final class PixelMenu {
    enum Key {
        case up, down, left, right, enter, escape
    }

    /// Um nível aberto.
    struct Level {
        let panel: NSPanel
        let view: PixelMenuView
        /// Linha cujo submenu está no nível seguinte.
        var openRow: Int?
    }

    /// Quanto o cursor fica noutra linha até o submenu aberto trocar: dá tempo de atravessar as linhas
    /// na diagonal a caminho dele.
    static let hoverPause = 0.25
    /// Vão entre a view que abriu o menu e o menu.
    static let gap: CGFloat = 4

    var theme = Theme.dark
    /// Põe um painel na tela, preso à janela de quem abriu o menu. Os testes trocam para não abrir janela.
    var present: (NSPanel, NSWindow?) -> Void = { panel, parent in
        if let parent {
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.orderFront(nil)
        }
    }
    /// Área da tela em que o menu pode aparecer.
    var bounds: (NSWindow?) -> NSRect = { ($0?.screen ?? NSScreen.main)?.visibleFrame ?? .zero }

    private(set) var levels: [Level] = []
    private weak var parent: NSWindow?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var pause: Timer?

    var isOpen: Bool { !levels.isEmpty }

    deinit { close() }

    // MARK: abrir e fechar

    /// Abre o menu logo abaixo de `anchor`, alinhado à esquerda dela.
    func show(_ menu: NSMenu, below anchor: NSView) {
        guard let window = anchor.window else { return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        show(menu, at: NSPoint(x: rect.minX, y: rect.minY - Self.gap), over: window)
    }

    /// Abre o menu com o canto de cima à esquerda em `topLeft`, em coordenadas da tela.
    func show(_ menu: NSMenu, at topLeft: NSPoint, over window: NSWindow?) {
        close()
        parent = window
        let bounds = bounds(window)
        push(menu) { Self.rootFrame(size: $0, topLeft: topLeft, within: bounds) }
        listen()
    }

    func close() {
        cancelPause()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        while let level = levels.popLast() { dismiss(level.panel) }
    }

    private func push(_ menu: NSMenu, frame: (NSSize) -> NSRect) {
        let index = levels.count
        let view = PixelMenuView(items: menu.items)
        view.theme = theme
        view.onHover = { [weak self] in self?.hover($0, level: index) }
        view.onChoose = { [weak self] in self?.choose($0, level: index) }
        let panel = NSPanel(contentRect: frame(NSSize(width: view.fittingWidth, height: view.fittingHeight)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Vazado: a sombra é a que a view desenha, deslocada.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        levels.append(Level(panel: panel, view: view, openRow: nil))
        present(panel, parent)
    }

    private func dismiss(_ panel: NSPanel) {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Fecha os níveis abertos a partir do nível `index`, que fica.
    private func closeLevels(after index: Int) {
        while levels.count > index + 1 { dismiss(levels.removeLast().panel) }
        if levels.indices.contains(index) { levels[index].openRow = nil }
    }

    /// Abre ao lado o submenu da linha, se ela tem um.
    private func openSubmenu(of row: Int?, level index: Int) {
        guard let row, let submenu = levels[index].view.items[row].submenu else { return }
        closeLevels(after: index)
        let beside = levels[index].panel.frame
        let rowTop = beside.maxY - CGFloat(levels[index].view.top(of: row))
        let bounds = bounds(parent)
        push(submenu) { Self.submenuFrame(size: $0, beside: beside, rowTop: rowTop, within: bounds) }
        levels[index].openRow = row
    }

    // MARK: lugar na tela

    /// Onde fica o primeiro nível, em coordenadas da tela. O que não cabe abaixo do ponto rola.
    static func rootFrame(size: NSSize, topLeft: NSPoint, within bounds: NSRect) -> NSRect {
        guard !bounds.isEmpty else {
            return NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        }
        let height = min(size.height, max(0, topLeft.y - bounds.minY))
        let x = max(bounds.minX, min(topLeft.x, bounds.maxX - size.width))
        return NSRect(x: x, y: topLeft.y - height, width: size.width, height: height)
    }

    /// Onde fica um submenu: à direita do nível que o abriu, com a primeira linha na altura de `rowTop`.
    /// Sem espaço à direita vai para a esquerda; sem espaço abaixo, sobe; mais alto que a tela, rola.
    static func submenuFrame(size: NSSize, beside parent: NSRect, rowTop: CGFloat, within bounds: NSRect) -> NSRect {
        let shadow = CGFloat(PixelMenuView.shadow), border = CGFloat(PixelMenuView.border)
        // As molduras dos dois níveis ficam uma sobre a outra.
        var x = parent.maxX - shadow - border
        let top = rowTop + CGFloat(PixelMenuView.inset)
        guard !bounds.isEmpty else { return NSRect(x: x, y: top - size.height, width: size.width, height: size.height) }
        if x + size.width > bounds.maxX { x = max(bounds.minX, parent.minX + border - (size.width - shadow)) }
        let height = min(size.height, bounds.height)
        let y = max(bounds.minY, min(top, bounds.maxY) - height)
        return NSRect(x: x, y: y, width: size.width, height: height)
    }

    // MARK: mouse

    /// O cursor está na linha `row` do nível `index`, ou saiu das linhas dele.
    func hover(_ row: Int?, level index: Int) {
        guard levels.indices.contains(index) else { return }
        // Quem trouxe o cursor até este nível volta a ficar destacado, mesmo que no caminho ele tenha
        // atravessado outras linhas.
        for above in 0..<index { levels[above].view.highlighted = levels[above].openRow }
        let open = levels[index].openRow
        let target = row ?? open
        levels[index].view.highlighted = target
        if target == open {
            cancelPause()
        } else if open == nil {
            cancelPause()
            openSubmenu(of: target, level: index)
        } else {
            pause?.invalidate()
            pause = Timer.scheduledTimer(withTimeInterval: Self.hoverPause, repeats: false) { [weak self] _ in
                self?.settleHover()
            }
        }
    }

    /// O cursor parou: o submenu aberto passa a ser o da linha em que ele está.
    func settleHover() {
        cancelPause()
        guard let index = levels.firstIndex(where: { $0.openRow != nil && $0.openRow != $0.view.highlighted }) else {
            return
        }
        closeLevels(after: index)
        openSubmenu(of: levels[index].view.highlighted, level: index)
    }

    private func cancelPause() {
        pause?.invalidate()
        pause = nil
    }

    /// A linha foi clicada, ou escolhida pelo teclado: abre o submenu dela, ou fecha o menu e manda a
    /// ação do item.
    func choose(_ row: Int, level index: Int) {
        guard levels.indices.contains(index), levels[index].view.items.indices.contains(row) else { return }
        let item = levels[index].view.items[row]
        if item.hasSubmenu {
            cancelPause()
            levels[index].view.highlighted = row
            if levels[index].openRow != row { openSubmenu(of: row, level: index) }
            return
        }
        close()
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
    }

    // MARK: teclado

    /// Tecla no nível mais fundo que tem linha destacada. Devolve false com o menu fechado.
    @discardableResult
    func keyDown(_ key: Key) -> Bool {
        guard isOpen else { return false }
        cancelPause()
        let index = levels.lastIndex { $0.view.highlighted != nil } ?? 0
        let view = levels[index].view
        switch key {
        case .up, .down:
            guard let row = MenuNavigation.next(from: view.highlighted, step: key == .down ? 1 : -1,
                                                selectable: view.selectable) else { break }
            closeLevels(after: index)
            view.highlighted = row
            view.reveal(row: row)
        case .right, .enter:
            guard let row = view.highlighted else { break }
            if view.items[row].hasSubmenu {
                enterSubmenu(of: row, level: index)
            } else if key == .enter {
                choose(row, level: index)
            }
        case .left:
            if index > 0 { closeLevels(after: index - 1) }
        case .escape:
            close()
        }
        return true
    }

    /// Abre o submenu da linha e leva o destaque para a primeira linha dele.
    private func enterSubmenu(of row: Int, level index: Int) {
        if levels[index].openRow != row { openSubmenu(of: row, level: index) }
        guard levels.count > index + 1 else { return }
        let child = levels[index + 1].view
        child.highlighted = MenuNavigation.next(from: nil, step: 1, selectable: child.selectable)
        if let first = child.highlighted { child.reveal(row: first) }
    }

    private static func key(forCode code: UInt16) -> Key? {
        switch code {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        // Return, Enter do teclado numérico e espaço.
        case 36, 76, 49: return .enter
        case 53: return .escape
        default: return nil
        }
    }

    // MARK: eventos do app

    private func listen() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.intercept(event)
        }
        var watched: [(NSNotification.Name, AnyObject?)] = [(NSApplication.didResignActiveNotification, nil)]
        if let parent {
            watched += [(NSWindow.didResignKeyNotification, parent), (NSWindow.willCloseNotification, parent)]
        }
        observers = watched.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                self?.close()
            }
        }
    }

    /// O que sobra de um evento do app com o menu aberto. nil: o menu ficou com ele.
    func intercept(_ event: NSEvent) -> NSEvent? {
        guard isOpen else { return event }
        if event.type == .keyDown {
            // Toda tecla fica no menu: nenhuma letra escapa para o terminal que está por baixo. Com ⌘
            // é atalho: fecha, e o ⌘D que abriu o menu serve para fechá-lo.
            if event.modifierFlags.contains(.command) {
                close()
            } else if let key = Self.key(forCode: event.keyCode) {
                keyDown(key)
            }
            return nil
        }
        if let window = event.window, levels.contains(where: { $0.panel === window }) { return event }
        // O clique fora fecha o menu e não vale como clique: no botão que o abriu, não o reabre.
        close()
        return nil
    }
}
