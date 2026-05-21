# mprotect mm-unstable lab sanity

这个目录记录针对 Pedro small-folio `mprotect()` optimization 的 lab follow-up。
父级 workload README 已经包含精简结果表和结论。

## 矩阵

- kernels：`v6.12.77`、`v6.19.9`、`akpm/mm mm-unstable`
- `mm-unstable`：`7.1.0-rc3-mm-unstable-444fc9435e57`
- workload：`shared_dirty_full_toggle_64m`
- CPU/memory：14336 MiB 下的 `1/2/4 CPU`、16384 MiB 下的 `8 CPU`、32768 MiB 下的 `16 CPU`
- repetitions：9
- order：interleaved
- coverage：disabled

可靠性说明：`1/2/4/8 CPU` 对三个版本都是 9/9 完成。`16 CPU` 行有一次
`v6.12.77` QEMU failure，因此只作为辅助趋势证据。

raw runner 目录由 `.gitignore` 排除在精简公开证据包之外。`results/` 目录保存
每个 CPU/memory 行的精简可引用材料：`summary`、`raw`、`pipeline_run_env.json`
和 `execution_order.json`。
