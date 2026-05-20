# old-faster 主信号与历史候选的源码行级归因分析

更新时间：2026-05-14 UTC（当前状态校准）

本文件最初对 `cross_platform_old_faster_reliability.zh-CN.md` 中的 4 个早期跨平台 old-faster 信号做 v6.12 → v6.19 源码行级归因。2026-05 之后，当前 formal 口径已经收窄：真正还作为独立 old-faster 主信号引用的是 `mprotect/shared_dirty_full_toggle` 与 `madvise/pageout_refault_anon`；`damon/large_region` 已收口为 benchmark artifact，`readahead/unaligned_middle` 已降级为历史 workflow 观察。

## 当前状态速览

| 条目 | 当前性能结论 | 根因/机制状态 |
|---|---|---|
| `mm/mprotect.c / shared_dirty_full_toggle` | 当前独立 old-faster 主信号；`6.12` 相对 `6.19` 稳定更快 | 高置信函数级归因：`change_pte_range()` 批处理重写在 shared-dirty `batch=1` 路径上引入额外固定成本；batch probe 已直接支持 |
| `MADV_PAGEOUT` / THP / no-swap 链：`madvise -> vmscan -> swapfile -> huge_memory` | 当前独立 old-faster 回归族；`madvise/pageout_refault_anon` 是入口层主信号，`vmscan`、`swapfile`、`huge_memory` 是同一链路的下游证据 | 机制已收敛到 THP 默认路径下的 pageout/refault 与 no-swap swap-allocation failure/reclaim worst-case；`swapfile` 已压到 `folio_alloc_swap()` / `swap_alloc_fast()` / `swap_alloc_slow()` 热路径，但不应写成单一文件或单一函数的无 caveat 全平台定案 |
| `mm/oom_kill.c / process_mrelease split_vmas_reap` | 历史 catalog-external focused 线索；不再作为当前 formal old-faster 或 root-cause candidate 推进 | attribution probe 与 exact single-shape refresh 已完成：见 [process_mrelease_split_vmas_attribution.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/process_mrelease/process_mrelease_split_vmas_attribution.zh-CN.md)。本地+lab `4CPU` 15-repeat clean refresh 均为 stable/reliable neutral；结果没有复现 `split_vmas_16_128m` 的强 old-faster，也没有随 VMA 数或 mapping size 单调放大；当前不应写成已确定源码根因 |
| `mm/damon/core.c / large_region` | 不再作为正式 old-faster；保留为 benchmark warmup / SLUB artifact 方法论案例 | 当前不是 DAMON 稳态性能回归，不需要继续寻找 DAMON 单点根因 |
| `mm/readahead.c / unaligned_middle_consume_file` | 不再作为正式 old-faster；steady-state 未复现 | 代码变化存在，但稳态性能差异未成立；只保留为历史 workflow 观察 |

**补充实验摘要**（2026-04-12 完成）：前一轮定向验证实验（batch probe、`change_huge_pmd()` probe + smaps/pagemap snapshot、mprotect size scan、madvise size scan、readahead steady-state）之后，又补做了一轮 `1CPU / 2CPU / 4CPU × 本地 / 实验室` 多 CPU 复核。结果：信号 1 的 `shared_dirty batch=1` 假设获得直接证据，并在多 CPU 下继续保持方向稳定；信号 3 跨 size、跨 CPU 数稳定复现；信号 2 在多 CPU 下翻向或失去经典可靠性，进一步支持其为 benchmark artifact；信号 4 在 steady-state 变体中不复现、应降级。详见各信号"补充实验"小节与 [mm_multicpu_validation.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/out/reports/platform_reruns/mm_multicpu_validation.zh-CN.md)。

**最新 formal refresh**（2026-05-13 完成）：`mprotect/shared_dirty_full_toggle_64m` 与 `madvise/pageout_refault_anon_16m` 已在实验室服务器按 `noapic=false`、SMP+ACPI、`QEMU_MEM_MB=14336`、`1/2/4 CPU` clean performance 矩阵重跑，结果整理在 [confirmed_regressions_refresh_2026-05-13.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/out/reports/platform_reruns/confirmed_regressions_refresh_2026-05-13.zh-CN.md)。这轮进一步加固 `madvise/pageout`：lab `1/2/4 CPU` 全部 clean reliable，`6.12` 快约 `41%`。`mprotect/shared_dirty` 方向同样保持 old-faster，但本轮 `2CPU` 只达到 robust-only，`4CPU` 有一次 QEMU failure/partial，因此引用这轮矩阵时要显式保留 caveat。本地 `madvise` 因无 `noapic` 的 `v6.12 1CPU` coverage run 触发 IO-APIC timer panic，被停止且不可作为完整证据。

---

## 信号 1：`mm/mprotect.c / shared_dirty_full_toggle`

> 本地 -19.3%, 服务器 -44.2%, 同文件 anon 路径方向相反

### 归因结论：已定位到函数级

根因在 v6.19 对 `change_pte_range()` 的 **批处理重写**。

### 关键变化清单

| 变化 | v6.12 位置 | v6.19 位置 | 说明 |
|------|-----------|-----------|------|
| `change_pte_range()` 整体重写 | `mm/mprotect.c:166` | `mm/mprotect.c:214` | 从逐 PTE 处理改为 folio 批量处理 |
| 新增 `mprotect_folio_pte_batch()` | 不存在 | `mm/mprotect.c:106` | 调用 `folio_pte_batch_flags()` 查询连续 PTE 批次 |
| 新增 `prot_commit_flush_ptes()` | 不存在 | `mm/mprotect.c:120` | 批量提交 PTE 修改 + TLB flush |
| 新增 `commit_anon_folio_batch()` | 不存在 | `mm/mprotect.c:172` | 匿名 folio 批量提交子路径 |
| 新增 `set_write_prot_commit_flush_ptes()` | 不存在 | `mm/mprotect.c:191` | 写保护 + commit + flush 一体化 |
| `can_change_pte_writable()` 拆分为 3 函数 | `mm/mprotect.c:32` (单函数) | `mm/mprotect.c:41,61,79` | 拆成 `maybe_change_pte_writable()`, `can_change_private_pte_writable()`, `can_change_shared_pte_writable()` |
| 批量 PTE 修改入口 | `ptep_modify_prot_start()` (单 PTE) | `modify_prot_start_ptes()` (批量, line 269) | v6.19 line 269 |
| NUMA 检查 | 内联 if 检查 | `folio_can_map_prot_numa()` (line 260) | 提取为独立函数 |
| folio 批量 flags | 不存在 | `FPB_RESPECT_SOFT_DIRTY \| FPB_RESPECT_WRITE` (line 241) | 控制批处理忽略哪些 PTE bit |

### 回归机制分析

#### workload 测量的内容

`shared_dirty_full_toggle` 来自 `mprotect_paths` profile（`profile.toml:36`），做的是：

1. `mmap(16MB, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS)`
2. 逐页写入，让所有 PTE 存在且 dirty
3. `mprotect(..., PROT_READ)` — RW → RO
4. `mprotect(..., PROT_READ | PROT_WRITE)` — RO → RW
5. 再逐页写入

指标 `cycle_ns_per_page` = `(protect_ns + restore_ns + post_touch_ns) / protected_pages`（生成逻辑在 `mprotect_paths.py:464`）。其中与 `mm/mprotect.c` 最直接相关的是步骤 3、4 的 `change_pte_range()` 逐 PTE 改权限成本。

#### v6.12 的路径：直接

v6.12 的 `change_pte_range()` 核心路径（`mprotect.c:86`），对每个 present PTE：

```c
oldpte = ptep_modify_prot_start(vma, addr, pte);   // 取 PTE + 开始修改
ptent = pte_modify(oldpte, newprot);                // 改权限 bit
if (can_change_pte_writable(vma, addr, ptent))      // shared dirty 时很轻
    ptent = pte_mkwrite(ptent, vma);
ptep_modify_prot_commit(vma, addr, pte, oldpte, ptent); // 提交单个 PTE
if (pte_needs_flush(oldpte, ptent))
    tlb_flush_pte_range(tlb, addr, PAGE_SIZE);      // 必要时 flush 单页
```

对 shared dirty 来说，`can_change_pte_writable()` 主要检查 `pte_dirty(pte)`（`mprotect.c:74`）：如果 shared PTE 已 dirty，内核认为文件系统已经历写通知，直接把 PTE 恢复 writable，避免后续写 fault。

#### v6.19 的路径：批处理框架

v6.19 的 `change_pte_range()` 重写后（`mprotect.c:214`），每个 present PTE 需要经过：

```c
page = vm_normal_page(vma, addr, oldpte);           // 新增
folio = page_folio(page);                            // 新增
nr_ptes = mprotect_folio_pte_batch(folio, ...);     // 新增：查询批次大小
oldpte = modify_prot_start_ptes(vma, addr, pte, nr_ptes); // 批量版 start
ptent = pte_modify(oldpte, newprot);
// 恢复写权限时走分发：
if (try_change_writable && !pte_write(ptent))
    set_write_prot_commit_flush_ptes(...);           // 新增分发层
else
    prot_commit_flush_ptes(...);
```

其中 `set_write_prot_commit_flush_ptes()`（`mprotect.c:191`）对 shared mapping 还要再拆一层：

```
change_pte_range
  → set_write_prot_commit_flush_ptes (line 191)
      → can_change_shared_pte_writable (line 79)
          → maybe_change_pte_writable (line 41)
      → prot_commit_flush_ptes (line 120)
          → modify_prot_commit_ptes
          → 可能 flush
```

#### 关键：shared dirty 为什么吃不到批处理收益

