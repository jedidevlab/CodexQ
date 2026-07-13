import Foundation
import UserNotifications

actor QuotaNotificationService {
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
        guard previous.resetsAt == current.resetsAt else { return }
        for threshold in thresholds where previous.remainingPercent > Double(threshold)
            && current.remainingPercent <= Double(threshold)
        {
            let content = UNMutableNotificationContent()
            content.title = "CodexQ 额度提醒"
            content.body = "\(name)剩余 \(Int(current.remainingPercent.rounded()))%，已低于 \(threshold)%"
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
