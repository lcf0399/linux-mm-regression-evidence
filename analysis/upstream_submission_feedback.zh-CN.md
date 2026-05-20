# 上游回归提交反馈与方法修正 - 2026-05-18

本文记录 2026-05-18 首次向 Linux MM 上游提交两条性能回归报告时遇到的问题、维护者反馈，以及对 `mm_regression_gen` 后续方法的修正。它和 `mm_regression_experiment_method.zh-CN.md` 同级，作为“实验方法到上游报告”的补充。

这次提交的两个报告是：

- `MADV_PAGEOUT` / THP / no-swap refault workflow。
- `mprotect` shared-dirty PTE toggle workflow。

公开 evidence repo：

```text
https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/e13469b
```

邮件草稿和后续回复草稿保存在：

```text
linux-mm-regression-mail-drafts-2026-05/
```

## 1. 提交过程踩坑

### 1.1 `git send-email` dry-run 不等于真实 SMTP 可用

本地 `git send-email --dry-run` 显示：

```text
Dry-OK
Result: OK
```

但真实发送时，学校邮箱 SMTP 在 `465 + SSL` 下失败：

```text
SSL connect attempt failed ... unexpected eof while reading
Unable to initialize SMTP properly ... encryption=ssl ... port=465
```

切到 `25 + no encryption` 后，自测邮件仍然失败：

```text
Unable to initialize SMTP properly ... encryption=none ... port=25
```

结论：

- `dry-run` 只能验证收件人解析、邮件格式和 send-email 参数，不代表 SMTP TLS/auth/投递链路真的可用。
- 当前 VM 到 `smtp.stu.xmu.edu.cn` 的 SMTP 会话初始化不稳定，真实发送不应继续硬试。
- 最终使用学校 Webmail 手动发送，正文按 `.eml` 纯文本复制。

后续方法修正：

- 上游提交前应先发一封自测邮件到自己邮箱，并确认实际收到。
- 如果 SMTP 失败，优先切 Webmail 纯文本发送，不要把时间消耗在 SMTP 环境排障上。
- Webmail 发送时要逐项复制 `To` / `Cc` / `Subject` / 正文，不要把邮件头混进正文。

### 1.2 邮件列表“召回”基本不可用

第二封 `mprotect` 邮件发送时标题曾误用或未及时修正。邮件列表场景下，Webmail 的“召回”不能作为可靠补救手段，因为：

- 邮件已经投递到多个个人邮箱和公开列表。
- lore / 列表归档可能已经收录。
- 收件人 MUA 不一定支持或尊重召回。

实际补救方式：

- 立刻对原线程 `reply-all` 发 correction。
- 用简短正文说明“上一封标题错误，正确标题是 ...”。
- 如果涉及 regzbot，使用 `#regzbot title:` 修正标题。

后续方法修正：

- 正式发送前必须预览标题，尤其是多封相似报告时。
- 两个问题必须新建两个独立邮件，不要做成 patch series，不要互相 reply。
- 如果标题错误，不要试图掩盖或重发整封；优先在原线程发 correction。

### 1.3 维护者邮箱会变化，不能只依赖旧输出

Lorenzo Stoakes 回复指出：

```text
Please use ljs@kernel.org. I switched over a while ago.
I tend to mark kernel mails that go to my work address read without reading them.
```

这说明即使收件人是通过 `get_maintainer.pl` 或旧文档得到的，也可能过期。

后续方法修正：

- 每次上游提交前，都应基于当前目标内核树重新运行 `scripts/get_maintainer.pl`。
- 对关键维护者，最好再查近期 lore 邮件里的常用地址。
- 如果维护者指出地址错误，后续 reply-all 应加新地址，必要时移除旧地址。
- 文档和脚本中的 maintainer 地址不要长期冻结为静态事实。

### 1.4 synthetic workload 的上游接受度有限

Lorenzo 进一步问：

```text
Is this really a regression you're seeing in real worklaods or synthetic?
```

这是非常关键的反馈。它说明上游维护者会首先判断：

- 是否来自真实应用或实际用户场景。
- 是否只是 synthetic / microbenchmark 信号。
- 这个信号是否值得作为 regression 处理。

本项目的 `mprotect` 报告应如实回答：

