# Token History Adaptive Model Footer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the model-distribution card grow only with its displayed model rows and move every Token-history annotation below that card, with the API-price disclaimer as the final page line.

**Architecture:** Keep the existing `TokenHistoryView` and `TokenModelBreakdownChart` boundaries. Let SwiftUI derive the model card's vertical size from its row stack, and compose one bottom notes section inside the existing scroll content after the model card; no data model, aggregation, or window changes are required.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSHostingView`, Swift Testing, macOS 14+

## Global Constraints

- The model-distribution card remains full width; only its vertical sizing changes.
- Preserve model sorting, top-eight-plus-`其他` compaction, Token/cost switching, bar rendering, and values.
- Preserve the existing compact empty state when there are no model records.
- Move data scope, activity coverage, unpriced Token, skipped-file, sync, warning, refresh-error, and API-price notes below the model card.
- The exact final line is `API 价格估算，非实际订阅账单`.
- Keep semantic colors: secondary for normal notes, orange for unpriced/warning notes, and red for refresh errors.
- Do not change the window size, scroll behavior, trend-chart layout, aggregation, pricing, or data sources.
- Preserve the user's untracked `docs/superpowers/plans/2026-08-07-token-history-dashboard.md`; never stage it.
- Baseline note: `TokenHistoryRenderingTests.modelBarsFollowLongestModelName` already fails independently with a measured 40.37-point gap against a `< 24` expectation. Do not change horizontal model/bar spacing under this task; report that existing blocker separately during final verification.

---

### Task 1: Make the model card use intrinsic row height

**Files:**
- Modify: `Tests/CodexQTests/TokenHistoryRenderingTests.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryCharts.swift:327-361`

**Interfaces:**
- Consumes: `TokenModelBreakdownChart.init(models: [TokenHistoryModelSummary])`
- Produces: A model card whose fitting height increases by the actual `TokenModelBreakdownRow` count without a fixed 180-point floor.

- [ ] **Step 1: Add a failing fitting-height regression test**

Add this test to `TokenHistoryRenderingTests`:

```swift
@Test("模型分布高度随模型数量自然增长")
@MainActor
func modelBreakdownHeightTracksModelCount() {
    let compactHeight = modelBreakdownFittingHeight(modelCount: 2)
    let expandedHeight = modelBreakdownFittingHeight(modelCount: 8)

    #expect(compactHeight < expandedHeight)
    #expect(expandedHeight - compactHeight >= 150)
}
```

Add these helpers beside the existing rendering helpers:

```swift
@MainActor
private func modelBreakdownFittingHeight(modelCount: Int) -> CGFloat {
    let models = (1...modelCount).map { index in
        TokenHistoryModelSummary(
            model: "model-\(index)",
            totalTokens: Int64(index * 1_000_000),
            estimatedCostUSD: Double(index)
        )
    }
    let host = NSHostingView(
        rootView: TokenModelBreakdownChart(models: models)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.colorScheme, .light)
    )
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 1)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.height
}
```

- [ ] **Step 2: Run the new test and verify the fixed minimum blocks compact sizing**

Run:

```bash
swift test --filter modelBreakdownHeightTracksModelCount
```

Expected: FAIL because the current `.frame(minHeight: 180, alignment: .top)` keeps the two-model card too tall, so the eight-model card is less than 150 points taller.

- [ ] **Step 3: Remove only the fixed model-list minimum height**

Change the populated model-list branch in `TokenModelBreakdownChart` to:

```swift
VStack(spacing: 8) {
    ForEach(sortedModels) { model in
        TokenModelBreakdownRow(
            model: model,
            value: value(for: model),
            maximumValue: maximumValue,
            valueLabel: label(for: model),
            labelColumnWidth: modelLabelWidth,
            color: metric == .tokens ? .accentColor : .green
        )
    }
}
```

Do not add a replacement height calculation or tiered size table.

- [ ] **Step 4: Run the focused test and confirm intrinsic sizing**

Run:

```bash
swift test --filter modelBreakdownHeightTracksModelCount
```

Expected: PASS; the two-model card shrinks while the eight-model card grows by the six additional rows and six additional inter-row gaps.

- [ ] **Step 5: Commit the adaptive-height change**

```bash
git add Tests/CodexQTests/TokenHistoryRenderingTests.swift Sources/CodexQ/Views/TokenHistoryCharts.swift
git commit -m "fix: adapt model history height"
```

---

### Task 2: Move every history annotation below the model card

**Files:**
- Modify: `Tests/CodexQTests/TokenHistoryViewTests.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryView.swift:7-192`

**Interfaces:**
- Consumes: `TokenHistorySnapshot`, existing `qualityRow(_:)`, and `store.errorMessage`.
- Produces: `footerNotes(_ snapshot: TokenHistorySnapshot) -> some View`, called immediately after `TokenModelBreakdownChart` in the scroll content.

- [ ] **Step 1: Add a failing source-contract test for bottom-note ordering**

Add this test to `TokenHistoryViewTests`:

