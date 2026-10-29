import Foundation
import UserNotifications
import ChargeGuardCore

/// User notifications for calibration phases, heat pauses, helper problems and schedule runs.
/// The daemon cannot post notifications (it has no user session), so it forwards events to the app.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var enabled: () -> Bool = { true }

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, identifier: String = UUID().uuidString) {
        guard enabled() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func post(_ event: PolicyEvent) {
        guard event.notifiesUser else { return }
        post(title: Self.title(for: event), body: event.summary)
    }

    static func title(for event: PolicyEvent) -> String {
        switch event {
        case .heatPaused, .heatResumed: return "Heat Protection"
        case .calibrationPhaseChanged, .calibrationFinished: return "Calibration"
        case .scheduleRan, .scheduleMissed: return "Schedule"
        case .backendError, .backendChanged: return "ChargeGuard helper"
        case .conflictDetected: return "Another charging tool is running"
        case .topUpFinished: return "Top Up"
        default: return "ChargeGuard"
        }
    }

    // Show banners even while the pop-up is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
