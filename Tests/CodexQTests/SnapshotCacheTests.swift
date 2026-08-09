import Foundation
import Testing
@testable import CodexQ

@Suite("SnapshotCacheTests")
struct SnapshotCacheTests {
    @Test("缓存只对写入时的账号可用")
    func cacheIsScopedToAccountFingerprint() throws {
        let first = try #require(SnapshotCache.accountFingerprint(
            authData: Data(#"{"tokens":{"account_id":"account-a"}}"#.utf8)
        ))
        let second = try #require(SnapshotCache.accountFingerprint(
            authData: Data(#"{"tokens":{"account_id":"account-b"}}"#.utf8)
        ))
        let snapshot = QuotaSnapshot(
            fiveHour: nil,
            weekly: .init(usedPercent: 25, resetsAt: nil, durationMinutes: nil)
        )
        let scoped = CachedQuotaSnapshot(
            snapshot: snapshot,
            updatedAt: Date(timeIntervalSince1970: 1),
            accountFingerprint: first
        )
        let legacy = CachedQuotaSnapshot(
            snapshot: snapshot,
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(first != second)
        #expect(SnapshotCache.isUsable(scoped, accountFingerprint: first))
        #expect(!SnapshotCache.isUsable(scoped, accountFingerprint: second))
        #expect(!SnapshotCache.isUsable(scoped, accountFingerprint: nil))
        #expect(!SnapshotCache.isUsable(legacy, accountFingerprint: first))
    }

    @Test("缺少稳定账号标识时不生成缓存指纹")
    func missingAccountIDDoesNotCreateFingerprint() {
        #expect(SnapshotCache.accountFingerprint(
            authData: Data(#"{"tokens":{}}"#.utf8)
        ) == nil)
        #expect(SnapshotCache.accountFingerprint(authData: Data("invalid".utf8)) == nil)
    }
}
