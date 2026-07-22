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

    @Test("可选汇总字段为空时仍能读取每日用量")
    func decodesNullPeakDailyTokens() throws {
        let data = #"{"summary":{"lifetimeTokens":null,"peakDailyTokens":null},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":4000}]}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)

        #expect(value.peakDailyTokens == 4_000)
        #expect(value.lifetimeTokens == nil)
        #expect(value.days == [.init(startDate: "2026-07-12", tokens: 4_000)])
    }

    @Test("每日用量列表缺失或为空时按空活动处理")
    func decodesAbsentOrNullDailyUsageBuckets() throws {
        for json in [
            #"{"summary":{}}"#,
            #"{"summary":{},"dailyUsageBuckets":null}"#
        ] {
            let data = try #require(json.data(using: .utf8))
            let value = try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)

            #expect(value.peakDailyTokens == 0)
            #expect(value.days.isEmpty)
        }
    }

    @Test("使用早于今天的最近完整日")
    func latestRecordedDayUsesNewestAvailableBucket() throws {
        let snapshot = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            lifetimeTokens: 9_000,
            days: [
                .init(startDate: "2026-07-12", tokens: 800),
                .init(startDate: "2026-07-16", tokens: 1_600),
                .init(startDate: "2026-07-13", tokens: 1_200),
                .init(startDate: "invalid", tokens: 2_000)
            ]
        )

        let latest = TokenActivityPresentation.latestRecordedDay(
            before: try date("2026-07-15"),
            snapshot: snapshot,
            calendar: utcCalendar
        )
        let expectedDate = try date("2026-07-13")

        #expect(latest == TokenActivityCell(
            date: expectedDate,
            tokens: 1_200
        ))
    }

    @Test("最近完整日忽略当天尚未结束的用量桶")
    func latestRecordedDayExcludesCurrentDay() throws {
        let snapshot = TokenActivitySnapshot(
            peakDailyTokens: 2_000,
            days: [
                .init(startDate: "2026-07-14", tokens: 1_200),
                .init(startDate: "2026-07-15", tokens: 400)
            ]
        )
        let expectedDate = try date("2026-07-14")

        let latest = TokenActivityPresentation.latestRecordedDay(
            before: try date("2026-07-15"),
            snapshot: snapshot,
            calendar: utcCalendar
        )

        #expect(latest == TokenActivityCell(date: expectedDate, tokens: 1_200))
    }

    @Test("最近完整日不是昨天时显示具体日期")
    func completedDayLabelShowsConcreteDate() throws {
        #expect(TokenActivityDateLabel.string(
            for: try date("2026-07-13"),
            now: try date("2026-07-15"),
            calendar: utcCalendar
        ) == "7/13")
    }

    @Test("最近完整日是昨天时显示昨日")
    func completedDayLabelShowsYesterday() throws {
        #expect(TokenActivityDateLabel.string(
            for: try date("2026-07-14"),
            now: try date("2026-07-15"),
            calendar: utcCalendar
        ) == "昨日")
    }

    @Test("热力图按可用周列扩展并在今天结束")
    func dailyCellsExpandToVisibleWeekCountAndEndToday() throws {
        let now = try date("2026-07-13")
        let firstDate = try date("2026-03-30")
        let missingDate = try date("2026-06-02")
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
            calendar: utcCalendar,
            weekCount: 16
        )

        #expect(cells.first?.date == firstDate)
        #expect(cells.last?.date == now)
        #expect(cells.count == 106)
        let missingCell = try #require(cells.first(where: { $0.date == missingDate }))
        #expect(missingCell.tokens == nil)
        #expect(!cells.contains(where: { $0.date == futureDate }))
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
            calendar: utcCalendar,
            weekCount: 16
        )
        let normalizedCell = try #require(cells.first(where: { $0.date == normalizedDate }))

        #expect(normalizedCell.tokens == nil)
    }

    @Test("跨年时热力图仍保留指定周列")
    func dailyCellsHandleYearBoundary() throws {
        let expectedFirstDate = try date("2026-09-21")
        let now = try date("2027-01-05")
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: .init(peakDailyTokens: 0, days: []),
            now: now,
            calendar: utcCalendar,
            weekCount: 16
        )

        #expect(cells.first?.date == expectedFirstDate)
        #expect(cells.last?.date == now)
        #expect(cells.count == 107)
    }

    @Test("范围外或非法响应仍生成完整空日历")
    func outOfRangeAndInvalidDaysProduceEmptyCalendarStructure() throws {
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: .init(
                peakDailyTokens: 2_000,
                days: [
                    .init(startDate: "2026-03-29", tokens: 900),
                    .init(startDate: "2026-06-31", tokens: 1_200)
                ]
            ),
            now: try date("2026-07-13"),
            calendar: utcCalendar,
            weekCount: 16
        )

        #expect(cells.count == 106)
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
