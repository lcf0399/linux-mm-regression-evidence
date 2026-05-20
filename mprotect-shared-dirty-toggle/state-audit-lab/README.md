# mprotect Shared-dirty State Audit - Lab

This run is a state-shape audit for the `shared_dirty_full_toggle_64m`
workload. It is meant to rule out a `madvise`-style caveat where different
kernel versions operate on materially different mapping state.

This is not a performance claim and should not be used as old-faster evidence.
It checks:

- semantic success: `expected_match_ratio`, `unexpected_results`
- VMA shape: `split_vmas_avg`, `final_vmas_avg`
- smaps: AnonHugePages, KernelPageSize, MMUPageSize, THPeligible
- pagemap: present pages, soft-dirty pages

Planned matrix:

```text
1 CPU / 14336 MiB
2 CPU / 14336 MiB
4 CPU / 14336 MiB
8 CPU / 16384 MiB
16 CPU / 32768 MiB
```

Kernel versions:

```text
v6.12.77
v6.19.9
akpm/mm mm-unstable 444fc9435e57
```

## Result Summary

The completed 2026-05-20 lab run is summarized in:

```text
summary-20260520.md
summary-20260520.zh-CN.md
```

Short version: successful runs across `v6.12.77`, `v6.19.9`, and
`mm-unstable` all reported `expected_match_ratio=100`,
`unexpected_results=0`, one final VMA, 16384 present pages before and after
the protection cycle, `AnonHugePages=0`, 4 KiB kernel/MMU page size, and
`THPeligible=0`.

This supports treating the mprotect comparison as a same-state shared-dirty
4 KiB PTE workload comparison. Raw runner directories and launch logs are
kept local by default and are ignored from the compact public evidence bundle
unless they are explicitly needed for follow-up debugging.
