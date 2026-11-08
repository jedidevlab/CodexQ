import Foundation

struct AccountModelUsageDay: Codable, Equatable, Sendable {
    let date: Date // UTC day, as returned by the desktop usage API.
    let model: String
    let tokens: Int64

    init(date: Date, model: String, tokens: Int64) {
        self.date = date
        self.model = TokenModelName.canonical(model)
        self.tokens = tokens
    }
}

struct AccountModelUsageResult: Sendable {
    let days: [AccountModelUsageDay]
    var unquantifiedDays: [AccountModelUsagePresence] = []
    var warning: String? = nil
}

/// A model listed by the account API without any token counts. This is not usage of zero tokens.
struct AccountModelUsagePresence: Codable, Equatable, Sendable {
    let date: Date
    let model: String

    init(date: Date, model: String) {
        self.date = date
        self.model = TokenModelName.canonical(model)
    }
}

/// Uses the same token breakdown endpoints and fields as the installed desktop app.
/// Credit/relative-usage responses are deliberately NOT converted to tokens.
actor AccountModelUsageReader {
    static let shared = AccountModelUsageReader(cacheURL: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexQ/account-model-usage.json"))
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    enum ReadError: LocalizedError, Equatable {
        case unavailable
        case signInRequired
        case tokenBreakdownUnavailable
        case invalidResponse
        case accountChanged
        case network(Int)
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "账号模型明细暂不可用，当前仅显示设备记录"
            case .signInRequired: return "账号模型明细认证失败，请检查 ChatGPT 登录状态"
            case .tokenBreakdownUnavailable: return "账号接口未提供按模型的 Token 数，桌面版对话可能未纳入模型统计"
            case .invalidResponse: return "账号模型明细格式无法识别，当前仅显示设备记录"
            case .accountChanged: return "账号已切换，请重新刷新模型明细"
            case .network(let code): return "账号模型明细连接失败（网络错误 \(code)），当前仅显示设备记录"
            case .httpStatus(let status): return "账号模型明细请求失败（HTTP \(status)），当前仅显示设备记录"
            }
        }
    }

    private struct CachedResult: Codable {
        let fingerprint: String
        let refreshedAt: Date
        let days: [AccountModelUsageDay]
        var unquantifiedDays: [AccountModelUsagePresence]?
    }

    private let authData: @Sendable () throws -> Data
    private let transport: Transport
    private let cacheURL: URL?
    private var cache: CachedResult?

    init(
        cacheURL: URL? = nil,
        authData: @escaping @Sendable () throws -> Data = {
            try Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json"))
        },
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ReadError.invalidResponse }
            return (data, response)
        }
    ) {
        self.authData = authData
        self.transport = transport
        self.cacheURL = cacheURL
    }

    func read(now: Date = Date()) async throws -> AccountModelUsageResult {
        let auth = try authData()
        guard let fingerprint = SnapshotCache.accountFingerprint(authData: auth) else {
            cache = nil
            throw ReadError.signInRequired
        }
        if cache?.fingerprint != fingerprint { cache = nil }
        if cache == nil, let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode(CachedResult.self, from: data),
           saved.fingerprint == fingerprint,
           saved.days.allSatisfy({ $0.tokens >= 0 && !$0.model.isEmpty }) {
            cache = saved
        }
        if let cache, now >= cache.refreshedAt, now.timeIntervalSince(cache.refreshedAt) < 60 {
            return Self.result(from: cache)
        }

        do {
            let fetched = try await fetch(auth: auth, now: now)
            try Task.checkCancellation()
            guard SnapshotCache.accountFingerprint(authData: try authData()) == fingerprint else {
                cache = nil
                throw ReadError.accountChanged
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now))!
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            guard fetched.days.allSatisfy({ $0.date >= start && $0.date < end }),
                  fetched.unquantifiedDays.allSatisfy({ $0.date >= start && $0.date < end }) else {
                throw ReadError.invalidResponse
            }
            // Refresh the queried window, retaining older saved history beyond API retention.
            let days = (cache?.days.filter { !fetched.unquantifiedDays.isEmpty || $0.date < start } ?? []) + fetched.days
            let presence = (cache?.unquantifiedDays?.filter { $0.date < start } ?? []) + fetched.unquantifiedDays
            let saved = CachedResult(fingerprint: fingerprint, refreshedAt: now, days: days, unquantifiedDays: presence)
            cache = saved
            var warning: String?
            if let cacheURL {
                do {
                    try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(saved).write(to: cacheURL, options: .atomic)
                } catch {
                    warning = "账号模型明细缓存无法更新，重启后可能缺少历史数据"
                }
            }
            return Self.result(from: saved, warning: warning)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard SnapshotCache.accountFingerprint(authData: try authData()) == fingerprint else {
                cache = nil
                throw ReadError.accountChanged
            }
            // Never carry one account's usage into another account's display.
            if let cache, cache.fingerprint == fingerprint {
                return Self.result(from: cache, warning: "账号模型明细更新失败，显示上次数据")
            }
            throw (error as? ReadError) ?? ReadError.unavailable
        }
    }

    private static func result(from cache: CachedResult, warning: String? = nil) -> AccountModelUsageResult {
        let presence = cache.unquantifiedDays ?? []
        let limitation = presence.isEmpty ? nil : "账号接口列出了模型，但仅提供额度百分比或积分，未提供 Token 明细"
        let warnings = [warning, limitation].compactMap { $0 }
        return AccountModelUsageResult(days: cache.days, unquantifiedDays: presence,
                                       warning: warnings.isEmpty ? nil : warnings.joined(separator: "；"))
    }

    private func fetch(auth: Data, now: Date) async throws -> AccountModelUsageResult {
        for isWorkspace in [true, false] {
            let request = try Self.request(authData: auth, now: now, isWorkspace: isWorkspace)
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport(request)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw CancellationError() }
                if let error = error as? URLError { throw ReadError.network(error.code.rawValue) }
                throw ReadError.unavailable
            }
            try Task.checkCancellation()
            if response.statusCode == 401 { throw ReadError.signInRequired }
            if [403, 404].contains(response.statusCode) { continue }
            if isWorkspace, response.statusCode == 400,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               body["detail"] as? String == "No active workspace found for the current account." {
                continue
            }
            guard response.statusCode == 200 else { throw ReadError.httpStatus(response.statusCode) }
            do {
                return AccountModelUsageResult(days: try AccountModelUsageParser.parse(data))
            } catch ReadError.tokenBreakdownUnavailable {
                let presence = try AccountModelUsageParser.parsePresence(data)
                if !presence.isEmpty { return AccountModelUsageResult(days: [], unquantifiedDays: presence) }
                continue
            }
        }
        throw ReadError.tokenBreakdownUnavailable
    }

    static func request(authData: Data, now: Date, isWorkspace: Bool) throws -> URLRequest {
        // Reuse the existing desktop credential handling, without persisting credentials.
        var request = try ResetCreditDetailsClient.makeRequest(authData: authData)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(byAdding: .day, value: -89, to: now)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        let endpoint = isWorkspace
            ? "daily-workspace-user-token-usage-breakdown"
            : "daily-token-usage-breakdown"
        var components = URLComponents(string: "https://chatgpt.com/backend-api/wham/usage/\(endpoint)")!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: formatter.string(from: start)),
            URLQueryItem(name: "end_date", value: formatter.string(from: now)),
            URLQueryItem(name: "group_by", value: "day")
        ]
        if isWorkspace {
            components.queryItems! += [
                URLQueryItem(name: "breakdown_by", value: "model"),
                URLQueryItem(name: "modes", value: "codex"),
                URLQueryItem(name: "modes", value: "work")
            ]
        }
        request.url = components.url
        request.setValue("1", forHTTPHeaderField: "x-openai-codex-usage-categories")
        request.setValue("codexq/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        return request
    }
}

