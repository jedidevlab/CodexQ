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

    static func toolTip(
        remainingPercent: Double?,
        lastUpdatedAt: Date?,
        error: String?,
        now: Date
    ) -> String {
        if let error {
            return "CodexQ · 刷新失败 · \(error)"
        }

        guard let remainingPercent else {
            return "CodexQ · 暂无额度数据"
        }

        guard hasFreshQuota(
            remainingPercent: remainingPercent,
            lastUpdatedAt: lastUpdatedAt,
            now: now
        ) else {
            return "CodexQ · 数据超过 10 分钟未更新"
        }

        return "CodexQ · 5 小时剩余 \(Int(remainingPercent.rounded()))%"
    }
}
