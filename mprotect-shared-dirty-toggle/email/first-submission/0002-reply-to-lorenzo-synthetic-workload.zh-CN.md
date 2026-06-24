# 回复 Lorenzo：workload 是否 synthetic 的中文审阅版

> 说明：这是 `0002-reply-to-lorenzo-synthetic-workload.md` 的中文审阅版，不直接发送到上游。实际发送仍使用英文版。

建议主题：

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

建议正文含义：

```text
Hi Lorenzo,

很抱歉用了过期的邮箱地址。后续 kernel 邮件我会使用
ljs@kernel.org。

这个确实是一个 synthetic / source-calibrated 的用户态
micro-workload，不是我在生产应用中直接观察到的 regression。

这个 workload 是从 mm/mprotect.c 路径生成和校准出来的，之后我把它
收窄到 shared-dirty full-range PTE toggle 这个 timing 信号比较稳定的
case。因此我本来的 claim 只想限定为：“这个合法的 userspace mprotect
模式在我的测试环境中发生了回归”，而不是“某个已知真实应用 workload
发生了回归”。

我同意，这会让这个报告弱于 application-level regression。我之所以
把它发出来，是因为 clean 1CPU formal run 里的差异比较大
（v6.19 相比 v6.12 约慢 1.67x），而且路径看起来和
change_pte_range() batching path 有关；在我的 probe run 里，
shared-dirty case 没有形成有效 batch。

David 也提醒我 Pedro 最近有一组 mprotect micro-optimization series。
我测试了当前 akpm/mm 的 mm-unstable 分支，commit 是 444fc9435e57；
这个分支已经包含 Pedro v3 的两个 patch，其中包括相关的 small-folio /
nr_ptes == 1 变更。在我的 lab 矩阵里，它部分降低了 shared-dirty signal，
但没有消除相对 v6.12.77 的差距；在干净的 1/2/4/8 CPU 行里，它大约关闭了
v6.12 -> v6.19 差距的 18-37%。

我还做了一轮 state-shape audit，因为 MADV_PAGEOUT 的后续检查说明：
如果两个内核实际操作的 page state 不一样，timing delta 可能会误导。
对这个 mprotect workload，v6.12.77、v6.19.9 和 mm-unstable 的成功 run
都使用同一种 4 KiB shared-dirty PTE mapping 状态。

所以，在没有 standalone reproducer 或更窄 bisect 之前，我不会把它继续
推进成很强的 regression claim。如果这个剩余 synthetic signal 仍然值得
刻画，我可以准备一个更小的 standalone reproducer，或者尝试 bisect 剩余
差距。

抱歉打扰，也感谢你抽时间看这个问题。

Thanks,
Chengfeng
```

语气说明：

- 先为 stale address 道歉。
- 直接承认 synthetic，不绕。
- 不把 micro-workload 说成真实应用回归。
- 给出为什么仍然报告的理由，但不强迫对方接受。
- 承接 David 提到的候选优化，说明已经验证，结论是“部分缓解但未完全消除”。
- 语气上明确“先补强证据，再请维护者继续花时间”。