enum AccountModelUsageParser {
    private struct Response: Decodable {
        let data: [Day]
        let units: String?
    }

    private struct Day: Decodable {
        let date: String
        let groups: [Group]?
        let models: [Group]?
    }

    private struct Group: Decodable {
        struct Dimensions: Decodable { let model: String? }
        let model: String?
        let dimensions: Dimensions?
        let is_other: Bool?
        let uncached_text_input_tokens: Int64?
        let cached_text_input_tokens: Int64?
        let text_output_tokens: Int64?
        let text_total_tokens: Int64?
        let credits: Double?
    }

    static func parsePresence(_ data: Data) throws -> [AccountModelUsagePresence] {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountModelUsageReader.ReadError.invalidResponse }
        guard let units = response.units, ["percent", "credits"].contains(units) else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return try response.data.flatMap { day in
            guard let date = formatter.date(from: day.date), formatter.string(from: date) == day.date,
                  let groups = day.groups ?? day.models else {
                throw AccountModelUsageReader.ReadError.invalidResponse
            }
            return try groups.map { group in
                let model = (group.model ?? group.dimensions?.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty, model.count <= 200 else { throw AccountModelUsageReader.ReadError.invalidResponse }
                return AccountModelUsagePresence(date: date, model: model)
            }
        }
    }

