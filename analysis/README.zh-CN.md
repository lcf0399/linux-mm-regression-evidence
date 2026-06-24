# 补充技术分析索引

这个目录只保留经过整理的技术补充材料，不再放私有邮件提交复盘或原始调查历史。

当前结论以各 workload 目录为准：

```text
madvise-pageout-thp-noswap-refault/
mprotect-shared-dirty-toggle/
```

## 文件说明

- `confirmed_regressions_refresh_2026-05-13.zh-CN.md`
  - 2026-05-13 原始 lab formal timing refresh 的短版历史摘要。
  - 当前 caveat 以 workload README 为准。

- `four_case_root_cause_line_level_attribution.zh-CN.md`
  - 早期“四案例”源码归因文档的短版历史索引。
  - 完整内部长文不进入当前精简公开证据包。

- `mprotect_mm_unstable_patch_analysis_2026-05-19.zh-CN.md`
  - Pedro small-folio `mprotect()` optimization 与 shared-dirty
    `nr_ptes == 1` 假设之间的技术关系分析。

- `mprotect_baremetal_narrowing_2026-06-23.zh-CN.md`
  - 新 bare-metal 节点上 `mprotect_shared_dirty_reproducer` 的
    `v6.16 -> v6.17` release-window narrowing、对应源码差异方向，以及
    2026-06-24 single-PTE attribution probe 的结论边界。

## 边界

- `madvise` 当前不应表述为已证明的真实 pageout/refault regression，也不应表述为
  same-state THP regression。
- `mprotect` 当前是 synthetic/source-calibrated shared-dirty PTE workload，
  不是泛化的 `mprotect()` regression claim。
- 上游提交流程复盘、实验编排脚本和 launch log 属于私有方法/运行笔记，保存在公开
  evidence 仓库之外。
