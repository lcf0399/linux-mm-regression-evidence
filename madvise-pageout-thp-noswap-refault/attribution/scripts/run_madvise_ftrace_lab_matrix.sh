#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
STAMP_BASE="${STAMP_BASE:-$(date -u +%Y%m%dT%H%M%SZ)}"
MODES="${MODES:-default hugepage nohugepage}"
JOBS="${JOBS:-8}"
QEMU_SMP="${QEMU_SMP:-1}"
QEMU_MEM_MB="${QEMU_MEM_MB:-14336}"
QEMU_TASKSET="${QEMU_TASKSET:-0,2,4,6,8,10,12,14}"
EXTRA_CMDLINE="${EXTRA_CMDLINE:-tsc=unstable clocksource=refined-jiffies}"
LOG_ROOT="${LOG_ROOT:-${SCRIPT_DIR}/lab-logs-${STAMP_BASE}}"

mkdir -p "${LOG_ROOT}"

cat > "${LOG_ROOT}/launcher_env.txt" <<EOF
stamp_base=${STAMP_BASE}
project_root=${PROJECT_ROOT}
jobs=${JOBS}
qemu_smp=${QEMU_SMP}
qemu_mem_mb=${QEMU_MEM_MB}
qemu_taskset=${QEMU_TASKSET}
extra_cmdline=${EXTRA_CMDLINE}
modes=${MODES}
purpose=lab madvise ftrace/smaps attribution matrix, not clean performance timing
EOF

for mode in ${MODES}; do
    stamp="${STAMP_BASE}_${mode}"
    out_root="${SCRIPT_DIR}/ftrace-lab-${stamp}"
    log_file="${LOG_ROOT}/${mode}.log"
    echo "[lab] start mode=${mode} out=${out_root} log=${log_file}"
    STAMP="${stamp}" \
    OUT_ROOT="${out_root}" \
    THP_MODE="${mode}" \
    JOBS="${JOBS}" \
    QEMU_SMP="${QEMU_SMP}" \
    QEMU_MEM_MB="${QEMU_MEM_MB}" \
    QEMU_TASKSET="${QEMU_TASKSET}" \
    EXTRA_CMDLINE="${EXTRA_CMDLINE}" \
        "${SCRIPT_DIR}/run_madvise_ftrace_local.sh" > "${log_file}" 2>&1
    echo "[lab] done mode=${mode}"
done

echo "[lab] all done: ${LOG_ROOT}"