- 它是 source-calibrated synthetic userspace micro-workload。
- 不是生产应用中直接观察到的 regression。
- 它仍然是合法用户态行为，但不能等同于 real workload regression。

后续方法修正：

- 上游邮件必须明确 workload 类型：real application、source-calibrated synthetic、stress probe、attribution probe。
- synthetic-only 结果即使幅度大，也应降低措辞强度。
- 如果要提高上游处理优先级，应该补：
  - standalone reproducer；
  - commit-level bisect；
  - 或现实应用类比 / 真实 workload 复现。
- 不要把 synthetic micro-workload 包装成“实际生产 workload 回归”。

### 1.5 evidence bundle 不应上传调查历史全量

早期 evidence repo 包含 release-narrowing raw、旧交接稿等内容，后来收紧为：

- formal lab 9-repeat performance evidence；
- separate coverage evidence；
- formal profile；
- workload source；
- root README / workload README。

release narrowing 只保留为内部报告范围依据，不作为公开 evidence bundle 主体。

后续方法修正：

- GitHub evidence repo 应是“上游可读的精简证据包”，不是本地调查历史备份。
- release-level sanity check 可在邮件中描述，但没有 bisect 到具体 commit 时，不应喧宾夺主。
- 旧数据、失败数据、探索数据放本地 archive manifest，必要时再补给维护者。

## 2. 维护者反馈与含义

### 2.1 Lorenzo：邮箱错误与 synthetic 质询

Lorenzo 的反馈包含两层：

1. 邮件地址应更新到 `ljs@kernel.org`。
2. 询问 `mprotect` 信号是真实 workload 还是 synthetic。

方法含义：

- 上游报告的第一关不是数字，而是“这个 regression 对用户是否有实际意义”。
- 对 synthetic benchmark，必须主动说明边界，避免维护者觉得报告在夸大。
- 如果 synthetic 结果要继续推进，应补更小、更独立、更容易运行的 reproducer。

推荐回复口径：

```text
This is a synthetic/source-calibrated userspace micro-workload, not a
regression I observed in a production application.
```

然后说明：

- 它是从 `mm/mprotect.c` 路径校准出来的合法用户态模式。
- 当前 claim 只限于这个测试环境和 shared-dirty full-range PTE toggle path。
- 愿意继续补 standalone reproducer 或 bisect。

### 2.2 David：Pedro 的 mprotect optimization 可能已修复

David Hildenbrand 回复指出 Pedro 最近做过相关优化：

```text
https://lore.kernel.org/all/20260402141628.3367596-1-pfalcato@suse.de/
```

并问：

```text
Maybe that fixes most of the regression for you?
```

方法含义：

- 维护者会把报告和最新开发分支 / patch series 联系起来。
- 只比较 `v6.12.77` 和 `v6.19.9` 不够；如果上游已经有修复或优化，必须测试它。
- 对“已知有相关优化”的路径，后续重点不应继续争论旧版本差异，而应验证：
  - patch series 是否消除 delta；
  - 还剩多少回归；
  - 是否需要继续 bisect。

推荐回复口径：

```text
I tested the current akpm/mm mm-unstable branch at 444fc9435e57.
It suggests that the new work reduces this synthetic signal, but does not
remove it in this setup.
```

2026-05-18 本地先导补测结果：

- 分支：`akpm/mm.git` `mm-unstable`，commit `444fc9435e57157fcf30fc99aee44997f3458641`。
- 版本点：`v6.12.77`、`v6.19.9`、`mm-unstable`。
- 运行口径：local VM，`QEMU_SMP=1`，`QEMU_MEM_MB=6144`，SMP+ACPI config，cmdline 不含 `noapic`，clean timing only，coverage disabled，9 repeats，interleaved order，seed `20260518`。
- 结果目录：`mm_regression_gen/out/mprotect_mm_unstable_local_1cpu_20260518T171521Z`。

`cycle_ns_per_page` 聚合结果：

| kernel | mean | median | CV | 相对说明 |
| --- | ---: | ---: | ---: | --- |
| `v6.12.77` | 247.8 | 257.0 | 0.125 | 旧版本最快 |
| `v6.19.9` | 397.2 | 392.0 | 0.150 | 原报告中的慢版本 |
| `mm-unstable` | 350.9 | 342.0 | 0.154 | 比 `v6.19.9` 快约 11.7%，但仍比 `v6.12.77` 慢约 41.6% |

