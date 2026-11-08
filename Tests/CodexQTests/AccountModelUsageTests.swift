import Foundation
import Testing
@testable import CodexQ

struct AccountModelUsageTests {
    private let grouped = #"{"data":[{"date":"2026-10-22","groups":[{"dimensions":{"model":"gpt-6.1-sol-wm"},"uncached_text_input_tokens":100,"cached_text_input_tokens":40,"text_output_tokens":10}]}]}"#

    @Test("读取新版桌面 Work 模型明细及旧版 models 结构")
    func parsesBothTokenSchemas() throws {
        let days = try AccountModelUsageParser.parse(Data(grouped.utf8))
        #expect(days.map(\.model) == ["gpt-6.1-sol"])
        #expect(days.map(\.tokens) == [150])
        #expect(days.first?.date == date("2026-10-22T00:00:00Z"))
        let legacy = #"{"data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","text_total_tokens":200}]}]}"#
        #expect(try AccountModelUsageParser.parse(Data(legacy.utf8)).first?.tokens == 200)
        let personal = #"{"units":"tokens","data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","credits":300}]}]}"#
        #expect(try AccountModelUsageParser.parse(Data(personal.utf8)).first?.tokens == 300)
    }

    @Test("积分、相对用量、畸形日期及负数不能变成 Token")
    func rejectsNonTokenOrInvalidData() {
        for fixture in [
            #"{"units":"credits","data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","credits":100}]}]}"#,
            #"{"units":"relative","data":[]}"#,
            #"{"data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","credits":100}]}]}"#,
            #"{"data":[{"date":"2026-02-30","models":[]}]}"#,
            #"{"data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","text_total_tokens":-1}]}]}"#,
            #"{"data":[{"date":"2026-10-22","models":[{"model":"gpt-6.1-sol","uncached_text_input_tokens":9223372036854775807,"text_output_tokens":1}]}]}"#
        ] {
            #expect(throws: (any Error).self) { try AccountModelUsageParser.parse(Data(fixture.utf8)) }
        }
    }

