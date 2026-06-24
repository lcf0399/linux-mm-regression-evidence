# 给 Pedro 的回复草稿：提供更小 mprotect reproducer

> 用法：对 Pedro 的邮件 reply-all，保持同一个 thread。证据链接已经固定到
> commit `aec9695`。

建议主题：

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

建议正文含义：

```text
Hi Pedro,

谢谢。我准备了一个更小的 standalone reproducer，针对同一个 shared-dirty case：

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/reproducer

它是从我之前 QEMU/lab runs 使用的 generated workload 里的
`shared_dirty_full_toggle_64m` scenario 抽出来的，只保留核心操作：

  - MAP_SHARED | MAP_ANONYMOUS mapping
  - 先 write-prefault 整个 range
  - full-range mprotect(PROT_READ)
  - 再恢复成 mprotect(PROT_READ | PROT_WRITE)
  - 每轮 protection cycle 后 write-touch

核心 loop 基本就是：

  p = mmap(..., MAP_SHARED | MAP_ANONYMOUS, ...);
  write_touch(p, len);
  for (...) {
          mprotect(p, len, PROT_READ);
          mprotect(p, len, PROT_READ | PROT_WRITE);
          write_touch(p, len);
  }

编译和运行：

  gcc -O2 -Wall -Wextra -o mprotect_shared_dirty_reproducer \
    mprotect_shared_dirty_reproducer.c

  ./mprotect_shared_dirty_reproducer \
    shared_dirty_full_toggle_64m 5 \
    --mapping-mb 64 \
    --iterations 200 \
    --warmup 5

主要指标是 `iteration_ns_per_page`，越低越好。它表示一次完整
protect/restore/post-touch iteration 的每个 base page wall-clock 纳秒数。
程序也会分别打印 `protect_ns_per_page` 和 `restore_ns_per_page`。

我把 QEMU direct-boot kernels 重编成支持 SMP 的配置，并在 lab 机器上重跑了
standalone reproducer：

  kernels: v6.12.77, v6.19.9, akpm/mm mm-unstable 444fc9435e57
  kernel config additions: CONFIG_SMP=y, CONFIG_NR_CPUS=16,
                           CONFIG_ACPI=y, CONFIG_ACPI_PROCESSOR=y
  QEMU_SMP: 1/2/4/8/16
  guest memory: 1/2/4 CPU 为 14336 MiB，8 CPU 为 16384 MiB，
                16 CPU 为 32768 MiB
  repetitions: 5
  order: interleaved
  coverage: disabled
  extra cmdline: tsc=unstable clocksource=refined-jiffies

我也检查了 serial logs。1/2/4/8 CPU 行每行检查了 15 个 serial logs。完整
matrix 里的 16 CPU 行有一次 v6.12.77 QEMU failure，但单独 16 CPU rerun 已干净
完成，并检查了 15/15 个 serial logs。所有已检查 logs 都匹配 requested guest
CPU count，并且 guest cmdline 中没有 `noapic`。

`iteration_ns_per_page` results：

  CPU   v6.12.77   v6.19.9   mm-unstable   mm-unstable vs v6.19   gap closed
    1      296.4     548.6       498.6          9.1% faster          19.8%
    2      327.2     564.8       488.4         13.5% faster          32.2%
    4      319.8     578.2       505.8         12.5% faster          28.0%
    8      336.4     570.4       508.2         10.9% faster          26.6%
   16      380.0     624.0       553.8         11.3% faster          28.8%

1/2/4/8 CPU 行是干净的 screening rows。16 CPU 因为使用更大的 32 GiB guest
memory，我只把它当作 extended/supporting row；前面的 v6.12.77 QEMU failure 在
干净 rerun 后看起来更像偶发问题。

所以这个 standalone reproducer 保持了同样的大方向：v6.19.9 慢于 v6.12.77，
当前 mm-unstable 有改善，但在这个环境里还没有回到 v6.12.77 水平。
per-phase metrics 仍显示 gap 主要在 protect/restore mprotect phases，而不是
post-touch phase。

lab validation summary 在这里：

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/reproducer-validation

一个 caveat：这个 standalone run 没有像单独 state-audit run 那样收集同等详细的
smaps/pagemap state-shape audit，所以我会把这轮当作 reproducer/timing screening
check。相同 workload shape 的前一轮 state audit 在这里：

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/state-audit-lab

作为参考，原来的 generated workload source 和 formal profile 是：

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/blob/aec9695/mprotect-shared-dirty-toggle/workload/mprotect_paths_storm.c

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/blob/aec9695/mprotect-shared-dirty-toggle/experiments/mprotect_shared_dirty_formal_refresh.toml

如果这个 reproducer 形态有用，我下一步可以尝试更窄的 bisect。

Thanks,
Chengfeng
```
