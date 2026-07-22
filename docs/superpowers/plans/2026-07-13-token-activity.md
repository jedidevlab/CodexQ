# Token Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the CodexQ menu bar popover width with daily account Token activity blocks.

**Architecture:** Read `account/usage/read` from the same local Codex app-server used for rate limits, decode its daily buckets, and keep activity loading/error state independent from quota state. The SwiftUI layout derives its visible week count from the popover width, then pure calendar presentation logic produces that many weeks of daily cells for one continuous heatmap.

**Tech Stack:** Swift 6, SwiftUI, Foundation `Calendar`, Swift Testing, local Codex app-server JSON-RPC.

## Global Constraints

- Daily mode derives the visible week count from the popover width and fills missing older data with empty cells.
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

@Test func dailyCellsExpandToVisibleWeekCountAndEndToday() throws {
    let cells = TokenActivityPresentation.dailyCells(snapshot: fixture, now: july13, calendar: utcCalendar)
    #expect(cells.first?.date == eightWeekWindowStart)
    #expect(cells.last?.date == july13)
    #expect(cells.first(where: { $0.date == missingDate })?.tokens == nil)
    #expect(cells.first(where: { $0.date == july14 })?.tokens == nil)
}

```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter TokenActivityTests`

Expected: compilation fails because the Token activity types do not exist.

- [ ] **Step 3: Implement the minimal models and pure presentation logic**

Decode `startDate` as the server-provided Gregorian `yyyy-MM-dd` value in the local time zone, normalize all comparisons with `Calendar.startOfDay(for:)`, compute the lower bound from the visible week count derived from the popover width, and end the visible grid on today. The current 256 pt popover fits 16 week columns; the current column ends on today.

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

Add a compact “Token 活动” header and render the daily cells as one continuous heatmap that fills the popover content width, without a mode picker or separate month grids. Derive the week count and exact inter-column spacing from the popover width. Put month labels below the heatmap, centered across their week spans. In the header's trailing space, show the latest completed daily bucket and “累计 Token” as one compact line with no background or border; label the latest bucket as “昨日” when it matches the previous local calendar day, otherwise show its month/day. Omit the repeated `tokens` suffix from these two visible values, while missing values display “暂无数据”. Use semantic SwiftUI colors, a single square size/spacing, shared formatter/levels, `.help(...)` for date and token count, and an explicit unavailable state. Insert the section below quota/reset-credit content and above embedded settings; adjust the compact popover only as required to prevent clipping.

- [ ] **Step 5: Run tests, build, and launch verification**

Run: `swift test && swift build && ./script/build_and_run.sh --verify`

Expected: no skipped/failing tests, build succeeds, and the `CodexQ` process is confirmed running.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexQ/Stores/QuotaStore.swift Sources/CodexQ/Views/TokenActivitySection.swift Sources/CodexQ/Views/QuotaPopoverView.swift Tests/CodexQTests/TokenActivityViewTests.swift
git commit -m "Show token activity in quota popover"
```
