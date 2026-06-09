# Linux MM Regression Evidence - May 2026

This repository contains curated evidence bundles for Linux MM performance
regression reports and later candidate analyses. It documents the formal test
method, environment, summary data, and current attribution state so that
reviewers can audit the reported results directly.

The two reports are scoped by workload:

- `madvise-pageout-thp-noswap-refault/`: `madvise(MADV_PAGEOUT)` on an anonymous THP/no-swap reclaim-failure path. The directory name preserves the wording from the original report; the current scope does not claim that the pages were actually paged out and faulted back in.
- `mprotect-shared-dirty-toggle/`: repeated `mprotect()` toggling over a shared dirty PTE mapping.
- `mincore-present-pte-scan/`: later `mincore()` present-PTE scan candidate
  analysis. After compiler cross-checking, it is best described as a
  GCC-13.3/QEMU-observed compiler/codegen-sensitive signal, not a generic
  `mincore()` regression report or an upstream-ready fix.
- `mempolicy-migrate-pages-syscall/`: later `migrate_pages()` syscall route
  candidate analysis. It is a source-calibrated NUMA2 synthetic signal covering
  the mempolicy syscall frontend plus migration core, not a `mempolicy-only`
  regression report.
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
  - `reproducer/` contains a maintainer-facing standalone C reproducer distilled
    from the original generated shared-dirty full-range toggle workload. It does
    not require the full experiment framework.
  - `reproducer-validation/` contains lab screening validation for that
    standalone reproducer. It keeps the same broad direction across
    `1/2/4/8/16 CPU`, but it is a 5-repeat reproducer/timing screening check,
    not a replacement for the earlier formal evidence.
  - Current scope: a synthetic/source-calibrated shared-dirty PTE `mprotect()`
    workload, not a generic `mprotect()` regression claim.

- `mincore-present-pte-scan/`
  - Later candidate analysis, not part of the original two reports.
  - The source-calibrated `no_thp_pte_scan_64m` workload targets the resident
    anonymous base-page path in `mincore_pte_range()`.
  - Release-level and targeted A/B testing narrow the main step to
    `v6.15 -> v6.16`, with
    `4df65651f7075 ("mm: mincore: use pte_batch_hint() to batch process large folios")`
    as the strongest suspect.
  - GCC 13.3 generates a different `mincore_pte_range()` shape for v6.16
    original, while the local fastpath and nobatch variants match each other.
    Clang 18.1.3 generates byte-identical output for all checked variants.
  - Current scope: compiler/codegen-sensitive signal observed with GCC-built
    kernels in the x86/QEMU lab. The local present-first test patch is retained
    as historical discussion material, not as an upstream-ready fix.

- `mempolicy-migrate-pages-syscall/`
  - Later candidate analysis, not part of the original two reports.
  - The source-calibrated workload targets the userspace-visible
    `migrate_pages()` syscall route on a two-node NUMA guest.
  - Lab same-PREEMPT 1/2/4 CPU clean timing shows `v7.0.9-preempt`
    substantially slower than `v6.12.77-preempt`, `v6.18.19-preempt`, and
    `v6.19.9-preempt` on `move_ns_per_page`.
  - Extended 8/16 CPU follow-up supports the same direction versus v6.18/v6.19,
    but is reported separately because guest memory changes with CPU count.
  - Direct coverage confirms the workload reaches both `mm/mempolicy.c` and
    `mm/migrate.c`; ftrace points the extra cost at the migration core.
    Deferred-split bookkeeping and simple `folio_mc_copy()` -> `folio_copy()`
    A/B tests are both negative attribution results.
  - Current scope: strong synthetic regression candidate needing lower-overhead
    migration-core attribution or commit-level narrowing before a final report.

No culprit commit has been fully bisected for the original two reports. Separate
release-level sanity checks showed `v6.18.19` already in the slow range for both
of them. The later `mincore` candidate has targeted A/B evidence against the
suspected v6.16 change, but it is still not a full `git bisect` result.

## Data Selection Policy

The formal workload directories include the latest citable evidence bundle for
the two reports and compact maintainer-facing material for the later candidate:

- latest lab formal refresh results for the main performance claims
- separate coverage evidence where useful, kept distinct from clean performance timing
- maintainer-requested standalone reproducers, compact summaries, and necessary
  run metadata

Older screenings, release-level sanity runs, invalid runs, failed runs,
instrumentation-contaminated runs, and exploratory intermediate outputs are
kept out of the minimal public evidence bundle by default. The `analysis/`
directory contains supplementary notes and should not replace the workload
directories.

This policy does not mean all per-run data is removed. Public directories may
keep compact CSV/JSON summaries, run environment records, execution order, and
completion sentinels. Bulky raw runner workspaces, scratch logs, and temporary
exploration directories remain ignored by default unless a maintainer asks for
them.

## Main Caveats

The reports are not claiming generic `madvise()` or generic `mprotect()` regressions.

The `MADV_PAGEOUT` claim is scoped to an anonymous THP/no-swap `MADV_PAGEOUT` reclaim-failure + write-touch iteration workflow; a real pageout/refault has not been established. The new local + lab attribution shows this is not a same-actual-THP-state comparison.

The `mprotect()` claim is scoped to the shared dirty full-range
protection-toggle workload; the cleanest original formal result is the 1CPU lab
run, while 2CPU and 4CPU are same-direction supporting evidence with
reliability caveats. The later 8/16 CPU rows are extended follow-up context, not
part of the strict same-memory primary formal matrix.

The `mincore()` material is not a formal regression report. It is scoped to a
source-calibrated anonymous no-THP resident-PTE scan. The current public claim
is compiler/codegen-sensitive: GCC 13.3 shows a generated-code layout
difference in the checked x86 path, while Clang 18.1.3 does not. The timing
evidence is x86/QEMU lab only, with no physical CPU timing yet.

The `mempolicy/migrate` material is not a generic `mempolicy` regression report.
It is scoped to a controlled NUMA2 anonymous-page migration route through
`migrate_pages()`. The current evidence is strong for that route, but attribution
still stops at migration-core cost centers and negative A/B leads rather than a
commit-level culprit.
