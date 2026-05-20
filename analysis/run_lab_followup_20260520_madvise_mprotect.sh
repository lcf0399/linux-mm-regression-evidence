#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/workspace/kernel-study}"
STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)_lab_followup}"
BASE="${ROOT}/linux-mm-regression-evidence-2026-05/analysis/lab-followup-${STAMP}"
MATRIX_CONFIGS="${MATRIX_CONFIGS:-2:14336 4:14336 8:16384 16:32768}"
MPROTECT_CONFIGS="${MPROTECT_CONFIGS:-1:14336 2:14336 4:14336 8:16384 16:32768}"
MODES="${MODES:-default hugepage nohugepage}"
JOBS="${JOBS:-8}"

mkdir -p "${BASE}"

{
    echo "started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "root=${ROOT}"
    echo "stamp=${STAMP}"
    echo "madvise_configs=${MATRIX_CONFIGS}"
    echo "mprotect_configs=${MPROTECT_CONFIGS}"
    echo "madvise_modes=${MODES}"
    echo "jobs=${JOBS}"
    echo "purpose=sequential lab follow-up: madvise ftrace CPU/memory matrix, then mprotect mm-unstable clean timing matrix"
    echo "note=large 8/16 CPU configs are conditional on cgroup memory capacity inside their child launchers"
    echo
    echo "=== uptime ==="
    uptime || true
    echo
    echo "=== cgroup memory ==="
    cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true
} > "${BASE}/launcher_env.txt"

run_step() {
    local name="$1"
    shift
    local log="${BASE}/${name}.log"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] start ${name}" | tee -a "${BASE}/progress.log"
    "$@" > "${log}" 2>&1
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] done ${name}" | tee -a "${BASE}/progress.log"
}

cd "${ROOT}"

run_step "madvise_cpumem" \
    env STAMP_BASE="${STAMP}_madvise" \
        CONFIGS="${MATRIX_CONFIGS}" \
        MODES="${MODES}" \
        JOBS="${JOBS}" \
        "${ROOT}/linux-mm-regression-evidence-2026-05/madvise-pageout-thp-noswap-refault/attribution/run_madvise_ftrace_lab_cpu_mem_matrix.sh"

run_step "mprotect_mm_unstable" \
    env STAMP="${STAMP}_mprotect" \
        CONFIGS="${MPROTECT_CONFIGS}" \
        JOBS="${JOBS}" \
        "${ROOT}/linux-mm-regression-evidence-2026-05/mprotect-shared-dirty-toggle/mm-unstable-lab-sanity/run_mprotect_mm_unstable_lab_matrix.sh"

echo "finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${BASE}/progress.log"
