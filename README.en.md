# CodexQ

[中文](README.md)

CodexQ is a macOS menu bar utility for monitoring Codex quota and token usage in real time. It shows 5-hour and weekly quota progress, remaining quota, projected run-out time, and supports quota warnings and automatic refresh.

## Features

- macOS menu bar quota indicator
- 5-hour and weekly quota progress bars
- Shows the 5-hour quota as unlimited when that window is temporarily absent, while weekly quota refresh continues
- Remaining quota percentage
- Projected run-out time based on current usage pace
- Daily token activity for the latest three months, plus yesterday and lifetime token usage
- Manual and automatic refresh
- Launch at login
- Quota warning notifications
- Native SwiftUI/AppKit floating panel

## Requirements

- macOS 13 or later
- ChatGPT app installed at `/Applications/ChatGPT.app` (legacy `/Applications/Codex.app` is also supported)
- Swift 6 toolchain for local builds

## Download

Choose the release archive that matches your Mac:

- Apple Silicon Mac: `CodexQ-1.0.8-arm64.zip`
- Intel Mac: `CodexQ-1.0.8-x86_64.zip`

Unzip the archive, then move `CodexQ.app` to Applications.

The release builds are ad-hoc signed and not notarized. On first launch, macOS may require right-clicking the app and choosing Open.

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

## Package a Release

Generate a ZIP archive for GitHub Releases using the current Mac architecture:

```bash
./script/package_release.sh 1.0.8
```

Pass an architecture explicitly when needed:

```bash
./script/package_release.sh 1.0.8 arm64
./script/package_release.sh 1.0.8 x86_64
```

The archive is written to:

```text
dist/CodexQ-1.0.8-<arch>.zip
```

## Packaging Note

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are intentionally excluded from Git.
