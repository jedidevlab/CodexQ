# CodexQ

<p align="center">
  <strong>不用打开额外页面，一眼看清 Codex 还能用多久。</strong>
</p>

<p align="center">
  <a href="README.en.md">English</a> ·
  <a href="https://github.com/jedidevlab/CodexQ/releases/latest">下载最新版</a>
</p>

CodexQ 是一款原生 macOS 菜单栏工具。它把ChatGPT（原Codex）5 小时与周限额、剩余额度、预计耗尽时间和每日 Token 活动集中在一个浮动面板中显示。

## 一眼掌握使用节奏

- **额度进度**：同时查看 5 小时与周限额；临时没有 5 小时限制时会明确显示“无限制”。
- **耗尽预测**：根据当前使用节奏判断额度是否够用，并显示预计耗尽时间。
- **Token 活动**：查看按弹窗宽度自动扩展的每日热力图、最近完整日与累计 Token 用量。
- **及时提醒**：支持自动刷新、登录时启动，以及 20% / 10% / 5% 额度预警。
- **原生体验**：使用 SwiftUI 与 AppKit 构建，常驻菜单栏，不打断当前工作。

## 下载与安装

从 [GitHub Releases](https://github.com/jedidevlab/CodexQ/releases/latest) 下载与你的 Mac 匹配的安装包：

| Mac | 安装包 |
| --- | --- |
| Apple Silicon | `CodexQ-1.0.14-arm64.zip` |
| Intel | `CodexQ-1.0.14-x86_64.zip` |

解压后，将 `CodexQ.app` 移入“应用程序”文件夹。

> 安装包沿用 ad-hoc 签名，无需 Apple 开发者账号，也未经过 notarization 公证。因此首次打开时可能被 macOS 拦截。

如果首次打开时被 macOS 拦截，请先尝试打开一次，再前往“系统设置”→“隐私与安全”，点击“仍要打开”并确认。仅当安装包来自本仓库的官方 Release 且你信任其来源时这样操作。参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

## 使用条件

- Apple Silicon 或 Intel Mac
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

生成 ad-hoc 签名的安装包：

```bash
./script/package_release.sh 1.0.14 arm64
./script/package_release.sh 1.0.14 x86_64
```

生成文件位于：

```text
dist/CodexQ-1.0.14-arm64.zip
dist/CodexQ-1.0.14-x86_64.zip
```

开发运行脚本会在 `dist/CodexQ.app` 生成本地 `.app` bundle；构建产物不会提交到 Git。

</details>
