# ChatGPT App-Server Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore quota refreshes with the current ChatGPT desktop app while retaining compatibility with the legacy Codex app.

**Architecture:** `AppServerClient` owns an ordered candidate list and resolves the first executable at refresh time. Existing JSON-RPC and injected-test-executable behavior remain unchanged.

**Tech Stack:** Swift 6, Foundation `Process`, Swift Testing, SwiftPM.

## Global Constraints

- Prefer `/Applications/ChatGPT.app/Contents/Resources/codex`.
- Fall back to `/Applications/Codex.app/Contents/Resources/codex`.
- Preserve the existing app-server JSON-RPC protocol and timeout behavior.
- Do not change unrelated quota or UI behavior.

---

### Task 1: Executable discovery regression coverage

**Files:**
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`
- Modify: `Sources/CodexQ/Services/AppServerClient.swift`

**Interfaces:**
- Consumes: `AppServerClient(executableURL:responseTimeout:)`
- Produces: `AppServerClient.firstExecutableURL(in:fileManager:) -> URL?`

- [x] Add tests proving the first executable candidate wins, a non-executable first candidate falls back to the second, and no executable candidate returns `nil`.
- [x] Add a regression test requiring the missing-executable message to name both ChatGPT and legacy Codex.
- [x] Run `swift test --filter AppServerClientTests` and confirm the new tests fail because candidate resolution does not exist.
- [x] Add current and legacy default candidate paths, resolve them on each request, and update the missing error text.
- [x] Run `swift test --filter AppServerClientTests` and confirm all client tests pass.

### Task 2: Requirements documentation

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

**Interfaces:**
- Consumes: the supported executable candidate paths from Task 1
- Produces: current installation requirements for users

- [x] Replace the legacy-only requirement with ChatGPT current-path guidance and Codex legacy fallback guidance in both languages.
- [x] Search the project for stale assertions that Codex must exist only at `/Applications/Codex.app`.

### Task 3: Validate the development app bundle

**Files:**
- Modify: `Tests/CodexQTests/BuildScriptPackagingTests.swift`
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Consumes: the completed local `.app` bundle
- Produces: an ad-hoc-signed, strictly verified bundle before launch

- [x] Add a failing packaging test requiring local signing and signature verification.
- [x] Add the same ad-hoc signing and strict verification used by the release script.
- [x] Run `swift test --filter BuildScriptPackagingTests` and require 0 failures.

### Task 4: Full verification and local runtime

**Files:**
- Verify only: project and generated `dist/CodexQ.app`

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: a tested, runnable local app bundle

- [x] Run `swift test` and require 0 failures and 0 skipped tests.
- [x] Run `swift build -c release` and require exit code 0.
- [x] Run `./script/build_and_run.sh --verify` and require a running CodexQ process.
- [x] Verify the current ChatGPT app-server directly with `account/rateLimits/read`.
- [x] Inspect `git diff --check`, `git diff`, and `git status --short` for unintended changes.
