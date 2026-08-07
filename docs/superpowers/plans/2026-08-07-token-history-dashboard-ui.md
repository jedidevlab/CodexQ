# Token 历史仪表盘 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Token 历史窗口改成系统自适应背景、分层筛选、统一摘要卡和宽屏双栏趋势图的 macOS 仪表盘。

**Architecture:** 保留 `TokenHistoryStore`、查询模型和三张现有图表的输入接口，只重组 `TokenHistoryView` 的视觉层级。新增一个可复用的系统卡片表面，并用 `ViewThatFits(in: .horizontal)` 在宽窗口选择双栏趋势图、窄窗口选择纵向回退。

**Tech Stack:** Swift 6、SwiftUI、AppKit `NSWindowController`、Swift Charts、Swift Testing、macOS 14+

## Global Constraints

- 只修改 Token 历史窗口，不修改菜单栏弹窗、设置窗口或数据读取逻辑。
- 根窗口不写死黑色、白色或固定 RGB 背景，使用 macOS 默认窗口背景。
- 默认窗口内容尺寸为 `1080 × 720`，最小窗口尺寸为 `840 × 600`。
- 保留 `日 / 月 / 年 / 订阅周期 / 自定义` 五种查询模式和当前数据语义。
- 保留共享图表选择、键盘左右切换、Escape 清除、错误状态和辅助功能标签。
- 不新增工具、项目、终端、时长、会话数、消息数、分享或同步功能。
- 不增加外部依赖。

---

## File Map

- `Sources/CodexQ/App/TokenHistoryWindowController.swift`：历史窗口默认尺寸、最小尺寸和 autosave 约束。
- `Sources/CodexQ/Views/TokenHistoryView.swift`：标题、分行筛选、数据说明、摘要卡和整体仪表盘组合。
- `Sources/CodexQ/Views/TokenHistoryCharts.swift`：响应式趋势图区域、图表卡片表面和现有图表内容。
- `Tests/CodexQTests/TokenHistoryViewTests.swift`：窗口尺寸、系统背景、信息层级、卡片表面和响应式布局契约。

### Task 1: 系统窗口、分行筛选与统一摘要卡

**Files:**
- Modify: `Tests/CodexQTests/TokenHistoryViewTests.swift`
- Modify: `Sources/CodexQ/App/TokenHistoryWindowController.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryView.swift`

**Interfaces:**
- Consumes: `TokenHistoryStore`、`TokenHistorySummary`、现有 `contextualControls` 和 `qualityRow(_:)`。
- Produces: `TokenHistoryCardSurface`、`titleRow`、`rangeRow`、`contextRow`，供 Task 2 的图表卡片复用。

- [ ] **Step 1: 写窗口和视觉层级的失败测试**

在 `TokenHistoryViewTests.historyViewUsesAdaptiveDashboardLayout()` 中读取窗口与 View 源码并加入：

```swift
@Test("历史窗口使用系统背景、分行筛选和统一摘要卡")
func historyViewUsesAdaptiveDashboardLayout() throws {
    let windowSource = try source("Sources/CodexQ/App/TokenHistoryWindowController.swift")
    let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")

    #expect(windowSource.contains("width: 1080, height: 720"))
    #expect(windowSource.contains("window.minSize = NSSize(width: 840, height: 600)"))
    #expect(viewSource.contains("private var titleRow: some View"))
    #expect(viewSource.contains("private var rangeRow: some View"))
    #expect(viewSource.contains("private var contextRow: some View"))
    #expect(viewSource.contains("TokenHistoryCardSurface(cornerRadius: 12)"))
    #expect(viewSource.contains(".foregroundStyle(accent)"))
    #expect(!viewSource.contains(".background(color.opacity(0.08)"))
    #expect(!viewSource.contains("Color.black"))
    #expect(!viewSource.contains(".preferredColorScheme(.dark)"))
}
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests/historyViewUsesAdaptiveDashboardLayout
```

Expected: FAIL；当前源码仍包含 `920 × 680`、`760 × 560`、单行 header 和整块彩色摘要卡背景。

