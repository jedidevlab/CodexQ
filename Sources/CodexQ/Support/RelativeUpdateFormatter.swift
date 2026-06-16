import Foundation

enum RelativeUpdateFormatter {
    static func string(since updatedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))

        if elapsed < 60 {
            return "Updated now"
        }
        if elapsed < 60 * 60 {
            return "Updated \(Int(elapsed / 60))m ago"
        }
        if elapsed < 24 * 60 * 60 {
            return "Updated \(Int(elapsed / (60 * 60)))h ago"
        }
        return "Updated \(Int(elapsed / (24 * 60 * 60)))d ago"
    }
}
