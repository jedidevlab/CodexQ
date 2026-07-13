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
        let data = #"{"summary":{"lifetimeTokens":9000000000,"peakDailyTokens":5000000000},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":4000000000}]}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)

        #expect(value.days == [.init(startDate: "2026-07-12", tokens: 4_000_000_000)])
        #expect(value.peakDailyTokens == 5_000_000_000)
        #expect(value.lifetimeTokens == 9_000_000_000)
    }

    @Test("今日 Token 只读取本地日历当天数据")
    func todayTokensUsesCurrentCalendarDay() throws {
        let snapshot = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            lifetimeTokens: 9_000,
            days: [
                .init(startDate: "2026-07-12", tokens: 800),
                .init(startDate: "2026-07-13", tokens: 1_200)
            ]
        )

        #expect(TokenActivityPresentation.tokens(
            on: try date("2026-07-13"),
            snapshot: snapshot,
            calendar: utcCalendar
        ) == 1_200)
        #expect(TokenActivityPresentation.tokens(
            on: try date("2026-07-14"),
            snapshot: snapshot,
            calendar: utcCalendar
        ) == nil)
    }

    @Test("日历模式保留当前月及前两个月，并为空缺日期补位")
    func dailyCellsKeepThreeCalendarMonthsAndFillMissingDays() throws {
        let now = try date("2026-07-13")
        let firstDate = try date("2026-05-01")
        let lastDate = try date("2026-07-31")
        let missingDate = try date("2026-05-02")
        let futureDate = try date("2026-07-14")
        let fixture = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            days: [
                .init(startDate: "2026-06-01", tokens: 1_200),
                .init(startDate: "2026-07-14", tokens: 1_500)
            ]
        )
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: fixture,
            now: now,
            calendar: utcCalendar
        )

        #expect(cells.first?.date == firstDate)
        #expect(cells.last?.date == lastDate)
        let missingCell = try #require(cells.first(where: { $0.date == missingDate }))
        #expect(missingCell.tokens == nil)
        let futureCell = try #require(cells.first(where: { $0.date == futureDate }))
        #expect(futureCell.tokens == nil)
        for pair in zip(cells, cells.dropFirst()) {
            #expect(utcCalendar.date(byAdding: .day, value: 1, to: pair.0.date) == pair.1.date)
        }
    }

    @Test("服务端无效日期不能归一化成另一天的用量")
    func invalidServerDateDoesNotCreateActivity() throws {
        let normalizedDate = try date("2026-03-02")
        let fixture = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            days: [.init(startDate: "2026-02-30", tokens: 1_200)]
        )

        let cells = TokenActivityPresentation.dailyCells(
            snapshot: fixture,
            now: try date("2026-03-03"),
            calendar: utcCalendar
        )
        let normalizedCell = try #require(cells.first(where: { $0.date == normalizedDate }))

        #expect(normalizedCell.tokens == nil)
    }

    @Test("跨年时日历下界仍是两个月前的月初")
    func dailyCellsHandleYearBoundary() throws {
        let expectedFirstDate = try date("2026-11-01")
        let now = try date("2027-01-05")
        let expectedLastDate = try date("2027-01-31")
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: .init(peakDailyTokens: 0, days: []),
            now: now,
            calendar: utcCalendar
        )

        #expect(cells.first?.date == expectedFirstDate)
        #expect(cells.last?.date == expectedLastDate)
    }

    @Test("范围外或非法响应仍生成完整空日历")
    func outOfRangeAndInvalidDaysProduceEmptyCalendarStructure() throws {
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: .init(
                peakDailyTokens: 2_000,
                days: [
                    .init(startDate: "2026-04-30", tokens: 900),
                    .init(startDate: "2026-06-31", tokens: 1_200)
                ]
            ),
            now: try date("2026-07-13"),
            calendar: utcCalendar
        )

        #expect(cells.count == 92)
        #expect(!TokenActivityPresentation.hasRecordedTokens(in: cells))
        #expect(cells.allSatisfy { $0.tokens == nil })
    }

    @Test("每日方块使用统一 Token 数量和活动等级规则")
    func sharedFormattingAndActivityLevels() {
        #expect(!TokenCountFormatter.compactNumber(1_200).contains("tokens"))
        #expect(TokenCountFormatter.string(1_200).hasSuffix(" tokens"))
        #expect(TokenActivityLevel.level(tokens: 0, peakTokens: 2_000) == 0)
        #expect(TokenActivityLevel.level(tokens: 2_000, peakTokens: 2_000) == 4)
    }

    @Test("Token 活动模型不再暴露周视图演示类型")
    func modelHasNoWeeklyPresentation() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Models/TokenActivity.swift",
            encoding: .utf8
        )

        #expect(!source.contains("TokenActivityWeek"))
        #expect(!source.contains("weeklyRows"))
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
