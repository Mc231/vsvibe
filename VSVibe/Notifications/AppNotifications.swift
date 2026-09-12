import Foundation
import UserNotifications
import AppKit

@MainActor
final class AppNotifications: NSObject {
    static let shared = AppNotifications()
    private var didRequestAuth = false
    private var onActivateSession: ((UUID) -> Void)?

    func configure(onActivateSession: @escaping (UUID) -> Void) {
        self.onActivateSession = onActivateSession
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.app.error("UN auth error: \(String(describing: error), privacy: .public)")
            }
            Log.app.info("UN auth granted=\(granted, privacy: .public)")
        }
    }

    func post(title: String, body: String, sessionID: UUID?) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let sessionID {
            content.userInfo["sessionID"] = sessionID.uuidString
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("UN add error: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension AppNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let idString = userInfo["sessionID"] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let idString, let id = UUID(uuidString: idString) {
                self.onActivateSession?(id)
            }
            completionHandler()
        }
    }
}
