# mprotect mm-unstable / Pedro small-folio optimization follow-up

日期：2026-05-19 UTC

本文记录对 Pedro Falcato 的 `mprotect` micro-optimization patchset 的技术分析，并把它和此前对 `mprotect/shared_dirty_full_toggle_64m` 的机制猜测、local sanity、lab sanity 和 state-shape audit 对齐。

## 背景

上游回复中 David Hildenbrand 指向 Pedro 的 patchset：

```text
https://lore.kernel.org/all/20260402141628.3367596-1-pfalcato@suse.de/
https://www.spinics.net/lists/kernel/msg6136206.html
```

Andrew Morton 后续回复说明该 v3 已进入 `mm-unstable`：

```text
https://www.spinics.net/lists/kernel/msg6136707.html
```

本地测试使用的 `mm-unstable` 版本：

```text
akpm/mm.git mm-unstable
commit 444fc9435e57157fcf30fc99aee44997f3458641
version label 7.1.0-rc3-mm-unstable-444fc9435e57
```

## 和我们原先机制猜测的关系

我们此前对 `mprotect/shared_dirty_full_toggle_64m` 的核心解释是：

```text
change_pte_range()
  -> mprotect_folio_pte_batch()
  -> modify_prot_start_ptes()
  -> set_write_prot_commit_flush_ptes()
  -> prot_commit_flush_ptes()
```

`shared_dirty_full_toggle_64m` 是 `MAP_SHARED | MAP_ANONYMOUS` 的 64 MiB mapping。batch probe 直接显示 measured path 上 `nr_ptes=1` 占主导：每个 4 KiB PTE 都要付出 folio lookup、batch-size query、helper dispatch 和 commit/flush machinery 的固定成本，但没有形成有效 batch amortization。

Pedro 的 patchset 正好命中这个方向。`linux-mm-unstable/mm/mprotect.c` 中可见几类变化：

1. helper 被改成 `__always_inline`
   - `prot_commit_flush_ptes()`
   - `page_anon_exclusive_sub_batch()`
   - `commit_anon_folio_batch()`
   - `set_write_prot_commit_flush_ptes()`

2. present-PTE 修改逻辑抽成 `change_present_ptes()`

3. `change_pte_range()` 对 `nr_ptes == 1` 做 special case：

```c
if (likely(nr_ptes == 1)) {
        change_present_ptes(tlb, vma, addr, pte, 1,
                end, newprot, folio, page, cp_flags);
} else {
        change_present_ptes(tlb, vma, addr, pte,
                nr_ptes, end, newprot, folio, page,
                cp_flags);
}
```

代码注释也明确写到：这是为了优化 small-folio common case，让 compiler constant propagation 和 `__always_inline` 生效。

因此，从源码层面看，这个 patchset **确实直接针对我们报告中的 `nr_ptes=1` 固定成本问题的一部分**。

## 为什么它可能只部分修复

这个 patchset 更像是降低 small-folio path 的函数/分发成本，而不是回到 v6.12 的旧路径。

它仍然保留：

- `mprotect_folio_pte_batch()` 用来判断 batch 大小；
- `modify_prot_start_ptes()` / `ptep_get_and_clear()` 相关成本；
- shared dirty 路径上的 `set_write_prot_commit_flush_ptes()` / `prot_commit_flush_ptes()` 提交流程；
- folio/page 识别和 `can_change_shared_pte_writable()` 相关判断。

所以它预期会减轻 `batch=1` 的 per-PTE overhead，但不一定完全消除相对 v6.12 的差距。

## 本地 sanity 结果

本地 clean timing sanity check 运行口径：

```text
kernels: v6.12.77, v6.19.9, akpm/mm mm-unstable 444fc9435e57
QEMU: direct boot
guest CPUs: QEMU_SMP=1/2/4
guest memory: QEMU_MEM_MB=6144
kernel config: SMP+ACPI enabled
cmdline: tsc=unstable clocksource=refined-jiffies
coverage: disabled
repetitions: 9
order: interleaved
```

结果目录：

```text
mprotect-shared-dirty-toggle/mm-unstable-local-sanity/local_1cpu/
mprotect-shared-dirty-toggle/mm-unstable-local-sanity/local_2cpu/
mprotect-shared-dirty-toggle/mm-unstable-local-sanity/local_4cpu/
```

