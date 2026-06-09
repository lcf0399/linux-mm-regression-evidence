# mempolicy migrate_pages() Attribution Summary

This directory contains compact attribution material.  It is not clean timing
evidence and should not replace the primary lab validation matrix.

## Files

- `migrate-core-coverage.summary.csv`: direct function-entry coverage summary
  for the `mm/migrate.c` view of the workload.
- `migrate-core-coverage.detail.csv`: per-function direct-hit detail for
  `mm/migrate.c`.
- `ftrace-v619-v70.profile.csv`: same-PREEMPT v6.19.9 vs v7.0.9 ftrace
  function-profile output.
- `ftrace-v619-v70.run-checks.csv`: run-level checks for the ftrace run.
- `ftrace-v619-v70.workload-rows.csv`: workload rows captured during ftrace.
- `ftrace-fine-v619-v70.profile.csv`: follow-up ftrace profile with copy,
  rmap, migration-PTE removal, and memcg helper functions included.
- `ftrace-fine-v619-v70.run-checks.csv`: compact run checks for the fine ftrace
  run.
- `ftrace-fine-v619-v70.workload-rows.csv`: workload rows captured during the
  fine ftrace run.
- `ftrace-minimal-v619-v70.profile.csv`: same-PREEMPT v6.19.9 vs v7.0.9
  reduced-function ftrace profile.
- `ftrace-minimal-v619-v70.run-checks.csv`: run-level checks for the reduced
  ftrace run.
- `ftrace-minimal-v619-v70.workload-rows.csv`: workload rows captured during
  the reduced ftrace run.
- `deferredsplit-ab.move-ns-per-page.csv`: compact clean timing A/B rows for the
  v7 deferred-split bookkeeping attribution patch.
- `foliocopy-ab.move-ns-per-page.csv`: compact clean timing A/B rows for the
  v7-only `folio_mc_copy()` -> `folio_copy()` attribution patch.
- `rmp-ttu-ab.move-ns-per-page.csv`: compact clean timing A/B rows for the
  v7 revert-style `832d95b5314e` RMP/TTU flag attribution patch.
- `commit-inventory.md`: compact source-history note for the first
  commit-level narrowing pass.
- `narrowing-notes.md`: current source-level narrowing state and negative leads.
- `narrowing-notes.zh-CN.md`: Chinese review copy of the narrowing notes.

## Interpretation

The direct coverage run confirms entry into migration core functions including:

```text
migrate_pages
migrate_pages_batch
migrate_folio_move
move_to_new_folio
remove_migration_pte
alloc_migration_target
kernel_move_pages
move_pages
```

The first ftrace function profile showed the queueing path as not slower, while
extra profiled time was concentrated in migration core:

```text
function              v6.19 total/avg us      v7.0 total/avg us
migrate_pages         431886 / 143962         642779 / 214260
migrate_pages_batch   430884 / 17235          641785 / 25671
move_to_new_folio     163126 / 13.1           398684 / 31.9
queue_pages_range      55537 / 9256            54552 / 9092
queue_folios_pte_range 52399 / 1027            51310 / 1006
```

The body of `move_to_new_folio()` is unchanged between v6.19 and v7.0, so this
is a cost-center hint, not a source-line culprit.

A later reduced-function ftrace run did not reproduce that large migration-core
increase.  In that lower-scope run, `move_to_new_folio()` and `folio_mc_copy()`
were only about 2% higher on v7, while `queue_pages_range()` and
`queue_folios_pte_range()` were about 7% higher:

```text
function              v6.19 total/avg us        v7.0 total/avg us
move_to_new_folio     2094233 / 167.8           2136649 / 171.2
folio_mc_copy         2015208 / 161.5           2056756 / 164.8
queue_pages_range       50601 / 8433              54029 / 9005
queue_folios_pte_range  48931 / 959               52398 / 1027
```

This reduced run is still ftrace attribution evidence, not clean timing, and it
does not explain the main clean-timing signal by itself.

The deferred-split bookkeeping A/B was neutral:

```text
v7.0.9-preempt            mean/median move_ns_per_page = 11067.7 / 11097
v7.0.9-nodeferredsplit    mean/median move_ns_per_page = 10959.2 / 10920
```

That is only about 1.0% mean / 1.6% median faster for the attribution tree,
below the 5% actionable threshold.

The fine ftrace follow-up shows that `folio_mc_copy()` / `copy_mc_to_kernel()`
dominates the profiled copy range, while rmap walk and migration-PTE removal are
much smaller.  The fine ftrace run is still attribution-only and its aggregate
direction flipped relative to clean timing, so it should not be used as version
performance evidence.  Its first workload round also reports one failed page in
both kernels while the placement check still shows all 4096 pages on the target
node; this is another reason to keep it out of clean timing claims.

The v7-only `folio_mc_copy()` -> `folio_copy()` A/B was also a negative lead:

```text
v7.0.9-preempt               mean/median move_ns_per_page = 10702.9 / 10654
v7.0.9-foliocopy-attribution mean/median move_ns_per_page = 11505.8 / 11541
```

The attribution tree was about 7.5% slower by mean and 8.3% slower by median,
so the simple machine-check-safe-copy replacement does not explain the main
old-faster signal and is not a proposed fix.

The first commit-inventory candidate, the RMP/TTU flag conversion in
`832d95b5314e`, was neutral in a v7 revert-style A/B:

```text
v7.0.9-preempt                    mean/median move_ns_per_page = 10782.0 / 10831
v7.0.9-revert-832d95b-attribution mean/median move_ns_per_page = 10732.4 / 10742
```

That is only about 0.46% mean / 0.82% median faster for the attribution tree,
below the 5% actionable threshold.

Host-side perf-style attribution was attempted next, but the current lab host
has `perf_event_paranoid=4` and no passwordless sudo for this user.  The current
narrowing note therefore keeps the claim as a strong route-level candidate, not
a line-level culprit report.
