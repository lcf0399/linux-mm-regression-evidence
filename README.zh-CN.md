# Linux MM 性能回归证据仓库

这个仓库保存整理后的 Linux MM 性能回归候选证据。它不是按某个月份封存的一次性归档，
而是长期使用的 evidence index：每个 workload 目录记录当前公开口径、实验方法、关键
结果、限制条件，以及 reproducer 或 raw-summary 材料链接。

这不是一个广泛 benchmark suite。每个条目都只对应一个 workload 和一个源码路径假设。
QEMU/lab 结果在筛选、coverage 或归因时仍然有用；但如果要面向上游主张性能回归，优先
使用 bare-metal 真机 timing 证据。

## Workload 索引

- `mprotect-shared-dirty-toggle/`：在 shared dirty 4 KiB PTE 映射上重复执行
  `mprotect()` 权限切换。当前最强证据来自 bare-metal：slowdown 出现在
  `v6.16 -> v6.17` release window；一个 v6.17 single-PTE source probe 可以把指标
  拉回 v6.16 的快区间。当前口径：这是 source-calibrated synthetic shared-dirty PTE
  workload，不是 generic `mprotect()` regression claim。

- `madvise-pageout-thp-noswap-refault/`：匿名 THP/no-swap reclaim-failure 路径上的
  `madvise(MADV_PAGEOUT)`。目录名保留原报告里的 `refault` 说法；当前口径不声称页面
  已经真的被 page out 后再 fault 回来。

- `mincore-present-pte-scan/`：`mincore()` present-PTE scan 候选分析。bare-metal A/B
  没有复现 QEMU 中观察到的 timing signal。当前口径：GCC-built/QEMU-observed
  compiler/codegen sensitivity，不是 generic `mincore()` regression report。

- `mempolicy-migrate-pages-syscall/`：NUMA2 设置上的 `migrate_pages()` syscall route
  候选分析。现有证据是 source-calibrated，覆盖 mempolicy syscall frontend 和
  migration core。当前 bare-metal 节点只有一个 NUMA node，因此不能验证这个 workload。

- `mseal-already-sealed-noop/`：暂存的 `mseal()` already-sealed no-op RFC notes。
  这是归档条目，不是 formal evidence 入口。

- `analysis/`：跨 workload 的技术笔记、patch 分析、历史摘要和当前 narrowing notes。
  可引用证据仍以各 workload 目录为准。

邮件草稿和上游回复记录保留在本地被忽略的 `email/` 目录中。除非明确提升为公开材料，
否则它们不属于 public evidence bundle。

## 证据取舍

公开仓库保留紧凑、可审阅的材料：

- workload README 和当前状态摘要
- 有用的 standalone reproducer 和辅助脚本
- 重点 CSV/JSON summary、运行环境记录、执行顺序文件和完成哨兵
- 用来解释结果的归因笔记和小型 source probe

公开仓库一般不保留体积大的 runner workspace、失败 scratch logs、临时构建输出和私有
邮件草稿历史。较早的 screening 和无效 run 可以在 `analysis/` 中摘要说明，但不应替代
各 workload 的证据目录。

## 方法摘要

- workload 根据具体 Linux `mm/*.c` 源码路径校准。
- coverage 和 performance 分开保存。coverage 证明直接函数命中；clean performance
  timing 应关闭 coverage instrumentation。
- timing metric 默认越低越好，除非 workload README 另有说明。
- formal run 应保留运行环境和执行顺序元数据。
- QEMU/lab timing 默认是 candidate-screening evidence，除非结论明确限定在虚拟化环境。
  面向上游的性能回归主张优先使用 bare-metal timing。
- 只有 exact revert、bisect 或 targeted source probe 足够支持时，才直接写 culprit
  attribution。否则应写成 release-window narrowing 或 candidate attribution。

## 当前公开口径

当前最清楚、最适合继续面向上游推进的候选是 `mprotect-shared-dirty-toggle/`，因为它已经有
bare-metal release-window narrowing 和一个聚焦的 v6.17 source probe。其他目录仍然保留，
因为它们解释了早期报告、negative follow-up，或者仍有用但需要限制口径的候选证据。

这个仓库会刻意保留 negative 或被削弱的结果。如果某个 workload 在 bare metal 上没有复现、
依赖 QEMU/codegen layout，或者缺少必要的 NUMA/swap 状态，它仍然是有价值的证据，但必须
明确标注这个限制。
