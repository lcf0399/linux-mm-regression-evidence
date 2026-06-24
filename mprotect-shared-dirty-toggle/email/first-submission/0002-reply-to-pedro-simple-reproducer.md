# Reply draft to Pedro with simpler mprotect reproducer

> Use reply-all on Pedro's email and keep the same thread. Evidence links are pinned to commit `aec9695`.

Suggested subject:

```text
Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
```

Suggested body:

```text
Hi Pedro,

Thanks. I prepared a smaller standalone reproducer for the shared-dirty case:

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/reproducer

It is distilled from the `shared_dirty_full_toggle_64m` scenario in the
generated workload I used for the earlier QEMU/lab runs. It keeps only the
core operation:

  - MAP_SHARED | MAP_ANONYMOUS mapping
  - write-prefault the whole range
  - full-range mprotect(PROT_READ)
  - restore with mprotect(PROT_READ | PROT_WRITE)
  - write-touch after each protection cycle

The core loop is essentially:

  p = mmap(..., MAP_SHARED | MAP_ANONYMOUS, ...);
  write_touch(p, len);
  for (...) {
          mprotect(p, len, PROT_READ);
          mprotect(p, len, PROT_READ | PROT_WRITE);
          write_touch(p, len);
  }

Build/run:

  gcc -O2 -Wall -Wextra -o mprotect_shared_dirty_reproducer \
    mprotect_shared_dirty_reproducer.c

  ./mprotect_shared_dirty_reproducer \
    shared_dirty_full_toggle_64m 5 \
    --mapping-mb 64 \
    --iterations 200 \
    --warmup 5

The main metric is `iteration_ns_per_page`, lower is better. It is
wall-clock nanoseconds per base page for one full
protect/restore/post-touch iteration. The program also prints
`protect_ns_per_page` and `restore_ns_per_page` separately.

I rebuilt the QEMU direct-boot kernels with an SMP-capable config and reran the
standalone reproducer on the lab machine:

  kernels: v6.12.77, v6.19.9, akpm/mm mm-unstable 444fc9435e57
  kernel config additions: CONFIG_SMP=y, CONFIG_NR_CPUS=16,
                           CONFIG_ACPI=y, CONFIG_ACPI_PROCESSOR=y
  QEMU_SMP: 1/2/4/8/16
  guest memory: 14336 MiB for 1/2/4 CPU, 16384 MiB for 8 CPU,
                32768 MiB for 16 CPU
  repetitions: 5
  order: interleaved
  coverage: disabled
  extra cmdline: tsc=unstable clocksource=refined-jiffies

I also checked the serial logs. The 1/2/4/8 CPU rows each had 15 serial logs
checked. The 16 CPU full-matrix row had one v6.12.77 QEMU failure, but a
targeted 16 CPU rerun completed cleanly with 15/15 serial logs checked. All
checked logs matched the requested guest CPU count, and none had `noapic` in
the guest cmdline.

`iteration_ns_per_page` results:

  CPU   v6.12.77   v6.19.9   mm-unstable   mm-unstable vs v6.19   gap closed
    1      296.4     548.6       498.6          9.1% faster          19.8%
    2      327.2     564.8       488.4         13.5% faster          32.2%
    4      319.8     578.2       505.8         12.5% faster          28.0%
    8      336.4     570.4       508.2         10.9% faster          26.6%
   16      380.0     624.0       553.8         11.3% faster          28.8%

The 1/2/4/8 CPU rows are clean screening rows. I would treat 16 CPU as
extended/supporting only because it uses the larger 32 GiB guest-memory setting;
the earlier v6.12.77 QEMU failure appears transient after the clean rerun.

So the standalone reproducer keeps the same broad direction: v6.19.9 is slower
than v6.12.77, and current mm-unstable improves the result but does not return
it to the v6.12.77 level in this setup. The per-phase metrics still put most of
the gap in the protect/restore mprotect phases rather than the post-touch phase.

The lab validation summary is here:

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/reproducer-validation

One caveat: the standalone run does not collect the same detailed
smaps/pagemap state-shape audit as my separate state-audit run, so I would
treat this as a reproducer/timing screening check. The earlier state audit for
the same workload shape is here:

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/tree/aec9695/mprotect-shared-dirty-toggle/state-audit-lab

For reference, the original generated workload source and formal profile are:

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/blob/aec9695/mprotect-shared-dirty-toggle/workload/mprotect_paths_storm.c

  https://github.com/lcf0399/linux-mm-regression-evidence-2026-05/blob/aec9695/mprotect-shared-dirty-toggle/experiments/mprotect_shared_dirty_formal_refresh.toml

I can try a narrower bisect next if this reproducer shape is useful.

Thanks,
Chengfeng
```
