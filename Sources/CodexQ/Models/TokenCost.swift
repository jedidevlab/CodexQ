import Foundation

enum TokenServiceTier: Hashable, Sendable {
    case standard
    case priority
}

struct TokenUsageRecord: Equatable, Hashable, Sendable {
    let timestamp: Date
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let serviceTier: TokenServiceTier

    init(
        timestamp: Date,
        model: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteInputTokens: Int64,
        outputTokens: Int64,
        totalTokens: Int64,
        serviceTier: TokenServiceTier = .standard
    ) {
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

struct TokenCostSnapshot: Equatable, Sendable {
    let today: TokenCostPeriodSummary
    let yesterday: TokenCostPeriodSummary
    let subscription: TokenCostPeriodSummary?
    let lifetime: TokenCostPeriodSummary
    let subscriptionPeriod: DateInterval?
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

    var id: Kind { kind }
    var totalTokens: Int64 { models.reduce(0) { $0 + $1.totalTokens } }
    var estimatedCostUSD: Double {
        models.compactMap(\.estimatedCostUSD).reduce(0, +)
    }
    var hasUnpricedTokens: Bool {
        models.contains { $0.estimatedCostUSD == nil && $0.totalTokens > 0 }
    }
}

struct TokenCostModelSummary: Equatable, Sendable, Identifiable {
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let estimatedCostUSD: Double?

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
    static let effectiveDate = "2026-07-09"
    static let longContextThreshold: Int64 = 272_000

    static func pricing(for model: String) -> TokenPricing? {
        switch model.lowercased() {
        case "gpt-5.6", "gpt-5.6-sol":
            return .init(
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                cacheWritePerMillion: 6.25,
                outputPerMillion: 30,
                priorityMultiplier: 2,
                appliesLongContextPremium: true
            )
        case "gpt-5.6-terra":
            return .init(
                inputPerMillion: 2.5,
                cachedInputPerMillion: 0.25,
                cacheWritePerMillion: 3.125,
                outputPerMillion: 15,
                priorityMultiplier: 2,
                appliesLongContextPremium: true
            )
        case "gpt-5.6-luna":
            return .init(
                inputPerMillion: 1,
                cachedInputPerMillion: 0.1,
                cacheWritePerMillion: 1.25,
                outputPerMillion: 6,
                priorityMultiplier: 2,
                appliesLongContextPremium: true
            )
        case "gpt-5.5":
            return .init(
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                cacheWritePerMillion: 5,
                outputPerMillion: 30,
                priorityMultiplier: 2.5,
                appliesLongContextPremium: true
            )
        default:
            return nil
        }
    }

    static func estimatedCost(for record: TokenUsageRecord) -> Double? {
        guard let pricing = pricing(for: record.model) else { return nil }
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
        subscriptionPeriod: DateInterval?
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
                records: records.filter { TokenPricingCatalog.pricing(for: $0.model) != nil }
            ),
            subscriptionPeriod: subscriptionPeriod
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
            var isPriced = true
        }

        var byModel: [String: Accumulator] = [:]
        for record in records {
            var value = byModel[record.model, default: Accumulator()]
            value.input += record.inputTokens
            value.cached += record.cachedInputTokens
            value.cacheWrite += record.cacheWriteInputTokens
            value.output += record.outputTokens
            value.total += record.totalTokens
            if let cost = TokenPricingCatalog.estimatedCost(for: record) {
                value.cost += cost
            } else {
                value.isPriced = false
            }
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
                estimatedCostUSD: value.isPriced ? value.cost : nil
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens { return $0.model < $1.model }
            return $0.totalTokens > $1.totalTokens
        }
        return TokenCostPeriodSummary(kind: kind, models: models)
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
        guard !summary.models.isEmpty else { return "$0.00" }
        let formatted = dollarAmount(summary.estimatedCostUSD)
        return summary.hasUnpricedTokens ? formatted + "+" : formatted
    }

    static func amount(_ value: Double?) -> String {
        guard let value else { return "未计价" }
        return dollarAmount(value)
    }

    private static func dollarAmount(_ value: Double) -> String {
        String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
