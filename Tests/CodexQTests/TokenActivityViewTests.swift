import Foundation
import Testing
@testable import CodexQ

struct TokenActivityViewTests {
    @Test("Token 活动失败独立于成功的额度刷新")
    @MainActor
    func activityFailureDoesNotReplaceSuccessfulQuota() async {
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: { throw ActivityFixtureError.unavailable },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notificationsEnabled: { false }
        )

        let succeeded = await store.refresh()

        #expect(succeeded)
        #expect(store.snapshot == quota)
        #expect(store.errorMessage == nil)
        #expect(store.tokenActivity == nil)
        #expect(store.tokenActivityErrorMessage != nil)
    }

    @Test("弹窗在设置前嵌入 Token 活动区域")
    func popoverEmbedsTokenActivityBeforeSettings() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let activityIndex = try #require(source.range(of: "TokenActivitySection("))
        let settingsIndex = try #require(source.range(of: "EmbeddedSettingsView("))

        #expect(activityIndex.lowerBound < settingsIndex.lowerBound)
    }

    @Test("每日与每周路径共享 Token 单位和活动等级")
    func bothModesUseSharedFormatterAndLevel() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(source.components(separatedBy: "TokenCountFormatter.string").count >= 3)
        #expect(source.components(separatedBy: "TokenActivityLevel.level").count >= 3)
        #expect(source.contains(".pickerStyle(.segmented)"))
    }
}

private enum ActivityFixtureError: Error {
    case unavailable
}
