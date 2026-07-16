import Foundation

enum QuotaPeriod {
    case fiveHour
    case weekly
}

struct ResetTimeFormatter {
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
    }

    func string(for resetDate: Date?, period: QuotaPeriod, now: Date = Date()) -> String {
        guard let resetDate else { return "未知" }
        guard resetDate > now else { return "已重置" }

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
