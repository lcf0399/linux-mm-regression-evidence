# mincore Present-PTE Scan Candidate

This directory is a maintainer-facing evidence sketch for a source-calibrated
`mincore()` workload that stresses the resident anonymous base-page PTE path in
`mm/mincore.c`.

Current scope:

- Workload type: source-calibrated synthetic userspace micro-workload.
- Hot path: `mincore()` -> `walk_page_range()` -> `mincore_pte_range()`.
- Primary scenario: `MADV_NOHUGEPAGE` anonymous 64 MiB resident mapping,
  reported as `no_thp_pte_scan_64m`.
- Main metric: `mincore_ns_per_1k_pages`, lower is better.

This is not a claim about a production application and not a generic
`mincore()` regression report.  It is a candidate fix discussion for a narrow
present-PTE hot path.

## Current Finding

Release-level and A/B testing narrowed the main step to the v6.15 -> v6.16
window.  The strongest suspect is:

```text
4df65651f7075 mm: mincore: use pte_batch_hint() to batch process large folios
```

That change improved large-folio/mTHP mincore batching, but local lab testing
shows a large cost in the base-page resident-PTE scan case.  A local
present-first candidate keeps `pte_batch_hint()` for `batch > 1`, but checks
`pte_present()` before the none/marker path.

As of the 2026-05-29 UTC recheck, torvalds/master still has
`mincore_pte_range()` checking `pte_none(pte) || pte_is_marker(pte)` before
`pte_present(pte)`.  The local `linux-mm-unstable` checkout used for the test
patch is `444fc9435e571`.

## Contents

- `reproducer/`: standalone C reproducer distilled from the workload source.
- `patches/mincore-present-first-fastpath-rfc.patch`: local test patch shape,
  not ready for direct upstream submission.
- `lab-validation/`: compact CSV summaries, the primary 1/2/4 CPU validation
  note, high-CPU v6.16 introduction-window A/B rows, high-CPU present-first
  A/B rows, and separate matched-PREEMPT release-level 8CPU/16CPU bridge rows.

## Caveats

- The present-first patch has only been validated on the x86/QEMU lab setup,
  up to the 16CPU/32GiB no-THP present-PTE scan follow-up.
- It still needs arm64 or mTHP/large-folio preservation validation before it can
  be proposed as an upstream fix.
- The patch file here intentionally says "not for submission"; it needs a real
  commit message, Signed-off-by, and architecture review before sending.
