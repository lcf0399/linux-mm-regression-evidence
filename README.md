# Linux MM Regression Evidence - May 2026

This repository contains a curated evidence bundle for two Linux MM performance
regression reports. It documents the formal test method, environment, raw
summaries, and current attribution state so that reviewers can audit the
reported results directly.

The two reports are scoped by workload:

- `madvise-pageout-thp-noswap-refault/`: `madvise(MADV_PAGEOUT)` on an anonymous THP/no-swap reclaim-failure path. The directory name preserves the wording from the original report; the current scope does not claim that the pages were actually paged out and faulted back in.
- `mprotect-shared-dirty-toggle/`: repeated `mprotect()` toggling over a shared dirty PTE mapping.
- `analysis/`: curated technical notes, patch analysis, and short historical summaries. Private upstream-submission workflow notes are kept outside this public evidence bundle; the formal evidence remains in the workload directories.

This is not a broad benchmark suite. Each claim is limited to the workload and environment described below.

## Experiment Method

Both workloads were run through the same project experiment framework:

- Source-calibrated workloads target concrete Linux `mm/*.c` paths and export per-page timing metrics.
- Coverage and performance evidence were collected separately. Coverage runs only show direct function-entry hits; clean performance runs have coverage disabled.
- Formal performance runs use interleaved version order to reduce host-drift bias.
- The primary lab formal matrix uses `QEMU_SMP=1/2/4` with the same guest memory, kernel config family, and command-line policy across CPU counts.
- Some follow-up checks include an extended lab matrix up to `QEMU_SMP=8/16` with larger guest memory, when explicitly documented in the workload directory. These extended rows are useful for scalability/context, but they are reported separately from the strict `1/2/4` same-memory formal matrix.
- Separate release-level sanity checks were used to choose a broad reporting range, but they are not part of this compact public evidence bundle. No commit-level bisection has been completed yet.

Primary timing metrics are lower-is-better:

- `cycle_ns_per_page`
- `advise_ns_per_page` for the `MADV_PAGEOUT` syscall/reclaim-side segment

Here, `cycle` means one complete workload iteration, not CPU cycles.
`cycle_ns_per_page` is wall-clock nanoseconds per page per workload iteration.
The name is retained for compatibility with the experiment data schema, but it
should be interpreted as a wall-clock duration, not a hardware cycle count.

The exact per-run metadata for the formal evidence is preserved in `pipeline_run_env.json`, `execution_order.json`, `*.summary.csv/json`, and `*.raw.csv/json`.

## Environment Summary

The formal evidence uses the lab server as the primary timing environment:

- Host label in metadata: `lcf`
- Host kernel: `Linux 6.14.0-37-generic x86_64`
- Host CPU count: 128
- Container/cgroup CPU set: `0,2,4,6,8,10,12,14`
- Container/cgroup memory limit: `16106127360` bytes
- QEMU: `qemu-system-x86_64 8.2.2`
- Primary formal guest memory: `QEMU_MEM_MB=14336`
- Primary formal guest CPUs: `QEMU_SMP=1/2/4`
- Extended follow-up runs, when present: `QEMU_SMP=8` with larger memory such as `QEMU_MEM_MB=16384`, and `QEMU_SMP=16` with larger memory such as `QEMU_MEM_MB=32768`
- Timing order: interleaved version order
- Formal repetitions: 9
- Performance timing: coverage disabled

The exact per-run environment remains in `pipeline_run_env.json`; this section is a compact summary.

## Workload Status

The workload directories are the source of truth for per-workload tables,
profiles, and follow-up summaries. This section only records the current public
scope.

- `madvise-pageout-thp-noswap-refault/`
  - Original lab timing showed `v6.19.9` slower than `v6.12.77` on the
    `1/2/4 CPU` matrix.
  - Follow-up ftrace/smaps checks now cover `1/2/4 CPU` at 14336 MiB, `8 CPU`
    at 16384 MiB, and `16 CPU` at 32768 MiB.
  - The follow-up found a page-state caveat: default/hugepage runs were not a
    same-actual-THP-state comparison between `v6.12.77` and `v6.19.9`.
  - Current scope: not a proven real pageout/refault regression and not a
    same-state THP regression; best treated as a narrower no-swap
    `MADV_PAGEOUT` anon/THP reclaim split/failure-path observation.

- `mprotect-shared-dirty-toggle/`
  - Original lab timing showed `v6.19.9` slower than `v6.12.77` on the
    shared-dirty PTE toggle workload.
  - `akpm/mm mm-unstable 444fc9435e57` partially mitigates the signal in the
    lab `1/2/4/8/16 CPU` matrix, but does not restore `v6.12.77`-level timing.
  - State-shape audit found the successful `v6.12.77`, `v6.19.9`, and
    `mm-unstable` runs use the same 4 KiB shared-dirty PTE mapping shape.
  - Current scope: a synthetic/source-calibrated shared-dirty PTE `mprotect()`
    workload, not a generic `mprotect()` regression claim.

No culprit commit has been bisected for either workload. Separate release-level
sanity checks showed `v6.18.19` already in the slow range for both reports.

## Data Selection Policy

The formal workload directories include the latest citable evidence bundle for the two reports:

- latest lab formal refresh results for the main performance claims
- separate coverage evidence where useful, kept distinct from clean performance timing

Older screenings, release-level sanity runs, invalid runs, failed runs,
instrumentation-contaminated runs, and exploratory intermediate outputs are
kept out of the minimal public evidence bundle by default. The `analysis/`
directory contains supplementary notes and should not replace the workload
directories.

## Main Caveats

The reports are not claiming generic `madvise()` or generic `mprotect()` regressions.

The `MADV_PAGEOUT` claim is scoped to an anonymous THP/no-swap `MADV_PAGEOUT` reclaim-failure + write-touch iteration workflow; a real pageout/refault has not been established. The new local + lab attribution shows this is not a same-actual-THP-state comparison.

The `mprotect()` claim is scoped to the shared dirty full-range
protection-toggle workload; the cleanest original formal result is the 1CPU lab
run, while 2CPU and 4CPU are same-direction supporting evidence with
reliability caveats. The later 8/16 CPU rows are extended follow-up context, not
part of the strict same-memory primary formal matrix.
