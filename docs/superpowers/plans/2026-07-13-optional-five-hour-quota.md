# Optional 5-hour Quota Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep quota refresh working when Codex returns only the weekly quota window.

**Architecture:** The five-hour `QuotaWindow` becomes optional; the weekly window remains the minimum valid response. The popover displays a neutral unavailable state and the status bar falls back to weekly remaining percentage.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Swift Package Manager.

## Global Constraints

- Do not synthesize a five-hour percentage or reset time.
- Preserve behavior when both windows are supplied.
- A response without a weekly window remains invalid.
- Do not change transport, refresh timing, reset credits, or notifications.

---

### Task 1: Decode a weekly-only response

**Files:**
- Modify: `Sources/CodexQ/Models/QuotaSnapshot.swift`
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`

- [x] **Step 1: Add the failing test**

```swift
@Test("仅周限额时仍生成可用快照")
func weeklyOnlyWindowProducesSnapshot() throws {
    let limits = RateLimitSnapshot(
        primary: RateLimitWindow(usedPercent: 1, windowDurationMins: 10_080, resetsAt: nil),
        secondary: nil
    )
    let snapshot = try #require(limits.quotaSnapshot)
    #expect(snapshot.fiveHour == nil)
    #expect(snapshot.weekly.usedPercent == 1)
}
```

- [x] **Step 2: Verify red**

Run: `swift test --filter QuotaFormattingTests/weeklyOnlyWindowProducesSnapshot`

Expected: fails because the current model requires both windows.

- [x] **Step 3: Implement the minimum model change**

Make `QuotaSnapshot.fiveHour` optional and have `RateLimitSnapshot.quotaSnapshot` require only `weekly`.

- [x] **Step 4: Verify green**

Run: `swift test --filter QuotaFormattingTests/weeklyOnlyWindowProducesSnapshot`

Expected: passes.

### Task 2: Present the missing window safely

**Files:**
- Modify: `Sources/CodexQ/Models/QuotaSnapshot.swift`
- Modify: `Sources/CodexQ/Views/QuotaPopoverView.swift`
- Modify: `Sources/CodexQ/App/StatusBarController.swift`
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`

- [x] **Step 1: Add the failing test**

```swift
@Test("5小时窗口缺失时状态栏使用周限额")
func weeklyQuotaIsStatusFallback() {
    let snapshot = QuotaSnapshot(
        fiveHour: nil,
        weekly: .init(usedPercent: 22, resetsAt: nil, durationMinutes: 10_080)
    )
    #expect(snapshot.statusRemainingPercent == 78)
}
```

- [x] **Step 2: Verify red**

Run: `swift test --filter QuotaFormattingTests/weeklyQuotaIsStatusFallback`

Expected: fails because the fallback property does not exist.

- [x] **Step 3: Implement the minimum presentation change**

Add `statusRemainingPercent`, conditionally render `QuotaRow` for a present 5-hour window, render `5 小时` plus `无限制` otherwise, and pass the fallback percentage to the status bar.

- [x] **Step 4: Verify all behavior**

Run: `swift test && swift build -c release && git diff --check`

Expected: all tests and the release build pass with no whitespace errors.
