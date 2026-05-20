# Linux MM 性能回归证据包 - 2026 年 5 月

这个仓库包含一份精简证据包，用于支撑两个 Linux MM 性能回归报告。它的目标是让正式实验方法、实验环境、原始摘要和当前归因状态可以被审计，而不是把一大包附件直接塞进 mailing list 报告里。

这两个报告按 workload 明确收窄：

- `madvise-pageout-thp-noswap-refault/`：匿名 THP、guest 无 swap、`MADV_PAGEOUT` 触发的 no-swap reclaim-failure path。目录名保留了原邮件里的 `refault` 说法，但后续更准确的描述是不声称页面真的被 page out 后 refault。
- `mprotect-shared-dirty-toggle/`：shared dirty PTE 映射上的重复 `mprotect()` protection toggle。
- `analysis/`：本地审阅用的归因分析、上游反馈、patch 分析和历史四案例材料；是否上传到 GitHub 证据包后续再筛选。

这不是一个广泛 benchmark suite。每个结论都只限定在下面描述的 workload 和实验环境内。

## 实验方法

两个 workload 都通过同一个本地实验框架运行：

- workload 由源码语义校准，目标是具体的 Linux `mm/*.c` 路径，并导出按页归一化的 timing metrics。
- coverage 和 performance 分开收集。coverage 只用来证明直接函数入口命中；clean performance run 关闭 coverage。
- 正式 performance run 使用 interleaved version order，降低 host drift 对版本差异的干扰。
- lab formal matrix 使用 `QEMU_SMP=1/2/4`，在不同 CPU 数下保持相同 guest memory、kernel config 族和 cmdline 口径。
- 单独做过 release-level sanity check，用来选择较宽的报告范围；这部分不是当前公开精简证据包的一部分。目前还没有做完 commit-level bisection。

主要 timing metrics 都是越低越好：

- `cycle_ns_per_page`
- `MADV_PAGEOUT` syscall/reclaim 主段使用 `advise_ns_per_page` 作为辅助指标

这里的 `cycle` 指一次完整 workload iteration，不是 CPU cycle。也就是说，
`cycle_ns_per_page` 是“每页每次 workload iteration 的 wall-clock
nanoseconds”。这个命名沿用框架早期字段名，后续对上游解释时应避免把它误读成
CPU 硬件周期数。

formal 证据的精确逐次运行元数据保留在 `pipeline_run_env.json`、`execution_order.json`、`*.summary.csv/json` 和 `*.raw.csv/json` 中。

## 实验环境摘要

正式证据以 lab server 作为主要 timing 环境：

- 元数据中的 host label：`lcf`
- host kernel：`Linux 6.14.0-37-generic x86_64`
- host CPU 数：128
- container/cgroup CPU set：`0,2,4,6,8,10,12,14`
- container/cgroup memory limit：`16106127360` bytes
- QEMU：`qemu-system-x86_64 8.2.2`
- guest memory：`QEMU_MEM_MB=14336`
- guest CPU：`QEMU_SMP=1/2/4`
- timing 顺序：interleaved version order
- formal repetitions：9
- performance timing：关闭 coverage

精确的逐次运行环境仍以 `pipeline_run_env.json` 为准；这里是给人快速阅读的摘要。

## 当前归因状态

下面的归因内容是机制解释。正式性能结论仍以关闭 coverage/probe instrumentation 的 clean timing runs 为准。

### MADV_PAGEOUT / THP / no-swap reclaim failure

当前解释不是泛化的 `madvise()` 变慢，也不是泛化的 `MADV_PAGEOUT` 变慢。

回归结论限定在这个 workflow：

1. 映射 16 MiB anonymous memory
2. 让 mapping 使用默认 THP 路径
3. 在 guest 无 swap 的情况下执行 `madvise(MADV_PAGEOUT)`
4. 再 write-touch 这段 mapping，作为 workload iteration 的后半段

maintainer 已指出：在无 swap 条件下，匿名页没有地方被真正 page out，因此不应把这个场景表述成真实 pageout/refault。更准确的语义是 `MADV_PAGEOUT` 触发 anon/THP no-swap reclaim/swap-allocation-failure path；后续 write-touch 只是 workload iteration 的一部分。

timing split 显示主要时间差在 `MADV_PAGEOUT` / reclaim 段。coverage 和后续路径验证都指向同一条 reclaim/swap-failure 链：

```text
madvise(MADV_PAGEOUT)
  -> reclaim_pages()
  -> shrink_folio_list()
  -> folio_alloc_swap()
  -> swap allocation failure path
```

2026-05-19 又补了几轮 local 1CPU ftrace/smaps attribution，原始 run 已统一收在：

```text
madvise-pageout-thp-noswap-refault/attribution/runs/local/
madvise-pageout-thp-noswap-refault/attribution/summaries/local-ftrace-20260519.zh-CN.md
```

