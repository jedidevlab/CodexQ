import Foundation
import Testing
@testable import CodexQ

struct TokenActivityViewTests {
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

        let succeeded = await store.refresh()
        for _ in 0..<100 where store.isTokenActivityRefreshing {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(succeeded)
        #expect(store.snapshot == quota)
        #expect(store.errorMessage == nil)
        #expect(store.tokenActivity == nil)
        #expect(store.tokenActivityErrorMessage != nil)
        #expect(cacheSaveCount == 1)
        #expect(notificationCallCount == 1)
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

    @Test("活动 loading 独立且空快照不绘制日历")
    func popoverUsesIndependentLoadingAndEmptyStatePrecedesGrids() throws {
        let popoverSource = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let activitySource = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )
        let emptyIndex = try #require(activitySource.range(of: "if snapshot.days.isEmpty"))
        let gridIndex = try #require(activitySource.range(of: "DailyTokenActivityGrid("))

        #expect(popoverSource.contains("isRefreshing: store.isTokenActivityRefreshing"))
        #expect(emptyIndex.lowerBound < gridIndex.lowerBound)
    }

    private func sourceSection(_ source: String, from start: String, to end: String) throws -> String {
        let startIndex = try #require(source.range(of: start)?.lowerBound)
        let endIndex = try #require(source.range(of: end, range: startIndex..<source.endIndex)?.lowerBound)
        return String(source[startIndex..<endIndex])
    }
}

private enum ActivityFixtureError: Error {
    case unavailable
}
