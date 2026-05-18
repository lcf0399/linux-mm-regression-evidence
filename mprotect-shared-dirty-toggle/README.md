# mprotect Shared-dirty Toggle Evidence

This directory supports the report:

```text
[REGRESSION] mm/mprotect: shared dirty PTE toggle path is ~40% slower on v6.19 than v6.12
```

## Claim scope

This is a userspace-visible `mprotect()` workload:

- shared dirty 64 MiB mapping
- repeated full-range protection toggle
- focus on the shared-dirty PTE path

It does not claim a generic `mprotect()` regression, and does not claim `anon_full_toggle` or THP mprotect regression.

## Key result

Formal lab timing shows `v6.19.9` slower than `v6.12.77`.

`cycle_ns_per_page`:

| CPU | v6.12.77 | v6.19.9 | delta | reliability |
| --- | ---: | ---: | ---: | --- |
| 1 | 346.8 | 578.1 | -40.0% | clean reliable |
| 2 | 394.7 | 641.7 | -38.5% | robust-only |
| 4 | 381.1 | 624.8 | -39.0% | partial same direction |

Separate release-level sanity checks showed `v6.18.19` already in the slow range, but those raw runs are kept out of this compact public evidence bundle.

## Directories

- `workload/`: generated workload source used by the framework.
- `experiments/`: formal experiment profile.
- `formal-lab/perf_{1,2,4}cpu/`: performance runs with coverage disabled.
- `formal-lab/coverage_1cpu/`: direct-hit coverage evidence collected separately from clean timing.
