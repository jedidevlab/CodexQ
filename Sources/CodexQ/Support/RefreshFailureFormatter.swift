import Foundation

enum RefreshFailureFormatter {
    static func status(error: String, updatedAt: Date?, now: Date) -> String {
        let prefix = updatedAt.map {
            RelativeUpdateFormatter.string(since: $0, now: now)
        } ?? "暂无缓存"
        return "\(prefix) · \(summary(error))"
    }

    static func summary(_ error: String) -> String {
        let message = error
            .replacingOccurrences(of: "Codex app-server 返回错误：", with: "")

        if message.contains("failed to fetch codex rate limits") {
            return "额度接口请求失败"
        }
        if message.contains("responseTimedOut") || message.contains("响应超时") {
            return "响应超时"
        }
        return message
    }
}
