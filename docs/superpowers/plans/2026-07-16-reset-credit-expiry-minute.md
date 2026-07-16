# Reset Credit Expiry Minute Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display each reset credit expiry as `M/d HH:mm` in the machine's current time zone.

**Architecture:** Keep the existing `ResetCreditPresentation` boundary and `expiresAt` data flow. Change only its `DateFormatter` pattern and the focused presentation test.

**Tech Stack:** Swift 6, Foundation `DateFormatter`, Swift Testing, Swift Package Manager

## Global Constraints

- Preserve the existing `expiresAt` parsing and reset-credit layout.
- Keep “无到期时间” when no expiry exists.
- Do not change refresh, cache, reset-count, or other quota-time behavior.
- Preserve unrelated uncommitted Token activity changes.

---

### Task 1: Format reset-credit expiry to the minute

**Files:**
- Modify: `Tests/CodexQTests/ResetCreditTests.swift`
- Modify: `Sources/CodexQ/Support/ResetCreditPresentation.swift`

**Interfaces:**
- Consumes: `ResetCredit.expiresAt: Date?` and `ResetCreditPresentation.init(summary:timeZone:)`
- Produces: `ResetCreditPresentation.Row.detail: String` in `将于 M/d HH:mm 到期` format

- [ ] **Step 1: Write the failing test**

Change the fixed UTC+8 expectation in `presentsBackendTitleAndExpiry()` to:

```swift
#expect(presentation.rows.first?.detail == "将于 7/17 12:00 到期")
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter ResetCreditPresentationTests.presentsBackendTitleAndExpiry`

Expected: FAIL because the implementation still returns `将于 7/17 到期`.

- [ ] **Step 3: Implement the minimal formatter change**

In `ResetCreditPresentation.init(summary:timeZone:)`, set:

```swift
formatter.dateFormat = "M/d HH:mm"
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter ResetCreditPresentationTests.presentsBackendTitleAndExpiry`

Expected: PASS.

Run: `swift test`

Expected: all tests PASS with none skipped.

- [ ] **Step 5: Commit only the two implementation files**

```bash
git add Tests/CodexQTests/ResetCreditTests.swift Sources/CodexQ/Support/ResetCreditPresentation.swift
git commit -m "Show reset credit expiry time"
```
