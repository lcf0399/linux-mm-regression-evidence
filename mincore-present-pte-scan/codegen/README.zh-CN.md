# mincore_pte_range x86 codegen 检查

这个目录记录 David Hildenbrand 提出的 codegen 问题：x86 上
`pte_batch_hint()` 返回 1 时，compiler 是否应该把 batching 逻辑优化回旧的
base-page 形状。

这只是 codegen/objdump 证据，不是 clean timing 证据。

## 范围

检查函数：

```text
mincore()
  -> walk_page_range()
     -> mincore_pte_range()
```

构建目标：

```text
make -C <tree> mm/mincore.o
objdump -dr --no-show-raw-insn mm/mincore.o
nm -S --defined-only mm/mincore.o
```

相关 config 形状：

```text
CONFIG_ADVISE_SYSCALLS=y
CONFIG_PGTABLE_LEVELS=5
CONFIG_PREEMPT_NONE=y
# CONFIG_PREEMPT is not set
# CONFIG_PREEMPT_DYNAMIC is not set
```

## GCC 13.3

Compiler：

```text
gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

`nm -S` 中 `mincore_pte_range` 的 size：

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc13_v6.15_original` | `0x1fb` | different |
| `gcc13_v6.16_original` | `0x245` | different |
| `gcc13_v6.16_fastpath` | `0x1ec` | identical to nobatch |
| `gcc13_v6.16_nobatch` | `0x1ec` | identical to fastpath |

在这个 GCC 构建下，v6.16 original 看起来没有被优化回旧的 x86 base-page 形状。
本地 `batch <= 1` fastpath 和 nobatch variant 生成了相同的
`mincore_pte_range()` 形状。

## GCC 14.2

Compiler：

```text
gcc-14 (Ubuntu 14.2.0-4ubuntu2~24.04.1) 14.2.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

这轮 GCC 14.2 是用 deb 包本地解包运行的，没有安装系统 package。

`nm -S` 中 `mincore_pte_range` 的 size：

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc14_v6.15_original` | `0x1e8` | different |
| `gcc14_v6.16_original` | `0x229` | different |
| `gcc14_v6.16_fastpath` | `0x1d9` | identical to nobatch |
| `gcc14_v6.16_nobatch` | `0x1d9` | identical to fastpath |

GCC 14.2 在这个检查里和 GCC 13.3 方向一致：v6.16 original 仍没有优化回旧的
x86 base-page 形状，而本地 `batch <= 1` fastpath 和 nobatch variant 逐字节等价。

## GCC 15.2

Compiler：

```text
gcc-15 (Ubuntu 15.2.0-4ubuntu4) 15.2.0
GNU ld (GNU Binutils for Ubuntu) 2.42
```

这轮 GCC 15.2 是用 deb 包本地解包运行的，没有安装系统 package。

`nm -S` 中 `mincore_pte_range` 的 size：

| variant | size | objdump relation |
| --- | ---: | --- |
| `gcc15_v6.15_original` | `0x1e0` | different |
| `gcc15_v6.16_original` | `0x221` | different |
| `gcc15_v6.16_fastpath` | `0x1d1` | identical to nobatch |
| `gcc15_v6.16_nobatch` | `0x1d1` | identical to fastpath |

GCC 15.2 在这个检查里也和 GCC 13.3 方向一致：v6.16 original 仍没有优化回旧的
x86 base-page 形状，而本地 `batch <= 1` fastpath 和 nobatch variant 逐字节等价。

同时保存了 GCC 15.2 的 `mincore_pte_range()` focused dump snippets：

| variant | optimized lines | RTL expand lines | objdump lines | objdump jumps |
| --- | ---: | ---: | ---: | ---: |
| `gcc15_v6.16_original` | 321 | 993 | 146 | 25 |
| `gcc15_v6.16_fastpath` | 299 | 921 | 136 | 23 |
| `gcc15_v6.16_nobatch` | 299 | 921 | 136 | 23 |

最终 fastpath 和 nobatch objdump 逐字节等价。它们的 optimized dump 只剩机械性的
SSA/source-line 命名差异。相反，original build 在 optimized 和 RTL-expand 阶段就已经
更大，不是最终汇编阶段才突然产生的差异。

## Clang 18.1.3

Compiler：

```text
Ubuntu clang version 18.1.3 (1ubuntu1)
GNU ld (GNU Binutils for Ubuntu) 2.42
```

`nm -S` 中 `mincore_pte_range` 的 size：

| variant | size | objdump relation |
| --- | ---: | --- |
| `clang18_v6.15_original` | `0x1f9` | identical |
| `clang18_v6.16_original` | `0x1f9` | identical |
| `clang18_v6.16_fastpath` | `0x1f9` | identical |
| `clang18_v6.16_nobatch` | `0x1f9` | identical |

四份 Clang objdump 逐字节等价：

```text
53463200547d1aef894b654e7dd681994e3894485c7ae3514284dbc9c5598242
```

所以 David 的理论预期在 Clang 18.1.3 下成立：x86 `pte_batch_hint() == 1`
场景会被优化成同一份 `mincore_pte_range()` 输出。

## GCC 实际差异

这看起来不像明显的额外 inlining 决策。GCC 13.3、GCC 14.2 和 GCC 15.2 下，
original 与 nobatch build 的外部 call / relocation 目标集合相同：

```text
__pte_offset_map_lock
__pmd_trans_huge_lock
memset
__cond_resched
filemap_get_incore_folio
__folio_put
swapper_spaces
```

可见差异主要是生成出来的 loop shape。v6.16 original 源码在调用
`pte_batch_hint()` 后保留了 `step`，用于 `ptep += step`、`addr += step * PAGE_SIZE`
和 `vec += step`。GCC 输出里，present-PTE single-page case 被拆到后面的 block：
先 store `1`，再跳回 common advance block。nobatch 和本地 `batch <= 1` fastpath
则生成更紧凑的 hot path，并且二者逐字节等价。

objdump 里的 hot-path 形状可以概括为：

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

`gcc-pte-loop-side-by-side.md` 里另外按 GCC 13.3、GCC 14.2 和 GCC 15.2
整理了一份短的 basic-block 对齐说明。

## Pedro 的 always-inline 建议

Pedro 建议测试把默认 x86 `pte_batch_hint()` helper 强制成 `__always_inline` 是否会改变
generated code。在这个 setup 下没有改变：GCC 13.3、GCC 14.2 和 GCC 15.2 生成的
`mincore_pte_range()` normalized function objdump 都和 v6.16 original 相同。见
`gcc-always-inline-test.md`。

## 解释

这个 codegen 检查会收窄原始报告：

- 这不是 generic x86 `mincore()` regression claim。
- 这不能证明 compiler bug。
- 原始 lab timing 是在 GCC 13.3 + QEMU direct-boot 环境中观察到的。
- 这个源码形状对 compiler/codegen 敏感：GCC 13.3、GCC 14.2 和 GCC 15.2 下有
  generated-code layout 差异，Clang 18.1.3 下没有。
