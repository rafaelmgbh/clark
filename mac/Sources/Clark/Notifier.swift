import AppKit
import UserNotifications

/// Avisos de agente pronto. Separado num protocolo para os testes não tocarem no sistema.
protocol Notifying: AnyObject {
    /// Chamado com o `session_id` do agente quando o usuário clica na notificação.
    var onOpen: ((String) -> Void)? { get set }
    /// Notificação do macOS e pedido de atenção no Dock.
    func agentDone(name: String, sessionID: String)
    /// Selo do Dock com a contagem de agentes em DONE.
    func setBadge(_ count: Int)
}

final class Notifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?
    // Sem bundle (binário solto do `swift build`) o centro de notificações aborta o processo.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()

    func start() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func agentDone(name: String, sessionID: String) {
        NSApp.requestUserAttention(.informationalRequest)
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "CLARK · \(name)"
        content.body = "Terminou e está te esperando."
        content.sound = .default
        content.userInfo = ["session_id": sessionID]
        // O mesmo identificador por agente: um aviso novo substitui o anterior.
        center.add(UNNotificationRequest(identifier: sessionID, content: content, trigger: nil))
    }

    func setBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionID = response.notification.request.content.userInfo["session_id"] as? String
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            if let sessionID { self?.onOpen?(sessionID) }
            completionHandler()
        }
    }
}
