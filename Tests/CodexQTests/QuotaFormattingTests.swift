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

    @Test("重置倒计时沿用 OpenUsage 的紧凑双单位")
    func resetCountdownUsesOpenUsageCompactUnits() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)

        #expect(formatter.string(
            for: now.addingTimeInterval(13 * 60 * 60 + 59 * 60),
            mode: .relative,
            now: now
        ) == "13h 59m 后重置")
        #expect(formatter.string(
            for: now.addingTimeInterval(4 * 24 * 60 * 60 + 52 * 60),
            mode: .relative,
            now: now
        ) == "4d 0h 后重置")
    }

    @Test("重置时间可切换为今天、明天或日期的绝对时间")
    func absoluteResetUsesOpenUsageDayBuckets() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)

        #expect(formatter.string(
            for: date(2026, 6, 15, 14, 30),
            mode: .absolute,
            now: now
        ) == "今天 14:30 重置")
        #expect(formatter.string(
            for: date(2026, 6, 16, 9, 0),
            mode: .absolute,
            now: now
        ) == "明天 09:00 重置")
        let later = formatter.string(
            for: date(2026, 6, 20, 9, 0),
            mode: .absolute,
            now: now
        )
        #expect(later.contains("6"))
        #expect(later.contains("20"))
        #expect(later.hasSuffix("09:00 重置"))
    }

    @Test("五分钟内或已过去的重置统一显示即将重置")
    func imminentOrPastResetShowsSoon() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)

        #expect(formatter.string(
            for: now.addingTimeInterval(5 * 60),
            mode: .relative,
            now: now
        ) == "即将重置")
        #expect(formatter.string(
            for: now.addingTimeInterval(-60),
            mode: .absolute,
            now: now
        ) == "即将重置")
    }

    @Test("重置提示展示当前模式并提供相反模式文案")
    func resetTooltipOffersOppositeDisplayMode() {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let reset = date(2026, 6, 16, 9, 0)

        #expect(formatter.string(for: reset, mode: .relative, now: now) == "23h 后重置")
        #expect(formatter.oppositeString(for: reset, mode: .relative, now: now) == "明天 09:00 重置")
        #expect(formatter.oppositeString(for: reset, mode: .absolute, now: now) == "23h 后重置")
    }

    @Test("非公历地区设置仍使用公历显示绝对重置日期")
    func absoluteResetUsesGregorianCalendar() throws {
        let formatter = ResetTimeFormatter(
            locale: Locale(identifier: "en_US@calendar=islamic"),
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
        )
        let reset = Date(timeIntervalSince1970: 1_784_260_800)

        #expect(formatter.string(
            for: reset,
            mode: .absolute,
            now: reset.addingTimeInterval(-5 * 24 * 60 * 60)
        ).contains("Jul 16"))
    }

    @Test("绝对时间跟随地区的十二或二十四小时格式")
    func absoluteResetUsesLocaleTimeFormat() throws {
        let formatter = ResetTimeFormatter(
            locale: Locale(identifier: "en_US"),
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
        )
        let now = Date(timeIntervalSince1970: 1_784_226_000)
        let reset = now.addingTimeInterval(2 * 60 * 60)
        let result = formatter.string(for: reset, mode: .absolute, now: now)

        #expect(result.contains("PM"))
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

        #expect(limits.quotaSnapshot?.fiveHour?.usedPercent == 5)
        #expect(limits.quotaSnapshot?.weekly.usedPercent == 20)
    }

    @Test("仅周限额时仍生成可用快照")
    func weeklyOnlyWindowProducesSnapshot() throws {
        let limits = RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: 1,
                windowDurationMins: 10_080,
                resetsAt: nil
            ),
            secondary: nil
        )

        let snapshot = try #require(limits.quotaSnapshot)

        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly.usedPercent == 1)
    }

    @Test("5小时窗口缺失时状态栏使用周限额")
    func weeklyQuotaIsStatusFallback() {
        let snapshot = QuotaSnapshot(
            fiveHour: nil,
            weekly: .init(
                usedPercent: 22,
                resetsAt: nil,
                durationMinutes: 10_080
            )
        )

        #expect(snapshot.statusRemainingPercent == 78)
    }

    @Test("套餐类型从 app-server 额度响应进入快照")
    func quotaSnapshotCarriesPlanType() throws {
        let json = #"""
        {
          "rateLimits": {
            "planType": "pro",
            "primary": {"usedPercent": 6, "windowDurationMins": 300},
            "secondary": {"usedPercent": 1, "windowDurationMins": 10080}
          },
          "rateLimitsByLimitId": {
            "codex": {
              "planType": "prolite",
              "primary": {"usedPercent": 7, "windowDurationMins": 300},
              "secondary": {"usedPercent": 2, "windowDurationMins": 10080}
            }
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
        let snapshot = try #require(response.quotaSnapshot)

        #expect(snapshot.fiveHour?.usedPercent == 7)
        #expect(snapshot.weekly.usedPercent == 2)
        #expect(snapshot.planType == "prolite")
        #expect(PlanTypeFormatter.displayName(for: snapshot.planType) == "Pro 5x")
    }

    @Test("Pace 按 OpenUsage 的 90% 与 100% 投影阈值分级")
    func paceUsesOpenUsageProjectionThresholds() {
        let now = Date(timeIntervalSince1970: 10_000)
        let reset = now.addingTimeInterval(2.5 * 60 * 60)

        #expect(QuotaWindow(usedPercent: 44, resetsAt: reset, durationMinutes: 300).paceState(at: now).isHealthy)
        #expect(QuotaWindow(usedPercent: 46, resetsAt: reset, durationMinutes: 300).paceState(at: now).sparePercent == 8)
        #expect(QuotaWindow(usedPercent: 60, resetsAt: reset, durationMinutes: 300).paceState(at: now).isRunningOut)
    }

    @Test("Pace 等待窗口开始至少一分钟且达到 1%")
    func paceWaitsForOpenUsageMinimumElapsedTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let tooEarly = QuotaWindow(
            usedPercent: 10,
            resetsAt: now.addingTimeInterval(4 * 60 * 60 + 58 * 60),
            durationMinutes: 300
        ).paceState(at: now)
        let ready = QuotaWindow(
            usedPercent: 10,
            resetsAt: now.addingTimeInterval(4 * 60 * 60 + 57 * 60),
            durationMinutes: 300
        ).paceState(at: now)

        #expect(tooEarly.isPlainLevel)
        #expect(ready.isRunningOut)
    }

    @Test("用量低于 5% 时不显示不可靠的提前耗尽 Pace")
    func tinyUsageSuppressesFalseRunOutWarning() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = QuotaWindow(
            usedPercent: 2,
            resetsAt: now.addingTimeInterval(4 * 60 * 60 + 56 * 60),
            durationMinutes: 300
        )

        #expect(window.paceState(at: now).isPlainLevel)
    }

    @Test("健康、临界、提前耗尽与用完状态使用 OpenUsage 提示")
    func paceStatusMatchesOpenUsageEscalation() throws {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)

        #expect(PaceFormatter.status(.healthy(projectedUsedPercent: 60), mode: .relative, formatter: formatter, now: now) == nil)
        #expect(PaceFormatter.status(
            .closeToLimit(sparePercent: 8, projectedUsedPercent: 92, markerPercent: 50),
            mode: .relative,
            formatter: formatter,
            now: now
        ) == PaceStatus(text: "~8% 余量", showsFlame: false))
        #expect(PaceFormatter.status(
            .runningOut(
                runOutAt: now.addingTimeInterval(45 * 60),
                projectedUsedPercent: 120,
                markerPercent: 50
            ),
            mode: .relative,
            formatter: formatter,
            now: now
        ) == PaceStatus(text: "45m 后用完", showsFlame: true))
        #expect(PaceFormatter.status(.spent, mode: .relative, formatter: formatter, now: now)
                == PaceStatus(text: "额度已用完", showsFlame: true))
    }

    @Test("提前耗尽时间跟随重置时间的相对绝对模式")
    func runOutTimeFollowsResetDisplayMode() throws {
        let formatter = ResetTimeFormatter(locale: locale, timeZone: timeZone)
        let now = date(2026, 6, 15, 10, 0)
        let state = QuotaPaceState.runningOut(
            runOutAt: date(2026, 6, 15, 10, 45),
            projectedUsedPercent: 120,
            markerPercent: 50
        )

        #expect(PaceFormatter.status(state, mode: .relative, formatter: formatter, now: now)?.text == "45m 后用完")
        #expect(PaceFormatter.status(state, mode: .absolute, formatter: formatter, now: now)?.text == "今天 10:45 用完")
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
    @Test("有可用次数但明细数组为空时仍需要回填")
    func emptyResetCreditDetailsNeedFallback() {
        let summary = ResetCreditsSummary(availableCount: 1, credits: [])

        #expect(AppServerClient.shouldReadResetCreditDetails(for: summary))
    }

    @Test("app-server 丢失重置明细时使用只读接口回填")
    func fillsMissingResetCreditDetails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = #"""
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized_notification
        IFS= read -r limits_request
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300},"secondary":{"usedPercent":1,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":1,"credits":null}}}'
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let details = ResetCreditsSummary(
            availableCount: 1,
            credits: [
                ResetCredit(
                    id: "credit-1",
                    resetType: "codexRateLimits",
                    status: "available",
                    title: "Full reset",
                    expiresAt: nil
                )
            ]
        )
        let client = AppServerClient(
            executableURL: executable,
            readResetCreditDetails: { details }
        )

        let snapshot = try await client.readRateLimits()

        #expect(snapshot.resetCredits == details)
    }

    @Test("token activity 通过 account/usage/read 读取每日用量")
    func tokenActivityUsesUsageReadMethod() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = #"""
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized_notification
        IFS= read -r usage_request
        method=$(printf '%s' "$usage_request" | /usr/bin/plutil -extract method raw -o - - 2>/dev/null)
        request_id=$(printf '%s' "$usage_request" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null)
        if [ "$method" = "account/usage/read" ] && [ "$request_id" = "2" ]; then
          printf '%s\n' '{"id":2,"result":{"summary":{"peakDailyTokens":1200},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":1200}]}}'
        else
          printf '%s\n' '{"id":2,"error":{"message":"unexpected method or id"}}'
        fi
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let snapshot = try await AppServerClient(executableURL: executable).readTokenActivity()

        #expect(snapshot.days.first?.tokens == 1_200)
    }

    @Test("额度与 Token 活动通过同一个 app-server 会话读取")
    func readsQuotaAndTokenActivityFromSingleServerSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let countFile = directory.appendingPathComponent("launch-count")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = #"""
        #!/bin/sh
        count=0
        if [ -f "$COUNT_FILE" ]; then
          count=$(cat "$COUNT_FILE")
        fi
        count=$((count + 1))
        printf '%s' "$count" > "$COUNT_FILE"
        IFS= read -r initialize_request
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized_notification
        IFS= read -r limits_request
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"planType":"prolite","primary":{"usedPercent":6,"windowDurationMins":300},"secondary":{"usedPercent":1,"windowDurationMins":10080}}}}'
        IFS= read -r usage_request
        printf '%s\n' '{"id":3,"result":{"summary":{"peakDailyTokens":1200},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":1200}]}}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let snapshot = try await AppServerClient(
            executableURL: executable,
            environment: ["COUNT_FILE": countFile.path]
        ).readDashboardSnapshots()

        #expect(snapshot.quota.planType == "prolite")
        #expect(snapshot.tokenActivity.days.first?.tokens == 1_200)
        #expect(try String(contentsOf: countFile, encoding: .utf8) == "1")
    }

    @Test("取消刷新会及时终止阻塞中的 app-server")
    func cancellationTerminatesBlockedServerProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let startedFile = directory.appendingPathComponent("started")
        let terminatedFile = directory.appendingPathComponent("terminated")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = """
        #!/bin/sh
        trap 'printf terminated > \(shellQuotedPath(terminatedFile.path)); exit 0' TERM
        printf started > \(shellQuotedPath(startedFile.path))
        while :; do sleep 0.1; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = AppServerClient(
            executableURL: executable,
            responseTimeout: 5
        )

        let task = Task {
            try await client.readRateLimits()
        }
        try await waitForFile(startedFile, timeout: 2)
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("取消后仍返回了额度快照")
        } catch is CancellationError {
            // Expected: cancellation should stop the blocking app-server request.
        } catch {
            Issue.record("返回了错误的失败类型：\(error)")
        }

        try await waitForFile(terminatedFile, timeout: 1.5)
        #expect(Date().timeIntervalSince(cancelledAt) < 0.8)
    }

    @Test("缺少候选程序时错误提示同时涵盖新旧应用")
    func missingExecutableMessageCoversCurrentAndLegacyApps() {
        #expect(AppServerClient.ClientError.executableMissing.errorDescription
            == "未找到 ChatGPT/Codex app-server")
    }

    @Test("默认候选优先新版 ChatGPT 并兼容旧版 Codex")
    func defaultCandidatesCoverCurrentAndLegacyApps() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        #expect(AppServerClient.defaultExecutableURLs(
            homeDirectory: homeDirectory
        ).map(\.path) == [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Users/example/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Users/example/Applications/Codex.app/Contents/Resources/codex"
        ])
    }

    @Test("优先使用候选列表中的第一个可执行文件")
    func firstExecutableCandidateWins() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = directory.appendingPathComponent("first-codex")
        let second = directory.appendingPathComponent("second-codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for executable in [first, second] {
            try Data("#!/bin/sh\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
        }

        #expect(AppServerClient.firstExecutableURL(in: [first, second]) == first)
    }

    @Test("首个候选不可执行时回退到后续候选")
    func fallsBackToNextExecutableCandidate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = directory.appendingPathComponent("first-codex")
        let second = directory.appendingPathComponent("second-codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("not executable\n".utf8).write(to: first)
        try Data("#!/bin/sh\n".utf8).write(to: second)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: second.path
        )

        #expect(AppServerClient.firstExecutableURL(in: [first, second]) == second)
    }

    @Test("没有可执行候选时返回空")
    func noExecutableCandidateReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        #expect(AppServerClient.firstExecutableURL(in: [missing]) == nil)
    }

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

    private func waitForFile(_ url: URL, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待文件超时：\(url.path)")
    }

    private func shellQuotedPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct RelativeUpdateFormatterTests {
    @Test("更新时间只按整分钟变化")
    func formatsWholeMinutes() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)

        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(59)
        ) == "刚刚更新")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(60)
        ) == "1 分钟前更新")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(179)
        ) == "2 分钟前更新")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(2 * 60 * 60)
        ) == "2 小时前更新")
        #expect(RelativeUpdateFormatter.string(
            since: updatedAt,
            now: updatedAt.addingTimeInterval(3 * 24 * 60 * 60)
        ) == "3 天前更新")
    }
}
