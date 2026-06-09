# Narrowing Notes

This note summarizes the current source-level narrowing state for the
`migrate_pages()` syscall route candidate.  It is not additional timing
evidence.

## What The Evidence Supports

- The main signal comes from same-PREEMPT lab clean timing: `v7.0.9-preempt` is
  substantially slower than `v6.12.77-preempt`, `v6.18.19-preempt`, and
  `v6.19.9-preempt` in the primary 1/2/4 CPU matrix.
- The state-shape checks are clean: all 4096 pages end on the target node,
  `move_failed_pages_avg=0`, and `expected_match_ratio=100`.
- Direct function-entry coverage confirms entry into both the `mm/mempolicy.c`
  syscall frontend and the `mm/migrate.c` migration core.
- Ftrace is attribution evidence, not clean timing.  The first ftrace run
  pointed extra profiled cost at the `migrate_pages_batch()` /
  `move_to_new_folio()` call range.  A later reduced-function ftrace run did
  not reproduce that large move/copy increase; it showed about +2% in
  move/copy and about +7% in the queueing frontend.

## Weakened Or Negative Leads

- The visible `mm/mempolicy.c` v6.19 -> v7.0 differences around this route are
  mostly policy lifetime/RCU freeing, nodemask helper rewrites, and weighted
  interleave allocation changes.  The reduced ftrace queueing increase is small
  relative to the copy/move body and still does not make the frontend the
  leading explanation.
- The most obvious `mm/migrate.c` v7 difference was deferred-split bookkeeping
  in `migrate_folio_move()`.  An attribution-only v7 A/B that removed that logic
  changed `move_ns_per_page` by only about 1-2%, below the 5% actionable
  threshold.  This is a negative attribution result for the main signal.
- The body of `move_to_new_folio()` is unchanged in the local v6.19 -> v7.0
  snapshot diff.  The ftrace result should therefore be treated as a
  cost-center/call-range hint, not as a line-level culprit.
- The `remove_migration_ptes()` flag conversion from `RMP_*` to `TTU_*` does not
  currently look like the main explanation for this anonymous base-page
  workload, which reaches `remove_migration_ptes(src, dst, 0)` in the base-page
  migration path.  A v7 revert-style A/B for `832d95b5314e` changed
  `move_ns_per_page` by less than 1% (about -0.46% mean / -0.82% median), so it
  is now a negative attribution lead.
- A finer ftrace profile shows that the copy range is large, especially
  `folio_mc_copy()` / `copy_mc_to_kernel()`, but the ftrace direction did not
  match clean timing and is only composition evidence.  A v7-only clean A/B that
  replaced `folio_mc_copy()` with `folio_copy()` made `move_ns_per_page` about
  7.5% slower, so this simple copy-path hypothesis is a negative attribution
  result, not a fix.

## Remaining Gap

The current claim should be framed as:

```text
mempolicy migrate_pages() syscall route plus mm/migrate.c migration core
```

not as a `mempolicy.c`-only regression and not as a line-level culprit report.
The remaining useful work is lower-overhead perf-style attribution or deeper
commit-level narrowing inside migration core and nearby rmap/folio migration
helpers, beyond the negative deferred-split, folio-copy, and RMP/TTU leads.
The current lab host blocks perf for this user with `perf_event_paranoid=4`, so
the next practical local step would be source-reasoned commit/A-B narrowing.
A second source scan did not find a stronger single-point candidate tightly
matching this anonymous base-page migration route; without perf access or
maintainer guidance, additional low-related A/B runs are not recommended.
