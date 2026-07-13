import Foundation
import UserNotifications

actor QuotaNotificationService {
    static func crossedThreshold(previous: Double, current: Double, threshold: Int) -> Bool {
        previous >= Double(threshold) && current < Double(threshold)
    }

    static func notificationBody(name: String, threshold: Int) -> String {
        let limitName = name.hasSuffix("限额") ? name : "\(name)限额"
        return "\(limitName)已低于 \(threshold)%"
    }

    static func isSameResetCycle(previous: QuotaWindow, current: QuotaWindow) -> Bool {
        guard let previousResetsAt = previous.resetsAt,
              let currentResetsAt = current.resetsAt else {
            return false
        }
        return previousResetsAt == currentResetsAt
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notifyCrossings(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        thresholds: [Int]
    ) async {
        guard let previous else { return }
        if let previousFiveHour = previous.fiveHour,
           let currentFiveHour = current.fiveHour {
            await notify(
                name: "5 小时",
                previous: previousFiveHour,
                current: currentFiveHour,
                thresholds: thresholds
            )
        }
        await notify(name: "周限额", previous: previous.weekly, current: current.weekly, thresholds: thresholds)
    }

    private func notify(
        name: String,
        previous: QuotaWindow,
        current: QuotaWindow,
        thresholds: [Int]
    ) async {
        guard Self.isSameResetCycle(previous: previous, current: current) else { return }
        for threshold in thresholds where Self.crossedThreshold(
            previous: previous.remainingPercent,
            current: current.remainingPercent,
            threshold: threshold
        )
        {
            let content = UNMutableNotificationContent()
            content.title = "CodexQ 额度提醒"
            content.body = Self.notificationBody(name: name, threshold: threshold)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(name)-\(current.resetsAt?.timeIntervalSince1970 ?? 0)-\(threshold)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
