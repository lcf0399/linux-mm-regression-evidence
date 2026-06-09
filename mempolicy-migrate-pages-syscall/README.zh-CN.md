# mempolicy migrate_pages() syscall route 候选证据包

这个目录是给维护者看的 compact evidence bundle，目标是一个由源码路径校准的 NUMA
页面迁移 synthetic workload。

当前范围：

- workload 类型：source-calibrated synthetic userspace micro-workload。
- 入口路径：`mm/mempolicy.c` 中的 `migrate_pages()` syscall。
- 计时工作：mempolicy syscall frontend 加上 `mm/migrate.c` migration core。
- 场景：双 NUMA node guest，16 MiB anonymous mapping 先放到 node 0，然后用
  `migrate_pages()` 迁到 node 1。
- 主指标：`move_ns_per_page`，越低越好。它表示 `migrate_pages()` syscall 本身的耗时
  除以 4096 pages；后面的 `move_pages(..., nodes=NULL, status=...)` 只是 placement /
  state 校验，不计入这个 timing 指标。

这不是生产应用回归报告，也不是 generic `mempolicy` regression claim。它是强候选，
但在作为正式上游 regression report 前，仍需要更多 attribution 或 commit-level
narrowing。

## 当前发现

在 lab x86/QEMU direct-boot 环境下，primary 1/2/4 CPU clean timing matrix 中，
`v7.0.9-preempt` 的 `migrate_pages()` syscall route 显著慢于
`v6.12.77-preempt`、`v6.18.19-preempt` 和 `v6.19.9-preempt`。

primary 1/2/4 CPU matrix，median `move_ns_per_page`：

```text
CPU   v7.0.9-preempt   v6.12.77-preempt   v6.18.19-preempt   v6.19.9-preempt
  1        17439              11914              11719              12110
  2        18137              12403              12110              12793
  4        17997              12804              12305              12696
```

该矩阵的 state-shape checks 干净：

```text
expected_match_ratio=100
unexpected_results=0
queried_pages_avg=4096
post_target_pages_avg=4096
move_failed_pages_avg=0
```

8/16 CPU extended run 对 v6.18/v6.19 方向仍然支持，但因为 guest memory 随 CPU 数变化，
它们只作为 supporting evidence，不作为 primary formal matrix：

```text
CPU/mem        v7.0.9 mean   v6.18.19 mean   v6.19.9 mean
8 CPU/16 GiB       19267          12591.6         13580.6
16 CPU/32 GiB      19299.2        13016.6         13802.4
```

## 归因状态

direct function-entry coverage 已确认 workload 命中：

- `mm/mempolicy.c` syscall frontend 和 queueing path；以及
- `mm/migrate.c` migration core，包括 `migrate_pages_batch()`、
  `migrate_folio_move()`、`move_to_new_folio()`、`remove_migration_pte()`。

ftrace attribution runs 的结论是 mixed。第一轮 function-profile 把额外 profiled cost
指向 migration core，尤其是 `migrate_pages_batch()` / `move_to_new_folio()` 调用范围；
后续 reduced function set 没有复现 move/copy 的大幅增加，只显示较小的 move/copy
变化和中等幅度的 queueing frontend 增加。这些都只能作为 cost-center/构成线索，
不能证明 line-level culprit。

一个明显的 v7 差异是 `migrate_folio_move()` 中新增 deferred-split bookkeeping。
对 v7 做 attribution-only A/B 后，删除这段逻辑只让 `move_ns_per_page` 变化约 1-2%，
低于 5% actionable threshold，所以当前是 negative attribution result。

后续更细的 ftrace 确认 copy path 是 migration-core profiled cost 的大头，但该 run 对
instrumentation 很敏感，没有保持 clean timing 的版本方向，因此只作为构成/归因线索。
另一个 v7-only clean A/B 把 `folio_mc_copy()` 替换为 `folio_copy()` 后，
`move_ns_per_page` 反而慢约 7.5%，所以“machine-check-safe copy 本身导致变慢”这个
简单假设也被弱化；这不是 proposed fix。

第一条 commit inventory 候选 `832d95b5314e`（`migrate: replace RMP_ flags with
TTU_ flags`）也做了 v7 revert-style attribution A/B。revert tree 的
`move_ns_per_page` 变化低于 1%（约 -0.46% mean / -0.82% median），因此这条
flag-conversion 线索对当前 anonymous base-page workload 也是 negative lead。

## 内容

- `reproducer/`：standalone C reproducer 和 lab host NUMA2 smoke 结果。
- `lab-validation/`：1/2/4 CPU clean timing summary CSV，以及 8/16 CPU extended summary。
- `attribution/`：coverage summary、ftrace profiles、deferred-split / folio-copy /
  RMP-TTU A/B summary、reduced-function ftrace，以及当前 narrowing notes。
- `patches/`：用于 deferred-split、folio-copy 和 RMP-TTU hypothesis 的
  attribution-only patch。

## 限制

- 这是 synthetic/source-calibrated workload，不是生产 NUMA 应用报告。
- 当前最佳描述是 `mempolicy syscall frontend plus migration core`，不是
  `mempolicy-only`。
- ftrace 是 attribution evidence，不是 clean timing evidence。
- 当前 lab host 上该用户受 `perf_event_paranoid=4` 限制，host-side perf-style
  attribution 暂时无法直接补。
- 已完成 `832d95b5314e` 的第一条 commit-inventory/revert A/B，但还没有完整
  commit-level bisect 或最终 culprit。
