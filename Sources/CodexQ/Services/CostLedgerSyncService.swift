import CryptoKit
import Foundation

struct CostSyncConfiguration: Equatable, Sendable {
    let folderURL: URL
    let deviceID: String
    let namespace: String
}

enum CostSyncPreferences {
    static let enabledKey = "icloudCostSyncEnabled"
    static let folderPathKey = "icloudCostSyncFolderPath"
    static let deviceIDKey = "icloudCostSyncDeviceID"
    static let namespaceKey = "icloudCostSyncNamespace"

    static func configuration(defaults: UserDefaults = .standard) -> CostSyncConfiguration? {
        guard defaults.bool(forKey: enabledKey),
              let path = defaults.string(forKey: folderPathKey),
              let namespace = defaults.string(forKey: namespaceKey),
              !path.isEmpty else {
            return nil
        }
        let deviceID: String
        if let stored = defaults.string(forKey: deviceIDKey), !stored.isEmpty {
            deviceID = stored
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: deviceIDKey)
        }
        return CostSyncConfiguration(
            folderURL: URL(fileURLWithPath: path, isDirectory: true),
            deviceID: deviceID,
            namespace: namespace
        )
    }
}

struct CostLedgerSyncResult: Sendable {
    let records: [TokenUsageRecord]
    let deviceCount: Int
    let skippedFileCount: Int
    let namespace: String
}

struct CostLedgerCachedResult: Sendable {
    let records: [TokenUsageRecord]
    let deviceCount: Int
}

struct CostLedgerSyncService {
    enum SyncError: Equatable, LocalizedError {
        case folderUnavailable
        case accountUnavailable
        case accountMismatch
        case unsupportedVersion
        case invalidLedger

        var errorDescription: String? {
            switch self {
            case .folderUnavailable:
                return "iCloud Drive 文件夹暂不可用"
            case .accountUnavailable:
                return "无法确认 Codex 账号，成本同步未开启"
            case .accountMismatch:
                return "所选文件夹属于另一个 Codex 账号"
            case .unsupportedVersion:
                return "账本版本较新，请更新 CodexQ"
            case .invalidLedger:
                return "成本账本无法读取"
            }
        }
    }

    private struct Manifest: Codable {
        let schemaVersion: Int
        let namespace: String
        let salt: String
        let accountFingerprint: String
        let createdAt: Date
    }

    private struct LedgerFile: Codable {
        let schemaVersion: Int
        let device: String
        let month: String
        let records: [LedgerEntry]
    }

    private struct CacheFile: Codable {
        let schemaVersion: Int
        let namespace: String
        let deviceCount: Int
        let records: [LedgerEntry]
    }

    private struct LedgerEntry: Codable, Hashable {
        let eventID: String
        let timestamp: Date
        let model: String
        let inputTokens: Int64
        let cachedInputTokens: Int64
        let cacheWriteInputTokens: Int64
        let outputTokens: Int64
        let totalTokens: Int64
        let serviceTier: TokenServiceTier

        init?(_ record: TokenUsageRecord) {
            guard let eventID = record.eventID, !eventID.isEmpty else { return nil }
            self.eventID = eventID
            timestamp = record.timestamp
            model = record.model
            inputTokens = record.inputTokens
            cachedInputTokens = record.cachedInputTokens
            cacheWriteInputTokens = record.cacheWriteInputTokens
            outputTokens = record.outputTokens
            totalTokens = record.totalTokens
            serviceTier = record.serviceTier
        }

        var record: TokenUsageRecord {
            TokenUsageRecord(
                eventID: eventID,
                timestamp: timestamp,
                model: model,
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                cacheWriteInputTokens: cacheWriteInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens,
                serviceTier: serviceTier
            )
        }

        var isValid: Bool {
            !eventID.isEmpty
                && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && model.count <= 256
                && inputTokens >= 0
                && cachedInputTokens >= 0
                && cachedInputTokens <= inputTokens
                && cacheWriteInputTokens >= 0
                && cacheWriteInputTokens <= inputTokens - cachedInputTokens
                && outputTokens >= 0
                && totalTokens >= 0
        }
    }

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accountID: String?

