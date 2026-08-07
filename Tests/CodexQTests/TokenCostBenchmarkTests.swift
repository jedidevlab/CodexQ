import Foundation
import Testing
@testable import CodexQ

@Suite("TokenCostBenchmarkTests", .serialized)
struct TokenCostBenchmarkTests {
    @Test("真实本机会话冷读与温读保持记录数和成本一致")
    func measuresLocalSessionReads() async throws {
        let home = try frozenSessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try fullParseReference(home: home)
        #expect(reference.recordCount > 0)

        let now = Date()
        let cold = try await (0..<5).asyncMap { _ in
            let reader = TokenCostReader(homeDirectory: home)
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let snapshot = try await reader.read(now: now)
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            assertMatchesReference(snapshot, reference: reference)
            return elapsed
        }

        let warmReader = TokenCostReader(homeDirectory: home)
        _ = try await warmReader.read(now: now)
        let warm = try await (0..<5).asyncMap { _ in
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let snapshot = try await warmReader.read(now: now)
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            assertMatchesReference(snapshot, reference: reference)
            return elapsed
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let year = calendar.component(.year, from: now)
        let historySelection = TokenHistorySelection.year(year)
        let coldHistoryRecords = try await TokenCostReader(
            homeDirectory: home
        ).readRecordSet(now: now)
        let coldHistoryStartedAt = DispatchTime.now().uptimeNanoseconds
        let coldHistory = try #require(TokenHistoryAggregator.snapshot(
            records: coldHistoryRecords.records,
            activity: nil,
            selection: historySelection,
            subscriptionCycles: [],
            dataScope: coldHistoryRecords.dataScope,
            skippedSessionFileCount: coldHistoryRecords.skippedSessionFileCount,
            syncMessage: coldHistoryRecords.syncMessage,
            now: now,
            calendar: calendar
        ))
        let coldHistoryElapsed = DispatchTime.now().uptimeNanoseconds - coldHistoryStartedAt
        let warmHistoryRecords = try await warmReader.readRecordSet(now: now)
        let warmHistoryStartedAt = DispatchTime.now().uptimeNanoseconds
        let warmHistory = try #require(TokenHistoryAggregator.snapshot(
            records: warmHistoryRecords.records,
            activity: nil,
            selection: historySelection,
            subscriptionCycles: [],
            dataScope: warmHistoryRecords.dataScope,
            skippedSessionFileCount: warmHistoryRecords.skippedSessionFileCount,
            syncMessage: warmHistoryRecords.syncMessage,
            now: now,
            calendar: calendar
        ))
        let warmHistoryElapsed = DispatchTime.now().uptimeNanoseconds - warmHistoryStartedAt

        #expect(warmHistory == coldHistory)

        print(
            "TOKEN_COST_BENCHMARK records=\(reference.recordCount) cost_usd=\(reference.costUSD) "
                + "cold_median_ms=\(milliseconds(median(cold))) warm_median_ms=\(milliseconds(median(warm))) "
                + "history_cold_ms=\(milliseconds(coldHistoryElapsed)) "
                + "history_warm_ms=\(milliseconds(warmHistoryElapsed))"
        )
    }

    private func fullParseReference(home: URL) throws -> (recordCount: Int, costUSD: Double) {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: sessions.path)
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
            .map { sessions.appendingPathComponent($0) }
        let records = try files.flatMap(TokenCostSessionParser.records)
        var identified: [String: TokenUsageRecord] = [:]
        var unidentified = Set<TokenUsageRecord>()
        for record in records {
            if let eventID = record.eventID {
                identified[eventID] = record
            } else {
                unidentified.insert(record)
            }
        }
        let uniqueRecords = Array(identified.values) + Array(unidentified)
        return (
            uniqueRecords.count,
            uniqueRecords.reduce(0) { $0 + (TokenPricingCatalog.estimatedCost(for: $1) ?? 0) }
        )
    }

    private func frozenSessionHome() throws -> URL {
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQ-TokenCostBenchmark-\(UUID().uuidString)", isDirectory: true)
        let destination = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return home
    }

    private func assertMatchesReference(
        _ snapshot: TokenCostSnapshot,
        reference: (recordCount: Int, costUSD: Double)
    ) {
        #expect(snapshot.sourceRecordCount == reference.recordCount)
        #expect(abs(snapshot.lifetime.recordedEstimatedCostUSD - reference.costUSD) < 0.000_001)
    }

    private func median(_ samples: [UInt64]) -> UInt64 {
        samples.sorted()[samples.count / 2]
    }

    private func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }
}

private extension Range where Bound == Int {
    func asyncMap<T>(_ transform: (Int) async throws -> T) async throws -> [T] {
        var result: [T] = []
        for value in self {
            result.append(try await transform(value))
        }
        return result
    }
}