- [ ] **Step 3: 调整窗口尺寸并保留 autosave 限制**

在 `TokenHistoryWindowController.init(store:)` 中只改尺寸常量：

```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.minSize = NSSize(width: 840, height: 600)
```

保留 `hostingController.sizingOptions = []`、`TokenHistoryWindow` autosave 名称和现有小于最小尺寸时的恢复帧修正。

- [ ] **Step 4: 将 header 拆成三个明确视觉行**

在 `TokenHistoryView` 中让 `header` 只组合以下三个属性：

```swift
private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
        titleRow
        rangeRow
        contextRow
    }
}

private var titleRow: some View {
    HStack(spacing: 12) {
        Text("Token 使用与成本")
            .font(.largeTitle.weight(.bold))
        Spacer(minLength: 12)
        if store.isLoading, store.snapshot != nil {
            ProgressView().controlSize(.small)
        }
        Button(action: store.reload) {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .help("刷新历史数据")
    }
}

private var rangeRow: some View {
    HStack(spacing: 12) {
        Label("日期", systemImage: "clock")
            .font(.callout)
            .foregroundStyle(.secondary)
        Picker("范围", selection: $store.mode) {
            ForEach(TokenHistoryRangeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 440)
        Spacer(minLength: 0)
    }
}

private var contextRow: some View {
    HStack(spacing: 10) {
        contextualControls
        Spacer(minLength: 12)
        Text("API 价格估算，非实际订阅账单")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 5: 新增系统自适应卡片表面并移除摘要卡整块染色**

在 `TokenHistoryView.swift` 中新增模块内可见的表面组件：

```swift
struct TokenHistoryCardSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
    }
}
```

将 `HistorySummaryCard.color` 重命名为 `accent`。数值使用强调色，卡片背景统一：

```swift
Text(value)
    .font(.title2.weight(.semibold))
    .foregroundStyle(accent)
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.75)

.background {
    TokenHistoryCardSurface(cornerRadius: 12)
}
```

根 `VStack` 不添加 `.background(...)`，让 NSWindow 提供默认背景。

- [ ] **Step 6: 运行聚焦测试并确认通过**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests/historyViewUsesAdaptiveDashboardLayout
```

Expected: PASS。

- [ ] **Step 7: 运行现有 UI 契约回归**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests
swift test --disable-sandbox --filter StatusBarControllerTests
```

Expected: 所有测试通过，无跳过。

- [ ] **Step 8: 提交 Task 1**

```bash
git add Sources/CodexQ/App/TokenHistoryWindowController.swift Sources/CodexQ/Views/TokenHistoryView.swift Tests/CodexQTests/TokenHistoryViewTests.swift
git commit -m "feat: refine token history dashboard header"
```

### Task 2: 响应式双栏趋势图与统一图表卡片

**Files:**
- Modify: `Tests/CodexQTests/TokenHistoryViewTests.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryView.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryCharts.swift`

**Interfaces:**
- Consumes: Task 1 的 `TokenHistoryCardSurface`，现有 `TokenUsageHistoryChart`、`TokenCostHistoryChart`、`TokenModelBreakdownChart` 和共享 `Binding<Date?>`。
- Produces: `ResponsiveTokenHistoryCharts`，宽屏输出双栏趋势图，窄屏输出纵向趋势图；模型分布仍由父 View 单独整行展示。

- [ ] **Step 1: 写响应式图表布局的失败测试**

在 `TokenHistoryViewTests` 中新增：

```swift
@Test("趋势图宽屏双栏且窄屏自动纵向回退")
func historyChartsUseResponsiveTwoColumnLayout() throws {
    let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
    let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

    #expect(viewSource.contains("ResponsiveTokenHistoryCharts("))
    #expect(viewSource.contains("TokenModelBreakdownChart(models: snapshot.models)"))
    #expect(chartSource.contains("struct ResponsiveTokenHistoryCharts"))
    #expect(chartSource.contains("ViewThatFits(in: .horizontal)"))
    #expect(chartSource.contains("HStack(alignment: .top, spacing: 16)"))
    #expect(chartSource.contains(".frame(minWidth: 900)"))
    #expect(chartSource.contains("VStack(alignment: .leading, spacing: 16)"))
    #expect(chartSource.contains("TokenHistoryCardSurface(cornerRadius: 12)"))
    #expect(!chartSource.contains(".background(.thinMaterial"))
}
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests/historyChartsUseResponsiveTwoColumnLayout
```

Expected: FAIL；当前图表只在根 `VStack` 中纵向排列，且图表卡使用 `.thinMaterial`。

- [ ] **Step 3: 新增响应式趋势图组合**

在 `TokenHistoryCharts.swift` 中新增：

```swift
struct ResponsiveTokenHistoryCharts: View {
    let buckets: [TokenHistoryBucket]
    @Binding var selectedBucketStart: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                TokenUsageHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                TokenCostHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
            }
            .frame(minWidth: 900)

            VStack(alignment: .leading, spacing: 16) {
                TokenUsageHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                TokenCostHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
            }
        }
    }
}
```

让两张趋势卡在 HStack 中都使用 `.frame(maxWidth: .infinity)`；不复制选择状态，继续传入同一个 Binding。

- [ ] **Step 4: 在根视图中组合响应式趋势图和整行模型分布**

将 snapshot 的滚动内容改为：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 16) {
        ResponsiveTokenHistoryCharts(
            buckets: snapshot.buckets,
            selectedBucketStart: $selectedBucketStart
        )
        TokenModelBreakdownChart(models: snapshot.models)
    }
    .padding(.bottom, 12)
}
```

