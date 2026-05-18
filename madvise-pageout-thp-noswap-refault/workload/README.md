# MADV_PAGEOUT Refault Reproducer

This directory contains a standalone userspace workload for the
`MADV_PAGEOUT + anonymous THP + no-swap + refault/write-touch` workflow used
by the `mm_regression_gen` `madvise_pageout_formal_refresh` profile.

It is meant for upstream reporting, bisection, and boundary checks. It is not
a replacement for the full `mm_regression_gen` evidence set.

## Files

- `madvise_pageout_refault_reproducer.c`
- `run_madvise_pageout_reproducer.sh`

## Default Workload

The defaults mirror the current reportable experiment:

- mapping size: `16 MiB`
- THP mode: default policy, no explicit `MADV_NOHUGEPAGE`
- advice: `MADV_PAGEOUT`
- refault: one write-touch per page
- external rounds: `5`
- internal rounds: at least `4`, at most `256`
- minimum measured time per external round: `1200 ms`
- warmup cycles before each external round: `2`
- wrapper repetitions: `9`

## Quick Smoke Test

This only checks that the program builds and runs. It is not performance
evidence.

```sh
cd /path/to/linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/workload
REPETITIONS=1 \
  ./run_madvise_pageout_reproducer.sh \
  --mapping-kb 4096 --external-rounds 1 --rounds 1 --max-rounds 1 --min-ms 0 --warmup-rounds 0
```

## Report-Style Run

Run this inside the target kernel guest:

```sh
cd /path/to/linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/workload
OUT_DIR=/tmp/madvise-pageout-$(uname -r) \
REPETITIONS=9 \
  ./run_madvise_pageout_reproducer.sh
```

Important fields:

- `advise_ns_per_page`
- `cycle_ns_per_page`
- `advise_ns_avg`
- `cycle_ns_avg`
- `expected_match_ratio`
- `unexpected_results`
- `errno_enomem`
- `errno_einval`

`cycle_ns_per_page` is `(advise_ns + post_touch_ns) / post_touch_pages`.

## THP Boundary Checks

Default THP policy:

```sh
./madvise_pageout_refault_reproducer
```

Disable THP for the mapping:

```sh
./madvise_pageout_refault_reproducer --thp nohugepage
```

Request THP for the mapping:

```sh
./madvise_pageout_refault_reproducer --thp hugepage
```

`--dump-smaps` prints selected `/proc/self/smaps` fields after prefault. Use it
only for path checks, not for timing evidence.

## Current Regression Context

The current lab evidence compares `v6.12.77` and `v6.19.9` with similar kernel
configuration. On the lab QEMU guest, `v6.12.77` is about `39%` to `42%` faster
than `v6.19.9` on `cycle_ns_per_page` across `1/2/4` vCPUs.

This should be reported as a path-specific regression in the
`THP default + MADV_PAGEOUT + no-swap/refault` workflow, not as a generic
`madvise(2)` slowdown.
