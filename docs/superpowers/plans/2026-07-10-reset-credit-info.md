# 限额重置信息实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务执行。本计划使用复选框跟踪进度。

**目标：** 在 CodexQ 菜单栏弹窗中增加只读、可折叠的限额重置信息区块。

**架构：** 扩展现有 `account/rateLimits/read` 解析结果和 `QuotaSnapshot`，让重置信息沿用 `QuotaStore` 与 `SnapshotCache` 数据流。将展示文案整理成可单测的 presentation 类型，SwiftUI 区块只负责折叠状态和渲染。

**技术栈：** Swift 6、Foundation、SwiftUI、Swift Testing、SwiftPM。

## 全局约束

- 只读取 `account/rateLimits/read`，不得调用 `account/rateLimitResetCredit/consume`。
- 不显示“使用重置”按钮或任何消耗重置次数的操作。
- `rateLimitResetCredits` 缺失或为 `null` 时保持现有界面。
- `availableCount` 是权威次数，不能用明细数量替代。
- 后端标题非空时按原文显示；缺失时使用中文兜底。
- 旧缓存必须继续正常解析。

---

### 任务 1：解析并缓存限额重置数据

**文件：**
- 修改：`Sources/CodexQ/Models/QuotaSnapshot.swift`
- 修改：`Sources/CodexQ/Services/AppServerClient.swift`
- 新建：`Tests/CodexQTests/ResetCreditTests.swift`

**接口：**
- 输入：`account/rateLimits/read` 顶层字段 `rateLimitResetCredits`
- 输出：`QuotaSnapshot.resetCredits: ResetCreditsSummary?`
- 输出：`ResetCreditsSummary.availableCredits: [ResetCredit]`

- [x] **步骤 1：编写失败测试**

在 `ResetCreditTests.swift` 中加入：

```swift
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
        #expect(snapshot.resetCredits?.credits?.first?.expiresAt == Date(timeIntervalSince1970: 1785109996))
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
                ResetCredit(id: "a", resetType: "codexRateLimits", status: "available", title: nil, expiresAt: nil),
                ResetCredit(id: "b", resetType: "codexRateLimits", status: "redeemed", title: nil, expiresAt: nil)
            ]
        )
        #expect(summary.availableCount == 3)
        #expect(summary.availableCredits.map(\.id) == ["a"])
    }
}
```

- [x] **步骤 2：确认测试因缺少模型而失败**

运行：`swift test --filter ResetCreditDecodingTests`

预期：编译失败，提示 `QuotaSnapshot` 没有 `resetCredits` 或找不到 `ResetCreditsSummary`。

- [x] **步骤 3：实现最小数据模型与响应映射**

在 `QuotaSnapshot.swift` 增加：

```swift
struct QuotaSnapshot: Codable, Equatable, Sendable {
    let fiveHour: QuotaWindow
    let weekly: QuotaWindow
    let resetCredits: ResetCreditsSummary?

    init(
        fiveHour: QuotaWindow,
        weekly: QuotaWindow,
        resetCredits: ResetCreditsSummary? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCredits = resetCredits
    }
}

struct ResetCreditsSummary: Codable, Equatable, Sendable {
    let availableCount: Int
    let credits: [ResetCredit]?

    var availableCredits: [ResetCredit] {
        credits?.filter { $0.status == "available" } ?? []
    }
}

struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let title: String?
    let expiresAt: Date?
}
```

给 `RateLimitsResponse` 增加 `rateLimitResetCredits` 和 `quotaSnapshot`，使用响应 DTO 将 Unix 时间戳转换为 `Date`：

```swift
struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsResponse?

    var preferredSnapshot: RateLimitSnapshot {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }

    var quotaSnapshot: QuotaSnapshot? {
        guard let limits = preferredSnapshot.quotaSnapshot else { return nil }
        return QuotaSnapshot(
            fiveHour: limits.fiveHour,
            weekly: limits.weekly,
            resetCredits: rateLimitResetCredits?.summary
        )
    }
}

struct RateLimitResetCreditsResponse: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCreditResponse]?

    var summary: ResetCreditsSummary {
        ResetCreditsSummary(
            availableCount: availableCount,
            credits: credits?.map(\.resetCredit)
        )
    }
}

struct RateLimitResetCreditResponse: Decodable {
    let id: String
    let resetType: String
    let status: String
    let title: String?
    let expiresAt: TimeInterval?

    var resetCredit: ResetCredit {
        ResetCredit(
            id: id,
            resetType: resetType,
            status: status,
            title: title,
            expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}
```

将 `AppServerClient` 的返回映射改为：

```swift
guard let snapshot = decoded.quotaSnapshot else {
    throw ClientError.missingRateLimits
}
return snapshot
```

- [x] **步骤 4：运行聚焦测试并确认通过**

运行：`swift test --filter ResetCreditDecodingTests`

预期：4 个测试通过。

- [x] **步骤 5：提交数据层变更**

```bash
git add Sources/CodexQ/Models/QuotaSnapshot.swift Sources/CodexQ/Services/AppServerClient.swift Tests/CodexQTests/ResetCreditTests.swift
git commit -m "Decode reset credit information"
```

### 任务 2：生成可单测的展示内容

**文件：**
- 新建：`Sources/CodexQ/Support/ResetCreditPresentation.swift`
- 修改：`Tests/CodexQTests/ResetCreditTests.swift`

**接口：**
- 输入：`ResetCreditsSummary`、时区
- 输出：`ResetCreditPresentation(countText:rows:emptyMessage:)`

- [x] **步骤 1：编写失败测试**

