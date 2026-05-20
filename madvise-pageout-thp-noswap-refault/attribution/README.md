# MADV_PAGEOUT no-swap attribution index

This directory contains attribution material for the narrow
`MADV_PAGEOUT anon/THP no-swap reclaim-failure path`.

The kernels used here enable tracing/debugfs/function profiling. Treat these
results as mechanism evidence only, not as clean performance timing. Formal
timing remains under the workload's `formal-lab/` directory.

Current reading:

```text
The original old-faster signal is primarily tied to actual page-state
differences. v6.19.9 is actually THP-backed in the default/hugepage runs and
enters the no-swap THP split/failure path. v6.12.77 is not actually THP-backed
in the same requested mode. The nohugepage same-state control does not show a
stable old-faster signal.
```

## Layout

```text
summaries/
  lab-1cpu-20260520.md
  lab-1cpu-20260520.zh-CN.md
  lab-multicpu-followup-20260520.zh-CN.md
  local-ftrace-20260519.zh-CN.md
runs/
  local/
    ftrace-local-20260519T*/
  lab/
    1cpu-20260520/
    multicpu-20260520/
scripts/
  run_madvise_ftrace_*.sh
MOVED_PATHS.zh-CN.md
```

Start from `summaries/lab-1cpu-20260520.zh-CN.md` and then
`summaries/lab-multicpu-followup-20260520.zh-CN.md`.
