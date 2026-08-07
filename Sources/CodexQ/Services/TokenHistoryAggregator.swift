import Foundation

enum TokenHistoryAggregator {
    static func subscriptionCycles(
        anchor: SubscriptionAnchor,
        dataInterval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [SubscriptionCycle] {
        guard let current = SubscriptionPeriodResolver.currentPeriod(
            activeStart: anchor.start,
            activeUntil: anchor.end,
            now: now,
            calendar: calendar
        ) else {
            return []
        }

        let component: Calendar.Component = anchor.cadence == .year ? .year : .month
        let anchorIsCurrent = now >= anchor.start && now < anchor.end
        let currentIsInferred = !anchorIsCurrent
        var result = [SubscriptionCycle(
            interval: current,
            isCurrent: true,
            isInferred: currentIsInferred
        )]
        var interval = current

        while interval.start > dataInterval.start {
            guard let previousStart = calendar.date(
                byAdding: component,
                value: -1,
                to: interval.start
            ), let previousEnd = calendar.date(
                byAdding: component,
                value: -1,
                to: interval.end
            ), previousEnd > previousStart else {
                break
            }
            interval = DateInterval(start: previousStart, end: previousEnd)
            guard interval.end > dataInterval.start else { break }
            result.append(SubscriptionCycle(
                interval: interval,
                isCurrent: false,
                isInferred: true
            ))
        }
        return result
    }

    static func snapshot(
        records: [TokenUsageRecord],
        activity: TokenActivitySnapshot?,
        selection: TokenHistorySelection,
        subscriptionCycles: [SubscriptionCycle],
        dataScope: TokenCostDataScope,
        skippedSessionFileCount: Int,
        syncMessage: String?,
        now: Date,
        calendar: Calendar
    ) -> TokenHistorySnapshot? {
        guard let interval = selection.interval(
            calendar: calendar,
            subscriptionPeriods: subscriptionCycles
        ) else {
            return nil
        }
        let granularity = selection.granularity(interval: interval, calendar: calendar)
        let selectedRecords = records.filter {
            $0.timestamp >= interval.start && $0.timestamp < interval.end
        }
        let selectedRate = unitRate(records: selectedRecords)
        let fallbackRate = selectedRate ?? unitRate(records: records) ?? 0
        let activityByDay = activityTokensByDay(activity, calendar: calendar)
        let dayStarts = calendarDayStarts(in: interval, calendar: calendar)

        var recordsByDay: [Date: [TokenUsageRecord]] = [:]
        for record in selectedRecords {
            recordsByDay[calendar.startOfDay(for: record.timestamp), default: []].append(record)
        }

        let days = dayStarts.map { dayStart in
            let dayRecords = recordsByDay[dayStart, default: []]
            let deviceTokens = dayRecords.reduce(Int64(0)) { $0 + $1.totalTokens }
            var recordedCostUSD = 0.0
            var unpricedTokens: Int64 = 0
            for record in dayRecords {
                if let cost = TokenPricingCatalog.estimatedCost(for: record) {
                    recordedCostUSD += cost
                } else {
                    unpricedTokens += record.totalTokens
                }
            }
            let officialTokens = activityByDay[dayStart]
            let totalTokens = max(deviceTokens, officialTokens ?? deviceTokens)
            let supplementTokens = max(0, totalTokens - deviceTokens)
            return DailyValue(
                start: dayStart,
                deviceTokens: deviceTokens,
                totalTokens: totalTokens,
                recordedCostUSD: recordedCostUSD,
                supplementTokens: supplementTokens,
                supplementCostUSD: Double(supplementTokens) * fallbackRate,
                unpricedTokens: unpricedTokens,
                hasOfficialActivity: officialTokens != nil
            )
        }

        let buckets = aggregate(days: days, granularity: granularity, calendar: calendar)
        let deviceTokens = days.reduce(Int64(0)) { $0 + $1.deviceTokens }
        let totalTokens = days.reduce(Int64(0)) { $0 + $1.totalTokens }
        let recordedCostUSD = days.reduce(0.0) { $0 + $1.recordedCostUSD }
        let supplementTokens = days.reduce(Int64(0)) { $0 + $1.supplementTokens }
        let supplementCostUSD = days.reduce(0.0) { $0 + $1.supplementCostUSD }
        let unpricedTokens = days.reduce(Int64(0)) { $0 + $1.unpricedTokens }

        return TokenHistorySnapshot(
            selection: selection,
            interval: interval,
            granularity: granularity,
            buckets: buckets,
            summary: TokenHistorySummary(
                deviceTokens: deviceTokens,
                totalTokens: totalTokens,
                recordedCostUSD: recordedCostUSD,
                supplementTokens: supplementTokens,
                supplementCostUSD: supplementCostUSD,
                unpricedTokens: unpricedTokens,
                calendarDayCount: days.count
            ),
            models: modelSummaries(records: selectedRecords),
            coverage: TokenHistoryCoverage(
                hasOfficialActivity: activity != nil,
                activityDaysAvailable: days.filter(\.hasOfficialActivity).count,
                calendarDaysInRange: days.count,
                dataScope: dataScope,
                skippedSessionFileCount: skippedSessionFileCount,
                syncMessage: syncMessage
            ),
            subscriptionCycles: subscriptionCycles,
            warningMessage: nil
        )
    }

    private struct DailyValue {
        let start: Date
        let deviceTokens: Int64
        let totalTokens: Int64
        let recordedCostUSD: Double
        let supplementTokens: Int64
        let supplementCostUSD: Double
        let unpricedTokens: Int64
        let hasOfficialActivity: Bool
    }

    private struct BucketValue {
        var deviceTokens: Int64 = 0
        var totalTokens: Int64 = 0
        var recordedCostUSD = 0.0
        var supplementTokens: Int64 = 0
        var supplementCostUSD = 0.0
        var unpricedTokens: Int64 = 0
    }

    private struct ModelValue {
        var totalTokens: Int64 = 0
        var estimatedCostUSD = 0.0
        var hasPrice = false
    }

    private static func aggregate(
        days: [DailyValue],
        granularity: TokenHistoryGranularity,
        calendar: Calendar
    ) -> [TokenHistoryBucket] {
        var values: [Date: BucketValue] = [:]
        for day in days {
            let start = bucketStart(for: day.start, granularity: granularity, calendar: calendar)
            var value = values[start, default: BucketValue()]
            value.deviceTokens += day.deviceTokens
            value.totalTokens += day.totalTokens
            value.recordedCostUSD += day.recordedCostUSD
            value.supplementTokens += day.supplementTokens
            value.supplementCostUSD += day.supplementCostUSD
            value.unpricedTokens += day.unpricedTokens
            values[start] = value
        }
        return values.map { start, value in
            let end = calendar.date(
                byAdding: calendarComponent(for: granularity),
                value: 1,
                to: start
            ) ?? start
            return TokenHistoryBucket(
                interval: DateInterval(start: start, end: end),
                deviceTokens: value.deviceTokens,
                totalTokens: value.totalTokens,
                recordedCostUSD: value.recordedCostUSD,
                supplementTokens: value.supplementTokens,
                supplementCostUSD: value.supplementCostUSD,
                unpricedTokens: value.unpricedTokens
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func modelSummaries(
        records: [TokenUsageRecord]
    ) -> [TokenHistoryModelSummary] {
        var values: [String: ModelValue] = [:]
        for record in records {
            var value = values[record.model, default: ModelValue()]
            value.totalTokens += record.totalTokens
            if let cost = TokenPricingCatalog.estimatedCost(for: record) {
                value.estimatedCostUSD += cost
                value.hasPrice = true
            }
            values[record.model] = value
        }
        return values.map { model, value in
            TokenHistoryModelSummary(
                model: model,
                totalTokens: value.totalTokens,
                estimatedCostUSD: value.hasPrice ? value.estimatedCostUSD : nil
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens { return $0.model < $1.model }
            return $0.totalTokens > $1.totalTokens
        }
    }

    private static func unitRate(records: [TokenUsageRecord]) -> Double? {
        var tokens: Int64 = 0
        var cost = 0.0
        for record in records {
            guard let recordCost = TokenPricingCatalog.estimatedCost(for: record) else { continue }
            tokens += record.totalTokens
            cost += recordCost
        }
        guard tokens > 0 else { return nil }
        return cost / Double(tokens)
    }

    private static func activityTokensByDay(
        _ activity: TokenActivitySnapshot?,
        calendar: Calendar
    ) -> [Date: Int64] {
        guard let activity else { return [:] }
        var values: [Date: Int64] = [:]
        for day in activity.days {
            guard let date = strictDate(day.startDate, calendar: calendar) else { continue }
            values[calendar.startOfDay(for: date), default: 0] += day.tokens
        }
        return values
    }

    private static func strictDate(_ value: String, calendar: Calendar) -> Date? {
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

    private static func calendarDayStarts(
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        var result: [Date] = []
        var date = calendar.startOfDay(for: interval.start)
        while date < interval.end {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date),
                  next > date else {
                break
            }
            date = next
        }
        return result
    }

    private static func bucketStart(
        for date: Date,
        granularity: TokenHistoryGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date))
                ?? calendar.startOfDay(for: date)
        }
    }

    private static func calendarComponent(
        for granularity: TokenHistoryGranularity
    ) -> Calendar.Component {
        switch granularity {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }
}