`mprotect_folio_pte_batch()` 的逻辑（`mprotect.c:106`）：

```c
if (!folio)
    return 1;
if (!folio_test_large(folio))
    return 1;          // ← base page 直接返回 1
return folio_pte_batch_flags(...);
```

`shared_dirty_full_toggle` 是 `MAP_SHARED | MAP_ANONYMOUS` 的 16MB mapping，逐页写入。这个场景下**不会形成 large folio**——shared anonymous mapping 不走 THP，所有页面都是 4KB base page。因此 `folio_test_large()` 恒假，`nr_ptes` 恒等于 1。

v6.19 的实际执行退化为：

```
每个 PTE:
    vm_normal_page()          // 额外
    page_folio()              // 额外
    folio_test_large() → 否   // 额外
    返回 nr_ptes = 1          // 批处理"空转"
    modify_prot_start_ptes(1个)
    set_write_prot_commit_flush_ptes(1个)
      → can_change_shared_pte_writable
      → prot_commit_flush_ptes(1个)
```

这是最尴尬的情况：**批处理的固定成本被每个 4KB PTE 单独承担，但每次只处理 1 个 PTE，完全摊不掉。**

#### 成本模型

```
v6.12 每页成本 ≈ pte_start + pte_modify + dirty_check + pte_commit + flush_check

v6.19 每页成本 ≈ vm_normal_page + page_folio + folio_test_large
                + batch_query(返回1) + pte_start_batch(1)
                + pte_modify + helper_dispatch
                + shared_writable_check(多一层调用)
                + pte_commit_batch(1) + flush_check
```

当 `batch_size = 1`（shared dirty 的实际情况，已被 probe 直接证实）时：

```
cost_v6.19_per_pte > cost_v6.12_per_pte  →  v6.12 更快
```

当热路径主要由 THP / huge-PMD 处理、从而避开逐 PTE 批处理时：

```
大量页面可在 PMD 粒度处理，显著减少逐 PTE 循环成本  →  v6.19 更快或持平
```

#### 为什么 anon 路径方向相反

这正是这个归因可信的关键：**同一个 `mm/mprotect.c`，shared dirty 变慢，但 anon 路径方向相反**。

Private anonymous mapping 在 `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y` 下倾向形成 2MB THP。补充实验显示：在计数窗口内，anon 场景的 batch histogram 为 0（`mprotect_batch_calls=0`），而 coverage 仍记录到少量 `change_pte_range()` / `mprotect_folio_pte_batch()` 命中。这说明当前 batch counter **不能**被解释为"anon 的 PTE batch size 为 0"，也不能单独作为"完全不进入 PTE 路径"的直接证据。

更严谨的解释是：anon 的主要性能收益来自 THP / huge-PMD 参与后减少逐 PTE 处理，或者至少来自与 shared dirty 完全不同的热路径。这个判断现在已经由新增 `change_huge_pmd()` probe 与 workload 侧 `smaps/pagemap` 快照补强为直接观测：本地和实验室服务器两端都显示 `anon_full_toggle_16m/64m` 存在稳定的 `mprotect_huge_pmd_calls` / `mprotect_huge_pmd_ret_hpage` 命中，且 `AnonHugePages` 分别等于映射大小、`THPeligible=100%`；而 `shared_dirty_full_toggle_16m/64m` 的 `huge_pmd` 计数恒为 0，`AnonHugePages=0`，`THPeligible=0`。需要保留的边界是：这证明 anon 的 measured hot path 明确包含 huge-PMD/THP 参与，但**不能**据此断言 anon 完全 PMD-only，因为 coverage 仍能看到少量 `change_pte_range()` 命中。

所以这不是"v6.19 的 mprotect 全面变慢"，而是更精确的结论：

> **v6.19 对 THP/anon 路径带来收益，但让无法形成有效批次的 shared dirty mapping 走 PTE batch=1 路径，承担额外 per-PTE 批处理框架开销。**

实验数据完全吻合：

| 场景 | 6.12 vs 6.19 | 实际路径 | 机制 |
|------|-------------|---------|------|
| `shared_dirty_full_toggle` | -44.2%（6.12 更快） | PTE 级, batch=1（probe 直接证实） | 批处理固定成本按单页摊销，纯亏 |
| `anon_full_toggle` | +75.8%~+123.2%（6.19 更快） | THP/anon 热路径（batch counter=0 + size scan 间接支持） | 避开或显著减少逐 PTE 批处理成本 |
| `anon_split_restore` | +98.5%（6.19 更快） | THP/anon 热路径 | 同上 |

三个场景的方向由是否能从 THP/anon 热路径受益决定：shared dirty 无法形成有效 batch → 走 PTE batch=1 路径 → 额外开销；anon 在 THP always 下更可能受益于 huge-page 粒度处理或更高效的 anon 路径 → 方向相反。

#### 服务器比本地回归更严重的解释

服务器 -44.2% vs 本地 -19.3%：服务器 CPU 更快，syscall 本体时间更短，额外函数调用链占 per-PTE 时间的比例更高，所以百分比放大。

#### 新增归因验证：nr_ptes 分布直接证据

已经新增一套更干净的 batch-size 观测路径，避免用 `pr_info_ratelimited()` 污染 serial log：

- workload 侧：`mprotect_paths` 会尝试读取 `/proc/ptg_mprotect_batch`，并输出 `mprotect_batch_*` 指标；如果内核没有打 probe 补丁，这些指标保持为 `0`。
- 内核 probe：`mm_regression_gen/mprotect/attribution/mprotect_batch_probe_v6.19.patch` 在 v6.19 `mprotect_folio_pte_batch()` 中统计 `nr_ptes` histogram，并通过 `/proc/ptg_mprotect_batch` 暴露。
- profile：`mprotect_batch_probe_attribution` 同时跑 `anon_full_toggle` 与 `shared_dirty_full_toggle`，并收集 batch histogram；`mprotect_attribution_mapping_scan` 另用于跨版本 size scan。

实测结果已经完成，本地与实验室服务器均跑通：

| 环境 | 场景 | `mprotect_batch_calls` | `mprotect_batch_mean_nr_ptes` | `mprotect_batch_nr_1` | `mprotect_batch_nr_512_plus` | 结论 |
|------|------|-----------------------:|------------------------------:|----------------------:|-----------------------------:|------|
| 本地 | `shared_dirty_full_toggle_16m` | 640614.4 | 1.0 | 640614.4 | 0.0 | 全部是 `nr_ptes=1` |
| 本地 | `shared_dirty_full_toggle_64m` | 668467.2 | 1.0 | 668467.2 | 0.0 | 全部是 `nr_ptes=1` |
| 实验室服务器 | `shared_dirty_full_toggle_16m` | 1035468.8 | 1.0 | 1035468.8 | 0.0 | 全部是 `nr_ptes=1` |
| 实验室服务器 | `shared_dirty_full_toggle_64m` | 1101004.8 | 1.0 | 1101004.8 | 0.0 | 全部是 `nr_ptes=1` |

这把 `shared_dirty_full_toggle` 的核心机制从推理推进到了直接观测：该场景确实没有形成有效 PTE batch，`mprotect_folio_pte_batch()` 的返回值稳定为 1。于是 v6.19 新增的 folio 查询、batch flags 判断、批量提交函数分发等固定成本都只能按单页摊销，成为纯 per-PTE 额外开销。

需要注意一个边界：本轮 probe 在 `anon_full_toggle` 上读到的 batch 计数为 **全 0**（`mprotect_batch_calls=0`, `mprotect_batch_total_ptes=0`, 所有桶均为 0）。这并非 batch size 为 0，也不能单独证明 anon 完全不进入 PTE 级别的 `change_pte_range()`。

原因是计数窗口和 coverage 的口径不同：workload 在 warmup 后才重置 `/proc/ptg_mprotect_batch`，因此 batch histogram 只反映 measured window；而 coverage 统计覆盖整个运行过程，仍能看到 anon 场景中少量 `change_pte_range()` / `mprotect_folio_pte_batch()` 命中。实验室服务器上 `anon_full_toggle_16m/64m` 的 `mprotect_folio_pte_batch` coverage 平均命中数为 61，但 measured-window batch counter 为 0。

这个发现自身仍然有意义：**anon 的 measured hot path 没有表现出 shared_dirty 那种大量 PTE-level batch=1 计数**。因此 anon 方向相反不是对 shared_dirty batch=1 模型的反证，而是说明二者处在不同热路径上。

因此本轮 batch histogram **只能直接证明 shared dirty 是 batch=1**，不能声称已经观测到 anon 的 PTE 级 `nr_ptes=512` 分布，也不能仅凭 counter=0 直接证明 anon 完全 PMD-only。

#### 新增归因验证：`change_huge_pmd()` + smaps/pagemap 直接证据

为把 "anon/THP 热路径" 从强推断推进到更直接的证据链，本轮又补了两类观测：

- 内核侧 probe：`mm_regression_gen/mprotect/attribution/mprotect_huge_pmd_probe_v6.19.patch` 在 `change_huge_pmd()` 周围暴露 `/proc/ptg_mprotect_huge_pmd`
- workload 侧快照：`mprotect_paths` 在 `before_protect` / `after_restore` 读取 `smaps` 与 `pagemap`，记录 `AnonHugePages`、`THPeligible`、`KernelPageSize`、`MMUPageSize`、`present_pages`

两端实测结果完全同方向：

