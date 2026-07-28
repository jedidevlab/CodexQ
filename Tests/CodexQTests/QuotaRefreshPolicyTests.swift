import Foundation
import Testing
@testable import CodexQ

struct QuotaNotificationTests {
    @Test("系统通知未授权时不发送提醒")
    func deniedAuthorizationPreventsDelivery() {
        #expect(!NotificationAuthorizationPolicy.canSendNotifications(authorizationGranted: false))
        #expect(NotificationAuthorizationPolicy.canSendNotifications(authorizationGranted: true))
    }

    @Test("系统拒绝通知后保留用户的额度预警选择")
    func deniedAuthorizationDoesNotTurnOffPreference() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains("settings.updateNotificationPermissionWarning(authorizationGranted: granted)"))
        #expect(!source.contains(
            "settings.notificationsEnabled = NotificationAuthorizationPolicy"
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

    @Test("自定义阈值参与提醒并与相同预设去重")
    func customThresholdIsClampedAndDeduplicated() {
        #expect(QuotaWarningThresholds.resolved(
            notifyAt20: true,
            notifyAt10: false,
            notifyAt5: false,
            notifyAtCustom: true,
            customThreshold: 20
        ) == [20])
        #expect(QuotaWarningThresholds.resolved(
            notifyAt20: true,
            notifyAt10: false,
            notifyAt5: false,
            notifyAtCustom: true,
            customThreshold: 7
        ) == [20, 7])
        #expect(QuotaWarningThresholds.resolved(
            notifyAt20: false,
            notifyAt10: false,
            notifyAt5: false,
            notifyAtCustom: true,
            customThreshold: 0
        ) == [1])
        #expect(QuotaWarningThresholds.resolved(
            notifyAt20: false,
            notifyAt10: false,
            notifyAt5: false,
            notifyAtCustom: true,
            customThreshold: 100
        ) == [99])
    }

    @Test("设置页提供可持久化的自定义额度预警阈值")
    func settingsExposePersistentCustomThreshold() throws {
        let settingsSource = try String(
            contentsOfFile: "Sources/CodexQ/Stores/AppSettings.swift",
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let notificationRowStart = try #require(
            viewSource.range(of: "HStack(spacing: 4) {\n                Toggle(\"额度预警通知\"")
        )
        let notificationRowEnd = try #require(
            viewSource.range(
                of: "if settings.notificationsEnabled,\n               let warning",
                range: notificationRowStart.upperBound..<viewSource.endIndex
            )
        )
        let notificationRow = viewSource[
            notificationRowStart.lowerBound..<notificationRowEnd.lowerBound
        ]

        #expect(settingsSource.contains("static let notifyAtCustom = \"notifyAtCustom\""))
        #expect(settingsSource.contains("static let customWarningThreshold = \"customWarningThreshold\""))
        #expect(notificationRow.contains("Toggle(\"自定义\""))
        #expect(notificationRow.contains("value: customWarningThresholdBinding"))
        #expect(notificationRow.components(separatedBy: "HStack(spacing: 4)").count == 2)
        #expect(viewSource.contains("输入 1–99 的剩余额度百分比"))
        #expect(viewSource.contains(".frame(width: 380)"))
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
