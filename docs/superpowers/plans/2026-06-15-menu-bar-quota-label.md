# 菜单栏额度文字实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让菜单栏始终显示完整图标，并在有效数据时于右侧显示 5 小时剩余百分比。

**Architecture:** 提取一个纯函数格式化菜单栏标题，便于覆盖有效、错误和陈旧状态。`StatusBarController` 改用可变长度状态栏项，以原生 `image + title` 显示内容，并继续通过现有 Combine 快照订阅更新。

**Tech Stack:** Swift 6、AppKit、Combine、Swift Testing

---

### Task 1: 标题规则与状态栏接入

**Files:**
- Create: `Sources/CodexQ/Support/StatusTitleFormatter.swift`
- Create: `Tests/CodexQTests/StatusTitleFormatterTests.swift`
- Modify: `Sources/CodexQ/App/StatusBarController.swift`

- [ ] 编写失败测试：有效百分比格式化为整数 `%`；无数据、错误或超过 10 分钟时返回空标题。
- [ ] 运行 `swift test --filter StatusTitleFormatterTests`，确认因格式化器不存在而失败。
- [ ] 实现最小纯函数 `StatusTitleFormatter.string(remainingPercent:lastUpdatedAt:error:now:)`。
- [ ] 将状态栏项改为 `NSStatusItem.variableLength`，按钮使用 `.imageLeading`。
- [ ] 快照更新时设置完整图标、标题和工具提示；错误或陈旧时清空标题。
- [ ] 运行筛选测试确认通过。
- [ ] 运行 `swift test`，记录任何既有无关失败。
- [ ] 运行 `./script/build_and_run.sh verify` 并确认进程正常。
