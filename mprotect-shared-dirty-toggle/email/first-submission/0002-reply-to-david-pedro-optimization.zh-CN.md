# 回复 David：Pedro mprotect optimization 的中文审阅版

> 说明：这是 `0002-reply-to-david-pedro-optimization.md` 的中文审阅版，不直接发送到上游。实际发送仍使用英文版。

建议主题：

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

建议正文含义：

```text
Hi David,

感谢你指出这个方向。我测试了当前 akpm/mm 的 mm-unstable 分支，commit 是
444fc9435e57。这个分支已经包含 Pedro v3 的两个 mprotect patch：softleaf
refactor，以及相关的 small-folio / nr_ptes == 1 变更。

我先做了一轮本地 sanity check，然后又在 lab 机器上用同一个
shared-dirty full-range toggle workload 重跑：

  kernels: v6.12.77, v6.19.9, akpm/mm mm-unstable 444fc9435e57
  QEMU: direct boot
  lab guest CPUs: QEMU_SMP=1/2/4/8/16
  lab guest memory: 1/2/4 CPU 使用 14336 MiB，
                    8 CPU 使用 16384 MiB，
                    16 CPU 使用 32768 MiB
  repetitions: 9
  order: interleaved
  coverage: disabled

主要指标是 cycle_ns_per_page，越低越好。这里的 cycle 指一次 workload
iteration，不是 CPU 硬件周期：

  CPU   v6.12.77   v6.19.9   mm-unstable   mm-unstable vs v6.19   gap closed
    1      336.1     532.0       497.0          快 6.6%             17.9%
    2      369.2     581.9       503.3          快 13.5%            36.9%
    4      355.7     587.2       524.2          快 10.7%            27.2%
    8      369.7     583.6       534.2          快 8.5%             23.1%
   16      374.8     607.1       547.8          快 9.8%             25.5%

1/2/4/8 CPU 行里三个内核都完成了 9/9。16 CPU 行里 v6.12.77 有一次
QEMU failure，所以我只把 16 CPU 当成补充趋势。

所以，是的，Pedro 的 small-folio 工作确实在我的环境里降低了这个
synthetic shared-dirty signal。但它看起来没有修掉相对 v6.12.77 的大部分
差距：按 cycle_ns_per_page 看，在干净的 1/2/4/8 CPU lab 行里，它大约
关闭了 v6.12 -> v6.19 差距的 18-37%。

我还单独跑了一轮 state-shape audit，因为 MADV_PAGEOUT 的后续检查说明：
如果比较的内核实际操作的 page state 不一样，timing delta 可能会误导。
对这个 mprotect workload，v6.12.77、v6.19.9 和 mm-unstable 的成功 run 都是
同一种 4 KiB shared-dirty PTE mapping 状态：

  expected_match_ratio = 100
  unexpected_results = 0
  final_vmas_avg = 1
  protect 前后 present pages = 16384 / 16384
  AnonHugePages = 0
  KernelPageSize/MMUPageSize = 4 KiB / 4 KiB
  THPeligible = 0

这轮 state audit 使用同样的 1/2/4/8/16 CPU 和 memory 矩阵，每个内核 5 次。
1/2/4/8 CPU 三个内核都完成 5/5；16 CPU 里 v6.19.9 有一次 QEMU failure，
但成功的 v6.19.9 run 仍是同样的 state-shape 值。

我把 follow-up 摘要放在这里：

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/0c0e2d9/mprotect-shared-dirty-toggle/mm-unstable-lab-sanity

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/0c0e2d9/mprotect-shared-dirty-toggle/state-audit-lab

考虑到 Lorenzo 问到 workload 是否 synthetic，我会避免把这条继续写成很强的
regression claim，除非我能提供 standalone reproducer 或更窄的 bisect。如果这个
剩余 signal 仍然值得刻画，我可以准备一个更小的 standalone reproducer，或者尝试
bisect 剩余差距。

Thanks,
Chengfeng
```
