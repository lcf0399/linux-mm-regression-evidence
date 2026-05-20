#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP_BASE="${STAMP_BASE:-$(date -u +%Y%m%dT%H%M%SZ)_lab_madvise_cpumem}"
CONFIGS="${CONFIGS:-2:14336 4:14336 8:16384 16:32768}"
MODES="${MODES:-default hugepage nohugepage}"
JOBS="${JOBS:-8}"
EXTRA_CMDLINE="${EXTRA_CMDLINE:-tsc=unstable clocksource=refined-jiffies}"
LOG_ROOT="${LOG_ROOT:-${SCRIPT_DIR}/lab-logs-${STAMP_BASE}}"

mkdir -p "${LOG_ROOT}"

memory_limit_mib() {
    local raw
    if [[ -f /sys/fs/cgroup/memory.max ]]; then
        raw="$(cat /sys/fs/cgroup/memory.max)"
        if [[ "${raw}" == "max" ]]; then
            echo 0
        else
            echo $((raw / 1024 / 1024))
        fi
        return
    fi
    if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        raw="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
        if (( raw > 9000000000000000000 )); then
            echo 0
        else
            echo $((raw / 1024 / 1024))
        fi
        return
    fi
    echo 0
}

taskset_for_cpu() {
    local cpu="$1"
    if (( cpu <= 1 )); then
        echo "0"
    elif (( cpu <= 2 )); then
        echo "0,2"
    elif (( cpu <= 4 )); then
        echo "0,2,4,6"
    elif (( cpu <= 8 )); then
        echo "0,2,4,6,8,10,12,14"
    else
        echo "0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30"
    fi
}

limit_mib="$(memory_limit_mib)"
{
    echo "started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "stamp_base=${STAMP_BASE}"
    echo "script_dir=${SCRIPT_DIR}"
    echo "configs=${CONFIGS}"
    echo "modes=${MODES}"
    echo "jobs=${JOBS}"
    echo "extra_cmdline=${EXTRA_CMDLINE}"
    echo "cgroup_memory_limit_mib=${limit_mib}"
    echo "purpose=lab madvise ftrace/smaps CPU+memory matrix, attribution only"
    echo "note=8:16384 and 16:32768 are skipped automatically if cgroup memory is too small"
} > "${LOG_ROOT}/launcher_env.txt"

for cfg in ${CONFIGS}; do
    cpu="${cfg%%:*}"
    mem="${cfg##*:}"
    pin="$(taskset_for_cpu "${cpu}")"
    stamp="${STAMP_BASE}_smp${cpu}_mem${mem}"
    log_file="${LOG_ROOT}/smp${cpu}_mem${mem}.log"

    if (( limit_mib > 0 && mem + 512 > limit_mib )); then
        {
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] skip smp=${cpu} mem=${mem}"
            echo "reason=requested guest memory plus reserve exceeds cgroup memory limit"
            echo "cgroup_memory_limit_mib=${limit_mib}"
        } | tee "${log_file}"
        continue
    fi

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] start madvise smp=${cpu} mem=${mem} modes=${MODES}" | tee -a "${LOG_ROOT}/progress.log"
    STAMP_BASE="${stamp}" \
    MODES="${MODES}" \
    JOBS="${JOBS}" \
    QEMU_SMP="${cpu}" \
    QEMU_MEM_MB="${mem}" \
    QEMU_TASKSET="${pin}" \
    EXTRA_CMDLINE="${EXTRA_CMDLINE}" \
        "${SCRIPT_DIR}/run_madvise_ftrace_lab_matrix.sh" > "${log_file}" 2>&1
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] done madvise smp=${cpu} mem=${mem}" | tee -a "${LOG_ROOT}/progress.log"
done

echo "finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG_ROOT}/progress.log"
