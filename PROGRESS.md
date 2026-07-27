# 执行进度

## 任务 0：基线核对（完成但存在已记录差异）

- 目标：在不改变任何可见行为、文案、交互或刷新节奏的前提下，加快真实本机会话日志的 Token 成本与活动加载。
- 顺序：核对基线 → 从 `237a3e1` 建立 `perf/lightweight` → 先以真实数据基准锁定正确性与耗时 → 最小实现优化 → 启动/面板验证 → 全量验证与提交。
- 最大风险：增量解析遗漏追加、截断或重写后的 JSONL 记录，造成“快而错”；基准必须固定记录数和成本合计。
- 所有 SwiftPM 命令均带 `--disable-sandbox`。
- `swift test --disable-sandbox`：176 tests passed，0 skipped（2026-07-27）。
- `swift build -c release --disable-sandbox`：成功；可执行文件 2,342,176 bytes。
- 差异已写入 `BLOCKED.md`：当前 sessions 为 71 文件、127,265,025 bytes；`dist/` 为 4.2M。因此仅在当前不变数据快照内比较任务 2 前后数据。

## 任务 1：完成

- 初始 `main` 为 `237a3e1`；已建立 `perf/lightweight`，未推送远端。由于任务 0 要求新增进度和阻塞文档，当前 `git status --short` 除任务书认可的 `.workbuddy/` 外还显示这两个待提交文档。

## 任务 2：基准建立中

- 已新增 `TokenCostBenchmarkTests`，首次直接读取活动中的 `~/.codex/sessions` 时发现测试过程本身会使会话日志增长，10 次一致性断言依次出现成本差值 0.037617 至 0.314381；此结果不能作为实现回归。
- 改为每次基准先从真实 `~/.codex/sessions` 建立只读临时快照、结束即删除；这样 5 冷读/5 温读共享同一真实数据快照，避免把运行中的日志追加误判为解析差异。
- 基线（`swift test --disable-sandbox --filter TokenCostBenchmarkTests`，全绿）：5,553 条去重记录，成本 $453.2710615；冷读中位数 42,236.618219ms，温读中位数 122.791913ms。冷读超过 1 秒，因此保留 ≥30% 相对提速目标。
- 实现：将互不依赖的 JSONL 文件解析改为任务组并发，缓存写回、去重、排序、错误统计仍在读取器 actor 内按原逻辑执行；没有改动 UI、刷新周期或网络读取链路。
- 优化后（同一命令，全绿）：5,582 条去重记录，成本 $453.9372015；冷读中位数 20,964.800071ms，温读 118.185939ms。相对本轮基线冷读下降 50.36%，温读下降 3.75%。会话源在两轮间增长，故两轮绝对记录/成本不同；每轮均以其冻结的真实源快照做独立全量解析断言，确保该轮 reader 与全量基准完全一致。
- 反向验证：临时在并发路径将每个文件的 `records` 改为 `dropFirst()`，基准如预期变红，10 次成本断言均报差值 `$5.568402`（输出含 `failed after 179.408 seconds`）；已立即还原为完整 records，待最终全绿复验。

## 任务 3：验证中

- 未改动 `Sources/CodexQ/Views/` 或 `Sources/CodexQ/App/`；`git diff main...HEAD -- Sources/CodexQ/Views/ Sources/CodexQ/App/` 为空。
- 受删除禁令影响未运行会重建并删除 `dist` 的既有启动脚本（见 `BLOCKED.md`）。直接运行已构建可执行文件的进程存活测量为 110.814ms、114.362ms、111.095ms，均不慢于任务书历史约 0.33s 基线。该测量命令的末尾等待到主动停止的进程而以 143 返回，但三次 `pgrep` 存活测量均已输出。

## 收尾验证

- `swift test --disable-sandbox`：177 tests passed，0 skipped（新增的真实数据基准测试使总数从冻结的 176 增至 177；原有测试未修改）。
- `swift build -c release --disable-sandbox`：成功；可执行文件 2,371,760 bytes，低于 2,459,285 bytes（原基线 +5%）上限。
- 再次全量测试中的基准：5,630 条去重记录、$455.234458；冷读 21,344.597875ms、温读 127.034902ms，均在独立冻结快照内通过全量解析成本一致性断言。
- 已提交：`d280e34 perf: parse token session files concurrently`（本地 `perf/lightweight`，未推送）。

## 后续缺陷修复

- 审查发现基准原先只断言成本，无法独立证明读取器的去重记录数相等。`TokenCostSnapshot` 现保存 `sourceRecordCount`；读取器传入本地去重记录数，reconcile 保持该值，真实基准同时断言记录数与成本。
- 验证：`swift test --disable-sandbox --filter TokenCostTests` 23 passed；`swift test --disable-sandbox --filter TokenCostBenchmarkTests` 全绿，5,670 条记录、$457.311073，冷读中位数 30,371.855088ms、温读 158.545927ms。