解释：

- `mm-unstable` 大约恢复了 `v6.12 -> v6.19` 差距的 31%，说明 Pedro 相关优化方向很可能确实减轻了这条 synthetic signal。
- 但本地 1CPU 这轮 `cycle_ns_per_page` 的 CV 在 `0.12-0.15`，框架没有把 comparison 标成 reliable，因此不能写成“已经修复”或“正式仍回归”。
- 对上游最稳的口径是：这是一个本地 sanity check，提示新优化降低但未完全消除该 synthetic signal；如果维护者认为值得继续，再补 lab matrix 或 standalone reproducer。

2026-05-20 lab 补测结果：

- 分支：`akpm/mm.git` `mm-unstable`，commit `444fc9435e57157fcf30fc99aee44997f3458641`。
- 版本点：`v6.12.77`、`v6.19.9`、`mm-unstable`。
- 运行口径：lab server，clean timing only，coverage disabled，9 repeats，interleaved order。
- 结果目录：`linux-mm-regression-evidence-2026-05/mprotect-shared-dirty-toggle/mm-unstable-lab-sanity/`。

`cycle_ns_per_page` 主结果：

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | gap closed |
|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 快约 6.6% | 约 17.9% |
| 2 | 369.2 | 581.9 | 503.3 | 快约 13.5% | 约 36.9% |
| 4 | 355.7 | 587.2 | 524.2 | 快约 10.7% | 约 27.2% |
| 8 | 369.7 | 583.6 | 534.2 | 快约 8.5% | 约 23.1% |
| 16 | 374.8 | 607.1 | 547.8 | 快约 9.8% | 约 25.5% |

新的上游回复口径应更新为：

```text
I tested current akpm/mm mm-unstable at 444fc9435e57 in the lab. It
reduces this synthetic shared-dirty signal compared with v6.19.9, but it
does not remove the gap to v6.12.77 in this workload. Looking at
cycle_ns_per_page, it closes roughly 18-37% of the v6.12->v6.19 gap in my
1/2/4/8 CPU runs.
```

这回答了 David 的“Pedro 的优化是否修掉大部分”的问题：**没有修掉大部分，但确实部分缓解**。

2026-05-20 另补 `mprotect` state-shape audit，目的是排除一个和
`MADV_PAGEOUT` 类似的风险：新老版本是否其实在操作不同的 page/VMA 状态。

结果目录：

```text
linux-mm-regression-evidence-2026-05/mprotect-shared-dirty-toggle/state-audit-lab/
```

审阅摘要：

```text
mprotect-shared-dirty-toggle/state-audit-lab/summary-20260520.zh-CN.md
```

结论：

- `1/2/4/8 CPU` 三个内核均完成 5/5。
- `16 CPU` 中 `v6.19.9` 有一次 QEMU failure，成功 run 仍同向。
- `v6.12.77`、`v6.19.9`、`mm-unstable` 的成功 run 均显示：
  - `expected_match_ratio=100`
  - `unexpected_results=0`
  - `final_vmas_avg=1`
  - protect 前后 `present_pages=16384`
  - `AnonHugePages=0`
  - `KernelPageSize/MMUPageSize=4 KiB`
  - `THPeligible=0`

这说明 `mprotect` 这条与 `MADV_PAGEOUT` 不同：目前没有看到“两个版本实际页状态不同导致比较失效”的迹象。上游回复里可以谨慎写成：

```text
I also ran a state-shape audit to avoid the MADV_PAGEOUT-style caveat.
The successful runs across v6.12.77, v6.19.9, and mm-unstable all used the
same 4 KiB shared-dirty PTE mapping shape.
```

### 2.3 `MADV_PAGEOUT` no-swap 报告：语义命名和路径证据不足

`MADV_PAGEOUT` 报告收到的关键反馈是：这个 workload 的原始表述容易让人误解。

维护者指出：

