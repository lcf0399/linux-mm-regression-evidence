// SPDX-License-Identifier: GPL-2.0-only
/*
 * Minimal userspace reproducer for the MADV_PAGEOUT + anonymous refault
 * workflow used by mm_regression_gen's madvise_pageout_formal_refresh profile.
 *
 * Default parameters mirror the reportable 16 MiB THP-default/no-swap workload:
 *   warm up twice, then repeat enough internal rounds to run for at least
 *   1200 ms per external round, with 5 external rounds.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifndef CLOCK_MONOTONIC_RAW
#define CLOCK_MONOTONIC_RAW CLOCK_MONOTONIC
#endif

#ifndef MADV_PAGEOUT
#define MADV_PAGEOUT 21
#endif

#ifndef MADV_HUGEPAGE
#define MADV_HUGEPAGE 14
#endif

#ifndef MADV_NOHUGEPAGE
#define MADV_NOHUGEPAGE 15
#endif

enum thp_mode {
    THP_DEFAULT = 0,
    THP_HUGEPAGE,
    THP_NOHUGEPAGE,
};

struct options {
    const char *scenario;
    size_t mapping_kb;
    unsigned int external_rounds;
    unsigned int rounds;
    unsigned int max_rounds;
    unsigned int warmup_rounds;
    uint64_t min_measure_ns;
    enum thp_mode thp;
    int dump_smaps;
};

struct run_result {
    uint64_t prefault_ns;
    uint64_t advise_ns;
    uint64_t post_touch_ns;
    uint64_t internal_rounds;
    uint64_t pages_touched;
    uint64_t expected_matches;
    uint64_t unexpected_results;
    uint64_t errno_enomem;
    uint64_t errno_einval;
    uint64_t errno_other;
    uint64_t checksum;
};

static volatile unsigned long benchmark_sink;

static uint64_t now_ns(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0) {
        if (errno != EINVAL || clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
            perror("clock_gettime");
            exit(1);
        }
    }
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static size_t page_size_or_default(void)
{
    long page = sysconf(_SC_PAGESIZE);

    if (page <= 0)
        return 4096;
    return (size_t)page;
}

static void touch_write_pages(unsigned char *addr, size_t len,
                              struct run_result *result)
{
    size_t page = page_size_or_default();

    for (size_t off = 0; off < len; off += page) {
        addr[off] = (unsigned char)(addr[off] + 1U);
        result->checksum += addr[off];
        result->pages_touched += 1;
    }
}

static void record_errno(struct run_result *result, int value)
{
    switch (value) {
    case 0:
        return;
    case ENOMEM:
        result->errno_enomem += 1;
        return;
    case EINVAL:
        result->errno_einval += 1;
        return;
    default:
        result->errno_other += 1;
        return;
    }
}

static const char *thp_mode_name(enum thp_mode mode)
{
    switch (mode) {
    case THP_DEFAULT:
        return "default";
    case THP_HUGEPAGE:
        return "hugepage";
    case THP_NOHUGEPAGE:
        return "nohugepage";
    default:
        return "unknown";
    }
}

static int apply_thp_hint(unsigned char *region, size_t bytes, enum thp_mode mode)
{
    int advice;

    if (mode == THP_DEFAULT)
        return 0;

    advice = mode == THP_NOHUGEPAGE ? MADV_NOHUGEPAGE : MADV_HUGEPAGE;
    if (madvise(region, bytes, advice) != 0) {
        perror(mode == THP_NOHUGEPAGE ? "madvise(MADV_NOHUGEPAGE)" :
                                        "madvise(MADV_HUGEPAGE)");
        return -1;
    }
    return 0;
}

static void dump_mapping_smaps(unsigned char *region, size_t bytes)
{
    FILE *fp;
    char line[512];
    unsigned long start = (unsigned long)region;
    unsigned long end = start + (unsigned long)bytes;
    int in_target = 0;
    unsigned long header_start;
    unsigned long header_end;

    fp = fopen("/proc/self/smaps", "r");
    if (!fp) {
        perror("fopen(/proc/self/smaps)");
        return;
    }

    printf("smaps_for=%lx-%lx\n", start, end);
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%lx-%lx", &header_start, &header_end) == 2) {
            in_target = header_start <= start && header_end >= end;
            if (in_target)
                printf("smaps_header=%s", line);
            continue;
        }
        if (!in_target)
            continue;
        if (strncmp(line, "AnonHugePages:", 14) == 0 ||
            strncmp(line, "THPeligible:", 12) == 0 ||
            strncmp(line, "KernelPageSize:", 15) == 0 ||
            strncmp(line, "MMUPageSize:", 12) == 0)
            printf("smaps_%s", line);
    }
    fclose(fp);
}

static int run_one_cycle(const struct options *opts, struct run_result *result)
{
    size_t bytes = opts->mapping_kb * 1024UL;
    unsigned char *region;
    struct run_result prefault = {0};
    struct run_result post = {0};
    uint64_t start_ns;
    uint64_t end_ns;
    int ret;
    int ret_errno = 0;

    region = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (region == MAP_FAILED) {
        perror("mmap");
        return -1;
    }

    if (apply_thp_hint(region, bytes, opts->thp) != 0) {
        munmap(region, bytes);
        return -1;
    }

    start_ns = now_ns();
    touch_write_pages(region, bytes, &prefault);
    end_ns = now_ns();
    result->prefault_ns += end_ns - start_ns;
    result->checksum += prefault.checksum;

    if (opts->dump_smaps)
        dump_mapping_smaps(region, bytes);

    errno = 0;
    start_ns = now_ns();
    ret = madvise(region, bytes, MADV_PAGEOUT);
    if (ret != 0)
        ret_errno = errno;
    end_ns = now_ns();
    result->advise_ns += end_ns - start_ns;

    if (ret == 0)
        result->expected_matches += 1;
    else
        result->unexpected_results += 1;
    record_errno(result, ret_errno);

    if (ret == 0) {
        start_ns = now_ns();
        touch_write_pages(region, bytes, &post);
        end_ns = now_ns();
        result->post_touch_ns += end_ns - start_ns;
        result->pages_touched += post.pages_touched;
        result->checksum += post.checksum;
    }

    munmap(region, bytes);
    return 0;
}

static int run_internal_sample(const struct options *opts, struct run_result *sample)
{
    unsigned int sample_rounds = 0;
    uint64_t sample_total_ns;

    do {
        if (run_one_cycle(opts, sample) != 0)
            return -1;
        sample_rounds += 1;
        sample_total_ns = sample->prefault_ns + sample->advise_ns +
                          sample->post_touch_ns;
    } while (sample_rounds < opts->rounds ||
             (opts->min_measure_ns > 0 &&
              sample_total_ns < opts->min_measure_ns &&
              sample_rounds < opts->max_rounds));

    sample->internal_rounds += sample_rounds;
    return 0;
}

static void add_result(struct run_result *dst, const struct run_result *src)
{
    dst->prefault_ns += src->prefault_ns;
    dst->advise_ns += src->advise_ns;
    dst->post_touch_ns += src->post_touch_ns;
    dst->internal_rounds += src->internal_rounds;
    dst->pages_touched += src->pages_touched;
    dst->expected_matches += src->expected_matches;
    dst->unexpected_results += src->unexpected_results;
    dst->errno_enomem += src->errno_enomem;
    dst->errno_einval += src->errno_einval;
    dst->errno_other += src->errno_other;
    dst->checksum += src->checksum;
}

static unsigned long parse_ulong(const char *name, const char *text,
                                 unsigned long min_value)
{
    char *endptr = NULL;
    unsigned long value;

    errno = 0;
    value = strtoul(text, &endptr, 0);
    if (errno || !endptr || *endptr != '\0' || value < min_value) {
        fprintf(stderr, "invalid %s: %s\n", name, text);
        exit(2);
    }
    return value;
}

static uint64_t parse_ms_to_ns(const char *name, const char *text)
{
    return (uint64_t)parse_ulong(name, text, 0) * 1000000ULL;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [scenario [external-rounds]] [options]\n"
            "\n"
            "Scenario:\n"
            "  pageout_refault_anon_16m (default; also accepts pageout_refault_anon)\n"
            "\n"
            "Options:\n"
            "  --mapping-kb N         mapping size in KiB (default: 16384)\n"
            "  --external-rounds N    outer repetitions (default: 5)\n"
            "  --rounds N             minimum internal rounds per outer round (default: 4)\n"
            "  --max-rounds N         maximum internal rounds per outer round (default: 256)\n"
            "  --warmup-rounds N      warmup cycles before each outer round (default: 2)\n"
            "  --min-ms N             minimum measured ms per outer round (default: 1200)\n"
            "  --thp MODE             default, hugepage, or nohugepage (default: default)\n"
            "  --dump-smaps           print selected smaps fields after prefault\n"
            "  --help                 show this help\n",
            argv0);
}

static int is_supported_scenario(const char *text)
{
    return strcmp(text, "pageout_refault_anon_16m") == 0 ||
           strcmp(text, "pageout_refault_anon") == 0;
}

static void parse_args(int argc, char **argv, struct options *opts)
{
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            exit(0);
        } else if (strcmp(argv[i], "--dump-smaps") == 0) {
            opts->dump_smaps = 1;
        } else if (strcmp(argv[i], "--mapping-kb") == 0 && i + 1 < argc) {
            opts->mapping_kb = parse_ulong("--mapping-kb", argv[++i], 4);
        } else if (strcmp(argv[i], "--external-rounds") == 0 && i + 1 < argc) {
            opts->external_rounds = parse_ulong("--external-rounds", argv[++i], 1);
        } else if (strcmp(argv[i], "--rounds") == 0 && i + 1 < argc) {
            opts->rounds = parse_ulong("--rounds", argv[++i], 1);
        } else if (strcmp(argv[i], "--max-rounds") == 0 && i + 1 < argc) {
            opts->max_rounds = parse_ulong("--max-rounds", argv[++i], 1);
        } else if (strcmp(argv[i], "--warmup-rounds") == 0 && i + 1 < argc) {
            opts->warmup_rounds = parse_ulong("--warmup-rounds", argv[++i], 0);
        } else if (strcmp(argv[i], "--min-ms") == 0 && i + 1 < argc) {
            opts->min_measure_ns = parse_ms_to_ns("--min-ms", argv[++i]);
        } else if (strcmp(argv[i], "--thp") == 0 && i + 1 < argc) {
            const char *mode = argv[++i];

            if (strcmp(mode, "default") == 0)
                opts->thp = THP_DEFAULT;
            else if (strcmp(mode, "hugepage") == 0)
                opts->thp = THP_HUGEPAGE;
            else if (strcmp(mode, "nohugepage") == 0)
                opts->thp = THP_NOHUGEPAGE;
            else {
                fprintf(stderr, "invalid --thp mode: %s\n", mode);
                exit(2);
            }
        } else if (argv[i][0] != '-') {
            if (is_supported_scenario(argv[i])) {
                opts->scenario = argv[i];
            } else {
                opts->external_rounds = parse_ulong("external-rounds", argv[i], 1);
            }
        } else {
            fprintf(stderr, "unknown or incomplete option: %s\n", argv[i]);
            usage(argv[0]);
            exit(2);
        }
    }

    if (opts->max_rounds < opts->rounds)
        opts->max_rounds = opts->rounds;
}

int main(int argc, char **argv)
{
    struct options opts = {
        .scenario = "pageout_refault_anon_16m",
        .mapping_kb = 16384,
        .external_rounds = 5,
        .rounds = 4,
        .max_rounds = 256,
        .warmup_rounds = 2,
        .min_measure_ns = 1200000000ULL,
        .thp = THP_DEFAULT,
        .dump_smaps = 0,
    };
    struct run_result aggregate = {0};
    size_t page_size;
    size_t pages;

    parse_args(argc, argv, &opts);
    page_size = page_size_or_default();
    pages = (opts.mapping_kb * 1024UL) / page_size;

    printf("workload=madvise_pageout_reproducer "
           "source=linux/mm/madvise.c scenarios=1 rounds=%u\n",
           opts.external_rounds);
    printf("reproducer=madvise_pageout_refault "
           "case=%s mapping_kb=%zu pages=%zu page_size=%zu thp=%s "
           "external_rounds=%u rounds=%u max_rounds=%u warmup_rounds=%u "
           "min_measure_ns=%" PRIu64 "\n",
           opts.scenario, opts.mapping_kb, pages, page_size,
           thp_mode_name(opts.thp), opts.external_rounds, opts.rounds, opts.max_rounds,
           opts.warmup_rounds, opts.min_measure_ns);

    for (unsigned int outer = 0; outer < opts.external_rounds; ++outer) {
        struct run_result sample = {0};

        for (unsigned int warmup = 0; warmup < opts.warmup_rounds; ++warmup) {
            struct run_result ignored = {0};

            if (run_one_cycle(&opts, &ignored) != 0)
                return 1;
        }

        if (run_internal_sample(&opts, &sample) != 0)
            return 1;
        add_result(&aggregate, &sample);
    }

    benchmark_sink += (unsigned long)aggregate.checksum;

    printf("result scenario=%s pattern=pageout_refault_anon advice=MADV_PAGEOUT"
           " internal_rounds=%" PRIu64
           " prefault_ns_avg=%" PRIu64
           " advise_ns_avg=%" PRIu64
           " post_touch_ns_avg=%" PRIu64
           " cycle_ns_avg=%" PRIu64
           " prefault_ns_per_page=%" PRIu64
           " advise_ns_per_page=%" PRIu64
           " post_touch_ns_per_page=%" PRIu64
           " cycle_ns_per_page=%" PRIu64
           " expected_match_ratio=%" PRIu64
           " unexpected_results=%" PRIu64
           " errno_enomem=%" PRIu64
           " errno_einval=%" PRIu64
           " errno_other=%" PRIu64
           " checksum=%" PRIu64 "\n",
           opts.scenario,
           aggregate.internal_rounds,
           aggregate.internal_rounds ? aggregate.prefault_ns / aggregate.internal_rounds : 0,
           aggregate.internal_rounds ? aggregate.advise_ns / aggregate.internal_rounds : 0,
           aggregate.internal_rounds ? aggregate.post_touch_ns / aggregate.internal_rounds : 0,
           aggregate.internal_rounds ?
                (aggregate.advise_ns + aggregate.post_touch_ns) /
                    aggregate.internal_rounds : 0,
           aggregate.pages_touched ? aggregate.prefault_ns / aggregate.pages_touched : 0,
           aggregate.pages_touched ? aggregate.advise_ns / aggregate.pages_touched : 0,
           aggregate.pages_touched ? aggregate.post_touch_ns / aggregate.pages_touched : 0,
           aggregate.pages_touched ?
                (aggregate.advise_ns + aggregate.post_touch_ns) /
                    aggregate.pages_touched : 0,
           aggregate.internal_rounds ?
                (uint64_t)((aggregate.expected_matches * 100ULL) /
                           aggregate.internal_rounds) : 0,
           aggregate.unexpected_results,
           aggregate.errno_enomem,
           aggregate.errno_einval,
           aggregate.errno_other,
           aggregate.checksum);

    return aggregate.unexpected_results ? 1 : 0;
}
