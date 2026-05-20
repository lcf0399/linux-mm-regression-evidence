# mprotect mm-unstable lab sanity - 2026-05-20

这轮实验用于回应 David 指出的 Pedro `mprotect` small-folio optimization
是否已经缓解我们报告中的 shared-dirty PTE toggle synthetic signal。

它不是原始上游报告的 formal refresh 替代品，而是一个后续 sanity check：

- 对比版本：`v6.12.77`、`v6.19.9`、`akpm/mm mm-unstable`
- `mm-unstable`：`7.1.0-rc3-mm-unstable-444fc9435e57`
- workload：`shared_dirty_full_toggle_64m`
- lab host：`lcf`
- QEMU：direct boot
- CPU/memory matrix：
  - `1/2/4 CPU` with `QEMU_MEM_MB=14336`
  - `8 CPU` with `QEMU_MEM_MB=16384`
  - `16 CPU` with `QEMU_MEM_MB=32768`
- repetitions：9
- order：interleaved
- coverage：disabled

原始结果目录：

```text
lab_1cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_2cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_4cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_8cpu_mem16384_20260520T084427Z_lab_mprotect_mm_unstable/
lab_16cpu_mem32768_20260520T084427Z_lab_mprotect_mm_unstable/
lab-logs-20260520T084427Z_lab_mprotect_mm_unstable/
```

## 主结果

主指标是 `cycle_ns_per_page`，越低越好。

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | mm-unstable vs v6.12 | v6.12 vs v6.19 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 快约 6.6% | 仍慢约 47.9% | v6.12 快约 36.8% |
| 2 | 369.2 | 581.9 | 503.3 | 快约 13.5% | 仍慢约 36.3% | v6.12 快约 36.5% |
| 4 | 355.7 | 587.2 | 524.2 | 快约 10.7% | 仍慢约 47.4% | v6.12 快约 39.4% |
| 8 | 369.7 | 583.6 | 534.2 | 快约 8.5% | 仍慢约 44.5% | v6.12 快约 36.7% |
| 16 | 374.8 | 607.1 | 547.8 | 快约 9.8% | 仍慢约 46.2% | v6.12 快约 38.3% |

## 可靠性备注

- `1/2/4/8 CPU` 三个版本均完成 9/9。
- `16 CPU` 中 `v6.12.77` 有 1 次 QEMU failure，因此这一行只能作为补充趋势。
- `cycle_ns_per_page` 在 `1/2/4 CPU` 上对 `mm-unstable` 和 `v6.19.9`
  都达到框架的 reliable/robust reliable。
- `8 CPU` 的 `mm-unstable` `cycle_ns_per_page` 是 robust-only。

## 结论

这轮 lab sanity 支持一个比较清楚的说法：

```text
Pedro 的 small-folio mprotect optimization 对这个 synthetic shared-dirty
PTE toggle signal 是有帮助的；在 lab 上，mm-unstable 相比 v6.19.9 快约
6.6% 到 13.5%。但它没有把结果拉回 v6.12.77 水平，剩余差距仍约
36% 到 48%。
```

所以给上游回复时不应说“已经修复”，也不应说“完全无效”。更准确的是：

```text
I tested current mm-unstable with Pedro's optimization. It reduces the
synthetic shared-dirty signal in my lab matrix, but does not remove the
gap to v6.12 in this workload.
```
