import Foundation

struct TokenActivitySnapshot: Decodable, Equatable, Sendable {
    let peakDailyTokens: Int64
    let days: [TokenActivityDay]

    init(peakDailyTokens: Int64, days: [TokenActivityDay]) {
        self.peakDailyTokens = peakDailyTokens
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case days = "dailyUsageBuckets"
    }

    private struct Summary: Decodable {
        let peakDailyTokens: Int64
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peakDailyTokens = try container.decode(Summary.self, forKey: .summary).peakDailyTokens
        days = try container.decode([TokenActivityDay].self, forKey: .days)
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

struct TokenActivityWeek: Equatable, Sendable {
    let cells: [TokenActivityCell]
}

enum TokenActivityPresentation {
    static func dailyCells(
        snapshot: TokenActivitySnapshot,
        now: Date,
        calendar: Calendar
    ) -> [TokenActivityCell] {
        let end = calendar.startOfDay(for: now)
        guard let lowerMonth = calendar.date(byAdding: .month, value: -2, to: end),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: lowerMonth)) else {
            return []
        }
        return cells(from: start, through: end, snapshot: snapshot, calendar: calendar)
    }

    static func weeklyRows(
        snapshot: TokenActivitySnapshot,
        now: Date,
        calendar: Calendar
    ) -> [TokenActivityWeek] {
        let statisticalEnd = calendar.startOfDay(for: now)
        guard let lowerMonth = calendar.date(byAdding: .month, value: -1, to: statisticalEnd),
              let statisticalStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: lowerMonth)
              ),
              let paddedStart = calendar.date(
                byAdding: .day,
                value: -mondayOffset(for: statisticalStart, calendar: calendar),
                to: statisticalStart
              ),
              let paddedEnd = calendar.date(
                byAdding: .day,
                value: sundayOffset(for: statisticalEnd, calendar: calendar),
                to: statisticalEnd
              ) else {
            return []
        }

        let tokensByDate = tokenLookup(snapshot: snapshot, calendar: calendar)
        var rows: [TokenActivityWeek] = []
        var weekStart = paddedStart
        while weekStart <= paddedEnd {
            let week = (0..<7).compactMap { offset -> TokenActivityCell? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                    return nil
                }
                let inRange = date >= statisticalStart && date <= statisticalEnd
                return TokenActivityCell(date: date, tokens: inRange ? tokensByDate[date] : nil)
            }
            rows.append(TokenActivityWeek(cells: week))
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = nextWeek
        }
        return rows
    }

    private static func cells(
        from start: Date,
        through end: Date,
        snapshot: TokenActivitySnapshot,
        calendar: Calendar
    ) -> [TokenActivityCell] {
        let tokensByDate = tokenLookup(snapshot: snapshot, calendar: calendar)
        var result: [TokenActivityCell] = []
        var date = start
        while date <= end {
            result.append(TokenActivityCell(date: date, tokens: tokensByDate[date]))
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

    private static func mondayOffset(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private static func sundayOffset(for date: Date, calendar: Calendar) -> Int {
        (8 - calendar.component(.weekday, from: date)) % 7
    }
}

enum TokenCountFormatter {
    static func string(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName)) + " tokens"
    }
}

enum TokenActivityLevel {
    static func level(tokens: Int64, peakTokens: Int64) -> Int {
        guard tokens > 0, peakTokens > 0 else { return 0 }
        let ratio = Double(tokens) / Double(peakTokens)
        return min(4, max(1, Int(ceil(ratio * 4))))
    }
}
