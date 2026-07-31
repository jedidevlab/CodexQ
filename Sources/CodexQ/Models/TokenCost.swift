import Foundation

enum TokenServiceTier: String, Codable, Hashable, Sendable {
    case standard
    case priority
}

struct TokenUsageRecord: Equatable, Hashable, Sendable {
    let eventID: String?
    let timestamp: Date
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let serviceTier: TokenServiceTier

    init(
        eventID: String? = nil,
        timestamp: Date,
        model: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteInputTokens: Int64,
        outputTokens: Int64,
        totalTokens: Int64,
        serviceTier: TokenServiceTier = .standard
    ) {
        self.eventID = eventID
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.serviceTier = serviceTier
    }
}

enum TokenCostDataScope: Equatable, Sendable {
    case local
    case singleDevice
    case multiDevice(deviceCount: Int)
    case syncDelayed
    case syncBlocked
    case partial(deviceCount: Int)
}

struct TokenCostSnapshot: Equatable, Sendable {
    let today: TokenCostPeriodSummary
    let yesterday: TokenCostPeriodSummary
    let subscription: TokenCostPeriodSummary?
    let lifetime: TokenCostPeriodSummary
    let subscriptionPeriod: DateInterval?
    let skippedSessionFileCount: Int
    let dataScope: TokenCostDataScope
    let syncMessage: String?
    let sourceRecordCount: Int

    init(
        today: TokenCostPeriodSummary,
        yesterday: TokenCostPeriodSummary,
        subscription: TokenCostPeriodSummary?,
        lifetime: TokenCostPeriodSummary,
        subscriptionPeriod: DateInterval?,
        skippedSessionFileCount: Int = 0,
        dataScope: TokenCostDataScope = .local,
        syncMessage: String? = nil,
        sourceRecordCount: Int = 0
    ) {
        self.today = today
        self.yesterday = yesterday
        self.subscription = subscription
        self.lifetime = lifetime
        self.subscriptionPeriod = subscriptionPeriod
        self.skippedSessionFileCount = skippedSessionFileCount
        self.dataScope = dataScope
        self.syncMessage = syncMessage
        self.sourceRecordCount = sourceRecordCount
    }
}

struct TokenCostPeriodSummary: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case today
        case yesterday
        case subscription
        case lifetime
    }

    let kind: Kind
    let models: [TokenCostModelSummary]
    let accountTokens: Int64?
    let supplement: TokenCostSupplement?

    var id: Kind { kind }
    var recordedTokens: Int64 { models.reduce(0) { $0 + $1.totalTokens } }
    var totalTokens: Int64 { accountTokens ?? recordedTokens }
    var recordedEstimatedCostUSD: Double {
        models.reduce(0) { $0 + $1.estimatedCostUSD }
    }
    var estimatedCostUSD: Double {
        recordedEstimatedCostUSD + (supplement?.estimatedCostUSD ?? 0)
    }

    init(
        kind: Kind,
        models: [TokenCostModelSummary],
        accountTokens: Int64? = nil,
        supplement: TokenCostSupplement? = nil
    ) {
        self.kind = kind
        self.models = models
        self.accountTokens = accountTokens
        self.supplement = supplement
    }
}

struct TokenCostSupplement: Equatable, Sendable {
    let tokens: Int64
    let estimatedCostUSD: Double
}

struct TokenCostModelSummary: Equatable, Sendable, Identifiable {
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let estimatedCostUSD: Double

    var id: String { model }
}

struct TokenPricing: Equatable, Sendable {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let cacheWritePerMillion: Double
    let outputPerMillion: Double
    let priorityMultiplier: Double
    let appliesLongContextPremium: Bool
}

enum TokenPricingCatalog {
    static let effectiveDate = "2026-07-31"
    static let longContextThreshold: Int64 = 272_000

    static func pricing(for model: String) -> TokenPricing? {
        pricing(for: model, at: nil)
    }

    static func pricing(for model: String, at timestamp: Date?) -> TokenPricing? {
        let key = model.lowercased()
        if let timestamp, let history = historicalCatalog[key] {
            return history.last { $0.effectiveAt <= timestamp }?.pricing
        }
        return catalog[key]
    }

    private struct HistoricalPricing: Sendable {
        let effectiveAt: Date
        let pricing: TokenPricing
    }

