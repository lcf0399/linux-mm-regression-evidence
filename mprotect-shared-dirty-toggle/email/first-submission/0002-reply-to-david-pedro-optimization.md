# Reply draft to David about Pedro's mprotect optimization

> 用法：对 David 的邮件点 reply-all。保持同一个 thread。确认 CC 里有 `pfalcato@suse.de`，如果 Lorenzo 还在旧地址上，额外加 `ljs@kernel.org`。

Suggested subject:

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

Suggested body:

```text
Hi David,

Thanks for the pointer. I tested the current akpm/mm mm-unstable branch at
444fc9435e57, which contains Pedro's v3 two-patch mprotect series: the
softleaf refactor and the relevant small-folio / nr_ptes == 1 changes.

I first ran a local sanity check, and then reran the same shared-dirty
full-range toggle workload on the lab machine:

  kernels: v6.12.77, v6.19.9, akpm/mm mm-unstable 444fc9435e57
  QEMU: direct boot
  lab guest CPUs: QEMU_SMP=1/2/4/8/16
  lab guest memory: 14336 MiB for 1/2/4 CPU, 16384 MiB for 8 CPU,
                    32768 MiB for 16 CPU
  repetitions: 9
  order: interleaved
  coverage: disabled

The primary metric is cycle_ns_per_page, lower is better. Here "cycle" means
one workload iteration, not CPU cycles:

  CPU   v6.12.77   v6.19.9   mm-unstable   mm-unstable vs v6.19   gap closed
    1      336.1     532.0       497.0          6.6% faster          17.9%
    2      369.2     581.9       503.3         13.5% faster          36.9%
    4      355.7     587.2       524.2         10.7% faster          27.2%
    8      369.7     583.6       534.2          8.5% faster          23.1%
   16      374.8     607.1       547.8          9.8% faster          25.5%

The 1/2/4/8 CPU rows completed 9/9 runs for all three kernels. In the
16 CPU row, v6.12.77 had one QEMU failure, so I would treat that row only
as a supporting trend.

So yes, Pedro's small-folio work does reduce this synthetic shared-dirty
signal in my setup. It does not seem to remove most of the gap to v6.12.77:
looking at cycle_ns_per_page, it closes roughly 18-37% of the v6.12 ->
v6.19 gap in the clean 1/2/4/8 CPU lab rows.

I also ran a separate state-shape audit, because the MADV_PAGEOUT follow-up
showed that a timing delta can be misleading if the compared kernels are not
actually operating on the same page state. For this mprotect workload, the
successful runs across v6.12.77, v6.19.9, and mm-unstable all used the same
4 KiB shared-dirty PTE mapping shape:

  expected_match_ratio = 100
  unexpected_results = 0
  final_vmas_avg = 1
  present pages before/after protect = 16384 / 16384
  AnonHugePages = 0
  KernelPageSize/MMUPageSize = 4 KiB / 4 KiB
  THPeligible = 0

The state audit used the same 1/2/4/8/16 CPU and memory matrix, with 5 runs
per kernel. The 1/2/4/8 CPU rows completed 5/5 for all three kernels; the
16 CPU row had one v6.19.9 QEMU failure, but the successful v6.19.9 runs had
the same state-shape values.

I put the follow-up summaries here:

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/0c0e2d9/mprotect-shared-dirty-toggle/mm-unstable-lab-sanity

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/0c0e2d9/mprotect-shared-dirty-toggle/state-audit-lab

Given Lorenzo's question and the synthetic nature of this workload, I will
avoid treating this as a strong regression claim unless I can provide a
standalone reproducer and/or a narrower bisect. If this remaining signal is
still useful to characterize, I can prepare a smaller standalone reproducer
or try to bisect the remaining gap.

Thanks,
Chengfeng
```
