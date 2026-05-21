# Supplementary Technical Analysis

This directory contains curated technical notes that supplement the workload
evidence. It does not contain private mailing workflow notes or raw experiment
history.

Use the workload directories as the source of truth for current claims:

```text
madvise-pageout-thp-noswap-refault/
mprotect-shared-dirty-toggle/
```

## Files

- `confirmed_regressions_refresh_2026-05-13.zh-CN.md`
  - Short historical summary of the original lab formal timing refresh.
  - Current caveats are in the workload README files.

- `four_case_root_cause_line_level_attribution.zh-CN.md`
  - Short historical index for the earlier four-case source-attribution note.
  - The long internal note is not part of this compact public evidence bundle.

- `mprotect_mm_unstable_patch_analysis_2026-05-19.zh-CN.md`
  - Technical analysis of Pedro's small-folio `mprotect()` optimization and
    how it relates to the shared-dirty `nr_ptes == 1` hypothesis.

- `run_lab_followup_20260520_madvise_mprotect.sh`
  - Lab orchestration helper used for the 2026-05-20 follow-up runs.

## Boundaries

- The `madvise` current scope is not a proven real pageout/refault regression
  and not a same-state THP regression.
- The `mprotect` current scope is a synthetic/source-calibrated shared-dirty
  PTE workload, not a generic `mprotect()` regression claim.
- Private upstream-submission process notes are kept outside this public
  evidence repository.
