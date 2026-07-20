# CodexQ

<p align="center">
  <strong>Know how much Codex time you have left without leaving your current task.</strong>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="https://github.com/jedidevlab/CodexQ/releases/latest">Download latest</a>
</p>

CodexQ is a native macOS menu bar utility. It brings ChatGPT (formerly Codex) five-hour and weekly quota, remaining capacity, projected run-out time, and the past three months of Token activity into one floating panel.

## Your usage pace at a glance

- **Quota progress:** follow five-hour and weekly limits together; a temporarily absent five-hour window is clearly shown as unlimited.
- **Run-out projection:** see whether your current pace is sustainable and when the quota may run out.
- **Token activity:** review three months of daily activity plus the latest completed day and lifetime Token usage.
- **Timely alerts:** enable automatic refresh, launch at login, and quota warnings at 20%, 10%, or 5%.
- **Native experience:** built with SwiftUI and AppKit to stay available without interrupting your work.

## Download and install

Download the archive for your Mac from [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest):

| Mac | Archive |
| --- | --- |
| Apple Silicon | `CodexQ-1.0.12-arm64.zip` |
| Intel | `CodexQ-1.0.12-x86_64.zip` |

Unzip the archive, then move `CodexQ.app` to Applications.

> Release archives continue to use ad-hoc signing. They require no Apple developer account and are not notarized, so macOS may block the first launch.

If macOS blocks the first launch, try opening the app once, then go to System Settings → Privacy & Security, click Open Anyway, and confirm. Do this only when the archive came from this repository's official Release and you trust its source. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Requirements

- Apple Silicon or Intel Mac
- macOS 14 or later
- ChatGPT app installed in `/Applications` or `~/Applications` (the legacy Codex app is also supported)
- Swift 6 toolchain for local builds

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
./script/package_release.sh 1.0.12 arm64
./script/package_release.sh 1.0.12 x86_64
```

The archive is written to:

```text
dist/CodexQ-1.0.12-arm64.zip
dist/CodexQ-1.0.12-x86_64.zip
```

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are excluded from Git.

</details>
