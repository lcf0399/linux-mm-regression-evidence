#!/bin/sh
set -eu

WORKLOAD=${WORKLOAD:-/mmreg_madvise_pageout_reproducer}
TRACE=${TRACE:-/sys/kernel/tracing}
THP_MODE=${THP_MODE:-default}

mkdir -p /proc /sys
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true

echo "PTG_FTRACE_GUEST_BEGIN"
echo "kernel=$(uname -a)"
CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
CMDLINE_THP_MODE="$(printf '%s\n' "$CMDLINE" | sed -n 's/.*ptg_thp_mode=\([^ ]*\).*/\1/p')"
if [ -n "$CMDLINE_THP_MODE" ]; then
    THP_MODE="$CMDLINE_THP_MODE"
fi
echo "cmdline=$CMDLINE"
echo "thp_mode=$THP_MODE"

mkdir -p /sys/kernel/tracing /sys/kernel/debug
mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true
if [ ! -f "$TRACE/current_tracer" ]; then
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    TRACE=/sys/kernel/debug/tracing
fi

if [ ! -f "$TRACE/current_tracer" ]; then
    echo "PTG_FTRACE_UNAVAILABLE tracefs_not_available"
    "$WORKLOAD" pageout_refault_anon_16m --external-rounds 1 --rounds 2 --max-rounds 2 --warmup-rounds 0 --min-ms 0
    echo "PTG_FTRACE_GUEST_END"
    exit 0
fi

echo "tracefs=$TRACE"
echo 0 > "$TRACE/tracing_on" 2>/dev/null || true
echo 0 > "$TRACE/function_profile_enabled" 2>/dev/null || true
echo nop > "$TRACE/current_tracer" 2>/dev/null || true
: > "$TRACE/trace" 2>/dev/null || true
: > "$TRACE/set_ftrace_filter" 2>/dev/null || true

FUNCTIONS="
madvise_pageout
madvise_cold_or_pageout_pte_range
reclaim_pages
shrink_folio_list
folio_alloc_swap
split_folio_to_list
try_to_unmap
folio_try_to_unmap
add_to_swap
"

echo "PTG_FTRACE_FILTER_BEGIN"
for fn in $FUNCTIONS; do
    if grep -w "$fn" "$TRACE/available_filter_functions" >/dev/null 2>&1; then
        echo "$fn" >> "$TRACE/set_ftrace_filter"
        echo "add $fn"
    else
        echo "missing $fn"
    fi
done
echo "PTG_FTRACE_FILTER_END"

if [ -f "$TRACE/current_tracer" ]; then
    echo function > "$TRACE/current_tracer" 2>/dev/null || true
fi

if [ -f "$TRACE/function_profile_enabled" ]; then
    echo 1 > "$TRACE/function_profile_enabled" 2>/dev/null || true
    echo "function_profile_enabled=1"
else
    echo "function_profile_enabled=missing"
fi

echo 1 > "$TRACE/tracing_on" 2>/dev/null || true

echo "PTG_WORKLOAD_BEGIN"
"$WORKLOAD" pageout_refault_anon_16m --external-rounds 1 --rounds 2 --max-rounds 2 --warmup-rounds 0 --min-ms 0 --dump-smaps --thp "$THP_MODE"
workload_status=$?
echo "PTG_WORKLOAD_STATUS=$workload_status"
echo "PTG_WORKLOAD_END"

echo 0 > "$TRACE/tracing_on" 2>/dev/null || true
echo 0 > "$TRACE/function_profile_enabled" 2>/dev/null || true

echo "PTG_FTRACE_PROFILE_BEGIN"
for profile in "$TRACE"/trace_stat/function*; do
    [ -f "$profile" ] || continue
    echo "PTG_FTRACE_PROFILE_FILE $(basename "$profile")"
    cat "$profile"
done
echo "PTG_FTRACE_PROFILE_END"

echo "PTG_FTRACE_TRACE_HEAD_BEGIN"
sed -n '1,200p' "$TRACE/trace" 2>/dev/null || true
echo "PTG_FTRACE_TRACE_HEAD_END"

echo nop > "$TRACE/current_tracer" 2>/dev/null || true
: > "$TRACE/set_ftrace_filter" 2>/dev/null || true
echo "PTG_FTRACE_GUEST_END"
exit "$workload_status"
