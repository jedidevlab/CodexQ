import Foundation

enum PaceFormatter {
    static func status(_ projection: QuotaProjection) -> String? {
        guard projection.isInDeficit else { return nil }
        let percent = Int(projection.displayPercent.rounded())
        if let etaSeconds = projection.etaSeconds {
            return "超额 \(percent)% · \(eta(etaSeconds))"
        }
        return "进度超额 \(percent)%"
    }

    static func eta(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        let hours = minutes / 60
        let remainderMinutes = minutes % 60

        if hours < 24 {
            return "\(hours)h\(remainderMinutes)m 后用完"
        }

        let days = hours / 24
        let remainderHours = hours % 24
        return "\(days)d\(remainderHours)h 后用完"
    }
}
