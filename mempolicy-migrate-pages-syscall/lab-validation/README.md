# mempolicy migrate_pages() Lab Validation Summary

These CSV files are compact summaries copied from local lab run outputs.  They
are intended for maintainer review, not as a full raw-run archive.

Primary clean timing setup:

- QEMU direct boot on the lab host.
- NUMA topology: `QEMU_NUMA_NODES=2`.
- Primary guest memory: `QEMU_MEM_MB=14336`.
- Primary guest CPUs: `QEMU_SMP=1/2/4`.
- Repetitions: 9.
- Coverage: disabled for timing.
- Execution order: interleaved versions.
- Compared trees: same `CONFIG_PREEMPT=y`.
- Scenario: `migrate_pages_syscall`.
- Main metric: `move_ns_per_page`, lower is better.

## Files

- `primary-1-2-4.move-ns-per-page.csv`: compact primary timing rows.
- `primary-1-2-4.state-shape.csv`: compact semantic/state-shape rows.
- `extended-8-16.move-ns-per-page.csv`: compact extended follow-up timing rows.

## Key Results

Primary 1/2/4 CPU matrix, median `move_ns_per_page`:

```text
CPU   v7.0.9-preempt   v6.12.77-preempt   v6.18.19-preempt   v6.19.9-preempt
  1        17439              11914              11719              12110
  2        18137              12403              12110              12793
  4        17997              12804              12305              12696
```

Extended follow-up, mean `move_ns_per_page`:

```text
CPU/mem        v7.0.9 mean   v6.18.19 mean   v6.19.9 mean
8 CPU/16 GiB       19267          12591.6         13580.6
16 CPU/32 GiB      19299.2        13016.6         13802.4
```

The 16 CPU v6.12 row had a large outlier in the extended run and should not be
cited as a stable mean comparison.
