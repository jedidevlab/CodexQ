# CodexQ

<p align="center">
  <strong>Know how much Codex time you have left without leaving your current task.</strong>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="https://github.com/jedidevlab/CodexQ/releases/latest">Download latest</a>
</p>

CodexQ is a native macOS menu bar utility. It brings ChatGPT (formerly Codex) five-hour and weekly quota, plan type, remaining capacity, projected run-out time, Token activity, and Token cost estimates into one floating panel.

## Your usage pace at a glance

- **Quota progress:** follow five-hour and weekly limits together; a temporarily absent five-hour window is clearly shown as unlimited.
- **Plan identification:** show the plan type returned by app-server in a compact native header.
- **Run-out projection:** see whether your current pace is sustainable and when the quota may run out.
- **Token activity:** review three months of daily activity plus the latest completed day and lifetime Token usage.
- **Token cost:** estimate yesterday, the current subscription period, and lifetime cost from local sessions, with optional multi-Mac merging through device records in a user-selected iCloud Drive folder.
- **Reliable refresh:** quota and Token activity share one app-server session; temporary refresh failures retain the last successful data with a clear status.
- **Timely alerts:** enable automatic refresh, launch at login, and quota warnings at 20%, 10%, or 5%.
- **Native experience:** built with SwiftUI and AppKit to stay available without interrupting your work.

## Download and install

Download the archive for your Mac from [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest):

| Mac | Archive |
| --- | --- |
| Apple Silicon | `CodexQ-1.0.22-arm64.zip` |
| Intel | `CodexQ-1.0.22-x86_64.zip` |

Unzip the archive, then move `CodexQ.app` to Applications.

> Release archives continue to use ad-hoc signing. They require no Apple developer account and are not notarized, so macOS may block the first launch.

If macOS blocks the first launch, try opening the app once, then go to System Settings → Privacy & Security, click Open Anyway, and confirm. Do this only when the archive came from this repository's official Release and you trust its source. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Requirements

- Apple Silicon or Intel Mac
- macOS 14 or later
- ChatGPT app installed in `/Applications` or `~/Applications` (the legacy Codex app is also supported)
- Swift 6 toolchain for local builds

## iCloud Cost Sync

Open settings from the bottom of the popover, enable `iCloud Cost Sync`, and select a dedicated folder in iCloud Drive. Other Macs using the same Codex account can select the same folder to merge their device records.

- Token activity is account data and is unaffected by this setting.
- With sync off, Token cost includes only the current Mac.
- With sync on, each Mac writes its own sanitized device records with only model names, timestamps, and Token counts; CodexQ does not copy raw sessions or login information.
- Multi-device merging deduplicates stable event identifiers, so the same session event is counted once even if it appears in more than one file.
- If official Token totals are higher than device records, CodexQ shows the missing portion separately as the official difference and estimates it from the average device-record rate.
- Sanitized sync files are not additionally encrypted by CodexQ. Do not choose a publicly shared folder.

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
./script/package_release.sh 1.0.22 arm64
./script/package_release.sh 1.0.22 x86_64
```

The archive is written to:

```text
dist/CodexQ-1.0.22-arm64.zip
dist/CodexQ-1.0.22-x86_64.zip
```

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are excluded from Git.

</details>
