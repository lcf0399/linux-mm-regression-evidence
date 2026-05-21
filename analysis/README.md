# Supplementary Analysis and Upstream Feedback

This directory contains supplementary notes that help explain the current
state of the two reports, the maintainer feedback received so far, and the
follow-up checks performed after the initial mailing-list submission.

The files here are not the primary performance evidence. For citable timing
and coverage data, use the workload directories:

```text
madvise-pageout-thp-noswap-refault/
mprotect-shared-dirty-toggle/
```

The analysis notes are included for transparency and provenance. Some of them
refer to historical investigation state and should be read together with the
top-level README and the workload-specific README files.

## Files

- `confirmed_regressions_refresh_2026-05-13.zh-CN.md`
  - Formal-refresh summary for `mprotect/shared_dirty_full_toggle_64m` and the
    original `madvise/pageout_refault_anon_16m` report.
  - Records the lab `1/2/4 CPU` clean performance matrix and separate coverage
    evidence.

- `four_case_root_cause_line_level_attribution.zh-CN.md`
  - Historical four-case line-level attribution note.
  - Currently best treated as historical analysis/method material. The active
    upstream-facing focus is `mprotect` and `madvise`; older `damon` and
    `readahead` signals have been downgraded.

- `mprotect_mm_unstable_patch_analysis_2026-05-19.zh-CN.md`
  - Local analysis of Pedro's small-folio `mprotect()` optimization series.
  - Connects the patchset to the earlier `nr_ptes == 1` / fixed per-PTE cost
    hypothesis and the local/lab `mm-unstable` sanity results.

- `upstream_submission_feedback.zh-CN.md`
  - Notes from the first upstream submission attempt and maintainer feedback.
  - Covers SMTP/webmail issues, stale maintainer addresses, synthetic workload
    scope, and the corrected `madvise` no-swap interpretation.

## Caveats

- The `mprotect` `mm-unstable` lab sanity result shows that Pedro's optimization
  reduces the synthetic signal, but it does not bring the workload back to the
  `v6.12` level. It should not be described as fully fixed.
- The original `madvise` directory name contains `refault`, but upstream
  feedback clarified that the no-swap workload should be described as a
  `MADV_PAGEOUT` anon/THP no-swap reclaim-failure path, not a proven real
  pageout/refault workflow.
- Older four-case wording may reflect historical state. Prefer the current
  top-level README and the newer analysis notes when preparing upstream
  follow-ups.
