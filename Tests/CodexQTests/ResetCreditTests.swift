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

struct ResetCreditPresentationTests {
    @Test("展示内容优先使用后端标题并格式化到期日")
    func presentsBackendTitleAndExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_784_260_800)
        let summary = ResetCreditsSummary(
            availableCount: 1,
            credits: [
                ResetCredit(
                    id: "a",
                    resetType: "codexRateLimits",
                    status: "available",
                    title: "Full reset",
                    expiresAt: expiry
                )
            ]
        )
        let presentation = ResetCreditPresentation(
            summary: summary,
            timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!
        )

        #expect(presentation.countText == "可用 1 次")
        #expect(presentation.rows.first?.title == "Full reset")
        #expect(presentation.rows.first?.detail == "将于 7/17 到期")
    }

    @Test("标题缺失时使用中文兜底")
    func fallsBackWhenTitleIsMissing() {
        let known = ResetCredit(
            id: "a",
            resetType: "codexRateLimits",
            status: "available",
            title: nil,
            expiresAt: nil
        )
        let unknown = ResetCredit(
            id: "b",
            resetType: "unknown",
            status: "available",
            title: "  ",
            expiresAt: nil
        )
        let presentation = ResetCreditPresentation(
            summary: ResetCreditsSummary(
                availableCount: 2,
                credits: [known, unknown]
            )
        )

        #expect(presentation.rows.map(\.title) == ["完整额度重置", "额度重置"])
        #expect(presentation.rows.allSatisfy { $0.detail == "无到期时间" })
    }

    @Test("空状态区分无可用次数与无明细")
    func distinguishesEmptyStates() {
        #expect(ResetCreditPresentation(
            summary: ResetCreditsSummary(availableCount: 0, credits: [])
        ).emptyMessage == "暂无可用重置")
        #expect(ResetCreditPresentation(
            summary: ResetCreditsSummary(availableCount: 2, credits: nil)
        ).emptyMessage == "暂无详细信息")
    }
}
