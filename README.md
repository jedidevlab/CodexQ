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
- Swift 6 toolchain
- Codex app installed at `/Applications/Codex.app`

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

Generate an arm64 ZIP archive for GitHub Releases:

```bash
./script/package_release.sh 1.0.0
```

The archive is written to:

```text
dist/CodexQ-1.0.0-arm64.zip
```

## Packaging Note

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for
development use. Generated build artifacts are intentionally excluded from Git.
