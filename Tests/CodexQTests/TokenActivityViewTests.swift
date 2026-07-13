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

    @Test("Token 活动显示昨日与累计 Token 汇总")
    func activityShowsYesterdayAndLifetimeTokenSummary() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )

        #expect(source.contains("昨日 Token"))
        #expect(source.contains("累计 Token"))
        #expect(source.contains("snapshot.lifetimeTokens"))
        #expect(source.contains("TokenActivityPresentation.tokens("))
        #expect(source.contains("date(byAdding: .day, value: -1, to: now)"))
        #expect(source.contains("TokenActivityInlineSummary("))
        #expect(!source.contains("TokenActivitySummaryRow"))
        #expect(!source.contains(".background(.quaternary"))
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
