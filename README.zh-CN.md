# Linux MM 性能回归证据包 - 2026 年 5 月

这个仓库包含整理后的证据包，用于支撑 Linux MM 性能回归报告和后续 candidate 分析。
仓库记录正式实验方法、实验环境、摘要数据和当前归因状态，方便审阅者直接核查报告中的结果。

这两个报告按 workload 明确收窄：

- `madvise-pageout-thp-noswap-refault/`：匿名 THP、guest 无 swap、`MADV_PAGEOUT` 触发的 no-swap reclaim-failure path。目录名保留了原邮件里的 `refault` 说法；当前证据范围不声称页面真的被 page out 后 refault。
- `mprotect-shared-dirty-toggle/`：shared dirty PTE 映射上的重复 `mprotect()` protection toggle。
- `mincore-present-pte-scan/`：后续 `mincore()` present-PTE scan 候选分析。它是
  RFC 风格的、由源码路径校准的 synthetic 信号和 candidate fix 草图，不是已经发送的正式
  regression 报告。
- `mempolicy-migrate-pages-syscall/`：后续 `migrate_pages()` syscall route 候选分析。
  它是 source-calibrated NUMA2 synthetic 信号，覆盖 mempolicy syscall frontend 和
  migration core，不是 `mempolicy-only` regression 报告。
- `analysis/`：整理后的技术补充、patch 分析和短版历史摘要。私有上游提交流程复盘不放入这个公开 evidence bundle；正式证据仍以各 workload 目录为准。

这不是一个广泛 benchmark suite。每个结论都只限定在下面描述的 workload 和实验环境内。

## 实验方法

两个 workload 都通过同一个项目实验框架运行：

- workload 由源码语义校准，目标是具体的 Linux `mm/*.c` 路径，并导出按页归一化的 timing metrics。
- coverage 和 performance 分开收集。coverage 只用来证明直接函数入口命中；clean performance run 关闭 coverage。
- 正式 performance run 使用 interleaved version order，降低 host drift 对版本差异的干扰。
- primary lab formal matrix 使用 `QEMU_SMP=1/2/4`，在不同 CPU 数下保持相同 guest memory、kernel config 族和 cmdline 口径。
- 部分 follow-up 检查会在 workload 目录中单独标注 extended lab matrix，最高扩展到 `QEMU_SMP=8/16` 并使用更大的 guest memory。这些扩展行用于观察扩展性和补充上下文，但应和严格的 `1/2/4` 同内存 formal matrix 分开解释。
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
- primary formal guest memory：`QEMU_MEM_MB=14336`
- primary formal guest CPU：`QEMU_SMP=1/2/4`
- extended follow-up run 如存在：`QEMU_SMP=8` 可配更大内存，例如 `QEMU_MEM_MB=16384`；`QEMU_SMP=16` 可配更大内存，例如 `QEMU_MEM_MB=32768`
- timing 顺序：interleaved version order
- formal repetitions：9
- performance timing：关闭 coverage

精确的逐次运行环境仍以 `pipeline_run_env.json` 为准；这里是简要摘要。

## Workload 当前状态

各 workload 目录是表格、profile 和 follow-up summary 的权威入口。这里仅记录当前公开口径。

- `madvise-pageout-thp-noswap-refault/`
  - 原始 lab timing 显示，在 `1/2/4 CPU` 矩阵上 `v6.19.9` 慢于 `v6.12.77`。
  - 后续 ftrace/smaps 覆盖了 14336 MiB 下的 `1/2/4 CPU`、16384 MiB 下的
    `8 CPU`、32768 MiB 下的 `16 CPU`。
  - follow-up 发现页面状态限制：default/hugepage run 不是
    `v6.12.77` 和 `v6.19.9` 之间实际 THP 状态一致的对比。
  - 当前口径：不能声称已经证明真实 pageout/refault regression，也不能声称
    same-state THP regression；更适合作为 no-swap `MADV_PAGEOUT`
    anon/THP reclaim split/failure-path observation。

- `mprotect-shared-dirty-toggle/`
  - 原始 lab timing 显示，shared-dirty PTE toggle workload 上 `v6.19.9`
    慢于 `v6.12.77`。
  - `akpm/mm mm-unstable 444fc9435e57` 在 lab `1/2/4/8/16 CPU` 矩阵中
    部分缓解该信号，但没有恢复到 `v6.12.77` 水平。
  - state-shape audit 显示，成功的 `v6.12.77`、`v6.19.9` 和
    `mm-unstable` run 都是同一种 4 KiB shared-dirty PTE mapping 状态。
  - `reproducer/` 提供给维护者审阅的 standalone C reproducer，抽取自原
    generated workload 的 shared-dirty full-range toggle 场景，不需要运行完整
    experiment framework。
  - `reproducer-validation/` 是该 standalone reproducer 的 lab screening
    验证；它在 `1/2/4/8/16 CPU` 下保持同样大方向，但属于 5-repeat
    reproducer/timing screening check，不替代前面的 formal evidence。
  - 当前口径：这是由源码路径校准的 synthetic shared-dirty PTE
    `mprotect()` workload，不是泛化的 `mprotect()` regression claim。

