import Foundation
import Testing
@testable import CodexQ

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

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

    @Test("多台设备同时初始化空文件夹时采用同一个账本命名空间")
    func concurrentPreparationUsesPersistedManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let namespaces = LockedStrings()

        DispatchQueue.concurrentPerform(iterations: 16) { device in
            do {
                let service = CostLedgerSyncService(
                    homeDirectory: home,
                    cacheURL: root.appendingPathComponent("cache-\(device).json")
                )
                namespaces.append(try service.prepare(folderURL: folder))
            } catch {
                namespaces.append("error:\(error)")
            }
        }

        #expect(namespaces.values.count == 16)
        #expect(Set(namespaces.values).count == 1)
    }

    @Test("同账号清单发生竞争后同步采用文件夹中的权威命名空间")
    func syncAdoptsAuthoritativeNamespace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let service = CostLedgerSyncService(
            homeDirectory: home,
            cacheURL: root.appendingPathComponent("cache.json")
        )
        let namespace = try service.prepare(folderURL: folder)

        let result = try service.sync(
            localRecords: [record(id: "valid-event", tokens: 100)],
            configuration: CostSyncConfiguration(
                folderURL: folder,
                deviceID: "current-device",
                namespace: "stale-namespace"
            )
        )

        #expect(result.namespace == namespace)
        #expect(result.records.count == 1)
    }

    @Test("聚合缓存超过容量时不保留旧缓存并明确报告")
    func reportsAggregateCacheFailureWithoutKeepingStaleData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let service = CostLedgerSyncService(
            homeDirectory: home,
            cacheURL: root.appendingPathComponent("cache.json"),
            cacheSizeLimit: 1
        )
        let namespace = try service.prepare(folderURL: folder)

        let result = try service.sync(
            localRecords: [record(id: "valid-event", tokens: 100)],
            configuration: CostSyncConfiguration(
                folderURL: folder,
                deviceID: "current-device",
                namespace: namespace
            )
        )

        #expect(result.records.count == 1)
        #expect(result.cacheWarning != nil)
        #expect(service.loadCache(namespace: namespace) == nil)
    }

    @Test("已取消的成本同步在扫描账本前立即停止")
    func cancelledSyncStopsBeforeScanningLedgers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let service = CostLedgerSyncService(
            homeDirectory: home,
            cacheURL: root.appendingPathComponent("cache.json")
        )
        let namespace = try service.prepare(folderURL: folder)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try service.sync(
                    localRecords: [record(id: "valid-event", tokens: 100)],
                    configuration: CostSyncConfiguration(
                        folderURL: folder,
                        deviceID: "current-device",
                        namespace: namespace
                    )
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        #expect(await task.value)
    }

    @Test("本设备账本混入无效记录后会重建，避免多设备成本永久缺失")
    func repairsInvalidEntryInCurrentDeviceLedger() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let service = CostLedgerSyncService(
            homeDirectory: home,
            cacheURL: root.appendingPathComponent("cache.json")
        )
        let namespace = try service.prepare(folderURL: folder)
        let configuration = CostSyncConfiguration(
            folderURL: folder,
            deviceID: "current-device",
            namespace: namespace
        )
        _ = try service.sync(
            localRecords: [record(id: "valid-event", tokens: 100)],
            configuration: configuration
        )

        let ledgerURL = try #require(deviceLedgerURLs(in: folder).first)
        var ledger = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any]
        )
        var entries = try #require(ledger["records"] as? [[String: Any]])
        var invalid = try #require(entries.first)
        invalid["eventID"] = "invalid-event"
        invalid["inputTokens"] = -1
        entries.append(invalid)
        ledger["records"] = entries
        try JSONSerialization.data(withJSONObject: ledger, options: [.sortedKeys])
            .write(to: ledgerURL, options: .atomic)

        let repaired = try service.sync(
            localRecords: [record(id: "valid-event", tokens: 100)],
            configuration: configuration
        )

        #expect(repaired.records.map(\.eventID) == ["valid-event"])
        #expect(repaired.skippedFileCount == 0)
        let repairedText = try String(contentsOf: ledgerURL, encoding: .utf8)
        #expect(!repairedText.contains("invalid-event"))
    }

    @Test("账本内容没有变化时不替换文件，避免历史月份反复上传")
    func leavesUnchangedLedgerFileUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sync", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAuth(accountID: "same-account", home: home)
        let service = CostLedgerSyncService(
            homeDirectory: home,
            cacheURL: root.appendingPathComponent("cache.json")
        )
        let namespace = try service.prepare(folderURL: folder)
        let configuration = CostSyncConfiguration(
            folderURL: folder,
            deviceID: "current-device",
            namespace: namespace
        )
        let records = [record(id: "stable-event", tokens: 100)]
        _ = try service.sync(localRecords: records, configuration: configuration)
        let ledgerURL = try #require(deviceLedgerURLs(in: folder).first)
        let before = try #require(
            FileManager.default.attributesOfItem(atPath: ledgerURL.path)[.modificationDate] as? Date
        )
        Thread.sleep(forTimeInterval: 0.05)

        _ = try service.sync(localRecords: records, configuration: configuration)

        let after = try #require(
            FileManager.default.attributesOfItem(atPath: ledgerURL.path)[.modificationDate] as? Date
        )
        #expect(after == before)
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

    private func deviceLedgerURLs(in folder: URL) -> [URL] {
        let devices = folder.appendingPathComponent("devices", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: devices,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "json" else { return nil }
            return url
        }
    }
}
