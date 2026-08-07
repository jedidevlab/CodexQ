import Foundation
import Testing
@testable import CodexQ

@Suite("TokenHistoryQueryTests")
struct TokenHistoryQueryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }

    private var utcCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test("日期范围包含累计但不包含周")
    func rangeModesIncludeCumulativeWithoutWeek() {
        #expect(TokenHistoryRangeMode.allCases.map(\.title) == [
            "日", "月", "年", "订阅周期", "累计", "自定义"
        ])
    }

    @Test("日查询覆盖所选日期所在自然周的七个本地自然日")
    func daySelectionUsesLocalCalendarWeek() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-07T04:00:00Z"))
        let selection = TokenHistorySelection.day(date)
        let interval = try #require(selection.interval(calendar: calendar, subscriptionPeriods: []))

        #expect(interval.start == calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3)
        ))
        #expect(interval.end == calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 10)
        ))
        #expect(calendar.dateComponents([.day], from: interval.start, to: interval.end).day == 7)
        #expect(selection.granularity(interval: interval, calendar: calendar) == .day)
    }

    @Test("累计范围从最早有效记录覆盖到今天并使用自适应粒度")
    func cumulativeSelectionUsesEarliestAvailableDayThroughToday() throws {
        let now = try date("2026-08-07T04:00:00Z")
        let records = [
            usage(at: "2026-08-02T02:00:00Z", model: "gpt-5.6-sol", tokens: 100)
        ]
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 300,
            days: [
                .init(startDate: "2026-07-30", tokens: 300),
                .init(startDate: "2026-07-99", tokens: 900)
            ]
        )

        let result = try #require(TokenHistoryAggregator.snapshot(
            records: records,
            activity: activity,
            selection: .cumulative,
            subscriptionCycles: [],
            dataScope: .local,
            skippedSessionFileCount: 0,
            syncMessage: nil,
            now: now,
            calendar: calendar
        ))

        #expect(result.interval.start == calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 30)
        ))
        #expect(result.interval.end == calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 8)
        ))
        #expect(result.granularity == .day)
        #expect(result.summary.totalTokens == 400)
    }

    @Test("累计范围没有历史记录时仍返回今天")
    func emptyCumulativeSelectionUsesToday() throws {
        let now = try date("2026-08-07T04:00:00Z")
        let result = try #require(TokenHistoryAggregator.snapshot(
            records: [],
            activity: .init(peakDailyTokens: 0, days: []),
            selection: .cumulative,
            subscriptionCycles: [],
            dataScope: .local,
            skippedSessionFileCount: 0,
            syncMessage: nil,
            now: now,
            calendar: calendar
        ))

        #expect(result.interval.start == calendar.startOfDay(for: now))
        #expect(result.interval.end == calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ))
        #expect(result.buckets.count == 1)
    }

    @Test("累计范围沿用自定义长范围的月年聚合阈值")
    func cumulativeSelectionUsesAdaptiveGranularity() throws {
        let start = try date("2022-01-01T00:00:00Z")
        let twoYears = try #require(calendar.date(byAdding: .year, value: 2, to: start))
        let fourYears = try #require(calendar.date(byAdding: .year, value: 4, to: start))

        #expect(TokenHistorySelection.cumulative.granularity(
            interval: DateInterval(start: start, end: twoYears),
            calendar: calendar
        ) == .month)
        #expect(TokenHistorySelection.cumulative.granularity(
            interval: DateInterval(start: start, end: fourYears),
            calendar: calendar
        ) == .year)
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
