import Foundation
import Testing
@testable import CodexQ

struct TokenActivityTests {
    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    @Test("账户用量响应保留服务端日期和 Token 数")
    func decodesAccountUsageBuckets() throws {
        let data = #"{"summary":{"peakDailyTokens":2000},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":1200}]}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)

        #expect(value.days == [.init(startDate: "2026-07-12", tokens: 1200)])
        #expect(value.peakDailyTokens == 2000)
    }

    @Test("日历模式保留当前月及前两个月，并为空缺日期补位")
    func dailyCellsKeepThreeCalendarMonthsAndFillMissingDays() throws {
        let now = try date("2026-07-13")
        let firstDate = try date("2026-05-01")
        let missingDate = try date("2026-05-02")
        let fixture = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            days: [.init(startDate: "2026-06-01", tokens: 1_200)]
        )
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: fixture,
            now: now,
            calendar: utcCalendar
        )

        #expect(cells.first?.date == firstDate)
        #expect(cells.last?.date == now)
        #expect(cells.first(where: { $0.date == missingDate })?.tokens == nil)
    }

    @Test("周历模式按完整周补齐两个月统计范围")
    func weeklyRowsKeepTwoMonthsAndSevenDailyCells() throws {
        let now = try date("2026-07-13")
        let june1 = try date("2026-06-01")
        let july19 = try date("2026-07-19")
        let fixture = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            days: [.init(startDate: "2026-06-01", tokens: 1_200)]
        )
        let rows = TokenActivityPresentation.weeklyRows(
            snapshot: fixture,
            now: now,
            calendar: utcCalendar
        )

        #expect(rows.first?.cells.count == 7)
        #expect(rows.flatMap(\.cells).first(where: { $0.date == june1 })?.tokens == 1_200)
        #expect(rows.last?.cells.last?.date == july19)
        #expect(rows.last?.cells.last?.tokens == nil)
    }

    @Test("日历与周历共享 Token 数量和活动等级规则")
    func sharedFormattingAndActivityLevels() {
        #expect(TokenCountFormatter.string(1_200).hasSuffix(" tokens"))
        #expect(TokenActivityLevel.level(tokens: 0, peakTokens: 2_000) == 0)
        #expect(TokenActivityLevel.level(tokens: 2_000, peakTokens: 2_000) == 4)
    }

    private func date(_ value: String) throws -> Date {
        let components = value.split(separator: "-").compactMap { Int($0) }
        return try #require(utcCalendar.date(from: DateComponents(
            year: components[0],
            month: components[1],
            day: components[2]
        )))
    }
}
