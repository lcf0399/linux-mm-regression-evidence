#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/workspace/kernel-study}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)_lab_mprotect_state_audit}"
CONFIGS="${CONFIGS:-1:14336 2:14336 4:14336 8:16384 16:32768}"
PROFILE="${PROFILE:-mm_regression_gen/mprotect/experiments/mprotect_shared_dirty_state_audit.toml}"
VERSION_FILE="${VERSION_FILE:-mm_regression_gen/out/kernel_versions_mprotect_mm_unstable.json}"
SEED="${SEED:-20260520}"
JOBS="${JOBS:-8}"
WORKLOAD_ROUNDS="${WORKLOAD_ROUNDS:-3}"
EXTRA_CMDLINE_VALUE="${MM_REGRESSION_EXTRA_CMDLINE:-tsc=unstable clocksource=refined-jiffies}"
EXTRA_CONFIG_ENABLE="${MM_REGRESSION_EXTRA_CONFIG_ENABLE:-SMP,ACPI,ACPI_PROCESSOR,PROC_PAGE_MONITOR}"
LOG_ROOT="${LOG_ROOT:-${SCRIPT_DIR}/lab-logs-${STAMP}}"

cd "${ROOT}"
mkdir -p "${LOG_ROOT}" "${SCRIPT_DIR}/experiments"
cp "${PROFILE}" "${SCRIPT_DIR}/experiments/" 2>/dev/null || true
cp "${VERSION_FILE}" "${SCRIPT_DIR}/experiments/" 2>/dev/null || true

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
    echo "root=${ROOT}"
    echo "stamp=${STAMP}"
    echo "configs=${CONFIGS}"
    echo "profile=${PROFILE}"
    echo "version_file=${VERSION_FILE}"
    echo "seed=${SEED}"
    echo "jobs=${JOBS}"
    echo "workload_rounds=${WORKLOAD_ROUNDS}"
    echo "extra_cmdline=${EXTRA_CMDLINE_VALUE}"
    echo "extra_config_enable=${EXTRA_CONFIG_ENABLE}"
    echo "cgroup_memory_limit_mib=${limit_mib}"
    echo "purpose=lab state-shape audit for mprotect shared-dirty workload"
} > "${LOG_ROOT}/launcher_env.txt"

if [[ ! -d linux-mm-unstable ]]; then
    {
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] missing linux-mm-unstable tree"
        echo "This launcher needs the akpm/mm mm-unstable tree referenced by ${VERSION_FILE}."
        echo "Skipping state audit rather than silently falling back."
    } | tee -a "${LOG_ROOT}/progress.log"
    exit 0
fi

for cfg in ${CONFIGS}; do
    cpu="${cfg%%:*}"
    mem="${cfg##*:}"
    pin="$(taskset_for_cpu "${cpu}")"
    out="${SCRIPT_DIR}/lab_${cpu}cpu_mem${mem}_${STAMP}"
    log_file="${LOG_ROOT}/lab_${cpu}cpu_mem${mem}.run.log"

    if (( limit_mib > 0 && mem + 512 > limit_mib )); then
        {
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] skip cpu=${cpu} mem=${mem}"
            echo "reason=requested guest memory plus reserve exceeds cgroup memory limit"
            echo "cgroup_memory_limit_mib=${limit_mib}"
        } | tee "${log_file}" | tee -a "${LOG_ROOT}/progress.log"
        continue
    fi

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] start mprotect state audit cpu=${cpu} mem=${mem} out=${out}" | tee -a "${LOG_ROOT}/progress.log"
    MM_REGRESSION_EXTRA_CONFIG_ENABLE="${EXTRA_CONFIG_ENABLE}" \
    MM_REGRESSION_EXTRA_CMDLINE="${EXTRA_CMDLINE_VALUE}" \
    QEMU_SMP="${cpu}" \
    QEMU_TASKSET="${pin}" \
    QEMU_MEM="${mem}" \
    QEMU_MEM_MB="${mem}" \
    WORKLOAD_EXTERNAL_ROUNDS="${WORKLOAD_ROUNDS}" \
    python3 mm_regression_gen/run_regression_pipeline.py "${PROFILE}" \
      --jobs "${JOBS}" \
      --disable-coverage \
      --execution-order interleaved \
      --execution-seed "${SEED}" \
      --version-file "${VERSION_FILE}" \
      --out-dir "${out}" \
      > "${log_file}" 2>&1
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] done mprotect state audit cpu=${cpu} mem=${mem}" | tee -a "${LOG_ROOT}/progress.log"
done

echo "finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG_ROOT}/progress.log"
