import Foundation

enum StatusTitleFormatter {
    static func string(
        remainingPercent: Double?,
        lastUpdatedAt: Date?,
        error: String?,
        now: Date
    ) -> String {
        guard error == nil,
              let remainingPercent,
              let lastUpdatedAt,
              now.timeIntervalSince(lastUpdatedAt) <= 600 else {
            return ""
        }

        return "\(Int(remainingPercent.rounded()))%"
    }
}
