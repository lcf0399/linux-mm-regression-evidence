# mprotect mm-unstable Local Sanity Check

This directory records a local sanity check against akpm/mm `mm-unstable`
commit `444fc9435e57157fcf30fc99aee44997f3458641`.

It exists because upstream feedback pointed to Pedro Falcato's recent
small-folio `mprotect()` optimization series. That patchset is directly
relevant to the earlier `nr_ptes == 1` hypothesis for the shared-dirty PTE
toggle workload.

This is not formal lab evidence. The lab server was unavailable when this was
collected, and local `mprotect` timing is noisier than the lab matrix. Treat
these files as follow-up analysis material only.

## Layout

- `experiments/`: the local profile and kernel-version mapping used for this
  sanity check.
- `local_1cpu/`: local clean timing result with `QEMU_SMP=1`.
- `local_2cpu/`: local clean timing result with `QEMU_SMP=2`.
- `local_4cpu/`: local clean timing result with `QEMU_SMP=4`.

## Current Reading

The local sanity check suggests that the `mm-unstable` optimization reduces the
synthetic shared-dirty signal relative to `v6.19.9`, but does not bring the
numbers back to `v6.12.77`.

Because this run is local and noisy, it should be described as:

```text
Pedro's small-folio mprotect optimization is directly relevant to the
nr_ptes == 1 hypothesis. In my local sanity check it reduces the synthetic
shared-dirty signal, but does not remove it. The local run is noisy, so I would
not present it as formal evidence until the lab matrix can be rerun.
```
