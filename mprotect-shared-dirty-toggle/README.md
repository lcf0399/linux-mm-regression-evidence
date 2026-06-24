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

## Follow-up Results

David Hildenbrand pointed to Pedro Falcato's recent small-folio mprotect
optimization. A lab sanity matrix against `akpm/mm mm-unstable
444fc9435e57` shows partial mitigation in this workload, but not a return
to `v6.12.77` timing:

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | gap closed |
|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 6.6% faster | 17.9% |
| 2 | 369.2 | 581.9 | 503.3 | 13.5% faster | 36.9% |
| 4 | 355.7 | 587.2 | 524.2 | 10.7% faster | 27.2% |
| 8 | 369.7 | 583.6 | 534.2 | 8.5% faster | 23.1% |
| 16 | 374.8 | 607.1 | 547.8 | 9.8% faster | 25.5% |

The 16 CPU row has one `v6.12.77` QEMU failure in that sanity matrix, so it
is supporting trend evidence only.

A separate state-shape audit checked whether this mprotect comparison has a
`MADV_PAGEOUT`-style caveat where kernels operate on materially different
page/VMA state. The state audit found the successful `v6.12.77`, `v6.19.9`,
and `mm-unstable` runs all using the same 4 KiB shared-dirty PTE mapping
shape: 16384 present pages before/after, no THP backing, one final VMA, and
no semantic mismatches. That supports treating the remaining timing gap as a
same-state implementation-path cost rather than a mismatched workload-state
comparison.

## Directories

- `workload/`: generated workload source used by the framework.
- `reproducer/`: standalone C reproducer and helper script for maintainer-side
  quick checks outside the experiment framework.
- `reproducer-validation/`: lab validation summary for the standalone
  reproducer.
- `experiments/`: formal experiment profile.
- `formal-lab/perf_{1,2,4}cpu/`: performance runs with coverage disabled.
- `formal-lab/coverage_1cpu/`: direct-hit coverage evidence collected separately from clean timing.
- `mm-unstable-lab-sanity/`: lab follow-up matrix for the small-folio optimization discussion.
- `state-audit-lab/`: lab state-shape audit supporting the same-state comparison assumption.
- `mm-unstable-local-sanity/`: local follow-up context only.
- `email/`: upstream mail drafts, follow-up drafts, and Chinese review notes.
- `bare-metal/`: i7-14700 bare-metal rerun results. The standalone A/B still
  shows `6.19.9` slower than `6.12.77`; `6.19.9 + Pedro v3` patch-only did
  not improve this standalone result. A later release-window narrowing shows
  the slowdown appears in the `v6.16 -> v6.17` window, and a v6.17
  attribution-only single-PTE probe brings the standalone metric back to the
  v6.16 fast range. That supports the working hypothesis that the cost in this
  workload comes from the v6.17 PTE-batching shape in
  `mm/mprotect.c::change_pte_range()`. The probe is not an exact commit
  revert; see
  `bare-metal/20260624-6.17-singlepte-probe/source-attribution-note.zh-CN.md`.

For the follow-up directories, compact `results/` subdirectories contain the
auditable `summary`, `raw`, `pipeline_run_env.json`, and `execution_order.json`
files for each CPU/memory row. Full runner directories and verbose launch logs
are excluded from the public bundle unless they become necessary for debugging.
