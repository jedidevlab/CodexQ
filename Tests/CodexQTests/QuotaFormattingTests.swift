import Foundation
import Testing
@testable import CodexQ

struct QuotaFormattingTests {
    private let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    private let locale = Locale(identifier: "zh_CN")

    @Test("剩余额度由 100 减已用百分比，并限制在有效范围")
    func remainingPercentIsClamped() {
        #expect(QuotaWindow(
            usedPercent: 37,
            resetsAt: nil,
            durationMinutes: nil
        ).remainingPercent == 63)
        #expect(QuotaWindow(
            usedPercent: 120,
            resetsAt: nil,
            durationMinutes: nil
        ).remainingPercent == 0)
        #expect(QuotaWindow(
            usedPercent: -4,
            resetsAt: nil,
            durationMinutes: nil
        ).remainingPercent == 100)
    }

    @Test("5 小时重置时间跨日期时仍只显示时间")
    func fiveHourAlwaysShowsTimeOnly() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 23, 0)
        let reset = date(2026, 6, 16, 2, 15)

        #expect(formatter.string(for: reset, period: .fiveHour, now: now) == "02:15")
    }

    @Test("周限额小于 24 小时显示距离重置的小时分钟")
    func weeklyUnder24HoursShowsRelativeResetTime() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let reset = date(2026, 6, 15, 23, 59)

        #expect(formatter.string(for: reset, period: .weekly, now: now) == "13h59m")
    }

    @Test("周限额跨日但小于 24 小时仍显示距离重置的小时分钟")
    func weeklyUnder24HoursOnFutureDayShowsRelativeResetTime() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let reset = date(2026, 6, 16, 9, 59)

        #expect(formatter.string(for: reset, period: .weekly, now: now) == "23h59m")
    }

    @Test("周限额等于 24 小时显示距离重置的小时分钟")
    func weeklyAt24HoursShowsRelativeResetTime() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let reset = date(2026, 6, 16, 10, 0)

        #expect(formatter.string(for: reset, period: .weekly, now: now) == "24h0m")
    }

    @Test("周限额大于 24 小时显示绝对日期")
    func weeklyOver24HoursShowsDateOnly() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let reset = date(2026, 6, 16, 10, 1)
        let result = formatter.string(for: reset, period: .weekly, now: now)

        #expect(result.contains("6"))
        #expect(result.contains("16"))
        #expect(!result.contains(":"))
    }

    @Test("额度窗口按时长识别，不依赖 primary 和 secondary 顺序")
    func rateLimitWindowsAreMatchedByDuration() {
        let limits = RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: 20,
                windowDurationMins: 10_080,
                resetsAt: nil
            ),
            secondary: RateLimitWindow(
                usedPercent: 5,
                windowDurationMins: 300,
                resetsAt: nil
            )
        )

        #expect(limits.quotaSnapshot?.fiveHour.usedPercent == 5)
        #expect(limits.quotaSnapshot?.weekly.usedPercent == 20)
    }

    @Test("预计余量与红线均按 CodexBar Pace 计算")
    func projectionUsesCurrentAverageRate() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 25,
            resetsAt: now.addingTimeInterval(3 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(abs(projection.expectedRemainingPercent - 60) < 0.001)
        #expect(abs(projection.reservePercent - 15) < 0.001)
        #expect(abs(projection.displayPercent - 15) < 0.001)
        #expect(projection.isInDeficit == false)
    }

    @Test("预测会在当前速率提前耗尽时归零")
    func projectionClampsEarlyExhaustionToZero() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 60,
            resetsAt: now.addingTimeInterval(3 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(projection.expectedRemainingPercent == 60)
        #expect(projection.reservePercent == 0)
        #expect(projection.displayPercent == 20)
        #expect(projection.isInDeficit)
    }

    @Test("剩余低于 Pace 红线时预测提前耗尽")
    func belowPaceMarkerRunsOutEarly() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 50,
            resetsAt: now.addingTimeInterval(3 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(window.remainingPercent < projection.expectedRemainingPercent)
        #expect(projection.reservePercent == 0)
        #expect(projection.isInDeficit)
    }

    @Test("剩余高于 Pace 红线时预测能撑到重置")
    func abovePaceMarkerLastsToReset() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 10,
            resetsAt: now.addingTimeInterval(3 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(window.remainingPercent > projection.expectedRemainingPercent)
        #expect(projection.reservePercent > 0)
        #expect(projection.isInDeficit == false)
    }

    @Test("周期进度不足 3% 时隐藏 Pace")
    func hidesPaceAtStartOfWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 1,
            resetsAt: now.addingTimeInterval(4.9 * 60 * 60),
            durationMinutes: 300
        )

        #expect(window.projection(at: now) == nil)
    }

    @Test("偏差在正负 2% 内视为正常进度")
    func treatsSmallDeltaAsOnTrack() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 41.5,
            resetsAt: now.addingTimeInterval(3 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(projection.isOnTrack)
        #expect(projection.isInDeficit == false)
    }

    @Test("超额使用时给出早于重置的耗尽时间")
    func providesRunOutETA() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 80,
            resetsAt: now.addingTimeInterval(2 * 60 * 60),
            durationMinutes: 300
        )
        let projection = try #require(window.projection(at: now))

        #expect(abs((projection.etaSeconds ?? 0) - 45 * 60) < 1)
        #expect(PaceFormatter.eta(projection.etaSeconds ?? 0) == "0h45m 后用完")
    }

    @Test("耗尽时间小于二十四小时显示小时分钟")
    func paceEtaUnder24HoursShowsHoursAndMinutes() {
        #expect(PaceFormatter.eta(23 * 60 * 60 + 59 * 60) == "23h59m 后用完")
    }

    @Test("耗尽时间达到二十四小时显示天和小时")
    func paceEtaAt24HoursShowsDaysAndHours() {
        #expect(PaceFormatter.eta(24 * 60 * 60) == "1d0h 后用完")
    }

    @Test("耗尽时间超过二十四小时忽略分钟显示天和小时")
    func paceEtaOver24HoursShowsDaysAndHours() {
        #expect(PaceFormatter.eta(119 * 60 * 60 + 12 * 60) == "4d23h 后用完")
    }


    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}

struct AppServerClientTests {
    @Test("app-server 不响应时刷新会超时返回")
    func unresponsiveServerTimesOut() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("#!/bin/sh\nexec sleep 5\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let client = AppServerClient(executableURL: executable, responseTimeout: 0.05)
        let startedAt = Date()

        do {
            _ = try await client.readRateLimits()
            Issue.record("客户端未在超时后返回")
        } catch AppServerClient.ClientError.responseTimedOut {
            // Expected: a stalled refresh must fail so future refreshes can continue.
        } catch {
            Issue.record("返回了错误的失败类型：\(error)")
        }

        #expect(Date().timeIntervalSince(startedAt) < 2)
    }
}

struct RelativeUpdateFormatterTests {
    @Test("更新时间只按整分钟变化")
    func formatsWholeMinutes() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)

        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(59)
        ) == "Updated now")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(60)
        ) == "Updated 1m ago")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(179)
        ) == "Updated 2m ago")
    }
}
