# CodexQ 图标实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成并接入一套开放式圆环 Q 图标，分别适用于 macOS App 安装包与菜单栏。

**Architecture:** 使用同一开放式圆环 Q 作为视觉母题，但输出两份独立资源：App 图标为深灰圆角方形底上的白色 Q，菜单栏图标为透明背景的纯白模板 PNG。菜单栏渲染器固定显示完整图形，不再根据额度裁切；额度继续由工具提示和弹窗表达。

**Tech Stack:** Swift 6、AppKit、SwiftPM 资源、PNG/ICNS、内置 ImageGen、Sharp 图像处理、Swift Testing

---

### Task 1: 生成并整理图标资产

**Files:**
- Create: `Sources/CodexQ/Resources/AppIcon.png`
- Create: `Sources/CodexQ/Resources/MenuBarIcon.png`
- Remove after replacement: `Sources/CodexQ/Resources/OpenAI-white-monoblossom.png`

- [ ] **Step 1: 使用内置 ImageGen 生成视觉母版**

使用 `logo-brand` 提示词生成开放式圆环 Q：

```text
Asset type: macOS app and menu bar icon master
Subject: a bold geometric letter Q built from an open circular ring
Composition: deliberate upper-right progress gap, short lower-right Q tail
Style: flat vector-like silhouette, optically corrected for 16 px
Color: pure white symbol on a flat chroma-key background
Avoid: text, shadows, gradients in the symbol, thin details, magnifying-glass appearance
```

预期：生成的 Q 在缩小后仍能清晰辨识，尾部短且不与放大镜混淆。

- [ ] **Step 2: 去除色键背景**

运行：

```bash
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input tmp/imagegen/codexq-icon-source.png \
  --out tmp/imagegen/codexq-icon-transparent.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
```

预期：输出包含 Alpha 通道，四角完全透明，图形边缘无色键残留。

- [ ] **Step 3: 生成菜单栏资源**

使用 Sharp 将可见 RGB 像素统一为纯白，只保留 Alpha 抗锯齿，并输出：

```text
Sources/CodexQ/Resources/MenuBarIcon.png
512 x 512 px
纯白可见像素
透明背景
```

- [ ] **Step 4: 生成 App 图标资源**

将同一白色 Q 居中放置在 1024 x 1024 px 的中性深灰圆角方形上，输出：

```text
Sources/CodexQ/Resources/AppIcon.png
1024 x 1024 px
```

- [ ] **Step 5: 生成小尺寸预览并检查**

生成：

```text
tmp/imagegen/MenuBarIcon-16.png
tmp/imagegen/MenuBarIcon-18.png
tmp/imagegen/MenuBarIcon-32.png
```

预期：三个尺寸均能读作开放式圆环 Q，右上缺口和右下短尾清晰。

### Task 2: 固定菜单栏图标渲染行为

**Files:**
- Create: `Tests/CodexQTests/StatusIconRendererTests.swift`
- Modify: `Sources/CodexQ/Support/StatusIconRenderer.swift`

- [ ] **Step 1: 编写失败测试**

添加测试，分别以 10% 和 100% 渲染同一源图，并比较输出 Alpha 像素：

```swift
@Test("菜单栏图标不随额度裁切")
func quotaDoesNotCropMenuBarIcon() throws {
    let source = makeOpaqueSourceImage()
    let lowQuota = StatusIconRenderer.image(source: source, remainingPercent: 10)
    let fullQuota = StatusIconRenderer.image(source: source, remainingPercent: 100)

    #expect(try alphaValues(of: lowQuota) == alphaValues(of: fullQuota))
}
```

- [ ] **Step 2: 运行测试并确认失败**

运行：

```bash
swift test --filter StatusIconRendererTests
```

预期：FAIL，因为当前实现会根据 `remainingPercent` 纵向裁切源图。

- [ ] **Step 3: 实现固定完整图标**

将 `StatusIconRenderer.image` 改为忽略额度参数，仅把源图完整绘制到 15 x 15 pt 区域，并保留：

```swift
image.isTemplate = true
```

- [ ] **Step 4: 运行测试并确认通过**

运行：

```bash
swift test --filter StatusIconRendererTests
```

预期：PASS，10% 与 100% 输出一致。

### Task 3: 接入菜单栏与 App 图标

**Files:**
- Modify: `Sources/CodexQ/App/StatusBarController.swift`
- Modify: `script/build_and_run.sh`

- [ ] **Step 1: 更新菜单栏资源引用**

将资源加载改为：

```swift
Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
```

缺失资源错误同步改为 `Missing MenuBarIcon.png`。

- [ ] **Step 2: 更新 App 图标打包来源**

将脚本中的图标母版改为：

```bash
SOURCE_ICON="$ROOT_DIR/Sources/CodexQ/Resources/AppIcon.png"
```

保留现有 `sips` 多尺寸生成和 `iconutil` 打包流程。

- [ ] **Step 3: 删除被替代的旧资源**

删除：

```text
Sources/CodexQ/Resources/OpenAI-white-monoblossom.png
```

- [ ] **Step 4: 检查所有资源引用**

运行：

```bash
rg -n 'OpenAI-white-monoblossom|MenuBarIcon|AppIcon.png' Sources script
```

预期：只存在新资源引用，不存在旧 OpenAI 图片引用。

### Task 4: 验证与运行

**Files:**
- Verify: `Sources/CodexQ/Resources/AppIcon.png`
- Verify: `Sources/CodexQ/Resources/MenuBarIcon.png`
- Verify: `dist/CodexQ.app/Contents/Resources/AppIcon.icns`

- [ ] **Step 1: 验证菜单栏像素**

使用 Sharp 检查：

```text
像素尺寸为 512 x 512
存在 Alpha 通道
所有 Alpha > 0 的像素 RGB 均为 255,255,255
```

- [ ] **Step 2: 运行完整测试**

运行：

```bash
swift test
```

预期：所有测试通过；若既有 app-server 临时文件测试出现竞态，单独记录，不将其归因于图标改动。

- [ ] **Step 3: 打包并启动**

运行：

```bash
./script/build_and_run.sh verify
```

预期：构建成功，生成 `AppIcon.icns`，`CodexQ` 进程保持运行。

- [ ] **Step 4: 核对最终产物**

运行：

```bash
file dist/CodexQ.app/Contents/Resources/AppIcon.icns
pgrep -x CodexQ
```

预期：识别为 macOS icon 文件，并返回正在运行的进程 ID。
