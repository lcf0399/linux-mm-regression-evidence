#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_ROOT="${OUT_ROOT:-${SCRIPT_DIR}/ftrace-local-${STAMP}}"
JOBS="${JOBS:-8}"
QEMU_SMP="${QEMU_SMP:-1}"
QEMU_MEM_MB="${QEMU_MEM_MB:-6144}"
QEMU_TASKSET="${QEMU_TASKSET:-0}"
EXTRA_CMDLINE="${EXTRA_CMDLINE:-tsc=unstable clocksource=refined-jiffies}"
THP_MODE="${THP_MODE:-default}"
EFFECTIVE_CMDLINE="${EXTRA_CMDLINE} ptg_thp_mode=${THP_MODE}"
GUEST_SCRIPT="madvise_ftrace_guest.sh"

mkdir -p "${OUT_ROOT}"

prepare_ftrace_kernel() {
    local version_label="$1"
    local source_tree="$2"
    local ftrace_tree="$3"

    local required_symbols=(
        DEBUG_FS
        FTRACE
        FUNCTION_TRACER
        FUNCTION_GRAPH_TRACER
        FUNCTION_PROFILER
        KALLSYMS
        PROC_FS
        PROC_PAGE_MONITOR
    )

    local config_ready=1
    if [[ -f "${PROJECT_ROOT}/${ftrace_tree}/.config" ]]; then
        for symbol in "${required_symbols[@]}"; do
            if ! grep -q "^CONFIG_${symbol}=y$" "${PROJECT_ROOT}/${ftrace_tree}/.config"; then
                config_ready=0
                break
            fi
        done
    else
        config_ready=0
    fi

    if [[ -f "${PROJECT_ROOT}/${ftrace_tree}/arch/x86/boot/bzImage" && "${config_ready}" == "1" && "${FORCE_REBUILD:-0}" != "1" ]]; then
        echo "[ftrace] reuse ${ftrace_tree}/arch/x86/boot/bzImage"
        return
    fi

    if [[ ! -d "${PROJECT_ROOT}/${ftrace_tree}" || "${FORCE_RECOPY:-0}" == "1" ]]; then
        echo "[ftrace] copy ${source_tree} -> ${ftrace_tree}"
        rm -rf "${PROJECT_ROOT}/${ftrace_tree}"
        cp -a "${PROJECT_ROOT}/${source_tree}" "${PROJECT_ROOT}/${ftrace_tree}"
    fi

    echo "[ftrace] prepare ${version_label} in ${ftrace_tree}"
    for symbol in "${required_symbols[@]}"; do
        "${PROJECT_ROOT}/${ftrace_tree}/scripts/config" --file "${PROJECT_ROOT}/${ftrace_tree}/.config" --enable "${symbol}" || true
    done

    make -C "${PROJECT_ROOT}/${ftrace_tree}" olddefconfig
    make -C "${PROJECT_ROOT}/${ftrace_tree}" "-j${JOBS}" bzImage
}

install_guest_script() {
    cp "${SCRIPT_DIR}/run_madvise_ftrace_guest.sh" "${PROJECT_ROOT}/initramfs/${GUEST_SCRIPT}"
    chmod +x "${PROJECT_ROOT}/initramfs/${GUEST_SCRIPT}"
}

run_one() {
    local version_label="$1"
    local ftrace_tree="$2"
    local suite="madvise_ftrace_${version_label}_${STAMP}"
    local version_out="${OUT_ROOT}/${version_label}"

    mkdir -p "${version_out}"
    echo "[ftrace] run ${version_label}"
    (
        cd "${PROJECT_ROOT}"
        KERNEL_TREE="${ftrace_tree}" \
        SUITE_NAME="${suite}" \
        WORKLOAD_BIN="${GUEST_SCRIPT}" \
        THP_MODE="${THP_MODE}" \
        WORKLOAD_ARGS="" \
        WORKLOAD_PRIMARY_METRIC="cycle_ns_per_page" \
        AUTO_POWEROFF_ON_AUTORUN=1 \
        EXTRA_CMDLINE="${EFFECTIVE_CMDLINE}" \
        QEMU_SMP="${QEMU_SMP}" \
        QEMU_MEM_MB="${QEMU_MEM_MB}" \
        QEMU_TASKSET="${QEMU_TASKSET}" \
        ./run_qemu_bitmap_bench.sh
    )

    local serial
    serial="$(ls -t "${PROJECT_ROOT}/out/qemu-logs/${suite}"-bench-*.serial.log | head -n 1)"
    cp "${serial}" "${version_out}/serial.log"
    if compgen -G "${PROJECT_ROOT}/out/workload-results/${suite}"'*' > /dev/null; then
        cp "${PROJECT_ROOT}/out/workload-results/${suite}"* "${version_out}/"
    fi
}

cat > "${OUT_ROOT}/run_env.txt" <<EOF
stamp=${STAMP}
project_root=${PROJECT_ROOT}
jobs=${JOBS}
qemu_smp=${QEMU_SMP}
qemu_mem_mb=${QEMU_MEM_MB}
qemu_taskset=${QEMU_TASKSET}
extra_cmdline=${EXTRA_CMDLINE}
effective_cmdline=${EFFECTIVE_CMDLINE}
thp_mode=${THP_MODE}
purpose=madvise ftrace attribution, not clean performance timing
EOF

install_guest_script
prepare_ftrace_kernel "v6_12" "linux-v6.12" "linux-v6.12-ftrace-tree"
prepare_ftrace_kernel "v6_19" "linux-v6.19" "linux-v6.19-ftrace-tree"
run_one "v6_12" "linux-v6.12-ftrace-tree"
run_one "v6_19" "linux-v6.19-ftrace-tree"

echo "[ftrace] results: ${OUT_ROOT}"
