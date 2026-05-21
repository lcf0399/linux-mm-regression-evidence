# 分析与上游反馈索引

这个目录保存补充分析材料，用于说明当前两个报告的状态、已经收到的 maintainer 反馈，以及首次提交后补做的验证工作。

这里的文件不是主要性能证据。可引用的 timing 和 coverage 数据应优先查看各 workload 目录：

```text
madvise-pageout-thp-noswap-refault/
mprotect-shared-dirty-toggle/
```

本目录的作用是提供上下文和调查 provenance。部分文档记录的是历史调查状态，阅读时应结合顶层 README 和 workload-specific README。

## 文件说明

- `confirmed_regressions_refresh_2026-05-13.zh-CN.md`
  - 2026-05-13 对 `mprotect/shared_dirty_full_toggle_64m` 和 `madvise/pageout_refault_anon_16m` 的 formal refresh 汇总。
  - 记录 lab `1/2/4 CPU` clean performance 矩阵和 coverage split。

- `four_case_root_cause_line_level_attribution.zh-CN.md`
  - 原“四个性能回归/候选案例”的源码行级归因分析。
  - 现在它更适合作为历史分析和方法论材料：`mprotect` 与 `madvise` 仍是当前主线，`damon` 和 `readahead` 已降级。

- `mprotect_mm_unstable_patch_analysis_2026-05-19.zh-CN.md`
  - 对 Pedro `mprotect` small-folio optimization patchset 的分析。
  - 结合先前的 `nr_ptes=1` / batch 固定成本假设，以及 `mm-unstable`
    本地和 lab sanity 结果。

- `upstream_submission_feedback.zh-CN.md`
  - 首次上游提交的踩坑、maintainer 回复、以及后续提交方法修正。
  - 包含 SMTP/Webmail、maintainer 地址、synthetic workload、madvise no-swap 语义修正等经验。
  - 记录 madvise follow-up 中对 no-swap/page-state 语义的修正，以及 mprotect follow-up 中对 `mm-unstable` 和 state-shape audit 的补充。

## 当前不应直接外推的点

- `mprotect` 的 `mm-unstable` lab sanity 显示 Pedro 相关优化能减轻 synthetic signal，但没有把结果拉回 v6.12 水平，因此不能说“已经修复”。
- `madvise` 的原目录名仍包含 `refault`，但 maintainer 已指出 no-swap 条件下不应表述为真实 pageout/refault。后续更准确的说法是 `MADV_PAGEOUT anon/THP no-swap reclaim-failure path`。
- `madvise` 的 ftrace/smaps rerun 是 attribution evidence，不是 clean timing evidence；其作用是修正语义和解释路径，不应替代正式性能数据。
- 四案例归因文档里早期说法可能包含历史术语和旧状态。引用时应优先看文档开头的当前状态校准和本目录新增分析。
