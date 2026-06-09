# narrowing 记录

这份记录总结 `migrate_pages()` syscall route 候选当前的源码定位状态。它不是新的 timing
证据。

## 现有证据支持什么

- 主信号来自 same-PREEMPT lab clean timing：`v7.0.9-preempt` 在 primary 1/2/4 CPU
  matrix 中显著慢于 `v6.12.77-preempt`、`v6.18.19-preempt` 和 `v6.19.9-preempt`。
- state-shape 干净：4096 pages 都迁到目标 node，`move_failed_pages_avg=0`，
  `expected_match_ratio=100`。
- direct function-entry coverage 证明 workload 命中 `mm/mempolicy.c` syscall frontend
  和 `mm/migrate.c` migration core。
- ftrace 是 attribution evidence，不是 clean timing。第一轮 ftrace 把额外 profiled cost
  指向 `migrate_pages_batch()` / `move_to_new_folio()` 调用范围；后续 reduced-function
  ftrace 没有复现 move/copy 的大幅增加，只看到 move/copy 约 +2%、queueing 前段约 +7%。

## 已弱化或排除的线索

- `mm/mempolicy.c` 的 v6.19 -> v7.0 可见差异主要是 policy lifetime/RCU freeing、
  nodemask helper 改写、weighted interleave 相关分配方式调整。reduced ftrace 中
  queueing 前段的增加相对 copy/move 主体仍较小，暂时不足以让 frontend 成为首要解释。
- `mm/migrate.c` 中最显眼的 v7 差异是 `migrate_folio_move()` 新增 deferred-split
  bookkeeping。v7 attribution-only A/B 删除该逻辑后只改变约 1-2%，低于 5% 门槛，
  因此这是主信号的 negative attribution result。
- `move_to_new_folio()` 本体在本地 v6.19 -> v7.0 snapshot diff 中没有变化。因此 ftrace
  结果只能作为 cost-center/call-range 线索，不能作为 line-level culprit。
- `remove_migration_ptes()` 的 flag 从 `RMP_*` 转为 `TTU_*`，但当前 anonymous base-page
  workload 走到 base-page migration path 里的 `remove_migration_ptes(src, dst, 0)`，
  暂时不像主解释。对 `832d95b5314e` 做 v7 revert-style A/B 后，
  `move_ns_per_page` 变化低于 1%（约 -0.46% mean / -0.82% median），因此现在也属于
  negative attribution lead。
- 更细的 ftrace profile 显示 copy range 很大，尤其是 `folio_mc_copy()` /
  `copy_mc_to_kernel()`，但该 ftrace run 的版本方向没有匹配 clean timing，只能作为构成
  线索。v7-only clean A/B 把 `folio_mc_copy()` 替换为 `folio_copy()` 后，
  `move_ns_per_page` 反而慢约 7.5%，所以这个简单 copy-path 假设是 negative
  attribution result，不是修复方案。

## 剩余缺口

当前最稳妥的表述是：

```text
mempolicy migrate_pages() syscall route plus mm/migrate.c migration core
```

而不是 `mempolicy.c` 单文件 regression，也不是 line-level culprit report。剩下最有价值的
工作是避开 deferred-split、folio-copy、RMP-TTU 这三条 negative lead 后，对 migration
core 以及附近 rmap/folio migration helper 做更低扰动的 perf-style attribution 或更深入
commit-level narrowing。当前 lab host 以 `perf_event_paranoid=4` 阻挡该用户使用 perf，
所以下一个可实际推进的本地步骤原本是 source-reasoned commit/A-B narrowing。但第二轮
source scan 没发现更贴合当前 anonymous base-page migration route 的强单点候选；在没有
perf 权限或维护者指路前，不建议继续跑低相关 A/B。
