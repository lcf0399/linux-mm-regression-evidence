# mprotect mm-unstable lab sanity - 2026-05-20

This run checks whether Pedro's small-folio `mprotect()` optimization in
`akpm/mm` `mm-unstable` mitigates the previously reported shared-dirty PTE
toggle synthetic signal.

This is a follow-up sanity check, not a replacement for the original formal
refresh evidence.

- kernels: `v6.12.77`, `v6.19.9`, `akpm/mm mm-unstable`
- `mm-unstable`: `7.1.0-rc3-mm-unstable-444fc9435e57`
- workload: `shared_dirty_full_toggle_64m`
- lab host label: `lcf`
- QEMU direct boot
- CPU/memory matrix:
  - `1/2/4 CPU` with `QEMU_MEM_MB=14336`
  - `8 CPU` with `QEMU_MEM_MB=16384`
  - `16 CPU` with `QEMU_MEM_MB=32768`
- repetitions: 9
- order: interleaved
- coverage: disabled

Raw result directories:

```text
lab_1cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_2cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_4cpu_mem14336_20260520T084427Z_lab_mprotect_mm_unstable/
lab_8cpu_mem16384_20260520T084427Z_lab_mprotect_mm_unstable/
lab_16cpu_mem32768_20260520T084427Z_lab_mprotect_mm_unstable/
lab-logs-20260520T084427Z_lab_mprotect_mm_unstable/
```

## Primary Result

Primary metric: `cycle_ns_per_page`, lower is better.

| CPU | v6.12.77 | v6.19.9 | mm-unstable | mm-unstable vs v6.19 | mm-unstable vs v6.12 | v6.12 vs v6.19 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 336.1 | 532.0 | 497.0 | 6.6% faster | still 47.9% slower | v6.12 36.8% faster |
| 2 | 369.2 | 581.9 | 503.3 | 13.5% faster | still 36.3% slower | v6.12 36.5% faster |
| 4 | 355.7 | 587.2 | 524.2 | 10.7% faster | still 47.4% slower | v6.12 39.4% faster |
| 8 | 369.7 | 583.6 | 534.2 | 8.5% faster | still 44.5% slower | v6.12 36.7% faster |
| 16 | 374.8 | 607.1 | 547.8 | 9.8% faster | still 46.2% slower | v6.12 38.3% faster |

## Reliability Notes

- `1/2/4/8 CPU` completed 9/9 runs for all three versions.
- In the `16 CPU` run, `v6.12.77` had one QEMU failure, so that row is only a
  supporting trend.
- `cycle_ns_per_page` is reliable/robust reliable for `mm-unstable` and `v6.19.9`
  in the `1/2/4 CPU` rows.
- The `8 CPU` `mm-unstable` `cycle_ns_per_page` row is robust-only.

## Conclusion

Pedro's small-folio `mprotect()` optimization helps this synthetic
shared-dirty PTE toggle signal. In this lab matrix, current `mm-unstable` is
about 6.6% to 13.5% faster than `v6.19.9`.

It does not remove the gap to `v6.12.77`: current `mm-unstable` remains about
36% to 48% slower than `v6.12.77` on this workload.
