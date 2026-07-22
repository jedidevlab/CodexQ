import Foundation

enum QuotaPeriod {
    case fiveHour
    case weekly
}

enum ResetDisplayMode: String {
    case relative
    case absolute

    var opposite: Self { self == .relative ? .absolute : .relative }
}

struct ResetTimeFormatter {
    private let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar

        timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")

        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
    }

    func string(for date: Date?, mode: ResetDisplayMode, now: Date = Date()) -> String {
        deadlineString(for: date, mode: mode, relativeSuffix: "后重置", absoluteSuffix: "重置", now: now)
            ?? "未知"
    }

    func oppositeString(for date: Date?, mode: ResetDisplayMode, now: Date = Date()) -> String {
        string(for: date, mode: mode.opposite, now: now)
    }

    func runOutString(for date: Date, mode: ResetDisplayMode, now: Date = Date()) -> String {
        deadlineString(for: date, mode: mode, relativeSuffix: "后用完", absoluteSuffix: "用完", now: now)
            ?? "即将用完"
    }

    private func deadlineString(
        for date: Date?,
        mode: ResetDisplayMode,
        relativeSuffix: String,
        absoluteSuffix: String,
        now: Date
    ) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 5 * 60 else {
            return absoluteSuffix == "重置" ? "即将重置" : "即将用完"
        }

        switch mode {
        case .relative:
            guard let duration = compactDuration(seconds) else { return nil }
            return "\(duration) \(relativeSuffix)"
        case .absolute:
            let dayDifference = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: date)
            ).day ?? 0
            let time = timeFormatter.string(from: date)
            if dayDifference <= 0 { return "今天 \(time) \(absoluteSuffix)" }
            if dayDifference == 1 { return "明天 \(time) \(absoluteSuffix)" }
            return "\(dateFormatter.string(from: date)) \(time) \(absoluteSuffix)"
        }
    }

    func compactDuration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let totalMinutes = max(1, Int((seconds / 60).rounded(.up)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
