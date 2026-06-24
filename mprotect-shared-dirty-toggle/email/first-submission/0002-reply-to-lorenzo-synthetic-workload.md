# Reply draft to Lorenzo on mprotect workload scope

> 用法：对 Lorenzo 的邮件点 reply-all。尽量把 `lorenzo.stoakes@oracle.com` 替换成 `ljs@kernel.org`，或者至少额外 CC `ljs@kernel.org`。不要新开线程。

Suggested subject:

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

Suggested body:

```text
Hi Lorenzo,

Sorry about the stale address. I will use ljs@kernel.org for future
kernel mails.

This is a synthetic/source-calibrated userspace micro-workload, not a
regression I observed in a production application.

The workload was generated from the mm/mprotect.c path and then narrowed
to the shared-dirty full-range PTE toggle case where the timing signal was
stable enough to report. So the intended claim is limited to "this legal
userspace mprotect pattern regressed in the test setup", not "a known real
application workload regressed".

I agree that this makes the report weaker than an application-level
regression. I sent it because the delta is large in the clean 1CPU formal
run (~1.67x slower on v6.19 vs v6.12), and the path looked plausibly tied
to the change_pte_range() batching path where the shared-dirty case did
not form an effective batch in my probe runs.

David also pointed me at Pedro's recent mprotect micro-optimization
series. I tested the current akpm/mm mm-unstable branch at 444fc9435e57,
which contains Pedro's v3 two-patch series, including the relevant
small-folio / nr_ptes == 1 changes. In my lab matrix, that partially
reduces the shared-dirty signal, but does not remove the gap to v6.12.77;
it closes roughly 18-37% of the v6.12 -> v6.19 gap in the clean 1/2/4/8
CPU rows.

I also ran a state-shape audit after the MADV_PAGEOUT follow-up showed how
misleading a timing delta can be if two kernels are not operating on the
same page state. For this mprotect workload, the successful runs across
v6.12.77, v6.19.9, and mm-unstable all used the same 4 KiB shared-dirty PTE
mapping shape.

So I will not push this as a strong regression claim without a standalone
reproducer and/or narrower bisect. If the remaining synthetic signal is
still useful to characterize, I can prepare a smaller standalone reproducer
or try to bisect the remaining gap.

Sorry for the noise, and thanks for taking a look.

Thanks,
Chengfeng
```
