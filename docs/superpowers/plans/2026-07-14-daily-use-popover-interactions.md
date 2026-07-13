# CodexQ Daily Popover Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CodexQ popover quieter during normal use, accurately reflect all refresh work, hide low-frequency settings by default, and pause auto-close during interaction.

**Architecture:** Keep view state in `QuotaPopoverView`, expose reset expansion through a binding, and report three interaction reasons to `StatusBarController`. Put Pace copy and auto-close eligibility in small pure helpers so behavior can be tested without driving AppKit windows.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Swift Package Manager

---

### Task 1: Quiet Pace Presentation

**Files:**
- Modify: `Sources/CodexQ/Support/PaceFormatter.swift`
- Modify: `Sources/CodexQ/Views/QuotaPopoverView.swift`
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`

- [ ] **Step 1: Write failing Pace presentation tests**

Add tests that construct `QuotaProjection` values directly and require normal and reserve states to return `nil`, while deficit states keep the existing copy:

```swift
@Test("正常与余量状态不显示 Pace 文案")
func quietPaceHidesNonDeficitCopy() {
    #expect(PaceFormatter.status(.init(
        reservePercent: 0,
        expectedRemainingPercent: 60,
        deltaPercent: 1,
        etaSeconds: nil
    )) == nil)
    #expect(PaceFormatter.status(.init(
        reservePercent: 8,
        expectedRemainingPercent: 60,
        deltaPercent: -8,
        etaSeconds: nil
    )) == nil)
}

@Test("超额状态保留风险 Pace 文案")
func deficitPaceKeepsRiskCopy() {
    #expect(PaceFormatter.status(.init(
        reservePercent: 0,
        expectedRemainingPercent: 60,
        deltaPercent: 5,
        etaSeconds: 45 * 60
    )) == "超额 5% · 0h45m 后用完")
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter QuotaFormattingTests
```

Expected: compilation fails because `PaceFormatter.status` does not exist.

- [ ] **Step 3: Implement the minimal Pace helper and use it in the view**

Add:

```swift
static func status(_ projection: QuotaProjection) -> String? {
    guard projection.isInDeficit else { return nil }
    let percent = Int(projection.displayPercent.rounded())
    if let eta = projection.etaSeconds {
        return "超额 \(percent)% · \(PaceFormatter.eta(eta))"
    }
    return "进度超额 \(percent)%"
}
```

In `QuotaRow`, render the label only when the helper returns text:

```swift
if let projection,
   let paceText = PaceFormatter.status(projection) {
    Text(paceText)
        .font(.caption)
        .foregroundStyle(.red)
}
```

Remove the view-local `paceText(for:)` function.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run `swift test --filter QuotaFormattingTests`.

Expected: all `QuotaFormattingTests` pass.

- [ ] **Step 5: Commit the Pace change**

```bash
git add Sources/CodexQ/Support/PaceFormatter.swift Sources/CodexQ/Views/QuotaPopoverView.swift Tests/CodexQTests/QuotaFormattingTests.swift
git commit -m "Quiet normal quota pace status"
```

### Task 2: Combined Refresh State And Collapsed Settings

**Files:**
- Modify: `Sources/CodexQ/Views/QuotaPopoverView.swift`
- Modify: `Sources/CodexQ/Views/ResetCreditsSection.swift`
- Modify: `Tests/CodexQTests/TokenActivityViewTests.swift`
- Modify: `Tests/CodexQTests/ResetCreditTests.swift`

- [ ] **Step 1: Write failing view structure tests**

Add source-backed tests that require:

```swift
#expect(source.contains("store.isRefreshing || store.isTokenActivityRefreshing"))
#expect(source.contains(".disabled(isAnyRefreshing)"))
#expect(source.contains("@State private var isSettingsExpanded = false"))
#expect(source.contains("if isSettingsExpanded"))
#expect(source.contains("gearshape.fill"))
#expect(source.contains("interactionDidChange(.settings, isSettingsExpanded)"))
```

Update the reset UI test to require external expansion state:

```swift
#expect(source.contains("@Binding var isExpanded: Bool"))
#expect(!source.contains("@State private var isExpanded"))
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter TokenActivityViewTests
swift test --filter ResetCreditUISafetyTests
```

Expected: new expectations fail because combined refresh, the settings gear, and reset binding are absent.

- [ ] **Step 3: Implement view state and controls**

Add to `QuotaPopoverView`:

```swift
let contentDidChange: () -> Void
let interactionDidChange: (PopoverInteraction, Bool) -> Void
@State private var isResetCreditsExpanded = false
@State private var isSettingsExpanded = false

