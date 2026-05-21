# mprotect Shared-dirty State Audit

This directory records the lab state-shape audit for
`shared_dirty_full_toggle_64m`. It checks whether different kernels operate on
materially different mapping state.

This is not performance evidence. It records semantic success, VMA shape,
smaps fields, and pagemap fields across:

```text
v6.12.77
v6.19.9
akpm/mm mm-unstable 444fc9435e57
```

Matrix: `1/2/4 CPU` at 14336 MiB, `8 CPU` at 16384 MiB, and `16 CPU` at
32768 MiB.

The compact conclusion is in the parent workload README. The detailed state
summary is in `summary-20260520.md` and `summary-20260520.zh-CN.md`.

Raw runner directories and verbose launch logs are excluded from the compact
public bundle by `.gitignore`. The `results/` directory keeps compact citable
state-audit artifacts for each CPU/memory row.