| 环境 | 场景 | `mprotect_huge_pmd_calls` | `mprotect_huge_pmd_ret_hpage` | `smaps_before_protect_anon_huge_kb_avg` | `smaps_before_protect_thpeligible_pct` | 结论 |
|------|------|--------------------------:|-------------------------------:|----------------------------------------:|---------------------------------------:|------|
| 本地 | `anon_full_toggle_16m` | 4144.0 | 4144.0 | 16384 | 100 | measured hot path 命中 huge-PMD/THP |
| 本地 | `anon_full_toggle_64m` | 5145.6 | 5145.6 | 65536 | 100 | measured hot path 命中 huge-PMD/THP |
| 本地 | `shared_dirty_full_toggle_16m` | 0.0 | 0.0 | 0 | 0 | 无 THP / 无 huge-PMD |
| 本地 | `shared_dirty_full_toggle_64m` | 0.0 | 0.0 | 0 | 0 | 无 THP / 无 huge-PMD |
| 实验室服务器 | `anon_full_toggle_16m` | 9814.4 | 9814.4 | 16384 | 100 | measured hot path 命中 huge-PMD/THP |
| 实验室服务器 | `anon_full_toggle_64m` | 9100.8 | 9100.8 | 65536 | 100 | measured hot path 命中 huge-PMD/THP |
| 实验室服务器 | `shared_dirty_full_toggle_16m` | 0.0 | 0.0 | 0 | 0 | 无 THP / 无 huge-PMD |
| 实验室服务器 | `shared_dirty_full_toggle_64m` | 0.0 | 0.0 | 0 | 0 | 无 THP / 无 huge-PMD |

补充一致性检查：

- 两端 `anon_full_toggle_16m/64m` 的 `pagemap_before_protect_present_pages_avg` 分别稳定为 `4096/16384`，说明映射已完整建立
- 两端 `shared_dirty` 场景的 `KernelPageSize=4KB`、`MMUPageSize=4KB`、`AnonHugePages=0`
- 两端 coverage 都仍能看到 anon 场景中少量 `change_pte_range()` / `mprotect_folio_pte_batch()` 命中，因此正确表述应为：**anon 的 measured hot path 明确包含 huge-PMD/THP 参与，但并非已证明完全 PMD-only**

这一步把证据链补全成了两层：

- `shared_dirty`：已有 batch histogram 直接证明 `nr_ptes=1`
- `anon`：新增 `change_huge_pmd()` probe + `smaps/pagemap` 直接证明 THP / huge-PMD 热路径参与

因此，`shared_dirty` 与 `anon` 方向相反不再只是 "看起来像不同路径"，而是已经有了跨平台一致的直接路径证据。anon 路径方向相反再由跨版本 mprotect size scan 独立支撑：

#### mprotect size scan 结果（实验室服务器）

| 场景 | v6.12 (ns/page) | v6.19 (ns/page) | Δ | reliable |
|------|----------------:|----------------:|----:|:--------:|
| `anon_full_toggle_16m` | 434.8 | 194.8 | **+123.2%** (6.12 慢) | ✅ |
| `anon_full_toggle_64m` | 408.6 | 218.2 | **+87.3%** (6.12 慢) | ✅ |
| `shared_dirty_full_toggle_64m` | 322.8 | 622.6 | **-48.2%** (6.12 快) | ✅ |
| `shared_dirty_full_toggle_16m` | 329.6 | 683.0 | **-51.7%** (6.12 快) | 部分 |
| `shared_dirty_full_toggle_4m` | 338.8 | 710.8 | **-52.3%** (6.12 快) | 部分 |

64M 的 shared_dirty 比较为双向 robust_reliable（cv 分别为 0.070 和 0.076），提供了最可靠的对比点 **-48.2%**，与之前 whole-mm 服务器结果 (-44.2%) 高度一致。

anon 方向完全相反：v6.12 在 16M 下比 v6.19 **慢 2.2 倍**、64M 下**慢 1.9 倍**。这继续支持"v6.19 批处理重写对 THP/anon 路径有收益、对 shared dirty batch=1 路径有代价"的完整模型。

#### 补充实验：`1CPU / 2CPU / 4CPU` 多 CPU 复核

多 CPU 复核见 [mm_multicpu_validation.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/out/reports/platform_reruns/mm_multicpu_validation.zh-CN.md)。`shared_dirty_full_toggle_64m / cycle_ns_per_page` 的结果如下：

| 环境 | CPU | 6.12 | 6.19 | Δ | comparison_reliable |
|------|----:|-----:|-----:|---:|:-------------------:|
| 本地 | 1 | 397.4 | 712.4 | -44.2% | yes |
| 本地 | 2 | 286.4 | 405.4 | -29.4% | yes |
| 本地 | 4 | 305.4 | 434.4 | -29.7% | yes |
| 实验室服务器 | 2 | 440.0 | 701.8 | -37.3% | yes |
| 实验室服务器 | 4 | 455.2 | 708.6 | -35.8% | yes |

这轮复核给出的关键信息是：

- 多 CPU 会改变幅度，但不会改变方向
- `6.12` 在 `shared_dirty` 上始终更快，且各点都保持 `comparison_reliable=yes`
- 因而 `Signal 1` 不是单 CPU 伪信号；`1CPU` 只是让 batch=1 路径上的固定开销占比看起来更大
- 这进一步强化了当前的主结论：shared dirty 的真实问题，是 v6.19 在无法形成有效 batch 的路径上引入了稳定的 per-PTE 额外成本

#### 最新 formal refresh：实验室 `noapic=false` 矩阵

2026-05-13 对当前 confirmed 主信号做了实验室 formal refresh，结果目录为 [confirmed_regressions_refresh_lab_20260513T121012Z/mprotect_shared_dirty_formal_refresh](/home/lcf/kernel-study/mm_regression_gen/out/confirmed_regressions_refresh_lab_20260513T121012Z/mprotect_shared_dirty_formal_refresh)。运行条件为 `QEMU_MEM_MB=14336`、SMP+ACPI、`noapic=false`、每个版本/场景 9 次、clean performance `1/2/4 CPU`。

`shared_dirty_full_toggle_64m / cycle_ns_per_page`：

| CPU | 6.12 | 6.19 | Δ | reliable | robust reliable | status |
|----:|-----:|-----:|---:|:--------:|:---------------:|--------|
| 1 | 346.8 | 578.1 | -40.0% | yes | yes | ok |
| 2 | 394.7 | 641.7 | -38.5% | no | yes | ok |
| 4 | 381.1 | 624.8 | -39.0% | no | no | partial: one QEMU failure |

coverage split 同时确认直接路径命中：`6.12` 为 `10/15` observable functions，`6.19` 为 `12/23` observable functions，二者均 `ok_runs=9`、`failed_runs=0`。这轮不改变 `batch=1` 根因判断；它更新的是证据分层：本轮 lab `1CPU` 是 clean reliable，`2CPU` 是 robust-only，`4CPU` 只能作为同方向 partial 辅助观察。

---

## 信号 2：`mm/damon/core.c / large_region`

> 本地 -25.8%, 服务器 -14.1%, cv=0.013

### 归因结论：已定位到 SLUB 分配器行为变化 + benchmark 顺序效应

回归不来自 DAMON 代码逻辑变化，而是来自 v6.19 SLUB 分配器 fastpath 的指令布局 / warmup 行为改变。

### 关键变化清单

#### DAMON 层（`mm/damon/core.c`、`include/linux/damon.h`）

| 变化 | v6.12 位置 | v6.19 位置 | 说明 |
|------|-----------|-----------|------|
| `damon_new_region()` | `core.c:121-139` | `core.c:117-135` | **完全一致**（`kmem_cache_alloc` + 赋值） |
| `damon_destroy_region()` | `core.c:158` | `core.c:154` | 功能一致（`list_del` + `kmem_cache_free`） |
| `damon_add_region()` | `core.c:141` | `core.c:137` | 功能一致（`list_add_tail` + `nr_regions++`） |
| `damon_new_target()` | `core.c:436-449` | `core.c:465-479` | 仅新增 `t->obsolete = false;`（line 477） |
| `damon_free_target()` | `core.c:467` | `core.c:497` | **完全一致**（遍历 regions + `kfree`） |
| `damon_destroy_target()` | `core.c:476`（1 参数） | `core.c:506`（2 参数） | v6.19 新增 `ctx->ops.cleanup_target` 调用；但 benchmark 传入的 target 没有挂到 ctx 上，走 `damon_free_target()` 不受影响 |
| `struct damon_target` 大小 | 48 bytes → kmalloc-64 | 49→56 bytes → kmalloc-64 | 新增 `bool obsolete`，**未跨越 slab size class** |
| `struct damon_region` | 56 bytes（`KMEM_CACHE` 专用 slab） | 56 bytes（完全一致） | 无变化 |
| 文件整体行数 | 2249 行 | 2983 行 | **+33% 代码量** |

#### SLUB 层（`mm/slub.c`）

| 变化 | v6.12 | v6.19 | 说明 |
|------|-------|-------|------|
| 文件行数 | 7523 行 | 10236 行 | **+36% 代码量** |
| `slab_alloc_node()` | 直接调用 `__slab_alloc_node()` | 新增 `if (s->cpu_sheaves) alloc_from_pcs()` 前置分支 | 即使 `cpu_sheaves=NULL`（DAMON 场景），也多一次条件跳转 |
| `__slab_alloc_node()` | 直接 fastpath | 新增 `strict_numa` 静态分支检查 | `static_branch_unlikely` 正常路径零开销，但改变了函数体大小和指令布局 |
| PCS (per-CPU sheaves) | 不存在 | 新增 ~2700 行完整子系统 | `KMEM_CACHE` 和默认 `kmalloc` 不启用，但代码存在改变了 `.text` 布局 |

### 回归机制分析

#### workload 测量的内容

`large_region` benchmark（`damon_core.bench.c`）循环 100000 次执行：

