# 分析与上游反馈索引

这个目录保存本地审阅用的分析材料。它不是当前 GitHub 公开证据包的最小集合；后续是否上传，需要根据 maintainer 反馈再筛选。

这里的若干文件是从 `mm_regression_gen/` 或仓库根目录复制过来的整理件。原路径先保留，避免破坏旧报告、邮件草稿或本地引用；等上游反馈和 lab rerun 都稳定后，再决定是否删除旧位置。

## 文件说明

- `confirmed_regressions_refresh_2026-05-13.zh-CN.md`
  - 2026-05-13 对 `mprotect/shared_dirty_full_toggle_64m` 和 `madvise/pageout_refault_anon_16m` 的 formal refresh 汇总。
  - 记录 lab `1/2/4 CPU` clean performance 矩阵和 coverage split。

- `four_case_root_cause_line_level_attribution.zh-CN.md`
  - 原“四个性能回归/候选案例”的源码行级归因分析。
  - 现在它更适合作为历史分析和方法论材料：`mprotect` 与 `madvise` 仍是当前主线，`damon` 和 `readahead` 已降级。

- `mprotect_mm_unstable_patch_analysis_2026-05-19.zh-CN.md`
  - 对 Pedro `mprotect` small-folio optimization patchset 的本地分析。
  - 结合我们原来的 `nr_ptes=1` / batch 固定成本假设，以及 `mm-unstable`
    本地和 lab sanity 结果。

- `upstream_submission_feedback.zh-CN.md`
  - 首次上游提交的踩坑、maintainer 回复、以及后续提交方法修正。
  - 包含 SMTP/Webmail、maintainer 地址、synthetic workload、madvise no-swap 语义修正等经验。
  - 当前 madvise follow-up 决策：先不急着回复，等 lab 恢复后补同口径 ftrace/路径分解，再把 local + lab 结果一起发到原线程。

## 当前不应直接外推的点

- `mprotect` 的 `mm-unstable` lab sanity 显示 Pedro 相关优化能减轻 synthetic signal，但没有把结果拉回 v6.12 水平，因此不能说“已经修复”。
- `madvise` 的原目录名仍包含 `refault`，但 maintainer 已指出 no-swap 条件下不应表述为真实 pageout/refault。后续更准确的说法是 `MADV_PAGEOUT anon/THP no-swap reclaim-failure path`。
- `madvise` 现在已有 local 1CPU ftrace 线索，但还不能当作 lab formal attribution；回复上游前应等 lab 同口径 run。
- 四案例归因文档里早期说法可能包含历史术语和旧状态。引用时应优先看文档开头的当前状态校准和本目录新增分析。
