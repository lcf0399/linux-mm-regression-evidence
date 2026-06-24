# Linux MM Regression Evidence

This repository contains curated evidence bundles for Linux MM performance
regression candidates. It is a long-lived evidence index rather than a
month-specific archive: each workload directory records the current public
scope, method, key results, caveats, and links to reproducer or raw-summary
material.

This is not a broad benchmark suite. Each entry is scoped to one workload and
one source path hypothesis. QEMU/lab results are kept when they are useful for
screening, coverage, or attribution, but upstream-facing timing claims should
prefer bare-metal confirmation.

## Workload Index

- `mprotect-shared-dirty-toggle/`: repeated `mprotect()` permission toggling
  over a shared dirty 4 KiB PTE mapping. The strongest current evidence is
  bare-metal: the slowdown appears in the `v6.16 -> v6.17` release window, and
  a v6.17 single-PTE source probe brings the metric back to the v6.16 fast
  range. Current scope: a source-calibrated synthetic shared-dirty PTE
  workload, not a generic `mprotect()` regression claim.

- `madvise-pageout-thp-noswap-refault/`: `madvise(MADV_PAGEOUT)` on an
  anonymous THP/no-swap reclaim-failure path. The directory name preserves the
  wording from the original report; the current scope does not claim that the
  pages were actually paged out and faulted back in.

- `mincore-present-pte-scan/`: `mincore()` present-PTE scan candidate analysis.
  Bare-metal A/B did not reproduce the QEMU-observed timing signal. Current
  scope: GCC-built/QEMU-observed compiler/codegen sensitivity, not a generic
  `mincore()` regression report.

- `mempolicy-migrate-pages-syscall/`: `migrate_pages()` syscall route candidate
  analysis on a NUMA2 setup. The available evidence is source-calibrated and
  covers both the mempolicy syscall frontend and migration core. The current
  bare-metal node has only one NUMA node, so it cannot validate this workload.

- `mseal-already-sealed-noop/`: parked `mseal()` already-sealed no-op RFC notes.
  This is an archive entry, not a formal evidence entry.

- `analysis/`: cross-workload technical notes, patch analysis, historical
  summaries, and current narrowing notes. Workload directories remain the
  source of truth for citable evidence.

Mail drafts and upstream-reply notes are kept locally under ignored `email/`
directories. They are not part of the public evidence bundle unless explicitly
promoted.

## Evidence Policy

The public tree keeps compact, reviewable material:

- workload README files and current status summaries
- standalone reproducers and helper scripts where useful
- focused CSV/JSON summaries, run environment records, execution order files,
  and completion sentinels
- attribution notes and small source probes that explain a result

The public tree generally excludes bulky runner workspaces, failed scratch logs,
temporary build outputs, and private mail-drafting history. Older screenings and
invalid runs may be summarized in `analysis/`, but they should not replace the
per-workload evidence directories.

## Method Summary

- Workloads are source-calibrated against concrete Linux `mm/*.c` paths.
- Coverage and performance are kept separate. Coverage proves direct function
  hits; clean performance timing should run without coverage instrumentation.
- Timing metrics are lower-is-better unless a workload README says otherwise.
- Formal runs should preserve environment and execution-order metadata.
- QEMU/lab timing is candidate-screening evidence unless the claim is explicitly
  scoped to that virtualized environment. Bare-metal timing is preferred for
  upstream performance-regression claims.
- Commit attribution is stated only when an exact revert, bisect, or targeted
  source probe justifies it. Otherwise the result is described as release-window
  narrowing or candidate attribution.

## Current Public Scope

The clearest current upstream-facing candidate is
`mprotect-shared-dirty-toggle/`, because it now has bare-metal release-window
narrowing and a focused v6.17 source probe. The other directories are preserved
because they explain earlier reports, negative follow-ups, or still-useful
candidate evidence.

The repository intentionally keeps negative or weakened results. A workload
that does not reproduce on bare metal, depends on QEMU/codegen layout, or lacks
the required NUMA/swap state is still useful evidence, but it must be labeled
with that limitation.
