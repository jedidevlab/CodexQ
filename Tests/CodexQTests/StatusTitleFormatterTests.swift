import Foundation
import Testing
@testable import CodexQ

struct StatusTitleFormatterTests {
    @Test("有效额度显示整数百分比")
    func validQuotaShowsRoundedPercent() {
        let now = Date()

        #expect(StatusTitleFormatter.string(
            remainingPercent: 88.6,
            lastUpdatedAt: now,
            error: nil,
            now: now
        ) == "89%")
    }

    @Test("无数据时隐藏百分比")
    func missingQuotaHidesTitle() {
        #expect(StatusTitleFormatter.string(
            remainingPercent: nil,
            lastUpdatedAt: nil,
            error: nil,
            now: Date()
        ).isEmpty)
    }

    @Test("刷新失败但有新鲜缓存时仍显示百分比")
    func refreshFailureWithFreshCacheShowsTitle() {
        let now = Date()

        #expect(StatusTitleFormatter.hasFreshQuota(
            remainingPercent: 89,
            lastUpdatedAt: now,
            now: now
        ))
        #expect(StatusTitleFormatter.string(
            remainingPercent: 89,
            lastUpdatedAt: now,
            error: "刷新失败",
            now: now
        ) == "89%")
    }

    @Test("数据超过十分钟时隐藏百分比")
    func staleQuotaHidesTitle() {
        let now = Date()

        #expect(StatusTitleFormatter.string(
            remainingPercent: 89,
            lastUpdatedAt: now.addingTimeInterval(-601),
            error: nil,
            now: now
        ).isEmpty)
    }
}
