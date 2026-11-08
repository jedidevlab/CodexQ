import Foundation

struct TokenHistoryReader: Sendable {
    let readActivity: @Sendable () async throws -> TokenActivitySnapshot
    let readSubscriptionAnchor: @Sendable () async -> SubscriptionAnchor?

    init(
        readActivity: @escaping @Sendable () async throws -> TokenActivitySnapshot = {
            try await AppServerClient().readTokenActivity()
        },
        readSubscriptionAnchor: @escaping @Sendable () async -> SubscriptionAnchor? = {
            SubscriptionAnchorReader.read()
        }
    ) {
        self.readActivity = readActivity
        self.readSubscriptionAnchor = readSubscriptionAnchor
    }

    func read(
        selection: TokenHistorySelection,
        now: Date,
        calendar: Calendar
    ) async throws -> TokenHistorySnapshot {
        async let activityResult = readActivity()
        async let anchorResult = readSubscriptionAnchor()
        let activity = try await activityResult
        let anchor = await anchorResult
        try Task.checkCancellation()

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cycles = anchor.map {
            TokenHistoryAggregator.subscriptionCycles(
                anchor: $0,
                dataInterval: Self.dataInterval(activity: activity, now: now, calendar: calendar),
                now: now,
                calendar: utcCalendar
            )
        } ?? []

        guard let snapshot = TokenHistoryAggregator.snapshot(
            records: [],
            activity: activity,
            selection: selection,
            subscriptionCycles: cycles,
            dataScope: .account,
            skippedSessionFileCount: 0,
            syncMessage: nil,
            now: now,
            calendar: calendar
        ) else {
            throw ReaderError.invalidSelection
        }
        return snapshot
    }

    enum ReaderError: LocalizedError {
        case invalidSelection

        var errorDescription: String? {
            "无法解析所选历史时间范围"
        }
    }

    private static func dataInterval(
        activity: TokenActivitySnapshot,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let dates = activity.days.compactMap { day -> Date? in
            let parts = day.startDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(
                year: parts[0],
                month: parts[1],
                day: parts[2]
            ))
        }
        guard let first = dates.min(), let last = dates.max() else {
            return DateInterval(start: now, duration: 1)
        }
        let end = calendar.date(byAdding: .day, value: 1, to: last)
            ?? last.addingTimeInterval(86_400)
        return DateInterval(start: first, end: end)
    }
}

private enum SubscriptionAnchorReader {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let idToken: String

            enum CodingKeys: String, CodingKey {
                case idToken = "id_token"
            }
        }

        let tokens: Tokens
    }

    private struct IDTokenPayload: Decodable {
        struct Claims: Decodable {
            let subscriptionStart: String?
            let subscriptionUntil: String?

            enum CodingKeys: String, CodingKey {
                case subscriptionStart = "chatgpt_subscription_active_start"
                case subscriptionUntil = "chatgpt_subscription_active_until"
            }
        }

        let auth: Claims

        enum CodingKeys: String, CodingKey {
            case auth = "https://api.openai.com/auth"
        }
    }

    static func read() -> SubscriptionAnchor? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let payload = jwtPayload(auth.tokens.idToken),
              let claims = try? JSONDecoder().decode(IDTokenPayload.self, from: payload),
              let startValue = claims.auth.subscriptionStart,
              let endValue = claims.auth.subscriptionUntil,
              let start = isoDate(startValue),
              let end = isoDate(endValue),
              end > start else {
            return nil
        }
        let cadence: SubscriptionAnchor.Cadence = end.timeIntervalSince(start) > 300 * 86_400
            ? .year
            : .month
        return SubscriptionAnchor(start: start, end: end, cadence: cadence)
    }

    private static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func jwtPayload(_ token: String) -> Data? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        var value = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }
}
