# standalone reproducer lab 验证

这个目录总结 `mprotect_shared_dirty_reproducer.c` standalone workload 的一次
lab 验证运行。

这次运行的目的比前面的 formal framework runs 更窄：确认给维护者检查用的更小
reproducer 在 lab QEMU 环境里仍然保持同样的 timing 方向。

## 运行设置

- host label: `lcf`
- QEMU: direct boot
- kernels: `v6.12.77`、`v6.19.9`、`akpm/mm mm-unstable 444fc9435e57`
- requested guest CPUs: `QEMU_SMP=1/2/4`
- guest memory: `14336 MiB`
- repetitions: `5`
- order: interleaved
- coverage: disabled
- extra guest cmdline: `tsc=unstable clocksource=refined-jiffies`
- workload external rounds: `5`

事后检查 kernel config 发现这几棵 kernel build 是 non-SMP：
`# CONFIG_SMP is not set` 且 `CONFIG_NR_CPUS=1`。因此下面这张表不是多 CPU
scaling 证据，只能视为在不同 requested QEMU SMP 值下的 single-CPU reproducer
screening。

主要指标是 `iteration_ns_per_page`，越低越好。它表示一次完整
protect/restore/post-touch iteration 的每个 base page wall-clock 纳秒数。

## iteration 结果

| Requested QEMU_SMP | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | v6.12 -> v6.19 gap closed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 301.6 | 563.2 | 477.6 | 15.2% faster | 32.7% |
| 2 | 306.2 | 542.4 | 488.4 | 10.0% faster | 22.9% |
| 4 | 305.6 | 552.4 | 479.2 | 13.3% faster | 29.7% |

standalone reproducer 保持了和前面 framework run 一致的大方向：`v6.19.9`
慢于 `v6.12.77`，当前 `mm-unstable` 有部分改善，但没有回到 `v6.12.77`
水平。

分阶段字段显示，主要 gap 出现在 `mprotect(PROT_READ)` 和
`mprotect(PROT_READ | PROT_WRITE)` 两个阶段。完整 per-metric 表见
`lab-summary-20260525.csv`。

## caveat

这是针对更小 reproducer 的 5 次重复 single-CPU screening run，不替代前面的 formal evidence。
QEMU guest run 报告 `expected_match_ratio=100`、`unexpected_results=0`，但这个
minimal guest 环境没有提供和单独 state audit 一样的 smaps state-shape 可见性。
state-shape 结论仍以 `../state-audit-lab/` 为准。

## 文件

- `lab-iteration-comparison-20260525.csv`：精简 CPU 对比表。
- `lab-summary-20260525.csv`：去重后的 per-version/per-metric summary。
- `lab-summary-20260525.json`：同一份数据，包含去重元数据。
- `profile/`：runner 使用的 generated workload profile。
- `../reproducer/`：这轮验证使用的 canonical standalone source。
- `run-env/`：1/2/4 CPU 行的运行环境、执行顺序和完成哨兵。
