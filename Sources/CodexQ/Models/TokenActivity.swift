import Foundation

struct TokenActivitySnapshot: Decodable, Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64
    let days: [TokenActivityDay]

    init(
        peakDailyTokens: Int64,
        lifetimeTokens: Int64? = nil,
        days: [TokenActivityDay]
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case days = "dailyUsageBuckets"
    }

    private struct Summary: Decodable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = try container.decode(Summary.self, forKey: .summary)
        let decodedDays = try container.decodeIfPresent([TokenActivityDay].self, forKey: .days) ?? []
        lifetimeTokens = summary.lifetimeTokens
        peakDailyTokens = summary.peakDailyTokens ?? decodedDays.map(\.tokens).max() ?? 0
        days = decodedDays
    }
}

struct TokenActivityDay: Decodable, Equatable, Sendable {
    let startDate: String
    let tokens: Int64
}

struct TokenActivityCell: Equatable, Sendable {
    let date: Date
    let tokens: Int64?
}

enum TokenActivityPresentation {
    static func dailyCells(
        snapshot: TokenActivitySnapshot,
        now: Date,
        calendar: Calendar,
        weekCount: Int
    ) -> [TokenActivityCell] {
        guard weekCount > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let weekdayOffset = (
            calendar.component(.weekday, from: today) - calendar.firstWeekday + 7
        ) % 7
        guard let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -weekdayOffset,
            to: today
        ),
              let start = calendar.date(
                byAdding: .weekOfYear,
                value: -(weekCount - 1),
                to: currentWeekStart
              ) else {
            return []
        }
        return cells(
            from: start,
            through: today,
            recordedThrough: today,
            snapshot: snapshot,
            calendar: calendar
        )
    }

    static func hasRecordedTokens(in cells: [TokenActivityCell]) -> Bool {
        cells.contains { $0.tokens != nil }
    }

    static func latestRecordedDay(
        before date: Date,
        snapshot: TokenActivitySnapshot,
        calendar: Calendar
    ) -> TokenActivityCell? {
        let cutoff = calendar.startOfDay(for: date)
        return snapshot.days.compactMap { day -> TokenActivityCell? in
            guard let parsedDate = self.date(day.startDate, calendar: calendar) else {
                return nil
            }
            let normalizedDate = calendar.startOfDay(for: parsedDate)
            guard normalizedDate < cutoff else { return nil }
            return TokenActivityCell(date: normalizedDate, tokens: day.tokens)
        }
        .max { $0.date < $1.date }
    }

    private static func cells(
        from start: Date,
        through end: Date,
        recordedThrough: Date,
        snapshot: TokenActivitySnapshot,
        calendar: Calendar
    ) -> [TokenActivityCell] {
        let tokensByDate = tokenLookup(snapshot: snapshot, calendar: calendar)
        var result: [TokenActivityCell] = []
        var date = start
        while date <= end {
            result.append(TokenActivityCell(
                date: date,
                tokens: date <= recordedThrough ? tokensByDate[date] : nil
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private static func tokenLookup(
        snapshot: TokenActivitySnapshot,
        calendar: Calendar
    ) -> [Date: Int64] {
        var result: [Date: Int64] = [:]
        for day in snapshot.days {
            guard let date = date(day.startDate, calendar: calendar) else { continue }
            result[calendar.startOfDay(for: date)] = day.tokens
        }
        return result
    }

    private static func date(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return date
    }
}

enum TokenCountFormatter {
    static func compactNumber(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName))
    }

    static func string(_ tokens: Int64) -> String {
        compactNumber(tokens) + " tokens"
    }
}

enum TokenActivityDateLabel {
    static func string(for date: Date, now: Date, calendar: Calendar) -> String {
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨日"
        }
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else {
            return ""
        }
        return "\(month)/\(day)"
    }
}

enum TokenActivityLevel {
    static func level(tokens: Int64, peakTokens: Int64) -> Int {
        guard tokens > 0, peakTokens > 0 else { return 0 }
        let ratio = Double(tokens) / Double(peakTokens)
        return min(4, max(1, Int(ceil(ratio * 4))))
    }
}
