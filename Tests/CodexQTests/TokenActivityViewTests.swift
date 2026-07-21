import Combine
import Foundation
import Testing
@testable import CodexQ

struct TokenActivityViewTests {
    @Test("活动请求随额度请求立即并发启动")
    @MainActor
    func activityStartsWhileQuotaRequestIsSuspended() async {
        let quotaGate = ActivityGate()
        let activityGate = ActivityGate()
        let activityStarted = AsyncStream<Void>.makeStream()
        var activityStartedIterator = activityStarted.stream.makeAsyncIterator()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: {
                await quotaGate.wait()
                return quota
            },
            readTokenActivity: {
                activityStarted.continuation.yield()
                await activityGate.wait()
                return .init(peakDailyTokens: 0, days: [])
            },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        let refreshTask = Task { @MainActor in await store.refresh() }
        _ = await activityStartedIterator.next()

        #expect(store.isRefreshing)
        #expect(store.isTokenActivityRefreshing)

        quotaGate.open()
        #expect(await refreshTask.value)
        activityGate.open()
    }

    @Test("挂起的 Token 活动不会阻塞额度刷新返回")
    @MainActor
    func suspendedActivityDoesNotBlockQuotaRefresh() async {
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        var startedIterator = started.stream.makeAsyncIterator()
        var refreshResult: Bool?
        var activityCallCount = 0
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                activityCallCount += 1
                started.continuation.yield()
                for await _ in release.stream { break }
                throw ActivityFixtureError.unavailable
            },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        let refreshTask = Task { @MainActor in
            refreshResult = await store.refresh()
        }
        _ = await startedIterator.next()
        await Task.yield()
        let returnedBeforeActivityFinished = refreshResult
        let quotaRefreshingBeforeRelease = store.isRefreshing
        let activityRefreshingBeforeRelease = store.isTokenActivityRefreshing
        let secondQuotaResult = await store.refresh()
        release.continuation.yield()
        _ = await refreshTask.value