- `mincore-present-pte-scan/`
  - 这是后续候选分析，不属于最初两个正式报告。
  - source-calibrated `no_thp_pte_scan_64m` workload 目标是
    `mincore_pte_range()` 中 resident anonymous base-page 路径。
  - release-level 和定向 A/B testing 把主台阶缩到 `v6.15 -> v6.16`，
    最强 suspect 是
    `4df65651f7075 ("mm: mincore: use pte_batch_hint() to batch process large folios")`。
  - 本地 present-first test patch 在 v6.18 和 v7.0 的 x86/QEMU lab 上让
    `no_thp_pte_scan_64m` 快约 30% 以上，同时 x86 上的 THP/no-THP semantic smoke
    仍通过。
  - 当前口径：已缩窄 suspect，并在 x86 lab 验证 candidate fix shape；但还需要
    arm64 或 mTHP/large-folio 保真验证，才能作为 upstream-ready fix 讨论。

- `mempolicy-migrate-pages-syscall/`
  - 这是后续候选分析，不属于最初两个正式报告。
  - source-calibrated workload 目标是双 NUMA node guest 上用户态可见的
    `migrate_pages()` syscall route。
  - lab same-PREEMPT 1/2/4 CPU clean timing 中，`v7.0.9-preempt` 的
    `move_ns_per_page` 显著慢于 `v6.12.77-preempt`、`v6.18.19-preempt` 和
    `v6.19.9-preempt`。
  - 8/16 CPU extended follow-up 对 v6.18/v6.19 方向仍支持，但因为 guest memory 随
    CPU 数变化，需要和主 formal matrix 分开解释。
  - direct coverage 确认 workload 同时进入 `mm/mempolicy.c` 和 `mm/migrate.c`；
    ftrace 把额外成本指向 migration core；deferred-split bookkeeping 和 simple
    `folio_mc_copy()` -> `folio_copy()` A/B 都是 negative attribution result。
  - 当前口径：强 synthetic regression candidate，但作为最终报告前仍需要更低扰动的
    migration-core attribution 或 commit-level narrowing。

最初两个报告都还没有完整 `git bisect` 到具体 culprit commit。单独的 release-level sanity
check 显示两者在 `v6.18.19` 已进入慢区间。后续 `mincore` 候选针对 v6.16 suspect
已有定向 A/B 证据，但仍不是完整 `git bisect` 结果。

## 数据取舍策略

这个仓库的正式 workload 目录只放两个报告当前最新、可引用的证据包，以及后续候选的
紧凑 maintainer-facing 材料：

- 用于主要性能结论的最新 lab formal refresh 结果
- 必要的 coverage 证据，但和 clean performance timing 分开保存
- 维护者要求时补充的 standalone reproducer、紧凑 summary 和必要 run metadata

旧 screening、release-level sanity run、无效 run、失败 run、被 instrumentation
污染的 run、探索性中间产物，默认不进入公开最小证据包。`analysis/` 目录只提供补充说明，
不能替代正式 workload 证据。

这个策略不等于删除所有逐次数据。公开目录可以保留 compact CSV/JSON summary、
运行环境、执行顺序和完成哨兵；体积较大的原始 runner workspace、scratch log 和临时
探索目录默认继续忽略，除非维护者明确要求。

## 主要限制条件

这些报告不声称存在泛化的 `madvise()` 或泛化的 `mprotect()` 性能回归。

`MADV_PAGEOUT` 的结论只限定在匿名 THP、guest 无 swap、`MADV_PAGEOUT` reclaim-failure + write-touch iteration 工作流上；当前不应声称真实 pageout/refault 已被证明。新的 local + lab attribution 表明：这不是一组 actual THP backing 一致的 same-state 对比。

`mprotect()` 的结论只限定在 shared dirty full-range protection-toggle workload 上；
原始 formal 结果里最干净的是 lab 1CPU run，2CPU 和 4CPU 是同方向补充证据但带有
可靠性限制。后续 8/16 CPU 行是 extended follow-up context，不属于严格同内存的
primary formal matrix。

`mincore()` 材料不是正式 regression 报告。它只限定在由源码路径校准的 anonymous no-THP
resident-PTE scan 和本地 present-first candidate fix shape。当前证据只覆盖 x86/QEMU
lab，还没有证明 arm64/mTHP 保真。

`mempolicy/migrate` 材料不是 generic `mempolicy` regression 报告。它只限定在受控 NUMA2
anonymous-page `migrate_pages()` route。当前 route 证据很强，但归因仍停在
migration-core cost center 和 negative A/B lead，还没有 commit-level culprit。