    private static let catalog: [String: TokenPricing] = {
        var result: [String: TokenPricing] = [:]

        func add(
            _ aliases: [String],
            input: Double,
            cached: Double? = nil,
            cacheWrite: Double? = nil,
            output: Double,
            priorityMultiplier: Double? = nil,
            longContext: Bool = false
        ) {
            let pricing = TokenPricing(
                inputPerMillion: input,
                cachedInputPerMillion: cached ?? input,
                cacheWritePerMillion: cacheWrite ?? input,
                outputPerMillion: output,
                priorityMultiplier: priorityMultiplier ?? 1,
                appliesLongContextPremium: longContext
            )
            for alias in aliases {
                result[alias.lowercased()] = pricing
            }
        }

        add(["gpt-5.6", "gpt-5.6-sol"], input: 5, cached: 0.5, cacheWrite: 6.25, output: 30, priorityMultiplier: 2, longContext: true)
        add(["gpt-5.6-terra"], input: 2, cached: 0.2, cacheWrite: 2.5, output: 12, priorityMultiplier: 2.5, longContext: true)
        add(["gpt-5.6-luna"], input: 0.2, cached: 0.02, cacheWrite: 0.25, output: 1.2, priorityMultiplier: 10, longContext: true)
        add(["gpt-5.5", "gpt-5.5-2026-04-23"], input: 5, cached: 0.5, output: 30, priorityMultiplier: 2.5, longContext: true)
        add(["gpt-5.5-pro", "gpt-5.5-pro-2026-04-23"], input: 30, output: 180, longContext: true)
        add(["gpt-5.4", "gpt-5.4-2026-03-05"], input: 2.5, cached: 0.25, output: 15, priorityMultiplier: 2, longContext: true)
        add(["gpt-5.4-mini", "gpt-5.4-mini-2026-03-17"], input: 0.75, cached: 0.075, output: 4.5, priorityMultiplier: 2)
        add(["gpt-5.4-nano", "gpt-5.4-nano-2026-03-17"], input: 0.2, cached: 0.02, output: 1.25)
        add(["gpt-5.4-pro", "gpt-5.4-pro-2026-03-05"], input: 30, output: 180, longContext: true)
        add(["gpt-5.3-codex"], input: 1.75, cached: 0.175, output: 14, priorityMultiplier: 2)
        add(["gpt-5.2", "gpt-5.2-2025-12-11"], input: 1.75, cached: 0.175, output: 14)
        add(["gpt-5.2-pro", "gpt-5.2-pro-2025-12-11"], input: 21, output: 168)
        add(["gpt-5.2-codex"], input: 1.75, cached: 0.175, output: 14)
        add(["gpt-5.1", "gpt-5.1-2025-11-13"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5.1-codex"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5.1-codex-max"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5.1-codex-mini"], input: 0.25, cached: 0.025, output: 2)
        add(["gpt-5", "gpt-5-2025-08-07"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5-mini", "gpt-5-mini-2025-08-07"], input: 0.25, cached: 0.025, output: 2)
        add(["gpt-5-nano", "gpt-5-nano-2025-08-07"], input: 0.05, cached: 0.005, output: 0.4)
        add(["gpt-5-pro", "gpt-5-pro-2025-10-06"], input: 15, output: 120)
        add(["gpt-5-chat-latest"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5.1-chat-latest"], input: 1.25, cached: 0.125, output: 10)
        add(["gpt-5.2-chat-latest"], input: 1.75, cached: 0.175, output: 14)
        add(["gpt-5.3-chat-latest"], input: 1.75, cached: 0.175, output: 14)
        add(["chat-latest"], input: 5, cached: 0.5, output: 30)

        add(["codex-mini-latest"], input: 1.5, cached: 0.375, output: 6)
        add(["o3-pro", "o3-pro-2025-06-10"], input: 20, output: 80)
        add(["o3", "o3-2025-04-16"], input: 2, cached: 0.5, output: 8)
        add(["o4-mini", "o4-mini-2025-04-16"], input: 1.1, cached: 0.275, output: 4.4)
        add(["o3-mini", "o3-mini-2025-01-31"], input: 1.1, cached: 0.55, output: 4.4)
        add(["o1", "o1-2024-12-17", "o1-preview", "o1-preview-2024-09-12"], input: 15, cached: 7.5, output: 60)
        add(["o1-mini", "o1-mini-2024-09-12"], input: 1.1, cached: 0.55, output: 4.4)
        add(["o1-pro", "o1-pro-2025-03-19"], input: 150, output: 600)

        add(["gpt-4.1", "gpt-4.1-2025-04-14"], input: 2, cached: 0.5, output: 8)
        add(["gpt-4.1-mini", "gpt-4.1-mini-2025-04-14"], input: 0.4, cached: 0.1, output: 1.6)
        add(["gpt-4.1-nano", "gpt-4.1-nano-2025-04-14"], input: 0.1, cached: 0.025, output: 0.4)
        add(["gpt-4o", "gpt-4o-2024-08-06", "gpt-4o-2024-11-20"], input: 2.5, cached: 1.25, output: 10)
        add(["gpt-4o-2024-05-13"], input: 5, output: 15)
        add(["gpt-4o-mini", "gpt-4o-mini-2024-07-18"], input: 0.15, cached: 0.075, output: 0.6)
        add(["gpt-4.5-preview", "gpt-4.5-preview-2025-02-27"], input: 75, cached: 37.5, output: 150)
        add(["gpt-4", "gpt-4-0613", "gpt-4-0314"], input: 30, output: 60)
        add(["gpt-4-turbo", "gpt-4-turbo-2024-04-09", "gpt-4-turbo-preview", "gpt-4-0125-preview", "gpt-4-1106-vision-preview"], input: 10, output: 30)
        add(["gpt-3.5-turbo", "gpt-3.5-turbo-0125", "gpt-3.5-turbo-1106"], input: 0.5, output: 1.5)
        add(["gpt-3.5-turbo-instruct"], input: 1.5, output: 2)
        add(["gpt-3.5-turbo-16k", "gpt-3.5-turbo-16k-0613"], input: 3, output: 4)
        add(["davinci-002"], input: 2, output: 2)
        add(["babbage-002"], input: 0.4, output: 0.4)
        add(["chatgpt-4o-latest"], input: 5, output: 15)

        add(["computer-use-preview", "computer-use-preview-2025-03-11"], input: 3, output: 12)
        add(["o3-deep-research", "o3-deep-research-2025-06-26"], input: 10, cached: 2.5, output: 40)
        add(["o4-mini-deep-research", "o4-mini-deep-research-2025-06-26"], input: 2, cached: 0.5, output: 8)

        return result
    }()

    private static let historicalCatalog: [String: [HistoricalPricing]] = [
        "gpt-5.6-terra": [
            HistoricalPricing(
                effectiveAt: .distantPast,
                pricing: TokenPricing(
                    inputPerMillion: 2.5,
                    cachedInputPerMillion: 0.25,
                    cacheWritePerMillion: 3.125,
                    outputPerMillion: 15,
                    priorityMultiplier: 2,
                    appliesLongContextPremium: true
                )
            ),
            HistoricalPricing(
                effectiveAt: date("2026-07-31T00:00:00Z"),
                pricing: TokenPricing(
                    inputPerMillion: 2,
                    cachedInputPerMillion: 0.2,
                    cacheWritePerMillion: 2.5,
                    outputPerMillion: 12,
                    priorityMultiplier: 2.5,
                    appliesLongContextPremium: true
                )
            )
        ],
        "gpt-5.6-luna": [
            HistoricalPricing(
                effectiveAt: .distantPast,
                pricing: TokenPricing(
                    inputPerMillion: 1,
                    cachedInputPerMillion: 0.1,
                    cacheWritePerMillion: 1.25,
                    outputPerMillion: 6,
                    priorityMultiplier: 2,
                    appliesLongContextPremium: true
                )
            ),
            HistoricalPricing(
                effectiveAt: date("2026-07-31T00:00:00Z"),
                pricing: TokenPricing(
                    inputPerMillion: 0.2,
                    cachedInputPerMillion: 0.02,
                    cacheWritePerMillion: 0.25,
                    outputPerMillion: 1.2,
                    priorityMultiplier: 10,
                    appliesLongContextPremium: true
                )
            )
        ],
        "gpt-4o": [
            HistoricalPricing(
                effectiveAt: date("2024-05-13T00:00:00Z"),
                pricing: TokenPricing(
                    inputPerMillion: 5,
                    cachedInputPerMillion: 5,
                    cacheWritePerMillion: 5,
                    outputPerMillion: 15,
                    priorityMultiplier: 1,
                    appliesLongContextPremium: false
                )
            ),
            HistoricalPricing(
                effectiveAt: date("2024-08-06T00:00:00Z"),
                pricing: TokenPricing(
                    inputPerMillion: 2.5,
                    cachedInputPerMillion: 1.25,
                    cacheWritePerMillion: 2.5,
                    outputPerMillion: 10,
                    priorityMultiplier: 1,
                    appliesLongContextPremium: false
                )
            )
        ]
    ]

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    static func estimatedCost(for record: TokenUsageRecord) -> Double? {
        guard let pricing = pricing(for: record.model, at: record.timestamp) else { return nil }
        let cached = min(record.cachedInputTokens, record.inputTokens)
        let cacheWrite = min(
            record.cacheWriteInputTokens,
            max(0, record.inputTokens - cached)
        )
        let uncached = max(0, record.inputTokens - cached - cacheWrite)
        // OpenAI Priority Processing excludes long-context requests. If a historical setting says
        // priority but the prompt crossed that boundary, charge the published Standard long-context
        // rate instead of inventing a Priority long-context price.
        let hasLongContextPremium = pricing.appliesLongContextPremium
            && record.inputTokens > longContextThreshold
        let priorityMultiplier = record.serviceTier == .priority && !hasLongContextPremium
            ? pricing.priorityMultiplier
            : 1.0
        let inputMultiplier = hasLongContextPremium ? 2.0 : 1.0
        let outputMultiplier = hasLongContextPremium ? 1.5 : 1.0
        let inputCost = (
            Double(uncached) * pricing.inputPerMillion
                + Double(cached) * pricing.cachedInputPerMillion
                + Double(cacheWrite) * pricing.cacheWritePerMillion
        ) * inputMultiplier
        let outputCost = Double(record.outputTokens)
            * pricing.outputPerMillion
            * outputMultiplier
        return (inputCost + outputCost) * priorityMultiplier / 1_000_000
    }
}

enum TokenCostCalculator {
    static func snapshot(
        records: [TokenUsageRecord],
        now: Date,
        calendar: Calendar,
        subscriptionPeriod: DateInterval?,
        skippedSessionFileCount: Int = 0,
        dataScope: TokenCostDataScope = .local,
        syncMessage: String? = nil,
        sourceRecordCount: Int? = nil
    ) -> TokenCostSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)
            ?? todayStart

        return TokenCostSnapshot(
            today: summary(
                kind: .today,
                records: records.filter { $0.timestamp >= todayStart && $0.timestamp < tomorrow }
            ),
            yesterday: summary(
                kind: .yesterday,
                records: records.filter {
                    $0.timestamp >= yesterdayStart && $0.timestamp < todayStart
                }
            ),
            subscription: subscriptionPeriod.map { period in
                summary(
                    kind: .subscription,
                    records: records.filter {
                        $0.timestamp >= period.start && $0.timestamp < period.end
                    }
                )
            },
            lifetime: summary(
                kind: .lifetime,
                records: records
            ),
            subscriptionPeriod: subscriptionPeriod,
            skippedSessionFileCount: skippedSessionFileCount,
            dataScope: dataScope,
            syncMessage: syncMessage,
            sourceRecordCount: sourceRecordCount ?? records.count
        )
    }

    private static func summary(
        kind: TokenCostPeriodSummary.Kind,
        records: [TokenUsageRecord]
    ) -> TokenCostPeriodSummary {
        struct Accumulator {
            var input: Int64 = 0
            var cached: Int64 = 0
            var cacheWrite: Int64 = 0
            var output: Int64 = 0
            var total: Int64 = 0
            var cost: Double = 0
        }

        var byModel: [String: Accumulator] = [:]
        for record in records {
            guard let cost = TokenPricingCatalog.estimatedCost(for: record) else { continue }
            var value = byModel[record.model, default: Accumulator()]
            value.input += record.inputTokens
            value.cached += record.cachedInputTokens
            value.cacheWrite += record.cacheWriteInputTokens
            value.output += record.outputTokens
            value.total += record.totalTokens
            value.cost += cost
            byModel[record.model] = value
        }

        let models = byModel.map { model, value in
            TokenCostModelSummary(
                model: model,
                inputTokens: value.input,
                cachedInputTokens: value.cached,
                cacheWriteInputTokens: value.cacheWrite,
                outputTokens: value.output,
                totalTokens: value.total,
                estimatedCostUSD: value.cost
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens { return $0.model < $1.model }
            return $0.totalTokens > $1.totalTokens
        }
        return TokenCostPeriodSummary(kind: kind, models: models)
    }
}

enum TokenCostReconciler {
    static func reconcile(
        _ recorded: TokenCostSnapshot,
        with activity: TokenActivitySnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenCostSnapshot {
        let tokensByDay = activity.days.reduce(into: [Date: Int64]()) { result, day in
            guard let date = date(day.startDate, calendar: calendar) else { return }
            result[calendar.startOfDay(for: date), default: 0] += day.tokens
        }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let fallbackRate = unitCost(of: recorded.lifetime)

        return TokenCostSnapshot(
            today: reconcile(
                recorded.today,
                accountTokens: tokensByDay[today],
                fallbackRate: fallbackRate
            ),
            yesterday: reconcile(
                recorded.yesterday,
                accountTokens: yesterday.flatMap { tokensByDay[$0] },
                fallbackRate: fallbackRate
            ),
            subscription: recorded.subscription.map { summary in
                reconcile(
                    summary,
                    accountTokens: recorded.subscriptionPeriod.flatMap {
                        accountTokens(in: $0, tokensByDay: tokensByDay, calendar: calendar)
                    },
                    fallbackRate: fallbackRate
                )
            },
            lifetime: reconcile(
                recorded.lifetime,
                accountTokens: activity.lifetimeTokens,
                fallbackRate: fallbackRate
            ),
            subscriptionPeriod: recorded.subscriptionPeriod,
            skippedSessionFileCount: recorded.skippedSessionFileCount,
            dataScope: recorded.dataScope,
            syncMessage: recorded.syncMessage,
            sourceRecordCount: recorded.sourceRecordCount
        )
    }

    private static func reconcile(
        _ recorded: TokenCostPeriodSummary,
        accountTokens: Int64?,
        fallbackRate: Double?
    ) -> TokenCostPeriodSummary {
        guard let accountTokens else { return recorded }
        let missingTokens = max(0, accountTokens - recorded.recordedTokens)
        let rate = unitCost(of: recorded) ?? fallbackRate ?? 0
        let supplement = missingTokens > 0
            ? TokenCostSupplement(
                tokens: missingTokens,
                estimatedCostUSD: Double(missingTokens) * rate
            )
            : nil
        return TokenCostPeriodSummary(
            kind: recorded.kind,
            models: recorded.models,
            accountTokens: accountTokens,
            supplement: supplement
        )
    }

    private static func unitCost(of summary: TokenCostPeriodSummary) -> Double? {
        guard summary.recordedTokens > 0 else { return nil }
        return summary.recordedEstimatedCostUSD / Double(summary.recordedTokens)
    }

    private static func accountTokens(
        in period: DateInterval,
        tokensByDay: [Date: Int64],
        calendar: Calendar
    ) -> Int64? {
        let start = calendar.startOfDay(for: period.start)
        let end = calendar.startOfDay(for: period.end)
        let values: [Int64] = tokensByDay.compactMap { entry in
            guard entry.key >= start, entry.key < end else { return nil }
            return entry.value
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private static func date(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
              ) else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return date
    }
}

enum SubscriptionPeriodResolver {
    static func currentPeriod(
        activeStart: Date,
        activeUntil: Date,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        guard activeUntil > activeStart else { return nil }
        if now < activeUntil {
            return DateInterval(start: activeStart, end: activeUntil)
        }

        let yearly = activeUntil.timeIntervalSince(activeStart) > 300 * 24 * 60 * 60
        let component: Calendar.Component = yearly ? .year : .month
        var start = activeStart
        var end = activeUntil
        while end <= now {
            guard let nextStart = calendar.date(byAdding: component, value: 1, to: start),
                  let nextEnd = calendar.date(byAdding: component, value: 1, to: end),
                  nextEnd > end else {
                return nil
            }
            start = nextStart
            end = nextEnd
        }
        return DateInterval(start: start, end: end)
    }
}

enum TokenCostFormatter {
    static func amount(_ summary: TokenCostPeriodSummary) -> String {
        guard !summary.models.isEmpty || summary.supplement != nil else { return "$0.00" }
        return dollarAmount(summary.estimatedCostUSD)
    }

    static func amount(_ value: Double?) -> String {
        guard let value else { return "未计价" }
        return dollarAmount(value)
    }

    static func amount(_ model: TokenCostModelSummary) -> String {
        dollarAmount(model.estimatedCostUSD)
    }

    private static func dollarAmount(_ value: Double) -> String {
        String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
