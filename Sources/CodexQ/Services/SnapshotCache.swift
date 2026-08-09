import Foundation

struct CachedQuotaSnapshot: Codable {
    let snapshot: QuotaSnapshot
    let updatedAt: Date
    let accountFingerprint: String?

    init(
        snapshot: QuotaSnapshot,
        updatedAt: Date,
        accountFingerprint: String? = nil
    ) {
        self.snapshot = snapshot
        self.updatedAt = updatedAt
        self.accountFingerprint = accountFingerprint
    }
}

enum SnapshotCache {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accountID: String?

            enum CodingKeys: String, CodingKey {
                case accountID = "account_id"
            }
        }

        let tokens: Tokens?
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQ", isDirectory: true)
            .appendingPathComponent("last-snapshot.json")
    }

    static func load() -> CachedQuotaSnapshot? {
        let accountFingerprint = currentAccountFingerprint()
        for url in [fileURL, legacyFileURL] {
            guard let data = try? Data(contentsOf: url),
                  let cached = try? JSONDecoder().decode(CachedQuotaSnapshot.self, from: data) else {
                continue
            }
            guard isUsable(cached, accountFingerprint: accountFingerprint) else { continue }
            return cached
        }
        return nil
    }

    static func save(_ cached: CachedQuotaSnapshot) {
        guard let accountFingerprint = currentAccountFingerprint() else { return }
        let scoped = CachedQuotaSnapshot(
            snapshot: cached.snapshot,
            updatedAt: cached.updatedAt,
            accountFingerprint: accountFingerprint
        )
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(scoped) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func accountFingerprint(authData: Data) -> String? {
        guard let accountID = try? JSONDecoder().decode(AuthFile.self, from: authData)
            .tokens?.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty else {
            return nil
        }
        return CostLedgerSyncService.digest("quota-cache:\(accountID)")
    }

    static func isUsable(
        _ cached: CachedQuotaSnapshot,
        accountFingerprint: String?
    ) -> Bool {
        guard let accountFingerprint else { return false }
        return cached.accountFingerprint == accountFingerprint
    }

    private static func currentAccountFingerprint() -> String? {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL) else { return nil }
        return accountFingerprint(authData: data)
    }

    private static var legacyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codesk", isDirectory: true)
            .appendingPathComponent("last-snapshot.json")
    }
}
