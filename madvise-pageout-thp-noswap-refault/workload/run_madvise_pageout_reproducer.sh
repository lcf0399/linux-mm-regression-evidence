#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-cc}
CFLAGS=${CFLAGS:-"-O2 -Wall -Wextra -std=c11"}
OUT_DIR=${OUT_DIR:-"$SCRIPT_DIR/out"}
REPETITIONS=${REPETITIONS:-9}
BIN=${BIN:-"$OUT_DIR/madvise_pageout_refault_reproducer"}
RAW_LOG=${RAW_LOG:-"$OUT_DIR/madvise_pageout_refault.raw.log"}
SUMMARY=${SUMMARY:-"$OUT_DIR/madvise_pageout_refault.summary.txt"}

mkdir -p "$OUT_DIR"

$CC $CFLAGS "$SCRIPT_DIR/madvise_pageout_refault_reproducer.c" -o "$BIN"

: > "$RAW_LOG"
i=1
while [ "$i" -le "$REPETITIONS" ]; do
    echo "=== repetition $i ===" | tee -a "$RAW_LOG"
    "$BIN" "$@" | tee -a "$RAW_LOG"
    i=$((i + 1))
done

awk '
function val(name,    i, kv) {
    for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == name)
            return kv[2] + 0
    }
    return 0
}
/^result / {
    n++
    advise += val("advise_ns_per_page")
    cycle += val("cycle_ns_per_page")
    avg_advise += val("advise_ns_avg")
    avg_cycle += val("cycle_ns_avg")
    unexpected += val("unexpected_results")
}
END {
    if (n == 0) {
        print "no result lines found"
        exit 1
    }
    printf("runs=%d\n", n)
    printf("mean_advise_ns_per_page=%.1f\n", advise / n)
    printf("mean_cycle_ns_per_page=%.1f\n", cycle / n)
    printf("mean_advise_ns_avg=%.1f\n", avg_advise / n)
    printf("mean_cycle_ns_avg=%.1f\n", avg_cycle / n)
    printf("unexpected_results=%d\n", unexpected)
}
' "$RAW_LOG" | tee "$SUMMARY"

printf 'raw_log=%s\nsummary=%s\n' "$RAW_LOG" "$SUMMARY"
