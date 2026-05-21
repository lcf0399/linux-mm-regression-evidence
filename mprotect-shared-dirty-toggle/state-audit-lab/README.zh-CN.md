# mprotect shared-dirty state audit

这个目录记录 `shared_dirty_full_toggle_64m` 的 lab state-shape audit，用来检查不同内核是否运行在 materially different mapping state 上。

这不是 performance evidence。它记录 semantic success、VMA shape、smaps 字段和 pagemap 字段，覆盖：

```text
v6.12.77
v6.19.9
akpm/mm mm-unstable 444fc9435e57
```

矩阵：14336 MiB 下的 `1/2/4 CPU`、16384 MiB 下的 `8 CPU`、32768 MiB 下的 `16 CPU`。

精简结论在父级 workload README。详细 state summary 在 `summary-20260520.md`
和 `summary-20260520.zh-CN.md`。

raw runner 目录和冗长 launch log 由 `.gitignore` 排除在精简公开证据包之外。
`results/` 目录保存每个 CPU/memory 行的精简可引用 state-audit 材料。
