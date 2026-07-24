import Foundation
import Testing
@testable import CodexQ

struct CostLedgerSyncTests {
    @Test("两台设备只合并脱敏事件并按稳定标识去重")
    func mergesSanitizedDeviceLedgersByStableEventID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let firstHome = root.appendingPathComponent("first-home", isDirectory: true)
        let secondHome = root.appendingPathComponent("second-home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: firstHome)
        try writeAuth(accountID: "same-account", home: secondHome)

        let firstService = CostLedgerSyncService(
            homeDirectory: firstHome,
            cacheURL: root.appendingPathComponent("first-cache.json")
        )
        let secondService = CostLedgerSyncService(
            homeDirectory: secondHome,
            cacheURL: root.appendingPathComponent("second-cache.json")
        )
        let namespace = try firstService.prepare(folderURL: folder)

        _ = try firstService.sync(
            localRecords: [record(id: "shared-event", tokens: 100)],
            configuration: CostSyncConfiguration(
                folderURL: folder,
                deviceID: "first-device",
                namespace: namespace
            )
        )
        let merged = try secondService.sync(
            localRecords: [
                record(id: "shared-event", tokens: 100),
                record(id: "second-event", tokens: 200)
            ],
            configuration: CostSyncConfiguration(
                folderURL: folder,
                deviceID: "second-device",
                namespace: namespace
            )
        )

        #expect(merged.records.count == 2)
        #expect(Set(merged.records.compactMap(\.eventID)) == ["shared-event", "second-event"])
        #expect(merged.deviceCount == 2)

        let contents = try ledgerText(in: folder)
        #expect(!contents.contains("same-account"))
        #expect(!contents.contains("first-device"))
        #expect(!contents.contains("second-device"))
        #expect(!contents.contains("prompt"))
        #expect(!contents.contains("cwd"))
        #expect(!contents.contains("access_token"))
    }

    @Test("不同 Codex 账号不能加入已有账本")
    func rejectsMismatchedAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let firstHome = root.appendingPathComponent("first-home", isDirectory: true)
        let secondHome = root.appendingPathComponent("second-home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "first-account", home: firstHome)
        try writeAuth(accountID: "second-account", home: secondHome)
        _ = try CostLedgerSyncService(homeDirectory: firstHome).prepare(folderURL: folder)

        #expect(throws: CostLedgerSyncService.SyncError.accountMismatch) {
            _ = try CostLedgerSyncService(homeDirectory: secondHome).prepare(folderURL: folder)
        }
    }

    @Test("复制会话生成相同事件标识且同会话重复事件仍各自保留")
    func parserCreatesStableIDsWithoutCollapsingRealRepeats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = """
        {"timestamp":"2026-07-23T01:00:00.000Z","type":"session_meta","payload":{"id":"stable-session"}}
        {"timestamp":"2026-07-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}}
        {"timestamp":"2026-07-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}}
        """
        let first = root.appendingPathComponent("first.jsonl")
        let copy = root.appendingPathComponent("copy.jsonl")
        try fixture.write(to: first, atomically: true, encoding: .utf8)
        try fixture.write(to: copy, atomically: true, encoding: .utf8)

        let firstRecords = try TokenCostSessionParser.records(in: first)
        let copiedRecords = try TokenCostSessionParser.records(in: copy)

        #expect(firstRecords.count == 2)
        #expect(firstRecords[0].eventID != firstRecords[1].eventID)
        #expect(firstRecords.map(\.eventID) == copiedRecords.map(\.eventID))
    }

    private func record(id: String, tokens: Int64) -> TokenUsageRecord {
        TokenUsageRecord(
            eventID: id,
            timestamp: Date(timeIntervalSince1970: 1_774_483_200),
            model: "gpt-5.6-sol",
            inputTokens: tokens,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            totalTokens: tokens
        )
    }

    private func writeAuth(accountID: String, home: URL) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )
        let auth = #"{"tokens":{"account_id":"\#(accountID)"}}"#
        try auth.write(
            to: home.appendingPathComponent(".codex/auth.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func ledgerText(in folder: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return ""
        }
        var result = ""
        for case let url as URL in enumerator where url.pathExtension == "json" {
            result += try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }
}
