import AppKit
import Foundation
import UserNotifications

@MainActor
internal final class AppNotifications: NSObject, HookEventNotifying, UNUserNotificationCenterDelegate {
    internal static let shared = AppNotifications()
    private var didRequestAuth = false
    private var onActivateSession: ((UUID) -> Void)?

    internal func configure(onActivateSession: @escaping (UUID) -> Void) {
        self.onActivateSession = onActivateSession
        UNUserNotificationCenter.current().delegate = self
    }

    internal func requestAuthorizationIfNeeded() {
        guard !didRequestAuth else {
            return
        }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.app.error("UN auth error: \(String(describing: error), privacy: .public)")
            }
            Log.app.info("UN auth granted=\(granted, privacy: .public)")
        }
    }

    internal func post(title: String, body: String, sessionID: UUID?) {
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

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated internal func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated internal func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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

    deinit {
        // Process-lifetime singleton; nothing to release.
    }
}
