# mincore Present-PTE Scan Codegen Check

This directory is a maintainer-facing evidence sketch for a source-calibrated
`mincore()` workload that stresses the resident anonymous base-page PTE path in
`mm/mincore.c`.

Current scope:

- Workload type: source-calibrated synthetic userspace micro-workload.
- Hot path: `mincore()` -> `walk_page_range()` -> `mincore_pte_range()`.
- Primary scenario: `MADV_NOHUGEPAGE` anonymous 64 MiB resident mapping,
  reported as `no_thp_pte_scan_64m`.
- Main metric: `mincore_ns_per_1k_pages`, lower is better.

This is not a claim about a production application and not a generic
`mincore()` regression report.  After the compiler cross-check in `codegen/`,
the current scope is narrower: it is a GCC-13.3/QEMU-observed
compiler/codegen-sensitive signal.  Clang 18.1.3 optimizes the checked x86
shapes to byte-identical `mincore_pte_range()` output.

## Current Finding

Release-level and A/B testing narrowed the main step to the v6.15 -> v6.16
window.  The strongest suspect is:

```text
4df65651f7075 mm: mincore: use pte_batch_hint() to batch process large folios
```

That change improved large-folio/mTHP mincore batching.  In the GCC 13.3 QEMU
lab runs, the base-page resident-PTE scan case showed a sizeable cost.

The key follow-up result is the codegen check:

- GCC 13.3 does not generate the same `mincore_pte_range()` shape for v6.16
  original.  The local `batch <= 1` fastpath and the nobatch variant do produce
  the same shape.
- Clang 18.1.3 generates byte-identical `mincore_pte_range()` output for
  v6.15 original, v6.16 original, the local fastpath variant, and the nobatch
  variant.

This means the observation should be treated as compiler/codegen-sensitive.  A
local present-first candidate is kept here as historical discussion material,
but it is not an upstream-ready fix and should not be presented as a generic
kernel regression fix.

## Contents

- `reproducer/`: standalone C reproducer distilled from the workload source.
- `experiments/`: the workload target/profile used by the local experiment
  framework. The standalone C source uses the same workload logic and is
  provided for maintainer-side builds without the full framework.
- `patches/mincore-present-first-fastpath-rfc.patch`: local test patch shape,
  not ready for direct upstream submission; retained as historical discussion
  material.
- `codegen/`: GCC 13.3 and Clang 18.1.3 `mincore_pte_range()` nm/objdump
  comparison for v6.15/v6.16 original and local variants.
- `lab-validation/`: compact CSV summaries, the primary 1/2/4 CPU validation
  note, matched-PREEMPT release bridge rows, high-CPU v6.16
  introduction-window A/B rows, and high-CPU present-first A/B rows.

## Caveats

- The timing signal has only been observed on the x86/QEMU lab setup with
  GCC-built kernels.  It should be described as compiler/codegen-sensitive,
  not as a generic x86 mincore regression.
- The Clang 18.1.3 cross-check does not reproduce the generated-code
  difference: all checked variants produce byte-identical
  `mincore_pte_range()` output.
- Physical CPU timing has not been run.
- The present-first patch has only been validated on the x86/QEMU lab setup,
  up to the 16CPU/32GiB no-THP present-PTE scan follow-up.
- Any real upstream fix direction would still need arm64 or mTHP/large-folio
  preservation validation.
- The patch file here intentionally says "not for submission"; it needs a real
  commit message, Signed-off-by, and architecture review before sending.
