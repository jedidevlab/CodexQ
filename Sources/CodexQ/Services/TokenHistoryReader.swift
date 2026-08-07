import Foundation

struct TokenHistoryReader: Sendable {
    let readActivity: @Sendable () async throws -> TokenActivitySnapshot
    let readCostRecords: @Sendable () async throws -> TokenCostRecordSet

    init(
        readActivity: @escaping @Sendable () async throws -> TokenActivitySnapshot = {
            try await AppServerClient().readTokenActivity()
        },
        readCostRecords: @escaping @Sendable () async throws -> TokenCostRecordSet = {
            try await TokenCostReader.shared.readRecordSet()
        }
    ) {
        self.readActivity = readActivity
        self.readCostRecords = readCostRecords
    }

    func read(
        selection: TokenHistorySelection,
        now: Date,
        calendar: Calendar
    ) async throws -> TokenHistorySnapshot {
        async let activityResult = Self.loadActivity(using: readActivity)
        async let recordSetResult = readCostRecords()

        let recordSet = try await recordSetResult
        let loadedActivity = await activityResult
        try Task.checkCancellation()

        let activity: TokenActivitySnapshot?
        let warningMessage: String?
        switch loadedActivity {
        case .success(let value):
            activity = value
            warningMessage = nil
        case .failure(let message):
            activity = nil
            warningMessage = "账号 Token 活动暂不可用：\(message)"
        case .cancelled:
            throw CancellationError()
        }

        let dataInterval = Self.dataInterval(
            records: recordSet.records,
            selection: selection,
            now: now,
            calendar: calendar
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cycles = recordSet.subscriptionAnchor.map {
            TokenHistoryAggregator.subscriptionCycles(
                anchor: $0,
                dataInterval: dataInterval,
                now: now,
                calendar: utcCalendar
            )
        } ?? []
        guard let snapshot = TokenHistoryAggregator.snapshot(
            records: recordSet.records,
            activity: activity,
            selection: selection,
            subscriptionCycles: cycles,
            dataScope: recordSet.dataScope,
            skippedSessionFileCount: recordSet.skippedSessionFileCount,
            syncMessage: recordSet.syncMessage,
            now: now,
            calendar: calendar
        ) else {
            throw ReaderError.invalidSelection
        }
        return snapshot.withWarningMessage(warningMessage)
    }

    enum ReaderError: LocalizedError {
        case invalidSelection

        var errorDescription: String? {
            "无法解析所选历史时间范围"
        }
    }

    private enum ActivityResult: Sendable {
        case success(TokenActivitySnapshot)
        case failure(String)
        case cancelled
    }

    private static func loadActivity(
        using provider: @Sendable () async throws -> TokenActivitySnapshot
    ) async -> ActivityResult {
        do {
            return .success(try await provider())
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func dataInterval(
        records: [TokenUsageRecord],
        selection: TokenHistorySelection,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        guard let first = records.map(\.timestamp).min(),
              let last = records.map(\.timestamp).max() else {
            return selection.interval(calendar: calendar, subscriptionPeriods: [])
                ?? DateInterval(start: now, duration: 1)
        }
        return DateInterval(start: first, end: max(last.addingTimeInterval(1), first.addingTimeInterval(1)))
    }
}

private extension TokenHistorySnapshot {
    func withWarningMessage(_ value: String?) -> TokenHistorySnapshot {
        TokenHistorySnapshot(
            selection: selection,
            interval: interval,
            granularity: granularity,
            buckets: buckets,
            summary: summary,
            models: models,
            coverage: coverage,
            subscriptionCycles: subscriptionCycles,
            warningMessage: value
        )
    }
}
