# Changelog

## [1.0.18] - 2026-07-24

**重要版本：多设备同步。**

- 新增 iCloud Drive 多设备成本同步：同一 Codex 账号的多台 Mac 可以选择同一文件夹，合并各设备的脱敏 Token 记录。
- 多设备合并按稳定事件标识去重，并在多台设备同时初始化时采用文件夹中的同账号同步清单，避免重复命名空间。
- 同步文件变化会触发成本刷新；如果刷新正在进行，会在当前刷新完成后补刷一次，避免漏掉其他设备刚同步来的数据。
- 官方 Token 总数高于设备记录时，界面单独显示“官方差额”，并按设备记录平均单价估算缺少明细的部分。
- 同步设置只影响 Token 成本，不额外触发额度和 Token 活动刷新，减少不必要的 app-server 请求。

## [1.0.17] - 2026-07-23

**Milestone:** Reliable quota data and pricing-only Token cost accounting.

- Show the plan type returned by app-server in the popover header and unify popover separators with the inset style.
- Read quota and Token activity through one app-server session. Keep the last successful Token activity and cost data visible if a refresh fails.
- Improve local Token cost parsing: skip unreadable session files, report partial data, show all included model details, and exclude models without official OpenAI API pricing from both Token totals and cost estimates.
