# MADV_PAGEOUT no-swap local ftrace/smaps 探索汇总 - 2026-05-19

这些本地 run 是上游要求 ftrace/perf breakdown 后的第一批探索材料。它们不是
formal lab timing，也不应用作最终性能结论。它们的价值在于逐步暴露：

- `v6.19.9` 的额外时间集中在 `reclaim_pages()` / `shrink_folio_list()`。
- `v6.19.9` 在 THP-backed 短跑中稳定命中 `split_folio_to_list()`。
- 原始实验更大的问题是：`v6.12.77` 与 `v6.19.9` 的 actual THP backing 不一致。

## 原始 run 目录

```text
runs/local/ftrace-local-20260519T095050Z/
runs/local/ftrace-local-20260519T_local_procfix/
runs/local/ftrace-local-20260519T_procpage/
runs/local/ftrace-local-20260519T_hugepage2/
runs/local/ftrace-local-20260519T_nohugepage/
```

## 分阶段结论

- `ftrace-local-20260519T095050Z/`
  - 早期 ftrace attribution，显示 `v6.19.9` 在 reclaim/split 侧更重。
  - 当时没有可靠 smaps/page-state 证据。
- `ftrace-local-20260519T_local_procfix/`
  - 复核 split 信号，确认 `split_folio_to_list()` 方向可重复。
  - 同样不能引用 smaps/page-state。
- `ftrace-local-20260519T_procpage/`
  - 打开 `CONFIG_PROC_PAGE_MONITOR=y` 后得到可读 smaps。
  - default THP 下，`v6.12.77` 实际 `AnonHugePages=0 kB`，`v6.19.9`
    实际 `AnonHugePages=16384 kB`。
- `ftrace-local-20260519T_hugepage2/`
  - 修正 THP mode 传递并显式请求 `hugepage`。
  - `v6.12.77` 仍没有实际 THP backing；`v6.19.9` 仍是 THP-backed。
- `ftrace-local-20260519T_nohugepage/`
  - 两边都是 `AnonHugePages=0 kB`、`THPeligible=0`。
  - 两边都不命中 `split_folio_to_list()`。
  - old-faster 信号消失。

## 后续影响

这些本地结果推动了 2026-05-20 的 lab 复核。lab 1CPU 与多 CPU 结果复现了同一
page-state caveat，因此当前不应继续把 madvise 结果描述为 same-state THP
performance regression。
