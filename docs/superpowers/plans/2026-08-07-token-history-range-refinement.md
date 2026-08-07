# Token History Range Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make “日” show the selected natural week, add an all-history “累计” range, and constrain the subscription-cycle picker width.

**Architecture:** Keep range intent in `TokenHistorySelection`, but resolve the data-dependent cumulative interval inside the aggregator after records and official activity are available. Reuse the existing adaptive custom-range granularity thresholds. Keep view changes limited to the picker option, contextual label, and a fixed subscription control width.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Swift Testing, Vision-based macOS rendering tests.

## Global Constraints

- Do not add a “周” range mode.
- “日” always covers exactly the natural week containing the selected date and uses daily buckets.
- “累计” runs from the earliest valid local record or official activity day through today.
- Preserve all existing month, year, subscription, and custom semantics.
- Do not modify pricing, source routing, or unrelated dashboard layout.

---

### Task 1: Range semantics

**Files:**
- Modify: `Sources/CodexQ/Models/TokenHistory.swift`
- Modify: `Sources/CodexQ/Services/TokenHistoryAggregator.swift`
- Test: `Tests/CodexQTests/TokenHistoryQueryTests.swift`

**Interfaces:**
- Produces: `TokenHistoryRangeMode.cumulative`, `TokenHistorySelection.cumulative`, and cumulative interval resolution in `TokenHistoryAggregator.snapshot(...)`.
- Preserves: `TokenHistorySelection.interval(calendar:subscriptionPeriods:)` for non-data-dependent ranges.

- [ ] **Step 1: Write failing query tests**

Add tests asserting that `.day(date)` resolves to the seven-day natural week containing `date`; `.cumulative` starts at the earliest local or official date, ends after today, returns today for empty input, and selects day/month/year granularity at the existing thresholds.

- [ ] **Step 2: Run the focused tests and observe failure**

Run: `swift test --disable-sandbox --filter TokenHistoryQueryTests`

Expected: failures because day still resolves to one day and cumulative cases do not exist.

- [ ] **Step 3: Implement the minimal range logic**

Add `cumulative` to both enums. Resolve `.day` with `calendar.dateInterval(of: .weekOfYear, for:)`. In the aggregator, resolve `.cumulative` using the earliest valid `TokenUsageRecord.timestamp` or parsed official activity day, and an exclusive end equal to the start of tomorrow. Reuse a shared adaptive-granularity helper for `.custom` and `.cumulative`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --disable-sandbox --filter TokenHistoryQueryTests`

Expected: all query tests pass.

### Task 2: Range controls and width

**Files:**
- Modify: `Sources/CodexQ/Stores/TokenHistoryStore.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryView.swift`
- Modify: `Tests/CodexQTests/TokenHistoryRenderingTests.swift`

**Interfaces:**
- Consumes: `TokenHistoryRangeMode.cumulative` and `TokenHistorySelection.cumulative`.
- Produces: no contextual control for cumulative, “所在周” copy for day, and a subscription picker constrained to 280 points.

- [ ] **Step 1: Write failing rendering/store tests**

Add assertions that the picker exposes “累计” but not “周”, day mode renders “所在周”, store maps cumulative mode to `.cumulative`, and the subscription picker remains bounded in an 840-point window.

- [ ] **Step 2: Run the focused tests and observe failure**

Run: `swift test --disable-sandbox --filter 'TokenHistory(Rendering|View|Store)Tests'`

Expected: failures because cumulative is not wired and the subscription picker is unconstrained.

- [ ] **Step 3: Implement the minimal UI/store changes**

Map cumulative mode in `TokenHistoryStore.selection`. Change the day date-picker label to “所在周”, add an empty cumulative branch, and replace the subscription picker’s minimum width with `.frame(width: 280)`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --disable-sandbox --filter 'TokenHistory(Rendering|View|Store)Tests'`

Expected: all focused tests pass.

### Task 3: Full verification and delivery

**Files:**
- Verify all modified source, test, specification, and plan files.

**Interfaces:**
- Consumes: completed range and UI behavior.
- Produces: a signed, launched `dist/CodexQ.app` and a clean committed worktree.

- [ ] **Step 1: Check the diff**

Run: `git diff --check` and inspect `git diff` for unrelated changes.

- [ ] **Step 2: Run all stable tests**

Run: `swift test --disable-sandbox --skip TokenCostBenchmarkTests`

Expected: zero failures and no skipped stable tests.

- [ ] **Step 3: Build Release**

Run: `swift build --disable-sandbox -c release`

Expected: exit 0.

- [ ] **Step 4: Build, sign, launch, and verify the app**

Run: `./script/build_and_run.sh --verify`

Expected: build succeeds, signature validates, and the actual history window exposes the revised controls.

- [ ] **Step 5: Commit the scoped implementation**

Stage only the Token history source/tests and commit with `fix: refine token history ranges`.
