# Commit Inventory Note

This is a compact source-history note for the `migrate_pages()` syscall route
candidate.  It is not a full bisect.

Range checked:

```text
v6.19: 05f7e89ab9731565d8a62e3b5d1ec206485eeb0b
v7.0:  028ef9c96e96197026887c0f092424679298aae8
```

Paths screened:

```text
mm/migrate.c
mm/rmap.c
include/linux/rmap.h
include/linux/migrate.h
mm/internal.h
mm/huge_memory.c
mm/mempolicy.c
```

The most direct first candidate was:

```text
832d95b5314e migrate: replace RMP_ flags with TTU_ flags
```

Reason: this is the most visible `v6.19..v7.0` change touching
`mm/migrate.c` migration/rmap flag plumbing.  Source review already made it a
questionable match for the current anonymous base-page workload, because the
base migration path reaches `remove_migration_ptes(src, dst, 0)`.

The v7 revert-style attribution A/B was neutral:

```text
tree                                  mean/median move_ns_per_page
v7.0.9-preempt                        10782.0 / 10831
v7.0.9-revert-832d95b-attribution     10732.4 / 10742
```

The attribution tree was only about 0.46% faster by mean and 0.82% faster by
median, below the 5% actionable threshold used for this work.  Therefore
`832d95b5314e` is currently a negative lead for this workload.

The remaining useful work is lower-overhead perf-style attribution or deeper
commit-level narrowing around migration-core/rmap/folio-migration helpers.
