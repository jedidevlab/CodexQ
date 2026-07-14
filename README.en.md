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
| Apple Silicon | `CodexQ-1.0.9-arm64.zip` |
| Intel | `CodexQ-1.0.9-x86_64.zip` |

Unzip the archive, then move `CodexQ.app` to Applications.

> Releases are ad-hoc signed and not notarized. On first launch, macOS may require right-clicking the app and choosing Open.

## Requirements

- macOS 13 or later
- ChatGPT app installed at `/Applications/ChatGPT.app` (legacy `/Applications/Codex.app` is also supported)
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

Generate a ZIP archive for GitHub Releases using the current Mac architecture:

```bash
./script/package_release.sh 1.0.9
```

Pass an architecture explicitly when needed:

```bash
./script/package_release.sh 1.0.9 arm64
./script/package_release.sh 1.0.9 x86_64
```

The archive is written to:

```text
dist/CodexQ-1.0.9-<arch>.zip
```

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are excluded from Git.

</details>
