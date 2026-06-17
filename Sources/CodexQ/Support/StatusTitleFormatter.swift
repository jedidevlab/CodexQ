import Foundation

enum StatusTitleFormatter {
    static func hasFreshQuota(
        remainingPercent: Double?,
        lastUpdatedAt: Date?,
        now: Date
    ) -> Bool {
        guard remainingPercent != nil,
              let lastUpdatedAt else {
            return false
        }
        return now.timeIntervalSince(lastUpdatedAt) <= 600
    }

    static func string(
        remainingPercent: Double?,
        lastUpdatedAt: Date?,
        error: String?,
        now: Date
    ) -> String {
        guard let remainingPercent,
              hasFreshQuota(
                remainingPercent: remainingPercent,
                lastUpdatedAt: lastUpdatedAt,
                now: now
              ) else {
            return ""
        }

        return "\(Int(remainingPercent.rounded()))%"
    }
}
