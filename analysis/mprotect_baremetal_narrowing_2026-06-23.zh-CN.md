# mprotect bare-metal narrowing note - 2026-06-23

## 结果摘要

新 bare-metal 节点上的 `mprotect_shared_dirty_reproducer` 已经完成 release-window
narrowing。结果目录：

```text
mprotect-shared-dirty-toggle/bare-metal/20260623-narrow-6.16-6.19-3rounds/
```

主指标是 `iteration_ns_per_page`，越小越好。三轮 interleaved 结果：

```text
6.16.0-bm-6.16        25 25 25  mean=25.000
6.17.0-bm-6.17        37 37 37  mean=37.000
6.18.0-bm-6.18        38 38 38  mean=38.000
6.18.19-bm-6.18.19    38 38 38  mean=38.000
6.19.9-bm-6.19.9      37 36 37  mean=36.667
```

所有 step 都是 `expected_match_ratio=100`、`unexpected_results=0`。

当前 clean release kernel 证据支持 release-window 级别结论：该 standalone workload
的 slowdown 出现在 `v6.16 -> v6.17`。2026-06-24 补充的 attribution-only probe
进一步支持该窗口中的 PTE batching hot-path shape 是主要成本来源。

## 源码差异方向

`v6.16 -> v6.17` 的 `mm/mprotect.c` 文件级 diff 显示，`change_pte_range()` 从
单页 PTE 修改路径变成批处理形状：

- 新增 `mprotect_folio_pte_batch()`，用 folio 信息决定本轮处理多少 PTE。
- 新增 `modify_prot_start_ptes()` / `modify_prot_commit_ptes()` 批量 start/commit helper。
- 新增 `set_write_prot_commit_flush_ptes()` 和 sub-batch helper，用于保持
  private anon exclusivity 判断的正确性。
- loop 从固定 `pte++` / `addr += PAGE_SIZE` 变成 `pte += nr_ptes` /
  `addr += nr_ptes * PAGE_SIZE`。

对当前 workload 来说，映射是 4 KiB shared dirty base-page，不是大 folio。也就是说，
批处理本身不会提供大于 1 的有效 batch，但新的 generic batching shape 仍然改变了热路径：
它会先做 `vm_normal_page()` / folio 查找，计算 `nr_ptes`，再通过批处理 helper 提交。

因此当前最合理的工作假设是：`v6.17` 引入的 mprotect PTE batching 形状让
base-page shared-dirty toggle workload 变慢；这和 LKML 上独立讨论中 bisect 到
`cac1db8c3aad ("mm: optimize mprotect() by PTE batching")` 的方向一致。

## 仍需避免的过度表述

- 这不是泛化的 `mprotect()` regression claim，只限定在当前 shared-dirty full-range
  protection-toggle standalone workload。
- 本地证据还没有完成 exact commit revert 或 git bisect；`cac1db8c3aad` 是外部讨论中的
  bisect 结果。我们当前自身证据是 release-window narrowing、source diff 对齐，以及
  针对 present-PTE hot path 的 attribution-only probe。
- `6.19.9 + Pedro v3 patch-only` 没有改善这条 standalone workload；因此不能把该 patch
  说成当前 standalone 场景的修复。

## 2026-06-24 attribution probe 更新

补了一轮 `v6.17` attribution-only probe：

```text
mprotect-shared-dirty-toggle/bare-metal/20260624-6.17-singlepte-probe/
```

该 probe 在 `v6.17` 基础上只改 `mm/mprotect.c::change_pte_range()` 的
present-PTE path，把当前 shared-dirty base-page 场景会走到的部分恢复成
single-PTE start/commit/flush 形状。它不是 upstream patch，也不是 clean release
kernel A/B。

结果：

```text
6.16.0-bm-6.16                      25 25 25  mean=25.000
6.17.0-bm-6.17                      37 37 37  mean=37.000
6.17.0-bm-6.17-singlepte-probe      25 25 25  mean=25.000
```

所有 probe run 都是 `expected_match_ratio=100`、`unexpected_results=0`，
state-shape 仍是 4 KiB/no THP。

这把当前工作假设从“release-window 和 source diff 对齐”推进到更强的机制归因：
在这个 standalone workload 上，`v6.17` 的 PTE batching hot-path shape 是主要成本来源；
恢复单页 present-PTE path 后，结果回到 `v6.16` 快区间。

但这个 probe 不是 `cac1db8c3aad` 的完整 exact revert。官方 patch 反打到当前
`linux-6.17` tree 时有 4 个 hunk 不匹配，所以更准确的标签是：

```text
commit-aligned source probe / attribution-only probe
```

参考：

- https://lkml.iu.edu/2602.1/07208.html
