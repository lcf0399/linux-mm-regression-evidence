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

Matched-PREEMPT 8CPU follow-up:

```text
source: matched-8cpu-preempt-bridge.summary.csv

CPU/mem     v6.12.77-preempt  v6.18.19-preempt  v6.19.9-preempt  v7.0.9-preempt
8/16 GiB          19866.111         20655.778         20867.333        20496.667
```

This matched 8CPU row is neutral for high-CPU old-faster evidence: v7.0.9 is
only about 3.2% slower than v6.12.77 by mean, below the 5% threshold, and is not
slower than v6.18.19/v6.19.9.  The original 36-run matrix had one v6.12.77 QEMU
returncode 139; the summary uses the 35 successful original samples plus one
successful v6.12.77 supplemental sample.

Matched-PREEMPT 16CPU follow-up:

```text
source: matched-16cpu-preempt-bridge.summary.csv
source: matched-16cpu-v70-supplement.summary.csv
source: matched-16cpu-interpreted.summary.csv

CPU/mem      v6.12.77-preempt  v6.18.19-preempt  v6.19.9-preempt  v7.0.9-preempt supplement
16/32 GiB          15011.667         17296.111         18919.556                 18160.667
```

The 16CPU matched matrix completed 36/36 with all_semantic_ok=true, but one
v7.0.9 repeat was an obvious timing outlier (`mincore_calls=4`, v7 CV=2.978).
The table therefore follows `matched-16cpu-interpreted.summary.csv`, which uses
the separate v7-only 9-repeat supplement for the v7 value.  Treat this row as
noisy extended context only: it is consistent with a cumulative v6.12 -> later
cost, but it is not a clean v7.0.9-vs-v6.19.9 regression row and it is not part
of the primary 1/2/4 CPU evidence.

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