```c
target = damon_new_target();           // kmalloc(~48 bytes, GFP_KERNEL)
region = damon_new_region(0, 2MB);     // kmem_cache_alloc(damon_region_cache)
damon_add_region(region, target);      // list_add_tail + nr_regions++
benchmark_sink += damon_nr_regions(target);  // return nr_regions
damon_destroy_region(region, target);  // list_del + nr_regions-- + kmem_cache_free
damon_free_target(target);             // iterate(empty) + kfree
```

指标 `ns_per_iter` = 整个循环的壁钟时间 / iterations。

#### 关键发现：`small_region` 对照组否定了 DAMON 逻辑变化假设

同一 benchmark module 中，`small_region` 在 `large_region` 之前运行（数组下标 0 vs 1），代码路径**完全一致**，唯一差异是 `damon_new_region(0, 4096)` vs `damon_new_region(0, 2UL*1024*1024)`——仅赋值常量不同：

| scenario | v6.12 ns/iter | v6.19 ns/iter | 变化 | cv(6.12) | cv(6.19) |
|----------|--------------|--------------|------|----------|----------|
| `small_region`（先跑，cold） | 668.4 | 669.7 | **+0.2%** | 0.007 | 0.012 |
| `large_region`（后跑，warm） | 574.4 | 669.1 | **+16.5%** | 0.013 | 0.009 |

如果回归来自 DAMON 函数的逻辑变化，`small_region` 也应该出现相同幅度的回归。但 `small_region` 在 v6.12 和 v6.19 之间**完全持平**（+0.2%, cv 极低）。

真正的差异在于 **v6.12 的 "second-run warmup benefit" 消失了**：

- v6.12：`small_region`（cold）= 668 → `large_region`（warm）= 574，**预热加速 14.1%**
- v6.19：`small_region`（cold）= 670 → `large_region`（warm）= 669，**预热加速 0.1%**
- v6.18：`small_region`（cold）= 580 → `large_region`（warm）= 577，**预热加速 0.5%**

#### 其他 scenario 交叉验证

| scenario | 含义 | v6.12 | v6.19 | 变化 |
|----------|------|-------|-------|------|
| `region_only_large` | 纯 region alloc/free（栈上 target，不走 kmalloc） | 275.6 | 289.6 | +5.1% |
| `empty_target` | 纯 target alloc/free（不分配 region） | 259.2 | 252.6 | **-2.6%** |
| `alloc_only` | 仅 `damon_new_target()` 批量分配 | 121.6 | 128.4 | +5.7% |
| `free_only` | 仅 `damon_free_target()` 批量释放 | 169.1 | 134.9 | **-20.2%** |

`empty_target` 和 `free_only` 在 v6.19 上反而更快，进一步排除了 DAMON 代码逻辑导致回归的可能性。

#### 根因：SLUB fastpath 指令布局变化消除了 slab warmup 效应

v6.12 的 SLUB `slab_alloc_node()` 的 fastpath 非常紧凑：

```c
// v6.12: slab_alloc_node() → __slab_alloc_node()
s = slab_pre_alloc_hook(s, gfpflags);
object = kfence_alloc(s, orig_size, gfpflags);     // unlikely
object = __slab_alloc_node(s, gfpflags, ...);       // 直接进入
  → c = raw_cpu_ptr(s->cpu_slab);
  → object = c->freelist;
  → cmpxchg fastpath
```

v6.19 的 `slab_alloc_node()` 在进入 `__slab_alloc_node()` 之前新增了一个分支：

```c
// v6.19: slab_alloc_node()
s = slab_pre_alloc_hook(s, gfpflags);
object = kfence_alloc(s, orig_size, gfpflags);     // unlikely
if (s->cpu_sheaves)                                  // ← 新增分支（对 DAMON 恒 false）
    object = alloc_from_pcs(s, gfpflags, node);
if (!object)
    object = __slab_alloc_node(s, gfpflags, ...);
  → // __slab_alloc_node() 内部也新增了 strict_numa 检查
```

这些新增代码虽然在 DAMON 场景下不会被真正执行（`cpu_sheaves=NULL`、`strict_numa` 默认 false），但它们：

1. **增大了 `slab_alloc_node()` 的函数体**，改变了 icache 行占用
2. **插入了额外的条件跳转指令**，占据了分支预测器 BTB 条目
3. 整个 `slub.c` 从 7523→10236 行（+36%），`.text` 段中 SLUB 相关函数的物理地址全部偏移

v6.12 下，当 `small_region`（先跑 120000 次）将 slab fastpath 加载到 icache 和 L1 后，紧接着运行的 `large_region` 能直接命中预热的 cache lines。v6.19 下，因为 fastpath 函数体更大、指令更多，icache footprint 增加，加上 DAMON 自身 `core.c` 也增长了 33%（热路径函数地址偏移），导致预热效应被稀释。

#### 为什么只有 `large_region` 受影响

这是一个 **benchmark 测量 artifact**：

1. `small_region` 作为数组中第一个 scenario，测量的是"冷启动"状态下的 slab 性能
2. `large_region` 作为第二个 scenario，测量的是"前一个 scenario 预热后"的 slab 性能
3. v6.12 的 SLUB fastpath 更紧凑 → 预热后 icache 命中率更高 → `large_region` 比 `small_region` 快 14%
4. v6.19 的 SLUB fastpath 更膨胀 → 预热效应消失 → `large_region` ≈ `small_region`

表面看是 `large_region` "回归"了 16.5%，实际上是 v6.12 的 `large_region` 因为预热效应"异常快"了 14%。v6.19 的绝对性能（669 ns/iter）与 v6.12 的冷启动性能（668 ns/iter）几乎一致。

### 归因总结

| 层面 | 归因 | 证据 |
|------|------|------|
| DAMON 代码逻辑 | **已排除** | `small_region` 与 `large_region` 代码路径完全相同，但只有后者出现回归 |
| `struct damon_target` slab class | **已排除** | v6.12 48B → v6.19 49→56B，均落在 kmalloc-64，未跨越边界 |
| `struct damon_region` slab | **已排除** | 两版结构体完全一致，56B，`KMEM_CACHE` 专用 slab |
| SLUB fastpath 指令膨胀 | **主因** | `slub.c` +36%（7523→10236 行），新增 PCS 分支 + strict_numa 检查 |
| DAMON `core.c` 编译布局 | **辅因** | +33%（2249→2983 行），热函数地址偏移 |
| benchmark 顺序效应 | **触发条件** | 仅第二个 scenario 体现回归，因预热效应被 SLUB 膨胀消除 |

> **结论：`large_region` 的 -14.1%/-25.8% old-faster 信号是真实可重复的，但它测量的不是 DAMON 代码变化的直接效果，而是 SLUB 分配器 fastpath 指令布局膨胀导致的 slab warmup 效应消失。v6.19 的"冷"性能（669 ns/iter）与 v6.12 的"冷"性能（668 ns/iter）实际上一致。**

### 补充实验：`1CPU / 2CPU / 4CPU` 多 CPU 复核

多 CPU 复核见 [mm_multicpu_validation.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/out/reports/platform_reruns/mm_multicpu_validation.zh-CN.md)。`large_region / ns_per_iter` 的关键结果如下：

| 环境 | CPU | 6.12 | 6.19 | Δ | comparison_reliable |
|------|----:|-----:|-----:|---:|:-------------------:|
| 本地 | 1 | 574.4 | 669.1 | -14.1% | yes |
| 本地 | 2 | 433.0 | 369.3 | +17.3% | no |
| 本地 | 4 | 369.7 | 346.0 | +6.9% | no |
| 实验室服务器 | 2 | 1449.1 | 1336.7 | +8.4% | yes |
| 实验室服务器 | 4 | 1382.4 | 1314.4 | +5.2% | no |

实验室服务器上的 `small_region` 同时表现为：

- `2CPU`: `1272.4 → 1358.1`, `Δ=-6.3%`, `comparison_reliable=yes`
- `4CPU`: `1221.9 → 1395.0`, `Δ=-12.4%`, `comparison_reliable=no`

这轮复核把 `Signal 2` 的性质进一步钉实了：

- 它不是那种在 CPU 数变化后仍保持同方向的稳态回归
- `large_region` 在 `1CPU` 下是 old-faster，但到 `2CPU / 4CPU` 会翻成 `6.12` 更慢或失去经典可靠性
- 邻近的 `small_region` 又同时朝相反方向漂移，这和“单一路径真实回归”不一致

因此，多 CPU 结果不是削弱了 benchmark artifact 的判断，恰恰是进一步强化了它：`Signal 2` 应被正式视为 warmup / SLUB / 调度环境敏感的 artifact，而不应再与 `mprotect`、`madvise` 放在同一层级引用。

---

## 信号 3：`mm/madvise.c / pageout_refault_anon`

> 本地 -42.2%, 服务器 -40.3%, THP 依赖（nohugepage 后反转 +13.5%）

### 归因结论：已定位到 3 个关键变化点 + THP 子系统交互

### 关键变化清单

