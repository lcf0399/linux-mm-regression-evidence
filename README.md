# Linux MM Regression Evidence - May 2026

This repository contains a small evidence bundle for two Linux MM performance regression reports. It is meant to make the formal test method, environment, raw summaries, and current attribution state auditable without putting a large attachment into the mailing-list report.

The two reports are scoped by workload:

- `madvise-pageout-thp-noswap-refault/`: `madvise(MADV_PAGEOUT)` on an anonymous THP/no-swap reclaim-failure path. The directory name preserves the wording from the original report, but the current description should not imply that the pages were actually paged out and faulted back in.
- `mprotect-shared-dirty-toggle/`: repeated `mprotect()` toggling over a shared dirty PTE mapping.
- `analysis/`: local review notes, upstream feedback, patch analysis, and historical four-case attribution material. This is a staging area; what to publish can be decided later.

This is not a broad benchmark suite. Each claim is limited to the workload and environment described below.

## Experiment Method

Both workloads were run through the same local experiment framework:

- Source-calibrated workloads target concrete Linux `mm/*.c` paths and export per-page timing metrics.
- Coverage and performance evidence were collected separately. Coverage runs only show direct function-entry hits; clean performance runs have coverage disabled.
- Formal performance runs use interleaved version order to reduce host-drift bias.
- The lab formal matrix uses `QEMU_SMP=1/2/4` with the same guest memory, kernel config family, and command-line policy across CPU counts.
- Separate release-level sanity checks were used to choose a broad reporting range, but they are not part of this compact public evidence bundle. No commit-level bisection has been completed yet.

Primary timing metrics are lower-is-better:

- `cycle_ns_per_page`
- `advise_ns_per_page` for the `MADV_PAGEOUT` syscall/reclaim-side segment

Here, `cycle` means one complete workload iteration, not CPU cycles.
`cycle_ns_per_page` is wall-clock nanoseconds per page per workload iteration.
The name is kept for compatibility with the local framework, but it should be
explained this way in upstream discussion to avoid ambiguity.

The exact per-run metadata for the formal evidence is preserved in `pipeline_run_env.json`, `execution_order.json`, `*.summary.csv/json`, and `*.raw.csv/json`.

## Environment Summary

The formal evidence uses the lab server as the primary timing environment:

- Host label in metadata: `lcf`
- Host kernel: `Linux 6.14.0-37-generic x86_64`
- Host CPU count: 128
- Container/cgroup CPU set: `0,2,4,6,8,10,12,14`
- Container/cgroup memory limit: `16106127360` bytes
- QEMU: `qemu-system-x86_64 8.2.2`
- Guest memory: `QEMU_MEM_MB=14336`
- Guest CPUs: `QEMU_SMP=1/2/4`
- Timing order: interleaved version order
- Formal repetitions: 9
- Performance timing: coverage disabled

The exact per-run environment remains in `pipeline_run_env.json`; this section is only a human-readable summary.

## Current Attribution

The attribution notes below are mechanism interpretation. The formal performance claims still rely on the clean timing runs with coverage/probe instrumentation disabled.

### MADV_PAGEOUT / THP / No-swap Reclaim Failure

The current interpretation is not a generic `madvise()` slowdown and not a generic `MADV_PAGEOUT` slowdown.

The regression is scoped to this workflow:

1. map 16 MiB anonymous memory
2. let the mapping use the default THP path
3. run `madvise(MADV_PAGEOUT)` in a guest with no configured swap
4. write-touch the mapping as the second half of the workload iteration

Upstream feedback correctly pointed out that with no swap configured, this should not be described as a real pageout/refault case. A more accurate description is a `MADV_PAGEOUT` anon/THP no-swap reclaim/swap-allocation-failure path; the later write-touch is part of the workload iteration.

The timing split points to the `MADV_PAGEOUT` / reclaim part. Coverage and follow-up path validation point to the same reclaim/swap-failure chain:

```text
madvise(MADV_PAGEOUT)
  -> reclaim_pages()
  -> shrink_folio_list()
  -> folio_alloc_swap()
  -> swap allocation failure path
```

Several local 1CPU ftrace/smaps attribution runs were added on 2026-05-19. The
raw runs are now grouped under:

```text
madvise-pageout-thp-noswap-refault/attribution/runs/local/
madvise-pageout-thp-noswap-refault/attribution/summaries/local-ftrace-20260519.zh-CN.md
```

