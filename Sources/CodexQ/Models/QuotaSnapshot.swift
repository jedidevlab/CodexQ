import Foundation

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow
    let resetCredits: ResetCreditsSummary?
    let planType: String?

    var statusRemainingPercent: Double {
        fiveHour?.remainingPercent ?? weekly.remainingPercent
    }

    init(
        fiveHour: QuotaWindow?,
        weekly: QuotaWindow,
        resetCredits: ResetCreditsSummary? = nil,
        planType: String? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCredits = resetCredits
        self.planType = planType
    }
}

enum PlanTypeFormatter {
    static func displayName(for planType: String?) -> String? {
        guard let planType, !planType.isEmpty else { return nil }
        switch planType.lowercased() {
        case "prolite": return "Pro 5x"
        case "pro": return "Pro 20x"
        case "plus": return "Plus"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return planType
        }
    }
}

struct ResetCreditsSummary: Codable, Equatable, Sendable {
    let availableCount: Int
    let credits: [ResetCredit]?

    var availableCredits: [ResetCredit] {
        credits?.filter { $0.status == "available" } ?? []
    }
}

struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let title: String?
    let expiresAt: Date?
}

struct QuotaWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    let durationMinutes: Int?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    func paceState(at now: Date = Date()) -> QuotaPaceState {
        if remainingPercent.rounded() <= 0 { return .spent }
        guard let resetsAt,
              let durationMinutes,
              durationMinutes > 0 else {
            return absoluteLevelState
        }

        let duration = TimeInterval(durationMinutes) * 60
        let remainingTime = resetsAt.timeIntervalSince(now)
        let elapsedTime = duration - remainingTime
        let minimumElapsed = max(60, duration * 0.01)
        guard remainingTime > 0, elapsedTime >= minimumElapsed else { return absoluteLevelState }

        let expectedUsedPercent = min(100, max(0, elapsedTime / duration * 100))
        let expectedRemainingPercent = 100 - expectedUsedPercent
        if usedPercent <= 0 { return .healthy(projectedUsedPercent: 0) }

        let projectedUsedPercent = usedPercent / elapsedTime * duration
        if projectedUsedPercent <= 90 {
            return .healthy(projectedUsedPercent: projectedUsedPercent)
        }
        guard usedPercent >= 5 else { return absoluteLevelState }
        if projectedUsedPercent <= 100 {
            let spare = Int((100 - projectedUsedPercent).rounded())
            guard spare >= 1 else {
                return .runningOut(
                    runOutAt: nil,
                    projectedUsedPercent: projectedUsedPercent,
                    markerPercent: expectedRemainingPercent
                )
            }
            return .closeToLimit(
                sparePercent: spare,
                projectedUsedPercent: projectedUsedPercent,
                markerPercent: expectedRemainingPercent
            )
        }

        let rate = usedPercent / elapsedTime
        let eta = rate > 0 ? remainingPercent / rate : nil
        let runOutAt = eta.flatMap { seconds in
            seconds > 0 && seconds < remainingTime ? now.addingTimeInterval(seconds) : nil
        }
        return .runningOut(
            runOutAt: runOutAt,
            projectedUsedPercent: projectedUsedPercent,
            markerPercent: expectedRemainingPercent
        )
    }

    private var absoluteLevelState: QuotaPaceState {
        let roundedUsed = min(100, max(0, usedPercent)).rounded()
        if roundedUsed >= 90 { return .level(.critical) }
        if roundedUsed >= 80 { return .level(.warning) }
        return .level(.normal)
    }
}

enum QuotaPaceSeverity: Equatable, Sendable { case normal, warning, critical }

enum QuotaPaceState: Equatable, Sendable {
    case spent
    case runningOut(runOutAt: Date?, projectedUsedPercent: Double, markerPercent: Double)
    case closeToLimit(sparePercent: Int, projectedUsedPercent: Double, markerPercent: Double)
    case healthy(projectedUsedPercent: Double)
    case level(QuotaPaceSeverity)

    var severity: QuotaPaceSeverity {
        switch self {
        case .spent, .runningOut: return .critical
        case .closeToLimit: return .warning
        case .healthy, .level(.normal): return .normal
        case .level(let severity): return severity
        }
    }

    var markerPercent: Double? {
        switch self {
        case .runningOut(_, _, let marker), .closeToLimit(_, _, let marker): return marker
        case .spent, .healthy, .level: return nil
        }
    }

    var sparePercent: Int? {
        if case .closeToLimit(let spare, _, _) = self { return spare }
        return nil
    }

    var isHealthy: Bool { if case .healthy = self { return true }; return false }
    var isRunningOut: Bool { if case .runningOut = self { return true }; return false }
    var isPlainLevel: Bool { if case .level = self { return true }; return false }
}

struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsResponse?

    var preferredSnapshot: RateLimitSnapshot {
        guard let codexLimits = rateLimitsByLimitId?["codex"],
              codexLimits.quotaSnapshot != nil else {
            return rateLimits
        }
        return codexLimits
    }

    var quotaSnapshot: QuotaSnapshot? {
        guard let limits = preferredSnapshot.quotaSnapshot else { return nil }
        return QuotaSnapshot(
            fiveHour: limits.fiveHour,
            weekly: limits.weekly,
            resetCredits: rateLimitResetCredits?.summary,
            planType: limits.planType
        )
    }
}

struct RateLimitResetCreditsResponse: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCreditResponse]?

    var summary: ResetCreditsSummary {
        ResetCreditsSummary(
            availableCount: availableCount,
            credits: credits?.map(\.resetCredit)
        )
    }
}

struct RateLimitResetCreditResponse: Decodable {
    let id: String
    let resetType: String
    let status: String
    let title: String?
    let expiresAt: TimeInterval?

    var resetCredit: ResetCredit {
        ResetCredit(
            id: id,
            resetType: resetType,
            status: status,
            title: title,
            expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

struct RateLimitResetCreditDetailsResponse: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCreditDetails]

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case credits
    }

    var summary: ResetCreditsSummary {
        ResetCreditsSummary(
            availableCount: availableCount,
            credits: credits.map(\.resetCredit)
        )
    }
}

struct RateLimitResetCreditDetails: Decodable {
    let id: String
    let resetType: String
    let status: String
    let title: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case title
        case expiresAt = "expires_at"
    }

    var resetCredit: ResetCredit {
        let expiryFormatter = ISO8601DateFormatter()
        expiryFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ResetCredit(
            id: id,
            resetType: resetType == "codex_rate_limits" ? "codexRateLimits" : resetType,
            status: status,
            title: title,
            expiresAt: expiresAt.flatMap {
                expiryFormatter.date(from: $0)
                    ?? ISO8601DateFormatter().date(from: $0)
            }
        )
    }
}

struct RateLimitSnapshot: Decodable {
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    init(
        planType: String? = nil,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?
    ) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }

    var quotaSnapshot: QuotaSnapshot? {
        let windows = [primary, secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.windowDurationMins == 300 }
            ?? primary.flatMap { $0.windowDurationMins == nil ? $0 : nil }
        let weekly = windows.first { $0.windowDurationMins == 10_080 }
            ?? secondary.flatMap { $0.windowDurationMins == nil ? $0 : nil }

        guard let weekly else { return nil }
        return QuotaSnapshot(
            fiveHour: fiveHour?.quotaWindow,
            weekly: weekly.quotaWindow,
            planType: planType
        )
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

private extension RateLimitWindow {
    var quotaWindow: QuotaWindow {
        QuotaWindow(
            usedPercent: usedPercent,
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
            durationMinutes: windowDurationMins
        )
    }
}
