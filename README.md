# CodexQ

CodexQ is a lightweight macOS menu bar app for monitoring Codex usage quotas.
It shows 5-hour and weekly quota progress, remaining percentage, projected
run-out time, refresh status, and optional quota warnings.

## Features

- macOS menu bar quota indicator
- 5-hour and weekly quota progress bars
- Pace marker and projected run-out time
- Manual and automatic refresh
- Optional launch at login
- Optional quota warning notifications
- Native SwiftUI/AppKit floating panel

## Requirements

- macOS 13 or later
- Apple Silicon Mac for the `arm64` release build, or Intel Mac for the
  `x86_64` release build
- Swift 6 toolchain
- Codex app installed at `/Applications/Codex.app`

## Download

Choose the release archive that matches your Mac:

- Apple Silicon Mac (M1 or later): `CodexQ-1.0.0-arm64.zip`
- Intel Mac: `CodexQ-1.0.0-x86_64.zip`

Unzip the archive, then move `CodexQ.app` to Applications.

The release builds are ad-hoc signed and not notarized. On first launch, macOS
may require right-clicking the app and choosing Open.

发布版本使用 ad-hoc 签名，未经过 notarization 公证。首次启动时，macOS
可能需要右键点击 app 并选择打开。

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

Generate a ZIP archive for GitHub Releases using the current Mac's architecture:

```bash
./script/package_release.sh 1.0.0
```

Pass an architecture explicitly when needed:

```bash
./script/package_release.sh 1.0.0 arm64
./script/package_release.sh 1.0.0 x86_64
```

The archive is written to:

```text
dist/CodexQ-1.0.0-<arch>.zip
```

## Packaging Note

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for
development use. Generated build artifacts are intentionally excluded from Git.