            enum CodingKeys: String, CodingKey {
                case accountID = "account_id"
            }
        }

        let tokens: Tokens
    }

    static let schemaVersion = 1
    static let maximumLedgerSize = 16 * 1_024 * 1_024

    private let fileManager: FileManager
    private let authURL: URL
    private let cacheURL: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        cacheURL: URL? = nil
    ) {
        self.fileManager = fileManager
        authURL = homeDirectory.appendingPathComponent(".codex/auth.json")
        self.cacheURL = cacheURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQ/cost-ledger-cache.json")
    }

    func prepare(folderURL: URL) throws -> String {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        guard isDirectory(folderURL) else { throw SyncError.folderUnavailable }

        let probe = folderURL.appendingPathComponent(".codexq-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try fileManager.removeItem(at: probe)
        } catch {
            try? fileManager.removeItem(at: probe)
            throw SyncError.folderUnavailable
        }

        return try validatedManifest(in: folderURL).namespace
    }

    func sync(
        localRecords: [TokenUsageRecord],
        configuration: CostSyncConfiguration
    ) throws -> CostLedgerSyncResult {
        let manifest = try validatedManifest(in: configuration.folderURL)
        guard manifest.namespace == configuration.namespace else {
            throw SyncError.invalidLedger
        }
        let device = Self.digest(configuration.deviceID)
        try writeLocalLedgers(
            records: localRecords,
            folderURL: configuration.folderURL,
            device: device
        )
        let result = try readAllLedgers(
            folderURL: configuration.folderURL,
            namespace: manifest.namespace
        )
        try? saveCache(result)
        return result
    }

    func loadCache(namespace: String) -> CostLedgerCachedResult? {
        guard let data = try? Data(contentsOf: cacheURL),
              data.count <= Self.maximumLedgerSize,
              let cache = try? decoder.decode(CacheFile.self, from: data),
              cache.schemaVersion == Self.schemaVersion,
              cache.namespace == namespace else {
            return nil
        }
        return CostLedgerCachedResult(
            records: cache.records.map(\.record),
            deviceCount: cache.deviceCount
        )
    }

    private func validatedManifest(in folderURL: URL) throws -> Manifest {
        let accountID = try accountID()
        let url = folderURL.appendingPathComponent(".codexq-cost-ledger.json")
        if fileManager.fileExists(atPath: url.path) {
            let data = try boundedData(at: url)
            guard let manifest = try? decoder.decode(Manifest.self, from: data) else {
                throw SyncError.invalidLedger
            }
            guard manifest.schemaVersion == Self.schemaVersion else {
                throw SyncError.unsupportedVersion
            }
            guard manifest.accountFingerprint == Self.fingerprint(
                accountID: accountID,
                salt: manifest.salt
            ) else {
                throw SyncError.accountMismatch
            }
            return manifest
        }

        let salt = UUID().uuidString
        let manifest = Manifest(
            schemaVersion: Self.schemaVersion,
            namespace: UUID().uuidString,
            salt: salt,
            accountFingerprint: Self.fingerprint(accountID: accountID, salt: salt),
            createdAt: Date()
        )
        try write(manifest, to: url)
        return manifest
    }

    private func writeLocalLedgers(
        records: [TokenUsageRecord],
        folderURL: URL,
        device: String
    ) throws {
        let directory = folderURL
            .appendingPathComponent("devices", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let entries = records.compactMap(LedgerEntry.init)
        let grouped = Dictionary(grouping: entries) { month(for: $0.timestamp) }
        for (month, newEntries) in grouped {
            let url = directory.appendingPathComponent("\(month).json")
            var byID: [String: LedgerEntry] = [:]
            if fileManager.fileExists(atPath: url.path),
               let existing = try? decoder.decode(LedgerFile.self, from: boundedData(at: url)),
               existing.schemaVersion == Self.schemaVersion,
               existing.device == device {
                for entry in existing.records {
                    byID[entry.eventID] = entry
                }
            }
            for entry in newEntries {
                byID[entry.eventID] = entry
            }
            let ledger = LedgerFile(
                schemaVersion: Self.schemaVersion,
                device: device,
                month: month,
                records: byID.values.sorted {
                    if $0.timestamp == $1.timestamp { return $0.eventID < $1.eventID }
                    return $0.timestamp < $1.timestamp
                }
            )
            try write(ledger, to: url)
        }
    }

    private func readAllLedgers(
        folderURL: URL,
        namespace: String
    ) throws -> CostLedgerSyncResult {
        let devicesURL = folderURL.appendingPathComponent("devices", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: devicesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CostLedgerSyncResult(
                records: [],
                deviceCount: 0,
                skippedFileCount: 0,
                namespace: namespace
            )
        }

        var byID: [String: LedgerEntry] = [:]
        var devices = Set<String>()
        var skipped = 0
        for case let url as URL in enumerator where url.pathExtension == "json" {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      (values.fileSize ?? 0) <= Self.maximumLedgerSize else {
                    skipped += 1
                    continue
                }
                let ledger = try decoder.decode(LedgerFile.self, from: boundedData(at: url))
                guard ledger.schemaVersion == Self.schemaVersion,
                      !ledger.device.isEmpty,
                      !ledger.month.isEmpty,
                      ledger.records.allSatisfy(\.isValid) else {
                    skipped += 1
                    continue
                }
                devices.insert(ledger.device)
                for entry in ledger.records where !entry.eventID.isEmpty {
                    byID[entry.eventID] = entry
                }
            } catch {
                skipped += 1
            }
        }
        _ = namespace
        return CostLedgerSyncResult(
            records: byID.values.map(\.record),
            deviceCount: devices.count,
            skippedFileCount: skipped,
            namespace: namespace
        )
    }

    private func saveCache(_ result: CostLedgerSyncResult) throws {
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cache = CacheFile(
            schemaVersion: Self.schemaVersion,
            namespace: result.namespace,
            deviceCount: result.deviceCount,
            records: result.records.compactMap(LedgerEntry.init)
        )
        try write(cache, to: cacheURL)
    }

    private func accountID() throws -> String {
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let accountID = auth.tokens.accountID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty else {
            throw SyncError.accountUnavailable
        }
        return accountID
    }

    private func boundedData(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= Self.maximumLedgerSize else {
            throw SyncError.invalidLedger
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumLedgerSize else { throw SyncError.invalidLedger }
        try data.write(to: url, options: .atomic)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func month(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func fingerprint(accountID: String, salt: String) -> String {
        digest("\(salt):\(accountID)")
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
