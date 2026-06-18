import Foundation
import Testing
@testable import CodexQ

struct QuotaRefreshPolicyTests {
    @Test("刷新失败后快速重试，避免网络恢复后长时间停留在失败状态")
    func failureUsesShortRetryInterval() {
        #expect(QuotaRefreshPolicy.intervalAfterRefresh(succeeded: false) == .seconds(15))
        #expect(QuotaRefreshPolicy.intervalAfterRefresh(succeeded: true) == .seconds(180))
    }

    @Test("打开弹窗时失败或过期数据会立即刷新")
    func presentationRefreshesFailedOrStaleState() {
        let now = Date()

        #expect(QuotaRefreshPolicy.shouldRefreshOnPresentation(
            remainingPercent: 70,
            lastUpdatedAt: now,
            errorMessage: "刷新失败",
            isRefreshing: false,
            now: now
        ))
        #expect(QuotaRefreshPolicy.shouldRefreshOnPresentation(
            remainingPercent: 70,
            lastUpdatedAt: now.addingTimeInterval(-601),
            errorMessage: nil,
            isRefreshing: false,
            now: now
        ))
        #expect(!QuotaRefreshPolicy.shouldRefreshOnPresentation(
            remainingPercent: 70,
            lastUpdatedAt: now,
            errorMessage: nil,
            isRefreshing: false,
            now: now
        ))
    }

    @Test("已有刷新进行中时打开弹窗不重复发起刷新")
    func presentationDoesNotDuplicateRefresh() {
        #expect(!QuotaRefreshPolicy.shouldRefreshOnPresentation(
            remainingPercent: 70,
            lastUpdatedAt: Date().addingTimeInterval(-601),
            errorMessage: "刷新失败",
            isRefreshing: true,
            now: Date()
        ))
    }
}
