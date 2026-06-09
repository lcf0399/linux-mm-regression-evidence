# mempolicy migrate_pages() Standalone Reproducer

`mempolicy_migrate_pages_numa2.c` is a small standalone reproducer for the
workload shape.  It demonstrates the syscall route and state-shape checks
without requiring the full `mm_regression_gen` pipeline.

Build:

```sh
gcc -O2 -Wall -Wextra -o mempolicy_migrate_pages_numa2 mempolicy_migrate_pages_numa2.c
```

Typical shape:

```text
mmap() 16 MiB anonymous memory
mbind() the range to node 0
fault/touch all pages
migrate_pages(0, old_nodes={node0}, new_nodes={node1})
verify page placement with move_pages(..., nodes=NULL, status=...)
```

The smoke log `mempolicy_migrate_pages_numa2.lab-host-smoke-20260604.txt`
records a 16 MiB / 3-round run on a two-node NUMA lab host where all 4096 pages
ended up on the target node and `failed_pages=0`.

This reproducer is workload-shape evidence only.  It is not version-comparison
timing evidence.
