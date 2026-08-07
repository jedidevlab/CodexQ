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

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
