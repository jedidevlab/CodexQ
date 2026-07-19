import Foundation
import Testing
@testable import CodexQ

struct QuotaNotificationTests {
    @Test("通知权限被拒绝时关闭应用内通知开关")
    func deniedAuthorizationDisablesNotifications() {
        #expect(!NotificationAuthorizationPolicy.effectiveEnabled(
            requestedEnabled: true,
            authorizationGranted: false
        ))
        #expect(NotificationAuthorizationPolicy.effectiveEnabled(
            requestedEnabled: true,
            authorizationGranted: true
        ))
        #expect(!NotificationAuthorizationPolicy.effectiveEnabled(
            requestedEnabled: false,
            authorizationGranted: true
        ))
    }

    @Test("授权完成时以当前开关状态为准")
    func authorizationCompletionUsesCurrentToggleState() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains(
            "requestedEnabled: settings.notificationsEnabled,\n" +
            "                    authorizationGranted: granted"
        ))
        #expect(!source.contains(
            "requestedEnabled: requestedEnabled,\n" +
            "                    authorizationGranted: granted"
        ))
    }

    @Test("额度必须从阈值及以上降到阈值以下才提醒")
    func detectsStrictThresholdCrossing() {
        #expect(QuotaNotificationService.crossedThreshold(previous: 20, current: 19, threshold: 20))
        #expect(!QuotaNotificationService.crossedThreshold(previous: 21, current: 20, threshold: 20))
    }

    @Test("所有额度类型和提醒档位统一说明已低于触发阈值")
    func formatsEveryThresholdCrossingBody() {
        for threshold in [20, 10, 5] {
            #expect(QuotaNotificationService.notificationBody(name: "5 小时", threshold: threshold) == "5 小时限额已低于 \(threshold)%")
            #expect(QuotaNotificationService.notificationBody(name: "周限额", threshold: threshold) == "周限额已低于 \(threshold)%")
        }
    }

    @Test("缺少重置时间时不判断为同一额度周期")
    func doesNotNotifyAcrossUnknownResetCycle() {
        let previous = QuotaWindow(usedPercent: 10, resetsAt: nil, durationMinutes: 300)
        let current = QuotaWindow(usedPercent: 95, resetsAt: nil, durationMinutes: 300)

        #expect(QuotaNotificationService.isSameResetCycle(previous: previous, current: current) == false)
    }
}

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
