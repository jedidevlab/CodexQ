# Global Release Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent globally distributed builds from failing because the companion app is undiscoverable, the advertised platform is unsupported, or the release is not signed and notarized.

**Architecture:** Keep `AppServerClient` responsible for deterministic executable candidates. Keep packaging policy in `script/package_release.sh`, with production signing required by default and an explicit ad-hoc escape hatch for local validation.

**Tech Stack:** Swift 6, Swift Testing, SwiftPM, bash, codesign, notarytool, stapler

## Global Constraints

- Preserve existing user Token activity changes.
- Preserve legacy `/Applications/Codex.app` discovery.
- New public releases target macOS 14 and Apple Silicon because the required ChatGPT macOS app has that official minimum.
- Never claim notarization without a Developer ID identity and completed notarytool submission.

---

### Task 1: Discover user-level companion app installations

**Files:**
- Modify: `Tests/CodexQTests/QuotaFormattingTests.swift`
- Modify: `Sources/CodexQ/Services/AppServerClient.swift`

- [ ] Change `defaultCandidatesCoverCurrentAndLegacyApps()` to require system and user `Applications` paths for ChatGPT and legacy Codex, using an injected home directory.
- [ ] Run `swift test --filter AppServerClientTests.defaultCandidatesCoverCurrentAndLegacyApps` and verify failure because only system paths exist.
- [ ] Add `defaultExecutableURLs(homeDirectory:)` and make the default property call it with `FileManager.default.homeDirectoryForCurrentUser`.
- [ ] Re-run the focused test and verify it passes.

### Task 2: Align public platform claims with the required companion app

**Files:**
- Modify: `Tests/CodexQTests/BuildScriptPackagingTests.swift`
- Modify: `Package.swift`
- Modify: `script/build_and_run.sh`
- Modify: `script/package_release.sh`
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] Add source-contract tests requiring `.macOS(.v14)`, `MIN_SYSTEM_VERSION="14.0"`, arm64-only release packaging, and Apple Silicon/macOS 14 documentation.
- [ ] Run `swift test --filter BuildScriptPackagingTests` and verify failures against the current macOS 13 and x86_64 contract.
- [ ] Update the package, scripts, and both READMEs to the verified platform contract.
- [ ] Re-run `swift test --filter BuildScriptPackagingTests` and verify it passes.

### Task 3: Fail loud unless a public release is signed and notarized

**Files:**
- Modify: `Tests/CodexQTests/BuildScriptPackagingTests.swift`
- Modify: `script/package_release.sh`
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] Add source-contract tests requiring `CODE_SIGN_IDENTITY`, `NOTARY_PROFILE`, hardened runtime, timestamping, notarytool submission, stapling, Gatekeeper assessment, and explicit `ALLOW_ADHOC=1` handling.
- [ ] Run `swift test --filter BuildScriptPackagingTests` and verify the new expectations fail.
- [ ] Validate signing configuration before building. Require production credentials by default; allow ad-hoc packaging only when explicitly requested.
- [ ] Sign production builds with hardened runtime and timestamp, submit the zip, staple the app, validate the ticket, recreate the zip, and assess it with Gatekeeper.
- [ ] Document production and local-validation commands in both READMEs.
- [ ] Run focused and complete tests, then build an arm64 ad-hoc validation package and inspect its architecture and signature.
