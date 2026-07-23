import Foundation
import Testing
@testable import CodexQ

struct TokenCostTests {
    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test("成本按非缓存输入、缓存输入和输出分别使用官方价格")
    func calculatesOfficialTokenCategories() throws {
        let record = TokenUsageRecord(
            timestamp: try date("2026-07-23T02:00:00Z"),
            model: "gpt-5.6-sol",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )

        let cost = try #require(TokenPricingCatalog.estimatedCost(for: record))

        #expect(abs(cost - 3.55) < 0.000_001)
    }

    @Test("超过长上下文阈值时输入和输出分别应用官方倍率")
    func appliesLongContextPremiumPerCall() throws {
        let record = TokenUsageRecord(
            timestamp: try date("2026-07-23T02:00:00Z"),
            model: "gpt-5.6-terra",
            inputTokens: 300_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 10_000,
            totalTokens: 310_000
        )

        let cost = try #require(TokenPricingCatalog.estimatedCost(for: record))

        #expect(abs(cost - 1.725) < 0.000_001)
    }

    @Test("Priority 会话按 OpenAI 官方 Priority 价格估算")
    func appliesPriorityServiceTierPricing() throws {
        let timestamp = try date("2026-07-23T02:00:00Z")
        let standard = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-sol",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000
        )
        let priority = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-sol",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000,
            serviceTier: .priority
        )

        #expect(TokenPricingCatalog.estimatedCost(for: standard) == 0.5)
        #expect(TokenPricingCatalog.estimatedCost(for: priority) == 1)
    }

    @Test("未知模型保留 Token 占比但不猜测金额")
    func preservesUnknownModelsWithoutInventingPrice() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let snapshot = TokenCostCalculator.snapshot(
            records: [record(model: "codex-auto-review", at: now, tokens: 500)],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )

        #expect(snapshot.today.totalTokens == 500)
        #expect(snapshot.today.models.first?.estimatedCostUSD == nil)
        #expect(snapshot.today.hasUnpricedTokens)
    }

    @Test("累计剔除未计价模型和未计价金额标记")
    func lifetimeExcludesUnpricedModels() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let snapshot = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 100),
                record(model: "codex-auto-review", at: now, tokens: 500)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )

        #expect(snapshot.today.totalTokens == 600)
        #expect(snapshot.today.hasUnpricedTokens)
        #expect(snapshot.lifetime.totalTokens == 100)
        #expect(snapshot.lifetime.models.map(\.model) == ["gpt-5.6-sol"])
        #expect(!snapshot.lifetime.hasUnpricedTokens)
        #expect(TokenCostFormatter.amount(snapshot.lifetime) == "$0.00")
    }

    @Test("今日、昨日、订阅周期和累计使用各自准确分组")
    func groupsRequestedCostPeriods() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let subscriptionStart = try date("2026-07-06T02:29:39Z")
        let subscriptionEnd = try date("2026-08-06T02:29:39Z")
        let snapshot = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.5", at: try date("2026-07-23T02:00:00Z"), tokens: 100),
                record(model: "gpt-5.5", at: try date("2026-07-22T02:00:00Z"), tokens: 200),
                record(model: "gpt-5.6-sol", at: try date("2026-07-10T02:00:00Z"), tokens: 300),
                record(model: "gpt-5.6-luna", at: try date("2026-06-10T02:00:00Z"), tokens: 400)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: DateInterval(start: subscriptionStart, end: subscriptionEnd)
        )

        #expect(snapshot.today.totalTokens == 100)
        #expect(snapshot.yesterday.totalTokens == 200)
        #expect(snapshot.subscription?.totalTokens == 600)
        #expect(snapshot.lifetime.totalTokens == 1_000)
    }

    @Test("过期的月度认证区间按原续费锚点推进到当前周期")
    func advancesStaleMonthlySubscriptionPeriod() throws {
        let period = SubscriptionPeriodResolver.currentPeriod(
            activeStart: try date("2026-06-06T02:29:39Z"),
            activeUntil: try date("2026-07-06T02:29:39Z"),
            now: try date("2026-07-23T12:00:00Z"),
            calendar: utcCalendar
        )
        let expectedStart = try date("2026-07-06T02:29:39Z")
        let expectedEnd = try date("2026-08-06T02:29:39Z")

        #expect(period?.start == expectedStart)
        #expect(period?.end == expectedEnd)
    }

    @Test("会话解析逐次累计用量并跟随当前模型")
    func parsesEveryTokenUsageEventWithItsModel() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        let fixture = """
        {"timestamp":"2026-07-23T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}
        {"timestamp":"2026-07-23T01:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"total_tokens":110}}}}
        {"timestamp":"2026-07-23T02:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T02:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"cache_write_input_tokens":0,"output_tokens":20,"total_tokens":220}}}}
        """
        try fixture.write(to: temporary, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let records = try TokenCostSessionParser.records(in: temporary)

        #expect(records.map(\.model) == ["gpt-5.5", "gpt-5.6-sol"])
        #expect(records.map(\.totalTokens) == [110, 220])
        #expect(records.first?.cacheWriteInputTokens == 0)
    }

    @Test("旧累计日志、子会话回放和服务档位按会话事实解析")
    func parsesReliableSessionUsageWithoutReplayDoubleCount() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        let fixture = """
        {"timestamp":"2026-07-23T01:00:00.000Z","type":"session_meta","payload":{"parent_thread_id":"parent"}}
        {"timestamp":"2026-07-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"total_tokens":120}}}}
        {"timestamp":"2026-07-23T01:00:03.000Z","type":"event_msg","payload":{"type":"task_started","started_at":0}}
        {"timestamp":"2026-07-23T01:00:04.000Z","type":"event_msg","payload":{"type":"task_started","started_at":2000000000}}
        {"timestamp":"2026-07-23T01:00:05.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"priority"}}}
        {"timestamp":"2026-07-23T01:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":20,"output_tokens":35,"total_tokens":195}}}}
        {"timestamp":"2026-07-23T01:00:07.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":60,"cached_input_tokens":10,"output_tokens":15,"total_tokens":75},"total_token_usage":{"input_tokens":160,"cached_input_tokens":20,"output_tokens":35,"total_tokens":195}}}}
        """
        try fixture.write(to: temporary, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let records = try TokenCostSessionParser.records(in: temporary)

        #expect(records.count == 1)
        #expect(records[0].inputTokens == 60)
        #expect(records[0].cachedInputTokens == 10)
        #expect(records[0].outputTokens == 15)
        #expect(records[0].totalTokens == 75)
        #expect(records[0].serviceTier == .priority)
    }

    @Test("成本读取器只用本机会话用量并从认证信息恢复当前订阅周期")
    func readerBuildsTodayAndSubscriptionSummaries() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = home.appendingPathComponent(".codex/sessions/2026/07/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let session = """
        {"timestamp":"2026-07-23T18:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T18:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"cache_write_input_tokens":0,"output_tokens":10,"total_tokens":110}}}}
        """
        try session.write(
            to: sessions.appendingPathComponent("rollout.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_subscription_active_start":"2026-06-06T02:29:39+00:00","chatgpt_subscription_active_until":"2026-07-06T02:29:39+00:00"}}"#
        let payload = try #require(claims.data(using: .utf8))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = #"{"tokens":{"id_token":"header.\#(payload).signature"}}"#
        let authURL = home.appendingPathComponent(".codex/auth.json")
        try auth.write(to: authURL, atomically: true, encoding: .utf8)

        let snapshot = try await TokenCostReader(homeDirectory: home).read(
            now: try date("2026-07-23T20:00:00Z")
        )
        let expectedStart = try date("2026-07-06T02:29:39Z")

        #expect(snapshot.today.totalTokens == 110)
        #expect(snapshot.subscription?.totalTokens == 110)
        #expect(snapshot.subscriptionPeriod?.start == expectedStart)
    }

    @Test("跨文件复制的相同会话事件只计一次")
    func readerDeduplicatesCopiedSessionEvents() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = home.appendingPathComponent(".codex/sessions/2026/07/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let session = """
        {"timestamp":"2026-07-23T18:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T18:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"total_tokens":110}}}}
        """
        try session.write(to: sessions.appendingPathComponent("first.jsonl"), atomically: true, encoding: .utf8)
        try session.write(to: sessions.appendingPathComponent("copied.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = try await TokenCostReader(homeDirectory: home).read(
            now: try date("2026-07-23T20:00:00Z")
        )

        #expect(snapshot.today.totalTokens == 110)
    }

    @Test("成本界面悬浮只高亮并由点击稳定展开面板内模型明细")
    func costSectionKeepsRequestedCompactInteraction() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/TokenCostSection.swift",
            encoding: .utf8
        )

        #expect(source.contains("case .yesterday: return \"昨日\""))
        #expect(source.contains("case .subscription: return \"本订阅周期\""))
        #expect(source.contains("case .lifetime: return \"累计\""))
        #expect(!source.contains("昨日成本"))
        #expect(!source.contains("本周期成本"))
        #expect(!source.contains("累计成本"))
        #expect(source.contains("Text(\"今日\")"))
        #expect(source.contains("Text(\"本机数据\")"))
        #expect(source.contains(".foregroundStyle(.tertiary)"))
        #expect(!source.contains("Text(\"API 估算\")"))
        #expect(source.contains("hoveredKind"))
        #expect(source.contains("pinnedKind"))
        #expect(source.contains("pinnedKind ?? hoveredKind"))
        #expect(source.contains(".onChange(of: pinnedKind)"))
        #expect(source.contains("guard let pinnedKind, let snapshot"))
        #expect(!source.contains(".onChange(of: activeKind)"))
        #expect(!source.contains("scheduleHoveredKindClear()"))
        #expect(!source.contains("hoverExitTask"))
        #expect(!source.contains(".transition("))
        #expect(source.contains("TokenCostDetailCard"))
        #expect(!source.contains(".popover("))
        #expect(source.contains("非实际账单"))
        #expect(source.contains("本机数据，按官方 API 价估算"))
        #expect(!source.contains("accountLifetimeTokens"))
        #expect(!source.contains("accountTotalTokens"))
        #expect(!source.contains("未归因用量"))
        #expect(!source.contains("TokenCostAttribution"))
    }

    @Test("金额固定使用美元符号且不显示地区前缀")
    func amountOmitsUSLocalePrefix() {
        #expect(TokenCostFormatter.amount(12.346) == "$12.35")
        #expect(!TokenCostFormatter.amount(12.346).contains("US"))
    }

    private func record(model: String, at date: Date, tokens: Int64) -> TokenUsageRecord {
        TokenUsageRecord(
            timestamp: date,
            model: model,
            inputTokens: tokens,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: tokens
        )
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