| 变化 | v6.12 位置 | v6.19 位置 | 说明 |
|------|-----------|-----------|------|
| `madvise_folio_pte_batch()` 签名重写 | `madvise.c:324-333` | `madvise.c:344-352` | 见下方详细分析 |
| 共享检测 API 替换 | `folio_likely_mapped_shared()` | `folio_maybe_mapped_shared()` | PMD 路径 line 399(v6.19) / PTE 路径 line 495(v6.19) |
| PMD migration 检查 API | `is_pmd_migration_entry()` | `pmd_is_migration_entry()` | `madvise.c:377`(v6.12) → `madvise.c:393`(v6.19) |
| PTE 批量 flags 语义 | `FPB_IGNORE_DIRTY \| FPB_IGNORE_SOFT_DIRTY` | `FPB_MERGE_YOUNG_DIRTY` | 从 "忽略后比较" 改为 "合并到首个 PTE" |
| large folio 批量路径简化 | 需要 `any_young`/`any_dirty` 回写 | 由 `FPB_MERGE_YOUNG_DIRTY` 自动处理 | v6.19 取消了手动 `pte_mkyoung()` |
| `folio_maybe_mapped_shared()` 新实现 | `include/linux/mm.h:2183` | `include/linux/mm.h:2399` | v6.19 走 `test_bit(FOLIO_MM_IDS_SHARED_BITNUM, ...)` |
| 文件整体行数 | 1559 行 | 2257 行 | **+45% 代码量** |

### 变化点 1：`madvise_folio_pte_batch()` 签名重写

**v6.12** (`madvise.c:324-333`):
```c
static inline int madvise_folio_pte_batch(unsigned long addr, unsigned long end,
    struct folio *folio, pte_t *ptep,
    pte_t pte, bool *any_young, bool *any_dirty)
{
    const fpb_t fpb_flags = FPB_IGNORE_DIRTY | FPB_IGNORE_SOFT_DIRTY;
    return folio_pte_batch(folio, addr, ptep, pte, max_nr, fpb_flags, NULL,
                           any_young, any_dirty);
}
```

**v6.19** (`madvise.c:344-352`):
```c
static inline int madvise_folio_pte_batch(unsigned long addr, unsigned long end,
    struct folio *folio, pte_t *ptep, pte_t *ptentp)
{
    return folio_pte_batch_flags(folio, NULL, ptep, ptentp, max_nr,
                                 FPB_MERGE_YOUNG_DIRTY);
}
```

关键差异：
- v6.12 的 `folio_pte_batch()` 用 `FPB_IGNORE_DIRTY` 标志在比较时清除 dirty bit，通过 `any_young`/`any_dirty` 输出参数报告是否有任何 young/dirty PTE
- v6.19 的 `folio_pte_batch_flags()` 用 `FPB_MERGE_YOUNG_DIRTY` 标志直接修改传入的 `*ptentp`，将整个批次的 young/dirty 信息合并到第一个 PTE 的副本中
- v6.19 版本额外增加了 `VM_WARN_ON(virt_addr_valid(ptentp) && PageTable(...))` 安全检查

### 变化点 2：`folio_likely_mapped_shared()` → `folio_maybe_mapped_shared()`

**v6.12** (`include/linux/mm.h:2183-2202`):
```c
static inline bool folio_likely_mapped_shared(struct folio *folio)
{
    int mapcount = folio_mapcount(folio);
    if (!folio_test_large(folio) || unlikely(folio_test_hugetlb(folio)))
        return mapcount > 1;
    if (mapcount <= 1) return false;
    if (folio_entire_mapcount(folio) || mapcount > folio_nr_pages(folio))
        return true;
    return atomic_read(&folio->_mapcount) > 0;  // 基于子页 mapcount 猜测
}
```

**v6.19** (`include/linux/mm.h:2399-2422`):
```c
static inline bool folio_maybe_mapped_shared(struct folio *folio)
{
    int mapcount = folio_mapcount(folio);
    if (!folio_test_large(folio) || unlikely(folio_test_hugetlb(folio)))
        return mapcount > 1;
    if (!IS_ENABLED(CONFIG_MM_ID))
        return true;                             // 无 MM_ID 时保守返回 true
    if (mapcount <= 1) return false;
    return test_bit(FOLIO_MM_IDS_SHARED_BITNUM, &folio->_mm_ids);  // 基于 mm_ids 位图
}
```

关键差异：
- v6.12 对大 folio 使用 `folio_entire_mapcount()` + 子页 `_mapcount` 的启发式猜测
- v6.19 引入了全新的 `CONFIG_MM_ID` 机制，使用 `folio->_mm_ids` 位图中的 shared bit 来判断
- 这改变了大 folio 的共享检测快路径，可能导致在 THP 默认路径下更多 folio 被误判为 shared 而跳过 pageout

### 变化点 3：PTE batch flag 语义翻转

这是最根本的架构变化。v6.12 的 `__pte_batch_clear_ignored()` 通过 `FPB_IGNORE_*` 标志在比较前清除特定 bit，然后通过独立的 `any_young`/`any_dirty` 输出参数让调用者决定如何处理。v6.19 将这一逻辑反转为 `FPB_RESPECT_*`（默认忽略）+ `FPB_MERGE_*`（将信息合并到首 PTE 副本），减少了调用者的复杂度但增加了 `folio_pte_batch_flags()` 内部的分支和写操作。

具体差异：

**v6.12** (`internal.h:167-173`):
```c
static inline pte_t __pte_batch_clear_ignored(pte_t pte, fpb_t flags)
{
    if (flags & FPB_IGNORE_DIRTY)     pte = pte_mkclean(pte);
    if (flags & FPB_IGNORE_SOFT_DIRTY) pte = pte_clear_soft_dirty(pte);
    return pte_wrprotect(pte_mkold(pte));  // ← 总是清除 write + accessed
}
```

**v6.19** (`internal.h:227-235`):
```c
static inline pte_t __pte_batch_clear_ignored(pte_t pte, fpb_t flags)
{
    if (!(flags & FPB_RESPECT_DIRTY))      pte = pte_mkclean(pte);
    if (!(flags & FPB_RESPECT_SOFT_DIRTY)) pte = pte_clear_soft_dirty(pte);
    if (!(flags & FPB_RESPECT_WRITE))      pte = pte_wrprotect(pte);  // ← 条件化
    return pte_mkold(pte);
}
```

此外，v6.19 在循环体中增加了 MERGE 分支：
```c
// v6.19 folio_pte_batch_flags() 循环内
if (flags & FPB_MERGE_WRITE)   any_writable |= pte_write(pte);
if (flags & FPB_MERGE_YOUNG_DIRTY) {
    any_young |= pte_young(pte);
    any_dirty |= pte_dirty(pte);
}
```
以及循环后的合并写入：
```c
if (any_writable) *ptentp = pte_mkwrite(*ptentp, vma);
if (any_young)    *ptentp = pte_mkyoung(*ptentp);
if (any_dirty)    *ptentp = pte_mkdirty(*ptentp);
```

madvise 的 pageout 路径使用 `FPB_MERGE_YOUNG_DIRTY`，意味着每次 PTE 扫描循环内都多了 2 个条件分支 + 2 次 OR 操作。但由于 madvise PTE walk 本身在 THP PMD 路径下根本不执行（见下方分析），**这个变化在本 benchmark 场景中影响极小**。

### 深度根因分析：`reclaim_pages()` 内 THP swap 分配失败路径

#### workload 关键路径重建

`pageout_refault_anon` 的完整 cycle 是：

1. `mmap(16MB, MAP_ANONYMOUS)` → 匿名 VMA
2. 逐页写入（prefault）→ THP enabled，分配 8 × 2MB huge page（PMD 映射）
3. `madvise(MADV_PAGEOUT)` → 进入 `madvise_cold_or_pageout_pte_range()`
4. 逐页写入（refault）→ 重新分配物理页

步骤 3 的 `madvise_cold_or_pageout_pte_range()` 对 THP 走 PMD 快路径（`pmd_trans_huge(*pmd)` 为 true）：
- 对每个 2MB PMD entry，直接取 `pmd_folio()`
- 检查共享、执行 `folio_isolate_lru()` 隔离
- 最后调用 `reclaim_pages(&folio_list)` 回收

**关键事实：测试环境（QEMU initramfs）没有配置 swap。**

serial log 确认 `errno_enomem=0`，说明 `madvise()` 系统调用本身返回 0（成功），但这只是表面——`reclaim_pages()` 内部的 swap 分配失败被静默吸收了。

#### `shrink_folio_list()` 中 THP 无 swap 的失败路径

两版的 `shrink_folio_list()` 对匿名 swapbacked large folio 都走以下路径：

**v6.12** (`vmscan.c:1250-1289`)：
```
folio_test_anon && folio_test_swapbacked → true
  → can_split_folio(folio, 1, NULL)     // 检查是否可拆分
  → add_to_swap(folio)                  // 尝试分配 swap slot
    → folio_alloc_swap(folio)           // 对 large folio: get_swap_pages(1, &entry, folio_order(folio))
    → 无 swap → 返回 swp_entry_t{.val=0} → add_to_swap 返回 false
  → folio_test_large(folio) → true
  → split_folio_to_list(folio, folio_list)  // ★ 拆分 2MB THP 为 512 × 4KB
  → 每个 4KB 页面: add_to_swap(folio) → 再次失败 → activate_locked_split
```

**v6.19** (`vmscan.c:1289-1327`)：
```
folio_test_anon && folio_test_swapbacked → true
  → folio_expected_ref_count(folio) != folio_ref_count(folio) - 1  // 新的 split 可行性检查
  → folio_alloc_swap(folio)             // 新合并函数，包含 swap_alloc_fast/slow + swap_cache_add_folio
    → 无 swap → 返回 -ENOMEM
  → folio_test_large(folio) → true
  → split_folio_to_list(folio, folio_list)  // ★ 同样拆分
  → 每个 4KB 页面: folio_alloc_swap(folio) → 再次失败 → activate_locked_split
```

**两版在无 swap 时的行为模式完全一致：都会把每个 2MB THP 拆分成 512 × 4KB 页面，然后逐个尝试 swap、全部失败、全部 activate。** 但它们的 per-iteration 成本不同。

#### 性能差异来源 1：`can_split_folio()` vs `folio_expected_ref_count()` 快路径

