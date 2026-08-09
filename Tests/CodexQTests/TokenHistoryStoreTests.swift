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

    @Test("账号活动失败时仍显示设备历史并公开警告")
    func activityFailureKeepsDeviceHistory() async throws {
        let reader = TokenHistoryReader(
            readActivity: { throw FixtureError.activityUnavailable },
            readCostRecords: { self.recordSet(tokens: 300) }
        )

        let result = try await reader.read(
            selection: .month(year: 2026, month: 8),
            now: now,
            calendar: calendar
        )

        #expect(result.summary.deviceTokens == 300)
        #expect(result.coverage.hasOfficialActivity == false)
        #expect(result.warningMessage?.contains("账号 Token 活动暂不可用") == true)
    }

    @Test("刷新失败保留最后一次成功数据")
    @MainActor
    func refreshFailureKeepsLastGoodSnapshot() async throws {
        let attempts = AttemptCounter()
        let reader = TokenHistoryReader(
            readActivity: { .init(peakDailyTokens: 0, days: []) },
            readCostRecords: {
                if await attempts.increment() == 1 {
                    return self.recordSet(tokens: 300)
                }
                throw FixtureError.costUnavailable
            }
        )
        let store = TokenHistoryStore(
            reader: reader,
            now: { self.now },
            calendar: calendar
        )

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
            readActivity: { .init(peakDailyTokens: 0, days: []) },
            readCostRecords: {
                if await attempts.increment() == 1 {
                    return self.recordSet(tokens: 800, month: 8)
                }
                throw FixtureError.costUnavailable
            }
        )
        let store = TokenHistoryStore(
            reader: reader,
            now: { self.now },
            calendar: calendar
        )

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
        let gate = RecordSetGate()
        let reader = TokenHistoryReader(
            readActivity: { .init(peakDailyTokens: 0, days: []) },
            readCostRecords: { await gate.load() }
        )
        let store = TokenHistoryStore(
            reader: reader,
            now: { self.now },
            calendar: calendar
        )

        store.selectedMonth = 8
        store.reload()
        try await waitUntil { await gate.startCount() == 1 }
        store.selectedMonth = 7
        store.reload()
        try await waitUntil { await gate.startCount() == 2 }

        await gate.release(index: 1, value: recordSet(tokens: 700, month: 7))
        try await waitUntil { store.snapshot?.selection == .month(year: 2026, month: 7) }
        await gate.release(index: 0, value: recordSet(tokens: 800, month: 8))
        try await Task.sleep(for: .milliseconds(30))

        #expect(store.snapshot?.selection == .month(year: 2026, month: 7))
        #expect(store.snapshot?.summary.deviceTokens == 700)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func recordSet(tokens: Int64, month: Int = 8) -> TokenCostRecordSet {
        TokenCostRecordSet(
            records: [
                TokenUsageRecord(
                    timestamp: ISO8601DateFormatter().date(
                        from: String(format: "2026-%02d-01T02:00:00Z", month)
                    )!,
                    model: "gpt-5.6-sol",
                    inputTokens: tokens,
                    cachedInputTokens: 0,
                    cacheWriteInputTokens: 0,
                    outputTokens: 0,
                    totalTokens: tokens
                )
            ],
            localRecordCount: 1,
            skippedSessionFileCount: 0,
            dataScope: .local,
            syncMessage: nil,
            subscriptionAnchor: nil
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 where !(await condition()) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition())
    }

    private enum FixtureError: LocalizedError {
        case activityUnavailable
        case costUnavailable

        var errorDescription: String? {
            switch self {
            case .activityUnavailable: return "活动不可用"
            case .costUnavailable: return "成本不可用"
            }
        }
    }
}

private actor AttemptCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private actor RecordSetGate {
    private var continuations: [Int: CheckedContinuation<TokenCostRecordSet, Never>] = [:]
    private var nextIndex = 0

    func load() async -> TokenCostRecordSet {
        let index = nextIndex
        nextIndex += 1
        return await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func startCount() -> Int {
        nextIndex
    }

    func release(index: Int, value: TokenCostRecordSet) {
        continuations.removeValue(forKey: index)?.resume(returning: value)
    }
}
