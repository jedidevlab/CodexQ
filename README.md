# CodexQ

<p align="center">
  <strong>不用打开额外页面，一眼看清 Codex 还能用多久。</strong>
</p>

<p align="center">
  <a href="README.en.md">English</a> ·
  <a href="https://github.com/jedidevlab/CodexQ/releases/latest">下载最新版</a>
</p>

CodexQ 是一款原生 macOS 菜单栏工具。它把ChatGPT（原Codex）5 小时与周限额、剩余额度、预计耗尽时间和近三个月 Token 活动集中在一个浮动面板中显示。

## 一眼掌握使用节奏

- **额度进度**：同时查看 5 小时与周限额；临时没有 5 小时限制时会明确显示“无限制”。
- **耗尽预测**：根据当前使用节奏判断额度是否够用，并显示预计耗尽时间。
- **Token 活动**：查看近三个月每日活动、最近完整日与累计 Token 用量。
- **及时提醒**：支持自动刷新、登录时启动，以及 20% / 10% / 5% 额度预警。
- **原生体验**：使用 SwiftUI 与 AppKit 构建，常驻菜单栏，不打断当前工作。

## 下载与安装

从 [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest) 下载 Apple Silicon 安装包：

`CodexQ-1.0.9-arm64.zip`

解压后，将 `CodexQ.app` 移入“应用程序”文件夹。

> v1.0.9 及更早版本使用 ad-hoc 签名，未经过 notarization 公证，不适合作为正式全球发行包。后续正式版本应使用下方 Developer ID＋公证流程生成。

## 使用条件

- Apple Silicon Mac
- macOS 14 或更新版本
- 已安装 ChatGPT app，支持 `/Applications` 或 `~/Applications`（同时兼容旧版 Codex app）
- 本地构建需要 Swift 6 工具链

## 本地运行

```bash
./script/build_and_run.sh
```

验证 app 是否成功启动：

```bash
./script/build_and_run.sh --verify
```

运行测试：

```bash
swift test
```

<details>
<summary><strong>维护者：打包 Release</strong></summary>

<br>

先把公证凭证保存到钥匙串：

```bash
xcrun notarytool store-credentials codexq-notary
```

使用 Developer ID Application 身份生成、提交公证并装订正式发行包：

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Example" \
NOTARY_PROFILE="codexq-notary" \
./script/package_release.sh 1.0.10 arm64
```

仅做本地打包验证时，必须明确允许 ad-hoc 签名：

```bash
ALLOW_ADHOC=1 ./script/package_release.sh 1.0.10 arm64
```

生成文件位于：

```text
dist/CodexQ-1.0.10-arm64.zip
```

开发运行脚本会在 `dist/CodexQ.app` 生成本地 `.app` bundle；构建产物不会提交到 Git。

</details>