这些本地和 lab 复跑都不是 clean timing 证据，但路径分解显示 `v6.19.9` 的额外时间集中在
`reclaim_pages()` / `shrink_folio_list()`，并且 `split_folio_to_list()` 在 THP-backed
短跑中稳定于 `v6.19.9` 出现 16 次。

lab 侧 ftrace/smaps attribution 已整理到：

```text
madvise-pageout-thp-noswap-refault/attribution/summaries/lab-1cpu-20260520.zh-CN.md
madvise-pageout-thp-noswap-refault/attribution/summaries/lab-multicpu-followup-20260520.zh-CN.md
madvise-pageout-thp-noswap-refault/attribution/runs/lab/
```

更重要的新 caveat 是：本地和 lab smaps 都显示 default THP 和显式 `thp=hugepage` 请求下，
`v6.12.77` 的 mapping 实际都是 `AnonHugePages=0 kB`，而 `v6.19.9` 是
`AnonHugePages=16384 kB`。在显式 `thp=nohugepage` 的同状态对照中，两边都没有
THP backing，也没有 hit `split_folio_to_list()`，并且本地短跑不再显示
old-version-faster 信号。

因此当前关键边界需要再收紧：这个现象和实际 THP backing 状态以及 no-swap reclaim
里的 split/failure path 强相关。后续上游表述不能再简单写成“同一 THP workload
下 v6.19 更慢”；更合适的是修正原 regression framing，并询问 no-swap THP
split/fast-fail 是否仍值得作为优化问题继续讨论。

单独做过的 release-level sanity check 显示 `v6.18.19` 已进入慢路径，但目前还没有 bisect 到具体 culprit commit。

### mprotect shared-dirty toggle

这条的机制假设更局部。

workload 对 shared dirty 64 MiB mapping 反复做 protection toggle。最强归因指向 v6.19 的 `change_pte_range()` 批处理重写：

```text
change_pte_range()
  -> mprotect_folio_pte_batch()
  -> modify_prot_start_ptes()
  -> set_write_prot_commit_flush_ptes()
  -> prot_commit_flush_ptes()
```

对这个 shared-dirty workload，实测路径无法形成有效的大 PTE batch。batch-probe attribution 显示 shared-dirty 路径上的 `nr_ptes=1`。这意味着额外的 folio lookup、batch-size query、helper dispatch 和 batch commit machinery 都按每个 4 KiB PTE 付费，但没有 batch-size amortization。

收到上游反馈后，又补了两类检查：

- `mm-unstable-lab-sanity/`：当前 akpm/mm `mm-unstable` commit
  `444fc9435e57` 在 lab CPU/memory 矩阵中相对 `v6.19.9` 部分缓解了这个
  synthetic shared-dirty signal，快约 6.6-13.5%，大约关闭了
  `v6.12.77 -> v6.19.9` 差距的 18-37%，但没有把这个 workload 拉回
  `v6.12.77` 水平。
- `state-audit-lab/`：对 `v6.12.77`、`v6.19.9` 和 `mm-unstable` 做的
  state-shape audit 显示，成功 run 都是同一种 4 KiB shared-dirty PTE
  mapping 状态：protect 前后 16384 个 present pages、无 THP backing、
  最终 1 个 VMA、没有 semantic mismatch。这支持把 mprotect 这条看作
  same-state comparison，和已修正口径后的 `MADV_PAGEOUT` 情况不同。

这也解释了为什么不能把结果泛化到所有 `mprotect()` 用户。同一测试套件里的 anonymous THP-oriented `mprotect()` 路径可以进入 huge-PMD/THP handling，并不表现出同样行为。因此回归结论应限定在 shared dirty PTE toggle path。

单独做过的 release-level sanity check 显示 `v6.18.19` 已进入慢路径，但目前还没有 bisect 到具体 culprit commit。

## 数据取舍策略

这个仓库的正式 workload 目录只放两个报告当前最新、可引用的证据包：

- 用于主要性能结论的最新 lab formal refresh 结果
- 必要的 coverage 证据，但和 clean performance timing 分开保存

旧 screening、release-level sanity run、无效 run、失败 run、被 instrumentation 污染的 run、探索性中间产物，默认不进入公开最小证据包。`analysis/` 目录是本地整理区，会暂存更宽的分析和历史材料；后续上传前需要再筛选。

## 主要限制条件

这些报告不声称存在泛化的 `madvise()` 或泛化的 `mprotect()` 性能回归。

`MADV_PAGEOUT` 的结论只限定在匿名 THP、guest 无 swap、`MADV_PAGEOUT` reclaim-failure + write-touch iteration 工作流上；当前不应声称真实 pageout/refault 已被证明。新的 local + lab attribution 表明：这不是一组 actual THP backing 一致的 same-state 对比。

`mprotect()` 的结论只限定在 shared dirty full-range protection-toggle workload 上；当前最干净的 formal 结果是 lab 1CPU run，2CPU 和 4CPU 是同方向的补充证据，但带有可靠性限制。

目前还没有 bisect 到具体 culprit commit。基于单独的 release-level sanity check，建议报告范围仍写成 `v6.12..v6.18`。
