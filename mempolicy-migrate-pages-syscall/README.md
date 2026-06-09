# mempolicy migrate_pages() Syscall Route Candidate

This directory is a maintainer-facing compact evidence bundle for a
source-calibrated synthetic NUMA migration workload.

Current scope:

- Workload type: source-calibrated synthetic userspace micro-workload.
- Entry path: `migrate_pages()` syscall in `mm/mempolicy.c`.
- Timed work: mempolicy syscall frontend plus migration core in `mm/migrate.c`.
- Scenario: two-node NUMA guest, 16 MiB anonymous mapping initially placed on
  node 0, then migrated to node 1 with `migrate_pages()`.
- Main metric: `move_ns_per_page`, lower is better.  It is the elapsed time
  around the `migrate_pages()` syscall divided by 4096 pages; the later
  `move_pages(..., nodes=NULL, status=...)` query is only a placement/state
  check and is not included in this timing metric.

This is not a production application regression report and not a generic
`mempolicy` regression claim.  It is a strong candidate that still needs
additional attribution or commit-level narrowing before it should be treated as
a final regression report.

## Current Finding

On the lab x86/QEMU direct-boot setup, the `migrate_pages()` syscall route is
substantially slower on `v7.0.9-preempt` than on `v6.12.77-preempt`,
`v6.18.19-preempt`, and `v6.19.9-preempt` in the primary 1/2/4 CPU clean
timing matrix.

Primary 1/2/4 CPU matrix, median `move_ns_per_page`:

```text
CPU   v7.0.9-preempt   v6.12.77-preempt   v6.18.19-preempt   v6.19.9-preempt
  1        17439              11914              11719              12110
  2        18137              12403              12110              12793
  4        17997              12804              12305              12696
```

The state-shape checks were clean in that matrix:

```text
expected_match_ratio=100
unexpected_results=0
queried_pages_avg=4096
post_target_pages_avg=4096
move_failed_pages_avg=0
```

Extended 8/16 CPU runs support the same direction versus v6.18/v6.19, but they
are supporting evidence rather than the primary formal matrix because guest
memory changes with CPU count:

```text
CPU/mem        v7.0.9 mean   v6.18.19 mean   v6.19.9 mean
8 CPU/16 GiB       19267          12591.6         13580.6
16 CPU/32 GiB      19299.2        13016.6         13802.4
```

## Attribution State

Direct function-entry coverage confirms that the workload enters both:

- the `mm/mempolicy.c` syscall frontend and queueing path; and
- the `mm/migrate.c` migration core, including `migrate_pages_batch()`,
  `migrate_folio_move()`, `move_to_new_folio()`, and `remove_migration_pte()`.

The ftrace attribution runs are mixed.  The first function-profile run pointed
the extra profiled cost at the migration core, especially the
`migrate_pages_batch()` / `move_to_new_folio()` call range.  A later reduced
function set did not reproduce the large move/copy increase; it showed smaller
move/copy changes and a modest queueing-front-end increase.  These runs remain
cost-center/composition hints, not line-level culprit evidence.

One obvious v7 difference, the deferred-split bookkeeping in
`migrate_folio_move()`, was tested as an attribution-only A/B.  Removing that
logic from v7 changed `move_ns_per_page` by only about 1-2%, below the 5%
actionable threshold, so this is currently a negative attribution result.

A follow-up fine-grained ftrace run confirmed that the copy path is a large
part of the profiled migration-core cost, but that run is instrumentation
sensitive and did not preserve the clean-timing direction.  I therefore use it
only as composition evidence.  A v7-only clean A/B that replaced
`folio_mc_copy()` with `folio_copy()` made `move_ns_per_page` about 7.5% slower,
so the simple "machine-check-safe copy is the slowdown" hypothesis is also a
negative attribution result, not a proposed fix.

The first commit-inventory candidate, `832d95b5314e` (`migrate: replace RMP_
flags with TTU_ flags`), was tested with a v7 revert-style attribution A/B.
The revert tree changed `move_ns_per_page` by less than 1% (about -0.46% mean /
-0.82% median), so that flag-conversion lead is also negative for this
anonymous base-page workload.

## Contents

- `reproducer/`: standalone C reproducer for the workload shape and a lab-host
  NUMA2 smoke result.
- `lab-validation/`: compact clean timing summary CSVs for 1/2/4 CPU and
  extended 8/16 CPU runs.
- `attribution/`: coverage summary, ftrace profiles, deferred-split,
  folio-copy, RMP/TTU A/B summaries, reduced-function ftrace, and the current
  narrowing notes.
- `patches/`: attribution-only patches used to test the deferred-split,
  folio-copy, and RMP/TTU hypotheses.

## Caveats

- This is a synthetic/source-calibrated workload, not a production NUMA
  application report.
- The current best description is `mempolicy syscall frontend plus migration
  core`, not `mempolicy-only`.
- ftrace is attribution evidence, not clean timing evidence.
- Host-side perf-style attribution is currently blocked on the lab host by
  `perf_event_paranoid=4` for this user.
- A first commit-inventory/revert A/B has been completed for `832d95b5314e`,
  but no full commit-level bisect or final culprit has been completed.
