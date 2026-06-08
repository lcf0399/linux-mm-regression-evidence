# mincore Present-PTE Lab Validation Summary

These CSV files are compact summaries copied from the local lab run outputs.
They are meant for maintainer review, not as a full raw-run archive.

Common setup for the key timing rows:

- QEMU direct boot on the lab host.
- Guest CPUs: `QEMU_SMP=1/2/4`.
- Repetitions: 9 for timing A/B rows.
- Coverage: disabled for timing.
- Primary scenario: `no_thp_pte_scan_64m`.
- Primary metric: `mincore_ns_per_1k_pages`, lower is better.

The high-CPU follow-ups below are labeled separately because they use larger
CPU and guest-memory settings than the primary 1/2/4 CPU matrix.  The
present-first high-CPU A/B rows test the candidate patch shape.  The
matched-PREEMPT release-level bridge rows are context only.

## Key Results

Matched-PREEMPT 1/2/4 CPU release bridge:

```text
source: matched-1-2-4-preempt-bridge.summary.csv
source: matched-1-2-4-preempt-bridge.interpreted.csv

CPU  v6.12.77   v6.18.19   v6.19.9    v7.0.9
1    12827.667  15677.444  16482.667  16726.333
2    13628.444  16102.333  18256.889  17270.333
4    13798.222  16739.333  18892.111  17068.222
```

This bridge shows cumulative cost relative to v6.12 in the primary 1/2/4 CPU
matrix.  It is used as release-level narrowing context before the v6.16
introduction-window A/B below.

v6.16 introduction-window A/B:

```text
source: v6.16-fastpath-ab.summary.csv

CPU  v6.15      v6.16      v6.16 fastpath  v6.16 nobatch
1    12946.889  17117.667  14560.556       13843.222
2    15053.111  18214.667  15714.778       14270.556
4    14942.000  18338.222  14397.889       14719.667
```

v6.16 introduction-window high-CPU follow-up:

```text
source: v6.16-fastpath-highcpu-ab.summary.csv
source: v6.16-fastpath-highcpu-ab.v615-16cpu-supplement.summary.csv
source: v6.16-fastpath-highcpu-ab.interpreted.csv

CPU/mem     v6.15      v6.16      v6.16 fastpath  v6.16 nobatch
8/16 GiB    15046.444  17540.222  13696.333       13200.000
16/32 GiB   14674.111  18928.889  13949.000       15351.111
```

The high-CPU matrix completed 72/72 with all_cpu_match=true,
any_noapic=false, all_autorun_exit0=true, and all_semantic_ok=true.  One v6.15
16CPU timing sample in the main matrix was an obvious outlier, so the 16/32 GiB
v6.15 value uses a clean v6.15-only 9-repeat supplement.

v6.18 present-first confirmation:

```text
source: v6.18-presentfirst-confirm.summary.csv

CPU  v6.15      v6.18      v6.18 present-first
1    13373.222  16473.000  11055.222
2    13454.444  16424.444  11467.556
4    13651.778  16772.333  11470.444
```

v7.0 present-first A/B:

```text
source: v7.0-presentfirst-ab.summary.csv

CPU  v7.0.9     v7.0.9 present-first
1    16328.778  10061.778
2    17600.000  11856.444
4    17819.000  11961.556
```

High-CPU present-first A/B follow-up:

```text
source: presentfirst-highcpu-ab.summary.csv
source: presentfirst-highcpu-ab.delta.csv

CPU/mem     kernel   original    present-first   mean improvement
8/16 GiB    v6.18    16008.778      10941.444          31.65%
16/32 GiB   v6.18    17549.556      11725.111          33.19%
8/16 GiB    v7.0.9   17379.778      10999.889          36.71%
16/32 GiB   v7.0.9   17917.778      11555.889          35.51%
```

This matrix completed 72/72 with all_cpu_match=true, any_noapic=false,
all_autorun_exit0=true, all_thp_always_cmdline=true, and all_semantic_ok=true.
It supports the present-first candidate shape on the x86 high-CPU lab path.
It is still not a substitute for arm64/mTHP/contiguous-PTE preservation
validation.

Matched-PREEMPT 8CPU/16CPU release-bridge rerun:

```text
source: matched-8-16-preempt-bridge-rerun-20260608.summary.csv
source: matched-8-16-preempt-bridge-rerun-20260608.failures.csv

CPU/mem     v6.12.77   v6.18.19   v6.19.9    v7.0.9
8/16 GiB    17251.889  23335.556  21863.556  21664.778
16/32 GiB   16697.333  21428.333  21629.778  21628.333
```

This 2026-06-08 rerun was done on the shared lab while the host was busy, and
the high-CPU CV is higher than the primary 1/2/4 CPU matrix.  The 8CPU row
completed 36/36.  The 16CPU row had two QEMU returncode-139 failures in the
original 36-run matrix; the missing v6.12/v6.18 samples were filled by a clean
two-run supplement.  Treat these high-CPU rows as extended context only.

v6.18 all-scenario semantic smoke:

```text
source: v6.18-presentfirst-allscenario-smoke.summary.csv

The v6.18 original and present-first kernels both completed THP and no-THP
scenarios with all_semantic_ok=true.
```

ftrace attribution:

```text
source: v6.16-intro-ftrace.profile.csv

The v6.16 original kernel shows a higher avg_us in mincore_pte_range than
v6.15, v6.16-nobatch, and v6.16-fastpath.
```

## Interpretation

The current best statement is:

```text
narrowed suspect + candidate fix shape validated on x86 lab
```

This is not yet an upstream-ready fix.  The remaining gap is arm64 or
mTHP/large-folio preservation validation.