        #expect(returnedBeforeActivityFinished == true)
        #expect(!quotaRefreshingBeforeRelease)
        #expect(activityRefreshingBeforeRelease)
        #expect(secondQuotaResult)
        #expect(activityCallCount == 1)
    }

    @Test("Token 活动失败不回滚额度缓存和通知")
    @MainActor
    func activityFailurePreservesQuotaSideEffects() async {
        var cacheSaveCount = 0
        var notificationCallCount = 0
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: { throw ActivityFixtureError.unavailable },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in cacheSaveCount += 1 },
            notifyQuotaCrossings: { _, _ in notificationCallCount += 1 }
        )
        let activityFinished = AsyncStream<Void>.makeStream()
        var activityFinishedIterator = activityFinished.stream.makeAsyncIterator()
        let cancellable = store.$isTokenActivityRefreshing
            .dropFirst()
            .filter { !$0 }
            .sink { _ in activityFinished.continuation.yield() }

        let succeeded = await store.refresh()
        _ = await activityFinishedIterator.next()

        #expect(succeeded)
        #expect(store.snapshot == quota)
        #expect(store.errorMessage == nil)
        #expect(store.tokenActivity == nil)
        #expect(store.tokenActivityErrorMessage != nil)
        #expect(cacheSaveCount == 1)
        #expect(notificationCallCount == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test("后台重试期间保留已有错误，直到刷新真正恢复")
    @MainActor
    func retryKeepsExistingFailureVisibleUntilSuccess() async {
        let retryGate = ActivityGate()
        let retryStarted = AsyncStream<Void>.makeStream()
        var retryStartedIterator = retryStarted.stream.makeAsyncIterator()
        var quotaCallCount = 0
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: {
                quotaCallCount += 1
                if quotaCallCount == 1 {
                    throw ActivityFixtureError.unavailable
                }
                retryStarted.continuation.yield()
                await retryGate.wait()
                return quota
            },
            readTokenActivity: { throw ActivityFixtureError.unavailable },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        #expect(!(await store.refresh()))
        let firstError = store.errorMessage
        #expect(firstError != nil)
        let retryTask = Task { @MainActor in await store.refresh() }
        _ = await retryStartedIterator.next()

        #expect(store.isRefreshing)
        #expect(store.errorMessage == firstError)

        retryGate.open()
        #expect(await retryTask.value)
        #expect(store.errorMessage == nil)
    }

    @Test("停止后的旧活动任务不能清理新任务状态")
    @MainActor
    func stoppedActivityTaskCannotClearNewGeneration() async {
        let firstGate = ActivityGate()
        let secondGate = ActivityGate()
        let firstStarted = AsyncStream<Void>.makeStream()
        let secondStarted = AsyncStream<Void>.makeStream()
        var firstStartedIterator = firstStarted.stream.makeAsyncIterator()
        var secondStartedIterator = secondStarted.stream.makeAsyncIterator()
        var callCount = 0
        let quota = QuotaSnapshot(
            fiveHour: nil,
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                callCount += 1
                if callCount == 1 {
                    firstStarted.continuation.yield()
                    await firstGate.wait()
                } else {
                    secondStarted.continuation.yield()
                    await secondGate.wait()
                }
                return .init(peakDailyTokens: 0, days: [])
            },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        #expect(await store.refresh())
        _ = await firstStartedIterator.next()
        store.stop()
        #expect(!store.isTokenActivityRefreshing)

        #expect(await store.refresh())
        _ = await secondStartedIterator.next()
        firstGate.open()
        await Task.yield()

        #expect(store.isTokenActivityRefreshing)
        #expect(callCount == 2)
        secondGate.open()
    }

    @Test("弹窗依次展示 Token 活动、限额重置和设置")
    func popoverOrdersTokenActivityBeforeResetCreditsAndSettings() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let activityIndex = try #require(source.range(of: "TokenActivitySection("))
        let resetCreditsIndex = try #require(source.range(of: "ResetCreditsSection("))
        let settingsIndex = try #require(source.range(of: "EmbeddedSettingsView("))

        #expect(activityIndex.lowerBound < resetCreditsIndex.lowerBound)
        #expect(activityIndex.lowerBound < settingsIndex.lowerBound)
        #expect(resetCreditsIndex.lowerBound < settingsIndex.lowerBound)
    }

    @Test("只有手动刷新让按钮转圈，后台刷新只负责禁用按钮")
    func refreshButtonOnlySpinsForManualRefresh() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains("store.isRefreshing || store.isTokenActivityRefreshing"))
        #expect(source.contains("Task { await store.refreshFromButton() }"))
        #expect(source.contains("if store.isRefreshButtonBusy"))
        #expect(!source.contains("if isAnyRefreshing"))
        #expect(source.contains(".disabled(isAnyRefreshing)"))
    }

    @Test("底部图标操作提供明确的中文提示与辅助功能标签")
    func footerActionsHaveClearChineseLabels() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains(".help(\"设置\")"))
        #expect(source.contains(".accessibilityLabel(\"设置\")"))
        #expect(source.contains(".help(\"立即刷新\")"))
        #expect(source.contains(".accessibilityLabel(\"立即刷新\")"))
    }

    @Test("弹窗底部操作统一为同尺寸图标按钮")
    func footerActionsUseConsistentIconButtons() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains("private struct FooterIconButtonLabel"))
        #expect(source.contains("systemName: \"power\""))
        #expect(source.contains(".frame(width: 24, height: 24)"))
        #expect(!source.contains("Button(\"退出\")"))
    }

    @Test("Pace 风险提示沿用 OpenUsage 的火焰与次级文字样式")
    func paceWarningMatchesOpenUsageStyle() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let rowSource = try sourceSection(
            source,
            from: "private struct QuotaRow",
            to: "private struct ContinuousQuotaBar"
        )

        #expect(rowSource.contains("Image(systemName: \"flame.fill\")"))
        #expect(rowSource.contains(".foregroundStyle(Color(nsColor: .systemRed))"))
        #expect(rowSource.contains(".foregroundStyle(.secondary)"))
        #expect(rowSource.contains(".font(.caption)"))
        #expect(rowSource.contains(".frame(width: QuotaBarLayout.width(for: period))"))
        #expect(rowSource.contains("VStack(alignment: .trailing, spacing: 3)"))
        let titleIndex = try #require(rowSource.range(of: "Text(title)")?.lowerBound)
        let spacerIndex = try #require(
            rowSource.range(of: "Spacer()", range: titleIndex..<rowSource.endIndex)?.lowerBound
        )
        let paceIndex = try #require(
            rowSource.range(of: "if let projection", range: titleIndex..<rowSource.endIndex)?.lowerBound
        )
        #expect(titleIndex < spacerIndex)
        #expect(spacerIndex < paceIndex)
        #expect(rowSource.contains("Text(\"\\(Int(window.remainingPercent.rounded()))%\")"))
    }

    @Test("额度条与 Pace 刻度沿用 OpenUsage 系统样式")
    func quotaBarAndPaceTickMatchOpenUsageStyle() throws {
        let quotaSource = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let resetSource = try String(
            contentsOfFile: "Sources/CodexQ/Views/ResetCreditsSection.swift",
            encoding: .utf8
        )

        #expect(quotaSource.contains("Capsule().fill(.quaternary)"))
        #expect(quotaSource.contains("Color(nsColor: .systemBlue)"))
        #expect(quotaSource.contains("Color(nsColor: .systemYellow)"))
        #expect(quotaSource.contains("Color(nsColor: .systemRed)"))
        #expect(quotaSource.contains(".overlay(alignment: .leading)"))
        #expect(quotaSource.contains("RoundedRectangle(cornerRadius: 1)"))
        #expect(quotaSource.contains(".fill(Color.primary.opacity(0.55))"))
        #expect(resetSource.contains("summary.availableCount > 0 ? Color.accentColor : Color.secondary"))
    }

    @Test("活动日历的次级标签与空方块保持可读")
    func activitySecondaryContentKeepsReadableContrast() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(source.contains("Color.primary.opacity(0.72)"))
        #expect(source.contains("Color.secondary.opacity(0.12)"))
        #expect(source.contains("Color.secondary.opacity(0.18)"))
    }

    @Test("低频设置默认折叠并由底部齿轮控制")
    func settingsAreCollapsedBehindGearButton() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains("@State private var isSettingsExpanded = false"))
        #expect(source.contains("if isSettingsExpanded"))
        #expect(source.contains("gearshape.fill"))
        #expect(source.contains("interactionDidChange(.settings, isSettingsExpanded)"))
    }

    @Test("鼠标停留与展开状态会上报并在关闭后复位")
    func popoverReportsInteractionsAndResetsExpansionOnClose() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )

        #expect(source.contains(".onHover"))
        #expect(source.contains("interactionDidChange(.pointer, isHovering)"))
        #expect(source.contains("interactionDidChange(.resetCredits, isExpanded)"))
        #expect(source.contains(".onChange(of: store.isPopoverPresented)"))
        #expect(source.contains("isResetCreditsExpanded = false"))
        #expect(source.contains("isSettingsExpanded = false"))
    }

    @Test("只有成功定位到屏幕后才标记弹窗已展示")
    func popoverPresentationStateFollowsSuccessfulPositioning() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )
        let toggleStart = try #require(source.range(of: "@objc private func togglePopover()"))
        let toggleEnd = try #require(
            source.range(of: "private func panelDidClose()", range: toggleStart.upperBound..<source.endIndex)
        )
        let toggleSource = source[toggleStart.lowerBound..<toggleEnd.lowerBound]
        let screenGuard = try #require(toggleSource.range(of: "guard let anchorRect"))
        let presentedState = try #require(toggleSource.range(of: "store.setPopoverPresented(true)"))

        #expect(screenGuard.lowerBound < presentedState.lowerBound)
    }

    @Test("每日路径调用共享方块、单位和等级")
    func dailyModeCallsSharedSquareFormatterAndLevel() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )
        let dailySource = try sourceSection(
            source,
            from: "private struct DailyActivitySquare",
            to: "private struct TokenActivitySquare"
        )

        #expect(dailySource.contains("TokenActivitySquare("))
        #expect(dailySource.contains("TokenCountFormatter.string"))
        #expect(dailySource.contains("TokenActivityLevel.level"))
    }

    @Test("Token 活动显示最近完整日与累计 Token 汇总")
    func activityShowsLatestRecordedDayAndLifetimeTokenSummary() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(source.contains("累计 Token"))
        #expect(source.contains("snapshot.lifetimeTokens"))
        #expect(source.contains("TokenActivityPresentation.latestRecordedDay("))
        #expect(source.contains("TokenActivityDateLabel.string("))
        #expect(!source.contains("今日 Token"))
        #expect(source.contains("TokenCountFormatter.compactNumber"))
        #expect(source.contains("TokenActivityInlineSummary("))
        #expect(!source.contains("TokenActivitySummaryRow"))
        #expect(!source.contains(".background(.quaternary"))
    }

    @Test("服务端日期始终使用公历展示")
    func activityUsesGregorianCalendarForServerDates() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(source.contains("Calendar(identifier: .gregorian)"))
        #expect(!source.contains("Calendar.autoupdatingCurrent"))
        #expect(source.components(separatedBy: "format.calendar = calendar").count - 1 == 2)
        #expect(source.components(separatedBy: "format.timeZone = calendar.timeZone").count - 1 == 2)
    }

    @Test("Token 活动只保留三个月每日入口")
    func activityUIHasNoWeeklyControlsOrRenderer() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(!source.contains("Picker("))
        #expect(!source.contains("WeeklyTokenActivityGrid"))
        #expect(!source.contains("WeeklyActivitySquare"))
        #expect(!source.contains("case weekly"))
        #expect(source.contains(".accessibilityLabel("))
        #expect(source.contains(".accessibilityValue("))
    }

    @Test("活动 loading 独立且空快照仍绘制完整日历")
    func popoverUsesIndependentLoadingAndEmptyStateKeepsGrid() throws {
        let popoverSource = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let activitySource = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )
        let emptyIndex = try #require(activitySource.range(of: "暂无 Token 使用记录"))
        let gridIndex = try #require(activitySource.range(of: "DailyTokenActivityGrid("))

        #expect(popoverSource.contains("isRefreshing: store.isTokenActivityRefreshing"))
        #expect(activitySource.contains("hasRecordedTokens"))
        #expect(gridIndex.lowerBound < emptyIndex.lowerBound)
    }

    @Test("设计与计划只保留近三个月每日口径")
    func docsContainNoSupersededWeeklyOrSwitchingLanguage() throws {
        for path in [
            "docs/superpowers/specs/2026-07-13-token-activity-design.md",
            "docs/superpowers/plans/2026-07-13-token-activity.md"
        ] {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let lowercased = source.lowercased()

            #expect(!lowercased.contains("week-grouped"))
            #expect(!lowercased.contains("both modes"))
            #expect(!source.contains("切换"))
        }
    }

    private func sourceSection(_ source: String, from start: String, to end: String) throws -> String {
        let startIndex = try #require(source.range(of: start)?.lowerBound)
        let endIndex = try #require(source.range(of: end, range: startIndex..<source.endIndex)?.lowerBound)
        return String(source[startIndex..<endIndex])
    }
}

@MainActor
private final class ActivityGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private enum ActivityFixtureError: Error {
    case unavailable
}
