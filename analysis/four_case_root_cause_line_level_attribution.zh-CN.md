# 四案例源码归因历史摘要

本文件是早期“四案例”源码归因文档的精简历史摘要。完整长文已从公开 evidence
bundle 移出，以避免和当前 workload README 重复或产生过时结论。

当前公开证据以以下目录为准：

- `mprotect-shared-dirty-toggle/`
- `madvise-pageout-thp-noswap-refault/`

## 当前状态

| 早期条目 | 当前状态 |
|---|---|
| `mprotect/shared_dirty_full_toggle` | 仍是当前 mprotect 主线。机制假设集中在 v6.19 `change_pte_range()` batching rewrite 对 shared-dirty `nr_ptes=1` 路径引入 per-PTE 固定成本；后续 `mm-unstable` 只部分缓解。 |
| `MADV_PAGEOUT` / THP / no-swap | 原始 timing 信号仍有历史价值，但后续 ftrace/smaps 显示 default/hugepage 请求下 `v6.12.77` 与 `v6.19.9` 的 actual THP backing 不一致。当前不再按 same-state THP regression 表述。 |
| `damon/large_region` | 已降级为 benchmark artifact / warmup 现象，不作为当前上游回归报告主线。 |
| `readahead/unaligned_middle` | steady-state 未复现，保留为历史 workflow 观察，不作为当前上游回归报告主线。 |
| `process_mrelease split_vmas_reap` | focused 线索后续未形成稳定 formal old-faster 结论，不作为当前上游回归报告主线。 |

## 当前可引用材料

- mprotect 主结论、`mm-unstable` follow-up 和 state audit：
  `mprotect-shared-dirty-toggle/README.zh-CN.md`
- MADV_PAGEOUT 当前 caveat 和 lab `1/2/4/8/16 CPU` attribution：
  `madvise-pageout-thp-noswap-refault/README.zh-CN.md`
- 2026-05-13 原始 formal timing 背景：
  `analysis/confirmed_regressions_refresh_2026-05-13.zh-CN.md`

## 证据边界

这份短文只用于解释历史调查来源。准备上游回复或公开说明时，不应引用早期长文中的
`pageout/refault`、`confirmed old-faster`、或单一源码根因表述；这些口径已经被后续
state-shape 和 attribution 结果收窄。
