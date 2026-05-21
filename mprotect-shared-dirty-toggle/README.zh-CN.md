# mprotect shared-dirty toggle 证据

这个目录支撑以下报告：

```text
[REGRESSION] mm/mprotect: shared dirty PTE toggle path is ~40% slower on v6.19 than v6.12
```

## 结论范围

这是一个用户态可见的 `mprotect()` workload：

- shared dirty 64 MiB mapping
- 反复做 full-range protection toggle
- 关注 shared-dirty PTE path

它不声称存在泛化的 `mprotect()` regression，也不声称 `anon_full_toggle` 或 THP mprotect regression。

## 关键结果

Formal lab timing 显示 `v6.19.9` 慢于 `v6.12.77`。

`cycle_ns_per_page`：

| CPU | v6.12.77 | v6.19.9 | delta | reliability |
| --- | ---: | ---: | ---: | --- |
| 1 | 346.8 | 578.1 | -40.0% | clean reliable |
| 2 | 394.7 | 641.7 | -38.5% | robust-only |
| 4 | 381.1 | 624.8 | -39.0% | partial same direction |

单独做过的 release-level sanity check 显示 `v6.18.19` 已经进入慢区间，但这些 raw run
没有放入当前精简公开证据包。

## 后续结果

David Hildenbrand 指向了 Pedro Falcato 最近的 small-folio mprotect optimization。
针对 `akpm/mm mm-unstable 444fc9435e57` 的 lab sanity matrix 显示，这个 workload
里出现了部分缓解，但没有回到 `v6.12.77` 的 timing：

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | gap closed |
|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 6.6% faster | 17.9% |
| 2 | 369.2 | 581.9 | 503.3 | 13.5% faster | 36.9% |
| 4 | 355.7 | 587.2 | 524.2 | 10.7% faster | 27.2% |
| 8 | 369.7 | 583.6 | 534.2 | 8.5% faster | 23.1% |
| 16 | 374.8 | 607.1 | 547.8 | 9.8% faster | 25.5% |

该 sanity matrix 中 16 CPU 行有一次 `v6.12.77` QEMU failure，因此它只是辅助趋势证据。

单独的 state-shape audit 检查了这个 mprotect 对比是否存在类似 `MADV_PAGEOUT` 的 caveat，
即不同内核是否在 materially different page/VMA state 上运行。state audit 发现成功的
`v6.12.77`、`v6.19.9` 和 `mm-unstable` run 都使用同一种 4 KiB shared-dirty PTE
mapping 形态：protect 前后都是 16384 个 present pages、无 THP backing、最终一个 VMA、
没有 semantic mismatch。这支持把剩余 timing gap 视为 same-state implementation-path
cost，而不是 workload-state mismatch comparison。

## 目录

- `workload/`：框架使用的 generated workload source。
- `experiments/`：formal experiment profile。
- `formal-lab/perf_{1,2,4}cpu/`：coverage disabled 的 performance run。
- `formal-lab/coverage_1cpu/`：与 clean timing 分开收集的 direct-hit coverage 证据。
- `mm-unstable-lab-sanity/`：small-folio optimization 讨论使用的 lab follow-up matrix。
- `state-audit-lab/`：支持 same-state comparison assumption 的 lab state-shape audit。
- `mm-unstable-local-sanity/`：仅作本地 follow-up context。

follow-up 目录中的精简 `results/` 子目录保存每个 CPU/memory 行可审计的
`summary`、`raw`、`pipeline_run_env.json` 和 `execution_order.json`。完整 runner
目录和冗长 launch logs 默认不放入公开证据包，除非后续 debug 需要。
