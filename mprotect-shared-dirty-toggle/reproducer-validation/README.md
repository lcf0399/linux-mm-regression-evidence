# Standalone Reproducer Lab Validation

This directory summarizes a lab validation run of the standalone
`mprotect_shared_dirty_reproducer.c` workload.

The purpose of this run is narrower than the earlier formal framework runs: it
checks that the smaller maintainer-facing reproducer preserves the same timing
direction on the lab QEMU setup.

## Run Setup

- host label: `lcf`
- QEMU: direct boot
- kernels: `v6.12.77`, `v6.19.9`, `akpm/mm mm-unstable 444fc9435e57`
- requested guest CPUs: `QEMU_SMP=1/2/4`
- guest memory: `14336 MiB`
- repetitions: `5`
- order: interleaved
- coverage: disabled
- extra guest cmdline: `tsc=unstable clocksource=refined-jiffies`
- workload external rounds: `5`

Post-run config review found these kernel builds were non-SMP:
`# CONFIG_SMP is not set` and `CONFIG_NR_CPUS=1`. Therefore the table below is
not multi-CPU scaling evidence. Treat it as a single-CPU reproducer screening
run under different requested QEMU SMP values.

The primary metric is `iteration_ns_per_page`, lower is better. It is wall-clock
nanoseconds per base page for one full protect/restore/post-touch iteration.

## Iteration Result

| Requested QEMU_SMP | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | v6.12 -> v6.19 gap closed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 301.6 | 563.2 | 477.6 | 15.2% faster | 32.7% |
| 2 | 306.2 | 542.4 | 488.4 | 10.0% faster | 22.9% |
| 4 | 305.6 | 552.4 | 479.2 | 13.3% faster | 29.7% |

The standalone reproducer keeps the same broad result direction as the earlier
framework run: `v6.19.9` is slower than `v6.12.77`, while current `mm-unstable`
partially improves the result but does not return to the `v6.12.77` level.

The per-phase fields show the largest gap in the `mprotect(PROT_READ)` and
`mprotect(PROT_READ | PROT_WRITE)` phases. See `lab-summary-20260525.csv` for
the full per-metric table.

## Caveat

This validation run is a 5-repeat single-CPU screening run for a smaller
reproducer, not a replacement for the earlier formal evidence. The QEMU guest run reports
`expected_match_ratio=100` and `unexpected_results=0`, but the minimal guest
environment does not provide the same smaps state-shape visibility as the
separate state audit. The state-shape conclusion remains based on
`../state-audit-lab/`.

## Files

- `lab-iteration-comparison-20260525.csv`: compact CPU comparison table.
- `lab-summary-20260525.csv`: deduplicated per-version/per-metric summary.
- `lab-summary-20260525.json`: same data with deduplication metadata.
- `profile/`: generated workload profile used by the runner.
- `../reproducer/`: canonical standalone source used by this validation.
- `run-env/`: run environment, execution order, and completion sentinels for
  the 1/2/4 CPU rows.
