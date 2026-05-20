# 已确认 old-faster 主信号 formal refresh 结果整理

更新时间：2026-05-13 UTC

本页整理 `2026-05-13` 对两个当前 confirmed old-faster 主信号的补跑结果：

- `mm/mprotect.c / shared_dirty_full_toggle_64m`
- `mm/madvise.c / pageout_refault_anon_16m`

## 运行口径

主要证据来自实验室服务器完整矩阵：

- 结果目录：[confirmed_regressions_refresh_lab_20260513T121012Z](/home/lcf/kernel-study/mm_regression_gen/out/confirmed_regressions_refresh_lab_20260513T121012Z)
- 平台：lab server container
- guest memory：`QEMU_MEM_MB=14336`
- repeat：每个版本/场景 `9` 次
- workload external rounds：`5`
- kernel cmdline：`tsc=unstable clocksource=refined-jiffies`
- kernel config：`SMP,ACPI,ACPI_PROCESSOR`
- `noapic=false`
- 方法：`split_1cpu` 用于 coverage + performance 分离验证；`perf_1cpu / perf_2cpu / perf_4cpu` 是 clean performance 矩阵

实验室矩阵完整性检查：

| profile | 完成时间 | matrix sentinel | serial logs | CPU mismatch | noapic logs |
|---|---:|:---:|---:|---:|---:|
| `mprotect_shared_dirty_formal_refresh` | `2026-05-13T12:41:10Z` | yes | split 36 / perf 53 | 0 | 0 |
| `madvise_pageout_formal_refresh` | `2026-05-13T13:05:09Z` | yes | split 36 / perf 54 | 0 | 0 |

本地同步状态：

- 本地结果目录：[confirmed_regressions_refresh_local_20260513T110115Z](/home/lcf/kernel-study/mm_regression_gen/out/confirmed_regressions_refresh_local_20260513T110115Z)
- `mprotect_shared_dirty_formal_refresh` 本地矩阵完成，但稳定性弱于 lab，主要作 sanity check。
- `madvise_pageout_formal_refresh` 本地在 `split_1cpu / v6.12 r09` 遇到无 `noapic` 的 `IO-APIC + timer` kernel panic 后被停止；该本地 `madvise` 目录不能作为完整证据。

## 1. `mprotect/shared_dirty_full_toggle_64m`

指标：`cycle_ns_per_page`，数值越低越快。

实验室 clean performance：

| CPU | 6.12 | 6.19 | Δ | classification | stable | robust | reliable | robust reliable | status |
|---:|---:|---:|---:|---|:---:|:---:|:---:|:---:|---|
| 1 | 346.8 | 578.1 | -40.0% | improvement | yes | yes | yes | yes | ok |
| 2 | 394.7 | 641.7 | -38.5% | improvement | no | yes | no | yes | ok |
| 4 | 381.1 | 624.8 | -39.0% | improvement | no | no | no | no | partial: one QEMU failure |

coverage split：

| version | direct function coverage | source text functions | ok runs | failed runs |
|---|---:|---:|---:|---:|
| 6.12 | 10/15 observable = 66.7% | 18 | 9 | 0 |
| 6.19 | 12/23 observable = 52.2% | 26 | 9 | 0 |

解释：

- 方向仍然支持 `6.12` old-faster，且幅度在 lab `1/2/4 CPU` 都约 `-38% ~ -40%`。
- 最严格口径下，`1CPU` 是 clean reliable；`2CPU` 是 robust-only；`4CPU` 因一次 QEMU failure 和稳定性不足只能作为同方向辅助观察。
- 这不改变既有根因判断：`shared_dirty` 仍指向 v6.19 `change_pte_range()` 批处理重写在 `batch=1` 路径上的 per-PTE 固定成本。
- 但写 formal 结论时，建议不要把这轮 `4CPU` 说成 clean reliable formal evidence。

本地 sanity check：

