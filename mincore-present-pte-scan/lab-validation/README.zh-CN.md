# mincore present-PTE lab 验证摘要

这些 CSV 文件是从本地 lab run 输出中复制出的紧凑摘要，方便维护者审阅；它不是完整 raw-run
归档。

关键 timing 行的共同设置：

- lab host 上 QEMU direct boot。
- Guest CPUs：`QEMU_SMP=1/2/4`。
- timing A/B 行重复次数：9。
- timing 时关闭 coverage。
- 主场景：`no_thp_pte_scan_64m`。
- 主指标：`mincore_ns_per_1k_pages`，越低越好。

下面的 high-CPU follow-up 单独标注，因为它们使用了比 primary 1/2/4 CPU matrix
更大的 CPU 和 guest-memory 设置。present-first high-CPU A/B 行测试的是候选 patch
形状；matched-PREEMPT release-level bridge 行只作为上下文。

## 关键结果

v6.16 引入窗口 A/B：

```text
source: v6.16-fastpath-ab.summary.csv

CPU  v6.15      v6.16      v6.16 fastpath  v6.16 nobatch
1    12946.889  17117.667  14560.556       13843.222
2    15053.111  18214.667  15714.778       14270.556
4    14942.000  18338.222  14397.889       14719.667
```

v6.16 引入窗口 high-CPU follow-up：

```text
source: v6.16-fastpath-highcpu-ab.summary.csv
source: v6.16-fastpath-highcpu-ab.v615-16cpu-supplement.summary.csv
source: v6.16-fastpath-highcpu-ab.interpreted.csv

CPU/mem     v6.15      v6.16      v6.16 fastpath  v6.16 nobatch
8/16 GiB    15046.444  17540.222  13696.333       13200.000
16/32 GiB   14674.111  18928.889  13949.000       15351.111
```

high-CPU matrix 72/72 完成，all_cpu_match=true，any_noapic=false，
all_autorun_exit0=true，all_semantic_ok=true。主矩阵中 v6.15 16CPU 有一个明显 timing
outlier，因此 16/32 GiB 的 v6.15 数字使用单独 v6.15-only 9-repeat supplement。

v6.18 present-first confirmation：

```text
source: v6.18-presentfirst-confirm.summary.csv

CPU  v6.15      v6.18      v6.18 present-first
1    13373.222  16473.000  11055.222
2    13454.444  16424.444  11467.556
4    13651.778  16772.333  11470.444
```

v7.0 present-first A/B：

```text
source: v7.0-presentfirst-ab.summary.csv

CPU  v7.0.9     v7.0.9 present-first
1    16328.778  10061.778
2    17600.000  11856.444
4    17819.000  11961.556
```

high-CPU present-first A/B follow-up：

```text
source: presentfirst-highcpu-ab.summary.csv
source: presentfirst-highcpu-ab.delta.csv

CPU/mem     kernel   original    present-first   mean improvement
8/16 GiB    v6.18    16008.778      10941.444          31.65%
16/32 GiB   v6.18    17549.556      11725.111          33.19%
8/16 GiB    v7.0.9   17379.778      10999.889          36.71%
16/32 GiB   v7.0.9   17917.778      11555.889          35.51%
```

这轮 matrix 72/72 完成，all_cpu_match=true，any_noapic=false，
all_autorun_exit0=true，all_thp_always_cmdline=true，all_semantic_ok=true。
它支持 present-first candidate shape 在 x86 high-CPU lab 路径上仍然有效；但仍不能
替代 arm64/mTHP/contiguous-PTE preservation validation。

matched-PREEMPT 8CPU follow-up：

```text
source: matched-8cpu-preempt-bridge.summary.csv

CPU/mem     v6.12.77-preempt  v6.18.19-preempt  v6.19.9-preempt  v7.0.9-preempt
8/16 GiB          19866.111         20655.778         20867.333        20496.667
```

这条 matched 8CPU row 对 high-CPU old-faster 证据是中性的：按 mean，v7.0.9
只比 v6.12.77 慢约 3.2%，低于 5% 门槛，并且不比 v6.18.19/v6.19.9 更慢。
原始 36-run matrix 有一个 v6.12.77 QEMU returncode 139；summary 使用 35 个原始
成功样本加 1 个成功的 v6.12.77 补跑样本。

matched-PREEMPT 16CPU follow-up：

```text
source: matched-16cpu-preempt-bridge.summary.csv
source: matched-16cpu-v70-supplement.summary.csv
source: matched-16cpu-interpreted.summary.csv

CPU/mem      v6.12.77-preempt  v6.18.19-preempt  v6.19.9-preempt  v7.0.9-preempt supplement
16/32 GiB          15011.667         17296.111         18919.556                 18160.667
```

16CPU matched matrix 36/36 完成，且 all_semantic_ok=true，但其中一个 v7.0.9 repeat
是明显 timing outlier（`mincore_calls=4`，v7 CV=2.978）。因此上表按
`matched-16cpu-interpreted.summary.csv` 解读，使用单独 v7-only 9-repeat supplement
作为 v7 数字。这条 row 只作为 noisy extended context：它和 v6.12 -> later 的累计成本
一致，但不是干净的 v7.0.9-vs-v6.19.9 regression row，也不是 primary 1/2/4 CPU
evidence。

v6.18 全场景 semantic smoke：

```text
source: v6.18-presentfirst-allscenario-smoke.summary.csv

v6.18 原版和 present-first kernel 的 THP/no-THP 场景均 all_semantic_ok=true。
```

ftrace 归因：

```text
source: v6.16-intro-ftrace.profile.csv

v6.16 原版的 mincore_pte_range avg_us 高于 v6.15、v6.16-nobatch 和 v6.16-fastpath。
```

## 解释

当前最准确的状态是：

```text
narrowed suspect + candidate fix shape validated on x86 lab
```

这还不是 upstream-ready fix。剩余关键缺口是 arm64 或 mTHP/large-folio 保真验证。
