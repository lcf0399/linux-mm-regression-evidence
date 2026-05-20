# MADV_PAGEOUT no-swap follow-up backlog - 2026-05-19

当前决策：**暂不急着回复上游**。本地 ftrace 已有有价值线索，但新补的
smaps/page-state 结果暴露了一个更关键的问题：本地 `v6.12.77` 和 `v6.19.9`
在 default/hugepage 请求下实际 THP backing 不一致。等 lab server 恢复后，需要先
确认正式 lab timing 的页状态，再决定如何回复原线程。

## 已完成

- 修正语义边界：这个 workload 不应称为真实 pageout/refault；更准确的说法是
  `MADV_PAGEOUT anon/THP no-swap reclaim-failure path`。
- 本地 1CPU ftrace attribution 两轮：
  - `madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T095050Z/`
  - `madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T_local_procfix/`
- 两轮本地结果共同显示：
  - `v6.19.9` 的额外时间集中在 `reclaim_pages()` / `shrink_folio_list()`。
  - `v6.19.9` 都 hit `split_folio_to_list()` 16 次。
  - `v6.12.77` 是 0 或 1 次。
- 补跑 `CONFIG_PROC_PAGE_MONITOR=y` 后的本地 smaps attribution：
  - `madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T_procpage/`
  - default THP 下，`v6.12.77` 是 `AnonHugePages=0 kB`，`v6.19.9` 是
    `AnonHugePages=16384 kB`。
- 修正 THP mode 传递后补跑两组本地对照：
  - `madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T_hugepage2/`：guest 确认 `thp=hugepage`，但
    `v6.12.77` 仍是 `AnonHugePages=0 kB`，`v6.19.9` 是 `16384 kB`。
  - `madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T_nohugepage/`：两边都是 `AnonHugePages=0 kB`、
    `THPeligible=0`，都没有 hit `split_folio_to_list()`，且本地短跑没有
    old-version-faster 信号。
- 已准备但暂不发送的 follow-up 草稿：
  - `linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.md`
  - `linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.zh-CN.md`
- 注意：这两份 follow-up 草稿已不是最新叙事，发送前必须重写，不能直接使用。

## 待做

0. 2026-05-20 已完成一轮 lab 1CPU ftrace/smaps attribution：
   - host PID：`3687375`
   - `STAMP_BASE=20260520T062622Z_lab_madvise`
   - launcher：`linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/scripts/run_madvise_ftrace_lab_matrix.sh`
   - launch log：`linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/runs/lab/1cpu-20260520/lab-launch-20260520T062622Z_lab_madvise.log`
   - per-mode logs：`.../attribution/runs/lab/1cpu-20260520/logs/{default,hugepage,nohugepage}.log`
   - output dirs：`.../attribution/runs/lab/1cpu-20260520/{default,hugepage,nohugepage}/`
   - 口径：`QEMU_SMP=1`，`QEMU_MEM_MB=14336`，`QEMU_TASKSET=0,2,4,6,8,10,12,14`，`JOBS=8`
   - 目的：先补 formal lab 环境的 page-state/ftrace breakdown；不是 clean timing。
   - summary：`.../attribution/summaries/lab-1cpu-20260520.zh-CN.md`
   - 结论：lab 与本地一致，default/hugepage 下 `v6.12.77` 实际不是 THP-backed，
     `v6.19.9` 是 `AnonHugePages=16384 kB`；`nohugepage` 同状态对照没有
     old-faster。
0. 2026-05-20 已完成 lab 多 CPU ftrace/smaps attribution：
   - `2CPU/14336MiB`、`4CPU/14336MiB`：
     `20260520T080847Z_lab_followup_madvise`
   - `8CPU/16384MiB`、`16CPU/32768MiB`：
     `20260520T081655Z_lab_madvise_large`
   - summary：
     `linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/summaries/lab-multicpu-followup-20260520.zh-CN.md`
   - 结论：多 CPU 下仍然是同一个结构。`default/hugepage` 中 `v6.19.9`
     实际 THP-backed 并命中 `split_folio_to_list()`；`v6.12.77` 实际不是
     THP-backed。`nohugepage` 同状态对照中没有稳定 old-faster。
1. 更新 follow-up 邮件草稿：
   - 承认原 pageout/refault 表述不准确；
   - 明确 `cycle_ns_per_page` 是 wall-clock iteration ns/page；
   - 说明 local + lab 都发现 actual THP backing 差异；
   - 说明 `nohugepage` same-state control 里 old-faster 消失；
   - 询问 no-swap THP split/fast-fail 方向是否仍值得作为优化问题继续。
2. 给用户审阅后再 reply-all 上游；不要直接发送。

## 当前不应做

- 不应只用 local-only ftrace 立即回复上游。
- 不应声称已经证明 culprit commit。
- 不应声称这是泛化的 `MADV_PAGEOUT` 或 `madvise()` 回归。
- 不应把 tracing kernel 的时间数字和 formal clean timing 直接混用。
- 不应再把当前 madvise 结果简单描述为“同一 THP workload 下 v6.19 更慢”，除非
  lab formal 环境能证明两边实际 THP backing 一致。