| CPU | 6.12 | 6.19 | Δ | reliable | robust reliable | status |
|---:|---:|---:|---:|:---:|:---:|---|
| 1 | 237.6 | 360.9 | -34.2% | no | yes | ok |
| 2 | 317.1 | 467.2 | -32.1% | no | no | ok |
| 4 | 405.3 | 541.1 | -25.1% | no | no | ok |

本地同方向，但稳定性不足；当前仍以 lab 为主证据。

## 2. `madvise/pageout_refault_anon_16m`

主指标：`cycle_ns_per_page`，数值越低越快。

实验室 clean performance：

| CPU | 6.12 | 6.19 | Δ | classification | stable | robust | reliable | robust reliable | status |
|---:|---:|---:|---:|---|:---:|:---:|:---:|:---:|---|
| 1 | 1900.3 | 3304.7 | -42.5% | improvement | yes | yes | yes | yes | ok |
| 2 | 2107.7 | 3583.2 | -41.2% | improvement | yes | yes | yes | yes | ok |
| 4 | 2154.2 | 3690.9 | -41.6% | improvement | yes | yes | yes | yes | ok |

辅助指标 `advise_ns_per_page`：

| CPU | 6.12 | 6.19 | Δ | reliable |
|---:|---:|---:|---:|:---:|
| 1 | 1713.2 | 2922.7 | -41.4% | yes |
| 2 | 1924.7 | 3162.9 | -39.1% | yes |
| 4 | 1953.1 | 3284.2 | -40.5% | yes |

coverage split：

| version | direct function coverage | source text functions | ok runs | failed runs |
|---|---:|---:|---:|---:|
| 6.12 | 9/25 observable = 36.0% | 34 | 9 | 0 |
| 6.19 | 21/56 observable = 37.5% | 68 | 9 | 0 |

解释：

- 这是本轮最干净的结果：lab `1/2/4 CPU` 全部 clean reliable，且无 semantic warning / failure。
- `cycle_ns_per_page` 和更贴近 syscall/reclaim 主段的 `advise_ns_per_page` 都稳定显示 `6.12` 更快，幅度约 `-39% ~ -42%`。
- 这进一步加固既有口径：`madvise/pageout_refault_anon` 是当前 formal old-faster 主信号之一，但必须限定在 `THP default + MADV_PAGEOUT + no-swap/refault workflow`。
- 本地本轮没有可引用的完整 `madvise` 矩阵；原因是本地无 `noapic` 的 `v6.12 1CPU` coverage run 触发 IO-APIC timer panic。

## 3. 当前收口

可直接引用：

- `madvise/pageout_refault_anon_16m / cycle_ns_per_page`：lab `1/2/4 CPU` 全部 clean reliable，`6.12` 相对 `6.19` 快约 `41%`；这是本轮 strongest formal refresh 结果。
- `mprotect/shared_dirty_full_toggle_64m / cycle_ns_per_page`：lab 方向在 `1/2/4 CPU` 一致，`1CPU` clean reliable、`2CPU` robust-only、`4CPU` partial；可继续作为 confirmed old-faster 主案例，但引用本轮矩阵时要带上 `2CPU robust-only / 4CPU partial` caveat。

不可直接引用：

- 本地 `madvise_pageout_formal_refresh/split_1cpu`：被 IO-APIC timer panic 中断，不是完整矩阵。
- `mprotect` 的 `protect_ns_per_page` / `restore_ns_per_page` 单项：方向很强，但本轮稳定性不足；主结论仍应使用 `cycle_ns_per_page`。

这轮结果不改变已有根因排序：当前正式 old-faster 主信号仍是 `mprotect/shared_dirty_full_toggle` 与 `madvise/pageout_refault_anon`；其中 `madvise` 在本轮 formal refresh 中更干净，`mprotect` 的机制归因更强但本轮多 CPU 稳定性 caveat 更多。
