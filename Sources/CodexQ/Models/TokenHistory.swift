import Foundation

enum TokenHistoryRangeMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case month
    case year
    case subscription
    case cumulative
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .day: return "日"
        case .month: return "月"
        case .year: return "年"
        case .subscription: return "订阅周期"
        case .cumulative: return "累计"
        case .custom: return "自定义"
        }
    }
}

enum TokenHistoryGranularity: String, Hashable, Sendable {
    case day
    case month
    case year
}

struct SubscriptionAnchor: Hashable, Sendable {
    enum Cadence: Hashable, Sendable {
        case month
        case year
    }

    let start: Date
    let end: Date
    let cadence: Cadence
}

struct SubscriptionCycle: Identifiable, Hashable, Sendable {
    let interval: DateInterval
    let isCurrent: Bool
    let isInferred: Bool

    var id: Date { interval.start }
}

enum TokenHistorySelection: Hashable, Sendable {
    case day(Date)
    case month(year: Int, month: Int)
    case year(Int)
    case subscription(DateInterval)
    case cumulative
    case custom(start: Date, endInclusive: Date)

    func interval(
        calendar: Calendar,
        subscriptionPeriods: [SubscriptionCycle]
    ) -> DateInterval? {
        switch self {
        case .day(let date):
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month(let year, let month):
            guard let start = calendar.date(from: DateComponents(year: year, month: month)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .year(let year):
            guard let start = calendar.date(from: DateComponents(year: year)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .subscription(let requested):
            return subscriptionPeriods.first { $0.interval == requested }?.interval
        case .cumulative:
            return nil
        case .custom(let first, let last):
            let start = calendar.startOfDay(for: min(first, last))
            let finalDay = calendar.startOfDay(for: max(first, last))
            return calendar.date(byAdding: .day, value: 1, to: finalDay).map {
                DateInterval(start: start, end: $0)
            }
        }
    }

    func granularity(
        interval: DateInterval,
        calendar: Calendar
    ) -> TokenHistoryGranularity {
        switch self {
        case .day, .month, .subscription:
            return .day
        case .year:
            return .month
        case .cumulative, .custom:
            let days = calendar.dateComponents(
                [.day],
                from: interval.start,
                to: interval.end
            ).day ?? 0
            if days <= 92 { return .day }
            if days <= 366 * 3 { return .month }
            return .year
        }
    }
}

struct TokenHistoryBucket: Identifiable, Equatable, Sendable {
    let interval: DateInterval
    let deviceTokens: Int64
    let totalTokens: Int64
    let recordedCostUSD: Double
    let supplementTokens: Int64
    let supplementCostUSD: Double
    let unpricedTokens: Int64

    var id: Date { interval.start }
    var start: Date { interval.start }
    var estimatedCostUSD: Double { recordedCostUSD + supplementCostUSD }
}

struct TokenHistoryModelSummary: Identifiable, Equatable, Sendable {
    let model: String
    let totalTokens: Int64
    let estimatedCostUSD: Double?

    var id: String { model }
}

struct TokenHistorySummary: Equatable, Sendable {
    let deviceTokens: Int64
    let totalTokens: Int64
    let recordedCostUSD: Double
    let supplementTokens: Int64
    let supplementCostUSD: Double
    let unpricedTokens: Int64
    let calendarDayCount: Int

    var estimatedCostUSD: Double { recordedCostUSD + supplementCostUSD }
    var averageDailyTokens: Double {
        calendarDayCount > 0 ? Double(totalTokens) / Double(calendarDayCount) : 0
    }
    var averageDailyCostUSD: Double {
        calendarDayCount > 0 ? estimatedCostUSD / Double(calendarDayCount) : 0
    }
}

struct TokenHistoryCoverage: Equatable, Sendable {
    let hasOfficialActivity: Bool
    let activityDaysAvailable: Int
    let calendarDaysInRange: Int
    let dataScope: TokenCostDataScope
    let skippedSessionFileCount: Int
    let syncMessage: String?
}

struct TokenHistorySnapshot: Equatable, Sendable {
    let selection: TokenHistorySelection
    let interval: DateInterval
    let granularity: TokenHistoryGranularity
    let buckets: [TokenHistoryBucket]
    let summary: TokenHistorySummary
    let models: [TokenHistoryModelSummary]
    let coverage: TokenHistoryCoverage
    let subscriptionCycles: [SubscriptionCycle]
    let warningMessage: String?
}
