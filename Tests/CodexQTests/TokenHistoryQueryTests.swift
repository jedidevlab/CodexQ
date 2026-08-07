import Foundation
import Testing
@testable import CodexQ

@Suite("TokenHistoryQueryTests")
struct TokenHistoryQueryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var utcCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test("单日查询覆盖本地自然日且结束时间不包含次日")
    func daySelectionUsesLocalCalendarDay() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-07T04:00:00Z"))
        let selection = TokenHistorySelection.day(date)
        let interval = try #require(selection.interval(calendar: calendar, subscriptionPeriods: []))

        #expect(interval.start == calendar.startOfDay(for: date))
        #expect(interval.end == calendar.date(byAdding: .day, value: 1, to: interval.start))
        #expect(selection.granularity(interval: interval, calendar: calendar) == .day)
    }

    @Test("月、年和自定义范围选择稳定的聚合粒度")
    func rangeModesChooseStableGranularity() throws {
        let month = TokenHistorySelection.month(year: 2026, month: 8)
        let year = TokenHistorySelection.year(2026)
        let shortCustom = TokenHistorySelection.custom(
            start: try date("2026-01-01T00:00:00Z"),
            endInclusive: try date("2026-03-01T00:00:00Z")
        )
        let mediumCustom = TokenHistorySelection.custom(
            start: try date("2024-01-01T00:00:00Z"),
            endInclusive: try date("2026-01-01T00:00:00Z")
        )

        let monthInterval = try #require(month.interval(calendar: calendar, subscriptionPeriods: []))
        let yearInterval = try #require(year.interval(calendar: calendar, subscriptionPeriods: []))
        let shortInterval = try #require(shortCustom.interval(calendar: calendar, subscriptionPeriods: []))
        let mediumInterval = try #require(mediumCustom.interval(calendar: calendar, subscriptionPeriods: []))

        #expect(month.granularity(interval: monthInterval, calendar: calendar) == .day)
        #expect(year.granularity(interval: yearInterval, calendar: calendar) == .month)
        #expect(shortCustom.granularity(interval: shortInterval, calendar: calendar) == .day)
        #expect(mediumCustom.granularity(interval: mediumInterval, calendar: calendar) == .month)
    }

    @Test("反向自定义日期会归一化为包含首尾两天的范围")
    func reversedCustomRangeIsNormalized() throws {
        let earlier = try date("2026-08-01T04:00:00Z")
        let later = try date("2026-08-07T04:00:00Z")
        let selection = TokenHistorySelection.custom(start: later, endInclusive: earlier)
        let interval = try #require(selection.interval(
            calendar: calendar,
            subscriptionPeriods: []
        ))

        #expect(interval.start == calendar.startOfDay(for: earlier))
        #expect(interval.end == calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: later)
        ))
    }

    @Test("月度订阅按续费锚点生成当前和历史周期")
    func generatesMonthlySubscriptionCycles() throws {
        let anchor = SubscriptionAnchor(
            start: try date("2026-06-06T02:29:39Z"),
            end: try date("2026-07-06T02:29:39Z"),
            cadence: .month
        )
        let cycles = TokenHistoryAggregator.subscriptionCycles(
            anchor: anchor,
            dataInterval: DateInterval(
                start: try date("2026-04-01T00:00:00Z"),
                end: try date("2026-08-08T00:00:00Z")
            ),
            now: try date("2026-08-07T00:00:00Z"),
            calendar: utcCalendar
        )

        let currentStart = try date("2026-08-06T02:29:39Z")
        let previousStart = try date("2026-07-06T02:29:39Z")
        #expect(cycles.first?.interval.start == currentStart)
        #expect(cycles.first?.isCurrent == true)
        #expect(cycles.dropFirst().first?.interval.start == previousStart)
        #expect(cycles.allSatisfy { $0.isInferred })
    }

    @Test("官方日数据逐日补差且不会下调更高的设备账本")
    func reconcilesEachDayBeforeBucketing() throws {
        let records = [
            usage(at: "2026-08-01T02:00:00Z", model: "gpt-5.6-sol", tokens: 200),
            usage(at: "2026-08-02T02:00:00Z", model: "gpt-5.6-sol", tokens: 100)
        ]
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 300,
            days: [
                .init(startDate: "2026-08-01", tokens: 150),
                .init(startDate: "2026-08-02", tokens: 300)
            ]
        )

        let result = try #require(TokenHistoryAggregator.snapshot(
            records: records,
            activity: activity,
            selection: .month(year: 2026, month: 8),
            subscriptionCycles: [],
            dataScope: .local,
            skippedSessionFileCount: 0,
            syncMessage: nil,
            now: try date("2026-08-07T00:00:00Z"),
            calendar: calendar
        ))

        #expect(result.summary.deviceTokens == 300)
        #expect(result.summary.totalTokens == 500)
        #expect(result.summary.supplementTokens == 200)
        #expect(result.coverage.activityDaysAvailable == 2)
        #expect(result.coverage.calendarDaysInRange == 31)
    }

    @Test("未定价模型保留 Token 且不伪造零成本")
    func preservesUnpricedModelUsage() throws {
        let record = usage(
            at: "2026-08-01T02:00:00Z",
            model: "unknown-model",
            tokens: 400
        )
        let result = try #require(TokenHistoryAggregator.snapshot(
            records: [record],
            activity: nil,
            selection: .month(year: 2026, month: 8),
            subscriptionCycles: [],
            dataScope: .local,
            skippedSessionFileCount: 0,
            syncMessage: nil,
            now: try date("2026-08-07T00:00:00Z"),
            calendar: calendar
        ))

        #expect(result.summary.unpricedTokens == 400)
        #expect(result.summary.estimatedCostUSD == 0)
        #expect(result.models.contains {
            $0.model == "unknown-model" && $0.estimatedCostUSD == nil
        })
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func usage(at value: String, model: String, tokens: Int64) -> TokenUsageRecord {
        TokenUsageRecord(
            timestamp: ISO8601DateFormatter().date(from: value)!,
            model: model,
            inputTokens: tokens,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: tokens
        )
    }
}