v6.12 在尝试 swap 之前先调用 `can_split_folio(folio, 1, NULL)` 做预检。如果预检失败直接 `goto activate_locked`，不走 swap 分配→拆分→重试的完整路径。

v6.19 用 `folio_expected_ref_count(folio) != folio_ref_count(folio) - 1` 替换了这个预检。在 `folio_isolate_lru()` 之后，folio 的 refcount 状态可能使这个检查更宽松（不容易提前退出），导致更多 folio 走完整的 swap 分配→失败→拆分→重试流程。

#### 性能差异来源 2：`folio_alloc_swap()` 重写带来的每次调用开销变化

v6.12 的 `folio_alloc_swap()` 在 `mm/swap_slots.c:305`：
```c
// 对 large folio：直接调用 get_swap_pages(1, &entry, folio_order(folio))
// 无 swap 时很快返回空 entry
```

v6.19 的 `folio_alloc_swap()` 在 `mm/swapfile.c:1421`，被彻底重写为一个更重的函数：
```c
// 对 large folio：调用 swap_alloc_fast() → swap_alloc_slow()
// 然后调用 swap_cache_add_folio() + mem_cgroup_try_charge_swap()
// 失败时还需要清理
```

v6.19 合并了 swap slot 分配 + swap cache 添加为一个函数，在成功路径上更高效（减少了一次独立的 `add_to_swap_cache()` 调用），但在**失败路径**上可能更重——每次 folio 都要走 `local_lock(&percpu_swap_cluster.lock)` → `swap_alloc_fast()` → `swap_alloc_slow()` → `mem_cgroup_try_charge_swap()` → 失败清理。

由于 16MB mapping = 8 × 2MB THP，每个 THP 拆分为 512 × 4KB，总共 `8 × (1 + 512) = 4104` 次 `folio_alloc_swap()` 失败调用（先大 folio 一次失败，拆分后 512 次失败）。微小的 per-call 开销差异在这个规模下被放大。

#### 性能差异来源 3：`split_folio_to_list()` 及其下游变化

`split_folio_to_list()` 拆分 2MB THP 时涉及大量 rmap、page table 操作。v6.19 在这些路径上也有变化（`folio_pte_batch` 重写、`MM_ID` 维护等），拆分的成本可能高于 v6.12。

### THP 方向反转机制的完整解释

THP 对照实验数据（default: -33.2%, nohugepage: +13.5%）揭示了 THP 是这个回归的**必要且充分条件**：

**THP default 路径（v6.19 慢 ~40%）：**

1. 匿名页面分配为 8 × 2MB THP（PMD 映射）
2. `MADV_PAGEOUT` 的 PMD 路径通过共享检测后隔离 folio
3. `reclaim_pages()` 对每个 2MB folio：swap 分配失败 → **拆分为 512 × 4KB** → 逐个重试 swap → 全部失败 → 全部 activate
4. 这 `4104` 次 swap 失败 + 8 次 THP 拆分构成了 `advise_ns` 的主体
5. v6.19 的 `folio_alloc_swap()` 重写、`split_folio` 下游变化、以及预检逻辑差异使每次迭代更慢
6. `folio_maybe_mapped_shared()` 基于 `MM_ID` 位图的新机制在 THP 场景下行为不同（但在单进程 benchmark 中两版都判断为 exclusive，此因素影响较小）

**THP nohugepage 路径（v6.19 快 ~13.5%）：**

1. 所有页面为 4KB 小页（4096 个 base page）
2. `MADV_PAGEOUT` 走 PTE 路径，`folio_test_large()` 为 false，不触发 batch/split 逻辑
3. `reclaim_pages()` 对每个 4KB folio：swap 分配失败 → 直接 `activate_locked_split`（不拆分）
4. 单次 `folio_alloc_swap()` 对 order-0 page 更简单
5. v6.19 在 PTE 遍历的基础路径上有其他优化（如 `folio_pte_batch_flags` 的内联特化），加上 `madvise_cold_or_pageout_pte_range` 循环结构的微优化，反而更快

### 补充：`reclaim_pages()` 函数级不变，但调用者的 folio 组成变化了

`mm/vmscan.c` 中的 `reclaim_pages()` 函数在两版之间功能完全一致（v6.12 line 2176, v6.19 line 2219）。但它的下游 `shrink_folio_list()` 存在显著差异（见上方分析），虽然 `reclaim_pages()` 本身的调度逻辑不变，其性能仍因下游 swap 分配和 folio 拆分路径的重写而改变。

### 补充：`try_to_unmap_one()` 中 PTE batching 不适用

v6.19 在 `rmap.c:1823` 新增了 `folio_unmap_pte_batch()`，但其中有硬性前置条件：
```c
if (!folio_test_anon(folio) || folio_test_swapbacked(folio))
    return 1;  // ← 匿名 swapbacked 页面不做批量 unmap
```
`pageout_refault_anon` 的匿名页面全部是 swapbacked，因此 unmap 路径不会产生批量化差异。

### 根因定级

| 因素 | 归因级别 | 说明 |
|------|---------|------|
| `shrink_folio_list()` 中无 swap 时 THP 拆分 + 重试路径 | **主因** | 8 × 2MB THP 的 4104 次 `folio_alloc_swap()` 失败调用，v6.19 per-call 开销更高 |
| `folio_alloc_swap()` 从 `swap_slots.c` 迁移到 `swapfile.c` 的完全重写 | **主因** | 合并了 swap cache 操作，失败路径变重 |
| `can_split_folio()` → `folio_expected_ref_count()` 预检变化 | **辅因** | 可能改变进入完整失败路径的概率 |
| PTE batch flag 语义翻转 (`FPB_IGNORE_*` → `FPB_RESPECT_*` + `FPB_MERGE_*`) | **间接因素** | PMD 路径不经过 PTE batch；仅在 THP 被拆分后的小页路径上有微弱影响 |
| `folio_likely_mapped_shared()` → `folio_maybe_mapped_shared()` | **已排除** | 单进程 benchmark，两版都判断为 exclusive |
| `madvise_folio_pte_batch()` 签名重写 | **间接因素** | THP default 路径走 PMD 不经过此函数 |

### 补充实验：madvise size scan 结果

#### pageout_refault_anon（old-faster 信号）

实验室服务器上 `pageout_refault_anon` 在所有 mapping 大小下均稳定复现 old-faster 方向：

| 场景 | v6.12 cycle_ns/page | v6.19 cycle_ns/page | Δ | cv(6.12) | cv(6.19) | robust_reliable |
|------|---------------------:|---------------------:|----:|:--------:|:--------:|:---------------:|
| `pageout_refault_anon_4m` | 1755.4 | 3076.0 | **-42.9%** | 0.026 | 0.007 | ✅ |
| `pageout_refault_anon_16m` | 1802.6 | 2941.6 | **-38.7%** | 0.005 | 0.006 | ✅ |
| `pageout_refault_anon_64m` | 1817.2 | 2981.8 | **-39.1%** | 0.005 | 0.011 | ✅ |

advise_ns 拆分也一致（-40%~-44%），说明回归主导性来自 madvise syscall 触发的 reclaim/vmscan 下游路径，而非 refault 消耗。

本地 QEMU 同方向：4M -34.6%、16M -38.3%、64M -37.9%。

三个 size 点均 robust_reliable、方向一致、幅度一致，排除了 size-dependent 的偶发因素。这是 4 个信号中跨条件最稳定的一个。

QEMU serial log 原始数据验证：
- v6.12: `advise_ns_avg=4,456,800`, `post_touch_ns_avg=1,000,062`
- v6.19: `advise_ns_avg=11,236,813`, `post_touch_ns_avg=1,083,401`
- post_touch（refault）几乎相同，**回归主导性来自 advise_ns**（即 madvise 系统调用内部；post_touch_ns 有微小差异但相对于 advise_ns 的数倍差距可忽略）

#### dontneed_refault_anon（对照组，方向相反）

| 场景 | v6.12 cycle_ns/page | v6.19 cycle_ns/page | Δ | robust_reliable |
|------|---------------------:|---------------------:|----:|:-----------            v6.12    v6.18    v6.19
Lab 2CPU:   2357     3020     3905   → v6.18 faster than v6.19 ✓
Local 2CPU: 2043     3275     2771   → v6.18 SLOWER than v6.19 ✗----:|
| `dontneed_refault_anon_4m` | 11799.0 | 2277.6 | **+418.0%** (6.12 慢) | ✅ |
| `dontneed_refault_anon_16m` | 11546.6 | 2226.2 | **+418.7%** (6.12 慢) | ✅ |
| `dontneed_refault_anon_64m` | 11613.8 | 2353.0 | **+393.6%** (6.12 慢) | ✅ |

v6.12 在 MADV_DONTNEED 路径上慢了 **4-5 倍**——方向完全相反。这证明 madvise 的 old-faster 信号不能泛化为"旧版本 madvise 都更快"，而是严格限定于 `MADV_PAGEOUT + refault` 这一特定工作流。

`dontneed` 在 v6.12 上极慢的原因值得单独注记：`MADV_DONTNEED` 对匿名页面会直接 zap PTE 并释放物理页，refault 时需要重新分配+清零。v6.12 的这条路径在 THP 配置下可能存在 folio split / 批量释放的效率问题，而 v6.19 的 PTE batch 重写和 folio 批量操作在此处带来了 4-5 倍的加速。

### 实际意义评估

#### 信号的真实性：✅ 确认为真实回归