    static func parse(_ data: Data) throws -> [AccountModelUsageDay] {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountModelUsageReader.ReadError.invalidResponse }
        if let units = response.units, units != "tokens" {
            throw AccountModelUsageReader.ReadError.tokenBreakdownUnavailable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        var result: [AccountModelUsageDay] = []
        for day in response.data {
            guard let date = formatter.date(from: day.date), formatter.string(from: date) == day.date,
                  let groups = day.groups ?? day.models else {
                throw AccountModelUsageReader.ReadError.invalidResponse
            }
            for group in groups {
                let model = (group.model ?? group.dimensions?.model ?? (group.is_other == true ? "other" : ""))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty, model.count <= 200 else {
                    throw AccountModelUsageReader.ReadError.invalidResponse
                }
                let components = [group.uncached_text_input_tokens, group.cached_text_input_tokens,
                                  group.text_output_tokens].compactMap { $0 }
                guard components.allSatisfy({ $0 >= 0 }) else {
                    throw AccountModelUsageReader.ReadError.invalidResponse
                }
                let tokens: Int64
                if let total = group.text_total_tokens, total < 0 {
                    throw AccountModelUsageReader.ReadError.invalidResponse
                }
                if let total = group.text_total_tokens, total > 0 {
                    tokens = total
                } else if !components.isEmpty {
                    var sum: Int64 = 0
                    for component in components {
                        let (next, overflow) = sum.addingReportingOverflow(component)
                        guard !overflow else { throw AccountModelUsageReader.ReadError.invalidResponse }
                        sum = next
                    }
                    tokens = sum
                } else if group.text_total_tokens == 0 {
                    tokens = 0
                } else if response.units == "tokens", let count = group.credits,
                          count.isFinite, count >= 0, count < Double(Int64.max), count.rounded() == count {
                    // The personal endpoint uses the `credits` field for the declared unit.
                    tokens = Int64(count)
                } else {
                    throw AccountModelUsageReader.ReadError.tokenBreakdownUnavailable
                }
                guard tokens >= 0 else { throw AccountModelUsageReader.ReadError.invalidResponse }
                if tokens > 0 { result.append(AccountModelUsageDay(date: date, model: model, tokens: tokens)) }
            }
        }
        return result
    }
}

enum AccountModelUsageMerger {
    /// Top up each UTC day/model to the account total; never add overlapping usage twice.
    /// Aggregate top-ups stay out of device ledgers and per-request API cost estimates.
    static func merge(_ accountDays: [AccountModelUsageDay], into records: [TokenUsageRecord]) throws -> [TokenUsageRecord] {
        struct Key: Hashable { let day: Date; let model: String }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var device: [Key: Int64] = [:]
        var account: [Key: Int64] = [:]
        for record in records {
            let key = Key(day: calendar.startOfDay(for: record.timestamp), model: record.model)
            device[key] = try adding(record.totalTokens, to: device[key, default: 0])
        }
        for day in accountDays {
            let key = Key(day: calendar.startOfDay(for: day.date), model: day.model)
            account[key] = try adding(day.tokens, to: account[key, default: 0])
        }
        return records + account.compactMap { key, total in
            let missing = max(0, total - device[key, default: 0])
            guard missing > 0 else { return nil }
            return TokenUsageRecord(
                timestamp: key.day, model: key.model, inputTokens: 0, cachedInputTokens: 0,
                cacheWriteInputTokens: 0, outputTokens: 0, totalTokens: missing,
                isAccountAggregate: true
            )
        }
    }

    private static func adding(_ count: Int64, to sum: Int64) throws -> Int64 {
        let (value, overflow) = sum.addingReportingOverflow(count)
        guard count >= 0, !overflow else { throw AccountModelUsageReader.ReadError.invalidResponse }
        return value
    }
}
