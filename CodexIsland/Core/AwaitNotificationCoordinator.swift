import Foundation
import UserNotifications

final class AwaitNotificationCoordinator {
    static let shared = AwaitNotificationCoordinator()

    private let notificationCooldown: TimeInterval = 30
    private var lastNotificationAtBySession: [String: Date] = [:]

    private init() {}

    func configure() {
        let category = UNNotificationCategory(
            identifier: "CODEX_AWAIT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("Notification permission request failed: \(error.localizedDescription)")
                return
            }

            print(granted ? "Notification permission granted" : "Notification permission denied")
        }
    }

    func notifyIfNeeded(sessionId: String?, reason: AwaitReason?) {
        let key = sessionId ?? "__unknown_session__"
        let now = Date()

        if let lastSentAt = lastNotificationAtBySession[key],
           now.timeIntervalSince(lastSentAt) < notificationCooldown {
            return
        }

        lastNotificationAtBySession[key] = now
        sendNotification(reason: reason)
    }

    private func sendNotification(reason: AwaitReason?) {
        let content = UNMutableNotificationContent()
        content.title = "Codex 正在等待您的回复"
        content.body = notificationBody(for: reason)
        content.sound = .default
        content.categoryIdentifier = "CODEX_AWAIT"

        let request = UNNotificationRequest(
            identifier: "codex-await-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to send await notification: \(error.localizedDescription)")
            }
        }
    }

    private func notificationBody(for reason: AwaitReason?) -> String {
        guard let reason else {
            return "需要您的输入"
        }

        switch reason {
        case .toolApproval(let tool, let command):
            if let command, !command.isEmpty {
                return "需要审批 \(tool)：\(String(command.prefix(80)))"
            }

            return "需要审批 \(tool)"

        case .question(let text):
            if let text, !text.isEmpty {
                return String(text.prefix(80))
            }

            return "需要您的回答"
        }
    }
}