- 跨平台（QEMU + 实验室服务器）方向一致、幅度一致（-34% ~ -43%）
- 跨 mapping size（4M/16M/64M）幅度一致
- cv < 0.03，robust_reliable = true
- advise_ns / post_touch_ns 拆分清晰，回归主导性来自 madvise 系统调用触发的 reclaim/vmscan 下游路径（非 madvise.c 的 PTE batching 本体）

#### 信号的实际影响：⚠️ 有限但值得关注

**触发条件极为特殊**：这个回归需要同时满足以下全部条件：

1. **THP 启用**（`TRANSPARENT_HUGEPAGE_ALWAYS` 或 `MADVISE`）
2. **对匿名 THP 执行 `MADV_PAGEOUT`**
3. **系统没有足够的 swap 空间**（或 swap 分配失败）

在这种组合下，`reclaim_pages()` 内部会触发"THP 拆分 → 逐页 swap 重试 → 全部失败"的 worst-case 路径。

**真实场景映射：**

- 容器 / cgroup 内存回收：运维通过 `MADV_PAGEOUT` 主动回收冷内存时，如果 swap 配额不足或未配置 swap，会命中此路径
- Android low-memory killer：Android 使用 `MADV_PAGEOUT` 做应用内存回收，在 swap 不足时可能触发
- 虚拟化 guest（如本测试环境）：initramfs / 极简 VM 通常不配置 swap

**不会触发 / 幅度预计明显收敛的场景：**

- 正常配置 swap 的服务器：`folio_alloc_swap()` 大概率成功，不会触发 THP 拆分+逐页重试的 worst-case 路径，因此该回归幅度预计会明显收敛（但不排除 swap 分配本身因重写带来微量开销差异）
- 仅使用 `MADV_DONTNEED` 的应用：走完全不同的路径（且 v6.19 反而快了 4-5 倍）
- THP 禁用的环境：不产生 large folio，不走拆分路径

**结论：这是一个真实的、可定量复现的性能回归，但其触发条件（THP + MADV_PAGEOUT + 无 swap）在生产环境中相对罕见。主导性来源不是 `madvise.c` 的 PTE batch 改写，而是 `MADV_PAGEOUT` 在 THP 默认路径下触发的 `reclaim_pages()` → `shrink_folio_list()` 回收链；在当前无 swap 测试环境中，large folio 会反复经历"swap 分配失败 → THP 拆分 → 逐页重试 → 再次失败"的 worst-case 路径，而 v6.19 的 `folio_alloc_swap()` / swap 分配失败路径更重，从而把回归集中放大在 `advise_ns` 上。正常配置 swap 的服务器大概率不会触发这条 no-swap worst-case，因此该回归幅度预计会明显收敛。如果需要追踪上游修复，应关注 `folio_alloc_swap()` 的失败快路径优化。**

### 补充实验：`1CPU / 2CPU / 4CPU` 多 CPU 复核

多 CPU 复核见 [mm_multicpu_validation.zh-CN.md](/home/lcf/kernel-study/mm_regression_gen/out/reports/platform_reruns/mm_multicpu_validation.zh-CN.md)。`pageout_refault_anon / cycle_ns_per_page` 的结果如下：

| 环境 | CPU | 6.12 | 6.19 | Δ | comparison_reliable |
|------|----:|-----:|-----:|---:|:-------------------:|
| 本地 | 1 | 1836.8 | 3075.0 | -40.3% | yes |
| 本地 | 2 | 1373.2 | 2267.2 | -39.4% | yes |
| 本地 | 4 | 1497.0 | 2342.4 | -36.1% | yes |
| 实验室服务器 | 2 | 2550.0 | 3895.0 | -34.5% | yes |
| 实验室服务器 | 4 | 2568.6 | 3915.0 | -34.4% | yes |

这轮复核进一步说明：

- `Signal 3` 不依赖单 CPU 才成立，`2CPU / 4CPU` 下方向完全不翻
- 幅度从 `-40%` 左右收敛到大约 `-34% ~ -36%`，但依然稳定且全部 `comparison_reliable=yes`
- 因而它应被视为带边界条件的稳健真实信号，而不是单核环境中的偶发现象

#### 最新 formal refresh：实验室 `noapic=false` 矩阵

2026-05-13 formal refresh 进一步把这条加固为当前最干净的已确认 old-faster 结果。结果目录为 [confirmed_regressions_refresh_lab_20260513T121012Z/madvise_pageout_formal_refresh](/home/lcf/kernel-study/mm_regression_gen/out/confirmed_regressions_refresh_lab_20260513T121012Z/madvise_pageout_formal_refresh)。运行条件同样为 `QEMU_MEM_MB=14336`、SMP+ACPI、`noapic=false`、每个版本/场景 9 次、clean performance `1/2/4 CPU`。

`pageout_refault_anon_16m / cycle_ns_per_page`：

| CPU | 6.12 | 6.19 | Δ | reliable | robust reliable | status |
|----:|-----:|-----:|---:|:--------:|:---------------:|--------|
| 1 | 1900.3 | 3304.7 | -42.5% | yes | yes | ok |
| 2 | 2107.7 | 3583.2 | -41.2% | yes | yes | ok |
| 4 | 2154.2 | 3690.9 | -41.6% | yes | yes | ok |

更贴近 `madvise(MADV_PAGEOUT)` / reclaim 主段的 `advise_ns_per_page` 也同向且全部 reliable：`1CPU=-41.4%`、`2CPU=-39.1%`、`4CPU=-40.5%`。coverage split 显示 `6.12` 覆盖 `9/25` observable functions、`6.19` 覆盖 `21/56` observable functions，二者均 `ok_runs=9`、`failed_runs=0`。

本地同轮 `madvise` 不可引用：它在 `split_1cpu / v6.12 r09` 遇到 `IO-APIC + timer` panic 后被停止。这不会影响 lab 结论，但本地目录只能作为失败现场保留。

更准确的收口是：

- 多 CPU 会影响绝对百分比
- 但不会改变当前最关键的机制判断：在 `THP default + no swap` 下，`MADV_PAGEOUT` 触发的 reclaim/vmscan worst-case 路径在 `6.19` 上依然更重

---

## 信号 4：`mm/readahead.c / unaligned_middle_consume_file`

> 本地 readahead_ns -5.4%, 服务器 cycle_ns -9.1%, 跨平台 reliable 指标不同

### 归因结论：已定位到 3 个函数级变化，但回归幅度小且指标不一致

### 关键变化清单

| 变化 | v6.12 位置 | v6.19 位置 | 说明 |
|------|-----------|-----------|------|
| `page_cache_ra_order()` 签名变化 | `readahead.c:452` (3参数) | `readahead.c:465` (2参数) | order 从参数改为 `ra->order` |
| order 递增逻辑迁移 | `page_cache_ra_order()` 内部 line 476 | `page_cache_async_ra()` 的 readit 标签后 line 689 | 从被调用者迁移到调用者 |
| async_size 赋值时机变化 | 多处 `ra->async_size = ra->size;` 在 goto readit 前 | readit 标签后统一赋值 line 695 | 结构变化 |
| 新增 `ractl_alloc_folio()` | 不存在 | `readahead.c:184-195` | 封装 `filemap_alloc_folio()` + dropbehind 标记 |
| `read_pages()` 残留 folio 清理简化 | `readahead.c:161-174` | `readahead.c:164-167` | 移除 `ra->size` / `ra->async_size` 的调整 |
| fallback 路径条件检查 | `readahead.c:519` 直接 `do_page_cache_ra()` | `readahead.c:530-536` 检查 `ra->size > index - start` | v6.19 防止重复读取 |
| lookahead mark 计算 | `readahead.c:235-237` 无条件计算 | `readahead.c:242-249` 仅当 `lookahead_size <= nr_to_read` 时 | v6.19 增加保护性检查 |
| 新增 trace 点 | 不存在 | line 231, 479, 563, 648 | `trace_page_cache_ra_*` 系列 |
| 文件整体行数 | 809 行 | 838 行 | +3.6% |

### 变化点 1：`page_cache_async_ra()` 中 order 递增逻辑的位置迁移

**v6.12** (`readahead.c:611-677`):
```c
void page_cache_async_ra(...) {
    unsigned int order = folio_order(folio);
    ...
    expected = round_down(ra->start + ra->size - ra->async_size, 1UL << order);
    if (index == expected) {
        ...
        ra->async_size = ra->size;  // ← 在 goto readit 前赋值
        goto readit;
    }
    ...
    ra->async_size = ra->size;      // ← 在 goto readit 前赋值
readit:
    ractl->_index = ra->start;
    page_cache_ra_order(ractl, ra, order);   // order 作为参数传入
}
```

**v6.19** (`readahead.c:631-697`):
```c
void page_cache_async_ra(...) {
    pgoff_t expected, start, end, aligned_end, align;
    ...
    expected = round_down(ra->start + ra->size - ra->async_size,
                          folio_nr_pages(folio));  // 用 folio_nr_pages 代替 1UL << order
    if (index == expected) {
        ...
        // ← 注意：此处不再设置 ra->async_size
        goto readit;
    }
    ...
    // ← 此处也不再设置 ra->async_size
readit:
    ra->order += 2;                                    // ← order 递增从 callee 迁移到 caller
    align = 1UL << min(ra->order, ffs(max_pages) - 1);
    end = ra->start + ra->size;
    aligned_end = round_down(end, align);
    if (aligned_end > ra->start)
        ra->size -= end - aligned_end;                 // ← 新增：按 order 对齐裁剪 ra->size
    ra->async_size = ra->size;                         // ← 统一在此处赋值
    ractl->_index = ra->start;
    page_cache_ra_order(ractl, ra);                    // 不再传 order 参数
}
```

