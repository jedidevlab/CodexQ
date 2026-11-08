import Foundation
import Testing
@testable import CodexQ

@Suite("TokenHistoryStoreTests")
struct TokenHistoryStoreTests {
    private let now = ISO8601DateFormatter().date(from: "2026-08-07T00:00:00Z")!

    @Test("累计模式映射为累计查询")
    @MainActor
    func cumulativeModeMapsToCumulativeSelection() {
        let store = TokenHistoryStore(now: { self.now }, calendar: calendar)
        store.mode = .cumulative
        #expect(store.selection == .cumulative)
    }

    @Test("历史读取只使用账号 Token 活动")
    func historyUsesAccountActivityOnly() async throws {
        let reader = TokenHistoryReader(
            readActivity: { self.activity(tokens: 300, month: 8) },
            readSubscriptionAnchor: { nil }
        )
        let result = try await reader.read(
            selection: .month(year: 2026, month: 8),
            now: now,
            calendar: calendar
        )

        #expect(result.summary.totalTokens == 300)
        #expect(result.summary.deviceTokens == 0)
        #expect(result.models.isEmpty)
        #expect(result.coverage.hasOfficialActivity)
    }

    @Test("刷新失败保留最后一次成功数据")
    @MainActor
    func refreshFailureKeepsLastGoodSnapshot() async throws {
        let attempts = AttemptCounter()
        let reader = TokenHistoryReader(
            readActivity: {
                if await attempts.increment() == 1 { return self.activity(tokens: 300, month: 8) }
                throw FixtureError.activityUnavailable
            },
            readSubscriptionAnchor: { nil }
        )
        let store = TokenHistoryStore(reader: reader, now: { self.now }, calendar: calendar)

        store.reload()
        try await waitUntil { store.snapshot != nil && !store.isLoading }
        let first = try #require(store.snapshot)
        store.reload()
        try await waitUntil { store.errorMessage != nil && !store.isLoading }

        #expect(store.snapshot == first)
        #expect(store.errorMessage != nil)
    }

    @Test("切换范围失败时不把旧范围数据当作当前数据展示")
    @MainActor
    func failedNewSelectionDoesNotExposeOldSnapshot() async throws {
        let attempts = AttemptCounter()
        let reader = TokenHistoryReader(
            readActivity: {
                if await attempts.increment() == 1 { return self.activity(tokens: 800, month: 8) }
                throw FixtureError.activityUnavailable
            },
            readSubscriptionAnchor: { nil }
        )
        let store = TokenHistoryStore(reader: reader, now: { self.now }, calendar: calendar)

        store.reload()
        try await waitUntil { store.snapshot != nil && !store.isLoading }
        store.selectedMonth = 7
        store.reload()
        try await waitUntil { store.errorMessage != nil && !store.isLoading }

        #expect(store.snapshot?.selection == .month(year: 2026, month: 8))
        #expect(store.visibleSnapshot == nil)
    }

    @Test("旧查询晚返回时不能覆盖最新筛选")
    @MainActor
    func staleResultCannotReplaceLatestSelection() async throws {
        let gate = ActivitySnapshotGate()
        let reader = TokenHistoryReader(
            readActivity: { await gate.load() },
            readSubscriptionAnchor: { nil }
        )
        let store = TokenHistoryStore(reader: reader, now: { self.now }, calendar: calendar)

        store.selectedMonth = 8
        store.reload()
        try await waitUntil { await gate.startCount() == 1 }
        store.selectedMonth = 7
        store.reload()
        try await waitUntil { await gate.startCount() == 2 }

        await gate.release(index: 1, value: activity(tokens: 700, month: 7))
        try await waitUntil { store.snapshot?.selection == .month(year: 2026, month: 7) }
        await gate.release(index: 0, value: activity(tokens: 800, month: 8))
        try await Task.sleep(for: .milliseconds(30))

        #expect(store.snapshot?.selection == .month(year: 2026, month: 7))
        #expect(store.snapshot?.summary.totalTokens == 700)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func activity(tokens: Int64, month: Int) -> TokenActivitySnapshot {
        TokenActivitySnapshot(
            peakDailyTokens: tokens,
            days: [.init(startDate: String(format: "2026-%02d-01", month), tokens: tokens)]
        )
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<100 where !(await condition()) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition())
    }

    private enum FixtureError: LocalizedError {
        case activityUnavailable
        var errorDescription: String? { "活动不可用" }
    }
}

private actor AttemptCounter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

private actor ActivitySnapshotGate {
    private var continuations: [Int: CheckedContinuation<TokenActivitySnapshot, Never>] = [:]
    private var nextIndex = 0

    func load() async -> TokenActivitySnapshot {
        let index = nextIndex
        nextIndex += 1
        return await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func startCount() -> Int { nextIndex }

    func release(index: Int, value: TokenActivitySnapshot) {
        continuations.removeValue(forKey: index)?.resume(returning: value)
    }
}
