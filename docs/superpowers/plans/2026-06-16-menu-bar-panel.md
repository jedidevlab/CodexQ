# 菜单栏浮动面板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用无标题浮动面板替换菜单栏 Popover。

**Architecture:** 新增纯定位器计算面板坐标并覆盖测试；新增 `NSPanel` 子类处理失焦关闭；控制器继续托管 SwiftUI 内容和现有自动关闭任务。

**Tech Stack:** AppKit、SwiftUI、Swift Testing

---

### Task 1: 面板定位与生命周期

- [ ] 为图标下方定位和屏幕边界限制编写失败测试。
- [ ] 实现 `StatusPanelPositioner`。
- [ ] 实现失焦自动关闭的无标题 `StatusPanel`。
- [ ] 将 `StatusBarController` 从 `NSPopover` 切换到 `StatusPanel`。
- [ ] 保留自动关闭和 `isPopoverPresented` 数据语义。
- [ ] 运行全量测试并启动 App。
