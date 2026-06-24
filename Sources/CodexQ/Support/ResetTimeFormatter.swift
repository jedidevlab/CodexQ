import Foundation

enum QuotaPeriod {
    case fiveHour
    case weekly
}

struct ResetTimeFormatter {
    private let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        self.calendar = calendar

        timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
    }

    func string(for resetDate: Date?, period: QuotaPeriod, now: Date = Date()) -> String {
        guard let resetDate else { return "未知" }

        switch period {
        case .fiveHour:
            return timeFormatter.string(from: resetDate)
        case .weekly:
            let secondsUntilReset = resetDate.timeIntervalSince(now)
            if secondsUntilReset <= 24 * 60 * 60 {
                let wholeMinutes = max(0, Int(secondsUntilReset) / 60)
                return "\(wholeMinutes / 60)h\(wholeMinutes % 60)m"
            }
            return dateFormatter.string(from: resetDate)
        }
    }
}