    @Test("按 UTC 日与模型只补差额，保留较新的设备记录且重复合并不重复计数")
    func mergesWithoutDoubleCounting() throws {
        let local = [record(model: "gpt-6.1-sol", tokens: 100), record(model: "gpt-6-sol", tokens: 300)]
        let account = [
            day(model: "gpt-6.1-sol", tokens: 120), day(model: "gpt-6.1-sol", tokens: 80),
            day(model: "gpt-6-sol", tokens: 200), day(model: "gpt-6.1-sol-wm", tokens: 50)
        ]
        let merged = try AccountModelUsageMerger.merge(account, into: local)
        #expect(merged.reduce(0) { $0 + $1.totalTokens } == 550)
        #expect(merged.filter(\.isAccountAggregate).map(\.totalTokens).sorted() == [150])
        #expect(try AccountModelUsageMerger.merge(account, into: merged) == merged)
        #expect(merged.filter(\.isAccountAggregate).allSatisfy { $0.eventID == nil })
        #expect(merged.filter(\.isAccountAggregate).allSatisfy { TokenPricingCatalog.estimatedCost(for: $0) == nil })
        #expect(throws: AccountModelUsageReader.ReadError.invalidResponse) {
            try AccountModelUsageMerger.merge([
                day(model: "gpt-6.1-sol", tokens: Int64.max), day(model: "gpt-6.1-sol", tokens: 1)
            ], into: [])
        }
    }

    @Test("账号补入的 GPT-6.1 同时进入成本面板和历史模型分布，缺少请求信息时不伪造零成本")
    func includesAccountModelInBothSummaries() throws {
        let records = try AccountModelUsageMerger.merge([day(model: "gpt-6.1-sol", tokens: 150)], into: [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-10-23T01:00:00Z")
        let cost = TokenCostCalculator.snapshot(records: records, now: now, calendar: calendar, subscriptionPeriod: nil)
        #expect(cost.yesterday.totalTokens == 150)
        #expect(cost.yesterday.models.first?.model == "gpt-6.1-sol")
        #expect(cost.yesterday.unpricedTokens == 150)
        #expect(TokenCostFormatter.amount(cost.yesterday) == "未计价")
        #expect(TokenCostFormatter.amount(try #require(cost.yesterday.models.first)) == "未计价")
        let history = try #require(TokenHistoryAggregator.snapshot(
            records: records, activity: nil, selection: .cumulative, subscriptionCycles: [],
            dataScope: .account, skippedSessionFileCount: 0, syncMessage: nil,
            now: now, calendar: calendar
        ))
        #expect(history.summary.totalTokens == 150)
        #expect(history.summary.unpricedTokens == 150)
        #expect(history.models.first?.estimatedCostUSD == nil)
        #expect(history.models.first?.totalTokens == 150)
    }

    @Test("没有本地会话时仍可显示桌面版账号明细")
    func readsAccountUsageWithoutSessionFiles() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let days = [day(model: "gpt-6.1-sol-wm", tokens: 150)]
        let reader = TokenCostReader(homeDirectory: home, costSyncConfiguration: { nil }, readAccountModelUsage: { _ in
            AccountModelUsageResult(days: days)
        })
        let result = try await reader.readRecordSet()
        #expect(result.localRecordCount == 0)
        #expect(result.records.first?.totalTokens == 150)
        #expect(result.dataScope == .account)
        #expect(result.syncMessage?.contains("UTC") == true)
    }

    @Test("账号接口不可用时保留设备记录并明确提示缺少桌面版模型明细")
    func keepsLocalDataOnAccountFailure() async throws {
        let home = try sessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let reader = TokenCostReader(homeDirectory: home, costSyncConfiguration: { nil }, readAccountModelUsage: { _ in
            throw AccountModelUsageReader.ReadError.tokenBreakdownUnavailable
        })
        let result = try await reader.readRecordSet()
        #expect(result.records.count == 1)
        #expect(result.syncMessage?.contains("桌面版对话可能未纳入") == true)
    }

    @Test("会话移入归档后历史用量不减少，普通与归档目录的副本只计一次")
    func includesArchiveAndDeduplicatesMoves() async throws {
        let home = try sessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent(".codex/sessions/session.jsonl")
        let archive = home.appendingPathComponent(".codex/archived_sessions")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let reader = TokenCostReader(homeDirectory: home, costSyncConfiguration: { nil })
        let initial = try await reader.readRecordSet()
        try FileManager.default.copyItem(at: source, to: archive.appendingPathComponent("copy.jsonl"))
        let copied = try await reader.readRecordSet()
        #expect(copied.records == initial.records)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/sessions"))
        let moved = try await reader.readRecordSet()
        #expect(moved.records == initial.records)
    }

    @Test("设置事件切换模型时，6.1 用量不沿用旧模型和不丢失服务档位")
    func followsModelSettingsWithoutTurnContext() throws {
        let home = try sessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".codex/sessions/session.jsonl")
        let fixture = """
        {"type":"turn_context","payload":{"model":"gpt-6-sol","service_tier":"priority"}}
        {"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol"}}}
        {"timestamp":"2026-10-22T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
        {"type":"event_msg","payload":{"type":"thread_settings_applied","service_tier":"ultrafast"}}
        {"timestamp":"2026-10-22T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"output_tokens":20}}}}
        {"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":null}}}
        {"timestamp":"2026-10-22T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"output_tokens":30}}}}
        """
        try fixture.write(to: file, atomically: true, encoding: .utf8)
        let records = try TokenCostSessionParser.records(in: file)
        #expect(records.map(\.model) == ["gpt-6.1-sol", "gpt-6.1-sol", "gpt-6.1-sol"])
        #expect(records.map(\.serviceTier) == [.priority, .ultrafast, .standard])
    }

    @Test("认证和请求参数沿用桌面接口，包含 Work 来源并使用 UTC 日期")
    func requestsWorkModelsWithCorrectScope() throws {
        let auth = Data(#"{"tokens":{"access_token":"test-token","account_id":"test-account"}}"#.utf8)
        let request = try AccountModelUsageReader.request(authData: auth, now: date("2026-10-23T01:00:00Z"), isWorkspace: true)
        let url = try #require(request.url)
        #expect(url.host == "chatgpt.com")
        #expect(url.path.hasSuffix("daily-workspace-user-token-usage-breakdown"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.filter { $0.name == "modes" }.compactMap(\.value) == ["codex", "work"])
        #expect(query.first { $0.name == "end_date" }?.value == "2026-10-23")
        #expect(request.value(forHTTPHeaderField: "x-openai-codex-usage-categories") == "1")
    }

    @Test("明细刷新失败保留同账号缓存，切换账号后不会复用旧数据")
    func scopesCacheAndKeepsStaleData() async throws {
        let box = AuthBox()
        let mock = MockTransport(data: Data(grouped.utf8))
        let reader = AccountModelUsageReader(authData: { box.read() }, transport: { request in
            try await mock.respond(request)
        })
        let now = date("2026-10-23T01:00:00Z")
        let first = try await reader.read(now: now)
        await mock.fail()
        let warm = try await reader.read(now: now.addingTimeInterval(30))
        #expect(warm.days == first.days)
        #expect(await mock.count == 1)
        let stale = try await reader.read(now: now.addingTimeInterval(61))
        #expect(stale.days == first.days)
        #expect(stale.warning != nil)
        box.changeAccount()
        await #expect(throws: (any Error).self) { try await reader.read(now: now.addingTimeInterval(62)) }
    }

    @Test("个人接口返回积分时不得伪造 GPT-6.1 Token")
    func rejectsCreditsFallback() async throws {
        let box = AuthBox()
        let reader = AccountModelUsageReader(authData: { box.read() }, transport: { request in
            let isWorkspace = request.url!.path.contains("workspace-user")
            let response = HTTPURLResponse(url: request.url!, statusCode: isWorkspace ? 403 : 200,
                                           httpVersion: nil, headerFields: nil)!
            return (Data(#"{"units":"credits","data":[]}"#.utf8), response)
        })
        await #expect(throws: AccountModelUsageReader.ReadError.tokenBreakdownUnavailable) { try await reader.read() }
    }

    @Test("重启后恢复同账号明细，查询窗口前移不会删除已保存的历史 Token")
    func restoresCacheAndRetainsOlderHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("usage.json")
        let auth = AuthBox()
        let mock = MockTransport(data: Data(grouped.utf8))
        let now = date("2026-10-23T01:00:00Z")
        let firstReader = AccountModelUsageReader(cacheURL: cache, authData: { auth.read() }, transport: { request in
            try await mock.respond(request)
        })
        let first = try await firstReader.read(now: now)
        let saved = try String(contentsOf: cache, encoding: .utf8)
        #expect(!saved.contains("test-token"))
        #expect(!saved.contains("first-test-account"))
        await mock.fail()
        let restored = AccountModelUsageReader(cacheURL: cache, authData: { auth.read() }, transport: { request in
            try await mock.respond(request)
        })
        let stale = try await restored.read(now: now.addingTimeInterval(61))
        #expect(stale.days == first.days)
        #expect(stale.warning != nil)
        let later = AccountModelUsageReader(cacheURL: cache, authData: { auth.read() }, transport: { request in
            (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                         httpVersion: nil, headerFields: nil)!)
        })
        let advanced = try await later.read(now: now.addingTimeInterval(100 * 86400))
        #expect(advanced.days == first.days)
        auth.changeAccount()
        await #expect(throws: (any Error).self) { try await restored.read(now: now.addingTimeInterval(62)) }
    }

    @Test("账号读取取消时向上传播取消，不回退成成功的旧统计")
    func propagatesCancellation() async throws {
        let home = try sessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let reader = TokenCostReader(homeDirectory: home, costSyncConfiguration: { nil }, readAccountModelUsage: { _ in
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) { try await reader.readRecordSet() }
    }

    @Test("账号模型明细不写入 iCloud 设备账本，防止多设备重复上报")
    func doesNotSyncAccountAggregatesAsDeviceEvents() async throws {
        let home = try sessionHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"account_id":"test-account"}}"#.utf8)
            .write(to: home.appendingPathComponent(".codex/auth.json"))
        let configuration = CostSyncConfiguration(folderURL: folder, deviceID: "test-device", namespace: "test-namespace")
        let days = [day(model: "gpt-6.1-sol", tokens: 200)]
        let reader = TokenCostReader(homeDirectory: home, costLedgerCacheURL: home.appendingPathComponent("ledger-cache.json"),
                                     costSyncConfiguration: { configuration }, readAccountModelUsage: { _ in
            AccountModelUsageResult(days: days)
        })
        let result = try await reader.readRecordSet()
        #expect(result.records.reduce(0) { $0 + $1.totalTokens } == 200)
        #expect(result.records.contains { $0.isAccountAggregate })
        let ledger = try CostLedgerSyncService(homeDirectory: home, cacheURL: home.appendingPathComponent("other-cache.json"))
            .sync(localRecords: [], configuration: configuration)
        #expect(ledger.records.reduce(0) { $0 + $1.totalTokens } == 110)
        #expect(!ledger.records.contains { $0.isAccountAggregate })
    }

    @Test("Plus 的工作区接口返回 400 时回退个人接口，保留 6.1 名称而不把百分比变成 Token")
    func fallsBackForPersonalAccountWithoutWorkspace() async throws {
        let auth = AuthBox()
        let reader = AccountModelUsageReader(authData: { auth.read() }, transport: { request in
            let workspace = request.url!.path.contains("workspace-user")
            let data = workspace
                ? Data(#"{"detail":"No active workspace found for the current account."}"#.utf8)
                : Data(#"{"units":"percent","data":[{"date":"2026-10-23","models":[{"model":"gpt-6.1-sol","speed":"standard","credits":0}]}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: workspace ? 400 : 200,
                                         httpVersion: nil, headerFields: nil)!)
        })
        let now = date("2026-10-23T10:00:00Z")
        let result = try await reader.read(now: now)
        #expect(result.days.isEmpty)
        #expect(result.unquantifiedDays.map(\.model) == ["gpt-6.1-sol"])
        #expect(result.warning?.contains("未提供 Token 明细") == true)
        let warm = try await reader.read(now: now.addingTimeInterval(1))
        #expect(warm.unquantifiedDays == result.unquantifiedDays)
        #expect(warm.warning == result.warning)
    }

    @Test("其他 HTTP 400 不会被误认为无工作区而掩盖请求错误")
    func reportsUnrelatedBadRequests() async throws {
        let auth = AuthBox()
        let reader = AccountModelUsageReader(authData: { auth.read() }, transport: { request in
            (Data(#"{"detail":"Invalid date range"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: AccountModelUsageReader.ReadError.httpStatus(400)) { try await reader.read() }
    }

    @Test("只有模型名称的账号明细进入今日面板且不显示零 Token 或零成本")
    func showsKnownAccountModelsWithoutInventingCounts() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let today = date("2026-10-23T00:00:00Z")
        let yesterday = date("2026-10-22T00:00:00Z")
        let reader = TokenCostReader(homeDirectory: home, costSyncConfiguration: { nil }, readAccountModelUsage: { _ in
            AccountModelUsageResult(days: [], unquantifiedDays: [
                .init(date: today, model: "gpt-6.1-sol"),
                .init(date: today, model: "gpt-6.1-sol"),
                .init(date: yesterday, model: "gpt-6-luna")
            ])
        })
        let snapshot = try await reader.read(now: date("2026-10-23T10:00:00Z"))
        #expect(snapshot.today.unquantifiedModels == ["gpt-6.1-sol"])
        #expect(snapshot.yesterday.unquantifiedModels == ["gpt-6-luna"])
        #expect(snapshot.today.models.isEmpty)
        #expect(TokenCostFormatter.amount(snapshot.today) == "未计价")
        #expect(snapshot.dataScope == .account)
        #expect(snapshot.syncMessage?.contains("gpt-6.1-sol") == true)
        let reconciled = TokenCostReconciler.reconcile(snapshot,
            with: .init(peakDailyTokens: 100, days: [.init(startDate: "2026-10-23", tokens: 100)]),
            now: date("2026-10-23T10:00:00Z"))
        #expect(reconciled.today.unquantifiedModels == ["gpt-6.1-sol"])
    }

    @Test("模型名称和 Token 未提供的提示跨重启保留，不因缓存变成零用量")
    func restoresUnquantifiedModelsFromCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("account.json")
        let auth = AuthBox()
        let reader = AccountModelUsageReader(cacheURL: cache, authData: { auth.read() }, transport: { request in
            (Data(#"{"units":"percent","data":[{"date":"2026-10-23","models":[{"model":"gpt-6.1-sol","credits":0}]}]}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let now = date("2026-10-23T10:00:00Z")
        let first = try await reader.read(now: now)
        let restored = AccountModelUsageReader(cacheURL: cache, authData: { auth.read() }, transport: { _ in
            throw URLError(.notConnectedToInternet)
        })
        let result = try await restored.read(now: now.addingTimeInterval(61))
        #expect(result.days.isEmpty)
        #expect(result.unquantifiedDays == first.unquantifiedDays)
        #expect(result.warning?.contains("未提供 Token 明细") == true)
    }

    @Test("账号有总 Token 但无任何可用单价时，差额成本是未知而非零")
    func accountTotalWithoutPricingRemainsUnpriced() {
        let now = date("2026-10-23T10:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for presence in [[], [AccountModelUsagePresence(date: date("2026-10-23T00:00:00Z"), model: "gpt-6.1-sol")]] {
            let recorded = TokenCostCalculator.snapshot(records: [], now: now, calendar: calendar,
                subscriptionPeriod: nil, unquantifiedAccountDays: presence)
            let result = TokenCostReconciler.reconcile(recorded,
                with: .init(peakDailyTokens: 100, lifetimeTokens: 100,
                            days: [.init(startDate: "2026-10-23", tokens: 100)]),
                now: now, calendar: calendar)
            #expect(result.today.totalTokens == 100)
            #expect(result.today.models.isEmpty)
            #expect(result.today.supplement?.tokens == 100)
            #expect(result.today.supplement?.estimatedCostUSD == nil)
            #expect(TokenCostFormatter.amount(result.today) == "未计价")
            #expect(TokenCostFormatter.amount(result.lifetime) == "未计价")
        }
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func day(model: String, tokens: Int64) -> AccountModelUsageDay {
        AccountModelUsageDay(date: date("2026-10-22T00:00:00Z"), model: model, tokens: tokens)
    }
    private func record(model: String, tokens: Int64) -> TokenUsageRecord {
        TokenUsageRecord(timestamp: date("2026-10-22T23:59:59Z"), model: model, inputTokens: tokens,
                         cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: 0, totalTokens: tokens)
    }
    private func sessionHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let fixture = """
        {"type":"session_meta","payload":{"id":"test-session"}}
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"timestamp":"2026-10-22T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
        """
        try fixture.write(to: sessions.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        return home
    }
}

private final class AuthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var account = "first-test-account"
    func read() -> Data {
        lock.lock(); defer { lock.unlock() }
        return Data("{\"tokens\":{\"access_token\":\"test-token\",\"account_id\":\"\(account)\"}}".utf8)
    }
    func changeAccount() { lock.lock(); defer { lock.unlock() }; account = "second-test-account" }
}

private actor MockTransport {
    let data: Data
    private var shouldFail = false
    private(set) var count = 0
    init(data: Data) { self.data = data }
    func fail() { shouldFail = true }
    func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        count += 1
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