- 在没有配置 swap 的 guest 里，对 anon pages 做 `MADV_PAGEOUT`，页面实际上没有地方被 page out。
- 因此这不应被描述成真正的 `pageout/refault` 场景。
- 更准确的语义应是 `MADV_PAGEOUT` 触发的 anon/THP no-swap reclaim/swap-allocation-failure path。
- 后续 write-touch 不应直接称为 refault；在 no-swap 条件下，它可能只是 workload iteration 的一部分。
- `cycle_ns_per_page` 这个名字有歧义，`cycle` 容易被理解成 CPU cycles，但实际含义是“一次 workload iteration 的 wall-clock time，按 page 数归一化”。
- 目前公开 evidence repo 主要是 end-to-end timing，对内核开发者定位问题还不够。
- 后续更有用的是补 `perf` 或 `ftrace` breakdown，说明时间具体花在 `shrink_folio_list()`、`folio_alloc_swap()`、THP split、swap allocation failure path，还是其他路径上。

这条反馈非常重要，因为它说明上游首先会校验“实验语义是否真的等同于报告标题”。即使性能数字稳定，如果术语把路径讲过头，也会削弱报告可信度。

方法修正：

- 不要把 no-swap `MADV_PAGEOUT` workload 称为真实 pageout/refault，除非有 fault/major fault/minor fault 或页状态证据证明。
- 报告标题和正文应改成更窄的路径名，例如：

```text
MADV_PAGEOUT anon/THP no-swap reclaim failure path
```

- metric 命名应避免 `cycle` 这种容易和 CPU cycles 混淆的词。后续更推荐：

```text
iteration_ns_per_page
advise_ns_per_page
post_touch_ns_per_page
```

- 如果历史结果里仍保留 `cycle_ns_per_page`，邮件里必须解释：

```text
cycle_ns_per_page is wall-clock ns per page for one full workload
iteration; it is not CPU cycles.
```

- 上游报告前，至少为强 claim 准备一种路径分解证据：
  - `perf record/report` 或 `perf stat`；
  - function graph / function tracer；
  - tracepoint/kprobe breakdown；
  - 或明确的 kernel-side attribution profile。

本次推荐的短回复草稿：

```text
linux-mm-regression-mail-drafts-2026-05/0001-reply-to-madvise-noswap-clarification.md
linux-mm-regression-mail-drafts-2026-05/0001-reply-to-madvise-noswap-clarification.zh-CN.md
```

### 2.4 `MADV_PAGEOUT` no-swap 本地 ftrace 后续

2026-05-19 先在 local VM 上补了一轮短版 ftrace attribution。lab server
当时不可连，因此这轮只能作为本地路径线索。

结果目录：

```text
linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T095050Z/
```

运行口径：

- `v6.12.77` vs `v6.19.9`。
- local VM，`QEMU_SMP=1`，`QEMU_MEM_MB=6144`，`QEMU_TASKSET=0`。
- 单独复制 ftrace kernel tree，打开 tracing/debugfs/function profiler。
- 短版 workload，`external_rounds=1`，`internal_rounds=2`，无 warmup。

function profiler 摘要：

| function | v6.12 hits | v6.12 total | v6.19 hits | v6.19 total | total ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| `madvise_pageout` | 2 | 28532.90 us | 2 | 42283.58 us | 1.48x |
| `madvise_cold_or_pageout_pte_range` | 16 | 25044.30 us | 16 | 38857.46 us | 1.55x |
| `reclaim_pages` | 16 | 17571.56 us | 16 | 37579.90 us | 2.14x |
| `shrink_folio_list` | 16 | 11617.01 us | 16 | 32278.93 us | 2.78x |
| `split_folio_to_list` | 1 | 5125.348 us | 16 | 26716.56 us | 5.21x |

这轮结果支持维护者指出的方向：no-swap 条件下，问题不应继续表述成真实
pageout/refault，而应聚焦 `MADV_PAGEOUT` 进入 reclaim 后的 THP split /
swap-allocation-failure 相关路径。最强线索是 `v6.19.9` 中
`split_folio_to_list()` 在短跑里反复出现，而 `v6.12.77` 只出现一次。
这里的 `split_folio_to_list()` 总时间比值不能理解成单次调用变慢；单次平均值在
`v6.19.9` 更低，关键是 hit count 从 1 变成 16。

随后又做了一轮本地复跑：

```text
linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/runs/local/ftrace-local-20260519T_local_procfix/
```

这轮 `v6.19.9` 仍然 hit `split_folio_to_list()` 16 次，而 `v6.12.77` 没有在
function profile 中报告该函数。因此后续对上游更稳的说法是：两轮本地 ftrace
中，`v6.19.9` 都稳定反复进入 `split_folio_to_list()`，而 `v6.12.77` 是 0 或
1 次。

