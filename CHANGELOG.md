# Changelog

## [1.1.2] - 2026-08-24

- 在菜单弹窗底部的设置与刷新之间新增镂空柱状图入口，点击即可打开 Token 使用与成本统计窗口。

## [1.1.1] - 2026-08-11

- 修复自定义范围切换到累计范围时短暂显示无历史数据，保留加载状态并正确刷新图表。
- 修复日、月、年、订阅周期、累计和自定义口径的官方活动覆盖天数，今天、未来日期及不完整自然日不再计入。
- 日模式恢复系统日历选择器，月份选择器按内容收窄，日期文案改为“日期选择”。

## [1.1.0] - 2026-08-09

**重要版本：增加 Token 统计界面。**

- 新增独立 Token 统计窗口：从菜单弹窗中的 `Token 活动` 或 `Token 成本` 标题进入同一窗口。
- 支持按日、月、年、订阅周期、累计和自定义日期范围查看 Token 趋势、估算成本趋势与模型分布。
- 新增响应式图表、共享悬浮提示、模型 Token/成本切换，以及官方活动覆盖、未计价 Token 和数据来源说明。
- 日视图周期固定从周一开始，并修复日期输入框数字被遮挡的问题。
- 修复切换范围失败时显示旧范围数据、官方 Token 下调本机账本、订阅周期整日边界、非公历日期解析和跨账号额度缓存问题。

## [1.0.22] - 2026-08-03

- 修复 Token 活动热力图最右侧月份标签在月初只有一列时换行的问题，保持单行并向热力图内侧对齐。
- 修复菜单栏弹窗与状态栏按钮边界的对齐问题。

## [1.0.21] - 2026-07-31

- 同步 OpenAI 最新 GPT-5.6 Terra 与 Luna API 价格，Sol 价格保持不变。
- 按记录时间应用价格：2026-07-31 之前的历史用量继续使用原价格，不会被新价格重算。
- 更新 GPT-5.6 缓存写入与 Priority 估算，并增加新旧价格切换回归测试。
- 调整菜单弹窗定位：与菜单栏按钮左侧对齐，并保留顶部间距，避免边缘重合。
- 将菜单弹窗外框圆角调整为 8pt，使轮廓更利落。

## [1.0.18] - 2026-07-24

**重要版本：多设备同步。**

- 新增 iCloud Drive 多设备成本同步：同一 Codex 账号的多台 Mac 可以选择同一文件夹，合并各设备的脱敏 Token 记录。
- 多设备合并按稳定事件标识去重，并在多台设备同时初始化时采用文件夹中的同账号同步清单，避免重复命名空间。
- 同步文件变化会触发成本刷新；如果刷新正在进行，会在当前刷新完成后补刷一次，避免漏掉其他设备刚同步来的数据。
- 官方 Token 总数高于设备记录时，界面单独显示“官方差额”，并按设备记录平均单价估算缺少明细的部分。
- 同步设置只影响 Token 成本，不额外触发额度和 Token 活动刷新，减少不必要的 app-server 请求。

## [1.0.17] - 2026-07-23

- Show the plan type returned by app-server in the popover header and unify popover separators with the inset style.
- Read quota and Token activity through one app-server session. Keep the last successful Token activity and cost data visible if a refresh fails.
- Improve local Token cost parsing: skip unreadable session files, report partial data, show all included model details, and exclude models without official OpenAI API pricing from both Token totals and cost estimates.
