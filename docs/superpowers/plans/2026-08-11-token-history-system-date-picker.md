# Token History System Date Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the day-mode fixed-width custom date field with the natural-width macOS system date picker, label it “日期选择”, and preserve selection of the date whose natural week is queried.

**Architecture:** Keep `TokenHistoryStore.selectedDay` and all range/query logic unchanged. Change only the day branch of `TokenHistoryView.contextualControls`, remove the now-unused AppKit wrapper, and protect the visible wording, alignment, graphical system calendar popover, and absence of a fixed width with focused tests.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Swift Testing, AppKit/Vision rendering tests.

## Global Constraints

- The visible label is exactly `日期选择`.
- Use an intrinsic-width system button and SwiftUI popover containing a graphical `DatePicker` with `displayedComponents: .date`; macOS 14's compact style was verified to expose only a stepper and no calendar.
- Use intrinsic width via `fixedSize(horizontal: true, vertical: false)` and do not set a fixed width on the date picker.
- Preserve `TokenHistoryStore.selectedDay`, natural-week query semantics, all other range modes, charts, and window layout.
- Remove `TokenHistoryWeekDatePicker.swift` after its only caller is replaced.

---

### Task 1: Replace the day-mode date control

**Files:**
- Modify: `Tests/CodexQTests/TokenHistoryRenderingTests.swift`
- Modify: `Tests/CodexQTests/TokenHistoryViewTests.swift`
- Modify: `Sources/CodexQ/Views/TokenHistoryView.swift`
- Delete: `Sources/CodexQ/Views/TokenHistoryWeekDatePicker.swift`

**Interfaces:**
- Consumes: `TokenHistoryStore.selectedDay: Date` through `$store.selectedDay`.
- Produces: an intrinsic-width system button that opens a graphical system `DatePicker` bound to `selectedDay`, with the external visible label `日期选择`.

- [ ] **Step 1: Write the failing rendering and source-contract expectations**

Update the day rendering test to require the new visible label while preserving the literal selected day and same-row assertion:

```swift
@Test("日模式显示日期选择、所选日期且范围包含累计")
@MainActor
func dayModeShowsSystemDatePickerAndCumulativeRange() throws {
    let store = TokenHistoryStore(now: { self.startDate }, calendar: calendar)
    store.mode = .day

    let observations = try recognizedText(
        in: render(TokenHistoryView(store: store), width: 840, height: 720)
    )

    let label = try #require(observation(containing: "日期选择", in: observations))
    let dateControl = try #require(observation(containing: "2026", in: observations))
    let dateControlText = try #require(dateControl.topCandidates(1).first?.string)
    #expect(dateControlText.contains("9"))
    #expect(abs(label.boundingBox.midY - dateControl.boundingBox.midY) < 0.02)
    #expect(observation(containing: "累计", in: observations) != nil)
}
```

Replace the existing fixed-width source contract with the system-control contract:

```swift
@Test("日日期选择器使用系统日历菜单和内容固有宽度")
func dayPickerUsesSystemCalendarAndIntrinsicWidth() throws {
    let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
    let dayStart = try #require(viewSource.range(of: "case .day:"))
    let dayEnd = try #require(viewSource.range(
        of: "case .month:",
        range: dayStart.upperBound..<viewSource.endIndex
    ))
    let daySource = viewSource[dayStart.lowerBound..<dayEnd.lowerBound]

    #expect(daySource.contains("Text(\"日期选择\")"))
    #expect(daySource.contains("Button {"))
    #expect(daySource.contains(".popover(isPresented: $isDayCalendarPresented"))
    #expect(daySource.contains("DatePicker("))
    #expect(daySource.contains("selection: $store.selectedDay"))
    #expect(daySource.contains("displayedComponents: .date"))
    #expect(daySource.contains(".datePickerStyle(.graphical)"))
    #expect(daySource.contains(".labelsHidden()"))
    #expect(daySource.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(!daySource.contains("TokenHistoryWeekDatePicker"))
    #expect(!daySource.contains(".frame(width:"))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter dayModeShowsSystemDatePickerAndCumulativeRange
swift test --disable-sandbox --filter dayPickerUsesSystemCalendarAndIntrinsicWidth
```

Expected: the rendering test fails because `日期选择` is absent; the source-contract test fails because the day branch still uses `TokenHistoryWeekDatePicker` and `.frame(width: 124, height: 22)`.

- [ ] **Step 3: Implement the system date picker and remove the obsolete wrapper**

Replace the day branch with:

```swift
case .day:
    HStack(spacing: 8) {
        Text("日期选择")
        Button {
            isDayCalendarPresented.toggle()
        } label: {
            Text(store.selectedDay, format: .dateTime.year().month().day())
        }
        .popover(isPresented: $isDayCalendarPresented, arrowEdge: .bottom) {
            DatePicker(
                "日期选择",
                selection: $store.selectedDay,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    .fixedSize(horizontal: true, vertical: false)
```

Delete `Sources/CodexQ/Views/TokenHistoryWeekDatePicker.swift`; `rg -n "TokenHistoryWeekDatePicker" Sources Tests` must return no matches.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter dayModeShowsSystemDatePickerAndCumulativeRange
swift test --disable-sandbox --filter dayPickerUsesSystemCalendarAndIntrinsicWidth
swift test --disable-sandbox --filter TokenHistoryRenderingTests
swift test --disable-sandbox --filter TokenHistoryViewTests
```

Expected: every command exits 0; rendering finds `日期选择`, the selected date remains visible on the same row, and the day source contract has no fixed-width custom picker.

- [ ] **Step 5: Commit the implementation**

```bash
git add Sources/CodexQ/Views/TokenHistoryView.swift Sources/CodexQ/Views/TokenHistoryWeekDatePicker.swift Tests/CodexQTests/TokenHistoryRenderingTests.swift Tests/CodexQTests/TokenHistoryViewTests.swift
git commit -m "fix: restore system token history date picker"
```

### Task 2: Validate the complete macOS interaction

**Files:**
- Verify only; no additional source files.

**Interfaces:**
- Consumes: the signed `dist/CodexQ.app` produced by the project launch script.
- Produces: evidence that the full suite, release build, signed launch, visible day-mode layout, and system calendar menu all work.

- [ ] **Step 1: Run repository validation**

```bash
git diff --check
swift test --disable-sandbox --skip TokenCostBenchmarkTests
swift build --disable-sandbox -c release
./script/build_and_run.sh --verify
```

Expected: no whitespace errors; 237 or more non-benchmark tests pass; Release build exits 0; the app bundle is validly ad-hoc signed and its exact binary is running.

- [ ] **Step 2: Verify the visible interaction through macOS Accessibility**

Open the Token history window, select day mode, and inspect the accessibility tree. Confirm the window contains the static text `日期选择`, the date value, and a system date control. Activate the date control and confirm a calendar grid/menu appears; select a date and confirm the displayed date changes while the chart reloads.

- [ ] **Step 3: Verify final repository state**

```bash
git status --short --branch
git log -2 --oneline --decorate
```

Expected: branch `codex/fix-custom-to-cumulative-history`, no uncommitted changes, and the implementation commit above the design/plan commits.
