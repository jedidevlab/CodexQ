import Foundation

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow
    let resetCredits: ResetCreditsSummary?

    var statusRemainingPercent: Double {
        fiveHour?.remainingPercent ?? weekly.remainingPercent
    }

    init(
        fiveHour: QuotaWindow?,
        weekly: QuotaWindow,
        resetCredits: ResetCreditsSummary? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCredits = resetCredits
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

    func projection(at now: Date = Date()) -> QuotaProjection? {
        guard let resetsAt,
              let durationMinutes,
              durationMinutes > 0 else {
            return nil
        }

        let duration = TimeInterval(durationMinutes * 60)
        let remainingTime = resetsAt.timeIntervalSince(now)
        let elapsedTime = duration - remainingTime
        guard remainingTime > 0, elapsedTime > 0 else { return nil }

        let expectedUsedPercent = min(100, max(0, elapsedTime / duration * 100))
        guard expectedUsedPercent >= 3 else { return nil }

        let expectedRemainingPercent = 100 - expectedUsedPercent
        let deltaPercent = usedPercent - expectedUsedPercent
        let rate = usedPercent / elapsedTime
        let etaSeconds = rate > 0 ? remainingPercent / rate : nil
        return QuotaProjection(
            reservePercent: max(0, -deltaPercent),
            expectedRemainingPercent: expectedRemainingPercent,
            deltaPercent: deltaPercent,
            etaSeconds: etaSeconds.flatMap { $0 < remainingTime ? $0 : nil }
        )
    }

}

struct QuotaProjection: Equatable, Sendable {
    let reservePercent: Double
    let expectedRemainingPercent: Double
    let deltaPercent: Double
    let etaSeconds: TimeInterval?

    var isOnTrack: Bool {
        abs(deltaPercent) <= 2
    }

    var isInDeficit: Bool {
        deltaPercent > 2
    }

    var displayPercent: Double {
        abs(deltaPercent)
    }
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
            resetCredits: rateLimitResetCredits?.summary
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
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    var quotaSnapshot: QuotaSnapshot? {
        let windows = [primary, secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.windowDurationMins == 300 }
            ?? primary.flatMap { $0.windowDurationMins == nil ? $0 : nil }
        let weekly = windows.first { $0.windowDurationMins == 10_080 }
            ?? secondary.flatMap { $0.windowDurationMins == nil ? $0 : nil }

        guard let weekly else { return nil }
        return QuotaSnapshot(
            fiveHour: fiveHour?.quotaWindow,
            weekly: weekly.quotaWindow
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