```swift
@Test("所有历史注释位于模型分布之后且价格说明最后显示")
func historyNotesFollowModelBreakdown() throws {
    let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
    let modelCall = try #require(
        viewSource.range(of: "TokenModelBreakdownChart(models: snapshot.models)")
    )
    let footerCall = try #require(viewSource.range(
        of: "footerNotes(snapshot)",
        range: modelCall.upperBound..<viewSource.endIndex
    ))
    let footerStart = try #require(
        viewSource.range(of: "private func footerNotes(_ snapshot: TokenHistorySnapshot)")
    )
    let footerEnd = try #require(viewSource.range(
        of: "private func qualityRow(_ snapshot: TokenHistorySnapshot)",
        range: footerStart.upperBound..<viewSource.endIndex
    ))
    let footerSource = viewSource[footerStart.lowerBound..<footerEnd.lowerBound]
    let quality = try #require(footerSource.range(of: "qualityRow(snapshot)"))
    let disclaimer = try #require(
        footerSource.range(of: "API 价格估算，非实际订阅账单")
    )

    #expect(modelCall.lowerBound < footerCall.lowerBound)
    #expect(quality.lowerBound < disclaimer.lowerBound)
    #expect(!viewSource.contains("private var contextRow: some View"))
}
```

- [ ] **Step 2: Run the new contract test and verify the footer is missing**

Run:

```bash
swift test --filter historyNotesFollowModelBreakdown
```

Expected: FAIL because `footerNotes(snapshot)` does not exist and the disclaimer still lives in `contextRow` above the charts.

- [ ] **Step 3: Recompose the page so notes follow the model card**

In the snapshot branch of `TokenHistoryView.body`, remove the top-level `qualityRow(snapshot)` and add the footer after the model card:

```swift
summaryStrip(snapshot.summary)
ScrollView {
    VStack(alignment: .leading, spacing: 16) {
        ResponsiveTokenHistoryCharts(
            buckets: snapshot.buckets,
            selectedBucketStart: $selectedBucketStart
        )
        TokenModelBreakdownChart(models: snapshot.models)
        footerNotes(snapshot)
    }
    .padding(.bottom, 12)
}
```

Remove `contextRow` from `header` and delete the obsolete `private var contextRow` property:

```swift
private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
        titleRow
        rangeRow
    }
}
```

Add the footer immediately before the existing `qualityRow(_:)` method so the static disclaimer is its final content:

```swift
private func footerNotes(_ snapshot: TokenHistorySnapshot) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        qualityRow(snapshot)
        Text("API 价格估算，非实际订阅账单")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

Keep `qualityRow(_:)` content and semantic colors unchanged.

- [ ] **Step 4: Run the footer contract and history-view suites**

Run:

```bash
swift test --filter historyNotesFollowModelBreakdown
swift test --filter TokenHistoryViewTests
```

Expected: PASS; the page source calls `footerNotes` after the model card, and the disclaimer is the footer's final line.

- [ ] **Step 5: Commit the bottom-note layout**

```bash
git add Tests/CodexQTests/TokenHistoryViewTests.swift Sources/CodexQ/Views/TokenHistoryView.swift
git commit -m "fix: move token history notes to footer"
```

---

### Task 3: Verify the feature and launch the current branch

**Files:**
- Verify only: `Sources/CodexQ/Views/TokenHistoryView.swift`
- Verify only: `Sources/CodexQ/Views/TokenHistoryCharts.swift`
- Verify only: `Tests/CodexQTests/TokenHistoryViewTests.swift`
- Verify only: `Tests/CodexQTests/TokenHistoryRenderingTests.swift`

**Interfaces:**
- Consumes: The intrinsic model-list layout and `footerNotes(_:)` from Tasks 1-2.
- Produces: Test, build, launch, process-path, and visual evidence for the current branch.

- [ ] **Step 1: Run the focused feature tests**

```bash
swift test --filter modelBreakdownHeightTracksModelCount
swift test --filter TokenHistoryViewTests
```

Expected: PASS.

- [ ] **Step 2: Run the complete rendering suite and record the known baseline issue separately**

```bash
swift test --filter TokenHistoryRenderingTests
```

Expected: The new adaptive-height test passes. The pre-existing `modelBarsFollowLongestModelName` test still fails with the previously reproduced horizontal-gap assertion; do not change horizontal spacing as part of this request.

- [ ] **Step 3: Run the full test suite and formatting check**

```bash
swift test
git diff --check
```

Expected: `git diff --check` passes. Report the full-suite result exactly, distinguishing any pre-existing model/bar horizontal-gap failure from the new feature tests.

- [ ] **Step 4: Build the release configuration**

```bash
swift build -c release
```

Expected: PASS without compiler or linker errors.

- [ ] **Step 5: Build, package, launch, and verify the exact app process**

```bash
./script/build_and_run.sh --verify
pgrep -f -x '/Users/qiujunjie/Desktop/CodexQ/dist/CodexQ.app/Contents/MacOS/CodexQ'
```

Expected: the script succeeds and `pgrep` prints the PID of the freshly launched branch app.

- [ ] **Step 6: Perform the visual acceptance pass**

Open the Token history window with a two-model dataset and verify:

- the model-distribution card ends shortly after the second row;
- increasing model rows increases the card height without changing full-width layout;
- all dynamic notes appear below the model card;
- `API 价格估算，非实际订阅账单` is the final page line;
- the footer remains readable in both light and dark system appearance.

Do not claim visual acceptance without inspecting the running window or receiving an updated screenshot from the user.
