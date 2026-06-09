# mincore present-PTE scan codegen 检查

这个目录是一份给维护者看的精简证据草稿，针对 `mm/mincore.c` 里 resident anonymous
base-page PTE 路径的 `mincore()` source-calibrated workload。

当前口径：

- workload 类型：由源码路径校准的 synthetic userspace micro-workload。
- 热路径：`mincore()` -> `walk_page_range()` -> `mincore_pte_range()`。
- 主场景：`MADV_NOHUGEPAGE` anonymous 64 MiB resident mapping，
  即 `no_thp_pte_scan_64m`。
- 主指标：`mincore_ns_per_1k_pages`，越低越好。

这不是生产应用回归，也不是泛化的 `mincore()` regression 报告。补做 `codegen/`
里的 compiler cross-check 后，当前口径更窄：它是在 GCC 13.3 + QEMU lab 环境中观察到的
compiler/codegen-sensitive signal。Clang 18.1.3 会把被检查的 x86 代码形状优化成
逐字节等价的 `mincore_pte_range()` 输出。

## 当前发现

release-level narrowing 和 A/B testing 已经把主台阶缩到 v6.15 -> v6.16 区间。
最强 suspect 是：

```text
4df65651f7075 mm: mincore: use pte_batch_hint() to batch process large folios
```

这条变化改善了 large-folio/mTHP mincore batching。在 GCC 13.3 QEMU lab runs 中，
base-page resident-PTE scan case 显示出明显成本。

关键 follow-up 结论来自 codegen 检查：

- GCC 13.3 不会把 v6.16 original 生成成同一份 `mincore_pte_range()` 形状。本地
  `batch <= 1` fastpath 和 nobatch variant 会生成相同形状。
- Clang 18.1.3 会把 v6.15 original、v6.16 original、本地 fastpath variant 和
  nobatch variant 全部生成成逐字节等价的 `mincore_pte_range()` 输出。

这说明当前观察应被视为 compiler/codegen-sensitive。这里保留的 present-first candidate
只是历史讨论材料，不是 upstream-ready fix，也不应写成 generic kernel regression fix。

## 内容

- `reproducer/`：从 workload source 抽出的 standalone C reproducer。
- `experiments/`：本地实验框架使用的 workload target/profile。standalone C source
  使用同一套 workload 逻辑，方便维护者不依赖完整框架直接构建。
- `patches/mincore-present-first-fastpath-rfc.patch`：本地 test patch 形状，不可直接发送上游；
  当前只作为历史讨论材料保留。
- `codegen/`：GCC 13.3 和 Clang 18.1.3 下，v6.15/v6.16 original 与本地 variants 的
  `mincore_pte_range()` nm/objdump 对比。
- `lab-validation/`：紧凑 CSV summary、primary 1/2/4 CPU 验证说明、matched-PREEMPT
  release bridge rows、high-CPU v6.16 introduction-window A/B rows，以及 high-CPU
  present-first A/B rows。

## 限制

- timing signal 目前只在 x86/QEMU lab 环境的 GCC-built kernels 上观察到。应把它描述为
  compiler/codegen-sensitive，而不是 generic x86 mincore regression。
- Clang 18.1.3 交叉检查没有复现 generated-code 差异：所有被检查 variants 都生成逐字节
  等价的 `mincore_pte_range()` 输出。
- 还没有做 physical CPU timing。
- present-first patch 目前只在 x86/QEMU lab 环境验证过，已覆盖到 16CPU/32GiB
  no-THP present-PTE scan follow-up。
- 如果未来要继续作为真实 upstream fix 方向推进，还需要 arm64 或 mTHP/large-folio
  保真验证。
- 这里的 patch 文件故意标成 “not for submission”；正式发送前需要真实 commit message、
  Signed-off-by 和架构侧 review。