复跑也确认了 smaps 失败原因：不是 `/proc` 没挂载，而是 ftrace tree 没有打开
`CONFIG_PROC_PAGE_MONITOR`。后续如果需要页状态证据，需要启用该选项并重编重跑。

限制：

- 这是 local 1CPU ftrace，不是 lab formal timing。
- tracing kernel 的时间不能和 clean timing 直接混用。
- `folio_alloc_swap` 在本轮 ftrace filter 中不可见，尚不能直接计数。
- `--dump-smaps` 在 guest 里失败，后续如果要补页状态证据，需要修正采集方式。

给上游的更好后续口径是：

```text
I ran two local 1CPU ftrace attribution builds. In these short runs, v6.19
spends more time under reclaim_pages()/shrink_folio_list(), and
split_folio_to_list() is hit 16 times on v6.19 while v6.12 hits it zero or one
time. This supports your suspicion that the no-swap THP split path is the
interesting part of this workload. I am not treating this as clean timing
evidence; I will try to rerun the same breakdown on the lab machine when it is
available.
```

本地已准备更完整 follow-up 草稿：

```text
linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.md
linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.zh-CN.md
```

当前决策：**暂不发送这封 follow-up**。等 lab server 使用恢复后，先补 lab 上同口径
ftrace/路径分解，再把 local + lab 的 attribution 一起整理后回复。这样可以避免只拿
local-only tracing 结果继续占用上游时间。

## 3. 对实验方法的修正

### 3.1 上游报告前新增“upstream readiness”检查

每个准备上游报告的 old-faster candidate 应通过以下检查：

- 是否有 clean performance evidence。
- 是否有 coverage / direct-hit evidence，且与 performance 分开。
- 是否明确 workload 类型：real / synthetic / stress / attribution。
- 是否有 standalone reproducer；如果没有，是否在邮件里说清楚。
- 是否有 commit-level bisect；如果没有，是否只写 release range。
- 是否查过目标路径近期是否已有优化 patch。
- 是否检查过标题和正文是否过度声称了 workload 的实际语义。
- metric 名称是否会被误解；如果会，是否在正文中清楚解释。
- 是否有端到端 timing 之外的路径分解证据；如果没有，是否明确说后续会补。
- 是否重新跑过当前 `get_maintainer.pl`。
- 是否检查过维护者近期 lore 邮箱。
- 是否准备好 correction / follow-up 文本。

### 3.2 synthetic workload 的分级口径

后续报告建议按下面分级写：

| 类型 | 上游措辞 | 是否可称 regression |
| --- | --- | --- |
| 真实应用 workload | strongest | 可以直接称 userspace-visible regression |
| source-calibrated synthetic workload | medium | 可以报告，但必须限定范围 |
| adversarial/stress probe | weak | 更适合作为 candidate / probe |
| attribution-only probe | explanatory | 不应单独作为 regression report |

`mprotect shared-dirty toggle` 当前应归为：

```text
source-calibrated synthetic userspace micro-workload
```

`MADV_PAGEOUT THP/no-swap` 当前应降格表述为：

```text
MADV_PAGEOUT anon/THP no-swap reclaim failure path
```

它虽然有 standalone workload、路径更贴近用户态 syscall 行为、1/2/4 CPU formal matrix 更稳，报告强度高于 `mprotect`；但在没有 swap 的条件下，不应继续称为真实 `pageout/refault`，除非补充页状态或 fault 证据。

### 3.3 维护者反馈进入实验 backlog

上游反馈不应只停留在邮件里，必须进入本地实验 backlog。当前新增动作：

1. `mprotect`：测试 Pedro 的 `mprotect` optimization series。已完成 local + lab sanity，结论是部分缓解但未完全消除。
2. `mprotect`：准备 standalone shared-dirty toggle reproducer。仍未完成。
3. `mprotect`：如果 optimization 未完全修复，再做 commit-level bisect。仍未完成，可等维护者判断 synthetic signal 是否值得继续追。
4. `madvise`：先在本地和 lab 补 `perf` 或 `ftrace` breakdown，对比 `v6.12.77` 和 `v6.19.9` 的耗时路径。
5. `madvise`：等 lab attribution 完成后，再回复并修正 no-swap/pageout/refault 语义表述。
6. `madvise`：根据 breakdown 决定是否需要更小 reproducer、skip split/no-swap fast-fail 方向验证，或 commit-level bisect。
7. 所有后续邮件：使用更新后的 maintainer 地址。

