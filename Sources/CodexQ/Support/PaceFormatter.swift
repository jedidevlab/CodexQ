import Foundation

struct PaceStatus: Equatable {
    let text: String?
    let showsFlame: Bool
}

enum PaceFormatter {
    static func status(
        _ state: QuotaPaceState,
        mode: ResetDisplayMode,
        formatter: ResetTimeFormatter,
        now: Date
    ) -> PaceStatus? {
        switch state {
        case .spent:
            return PaceStatus(text: "额度已用完", showsFlame: true)
        case .runningOut(let runOutAt, _, _):
            return PaceStatus(
                text: runOutAt.map { formatter.runOutString(for: $0, mode: mode, now: now) },
                showsFlame: true
            )
        case .closeToLimit(let sparePercent, _, _):
            return PaceStatus(text: "~\(sparePercent)% 余量", showsFlame: false)
        case .healthy, .level:
            return nil
        }
    }
}
