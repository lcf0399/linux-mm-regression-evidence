# MADV_PAGEOUT no-swap lab 多 CPU ftrace/smaps 补充结果 - 2026-05-20

这轮是对 `MADV_PAGEOUT anon/THP no-swap reclaim-failure path` 的 lab 侧
多 CPU attribution 补充。它不是 clean performance timing，不能替代 formal timing；
用途是确认不同 CPU/内存配置下的实际页状态、`split_folio_to_list()` 路径和时间分布。

## 运行口径

- kernel：`v6.12.77` vs `v6.19.9`。
- workload：`madvise_ftrace_guest.sh`，16 MiB anonymous mapping，`MADV_PAGEOUT`，
  guest 无 swap。
- tracing：ftrace/function profile + smaps，`CONFIG_PROC_PAGE_MONITOR=y`。
- modes：`default`、`hugepage`、`nohugepage`。
- 第一轮：
  - `STAMP_BASE=20260520T080847Z_lab_followup_madvise`
  - `QEMU_SMP=2/4`，`QEMU_MEM_MB=14336`
  - `8/16` 组合因当时容器仍是 15 GiB 上限被脚本保护逻辑跳过。
- 第二轮：
  - `STAMP_BASE=20260520T081655Z_lab_madvise_large`
  - 容器内存上限调到 48 GiB 后补跑。
  - `QEMU_SMP=8` with `QEMU_MEM_MB=16384`
  - `QEMU_SMP=16` with `QEMU_MEM_MB=32768`

对应目录：

```text
runs/lab/multicpu-20260520/smp2_mem14336_{default,hugepage,nohugepage}/
runs/lab/multicpu-20260520/smp4_mem14336_{default,hugepage,nohugepage}/
runs/lab/multicpu-20260520/smp8_mem16384_{default,hugepage,nohugepage}/
runs/lab/multicpu-20260520/smp16_mem32768_{default,hugepage,nohugepage}/
runs/lab/multicpu-20260520/logs/
```

## 关键页状态结果

`default` 和 `hugepage` 下，所有 CPU 配置都呈现同一个结构：

- `v6.12.77`：`THPeligible=1`，但实际 `AnonHugePages=0 kB`。
- `v6.19.9`：实际 `AnonHugePages=16384 kB`。
- `v6.19.9` 命中 `split_folio_to_list()` 16 次；`v6.12.77` 没有命中。

`nohugepage` 下，两个版本同状态：

- `v6.12.77` / `v6.19.9` 都是 `AnonHugePages=0 kB`、`THPeligible=0`。
- 两个版本都没有命中 `split_folio_to_list()`。
- old-faster 信号消失或变得不稳定，不支持原来的 same-state regression claim。

## 汇总表

`cycle_ns_per_page` 是 workload iteration wall-clock ns/page，不是 CPU cycles。
这些数字来自 tracing kernel 的短跑，只能辅助解释路径，不应用作 formal timing。

| CPU | mem MiB | mode | guest CPU seen | `v6.12` AHP / THPeligible | `v6.19` AHP / THPeligible | `split_folio_to_list` `v6.12/v6.19` | `advise_ns_per_page` `v6.12/v6.19` | `cycle_ns_per_page` `v6.12/v6.19` | `v6.19/v6.12` |
| ---: | ---: | --- | --- | --- | --- | --- | --- | --- | ---: |
| 2 | 14336 | default | 2 / 2 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2441 / 4394 | 2929 / 4883 | 1.67x |
| 2 | 14336 | hugepage | 2 / 2 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2441 / 4394 | 2441 / 4883 | 2.00x |
| 2 | 14336 | nohugepage | 2 / 2 | 0/0 / 0/0 | 0/0 / 0/0 | 0 / 0 | 2441 / 2929 | 2929 / 3906 | 1.33x |
| 4 | 14336 | default | 4 / 4 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 3906 / 7812 | 4394 / 7812 | 1.78x |
| 4 | 14336 | hugepage | 4 / 4 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2441 / 4394 | 2441 / 5371 | 2.20x |
| 4 | 14336 | nohugepage | 4 / 4 | 0/0 / 0/0 | 0/0 / 0/0 | 0 / 0 | 2441 / 2441 | 2441 / 2441 | 1.00x |
| 8 | 16384 | default | 8 / 8 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2929 / 5859 | 2929 / 5859 | 2.00x |
| 8 | 16384 | hugepage | 8 / 8 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2441 / 4883 | 2441 / 5859 | 2.40x |
| 8 | 16384 | nohugepage | 8 / 8 | 0/0 / 0/0 | 0/0 / 0/0 | 0 / 0 | 2441 / 1953 | 2441 / 2441 | 1.00x |
| 16 | 32768 | default | 16 / 16 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2929 / 4883 | 2929 / 5859 | 2.00x |
| 16 | 32768 | hugepage | 16 / 16 | 0/0 / 1/1 | 16384/16384 / 1/1 | 0 / 16 | 2929 / 5371 | 3418 / 5859 | 1.71x |
| 16 | 32768 | nohugepage | 16 / 16 | 0/0 / 0/0 | 0/0 / 0/0 | 0 / 0 | 2929 / 2441 | 2929 / 2441 | 0.83x |

