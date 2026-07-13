# Token Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the latest three calendar months of daily account Token activity blocks to the existing CodexQ menu bar popover.

**Architecture:** Read `account/usage/read` from the same local Codex app-server used for rate limits, decode its daily buckets, and keep activity loading/error state independent from quota state. Pure calendar presentation logic produces three-month daily cells; a focused SwiftUI section renders them with one formatter and color scale.

**Tech Stack:** Swift 6, SwiftUI, Foundation `Calendar`, Swift Testing, local Codex app-server JSON-RPC.

## Global Constraints

- Daily mode shows only the latest 3 calendar months.
- All daily cells use the same token unit, formatter, and color thresholds.
- Missing dates render empty cells; no data may be fabricated.
- Token activity failure must not prevent quota display or refresh.
- Do not read or print authentication credentials.

---

### Task 1: Token activity model and calendar presentation

**Files:**
- Create: `Sources/CodexQ/Models/TokenActivity.swift`
- Create: `Tests/CodexQTests/TokenActivityTests.swift`

**Interfaces:**
- Produces: `TokenActivitySnapshot`, `TokenActivityDay`, `TokenActivityCell`, and `TokenActivityPresentation.dailyCells(snapshot:now:calendar:)`.
- Produces: `TokenCountFormatter.string(_:)` and `TokenActivityLevel.level(tokens:peakTokens:)` shared by all daily cells.

- [ ] **Step 1: Write failing decoding and date-window tests**

```swift
@Test func decodesAccountUsageBuckets() throws {
    let data = #"{"summary":{"peakDailyTokens":2000},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":1200}]}"#.data(using: .utf8)!
    let value = try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)
    #expect(value.days == [.init(startDate: "2026-07-12", tokens: 1200)])
}

@Test func dailyCellsKeepThreeCalendarMonthsAndFillMissingDays() throws {
    let cells = TokenActivityPresentation.dailyCells(snapshot: fixture, now: july13, calendar: utcCalendar)
    #expect(cells.first?.date == may1)
    #expect(cells.last?.date == july13)
    #expect(cells.first(where: { $0.date == missingDate })?.tokens == nil)
}

```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter TokenActivityTests`

Expected: compilation fails because the Token activity types do not exist.

- [ ] **Step 3: Implement the minimal models and pure presentation logic**

Decode `startDate` as the server-provided `yyyy-MM-dd` value, normalize all comparisons with `Calendar.startOfDay(for:)`, and compute the daily lower bound as the first day of the month two months before `now`.

Use one formatter for every daily cell:

```swift
enum TokenCountFormatter {
    static func string(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName)) + " tokens"
    }
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter TokenActivityTests && swift test`

Expected: all tests pass with no skipped tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexQ/Models/TokenActivity.swift Tests/CodexQTests/TokenActivityTests.swift
git commit -m "Add token activity calendar model"
```

### Task 2: Read account Token usage from app-server

**Files:**
- Modify: `Sources/CodexQ/Services/AppServerClient.swift`
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`

**Interfaces:**
- Consumes: `TokenActivitySnapshot: Decodable & Sendable`.
- Produces: `AppServerClient.readTokenActivity() async throws -> TokenActivitySnapshot`.

- [ ] **Step 1: Add a failing scripted app-server test**

Create a temporary executable fixture that responds to `initialize` and then `account/usage/read`. Assert that `readTokenActivity()` sends the exact method and decodes the returned daily bucket. Keep visible fixture values synthetic.

```swift
let snapshot = try await AppServerClient(executableURL: executable).readTokenActivity()
#expect(snapshot.days.first?.tokens == 1_200)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AppServerClientTests`

Expected: compilation fails because `readTokenActivity()` does not exist.

- [ ] **Step 3: Implement the minimal request**

Reuse the existing initialize/validate/read-response process path. Send:

```swift
["method": "account/usage/read", "id": 2]
```

Decode `response["result"]` as `TokenActivitySnapshot`. Add a dedicated localized missing-usage error only if the result is absent; do not change the existing rate-limit error behavior.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter AppServerClientTests && swift test`

Expected: all tests pass with no skipped tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexQ/Services/AppServerClient.swift Tests/CodexQTests/QuotaFormattingTests.swift
git commit -m "Read token activity from app server"
```

### Task 3: Store state and popover activity blocks

**Files:**
- Modify: `Sources/CodexQ/Stores/QuotaStore.swift`
- Create: `Sources/CodexQ/Views/TokenActivitySection.swift`
- Modify: `Sources/CodexQ/Views/QuotaPopoverView.swift`
- Create: `Tests/CodexQTests/TokenActivityViewTests.swift`

**Interfaces:**
- Consumes: `AppServerClient.readTokenActivity()`, `TokenActivityPresentation`, `TokenCountFormatter`, and `TokenActivityLevel`.
- Produces: `QuotaStore.tokenActivity`, `QuotaStore.tokenActivityErrorMessage`, and `TokenActivitySection`.

- [ ] **Step 1: Write failing store-policy and source-structure tests**

Test that activity failure is represented separately from quota failure and that the popover embeds `TokenActivitySection`. Test the daily square uses `TokenCountFormatter` and `TokenActivityLevel`, preventing unit or color drift.

```swift
#expect(source.contains("TokenActivitySection("))
#expect(dailyCellSource.contains("TokenCountFormatter.string"))
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter TokenActivityViewTests`

Expected: fails because the section and store properties do not exist.

- [ ] **Step 3: Implement independent refresh state**

In `QuotaStore.refresh()`, preserve the existing quota request and error behavior while starting Token activity concurrently with a separate loading/error state. Token activity must not delay the quota result, global refresh state, or next quota schedule. Publish the activity snapshot and error string on the main actor.

- [ ] **Step 4: Implement the SwiftUI section**

Add a compact “Token 活动” header and render the daily cells as a compact three-month calendar grid without a mode picker. Use semantic SwiftUI colors, a single square size/spacing, shared formatter/levels, `.help(...)` for date and token count, and an explicit unavailable state. Insert the section below quota/reset-credit content and above embedded settings; widen or height-adjust the popover only as required to prevent clipping.

- [ ] **Step 5: Run tests, build, and launch verification**

Run: `swift test && swift build && ./script/build_and_run.sh --verify`

Expected: no skipped/failing tests, build succeeds, and the `CodexQ` process is confirmed running.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexQ/Stores/QuotaStore.swift Sources/CodexQ/Views/TokenActivitySection.swift Sources/CodexQ/Views/QuotaPopoverView.swift Tests/CodexQTests/TokenActivityViewTests.swift
git commit -m "Show token activity in quota popover"
```