## 4. 当前后续动作

### 4.1 立即回复 Lorenzo

目标：诚实说明 synthetic 属性，避免上游误解。

本地草稿：

```text
linux-mm-regression-mail-drafts-2026-05/0002-reply-to-lorenzo-synthetic-workload.md
```

要点：

- 道歉并更新邮箱地址。
- 承认是 synthetic/source-calibrated userspace micro-workload。
- 不声称真实应用已受影响。
- 表示愿意补 standalone reproducer / bisect。

### 4.2 回复 David

目标：给出已完成的 `mm-unstable` local + lab sanity 结果，并诚实说明它只是
synthetic workload。

本地草稿：

```text
linux-mm-regression-mail-drafts-2026-05/0002-reply-to-david-pedro-optimization.md
```

要点：

- 已测试包含 Pedro series 的 `akpm/mm mm-unstable`。
- lab 结果显示它相对 `v6.19.9` 快约 `6.6%` 到 `13.5%`。
- 按 `cycle_ns_per_page` 看，大约关闭了 `v6.12 -> v6.19` 差距的 `18%` 到 `37%`，不是“大部分”。
- 仍要说明这是 synthetic/source-calibrated workload，不是生产应用回归。
- 如维护者认为值得继续，再补 standalone reproducer 或 commit-level bisect。

### 4.3 `MADV_PAGEOUT` no-swap：先等 lab attribution，再回复

目标：承认原邮件表述不够准确，但不要急着只拿 local-only ftrace 回复。当前先保留
本地回复草稿，等 lab server 恢复后补同口径 lab ftrace/路径分解，再把 local + lab
结果一起发到原线程。

本地草稿：

```text
linux-mm-regression-mail-drafts-2026-05/0001-reply-to-madvise-noswap-clarification.md
linux-mm-regression-mail-drafts-2026-05/0001-reply-to-madvise-noswap-clarification.zh-CN.md
linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.md
linux-mm-regression-mail-drafts-2026-05/0001-followup-madvise-local-ftrace-attribution.zh-CN.md
```

要点：

- no-swap 条件下不应说成真实 pageout/refault。
- 更准确的名字是 `MADV_PAGEOUT anon/THP no-swap reclaim-failure path`。
- `cycle_ns_per_page` 是 workload iteration 的 wall-clock ns/page，不是 CPU cycles。
- 端到端 timing 不足以定位问题，需要补 `perf/ftrace`。
- local ftrace 已经显示 v6.19 反复进入 `split_folio_to_list()`，但暂不单独发送。
- 等 lab 同口径 attribution 完成后再回复，避免只拿 local-only tracing 结果占用上游时间。

### 4.4 不要再发新的完整报告

当前 `mprotect` thread 已经有维护者回复，后续应在同一 thread 中 reply-all，不应再新开完整报告。除非需要提供全新 reproducer 或完整 bisect 结果，也应优先作为 follow-up 发到原 thread。

## 5. 给后续提交的简短 checklist

提交前：

- 重新跑 `scripts/get_maintainer.pl`。
- 检查关键维护者最近 lore 地址。
- 标记 workload 类型。
- 检查是否已有相关 patch series。
- 准备中文审阅稿和英文纯文本稿。
- 先用 Webmail / SMTP 给自己发实际测试邮件。

发送时：

- 两个问题分两封独立邮件。
- 标题必须准确，带 `[REGRESSION]`。
- 标题不要把未证明的机制写死，例如 no-swap 场景不要写成已经 refault。
- 正文不要混入 `To/Cc/Subject` header。
- `#regzbot introduced:` 独立成段。
- 证据链接指向固定 commit。
- metric 如果有历史命名歧义，正文必须先定义。
- 端到端 timing 后面最好跟路径分解或明确说明会补路径分解。

发送后：

- 检查退信和 lore 归档。
- 如果标题错误，发 correction，不依赖召回。
- 如果维护者指出地址错误，立即更新后续 reply。
- 如果维护者质疑 synthetic，诚实承认并补强 evidence。
- 如果维护者指出可能修复 patch，优先验证 patch，而不是继续争论旧结果。