## ftrace function profile 摘要

| CPU | mode | `reclaim_pages` total us `v6.12/v6.19` | `shrink_folio_list` total us `v6.12/v6.19` | `split_folio_to_list` total us `v6.12/v6.19` |
| ---: | --- | ---: | ---: | ---: |
| 2 | default | 10226.5 / 31726.8 | 5101.1 / 26359.3 | n/a / 21858.0 |
| 2 | hugepage | 10772.4 / 35078.5 | 5410.9 / 29161.0 | n/a / 24176.2 |
| 2 | nohugepage | 10200.3 / 15496.7 | 5086.0 / 6445.0 | n/a / n/a |
| 4 | default | 16060.5 / 56479.9 | 7748.4 / 48150.0 | n/a / 40765.9 |
| 4 | hugepage | 11685.3 / 33807.2 | 5747.6 / 27863.5 | n/a / 22700.2 |
| 4 | nohugepage | 11415.3 / 9980.3 | 6020.6 / 4111.8 | n/a / n/a |
| 8 | default | 11144.9 / 41063.2 | 5563.5 / 34274.9 | n/a / 28310.5 |
| 8 | hugepage | 10654.5 / 39826.8 | 5404.2 / 33099.2 | n/a / 27365.6 |
| 8 | nohugepage | 10598.3 / 10089.6 | 5202.2 / 4308.8 | n/a / n/a |
| 16 | default | 10441.7 / 39360.4 | 5119.9 / 33018.4 | n/a / 27642.3 |
| 16 | hugepage | 13480.6 / 38783.2 | 6953.1 / 32413.0 | n/a / 26662.7 |
| 16 | nohugepage | 11321.5 / 11185.1 | 5232.3 / 4374.9 | n/a / n/a |

## 当前解释

这轮多 CPU lab 结果强化了 1CPU attribution 的结论：

```text
原始 old-faster 信号主要对应 v6.19.9 实际 THP-backed 后在 no-swap
MADV_PAGEOUT reclaim 中进入 THP split/failure path；v6.12.77 在同一请求下
没有实际 THP backing。nohugepage 同状态对照没有稳定 old-faster。
```

因此，不应再把这组结果作为“同一 actual THP 状态下 v6.19 比 v6.12 慢”的
性能回归继续推进。更稳妥的上游 follow-up 是承认并修正原报告：

- 无 swap 场景不是实际 pageout/refault。
- `cycle_ns_per_page` 命名不够清楚，应解释为 wall-clock iteration ns/page。
- local + lab 都显示 `v6.12.77` 与 `v6.19.9` 的 actual THP backing 不一致。
- `nohugepage` same-state control 中没有稳定 old-faster。
- 如果 maintainer 仍认为有价值，可以转为讨论 no-swap THP reclaim split/failure path 是否能 fast-fail 或 skip split。

## 后续建议

当前最适合做的不是继续扩大 CPU 矩阵，而是整理一封谨慎的 follow-up 回复上游。
如果还想继续实验，优先级应是：

1. 做一个明确控制 actual THP backing 的 reproducer/配置，而不是只依赖 THPeligible。
2. 若要讨论优化，构造 no-swap THP-backed case，直接比较是否跳过 split 后能减少
   `shrink_folio_list()` / `split_folio_to_list()` 成本。
3. clean timing 重新命名或拆分指标，避免 `cycle_ns_per_page` 被误解成 CPU cycles。
