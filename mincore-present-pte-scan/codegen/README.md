# mincore_pte_range x86 codegen check

This directory contains a small generated-code check for David Hildenbrand's
question about whether x86 should optimize the `pte_batch_hint()` batching code
back to the old base-page shape when `pte_batch_hint()` returns 1.

This is codegen evidence only. It is not clean timing evidence.

## Scope

Function checked:

```text
mincore()
  -> walk_page_range()
     -> mincore_pte_range()
```

Build target:

```text
make -C <tree> mm/mincore.o
objdump -dr --no-show-raw-insn mm/mincore.o
nm -S --defined-only mm/mincore.o
```

Relevant config shape:

```text
CONFIG_ADVISE_SYSCALLS=y
CONFIG_PGTABLE_LEVELS=5
CONFIG_PREEMPT_NONE=y
# CONFIG_PREEMPT is not set
# CONFIG_PREEMPT_DYNAMIC is not set
```

## GCC 13.3

Compiler:

```text
gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

`mincore_pte_range` sizes from `nm -S`:

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc13_v6.15_original` | `0x1fb` | different |
| `gcc13_v6.16_original` | `0x245` | different |
| `gcc13_v6.16_fastpath` | `0x1ec` | identical to nobatch |
| `gcc13_v6.16_nobatch` | `0x1ec` | identical to fastpath |

With this GCC build, v6.16 original does not appear to optimize back to the old
x86 base-page shape. The small `batch <= 1` fastpath and the nobatch variant
produce the same generated `mincore_pte_range()` shape.

## GCC 14.2

Compiler:

```text
gcc-14 (Ubuntu 14.2.0-4ubuntu2~24.04.1) 14.2.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

This was run from user-local deb extraction, without installing system
packages.

`mincore_pte_range` sizes from `nm -S`:

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc14_v6.15_original` | `0x1e8` | different |
| `gcc14_v6.16_original` | `0x229` | different |
| `gcc14_v6.16_fastpath` | `0x1d9` | identical to nobatch |
| `gcc14_v6.16_nobatch` | `0x1d9` | identical to fastpath |

GCC 14.2 behaves like GCC 13.3 for this check: v6.16 original still does not
optimize back to the old x86 base-page shape, while the small `batch <= 1`
fastpath and the nobatch variant are byte-identical.

## GCC 15.2

Compiler:

```text
gcc-15 (Ubuntu 15.2.0-4ubuntu4) 15.2.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

This was run from user-local deb extraction, without installing system
packages.

`mincore_pte_range` sizes from `nm -S`:

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc15_v6.15_original` | `0x1e0` | different |
| `gcc15_v6.16_original` | `0x221` | different |
| `gcc15_v6.16_fastpath` | `0x1d1` | identical to nobatch |
| `gcc15_v6.16_nobatch` | `0x1d1` | identical to fastpath |

GCC 15.2 also behaves like GCC 13.3 for this check: v6.16 original still does
not optimize back to the old x86 base-page shape, while the small `batch <= 1`
fastpath and the nobatch variant are byte-identical.

Focused GCC 15.2 dump snippets were also saved for `mincore_pte_range()`:

| variant | optimized lines | RTL expand lines | objdump lines | objdump jumps |
| --- | ---: | ---: | ---: | ---: |
| `gcc15_v6.16_original` | 321 | 993 | 146 | 25 |
| `gcc15_v6.16_fastpath` | 299 | 921 | 136 | 23 |
| `gcc15_v6.16_nobatch` | 299 | 921 | 136 | 23 |

The final fastpath and nobatch objdump files are byte-identical. Their
optimized dumps differ only in mechanical SSA/source-line naming. By contrast,
the original build is already larger at the optimized and RTL-expand stages,
before final assembly.

## Clang 18.1.3

Compiler:

```text
Ubuntu clang version 18.1.3 (1ubuntu1)
GNU ld (GNU Binutils for Ubuntu) 2.42
```

`mincore_pte_range` sizes from `nm -S`:

| variant | size | objdump relation |
| --- | ---: | --- |
| `clang18_v6.15_original` | `0x1f9` | identical |
| `clang18_v6.16_original` | `0x1f9` | identical |
| `clang18_v6.16_fastpath` | `0x1f9` | identical |
| `clang18_v6.16_nobatch` | `0x1f9` | identical |

The four Clang-generated objdump files are byte-identical:

```text
53463200547d1aef894b654e7dd681994e3894485c7ae3514284dbc9c5598242
```

So David's expectation holds for Clang 18.1.3: the x86 `pte_batch_hint() == 1`
case is optimized to the same `mincore_pte_range()` output across the original
and patched variants.

## Actual GCC Difference

This does not look like an obvious extra inlining decision. In GCC 13.3,
GCC 14.2, and GCC 15.2, the original and nobatch builds have the same external
call / relocation targets:

```text
__pte_offset_map_lock
__pmd_trans_huge_lock
memset
__cond_resched
filemap_get_incore_folio
__folio_put
swapper_spaces
```

The visible difference is the generated loop shape.  The v6.16 original source
keeps `step` for `ptep += step`, `addr += step * PAGE_SIZE`, and `vec += step`
after calling `pte_batch_hint()`.  In the GCC output, the present-PTE single
page case is split into a later block that stores `1` and jumps back to a common
advance block.  The nobatch and local `batch <= 1` fastpath builds produce a
more compact hot path and are byte-identical to each other.

The objdump hot-path shape is:

```text
GCC15 v6.16 original:
  ... test present bits
  jne  <later present-store block>
  ...
  common advance:
    add vec
    add ptep
    cmp end
    jne loop
  later present-store block:
    movb $0x1,(vec)
    jmp common advance

GCC15 v6.16 nobatch / batch<=1 fastpath:
  present-store block:
    movb $0x1,(vec)
    add vec
    add ptep
    cmp end
    ...
```

See `gcc-pte-loop-side-by-side.md` for the short side-by-side block note across
GCC 13.3, GCC 14.2, and GCC 15.2.

## Pedro's always-inline suggestion

Pedro suggested testing whether forcing the default x86 `pte_batch_hint()` helper
to `__always_inline` changes the generated code. It does not in this setup:
GCC 13.3, GCC 14.2, and GCC 15.2 all produce `mincore_pte_range()` output that
has the same normalized function objdump as v6.16 original. See
`gcc-always-inline-test.md`.

## Interpretation

This codegen check narrows the original report:

- It is not a generic x86 `mincore()` regression claim.
- It is not proof of a compiler bug.
- The original lab timing was observed with GCC 13.3 in a QEMU direct-boot
  environment.
- The source shape is compiler/codegen-sensitive: GCC 13.3, GCC 14.2, and
  GCC 15.2 show a generated-code layout difference; Clang 18.1.3 does not.
