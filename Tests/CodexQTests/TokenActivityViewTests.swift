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
            readTokenCost: { emptyTokenCostSnapshot() },
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
        let activityCallCount = ActivityCounter()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                _ = await activityCallCount.increment()
                started.continuation.yield()
                for await _ in release.stream { break }
                throw ActivityFixtureError.unavailable
            },
            readTokenCost: { emptyTokenCostSnapshot() },
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
        #expect(await activityCallCount.value == 1)
    }

    @Test("挂起的 Token 活动不阻塞并发 Token 成本结果")
    @MainActor
    func suspendedActivityDoesNotDelayTokenCost() async {
        let activityStarted = AsyncStream<Void>.makeStream()
        let releaseActivity = AsyncStream<Void>.makeStream()
        var activityStartedIterator = activityStarted.stream.makeAsyncIterator()
        let expectedCost = emptyTokenCostSnapshot()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                activityStarted.continuation.yield()
                for await _ in releaseActivity.stream { break }
                return .init(peakDailyTokens: 0, days: [])
            },
            readTokenCost: { expectedCost },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        #expect(await store.refresh())
        _ = await activityStartedIterator.next()
        await Task.yield()

        #expect(store.tokenCost == expectedCost)
        #expect(store.isTokenActivityRefreshing)
        releaseActivity.continuation.yield()
    }

    @Test("挂起的 Token 成本不阻塞 Token 活动结果")
    @MainActor
    func suspendedCostDoesNotDelayTokenActivity() async {
        let costGate = ActivityGate()
        let activityStarted = AsyncStream<Void>.makeStream()
        var activityStartedIterator = activityStarted.stream.makeAsyncIterator()
        let expectedActivity = TokenActivitySnapshot(peakDailyTokens: 20, days: [])
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                activityStarted.continuation.yield()
                return expectedActivity
            },
            readTokenCost: {
                await costGate.wait()
                return emptyTokenCostSnapshot()
            },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        #expect(await store.refresh())
        _ = await activityStartedIterator.next()
        await Task.yield()

        #expect(store.tokenActivity == expectedActivity)
        #expect(store.isTokenActivityRefreshing)
        costGate.open()
    }

    @Test("活动与成本并发完成后发布账号补算结果")
    @MainActor
    func reconcilesPublishedCostWithAccountActivity() async {
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 150,
            lifetimeTokens: 150,
            days: []
        )
        let recordedCost = tokenCostSnapshot(tokens: 100, cost: 2)
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: { activity },
            readTokenCost: { recordedCost },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )
        let finished = AsyncStream<Void>.makeStream()
        var finishedIterator = finished.stream.makeAsyncIterator()
        let cancellable = store.$isTokenActivityRefreshing
            .dropFirst()
            .filter { !$0 }
            .sink { _ in finished.continuation.yield() }

        #expect(await store.refresh())
        _ = await finishedIterator.next()

        #expect(store.tokenCost?.lifetime.recordedTokens == 100)
        #expect(store.tokenCost?.lifetime.totalTokens == 150)
        #expect(store.tokenCost?.lifetime.recordedEstimatedCostUSD == 2)
        #expect(store.tokenCost?.lifetime.supplement?.estimatedCostUSD == 1)
        withExtendedLifetime(cancellable) {}
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
            readTokenCost: { emptyTokenCostSnapshot() },
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

    @Test("合并请求失败时仍单独刷新额度和 Token 活动")
    @MainActor
    func dashboardActivityFailureFallsBackToQuotaRefresh() async {
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 150,
            lifetimeTokens: 150,
            days: [.init(startDate: "2026-07-24", tokens: 150)]
        )
        let fallbackCalls = ActivityCounter()
        let store = QuotaStore(
            readDashboardSnapshots: { throw ActivityFixtureError.unavailable },
            readRateLimits: {
                _ = await fallbackCalls.increment()
                return quota
            },
            readTokenActivity: { activity },
            readTokenCost: { emptyTokenCostSnapshot() },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        let succeeded = await store.refresh()

        #expect(succeeded)
        #expect(store.snapshot == quota)
        #expect(store.errorMessage == nil)
        #expect(store.tokenActivity == activity)
        #expect(store.tokenActivityErrorMessage == nil)
        #expect(await fallbackCalls.value == 1)
    }

    @Test("临时失败保留上次成功的 Token 活动和成本")
    @MainActor
    func transientTokenFailuresKeepPreviousSnapshots() async {
        let activityCalls = ActivityCounter()
        let costCalls = ActivityCounter()
        let activity = TokenActivitySnapshot(peakDailyTokens: 20, days: [])
        let cost = emptyTokenCostSnapshot()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                if await activityCalls.increment() == 1 { return activity }
                throw ActivityFixtureError.unavailable
            },
            readTokenCost: {
                if await costCalls.increment() == 1 { return cost }
                throw ActivityFixtureError.unavailable
            },
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )
        let activityFinished = AsyncStream<Void>.makeStream()
        var activityFinishedIterator = activityFinished.stream.makeAsyncIterator()
        let cancellable = store.$isTokenActivityRefreshing
            .dropFirst()
            .filter { !$0 }
            .sink { _ in activityFinished.continuation.yield() }

        #expect(await store.refresh())
        _ = await activityFinishedIterator.next()
        #expect(store.tokenActivity == activity)
        #expect(store.tokenCost == cost)

        #expect(await store.refresh())
        _ = await activityFinishedIterator.next()
        #expect(store.tokenActivity == activity)
        #expect(store.tokenCost == cost)
        #expect(store.tokenActivityErrorMessage != nil)
        #expect(store.tokenCostErrorMessage != nil)
        withExtendedLifetime(cancellable) {}
    }

    @Test("同步文件变化只刷新 Token 成本")
    @MainActor
    func costSyncFileChangeRefreshesOnlyTokenCost() async {
        let changes = AsyncStream<Void>.makeStream()
        let costPublished = AsyncStream<TokenCostSnapshot>.makeStream()
        var costIterator = costPublished.stream.makeAsyncIterator()
        let quotaCalls = ActivityCounter()
        let activityCalls = ActivityCounter()
        let costCalls = ActivityCounter()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let expectedCost = tokenCostSnapshot(tokens: 200, cost: 4)
        let store = QuotaStore(
            readRateLimits: {
                _ = await quotaCalls.increment()
                return quota
            },
            readTokenActivity: {
                _ = await activityCalls.increment()
                return .init(peakDailyTokens: 0, days: [])
            },
            readTokenCost: {
                _ = await costCalls.increment()
                return expectedCost
            },
            costSyncChangeEvents: { changes.stream },
            costSyncChangeDebounce: .milliseconds(1),
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )
        let cancellable = store.$tokenCost
            .compactMap { $0 }
            .sink { costPublished.continuation.yield($0) }

        changes.continuation.yield()
        let published = await costIterator.next()
        store.stop()

        #expect(published == expectedCost)
        #expect(await costCalls.value == 1)
        #expect(await quotaCalls.value == 0)
        #expect(await activityCalls.value == 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test("成本刷新期间收到同步变化会在完成后补刷")
    @MainActor
    func costSyncFileChangeDuringRefreshQueuesAnotherRefresh() async {
        let changes = AsyncStream<Void>.makeStream()
        let firstCostStarted = AsyncStream<Void>.makeStream()
        var firstCostStartedIterator = firstCostStarted.stream.makeAsyncIterator()
        let firstCostGate = ActivityGate()
        let costCalls = ActivityCounter()
        let initialCost = tokenCostSnapshot(tokens: 100, cost: 2)
        let updatedCost = tokenCostSnapshot(tokens: 200, cost: 4)
        let store = QuotaStore(
            readTokenCost: {
                let call = await costCalls.increment()
                if call == 1 {
                    firstCostStarted.continuation.yield()
                    await firstCostGate.wait()
                    return initialCost
                }
                return updatedCost
            },
            costSyncChangeEvents: { changes.stream },
            costSyncChangeDebounce: .milliseconds(1),
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            notifyQuotaCrossings: { _, _ in }
        )

        changes.continuation.yield()
        _ = await firstCostStartedIterator.next()
        changes.continuation.yield()
        try? await Task.sleep(for: .milliseconds(20))
        firstCostGate.open()
        for _ in 0..<100 where await costCalls.value < 2 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        store.stop()

        #expect(await costCalls.value == 2)
        #expect(store.tokenCost == updatedCost)
    }

    @Test("重置明细瞬时缺失时保留同次数下尚未到期的最近明细")
    @MainActor
    func transientMissingResetCreditDetailsPreserveRecentDetails() async {
        let now = Date()
        let credit = ResetCredit(
            id: "credit-1",
            resetType: "codexRateLimits",
            status: "available",
            title: "完整额度重置",
            expiresAt: now.addingTimeInterval(3_600)
        )
        let cachedSnapshot = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080),
            resetCredits: .init(availableCount: 1, credits: [credit])
        )
        let incompleteSnapshot = QuotaSnapshot(
            fiveHour: .init(usedPercent: 30, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 45, resetsAt: nil, durationMinutes: 10_080),
            resetCredits: .init(availableCount: 1, credits: nil)
        )
        var savedSnapshot: CachedQuotaSnapshot?
        let store = QuotaStore(
            readRateLimits: { incompleteSnapshot },
            readTokenActivity: { .init(peakDailyTokens: 0, days: []) },
            readTokenCost: { emptyTokenCostSnapshot() },
            loadCachedSnapshot: {
                CachedQuotaSnapshot(snapshot: cachedSnapshot, updatedAt: now)
            },
            saveCachedSnapshot: { savedSnapshot = $0 },
            notifyQuotaCrossings: { _, _ in }
        )

        #expect(await store.refresh())
        #expect(store.snapshot?.fiveHour?.usedPercent == 30)
        #expect(store.snapshot?.resetCredits?.availableCredits == [credit])
        #expect(savedSnapshot?.snapshot.resetCredits?.availableCredits == [credit])
    }

    @Test("后台重试期间保留已有错误，直到刷新真正恢复")
    @MainActor
    func retryKeepsExistingFailureVisibleUntilSuccess() async {
        let retryGate = ActivityGate()
        let retryStarted = AsyncStream<Void>.makeStream()
        var retryStartedIterator = retryStarted.stream.makeAsyncIterator()
        let quotaCallCount = ActivityCounter()
        let quota = QuotaSnapshot(
            fiveHour: .init(usedPercent: 25, resetsAt: nil, durationMinutes: 300),
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: {
                let quotaCallNumber = await quotaCallCount.increment()
                if quotaCallNumber == 1 {
                    throw ActivityFixtureError.unavailable
                }
                retryStarted.continuation.yield()
                await retryGate.wait()
                return quota
            },
            readTokenActivity: { throw ActivityFixtureError.unavailable },
            readTokenCost: { emptyTokenCostSnapshot() },
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
        let activityCallCount = ActivityCounter()
        let quota = QuotaSnapshot(
            fiveHour: nil,
            weekly: .init(usedPercent: 40, resetsAt: nil, durationMinutes: 10_080)
        )
        let store = QuotaStore(
            readRateLimits: { quota },
            readTokenActivity: {
                let activityCallNumber = await activityCallCount.increment()
                if activityCallNumber == 1 {
                    firstStarted.continuation.yield()
                    await firstGate.wait()
                } else {
                    secondStarted.continuation.yield()
                    await secondGate.wait()
                }
                return .init(peakDailyTokens: 0, days: [])
            },
            readTokenCost: { emptyTokenCostSnapshot() },
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
        #expect(await activityCallCount.value == 2)
        secondGate.open()
    }

    @Test("弹窗依次展示 Token 活动、Token 成本、限额重置和设置")
    func popoverOrdersTokenActivityAndCostBeforeResetCreditsAndSettings() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let activityIndex = try #require(source.range(of: "TokenActivitySection("))
        let costIndex = try #require(source.range(of: "TokenCostSection("))
        let resetCreditsIndex = try #require(source.range(of: "ResetCreditsSection("))
        let settingsIndex = try #require(source.range(of: "EmbeddedSettingsView("))

        #expect(activityIndex.lowerBound < costIndex.lowerBound)
        #expect(costIndex.lowerBound < resetCreditsIndex.lowerBound)
        #expect(activityIndex.lowerBound < settingsIndex.lowerBound)
        #expect(resetCreditsIndex.lowerBound < settingsIndex.lowerBound)
    }

    @Test("弹窗顶部显示 app-server 返回的套餐类型")
    func popoverShowsDecodedPlanType() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        #expect(source.contains("PlanTypeFormatter.displayName(for: snapshot.planType)"))
        #expect(source.contains("PlanHeader(planName: planName)"))
        #expect(source.contains("private struct PlanHeader"))
        #expect(source.contains("private struct PlanBadge"))
        #expect(source.contains("struct InsetSeparator"))
        #expect(source.contains("Text(planName)"))
        #expect(source.contains("Capsule().fill(.thinMaterial)"))
        #expect(source.contains("Circle().fill(Color.accentColor)"))
        #expect(source.contains("VStack(spacing: 5)"))
        #expect(source.contains("InsetSeparator()"))
        #expect(source.contains("LinearGradient("))
        #expect(source.contains("Color.primary.opacity(0.08)"))
        #expect(source.contains("Color.primary.opacity(0.035)"))
        #expect(source.contains("Color(nsColor: .textBackgroundColor).opacity(0.16)"))
        #expect(!source.contains(".padding(.bottom, 1)"))
        let headerIndex = try #require(source.range(of: "PlanHeader(planName: planName)")?.lowerBound)
        let dividerIndex = try #require(
            source.range(
                of: "InsetSeparator()",
                range: headerIndex..<source.endIndex
            )?.lowerBound
        )
        let quotaIndex = try #require(
            source.range(
                of: "QuotaRow(",
                range: dividerIndex..<source.endIndex
            )?.lowerBound
        )
        #expect(headerIndex < dividerIndex)
        #expect(dividerIndex < quotaIndex)
        #expect(!source.contains("Text(\"套餐\")"))
    }

    @Test("弹窗所有分隔线使用嵌入式样式")
    func popoverUsesInsetSeparatorsEverywhere() throws {
        let paths = [
            "Sources/CodexQ/Views/QuotaPopoverView.swift",
            "Sources/CodexQ/Views/ResetCreditsSection.swift"
        ]
        let sources = try paths.map {
            try String(contentsOfFile: $0, encoding: .utf8)
        }
        let defaultDividerLines = sources.flatMap { source in
            source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { $0.trimmingCharacters(in: .whitespaces) == "Divider()" }
        }

        #expect(defaultDividerLines.isEmpty)
        #expect(sources.joined(separator: "\n").contains("InsetSeparator()"))
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

    @Test("底部栏与限额重置栏使用同一处分隔线间距")
    func footerRowUsesResetCreditSeparatorSpacing() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let footerSource = try sourceSection(
            source,
            from: "if isSettingsExpanded {",
            to: ".padding(.bottom, 10)"
        )

        #expect(footerSource.contains(".frame(width: 24, height: 24)"))
        #expect(source.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(!footerSource.contains("VStack(spacing: 10)"))
        #expect(source.contains(".padding(.bottom, 10)"))
        #expect(source.contains(".padding(.top, QuotaPopoverLayout.horizontalPadding)"))
    }

    @Test("5 小时与周限额按标题 Pace、进度条、额度重置三层排列")
    func paceWarningUsesOpenUsageQuotaRowLayout() throws {
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
        #expect(rowSource.contains("HStack(alignment: .firstTextBaseline, spacing: 6)"))
        #expect(rowSource.contains("HStack(alignment: .firstTextBaseline, spacing: 8)"))
        #expect(rowSource.contains(".frame(width: QuotaBarLayout.width(for: period))"))
        #expect(rowSource.contains("Button(action: toggleResetDisplay)"))
        #expect(rowSource.contains("formatter.oppositeString("))
        let titleIndex = try #require(rowSource.range(of: "Text(title)")?.lowerBound)
        let paceIndex = try #require(
            rowSource.range(of: "paceWarning", range: titleIndex..<rowSource.endIndex)?.lowerBound
        )
        let barIndex = try #require(
            rowSource.range(of: "ContinuousQuotaBar(", range: paceIndex..<rowSource.endIndex)?.lowerBound
        )
        let remainingIndex = try #require(
            rowSource.range(
                of: "Text(\"\\(Int(window.remainingPercent.rounded()))% 剩余\")",
                range: barIndex..<rowSource.endIndex
            )?.lowerBound
        )
        let resetIndex = try #require(
            rowSource.range(of: "private var resetLabel", range: remainingIndex..<rowSource.endIndex)?.lowerBound
        )
        #expect(titleIndex < paceIndex)
        #expect(paceIndex < barIndex)
        #expect(barIndex < remainingIndex)
        #expect(remainingIndex < resetIndex)
        #expect(rowSource.contains("Text(\"\\(Int(window.remainingPercent.rounded()))% 剩余\")"))
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

    @Test("热力图按弹窗宽度自动扩展并铺满")
    func activityHeatmapFillsPopoverWidth() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenActivitySection.swift",
            encoding: .utf8
        )
        let gridSource = try sourceSection(
            source,
            from: "private struct DailyTokenActivityGrid",
            to: "private struct ActivityMonth"
        )

        #expect(source.contains("static let contentWidth = QuotaPopoverLayout.width"))
        #expect(source.contains("static let squareSize: CGFloat = 11"))
        #expect(source.contains("static let minimumSpacing: CGFloat = 3"))
        #expect(source.contains("static let weekCount = max("))
        #expect(source.contains("static let spacing = weekCount > 1"))
        #expect(source.contains("contentWidth - squareSize * CGFloat(weekCount)"))
        #expect(source.contains("static let gridWidth = contentWidth"))
        #expect(source.contains("weekCount: TokenActivityGridLayout.weekCount"))
        #expect(gridSource.contains("ForEach(weeks)"))
        #expect(gridSource.contains("ForEach(monthSpans)"))
        #expect(!source.contains("monthWidth"))
        #expect(!source.contains("monthSpacing"))
    }

    @Test("低频设置默认折叠并由底部齿轮控制")
    func settingsAreCollapsedBehindGearButton() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let settingsSource = try sourceSection(
            source,
            from: "private struct EmbeddedSettingsView",
            to: "private struct QuotaRow"
        )

        #expect(source.contains("@State private var isSettingsExpanded = false"))
        #expect(source.contains("if isSettingsExpanded"))
        #expect(source.contains("gearshape.fill"))
        #expect(source.contains("interactionDidChange(.settings, isSettingsExpanded)"))
        #expect(settingsSource.contains("HStack(spacing: 4)"))
    }

    @Test("iCloud 同步设置明确区分活动与成本，并始终提供文件夹选择")
    func costSyncSettingsExplainDataImpact() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let impactRowSource = try sourceSection(
            source,
            from: "private func syncImpactRow",
            to: "private struct QuotaRow"
        )

        #expect(source.contains("Toggle(\"启用 iCloud 多设备成本同步\""))
        #expect(source.contains("ScrollingFolderPathText(path: settings.icloudCostSyncFolderPath)"))
        #expect(source.contains("Button(\"选择文件夹\")"))
        #expect(source.contains("path ?? \"尚未选择文件夹\""))
        #expect(source.contains(".repeatForever(autoreverses: true)"))
        #expect(source.contains("\"chart.bar.fill\""))
        #expect(source.contains("\"Token 活动不受影响\""))
        #expect(source.contains("\"始终读取当前账号的 app-server 数据。\""))
        #expect(source.contains("\"dollarsign.circle\""))
        #expect(source.contains("\"Token 成本\""))
        #expect(source.contains("\"关闭仅统计本机；开启合并统计多设备。\""))
        #expect(source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains(".controlSize(.small)"))
        #expect(source.contains("ICloudDriveFolderPicker.chooseFolder()"))
        #expect(!source.contains("costSyncDidChange"))
        #expect(impactRowSource.contains(
            "VStack(alignment: .leading, spacing: 2) {\n            HStack(alignment: .top, spacing: 8) {"
        ))
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

    @Test("Token 活动只保留自适应范围的每日入口")
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
        #expect(!activitySource.contains("Token 活动刷新失败，显示上次数据"))
    }

    @Test("设计与计划采用按弹窗宽度扩展的合并热力图")
    func docsContainNoSupersededWeeklyOrSwitchingLanguage() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        #expect(readme.contains("按弹窗宽度自动扩展的每日热力图"))

        for path in [
            "docs/superpowers/specs/2026-07-13-token-activity-design.md",
            "docs/superpowers/plans/2026-07-13-token-activity.md"
        ] {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let lowercased = source.lowercased()

            #expect(!lowercased.contains("week-grouped"))
            #expect(!lowercased.contains("both modes"))
            #expect(!source.contains("切换"))
            #expect(source.contains("弹窗宽度") || lowercased.contains("popover width"))
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

private actor ActivityCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    var value: Int {
        count
    }
}

private enum ActivityFixtureError: Error {
    case unavailable
}

private func emptyTokenCostSnapshot() -> TokenCostSnapshot {
    let today = TokenCostPeriodSummary(kind: .today, models: [])
    return TokenCostSnapshot(
        today: today,
        yesterday: TokenCostPeriodSummary(kind: .yesterday, models: []),
        subscription: nil,
        lifetime: TokenCostPeriodSummary(kind: .lifetime, models: []),
        subscriptionPeriod: nil
    )
}

private func tokenCostSnapshot(tokens: Int64, cost: Double) -> TokenCostSnapshot {
    let model = TokenCostModelSummary(
        model: "gpt-test",
        inputTokens: tokens,
        cachedInputTokens: 0,
        cacheWriteInputTokens: 0,
        outputTokens: 0,
        totalTokens: tokens,
        estimatedCostUSD: cost
    )
    return TokenCostSnapshot(
        today: TokenCostPeriodSummary(kind: .today, models: [model]),
        yesterday: TokenCostPeriodSummary(kind: .yesterday, models: []),
        subscription: nil,
        lifetime: TokenCostPeriodSummary(kind: .lifetime, models: [model]),
        subscriptionPeriod: nil
    )
}
