import Foundation
import Testing
@testable import CodexQ

struct ResetCreditDecodingTests {
    @Test("额度响应解析可用次数和重置明细")
    func decodesResetCreditSummary() throws {
        let json = #"""
        {
          "rateLimits": {
            "primary": {"usedPercent": 6, "windowDurationMins": 300, "resetsAt": 1783663386},
            "secondary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1784250186}
          },
          "rateLimitResetCredits": {
            "availableCount": 2,
            "credits": [{
              "id": "credit-1",
              "resetType": "codexRateLimits",
              "status": "available",
              "title": "Full reset (Weekly + 5 hr)",
              "expiresAt": 1785109996,
              "grantedAt": 1782517996
            }]
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
        let snapshot = try #require(response.quotaSnapshot)

        #expect(snapshot.resetCredits?.availableCount == 2)
        #expect(snapshot.resetCredits?.credits?.first?.title == "Full reset (Weekly + 5 hr)")
        #expect(snapshot.resetCredits?.credits?.first?.expiresAt
            == Date(timeIntervalSince1970: 1_785_109_996))
    }

    @Test("旧缓存缺少重置字段时仍可解析")
    func decodesLegacySnapshotWithoutResetCredits() throws {
        let json = #"{"fiveHour":{"usedPercent":6,"resetsAt":null,"durationMinutes":300},"weekly":{"usedPercent":1,"resetsAt":null,"durationMinutes":10080}}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: json)

        #expect(snapshot.resetCredits == nil)
    }

    @Test("额度响应缺少或返回空重置信息时保持兼容")
    func decodesMissingAndNullResetCredits() throws {
        let withoutField = #"{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300},"secondary":{"usedPercent":1,"windowDurationMins":10080}}}"#.data(using: .utf8)!
        let withNull = #"{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300},"secondary":{"usedPercent":1,"windowDurationMins":10080}},"rateLimitResetCredits":null}"#.data(using: .utf8)!

        for json in [withoutField, withNull] {
            let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
            #expect(response.quotaSnapshot?.resetCredits == nil)
        }
    }

    @Test("只展示 available 状态但保留权威次数")
    func filtersAvailableDetailsWithoutChangingCount() {
        let summary = ResetCreditsSummary(
            availableCount: 3,
            credits: [
                ResetCredit(
                    id: "a",
                    resetType: "codexRateLimits",
                    status: "available",
                    title: nil,
                    expiresAt: nil
                ),
                ResetCredit(
                    id: "b",
                    resetType: "codexRateLimits",
                    status: "redeemed",
                    title: nil,
                    expiresAt: nil
                )
            ]
        )

        #expect(summary.availableCount == 3)
        #expect(summary.availableCredits.map(\.id) == ["a"])
    }
}
