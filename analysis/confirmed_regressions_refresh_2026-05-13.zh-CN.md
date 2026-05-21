# 2026-05-13 formal refresh 历史摘要

本文件是 2026-05-13 formal refresh 的精简历史摘要。它保留原始上游报告前的
clean timing 背景，但不替代当前 workload README。

当前引用顺序：

- `madvise-pageout-thp-noswap-refault/README.zh-CN.md`
- `mprotect-shared-dirty-toggle/README.zh-CN.md`
- 顶层 `README.zh-CN.md`

## 运行口径

- 平台：lab server container
- guest memory：`QEMU_MEM_MB=14336`
- guest CPUs：`QEMU_SMP=1/2/4`
- repeat：每个版本/场景 9 次
- 方法：coverage/performance split；performance run 关闭 coverage
- kernel config：SMP + ACPI + ACPI_PROCESSOR
- kernel cmdline：不使用 `noapic`

## mprotect / shared_dirty_full_toggle_64m

`cycle_ns_per_page`，越低越好：

| CPU | v6.12 | v6.19 | delta | reliability |
|---:|---:|---:|---:|---|
| 1 | 346.8 | 578.1 | -40.0% | clean reliable |
| 2 | 394.7 | 641.7 | -38.5% | robust-only |
| 4 | 381.1 | 624.8 | -39.0% | partial, same direction |

当前解读以 `mprotect-shared-dirty-toggle/README.zh-CN.md` 为准：后续
`mm-unstable` lab sanity 显示 Pedro small-folio optimization 部分缓解该
synthetic signal，但没有恢复到 `v6.12` 水平；state-shape audit 支持把该项作为
same-state shared-dirty PTE workload 比较。

## MADV_PAGEOUT / anon THP / no-swap

`cycle_ns_per_page`，越低越好：

| CPU | v6.12 | v6.19 | delta |
|---:|---:|---:|---:|
| 1 | 1900.3 | 3304.7 | -42.5% |
| 2 | 2107.7 | 3583.2 | -41.2% |
| 4 | 2154.2 | 3690.9 | -41.6% |

`advise_ns_per_page` 同方向，约 `-39%` 到 `-41%`。

当前解读以 `madvise-pageout-thp-noswap-refault/README.zh-CN.md` 为准：后续
ftrace/smaps follow-up 发现 default/hugepage 请求下两个内核的 actual THP backing
不同，因此原始结果不应继续表述为 same-state THP regression，也不应表述为已证明的
真实 pageout/refault。

## 证据边界

这份文档只记录历史 formal timing 背景。公开报告应引用各 workload 目录中的当前
README、profile、formal-lab 数据和 attribution summaries。
