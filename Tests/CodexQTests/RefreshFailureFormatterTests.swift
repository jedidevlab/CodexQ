import Foundation
import Testing
@testable import CodexQ

struct RefreshFailureFormatterTests {
    @Test("额度接口请求失败时底部状态显示具体原因")
    func rateLimitFetchFailureShowsSpecificSummary() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let now = updatedAt.addingTimeInterval(5 * 60)
        let error = "Codex app-server 返回错误：failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"

        #expect(RefreshFailureFormatter.status(
            error: error,
            updatedAt: updatedAt,
            now: now
        ) == "5 分钟前更新 · 额度接口请求失败")
    }

    @Test("无缓存失败时使用短错误摘要")
    func missingCacheFailureShowsShortSummary() {
        let error = "Codex app-server 返回错误：failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"

        #expect(RefreshFailureFormatter.summary(error) == "额度接口请求失败")
        #expect(RefreshFailureFormatter.status(
            error: error,
            updatedAt: nil,
            now: Date()
        ) == "暂无缓存 · 额度接口请求失败")
    }
}