加入标题优先级、到期日期、0 次和无明细测试：

```swift
struct ResetCreditPresentationTests {
    @Test("展示内容优先使用后端标题并格式化到期日")
    func presentsBackendTitleAndExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_784_260_800)
        let summary = ResetCreditsSummary(
            availableCount: 1,
            credits: [ResetCredit(id: "a", resetType: "codexRateLimits", status: "available", title: "Full reset", expiresAt: expiry)]
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
        let known = ResetCredit(id: "a", resetType: "codexRateLimits", status: "available", title: nil, expiresAt: nil)
        let unknown = ResetCredit(id: "b", resetType: "unknown", status: "available", title: "  ", expiresAt: nil)
        let presentation = ResetCreditPresentation(summary: .init(availableCount: 2, credits: [known, unknown]))
        #expect(presentation.rows.map(\.title) == ["完整额度重置", "额度重置"])
        #expect(presentation.rows.allSatisfy { $0.detail == "无到期时间" })
    }

    @Test("空状态区分无可用次数与无明细")
    func distinguishesEmptyStates() {
        #expect(ResetCreditPresentation(summary: .init(availableCount: 0, credits: [])).emptyMessage == "暂无可用重置")
        #expect(ResetCreditPresentation(summary: .init(availableCount: 2, credits: nil)).emptyMessage == "暂无详细信息")
    }
}
```

- [x] **步骤 2：确认测试因缺少 presentation 而失败**

运行：`swift test --filter ResetCreditPresentationTests`

预期：编译失败，提示找不到 `ResetCreditPresentation`。

- [x] **步骤 3：实现展示类型**

```swift
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
                detail: credit.expiresAt.map { "将于 \(formatter.string(from: $0)) 到期" } ?? "无到期时间"
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
```

- [x] **步骤 4：运行聚焦测试并确认通过**

运行：`swift test --filter ResetCreditPresentationTests`

预期：3 个测试通过。

- [x] **步骤 5：提交展示逻辑**

```bash
git add Sources/CodexQ/Support/ResetCreditPresentation.swift Tests/CodexQTests/ResetCreditTests.swift
git commit -m "Format reset credit information"
```

### 任务 3：加入可折叠 SwiftUI 区块

**文件：**
- 新建：`Sources/CodexQ/Views/ResetCreditsSection.swift`
- 修改：`Sources/CodexQ/Views/QuotaPopoverView.swift`
- 修改：`Tests/CodexQTests/ResetCreditTests.swift`

**接口：**
- 输入：`ResetCreditsSummary`
- 输出：默认收起的 `ResetCreditsSection`

- [x] **步骤 1：添加安全边界测试**

```swift
struct ResetCreditUISafetyTests {
    @Test("限额重置界面不接入消耗操作")
    func resetCreditUIContainsNoConsumeAction() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/ResetCreditsSection.swift",
            encoding: .utf8
        )
        #expect(!source.contains("rateLimitResetCredit/consume"))
        #expect(!source.contains("使用重置"))
    }
}
```

测试文件尚不存在时运行并确认失败。

- [x] **步骤 2：实现 `ResetCreditsSection`**

创建独立 SwiftUI 视图：

```swift
import SwiftUI

struct ResetCreditsSection: View {
    let summary: ResetCreditsSummary
    @State private var isExpanded = false

    var body: some View {
        let presentation = ResetCreditPresentation(summary: summary)
        VStack(alignment: .leading, spacing: 8) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Text("限额重置")
                        .font(.headline)
                    Spacer()
                    Text(presentation.countText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            summary.availableCount > 0 ? Color.green : Color.secondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            summary.availableCount > 0
                                ? Color.green.opacity(0.16)
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let emptyMessage = presentation.emptyMessage {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(row.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)

                            if index < presentation.rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

徽标有次数时使用绿色背景，0 次时使用次要灰色；行标题单行截断，到期信息使用次要 caption 样式。

- [x] **步骤 3：接入现有弹窗**

在 `QuotaPopoverView` 的额度区和设置区之间加入：

```swift
if let resetCredits = store.snapshot?.resetCredits {
    Divider()
    ResetCreditsSection(summary: resetCredits)
}
```

保留设置区前原有 `Divider()`，因此缺少字段时布局不变。

- [x] **步骤 4：运行聚焦测试和编译验证**

运行：`swift test --filter ResetCredit`

预期：所有限额重置测试通过，SwiftUI 新文件编译成功。

- [x] **步骤 5：提交界面变更**

```bash
git add Sources/CodexQ/Views/ResetCreditsSection.swift Sources/CodexQ/Views/QuotaPopoverView.swift Tests/CodexQTests/ResetCreditTests.swift
git commit -m "Show reset credit information"
```

### 任务 4：全量验证与实际运行

**文件：**
- 验证：整个项目、`dist/CodexQ.app`

**接口：**
- 输入：任务 1 至任务 3 的完整实现
- 输出：可运行、可打包的菜单栏应用

- [x] 运行 `swift test`，要求 0 失败、0 跳过。
- [x] 运行 `swift build -c release -Xswiftc -warnings-as-errors`，要求退出码 0。
- [x] 运行 `./script/build_and_run.sh --verify`，要求 CodexQ 进程启动且 app bundle 签名通过。
- [x] 通过真实 `account/rateLimits/read` 验证返回的 `availableCount` 与缓存中的 `resetCredits` 一致。
- [x] 搜索 `account/rateLimitResetCredit/consume` 和“使用重置”，确认生产代码中不存在消耗入口。
- [x] 运行 `git diff --check`，检查提交历史和工作区状态。
