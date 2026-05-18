# MADV_PAGEOUT THP/no-swap Refault Evidence

This directory supports the report:

```text
[REGRESSION] mm: MADV_PAGEOUT on THP/no-swap refault workflow is ~40% slower on v6.19 than v6.12
```

## Claim scope

This is a userspace-visible `madvise(MADV_PAGEOUT)` workload:

- anonymous 16 MiB mapping
- default THP path
- no guest swap
- `MADV_PAGEOUT`, then refault/write-touch

It does not claim that all `MADV_PAGEOUT` workloads regress.

## Key result

Formal lab timing shows `v6.19.9` slower than `v6.12.77` across `1/2/4` vCPUs.

`cycle_ns_per_page`:

| CPU | v6.12.77 | v6.19.9 | delta |
| --- | ---: | ---: | ---: |
| 1 | 1900.3 | 3304.7 | -42.5% |
| 2 | 2107.7 | 3583.2 | -41.2% |
| 4 | 2154.2 | 3690.9 | -41.6% |

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
