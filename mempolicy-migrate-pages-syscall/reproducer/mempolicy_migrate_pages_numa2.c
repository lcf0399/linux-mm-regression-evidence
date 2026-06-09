// SPDX-License-Identifier: GPL-2.0-only
/*
 * Minimal reproducer for the mempolicy migrate_pages() NUMA2 workload.
 *
 * Shape:
 *   mmap anonymous memory
 *   mbind() the range to the first online node
 *   touch all pages
 *   migrate_pages(0, old_nodes={first}, new_nodes={second})
 *   verify placement with move_pages(..., nodes=NULL, status=...)
 *
 * This is intentionally small and syscall-based so it can be sent upstream as
 * a workload-shape reproducer without the mm_regression_gen harness.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#ifndef MADV_NOHUGEPAGE
#define MADV_NOHUGEPAGE 15
#endif

#ifndef MPOL_BIND
#define MPOL_BIND 2
#endif

#ifndef __NR_mbind
# if defined(__x86_64__)
#  define __NR_mbind 237
# else
#  error "__NR_mbind is not defined for this architecture"
# endif
#endif

#ifndef __NR_migrate_pages
# if defined(__x86_64__)
#  define __NR_migrate_pages 256
# else
#  error "__NR_migrate_pages is not defined for this architecture"
# endif
#endif

#ifndef __NR_move_pages
# if defined(__x86_64__)
#  define __NR_move_pages 279
# else
#  error "__NR_move_pages is not defined for this architecture"
# endif
#endif

#define MAX_NODE_BITS ((unsigned int)(sizeof(unsigned long) * 8U))
#define MAXNODE_ARG ((unsigned long)MAX_NODE_BITS + 1UL)

struct node_pair {
	int count;
	int first;
	int second;
	unsigned long first_mask;
	unsigned long second_mask;
};

static volatile unsigned long sink;

static uint64_t now_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0 &&
	    clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		perror("clock_gettime");
		exit(1);
	}
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static size_t page_size(void)
{
	long value = sysconf(_SC_PAGESIZE);

	return value > 0 ? (size_t)value : 4096UL;
}

static void add_node(struct node_pair *nodes, int node)
{
	if (node < 0 || (unsigned int)node >= MAX_NODE_BITS)
		return;
	if (nodes->count == 0)
		nodes->first = node;
	else if (nodes->count == 1)
		nodes->second = node;
	nodes->count++;
}

static void read_online_nodes(struct node_pair *nodes)
{
	FILE *fp;
	char buf[128];

	memset(nodes, 0, sizeof(*nodes));
	nodes->first = 0;
	nodes->second = 0;

	fp = fopen("/sys/devices/system/node/online", "r");
	if (!fp) {
		add_node(nodes, 0);
		goto out;
	}
	if (!fgets(buf, sizeof(buf), fp)) {
		fclose(fp);
		add_node(nodes, 0);
		goto out;
	}
	fclose(fp);

	for (char *p = buf; *p;) {
		char *end = NULL;
		long first = strtol(p, &end, 10);
		long last = first;

		if (end == p)
			break;
		if (*end == '-') {
			p = end + 1;
			last = strtol(p, &end, 10);
		}
		for (long node = first; node <= last; node++)
			add_node(nodes, (int)node);
		p = end;
		while (*p == ',' || *p == ' ' || *p == '\n')
			p++;
	}
	if (nodes->count <= 0)
		add_node(nodes, 0);

out:
	nodes->first_mask = 1UL << (unsigned int)nodes->first;
	nodes->second_mask = nodes->count > 1 ?
		1UL << (unsigned int)nodes->second : nodes->first_mask;
}

static long sys_mbind(void *addr, size_t len, int mode,
		      const unsigned long *mask, unsigned long flags)
{
	return syscall(__NR_mbind, (unsigned long)addr, (unsigned long)len,
		       (unsigned long)mode, mask, MAXNODE_ARG, flags);
}

static long sys_migrate_pages(unsigned long old_mask, unsigned long new_mask)
{
	return syscall(__NR_migrate_pages, 0, MAXNODE_ARG, &old_mask, &new_mask);
}

static long sys_move_pages(void **pages, int *status, size_t nr_pages)
{
	return syscall(__NR_move_pages, 0, (unsigned long)nr_pages,
		       pages, NULL, status, 0);
}

static void touch_mapping(unsigned char *addr, size_t bytes, size_t ps)
{
	unsigned long checksum = 0;

	for (size_t off = 0; off < bytes; off += ps) {
		addr[off] = (unsigned char)(off / ps);
		checksum += addr[off];
	}
	sink += checksum;
}

static int run_once(size_t bytes, const struct node_pair *nodes, unsigned int round)
{
	size_t ps = page_size();
	size_t nr_pages = bytes / ps;
	unsigned char *addr;
	void **pages;
	int *status;
	uint64_t start;
	uint64_t move_ns;
	long rc;
	unsigned long target_pages = 0;
	unsigned long other_pages = 0;
	unsigned long failed_pages = 0;

	addr = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
		    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (addr == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	(void)madvise(addr, bytes, MADV_NOHUGEPAGE);

	pages = calloc(nr_pages, sizeof(*pages));
	status = calloc(nr_pages, sizeof(*status));
	if (!pages || !status) {
		perror("calloc");
		munmap(addr, bytes);
		free(pages);
		free(status);
		return 1;
	}
	for (size_t i = 0; i < nr_pages; i++)
		pages[i] = addr + i * ps;

	rc = sys_mbind(addr, bytes, MPOL_BIND, &nodes->first_mask, 0);
	if (rc != 0) {
		perror("mbind");
		goto fail;
	}

	touch_mapping(addr, bytes, ps);

	start = now_ns();
	rc = sys_migrate_pages(nodes->first_mask, nodes->second_mask);
	move_ns = now_ns() - start;
	if (rc < 0) {
		perror("migrate_pages");
		goto fail;
	}
	failed_pages = (unsigned long)rc;

	rc = sys_move_pages(pages, status, nr_pages);
	if (rc != 0) {
		perror("move_pages query");
		goto fail;
	}

	for (size_t i = 0; i < nr_pages; i++) {
		if (status[i] == nodes->second)
			target_pages++;
		else
			other_pages++;
	}

	printf("round=%u bytes=%zu pages=%zu old_node=%d new_node=%d "
	       "move_ns=%" PRIu64 " move_ns_per_page=%" PRIu64 " "
	       "target_pages=%lu other_pages=%lu failed_pages=%lu\n",
	       round, bytes, nr_pages, nodes->first, nodes->second,
	       move_ns, move_ns / nr_pages, target_pages, other_pages, failed_pages);

	free(pages);
	free(status);
	munmap(addr, bytes);
	return target_pages == nr_pages && failed_pages == 0 ? 0 : 2;

fail:
	free(pages);
	free(status);
	munmap(addr, bytes);
	return 1;
}

int main(int argc, char **argv)
{
	struct node_pair nodes;
	size_t mib = argc > 1 ? strtoull(argv[1], NULL, 0) : 16;
	unsigned int rounds = argc > 2 ? (unsigned int)strtoul(argv[2], NULL, 0) : 9;
	size_t ps = page_size();
	size_t bytes = mib * 1024ULL * 1024ULL;
	int failures = 0;

	if (argc > 1 && (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help"))) {
		fprintf(stderr, "usage: %s [mapping_mib=16] [rounds=9]\n", argv[0]);
		return 0;
	}
	bytes = (bytes / ps) * ps;
	if (!bytes)
		bytes = ps;

	read_online_nodes(&nodes);
	if (nodes.count < 2) {
		fprintf(stderr, "need at least two online NUMA nodes, got %d\n", nodes.count);
		return 77;
	}

	printf("mempolicy_migrate_pages_numa2 mapping_mib=%zu rounds=%u "
	       "first_node=%d second_node=%d page_size=%zu\n",
	       mib, rounds, nodes.first, nodes.second, ps);

	for (unsigned int round = 1; round <= rounds; round++)
		failures += run_once(bytes, &nodes, round) != 0;

	return failures ? 1 : 0;
}
