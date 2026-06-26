# CodexQ

[English](README.en.md)

CodexQ 是一款 macOS 菜单栏工具，用于实时查看 Codex 额度使用情况，展示 5 小时与周限额进度、剩余额度、预测耗尽时间，并支持额度预警与自动刷新。

## 功能

- macOS 菜单栏额度指示器
- 5 小时与周限额进度条
- 剩余额度百分比
- 按当前使用节奏预测耗尽时间
- 手动刷新与自动刷新
- 登录时启动
- 额度预警通知
- 原生 SwiftUI/AppKit 浮动窗口

## 系统要求

- macOS 13 或更新版本
- 已安装 Codex app，路径为 `/Applications/Codex.app`
- 如需本地构建，需要 Swift 6 工具链

## 下载

在 GitHub Releases 中选择与你的 Mac 匹配的安装包：

- Apple Silicon Mac：`CodexQ-1.0.2-arm64.zip`
- Intel Mac：`CodexQ-1.0.2-x86_64.zip`

下载后解压，将 `CodexQ.app` 移动到“应用程序”文件夹。

当前发布包使用 ad-hoc 签名，未经过 notarization 公证。首次启动时，macOS 可能需要右键点击 app 并选择“打开”。

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

## 打包 Release

按当前 Mac 架构生成 GitHub Release zip：

```bash
./script/package_release.sh 1.0.2
```

也可以显式指定架构：

```bash
./script/package_release.sh 1.0.2 arm64
./script/package_release.sh 1.0.2 x86_64
```

生成文件位于：

```text
dist/CodexQ-1.0.2-<arch>.zip
```

## 打包说明

开发运行脚本会在 `dist/CodexQ.app` 生成本地 `.app` bundle。构建产物不会提交到 Git。
