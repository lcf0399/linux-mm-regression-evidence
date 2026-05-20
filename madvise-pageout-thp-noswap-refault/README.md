# MADV_PAGEOUT THP/no-swap Reclaim-failure Evidence

This directory was created for the original report:

```text
[REGRESSION] mm: MADV_PAGEOUT on THP/no-swap refault workflow is ~40% slower on v6.19 than v6.12
```

The directory name and original report title preserve the initial `refault`
wording. After upstream review, the current and more accurate scope is a
`MADV_PAGEOUT` anon/THP no-swap reclaim-failure path; the later write-touch is
part of the workload iteration and should not be treated as proof of a real
pageout/refault.

## Claim scope

This is a userspace-visible `madvise(MADV_PAGEOUT)` workload:

- anonymous 16 MiB mapping
- default THP path
- no guest swap
- `MADV_PAGEOUT`, then write-touch as the second half of the iteration

It does not claim that all `MADV_PAGEOUT` workloads regress.

## Key result

Formal lab timing shows `v6.19.9` slower than `v6.12.77` across `1/2/4` vCPUs.
After upstream review, the important caveat is that these formal timing runs
did not record smaps/page-state. New local attribution runs found that actual
THP backing can differ between the two kernels in this workload shape.
Therefore, the timing table below remains the original formal timing result,
but the mechanism claim needs a lab page-state check before it should be
described as a same-state THP regression.

`cycle_ns_per_page`:

| CPU | v6.12.77 | v6.19.9 | delta |
| --- | ---: | ---: | ---: |
| 1 | 1900.3 | 3304.7 | -42.5% |
| 2 | 2107.7 | 3583.2 | -41.2% |
| 4 | 2154.2 | 3690.9 | -41.6% |

`cycle_ns_per_page` means wall-clock nanoseconds per page for one full workload
iteration. It is not a CPU-cycle counter.

`advise_ns_per_page`:

| CPU | v6.12.77 | v6.19.9 | delta |
| --- | ---: | ---: | ---: |
| 1 | 1713.2 | 2922.7 | -41.4% |
| 2 | 1924.7 | 3162.9 | -39.1% |
| 4 | 1953.1 | 3284.2 | -40.5% |

Separate release-level sanity checks showed `v6.18.19` already in the slow range, but those raw runs are kept out of this compact public evidence bundle.

## Directories

- `workload/`: standalone workload source and helper script.
- `experiments/`: formal experiment profile.
- `formal-lab/perf_{1,2,4}cpu/`: clean performance runs with coverage disabled.
- `formal-lab/coverage_1cpu/`: direct-hit coverage evidence collected separately from clean timing.
- `attribution/`: local ftrace/smaps follow-up for the upstream request for
  path breakdown. The current local result points at `reclaim_pages()` /
  `shrink_folio_list()` and repeated `split_folio_to_list()` hits on
  `v6.19.9`, but also shows a critical caveat: local `v6.12.77` often has
  `AnonHugePages=0 kB` while `v6.19.9` is THP-backed. It is attribution
  evidence only, not clean timing evidence.
