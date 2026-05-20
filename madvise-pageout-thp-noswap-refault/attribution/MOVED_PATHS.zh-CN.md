# MADV_PAGEOUT attribution 目录迁移索引

2026-05-20 为了降低目录噪音，`attribution/` 下的原始 run 已按类型收纳。
旧路径没有删除证据，只是移动到了下面的新位置。

## 脚本

| 旧位置 | 新位置 |
| --- | --- |
| `run_madvise_ftrace_guest.sh` | `scripts/run_madvise_ftrace_guest.sh` |
| `run_madvise_ftrace_local.sh` | `scripts/run_madvise_ftrace_local.sh` |
| `run_madvise_ftrace_lab_matrix.sh` | `scripts/run_madvise_ftrace_lab_matrix.sh` |
| `run_madvise_ftrace_lab_cpu_mem_matrix.sh` | `scripts/run_madvise_ftrace_lab_cpu_mem_matrix.sh` |

## 本地探索 run

| 旧位置 | 新位置 |
| --- | --- |
| `ftrace-local-20260519T095050Z/` | `runs/local/ftrace-local-20260519T095050Z/` |
| `ftrace-local-20260519T_local_procfix/` | `runs/local/ftrace-local-20260519T_local_procfix/` |
| `ftrace-local-20260519T_procpage/` | `runs/local/ftrace-local-20260519T_procpage/` |
| `ftrace-local-20260519T_hugepage2/` | `runs/local/ftrace-local-20260519T_hugepage2/` |
| `ftrace-local-20260519T_nohugepage/` | `runs/local/ftrace-local-20260519T_nohugepage/` |

## lab 1CPU run

| 旧位置 | 新位置 |
| --- | --- |
| `ftrace-lab-20260520T062622Z_lab_madvise_default/` | `runs/lab/1cpu-20260520/default/` |
| `ftrace-lab-20260520T062622Z_lab_madvise_hugepage/` | `runs/lab/1cpu-20260520/hugepage/` |
| `ftrace-lab-20260520T062622Z_lab_madvise_nohugepage/` | `runs/lab/1cpu-20260520/nohugepage/` |
| `lab-logs-20260520T062622Z_lab_madvise/` | `runs/lab/1cpu-20260520/logs/` |
| `lab-launch-20260520T062622Z_lab_madvise.log` | `runs/lab/1cpu-20260520/lab-launch-20260520T062622Z_lab_madvise.log` |
| `lab-logs-20260520T062622Z_lab_madvise/SUMMARY.zh-CN.md` | `summaries/lab-1cpu-20260520.zh-CN.md` |
| `lab-logs-20260520T062622Z_lab_madvise/SUMMARY.md` | `summaries/lab-1cpu-20260520.md` |

## lab 多 CPU run

| 旧模式 | 新模式 |
| --- | --- |
| `ftrace-lab-20260520T080847Z_lab_followup_madvise_smp*_mem*_<mode>/` | `runs/lab/multicpu-20260520/smp*_mem*_<mode>/` |
| `ftrace-lab-20260520T081655Z_lab_madvise_large_smp*_mem*_<mode>/` | `runs/lab/multicpu-20260520/smp*_mem*_<mode>/` |
| `lab-logs-20260520T080847Z_lab_followup_madvise*/` | `runs/lab/multicpu-20260520/logs/` |
| `lab-logs-20260520T081655Z_lab_madvise_large*/` | `runs/lab/multicpu-20260520/logs/` |
| `lab-multicpu-followup-20260520.zh-CN.md` | `summaries/lab-multicpu-followup-20260520.zh-CN.md` |
