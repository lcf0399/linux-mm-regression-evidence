# Linux MM Regression Evidence - May 2026

This repository contains a small evidence bundle for two Linux MM performance regression reports. It is meant to make the formal test method, environment, raw summaries, and current attribution state auditable without putting a large attachment into the mailing-list report.

The two reports are scoped by workload:

- `madvise-pageout-thp-noswap-refault/`: `madvise(MADV_PAGEOUT)` on an anonymous THP/no-swap refault workflow.
- `mprotect-shared-dirty-toggle/`: repeated `mprotect()` toggling over a shared dirty PTE mapping.

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

### MADV_PAGEOUT / THP / No-swap Refault

The current interpretation is not a generic `madvise()` slowdown and not a generic `MADV_PAGEOUT` slowdown.

The regression is scoped to this workflow:

1. map 16 MiB anonymous memory
2. let the mapping use the default THP path
3. run `madvise(MADV_PAGEOUT)` in a guest with no configured swap
4. refault/write-touch the mapping

The timing split points to the `MADV_PAGEOUT` / reclaim part, not the refault touch part. Coverage and follow-up path validation point to the same reclaim/swap-failure chain:

```text
madvise(MADV_PAGEOUT)
  -> reclaim_pages()
  -> shrink_folio_list()
  -> folio_alloc_swap()
  -> swap allocation failure path
```

The important boundary is the no-swap THP path. In this environment, pageout of a THP-backed anonymous mapping can hit a worst case where swap allocation fails, THP handling/splitting is involved, and the reclaim path retries at page granularity. That is why this should be reported as a THP + `MADV_PAGEOUT` + no-swap refault workflow regression, not as a claim about all swap-backed or all `MADV_PAGEOUT` workloads.

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

This also explains why the result should not be generalized to all `mprotect()` users. Anonymous THP-oriented `mprotect()` paths can go through huge-PMD/THP handling and do not show the same behavior in the same test suite. The regression claim is therefore scoped to the shared dirty PTE toggle path.

Separate release-level sanity checks showed `v6.18.19` already in the slow range, but the exact culprit commit is not bisected.

## Data Selection Policy

This repository only includes the latest citable evidence bundle for the two reports:

- latest lab formal refresh results for the main performance claims
- separate coverage evidence where useful, kept distinct from clean performance timing

Older screenings, release-level sanity runs, invalid runs, failed runs, instrumentation-contaminated runs, and exploratory intermediate outputs are intentionally not uploaded here. They are kept out of the upstream evidence bundle so the reports stay focused on the latest citable formal data.

## Main Caveats

The reports are not claiming generic `madvise()` or generic `mprotect()` regressions.

The `MADV_PAGEOUT` claim is scoped to the anonymous THP/no-swap refault/write-touch workflow.

The `mprotect()` claim is scoped to the shared dirty full-range protection-toggle workload; the cleanest current formal result is the 1CPU lab run, while 2CPU and 4CPU are same-direction supporting evidence with reliability caveats.

No culprit commit has been bisected yet. The proposed reporting range remains `v6.12..v6.18` based on separate release-level sanity checks.