主指标 `cycle_ns_per_page`，越低越好：

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | mm-unstable vs v6.12 |
|---:|---:|---:|---:|---:|---:|
| 1 | 247.8 | 397.2 | 350.9 | 快约 11.7% | 仍慢约 41.6% |
| 2 | 326.4 | 486.0 | 450.9 | 快约 7.2% | 仍慢约 38.1% |
| 4 | 352.8 | 541.1 | 503.1 | 快约 7.0% | 仍慢约 42.6% |

辅助指标同向：

| CPU | metric | mm-unstable vs v6.19 | mm-unstable vs v6.12 |
|---:|---|---:|---:|
| 1 | `protect_ns_per_page` | 快约 21.2% | 仍慢约 87.0% |
| 1 | `restore_ns_per_page` | 快约 19.4% | 仍慢约 162.6% |
| 2 | `protect_ns_per_page` | 快约 11.7% | 仍慢约 70.3% |
| 2 | `restore_ns_per_page` | 快约 5.9% | 仍慢约 104.9% |
| 4 | `protect_ns_per_page` | 快约 13.8% | 仍慢约 129.7% |
| 4 | `restore_ns_per_page` | 快约 10.2% | 仍慢约 149.7% |

## lab sanity 结果

2026-05-20 已在 lab 上补跑 `1/2/4/8/16 CPU` matrix。结果目录：

```text
mprotect-shared-dirty-toggle/mm-unstable-lab-sanity/
```

主指标 `cycle_ns_per_page`，越低越好：

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | mm-unstable vs v6.12 |
|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 快约 6.6% | 仍慢约 47.9% |
| 2 | 369.2 | 581.9 | 503.3 | 快约 13.5% | 仍慢约 36.3% |
| 4 | 355.7 | 587.2 | 524.2 | 快约 10.7% | 仍慢约 47.4% |
| 8 | 369.7 | 583.6 | 534.2 | 快约 8.5% | 仍慢约 44.5% |
| 16 | 374.8 | 607.1 | 547.8 | 快约 9.8% | 仍慢约 46.2% |

这比本地 sanity 更有价值：它确认 patchset 在 lab 上也能减轻 synthetic
signal，但没有消除相对 v6.12 的差距。

## 可靠性限制

本地 sanity check 仍只作为先导材料。lab 结果的边界如下：

- `1/2/4/8 CPU` 三个版本均完成 9/9。
- `16 CPU` 的 `v6.12.77` 有 1 次 QEMU failure，因此只作为趋势参考。
- 这仍然是 synthetic/source-calibrated workload，不是实际应用 workload。

2026-05-20 又补了一轮 state-shape audit，专门检查这个 mprotect workload 是否存在
类似 `MADV_PAGEOUT` 那样的“新老版本实际页状态不同”的问题：

```text
mprotect-shared-dirty-toggle/state-audit-lab/summary-20260520.zh-CN.md
```

这轮不是 timing evidence。它显示 `v6.12.77`、`v6.19.9`、`mm-unstable`
成功 run 中的关键状态一致：`expected_match_ratio=100`、`unexpected_results=0`、
最终 1 个 VMA、protect 前后都是 16384 个 present pages、`AnonHugePages=0`、
Kernel/MMU page size 都是 4 KiB、`THPeligible=0`。因此，当前 mprotect
结果不像 `MADV_PAGEOUT` 那样因为 actual THP/page state 不一致而需要撤回
same-state 比较口径。

最稳妥的表述是：

```text
Pedro's small-folio mprotect optimization is directly relevant to the
nr_ptes == 1 hypothesis. In my lab sanity matrix it reduces the
synthetic shared-dirty signal compared with v6.19.9, but it does not
remove the gap to v6.12.77 in this workload.
```

如果需要补充 state-audit 结果，可以加：

```text
I also ran a state-shape audit. The successful runs across v6.12.77,
v6.19.9, and mm-unstable all used the same 4 KiB shared-dirty PTE mapping
shape, so I do not currently see a MADV_PAGEOUT-style state mismatch here.
```

## 当前结论

- 从源码看，patchset 命中了我们原先的 `batch=1` 固定成本解释。
- 从本地和 lab sanity 看，它降低了 `v6.19` 的开销，但没有回到 `v6.12` 水平。
- 后续如果 lab 仍显示剩余差距，应继续区分：
  - `mprotect_folio_pte_batch()` batch-size 判断成本；
  - `modify_prot_start_ptes()` / x86 `ptep_get_and_clear()` 成本；
  - shared dirty writable restore 的 commit/flush 成本；
  - helper inline 后仍存在的 per-PTE fixed cost。