关键影响：
- v6.19 在 readit 标签后新增了 order 对齐裁剪逻辑（`round_down(end, align)`），这**在代码层面**会缩小 readahead 窗口使其对齐到 order 边界
- 对于 "unaligned_middle" 这个场景（读取位置不对齐），这个裁剪逻辑在首轮 readahead 中会被触发；但 steady-state 实验表明其稳态影响不可测量（见下方补充实验）

### 变化点 2：`page_cache_ra_order()` 内部 order 递增的移除

**v6.12** (`readahead.c:475-476`):
```c
if (new_order < mapping_max_folio_order(mapping))
    new_order += 2;                  // ← 在 callee 内部递增 order
```

**v6.19** (`readahead.c:478-489`):
```c
// 此处不再有 order += 2；递增逻辑已迁移到 page_cache_async_ra() 的 readit 标签后
new_order = min(mapping_max_folio_order(mapping), new_order);
new_order = min_t(unsigned int, new_order, ilog2(ra->size));
new_order = max(new_order, min_order);
ra->order = new_order;                // ← 将最终 order 回写到 ra
```

这意味着 v6.19 中 order 的递增（`+2`）在 `page_cache_async_ra()` 调用 `page_cache_ra_order()` **之前**就已完成，而 v6.12 是在 `page_cache_ra_order()` **内部**递增。这改变了 order 值在整个 readahead 流程中的生效时机。

### 变化点 3：`read_pages()` 残留 folio 清理的简化

**v6.12** (`readahead.c:161-174`):
```c
while ((folio = readahead_folio(rac)) != NULL) {
    unsigned long nr = folio_nr_pages(folio);
    folio_get(folio);
    rac->ra->size -= nr;           // ← 调整 ra->size
    if (rac->ra->async_size >= nr) {
        rac->ra->async_size -= nr; // ← 调整 ra->async_size
        filemap_remove_folio(folio);
    }                               // ← else: folio 被保留，不移除！
    folio_unlock(folio);
    folio_put(folio);
}
```

**v6.19** (`readahead.c:164-167`):
```c
while ((folio = readahead_folio(rac)) != NULL) {
    folio_get(folio);
    filemap_remove_folio(folio);   // ← 无条件移除
    folio_unlock(folio);
    folio_put(folio);
}
```

v6.12 在清理残留 folio 时会保留 `async_size` 以下的 folio（不移除它们，留在 page cache 供后续 async readahead 使用），同时调整 `ra->size` 和 `ra->async_size` 以确保后续 readahead 窗口计算准确。v6.19 简化为无条件移除所有残留 folio，不再调整 `ra` 状态。

这个简化配合 fallback 路径中新增的 `if (ra->size > index - start)` 防护检查（v6.19 line 530-536），改变了 readahead 在遇到 page cache 冲突时的恢复策略。

### 回归机制分析

"unaligned_middle" 场景的核心特征是：readahead 请求的起始位置不对齐到大 folio 边界。代码层面存在以下变化，曾被列为候选回归机制：

1. v6.19 的 `page_cache_async_ra()` readit 路径新增的 **order 对齐裁剪** (`round_down(end, align)`) 在代码层面确实会缩小 readahead 窗口使其对齐到 order 边界，但 steady-state 实验中未体现出可测量的稳态性能差异（见下方补充实验），说明其实际影响可能仅限于首次 warming 阶段或被其他路径补偿
2. v6.19 `read_pages()` 简化后的 **无条件移除残留 folio** 策略在代码上确实存在，但这条清理路径只在 `aops->readahead()` 返回后仍有未消费 folio 时才触发——这是错误恢复路径，不是正常热路径，在 benchmark 的稳态执行中大概率不参与
3. 新增的 4 个 trace 点（`trace_page_cache_ra_unbounded`, `trace_page_cache_ra_order`, `trace_page_cache_sync_ra`, `trace_page_cache_async_ra`）即使在 trace 关闭时也有少量 `tracepoint_active()` 检查开销，但在 steady-state 结果已显示 <1.3% 差异的背景下，此因素的实质影响已被排除

此外，这条信号的跨平台一致性最弱——本地 reliable 的是 `readahead_ns_avg`（-5.4%），服务器 reliable 的是 `cycle_ns_avg`（-9.1%），说明即使存在差异，其在不同硬件上体现在不同的性能维度，缺乏一致性。

### 补充实验：steady-state 变体不复现

为验证 readahead 信号是否来自 readahead syscall 本体的稳态代价，而非首次触发或 page cache warming 效应，设计了 steady-state 变体：先完整读取文件建立 page cache，然后在 cache 热的状态下测量 readahead + consume 循环。

#### 实验室服务器结果

| 场景 | v6.12 cycle_ns/page | v6.19 cycle_ns/page | Δ | cv(6.12) | cv(6.19) | robust_reliable |
|------|---------------------:|---------------------:|----:|:--------:|:--------:|:---------------:|
| `full_range_consume_file_steady` | 9193.2 | 9227.8 | **-0.37%** | 0.002 | 0.005 | ✅ |
| `middle_range_consume_file_steady` | 9365.6 | 9488.2 | **-1.29%** | 0.002 | 0.008 | ✅ |
| `unaligned_middle_consume_file_steady` | 9416.2 | 9497.0 | **-0.85%** | 0.004 | 0.008 | ✅ |

readahead_ns_avg（纯 readahead syscall 时间）：

| 场景 | v6.12 | v6.19 | Δ |
|------|------:|------:|----:|
| `full_range_steady` | 2191387 | 2145759 | **+2.1%** (6.12 慢) |
| `middle_range_steady` | 2142633 | 2178261 | **-1.6%** |
| `unaligned_middle_steady` | 2178886 | 2131383 | **+2.2%** (6.12 慢) |

关键发现：

1. **cycle_ns 差异 < 1.3%**：`unaligned_middle` 的 cycle_ns 差仅 -0.85%，远低于原先 whole-mm 观察到的 -9.1%，在工程意义上视为无实质差异
2. **readahead_ns 方向翻转**：`unaligned_middle` 的 readahead_ns 反而 v6.12 **慢** 2.2%，完全不支持 v6.12 更快的假设
3. **所有场景一致**：full_range / middle_range / unaligned_middle 三个变体的结果高度一致，没有出现 unaligned 特有的回归

#### 本地 QEMU 结果

本地结果方向相同：`unaligned_middle_steady` 的 cycle_ns delta = -2.9%（neutral），readahead_ns delta = +1.5%（neutral）。所有场景 classification = neutral。

#### 结论更新

原先对信号 4 的归因——"v6.19 `page_cache_async_ra()` 新增的 order 对齐裁剪导致 readahead 窗口缩小"——在 steady-state 实验中**未被复现**。这意味着：

1. 原先 whole-mm 测试中观察到的 readahead old-faster 信号可能来自 **首次 readahead 建立 page cache 的 cold-start 过程**——此时 v6.19 的 order 对齐裁剪确实可能导致首轮 readahead 窗口略小，但这只影响 cold-start 性能，不影响稳态
2. 或者，whole-mm 测试的 readahead 场景设计（单次 readahead + 单次 consume）与 steady-state 循环测量的测量点不同，信号出现在初始化路径而非热路径
3. 无论哪种解释，原先的 "readahead syscall 本体退化" 归因应**降级为"完整 workflow 级观察，readahead 稳态路径未见实质差异"**

> **修订后结论**：readahead/unaligned_middle 的 old-faster 信号从"函数级归因"降级为"workflow 级观察"。v6.19 `page_cache_async_ra()` 的 order 对齐裁剪逻辑确实存在代码变化，但 steady-state 验证实验中未体现出稳态性能差异。该信号不应被视为 readahead syscall 本体的回归。

---

## 总表

| 信号 | 归因精度 | 补充实验 | 主要变化位置 | v6.19 行号 | 机制 |
|------|---------|---------|-------------|-----------|------|
| mprotect/shared_dirty | **函数级** ✅ | batch probe 直接证实 shared_dirty `nr_ptes=1`；`1/2/4CPU × 本地/实验室` 方向稳定；2026-05-13 lab refresh 中 `1CPU` clean reliable、`2CPU` robust-only、`4CPU` partial 同方向 | `change_pte_range()` 批处理重写 | `mprotect.c:214` | batch=1 时批处理架构额外开销；anon/THP 热路径方向相反；多 CPU 只改变幅度不改变方向，但最新矩阵引用需保留稳定性 caveat |
| damon/large_region | **artifact 案例** | `1CPU` 为 old-faster，但 `2/4CPU` 翻向或失去经典可靠性 | SLUB fastpath 膨胀 + benchmark 顺序效应 | `slub.c:5340` | 多 CPU 复核进一步支持 warmup / SLUB / 调度环境敏感 artifact，而非稳态回归 |
| madvise/pageout_refault | **变化点级** ✅ | size scan 跨 4M/16M/64M 稳定复现；`1/2/4CPU × 本地/实验室` 方向稳定；2026-05-13 lab refresh 中 `1/2/4CPU` 全部 clean reliable | `shrink_folio_list()` THP swap 失败路径 + `folio_alloc_swap()` 重写 | `vmscan.c:1289-1327`, `swapfile.c:1421` | 主因：无 swap 环境下 THP 反复经历"swap 分配失败→拆分→逐页重试"worst-case，v6.19 失败路径更重；多 CPU 仅让幅度收敛，本轮 lab formal refresh 约 `-41%` |
| readahead/unaligned_middle | **降级为 workflow 级** ⚠️ | steady-state 未复现 (Δ < 1.3%) | `page_cache_async_ra()` order 对齐裁剪 | `readahead.c:689-695` | 代码变化存在但稳态性能无差异；不应归因为 readahead syscall 本体回归 |
