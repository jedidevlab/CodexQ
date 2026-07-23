import Foundation

func readCurrentTokenCost() async throws -> TokenCostSnapshot {
    try await TokenCostReader.shared.read()
}

actor TokenCostReader {
    static let shared = TokenCostReader()

    enum ReaderError: LocalizedError {
        case sessionsUnavailable
        case subscriptionUnavailable

        var errorDescription: String? {
            switch self {
            case .sessionsUnavailable:
                return "未找到本机 Codex 会话记录"
            case .subscriptionUnavailable:
                return "无法读取订阅周期"
            }
        }
    }

    private struct CachedFile {
        let size: UInt64
        let modificationDate: Date
        let records: [TokenUsageRecord]
    }

    private let sessionsDirectory: URL
    private let authURL: URL
    private let fileManager: FileManager
    private var cache: [URL: CachedFile] = [:]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        sessionsDirectory = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        authURL = homeDirectory.appendingPathComponent(".codex/auth.json")
        self.fileManager = fileManager
    }

    func read(now: Date = Date()) throws -> TokenCostSnapshot {
        let files = try sessionFiles()
        guard !files.isEmpty else { throw ReaderError.sessionsUnavailable }

        var records: [TokenUsageRecord] = []
        var liveFiles = Set<URL>()
        for url in files {
            try Task.checkCancellation()
            liveFiles.insert(url)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
            if let cached = cache[url],
               cached.size == size,
               cached.modificationDate == modificationDate {
                records.append(contentsOf: cached.records)
                continue
            }
            let parsed = try TokenCostSessionParser.records(in: url)
            cache[url] = CachedFile(
                size: size,
                modificationDate: modificationDate,
                records: parsed
            )
            records.append(contentsOf: parsed)
        }
        cache = cache.filter { liveFiles.contains($0.key) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let subscriptionPeriod = try? subscriptionPeriod(now: now)
        let uniqueRecords = Array(Set(records)).sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.model != $1.model { return $0.model < $1.model }
            return $0.totalTokens < $1.totalTokens
        }
        return TokenCostCalculator.snapshot(
            records: uniqueRecords,
            now: now,
            calendar: calendar,
            subscriptionPeriod: subscriptionPeriod
        )
    }

    private func sessionFiles() throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ReaderError.sessionsUnavailable
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func subscriptionPeriod(now: Date) throws -> DateInterval {
        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(AuthFile.self, from: data)
        guard let payload = Self.jwtPayload(auth.tokens.idToken),
              let claims = try? JSONDecoder().decode(IDTokenPayload.self, from: payload),
              let startValue = claims.auth.subscriptionStart,
              let untilValue = claims.auth.subscriptionUntil else {
            throw ReaderError.subscriptionUnavailable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let start = formatter.date(from: startValue)
                ?? ISO8601DateFormatter().date(from: startValue),
              let until = formatter.date(from: untilValue)
                ?? ISO8601DateFormatter().date(from: untilValue) else {
            throw ReaderError.subscriptionUnavailable
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let period = SubscriptionPeriodResolver.currentPeriod(
            activeStart: start,
            activeUntil: until,
            now: now,
            calendar: calendar
        ) else {
            throw ReaderError.subscriptionUnavailable
        }
        return period
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

enum TokenCostSessionParser {
    static func records(in url: URL) throws -> [TokenUsageRecord] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var model: String?
        var serviceTier: TokenServiceTier = .standard
        var previousTotals: RawUsage?
        var replayGate: ChildReplayGate?
        var sawSessionMeta = false
        var result: [TokenUsageRecord] = []

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { continue }
            if type == "turn_context" {
                model = modelName(in: payload) ?? model
                continue
            }
            if type == "session_meta", !sawSessionMeta {
                sawSessionMeta = true
                if isChildSession(payload) {
                    if let timestamp = object["timestamp"] as? String,
                       let date = dateFormatter.date(from: timestamp)
                            ?? ISO8601DateFormatter().date(from: timestamp) {
                        replayGate = .untilStartedAt(date.timeIntervalSince1970.rounded(.down))
                    } else {
                        replayGate = .untilCurrentTaskStarted
                    }
                }
                continue
            }
            guard type == "event_msg", let eventType = payload["type"] as? String else { continue }
            if eventType == "thread_settings_applied" {
                serviceTier = tier(in: payload)
                continue
            }
            if eventType == "task_started" {
                if let gate = replayGate,
                   let startedAt = number(payload["started_at"]),
                   gate.isCleared(by: Double(startedAt), lineTimestamp: object["timestamp"] as? String, formatter: dateFormatter) {
                    replayGate = nil
                }
                continue
            }
            guard eventType == "token_count",
                  let timestamp = object["timestamp"] as? String,
                  let date = dateFormatter.date(from: timestamp)
                    ?? ISO8601DateFormatter().date(from: timestamp) else { continue }

            let info = payload["info"] as? [String: Any]
            let totals = (info?["total_token_usage"] as? [String: Any]).map(RawUsage.init)
            if replayGate != nil {
                if let totals { previousTotals = totals }
                continue
            }
            if let totals, let previousTotals, totals == previousTotals { continue }

            let usage: RawUsage
            if let last = (info?["last_token_usage"] as? [String: Any]).map(RawUsage.init) {
                usage = last
            } else if let totals {
                usage = totals.subtracting(previousTotals)
            } else {
                continue
            }
            if let totals { previousTotals = totals }
            guard usage.hasTokens else { continue }
            guard let resolvedModel = modelName(in: payload) ?? info.flatMap(modelName(in:)) ?? model else { continue }
            result.append(TokenUsageRecord(
                timestamp: date,
                model: resolvedModel,
                inputTokens: usage.input,
                cachedInputTokens: min(usage.cached, usage.input),
                cacheWriteInputTokens: min(usage.cacheWrite, max(0, usage.input - usage.cached)),
                outputTokens: usage.output,
                totalTokens: usage.total,
                serviceTier: serviceTier
            ))
        }
        return result
    }

    private struct RawUsage: Equatable {
        let input: Int64
        let cached: Int64
        let cacheWrite: Int64
        let output: Int64
        let total: Int64

        init(_ object: [String: Any]) {
            input = number(object["input_tokens"] ?? object["prompt_tokens"] ?? object["input"]) ?? 0
            cached = number(object["cached_input_tokens"] ?? object["cache_read_input_tokens"] ?? object["cached_tokens"]) ?? 0
            cacheWrite = number(object["cache_write_input_tokens"]) ?? 0
            output = number(object["output_tokens"] ?? object["completion_tokens"] ?? object["output"]) ?? 0
            let reportedTotal = number(object["total_tokens"]) ?? 0
            total = reportedTotal > 0 ? reportedTotal : input + output
        }

        var hasTokens: Bool { input > 0 || cached > 0 || cacheWrite > 0 || output > 0 }

        func subtracting(_ previous: RawUsage?) -> RawUsage {
            RawUsage(
                input: max(0, input - (previous?.input ?? 0)),
                cached: max(0, cached - (previous?.cached ?? 0)),
                cacheWrite: max(0, cacheWrite - (previous?.cacheWrite ?? 0)),
                output: max(0, output - (previous?.output ?? 0)),
                total: max(0, total - (previous?.total ?? 0))
            )
        }

        private init(input: Int64, cached: Int64, cacheWrite: Int64, output: Int64, total: Int64) {
            self.input = input
            self.cached = cached
            self.cacheWrite = cacheWrite
            self.output = output
            self.total = total
        }
    }

    private enum ChildReplayGate {
        case untilStartedAt(TimeInterval)
        case untilCurrentTaskStarted

        func isCleared(by startedAt: TimeInterval, lineTimestamp: String?, formatter: ISO8601DateFormatter) -> Bool {
            switch self {
            case .untilStartedAt(let creation): return startedAt >= creation
            case .untilCurrentTaskStarted:
                guard let lineTimestamp,
                      let lineDate = formatter.date(from: lineTimestamp) ?? ISO8601DateFormatter().date(from: lineTimestamp) else {
                    return false
                }
                return startedAt >= lineDate.timeIntervalSince1970.rounded(.down)
            }
        }
    }

    private static func tier(in payload: [String: Any]) -> TokenServiceTier {
        let settings = payload["thread_settings"] as? [String: Any]
        let value = (settings?["service_tier"] ?? payload["service_tier"]) as? String
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "priority", "fast": return .priority
        default: return .standard
        }
    }

    private static func modelName(in object: [String: Any]) -> String? {
        for value in [object["model"], object["model_name"], (object["metadata"] as? [String: Any])?["model"]] {
            if let name = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func isChildSession(_ payload: [String: Any]) -> Bool {
        nonNull(payload["forked_from_id"])
            || nonNull(payload["parent_thread_id"])
            || payload["thread_source"] as? String == "subagent"
            || nonNull((payload["source"] as? [String: Any])?["subagent"])
    }

    private static func nonNull(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: return false
        case let string as String: return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    private static func number(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

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