- [ ] **Step 5: 统一图表卡片表面**

在 `HistoryChartCard.body` 中保留 padding 和 overlay 层级，替换材质背景：

```swift
.background {
    TokenHistoryCardSurface(cornerRadius: 12)
}
```

移除原来的 `.background(.thinMaterial, in: ...)` 和重复 stroke overlay。Tooltip 继续使用 `.regularMaterial`，因为它是浮层而不是根卡片。

- [ ] **Step 6: 运行聚焦测试并确认通过**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests/historyChartsUseResponsiveTwoColumnLayout
```

Expected: PASS。

- [ ] **Step 7: 运行历史窗口和现有菜单栏回归**

Run:

```bash
swift test --disable-sandbox --filter TokenHistoryViewTests
swift test --disable-sandbox --filter TokenHistoryQueryTests
swift test --disable-sandbox --filter TokenHistoryStoreTests
swift test --disable-sandbox --filter TokenActivityViewTests
git diff --check
```

Expected: 所有测试通过，无跳过；无空白错误。

- [ ] **Step 8: 构建并进行实际窗口验收**

Run:

```bash
swift build --disable-sandbox -c release
./script/build_and_run.sh --verify
```

实际窗口检查：

1. 根背景跟随 macOS 外观，没有固定黑色。
2. 标题、范围模式和上下文控件分成三行。
3. 四张摘要卡统一系统表面，只有数值保留强调色。
4. 将窗口调整到 `1080 × 720` 时两张趋势图左右并列。
5. 将窗口收窄到 `840 × 600` 时两张趋势图纵向排列且可滚动。
6. 模型分布始终整行显示。
7. 选择一个 Token 桶后，成本图保持同一时间选择；左右键和 Escape 仍生效。

- [ ] **Step 9: 提交 Task 2**

```bash
git add Sources/CodexQ/Views/TokenHistoryView.swift Sources/CodexQ/Views/TokenHistoryCharts.swift Tests/CodexQTests/TokenHistoryViewTests.swift
git commit -m "feat: add responsive token history charts"
```

## Final Verification

- [ ] 运行 `git status --short --branch`，确认只在 `codex/token-history-dashboard` 上工作且工作区干净。
- [ ] 运行 `git log --oneline -4`，确认设计、计划和两项实现都有独立提交。
- [ ] 清理本次验收产生的临时截图；不删除 `.build`、`dist/CodexQ.app` 或用户数据。
