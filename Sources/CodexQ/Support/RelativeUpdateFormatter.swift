import Foundation

enum RelativeUpdateFormatter {
    static func string(since updatedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))

        if elapsed < 60 {
            return "刚刚更新"
        }
        if elapsed < 60 * 60 {
            return "\(Int(elapsed / 60)) 分钟前更新"
        }
        if elapsed < 24 * 60 * 60 {
            return "\(Int(elapsed / (60 * 60))) 小时前更新"
        }
        return "\(Int(elapsed / (24 * 60 * 60))) 天前更新"
    }
}
