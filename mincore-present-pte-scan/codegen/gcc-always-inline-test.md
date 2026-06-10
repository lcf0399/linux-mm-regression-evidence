# GCC `pte_batch_hint()` always-inline test

Pedro suggested checking whether forcing the default `pte_batch_hint()` helper
to inline changes the x86 generated code:

```diff
-static inline unsigned int pte_batch_hint(pte_t *ptep, pte_t pte)
+static __always_inline unsigned int pte_batch_hint(pte_t *ptep, pte_t pte)
 {
        return 1;
 }
```

This note records that test. It is static codegen evidence only.

## Result

For GCC 13.3, GCC 14.2, and GCC 15.2, the always-inline variant is
byte-identical to the v6.16 original `mincore_pte_range()` objdump. It does not
collapse to the local `batch <= 1` fastpath / nobatch shape.

| compiler | v6.16 original size | v6.16 always-inline size | relation |
| --- | ---: | ---: | --- |
| GCC 13.3 | `0x245` | `0x245` | byte-identical to original |
| GCC 14.2 | `0x229` | `0x229` | byte-identical to original |
| GCC 15.2 | `0x221` | `0x221` | byte-identical to original |

The matching objdump hashes are:

```text
GCC 13.3 original / always-inline:
  11ba50b6f4d749692b9d0c277bd26437958543144a2c90c9cf1038fe1eaa4437

GCC 14.2 original / always-inline:
  99f72d073d7ad9219fee7cb1459ed4c268444d1dfd3b2c41e2edd2d8077d854d

GCC 15.2 original / always-inline:
  5d80f8a89aa3e478ead7e96fa91015fc679a56835f3ec5eac168fb196eae9d9d
```

## Interpretation

This suggests that the observed GCC layout difference is not simply caused by
GCC refusing to inline the default x86 `pte_batch_hint()` helper. For these
builds, forcing `__always_inline` leaves the v6.16 original generated code
unchanged.

The remaining difference still points at the surrounding batching/`step`
control-flow shape: the local `batch <= 1` fastpath and the nobatch variant
continue to produce a shorter, byte-identical `mincore_pte_range()` output,
while the v6.16 original and always-inline variant keep the larger layout.
