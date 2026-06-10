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

For GCC 13.3, GCC 14.2, and GCC 15.2, the always-inline variant has the same
`mincore_pte_range()` size and the same normalized function objdump as v6.16
original. It does not collapse to the local `batch <= 1` fastpath / nobatch
shape.

| compiler | v6.16 original size | v6.16 always-inline size | relation |
| --- | ---: | ---: | --- |
| GCC 13.3 | `0x245` | `0x245` | same normalized objdump as original |
| GCC 14.2 | `0x229` | `0x229` | same normalized objdump as original |
| GCC 15.2 | `0x221` | `0x221` | same normalized objdump as original |

The matching normalized `mincore_pte_range()` objdump hashes are:

```text
GCC 13.3 original / always-inline:
  72e241e87b3955ac68073a4d3c9fb753f16ae03a1b50fdedf26fefc524a9919f

GCC 14.2 original / always-inline:
  c6ec9ff7d34afdeace1e36f3d94fc4627b36192cc1dd455602dd7767d05f01db

GCC 15.2 original / always-inline:
  86f3574d08cb0cbd459ec77bfc27e16911f29803a3aafefa218ce9eabb41da6d
```

## Interpretation

This suggests that the observed GCC layout difference is not simply caused by
GCC refusing to inline the default x86 `pte_batch_hint()` helper. For these
builds, forcing `__always_inline` leaves the v6.16 original generated
instruction listing unchanged.

The remaining difference still points at the surrounding batching/`step`
control-flow shape: the local `batch <= 1` fastpath and the nobatch variant
continue to produce a shorter, byte-identical `mincore_pte_range()` output,
while the v6.16 original and always-inline variant keep the larger layout.
