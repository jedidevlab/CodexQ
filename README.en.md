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

Download the Apple Silicon archive from [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest):

`CodexQ-1.0.9-arm64.zip`

Unzip the archive, then move `CodexQ.app` to Applications.

> v1.0.9 and earlier are ad-hoc signed and not notarized, so they are not suitable as normal global releases. Future production releases should use the Developer ID and notarization flow below.

## Requirements

- Apple Silicon Mac
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

Store notarization credentials in Keychain first:

```bash
xcrun notarytool store-credentials codexq-notary
```

Build, notarize, staple, and validate a production archive with a Developer ID Application identity:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Example" \
NOTARY_PROFILE="codexq-notary" \
./script/package_release.sh 1.0.10 arm64
```

For local packaging validation only, explicitly allow ad-hoc signing:

```bash
ALLOW_ADHOC=1 ./script/package_release.sh 1.0.10 arm64
```

The archive is written to:

```text
dist/CodexQ-1.0.10-arm64.zip
```

The helper script builds a local `.app` bundle in `dist/CodexQ.app` for development use. Generated build artifacts are excluded from Git.

</details>