private var isAnyRefreshing: Bool {
    store.isRefreshing || store.isTokenActivityRefreshing
}
```

Pass `$isResetCreditsExpanded` into `ResetCreditsSection`. Render `EmbeddedSettingsView` only when `isSettingsExpanded`. Add a bottom button whose icon switches between `gearshape` and `gearshape.fill`, and use `isAnyRefreshing` for the refresh spinner and disabled state.

Report changes with:

```swift
.onHover { interactionDidChange(.pointer, $0) }
.onChange(of: isResetCreditsExpanded) { isExpanded in
    interactionDidChange(.resetCredits, isExpanded)
    contentDidChange()
}
.onChange(of: isSettingsExpanded) { isExpanded in
    interactionDidChange(.settings, isExpanded)
    contentDidChange()
}
.onChange(of: store.isPopoverPresented) { isPresented in
    guard !isPresented else { return }
    isResetCreditsExpanded = false
    isSettingsExpanded = false
}
```

Change `ResetCreditsSection` to:

```swift
struct ResetCreditsSection: View {
    let summary: ResetCreditsSummary
    @Binding var isExpanded: Bool
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the two focused suites again.

Expected: both pass.

- [ ] **Step 5: Commit the view change**

```bash
git add Sources/CodexQ/Views/QuotaPopoverView.swift Sources/CodexQ/Views/ResetCreditsSection.swift Tests/CodexQTests/TokenActivityViewTests.swift Tests/CodexQTests/ResetCreditTests.swift
git commit -m "Collapse settings and track all refreshes"
```

### Task 3: Interaction-Aware Auto-Close

**Files:**
- Create: `Sources/CodexQ/Support/PopoverAutoClosePolicy.swift`
- Modify: `Sources/CodexQ/App/StatusBarController.swift`
- Create: `Tests/CodexQTests/PopoverAutoClosePolicyTests.swift`
- Modify: `Tests/CodexQTests/StatusPanelPositionerTests.swift`

- [ ] **Step 1: Write failing policy and integration tests**

Create tests for the desired pure API:

```swift
@Test("仅在全部刷新结束且没有交互时启动自动关闭")
func schedulesOnlyWhenIdle() {
    #expect(PopoverAutoClosePolicy.shouldSchedule(
        isQuotaRefreshing: false,
        isTokenActivityRefreshing: false,
        activeInteractions: []
    ))
    #expect(!PopoverAutoClosePolicy.shouldSchedule(
        isQuotaRefreshing: true,
        isTokenActivityRefreshing: false,
        activeInteractions: []
    ))
    #expect(!PopoverAutoClosePolicy.shouldSchedule(
        isQuotaRefreshing: false,
        isTokenActivityRefreshing: true,
        activeInteractions: []
    ))
    for interaction in PopoverInteraction.allCases {
        #expect(!PopoverAutoClosePolicy.shouldSchedule(
            isQuotaRefreshing: false,
            isTokenActivityRefreshing: false,
            activeInteractions: [interaction]
        ))
    }
}
```

Add a controller source test requiring `activeInteractions`, `interactionDidChange`, the policy call, and `activeInteractions.removeAll()` in close handling.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter PopoverAutoClosePolicyTests
swift test --filter StatusPanelPositionerTests
```

Expected: compilation or assertions fail because the policy and controller integration do not exist.

- [ ] **Step 3: Implement the policy**

Create:

```swift
enum PopoverInteraction: CaseIterable, Hashable, Sendable {
    case pointer
    case resetCredits
    case settings
}

enum PopoverAutoClosePolicy {
    static func shouldSchedule(
        isQuotaRefreshing: Bool,
        isTokenActivityRefreshing: Bool,
        activeInteractions: Set<PopoverInteraction>
    ) -> Bool {
        !isQuotaRefreshing
            && !isTokenActivityRefreshing
            && activeInteractions.isEmpty
    }
}
```

- [ ] **Step 4: Wire the controller to the policy**

Maintain:

```swift
private var activeInteractions = Set<PopoverInteraction>()
```

Update the view callback, both refresh subscriptions, presentation path, and close path. Centralize scheduling in:

```swift
private func updateAutoClose() {
    guard panel.isVisible else { return }
    guard PopoverAutoClosePolicy.shouldSchedule(
        isQuotaRefreshing: store.isRefreshing,
        isTokenActivityRefreshing: store.isTokenActivityRefreshing,
        activeInteractions: activeInteractions
    ) else {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        return
    }
    scheduleAutoClose()
}
```

Interaction callbacks insert or remove a reason, then call `updateAutoClose()`. `panelDidClose()` clears the set. Keep `StatusPanel.resignKey()` unchanged so focus loss remains an immediate close.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run both focused suites again.

Expected: all policy and controller integration tests pass.

- [ ] **Step 6: Commit the auto-close change**

```bash
git add Sources/CodexQ/Support/PopoverAutoClosePolicy.swift Sources/CodexQ/App/StatusBarController.swift Tests/CodexQTests/PopoverAutoClosePolicyTests.swift Tests/CodexQTests/StatusPanelPositionerTests.swift
git commit -m "Pause popover auto-close during interaction"
```

### Task 4: Full Verification

**Files:**
- Verify only: all project files and generated `dist/CodexQ.app`

- [ ] **Step 1: Run the complete test suite**

Run `swift test`.

Expected: all suites pass with zero failures.

- [ ] **Step 2: Build Release**

Run `swift build -c release`.

Expected: build completes successfully.

- [ ] **Step 3: Check the diff**

Run `git diff --check` and inspect `git status --short`.

Expected: no whitespace errors; only the four pre-existing unrelated files remain uncommitted.

- [ ] **Step 4: Build and run the app bundle**

Run `./script/build_and_run.sh --verify` and `pgrep -x CodexQ`.

Expected: signing verification succeeds and a CodexQ process is running.
