import Foundation

struct CachedQuotaSnapshot: Codable {
    let snapshot: QuotaSnapshot
    let updatedAt: Date
}

enum SnapshotCache {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQ", isDirectory: true)
            .appendingPathComponent("last-snapshot.json")
    }

    static func load() -> CachedQuotaSnapshot? {
        for url in [fileURL, legacyFileURL] {
            guard let data = try? Data(contentsOf: url),
                  let cached = try? JSONDecoder().decode(CachedQuotaSnapshot.self, from: data) else {
                continue
            }
            return cached
        }
        return nil
    }

    static func save(_ cached: CachedQuotaSnapshot) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static var legacyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codesk", isDirectory: true)
            .appendingPathComponent("last-snapshot.json")
    }
}
