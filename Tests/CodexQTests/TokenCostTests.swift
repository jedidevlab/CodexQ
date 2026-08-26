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

    @Test("GPT-5.6 Sol 促销价只应用于生效后的记录和别名")
    func appliesGPT56SolPromotionalPriceByRecordTime() throws {
        let oldSol = TokenUsageRecord(
            timestamp: try date("2026-08-20T23:59:59Z"),
            model: "gpt-5.6-sol",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )
        let currentAlias = TokenUsageRecord(
            timestamp: try date("2026-08-21T00:00:00Z"),
            model: "gpt-5.6",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )

        #expect(TokenPricingCatalog.estimatedCost(for: oldSol) == 3.55)
        #expect(TokenPricingCatalog.estimatedCost(for: currentAlias) == 2.44)
    }

    @Test("GPT-5.6 Sol 促销价同步覆盖缓存写入和 Fast 计价")
    func appliesCurrentGPT56SolCacheWriteAndFastRates() throws {
        let timestamp = try date("2026-08-21T02:00:00Z")
        let cacheWrite = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-sol",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 100_000,
            outputTokens: 0,
            totalTokens: 100_000
        )
        let fast = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-sol",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000,
            serviceTier: .priority
        )

        #expect(TokenPricingCatalog.estimatedCost(for: cacheWrite) == 0.5)
        #expect(TokenPricingCatalog.estimatedCost(for: fast) == 0.8)
    }

    @Test("GPT-5.6 Terra 和 Luna 降价只应用于生效后的记录")
    func appliesGPT56PriceReductionByRecordTime() throws {
        let oldTerra = TokenUsageRecord(
            timestamp: try date("2026-07-30T23:59:59Z"),
            model: "gpt-5.6-terra",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )
        let newTerra = TokenUsageRecord(
            timestamp: try date("2026-07-31T00:00:00Z"),
            model: "gpt-5.6-terra",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )
        let oldLuna = TokenUsageRecord(
            timestamp: try date("2026-07-30T23:59:59Z"),
            model: "gpt-5.6-luna",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )
        let newLuna = TokenUsageRecord(
            timestamp: try date("2026-07-31T00:00:00Z"),
            model: "gpt-5.6-luna",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )

        #expect(TokenPricingCatalog.estimatedCost(for: oldTerra) == 1.775)
        #expect(TokenPricingCatalog.estimatedCost(for: newTerra) == 1.42)
        #expect(TokenPricingCatalog.estimatedCost(for: oldLuna) == 0.71)
        #expect(TokenPricingCatalog.estimatedCost(for: newLuna) == 0.142)
    }

    @Test("GPT-5.6 降价后的缓存写入和 Priority 仍使用各自官方费率")
    func appliesCurrentGPT56CacheWriteAndPriorityRates() throws {
        let timestamp = try date("2026-07-31T02:00:00Z")
        let terraCacheWrite = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-terra",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 100_000,
            outputTokens: 0,
            totalTokens: 100_000
        )
        let lunaCacheWrite = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-luna",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 100_000,
            outputTokens: 0,
            totalTokens: 100_000
        )
        let terraPriority = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-terra",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000,
            serviceTier: .priority
        )
        let lunaPriority = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.6-luna",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000,
            serviceTier: .priority
        )

        #expect(TokenPricingCatalog.estimatedCost(for: terraCacheWrite) == 0.25)
        #expect(TokenPricingCatalog.estimatedCost(for: lunaCacheWrite) == 0.025)
        #expect(TokenPricingCatalog.estimatedCost(for: terraPriority) == 0.5)
        #expect(TokenPricingCatalog.estimatedCost(for: lunaPriority) == 0.2)
    }

    @Test("GPT-5.4 按官方标准价、长上下文和 Priority 计价")
    func pricesGPT54WithOfficialRates() throws {
        let timestamp = try date("2026-07-23T02:00:00Z")
        let standard = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.4",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 300_000
        )
        let longContext = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.4-2026-03-05",
            inputTokens: 300_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 10_000,
            totalTokens: 310_000
        )
        let priority = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-5.4",
            inputTokens: 100_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: 100_000,
            serviceTier: .priority
        )

        #expect(TokenPricingCatalog.estimatedCost(for: standard) == 1.775)
        #expect(TokenPricingCatalog.estimatedCost(for: longContext) == 1.725)
        #expect(TokenPricingCatalog.estimatedCost(for: priority) == 0.5)
    }

    @Test("官方文档列价的文本模型和快照都有本地价格")
    func officialTextModelsAndSnapshotsHaveLocalPricing() {
        let models = [
            "gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
            "gpt-5.5", "gpt-5.5-2026-04-23", "gpt-5.5-pro", "gpt-5.5-pro-2026-04-23",
            "gpt-5.4", "gpt-5.4-2026-03-05", "gpt-5.4-mini", "gpt-5.4-mini-2026-03-17",
            "gpt-5.4-nano", "gpt-5.4-nano-2026-03-17", "gpt-5.4-pro", "gpt-5.4-pro-2026-03-05",
            "gpt-5.3-codex", "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-5.2-pro",
            "gpt-5.2-pro-2025-12-11", "gpt-5.2-codex", "gpt-5.1", "gpt-5.1-2025-11-13",
            "gpt-5.1-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini",
            "gpt-5", "gpt-5-2025-08-07", "gpt-5-mini", "gpt-5-mini-2025-08-07",
            "gpt-5-nano", "gpt-5-nano-2025-08-07", "gpt-5-pro", "gpt-5-pro-2025-10-06",
            "gpt-5-chat-latest", "gpt-5.1-chat-latest", "gpt-5.2-chat-latest",
            "gpt-5.3-chat-latest", "chat-latest", "codex-mini-latest",
            "o3-pro", "o3-pro-2025-06-10", "o3", "o3-2025-04-16",
            "o4-mini", "o4-mini-2025-04-16", "o3-mini", "o3-mini-2025-01-31",
            "o1", "o1-2024-12-17", "o1-preview", "o1-preview-2024-09-12",
            "o1-mini", "o1-mini-2024-09-12", "o1-pro", "o1-pro-2025-03-19",
            "gpt-4.1", "gpt-4.1-2025-04-14", "gpt-4.1-mini", "gpt-4.1-mini-2025-04-14",
            "gpt-4.1-nano", "gpt-4.1-nano-2025-04-14", "gpt-4o", "gpt-4o-2024-08-06",
            "gpt-4o-2024-11-20", "gpt-4o-2024-05-13", "gpt-4o-mini", "gpt-4o-mini-2024-07-18",
            "gpt-4.5-preview", "gpt-4.5-preview-2025-02-27", "gpt-4", "gpt-4-0613",
            "gpt-4-0314", "gpt-4-turbo", "gpt-4-turbo-2024-04-09", "gpt-4-turbo-preview",
            "gpt-4-0125-preview", "gpt-4-1106-vision-preview", "gpt-3.5-turbo",
            "gpt-3.5-turbo-0125", "gpt-3.5-turbo-1106", "gpt-3.5-turbo-instruct",
            "gpt-3.5-turbo-16k", "gpt-3.5-turbo-16k-0613",
            "davinci-002", "babbage-002", "chatgpt-4o-latest",
            "computer-use-preview", "computer-use-preview-2025-03-11",
            "o3-deep-research", "o3-deep-research-2025-06-26",
            "o4-mini-deep-research", "o4-mini-deep-research-2025-06-26"
        ]

        #expect(models.allSatisfy { TokenPricingCatalog.pricing(for: $0) != nil })
    }

    @Test("独立的 Instruct 和 16K 旧模型使用各自的官方价格")
    func pricesLegacyGPT35ModelsIndividually() throws {
        let timestamp = try date("2026-07-23T02:00:00Z")
        let instruct = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-3.5-turbo-instruct",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000
        )
        let longContext = TokenUsageRecord(
            timestamp: timestamp,
            model: "gpt-3.5-turbo-16k-0613",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000
        )

        #expect(TokenPricingCatalog.estimatedCost(for: instruct) == 3.5)
        #expect(TokenPricingCatalog.estimatedCost(for: longContext) == 7)
    }

    @Test("同一模型别名按记录时间使用当时价格")
    func pricesMutableModelAliasAtRecordTimestamp() throws {
        let launchAlias = TokenUsageRecord(
            timestamp: try date("2024-06-01T00:00:00Z"),
            model: "gpt-4o",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000
        )
        let discountedAlias = TokenUsageRecord(
            timestamp: try date("2024-09-01T00:00:00Z"),
            model: "gpt-4o",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000
        )
        let launchSnapshot = TokenUsageRecord(
            timestamp: try date("2026-07-23T00:00:00Z"),
            model: "gpt-4o-2024-05-13",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000
        )

        #expect(TokenPricingCatalog.estimatedCost(for: launchAlias) == 20)
        #expect(TokenPricingCatalog.estimatedCost(for: discountedAlias) == 12.5)
        #expect(TokenPricingCatalog.estimatedCost(for: launchSnapshot) == 20)
    }

    @Test("非 OpenAI 或无官方价格的模型完全不纳入成本")
    func excludesModelsWithoutOfficialPricing() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let snapshot = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 100),
                record(model: "codex-auto-review", at: now, tokens: 500),
                record(model: "MiniMax-M3", at: now, tokens: 1_000)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )

        #expect(snapshot.today.totalTokens == 100)
        #expect(snapshot.today.models.map(\.model) == ["gpt-5.6-sol"])
        #expect(snapshot.lifetime.totalTokens == 100)
        #expect(TokenCostFormatter.amount(snapshot.lifetime) == "$0.00")
    }

    @Test("同一 OpenAI 模型缺少历史定价的记录不纳入成本")
    func excludesRecordsWithoutHistoricalPricing() throws {
        let snapshot = TokenCostCalculator.snapshot(
            records: [
                record(
                    model: "gpt-4o",
                    at: try date("2024-01-01T00:00:00Z"),
                    tokens: 1_000_000
                ),
                record(
                    model: "gpt-4o",
                    at: try date("2024-09-01T00:00:00Z"),
                    tokens: 1_000_000
                )
            ],
            now: try date("2026-07-23T12:00:00Z"),
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )

        #expect(snapshot.lifetime.estimatedCostUSD == 2.5)
        #expect(snapshot.lifetime.totalTokens == 1_000_000)
        #expect(TokenCostFormatter.amount(snapshot.lifetime) == "$2.50")
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

    @Test("账号累计 Token 以净差额补算并与账本成本分开")
    func reconcilesAccountTotalsWithoutChangingRecordedCost() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let recorded = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 1_000_000)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 1_500_000,
            lifetimeTokens: 1_500_000,
            days: [
                TokenActivityDay(startDate: "2026-07-23", tokens: 1_500_000)
            ]
        )

        let reconciled = TokenCostReconciler.reconcile(
            recorded,
            with: activity,
            now: now,
            calendar: utcCalendar
        )

        #expect(reconciled.lifetime.recordedTokens == 1_000_000)
        #expect(reconciled.lifetime.totalTokens == 1_500_000)
        #expect(
            reconciled.lifetime.recordedEstimatedCostUSD
                == recorded.lifetime.recordedEstimatedCostUSD
        )
        #expect(reconciled.lifetime.supplement?.tokens == 500_000)
        #expect(
            reconciled.lifetime.supplement?.estimatedCostUSD
                == recorded.lifetime.recordedEstimatedCostUSD / 2
        )
        #expect(
            reconciled.lifetime.estimatedCostUSD
                == recorded.lifetime.recordedEstimatedCostUSD * 1.5
        )
        #expect(reconciled.today.totalTokens == 1_500_000)
    }

    @Test("账号 Token 不高于账本时不生成负数补算")
    func doesNotCreateNegativeSupplement() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let recorded = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 1_000_000)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 900_000,
            lifetimeTokens: 900_000,
            days: [
                TokenActivityDay(startDate: "2026-07-23", tokens: 900_000)
            ]
        )

        let reconciled = TokenCostReconciler.reconcile(
            recorded,
            with: activity,
            now: now,
            calendar: utcCalendar
        )

        #expect(reconciled.lifetime.recordedTokens == 1_000_000)
        #expect(reconciled.lifetime.totalTokens == 1_000_000)
        #expect(reconciled.lifetime.supplement == nil)
        #expect(
            reconciled.lifetime.estimatedCostUSD
                == recorded.lifetime.recordedEstimatedCostUSD
        )
    }

    @Test("非公历系统下仍按公历解析账号活动日期")
    func reconcilerUsesGregorianActivityDates() throws {
        let now = try date("2026-08-09T12:00:00Z")
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let recorded = TokenCostCalculator.snapshot(
            records: [],
            now: now,
            calendar: buddhistCalendar,
            subscriptionPeriod: nil
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 123,
            days: [TokenActivityDay(startDate: "2026-08-09", tokens: 123)]
        )

        let reconciled = TokenCostReconciler.reconcile(
            recorded,
            with: activity,
            now: now,
            calendar: buddhistCalendar
        )

        #expect(reconciled.today.totalTokens == 123)
    }

    @Test("非法活动日期不能归一化后参与成本补算")
    func invalidActivityDateDoesNotAffectReconciliation() throws {
        let now = try date("2026-03-02T12:00:00Z")
        let recorded = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 100)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: nil
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 200,
            days: [
                TokenActivityDay(startDate: "2026-02-30", tokens: 200)
            ]
        )

        let reconciled = TokenCostReconciler.reconcile(
            recorded,
            with: activity,
            now: now,
            calendar: utcCalendar
        )

        #expect(reconciled.today.accountTokens == nil)
        #expect(reconciled.today.totalTokens == 100)
        #expect(reconciled.today.supplement == nil)
    }

    @Test("缺少活动日桶时保留账本中的订阅周期 Token")
    func missingDailyBucketsPreserveRecordedSubscriptionTokens() throws {
        let now = try date("2026-07-23T12:00:00Z")
        let period = DateInterval(
            start: try date("2026-07-06T02:29:39Z"),
            end: try date("2026-08-06T02:29:39Z")
        )
        let recorded = TokenCostCalculator.snapshot(
            records: [
                record(model: "gpt-5.6-sol", at: now, tokens: 100)
            ],
            now: now,
            calendar: utcCalendar,
            subscriptionPeriod: period
        )
        let activity = TokenActivitySnapshot(
            peakDailyTokens: 0,
            lifetimeTokens: 100,
            days: []
        )

        let reconciled = TokenCostReconciler.reconcile(
            recorded,
            with: activity,
            now: now,
            calendar: utcCalendar
        )

        #expect(reconciled.subscription?.accountTokens == nil)
        #expect(reconciled.subscription?.totalTokens == 100)
        #expect(reconciled.subscription?.supplement == nil)
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

        let reader = TokenCostReader(
            homeDirectory: home,
            costSyncConfiguration: { nil }
        )
        let now = try date("2026-07-23T20:00:00Z")
        let records = try await reader.readRecordSet(now: now)
        let snapshot = try await reader.read(now: now)
        let expectedStart = try date("2026-07-06T02:29:39Z")

        #expect(records.records.count == 1)
        #expect(records.localRecordCount == snapshot.sourceRecordCount)
        #expect(records.dataScope == snapshot.dataScope)
        #expect(records.skippedSessionFileCount == snapshot.skippedSessionFileCount)
        #expect(records.subscriptionAnchor?.cadence == .month)
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

    @Test("成本读取器跳过单个不可读会话文件并报告部分数据")
    func readerSkipsUnreadableSessionFilesAndReportsPartialData() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = home.appendingPathComponent(".codex/sessions/2026/07/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let session = """
        {"timestamp":"2026-07-23T18:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T18:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"total_tokens":110}}}}
        """
        try session.write(to: sessions.appendingPathComponent("valid.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: sessions.appendingPathComponent("unreadable.jsonl", isDirectory: true),
            withIntermediateDirectories: true
        )

        let snapshot = try await TokenCostReader(homeDirectory: home).read(
            now: try date("2026-07-23T20:00:00Z")
        )

        #expect(snapshot.today.totalTokens == 110)
        #expect(snapshot.skippedSessionFileCount == 1)
    }

    @Test("启用多设备同步后无本机会话仍读取远端账本")
    func readerLoadsRemoteLedgerWithoutLocalSessions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let remoteHome = root.appendingPathComponent("remote-home", isDirectory: true)
        let localHome = root.appendingPathComponent("local-home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for home in [remoteHome, localHome] {
            let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(
                at: codexDirectory,
                withIntermediateDirectories: true
            )
            try #"{"tokens":{"account_id":"same-account"}}"#.write(
                to: codexDirectory.appendingPathComponent("auth.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let remoteService = CostLedgerSyncService(
            homeDirectory: remoteHome,
            cacheURL: root.appendingPathComponent("remote-cache.json")
        )
        let namespace = try remoteService.prepare(folderURL: folder)
        _ = try remoteService.sync(
            localRecords: [
                TokenUsageRecord(
                    eventID: "remote-event",
                    timestamp: try date("2026-07-23T18:00:00Z"),
                    model: "gpt-5.6-sol",
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    cacheWriteInputTokens: 0,
                    outputTokens: 10,
                    totalTokens: 110
                )
            ],
            configuration: CostSyncConfiguration(
                folderURL: folder,
                deviceID: "remote-device",
                namespace: namespace
            )
        )
        let configuration = CostSyncConfiguration(
            folderURL: folder,
            deviceID: "local-device",
            namespace: namespace
        )

        let snapshot = try await TokenCostReader(
            homeDirectory: localHome,
            costLedgerCacheURL: root.appendingPathComponent("local-cache.json"),
            costSyncConfiguration: { configuration }
        ).read(now: try date("2026-07-23T20:00:00Z"))

        #expect(snapshot.today.totalTokens == 110)
        #expect(snapshot.lifetime.totalTokens == 110)
        #expect(snapshot.dataScope == .singleDevice)
    }

    @Test("取消多设备成本读取必须向上抛出取消，不能降级成同步延迟结果")
    func readerPropagatesSyncCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = CostSyncConfiguration(
            folderURL: folder,
            deviceID: "cancelled-device",
            namespace: "cancelled-namespace"
        )
        let reader = TokenCostReader(
            homeDirectory: home,
            costLedgerCacheURL: root.appendingPathComponent("cache.json"),
            costSyncConfiguration: { configuration }
        )
        let propagated = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await reader.read()
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value

        #expect(propagated)
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
        #expect(source.contains("Text(scopeLabel)"))
        #expect(source.contains(".foregroundStyle(.tertiary)"))
        #expect(!source.contains("Text(\"API 估算\")"))
        #expect(source.contains("hoveredKind"))
        #expect(source.contains("pinnedKind"))
        let willChange = try #require(source.range(of: "contentWillChange()"))
        let stateChange = try #require(
            source.range(
                of: "pinnedKind = pinnedKind == summary.kind ? nil : summary.kind",
                range: willChange.upperBound..<source.endIndex
            )
        )
        #expect(willChange.lowerBound < stateChange.lowerBound)
        #expect(source.contains("transaction.disablesAnimations = true"))
        #expect(source.contains("withTransaction(transaction)"))
        #expect(source.contains("pinnedKind ?? hoveredKind"))
        #expect(source.contains(".onChange(of: pinnedKind)"))
        #expect(source.contains("guard let pinnedKind, let snapshot"))
        #expect(!source.contains(".onChange(of: activeKind)"))
        #expect(!source.contains("scheduleHoveredKindClear()"))
        #expect(!source.contains("hoverExitTask"))
        #expect(!source.contains(".transition("))
        #expect(source.contains("TokenCostDetailCard"))
        #expect(source.contains(".background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))"))
        #expect(source.contains(".strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)"))
        #expect(!source.contains(".background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))"))
        #expect(!source.contains(".shadow(color: .black.opacity(0.12), radius: 8, y: 3)"))
        #expect(source.contains("ForEach(summary.models) { model in"))
        #expect(!source.contains("summary.models.prefix(6)"))
        #expect(!source.contains("另有 \\(summary.models.count - 6) 个模型"))
        #expect(source.contains("非实际账单"))
        #expect(source.contains("本机数据，按官方 API 价估算"))
        #expect(source.contains("case .singleDevice: return \"仅此设备\""))
        #expect(source.contains("case .multiDevice: return \"多设备数据\""))
        #expect(source.contains("仅此设备数据，按官方 API 价估算"))
        #expect(source.contains("多设备数据，按官方 API 价估算"))
        #expect(!source.contains("仅本地数据"))
        #expect(!source.contains("同步账本 · 1 台"))
        #expect(!source.contains("iCloud 脱敏账本，按官方 API 价估算"))
        #expect(!source.contains("多设备脱敏账本，按官方 API 价估算"))
        #expect(source.contains("summary.recordedEstimatedCostUSD"))
        #expect(source.contains("summary.supplement"))
        #expect(source.contains("设备记录"))
        #expect(source.contains("官方差额"))
        #expect(source.contains("Image(systemName: \"info.circle\")"))
        #expect(source.contains(".popover(isPresented: $isSupplementExplanationPresented"))
        #expect(source.contains("官方 Token 数据高于设备记录时"))
        #expect(source.contains("TokenCountFormatter.compactNumber(summary.totalTokens, fractionLength: 1)"))
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
