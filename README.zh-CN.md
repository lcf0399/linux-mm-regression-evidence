# Linux MM 性能回归证据包 - 2026 年 5 月

这个仓库包含一份精简证据包，用于支撑两个 Linux MM 性能回归报告。它的目标是让正式实验方法、实验环境、原始摘要和当前归因状态可以被审计，而不是把一大包附件直接塞进 mailing list 报告里。

这两个报告按 workload 明确收窄：

- `madvise-pageout-thp-noswap-refault/`：匿名 THP、guest 无 swap、refault 工作流中的 `madvise(MADV_PAGEOUT)`。
- `mprotect-shared-dirty-toggle/`：shared dirty PTE 映射上的重复 `mprotect()` protection toggle。

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

### MADV_PAGEOUT / THP / no-swap refault

当前解释不是泛化的 `madvise()` 变慢，也不是泛化的 `MADV_PAGEOUT` 变慢。

回归结论限定在这个 workflow：

1. 映射 16 MiB anonymous memory
2. 让 mapping 使用默认 THP 路径
3. 在 guest 无 swap 的情况下执行 `madvise(MADV_PAGEOUT)`
4. 再 refault/write-touch 这段 mapping

timing split 显示主要时间差在 `MADV_PAGEOUT` / reclaim 段，而不是 refault touch 段。coverage 和后续路径验证都指向同一条 reclaim/swap-failure 链：

```text
madvise(MADV_PAGEOUT)
  -> reclaim_pages()
  -> shrink_folio_list()
  -> folio_alloc_swap()
  -> swap allocation failure path
```

关键边界是 no-swap THP 路径。在这个环境里，对 THP-backed anonymous mapping 做 pageout，会遇到 swap allocation 失败、THP handling/splitting 参与、reclaim 路径按页粒度重试的 worst case。因此上报时应写成 THP + `MADV_PAGEOUT` + no-swap refault workflow regression，而不是声称所有 swap-backed 或所有 `MADV_PAGEOUT` workload 都回归。

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

这也解释了为什么不能把结果泛化到所有 `mprotect()` 用户。同一测试套件里的 anonymous THP-oriented `mprotect()` 路径可以进入 huge-PMD/THP handling，并不表现出同样行为。因此回归结论应限定在 shared dirty PTE toggle path。

单独做过的 release-level sanity check 显示 `v6.18.19` 已进入慢路径，但目前还没有 bisect 到具体 culprit commit。

## 数据取舍策略

这个仓库只放两个报告当前最新、可引用的证据包：

- 用于主要性能结论的最新 lab formal refresh 结果
- 必要的 coverage 证据，但和 clean performance timing 分开保存

旧 screening、release-level sanity run、无效 run、失败 run、被 instrumentation 污染的 run、探索性中间产物，都不上传到这里。这样上游证据包只保留当前最新、可引用的 formal 数据，不把旧调查历史混进报告。

## 主要限制条件

这些报告不声称存在泛化的 `madvise()` 或泛化的 `mprotect()` 性能回归。

`MADV_PAGEOUT` 的结论只限定在匿名 THP、guest 无 swap、refault/write-touch 工作流上。

`mprotect()` 的结论只限定在 shared dirty full-range protection-toggle workload 上；当前最干净的 formal 结果是 lab 1CPU run，2CPU 和 4CPU 是同方向的补充证据，但带有可靠性限制。

目前还没有 bisect 到具体 culprit commit。基于单独的 release-level sanity check，建议报告范围仍写成 `v6.12..v6.18`。
