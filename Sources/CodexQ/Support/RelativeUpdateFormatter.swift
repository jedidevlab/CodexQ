import Foundation

enum RelativeUpdateFormatter {
    static func string(since updatedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        guard elapsed.isFinite else { return "很久前更新" }

        if elapsed < 60 {
            return "刚刚更新"
        }
        if elapsed < 60 * 60 {
            return "\(Int(elapsed / 60)) 分钟前更新"
        }
        if elapsed < 24 * 60 * 60 {
            return "\(Int(elapsed / (60 * 60))) 小时前更新"
        }
        let days = elapsed / (24 * 60 * 60)
        guard days < Double(Int.max) else { return "很久前更新" }
        return "\(Int(days)) 天前更新"
    }
}
