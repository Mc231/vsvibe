import Foundation

/// Delivers user-facing notifications for hook events. `AppNotifications` is
/// the production implementation; tests inject a recorder.
@MainActor
internal protocol HookEventNotifying: AnyObject {
    /// Registers the handler invoked when the user clicks a notification that
    /// carries a session id.
    func configure(onActivateSession: @escaping (UUID) -> Void)

    /// Posts a notification; `sessionID` is attached so a click can focus it.
    func post(title: String, body: String, sessionID: UUID?)
}
