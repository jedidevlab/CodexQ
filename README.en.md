# CodexQ

<p align="center">
  <strong>Know how much Codex time you have left without leaving your current task.</strong>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="https://github.com/jedidevlab/CodexQ/releases/latest">Download latest</a>
</p>

CodexQ is a native macOS menu bar utility. It brings ChatGPT (formerly Codex) five-hour and weekly quota, plan type, remaining capacity, projected run-out time, and Token activity into one floating panel.

## Current version: v1.2.3 — **Clearer Token activity heatmap**

This release refines the Token activity heatmap with a gray base and four soft blue levels that remain distinct against the background. It retains official account-level Token activity from v1.2.2. Existing local history and settings are not deleted.

## Your usage pace at a glance

- **Quota progress:** follow five-hour and weekly limits together; a temporarily absent five-hour window is clearly shown as unlimited.
- **Plan identification:** show the plan type returned by app-server in a compact native header.
- **Run-out projection:** see whether your current pace is sustainable and when the quota may run out.
- **Token activity:** review three months of daily activity plus the latest completed day and lifetime Token usage.
- **Clear heatmap colors:** distinguish a gray base and four soft blue activity levels in both light and dark appearances.
- **History analysis:** click `Token Activity` to open day, month, year, subscription-cycle, cumulative, and custom-range Token trends.
- **Reliable refresh:** quota and Token activity share one app-server session; temporary refresh failures retain the last successful data with a clear status.
- **Timely alerts:** enable automatic refresh, launch at login, and quota warnings at 20%, 10%, or 5%.
- **Native experience:** built with SwiftUI and AppKit to stay available without interrupting your work.

## Download and install

Download the archive for your Mac from [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest):

| Mac | Archive |
| --- | --- |
| Apple Silicon | `CodexQ-1.2.3-arm64.zip` |
| Intel | `CodexQ-1.2.3-x86_64.zip` |

Unzip the archive, then move `CodexQ.app` to Applications.

> Release archives continue to use ad-hoc signing. They require no Apple developer account and are not notarized, so macOS may block the first launch.

If macOS blocks the first launch, try opening the app once, then go to System Settings → Privacy & Security, click Open Anyway, and confirm. Do this only when the archive came from this repository's official Release and you trust its source. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Requirements

- Apple Silicon or Intel Mac
- macOS 14 or later
- ChatGPT app installed in `/Applications` or `~/Applications` (the legacy Codex app is also supported)
- Swift 6 toolchain for local builds

## Token History Data Notes

- Token activity is account-level daily data from app-server; historical availability depends on its retained daily coverage.
- CodexQ no longer infers Tokens from credits, quota percentages, or model names, and no longer scans local sessions for API-cost estimates.
- Cost history and sync preferences created by earlier releases remain in place, but this release no longer reads, displays, or updates them.

## Build and Run

```bash
./script/build_and_run.sh
```

Verify that the app starts:

```bash
./script/build_and_run.sh --verify
```

Run tests:

```bash
swift test
```

<details>
<summary><strong>Maintainers: package a release</strong></summary>

<br>

Build an ad-hoc signed archive:

```bash
./script/package_release.sh 1.2.3 arm64
./script/package_release.sh 1.2.3 x86_64
```

After publishing and verifying the GitHub Release, install the archive for this Mac:

```bash
./script/install_release.sh "dist/CodexQ-1.2.3-$(uname -m).zip"
```

The installer verifies the bundle version, architecture, and signature, replaces the old app, and starts the new one. If startup fails, it restores the previous app. User settings and history remain in place.

The archive is written to:

```text
dist/CodexQ-1.2.3-arm64.zip
dist/CodexQ-1.2.3-x86_64.zip
```

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are excluded from Git.

</details>