These local and lab reruns are not clean timing evidence, but the path breakdown shows that the
additional `v6.19.9` time is concentrated under `reclaim_pages()` /
`shrink_folio_list()`, and `split_folio_to_list()` is hit 16 times on
`v6.19.9` in THP-backed local short runs.

The lab ftrace/smaps attribution has been consolidated under:

```text
madvise-pageout-thp-noswap-refault/attribution/summaries/lab-1cpu-20260520.zh-CN.md
madvise-pageout-thp-noswap-refault/attribution/summaries/lab-multicpu-followup-20260520.zh-CN.md
madvise-pageout-thp-noswap-refault/attribution/runs/lab/
```

The more important new caveat is page state: local and lab smaps show that in the
default-THP and explicit `thp=hugepage` runs, `v6.12.77` actually had
`AnonHugePages=0 kB`, while `v6.19.9` had `AnonHugePages=16384 kB`. In the
explicit `thp=nohugepage` same-state control, neither kernel hit
`split_folio_to_list()` and the local short run no longer showed an
old-version-faster signal.

The current interpretation is therefore narrower: the signal is strongly tied
to actual THP backing and the no-swap reclaim split/failure path. Future
upstream wording should correct the original same-state regression framing and
ask whether the no-swap THP split fast-fail direction is still useful as an
optimization discussion.

Separate release-level sanity checks showed `v6.18.19` already in the slow range, but the exact culprit commit is not bisected.

### mprotect Shared-dirty Toggle

The current mechanism hypothesis is more localized here.

The workload repeatedly toggles protection over a shared dirty 64 MiB mapping. The strongest attribution points to the v6.19 `change_pte_range()` batching rewrite:

```text
change_pte_range()
  -> mprotect_folio_pte_batch()
  -> modify_prot_start_ptes()
  -> set_write_prot_commit_flush_ptes()
  -> prot_commit_flush_ptes()
```

For this shared-dirty workload, the measured path does not form an effective large PTE batch. Batch-probe attribution showed `nr_ptes=1` for the shared-dirty path. That means the extra folio lookup, batch-size query, helper dispatch, and batch commit machinery are paid per 4 KiB PTE, but there is no batch-size amortization.

After upstream feedback, two follow-up checks were added:

- `mm-unstable-lab-sanity/`: current akpm/mm `mm-unstable` commit
  `444fc9435e57` partially mitigates the synthetic shared-dirty signal
  versus `v6.19.9` by about 6.6-13.5% in the lab CPU/memory matrix, closing
  about 18-37% of the `v6.12.77 -> v6.19.9` gap, but it does not restore
  `v6.12.77`-level timing in this workload.
- `state-audit-lab/`: a state-shape audit across `v6.12.77`, `v6.19.9`, and
  `mm-unstable` found the successful runs all use the same 4 KiB shared-dirty
  PTE mapping shape: 16384 present pages before/after, no THP backing, one
  final VMA, and no semantic mismatches. This supports treating mprotect as a
  same-state comparison, unlike the corrected `MADV_PAGEOUT` follow-up.

This also explains why the result should not be generalized to all `mprotect()` users. Anonymous THP-oriented `mprotect()` paths can go through huge-PMD/THP handling and do not show the same behavior in the same test suite. The regression claim is therefore scoped to the shared dirty PTE toggle path.

Separate release-level sanity checks showed `v6.18.19` already in the slow range, but the exact culprit commit is not bisected.

## Data Selection Policy

The formal workload directories include the latest citable evidence bundle for the two reports:

- latest lab formal refresh results for the main performance claims
- separate coverage evidence where useful, kept distinct from clean performance timing

Older screenings, release-level sanity runs, invalid runs, failed runs, instrumentation-contaminated runs, and exploratory intermediate outputs are kept out of the minimal public evidence bundle by default. The `analysis/` directory is a local staging area for broader notes and historical material; it should be reviewed before publishing.

## Main Caveats

The reports are not claiming generic `madvise()` or generic `mprotect()` regressions.

The `MADV_PAGEOUT` claim is scoped to an anonymous THP/no-swap `MADV_PAGEOUT` reclaim-failure + write-touch iteration workflow; a real pageout/refault has not been established. The new local + lab attribution shows this is not a same-actual-THP-state comparison.

The `mprotect()` claim is scoped to the shared dirty full-range protection-toggle workload; the cleanest current formal result is the 1CPU lab run, while 2CPU and 4CPU are same-direction supporting evidence with reliability caveats.

No culprit commit has been bisected yet. The proposed reporting range remains `v6.12..v6.18` based on separate release-level sanity checks.
