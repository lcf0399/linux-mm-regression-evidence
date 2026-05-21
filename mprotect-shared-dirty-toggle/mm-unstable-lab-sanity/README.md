# mprotect mm-unstable Lab Sanity

This directory records the lab follow-up for Pedro's small-folio `mprotect()`
optimization in `akpm/mm mm-unstable`.

The parent workload README contains the compact result table and conclusion.

## Matrix

- kernels: `v6.12.77`, `v6.19.9`, `akpm/mm mm-unstable`
- `mm-unstable`: `7.1.0-rc3-mm-unstable-444fc9435e57`
- workload: `shared_dirty_full_toggle_64m`
- CPU/memory: `1/2/4 CPU` at 14336 MiB, `8 CPU` at 16384 MiB, `16 CPU` at 32768 MiB
- repetitions: 9
- order: interleaved
- coverage: disabled

Reliability note: `1/2/4/8 CPU` completed 9/9 runs for all three versions. The
`16 CPU` row had one `v6.12.77` QEMU failure and is supporting trend evidence.

Raw runner directories are excluded from the compact public bundle by
`.gitignore`. The `results/` directory keeps the compact citable artifacts for
each CPU/memory row: `summary`, `raw`, `pipeline_run_env.json`, and
`execution_order.json`.
