# mprotect shared dirty PTE toggle 回归报告邮件草稿中文版

> 说明：这是 `0002-mprotect-shared-dirty-toggle-regression.eml` 的中文审阅版，不是准备直接发送到上游邮件列表的版本。

```text
To: Andrew Morton <akpm@linux-foundation.org>, linux-mm@kvack.org
Cc: "Liam R. Howlett" <Liam.Howlett@oracle.com>, Lorenzo Stoakes <lorenzo.stoakes@oracle.com>, Vlastimil Babka <vbabka@suse.cz>, Jann Horn <jannh@google.com>, Pedro Falcato <pfalcato@suse.de>, linux-kernel@vger.kernel.org, regressions@lists.linux.dev
Subject: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

你好，

我想报告一个用户态可观察到的 `mprotect()` performance regression，出现在 shared dirty PTE workload 中。

这个 workload 有意限定得比较窄：

- anonymous shared 64 MiB mapping
- 在 protection change 之前 prefault
- 反复对整个 range 执行 `mprotect(PROT_READ)`
- 再用 `mprotect(PROT_READ | PROT_WRITE)` 恢复
- protection cycle 之后执行 write-touch

这不是一个泛化的 `mprotect()` 回归报告。特别是，我不声称 anon/THP mprotect 路径也发生了回归。当前信号只限定在上面的 shared-dirty full-range PTE toggle path。

当前公开证据包在这里：

```text
https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/e13469b/mprotect-shared-dirty-toggle
```

用于审计 workload 语义的生成 workload 源码在这里：

```text
https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/blob/e13469b/mprotect-shared-dirty-toggle/workload/mprotect_paths_storm.c
```

formal 实验 profile 在这里：

```text
https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/e13469b/mprotect-shared-dirty-toggle/experiments
```

formal timing run 使用相似 kernel configuration，通过 QEMU direct boot 比较 `v6.12.77` 和 `v6.19.9`。formal performance run 是关闭 coverage 的 clean timing run。coverage 是单独收集的，不用于下面的 timing 数字。

Lab 环境：

```text
host label: lcf
host kernel: Linux 6.14.0-37-generic x86_64
QEMU: qemu-system-x86_64 8.2.2
container/cgroup CPU set: 0,2,4,6,8,10,12,14
container/cgroup memory limit: 16106127360 bytes
guest memory: QEMU_MEM_MB=14336
guest CPUs: QEMU_SMP=1/2/4
repetitions: 9
version order: interleaved
performance coverage_enabled: false
```

主要结果，`cycle_ns_per_page`，越低越好：

```text
CPU   v6.12.77   v6.19.9   old-lower-vs-new   v6.19/v6.12   reliability
  1      346.8     578.1        40.0%             1.67x      reliable
  2      394.7     641.7        38.5%             1.63x      robust-only
  4      381.1     624.8        39.0%             1.64x      partial, same direction
```

当前最强结果是 lab formal 的 1CPU 结果。2CPU 是同方向，但在框架分类里属于 robust-only。4CPU 也是同方向，但因为有一次 QEMU run 失败，所以属于 partial；这个 CPU 数的 summary 里仍有 8 次成功运行。

当前机制假设限定在 shared-dirty PTE path。`v6.19` 中，实测 hot path 经过 `change_pte_range()` batching machinery：

```text
change_pte_range()
  -> mprotect_folio_pte_batch()
  -> modify_prot_start_ptes()
  -> set_write_prot_commit_flush_ptes()
  -> prot_commit_flush_ptes()
```

对于这个 shared-dirty workload，后续 batch-probe attribution 显示实测路径中的 `nr_ptes=1`。当前假设是：额外的 folio lookup、batch-size query、helper dispatch 和 commit machinery 都按每个 4 KiB PTE 付费，但在这个 workload 里没有有效的 batch-size amortization。

这是机制解释，不是已经完成的 culprit-commit bisect。

我目前还没有 bisect 到具体 culprit commit。单独做过的 release-level sanity check 显示 `v6.18.19` 已经进入慢速范围，所以当前最佳报告范围是：

```text
#regzbot introduced: v6.12..v6.18
```

如果需要 standalone reproducer、更窄的 bisect，或者额外 raw logs，请告诉我。
