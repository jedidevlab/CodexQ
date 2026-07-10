import Foundation

struct ResetCreditPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    let countText: String
    let rows: [Row]
    let emptyMessage: String?

    init(
        summary: ResetCreditsSummary,
        timeZone: TimeZone = .current
    ) {
        countText = "可用 \(summary.availableCount) 次"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"

        rows = summary.availableCredits.map { credit in
            Row(
                id: credit.id,
                title: Self.title(for: credit),
                detail: credit.expiresAt.map {
                    "将于 \(formatter.string(from: $0)) 到期"
                } ?? "无到期时间"
            )
        }

        if summary.availableCount == 0 {
            emptyMessage = "暂无可用重置"
        } else if rows.isEmpty {
            emptyMessage = "暂无详细信息"
        } else {
            emptyMessage = nil
        }
    }

    private static func title(for credit: ResetCredit) -> String {
        let trimmedTitle = credit.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return credit.resetType == "codexRateLimits"
            ? "完整额度重置"
            : "额度重置"
    }
}
