# GDU-03: deterministic generator portability

2026-10-25. Two integration checks exposed checkout/interpreter differences on
native Windows. Their strict checks remain enabled.

`horizon.json` had one CRLF newline: 164,688 bytes rather than the generator's
164,687. Running `tools/terrain/gen_terrain.py` restored its exact LF output;
an explicit checkout rule retains those bytes. Parsed JSON and every generated
height value are unchanged. The [byte proof](horizon-byte-proof.json),
[root check](horizon-root-check.log), [frozen check](horizon-frozen-check.log) and
[fresh-clone checks](horizon-checkout-proof.json) retain the evidence. Both
`core.autocrlf=true` and `false` clones produce the same LF hash.

E0b2's polygon `area()` used built-in floating-point `sum()`. Native Python
3.11.9 produced six final-bit area differences from the recorded report; the
original generator reproduces it on WSL Python 3.12.3. Python 3.12 changed float
[`sum()` to Neumaier summation](https://docs.python.org/3.12/whatsnew/3.12.html#other-language-changes).
The generator now uses explicit `math.fsum`, reproducing the existing report
text exactly on both interpreters. Its existing five geometry tests and
`derive_geometry.py --check` pass on both. No handoff report, source geometry,
compiled geometry or aircraft data was rewritten. The [cross-Python proof](e0b2-cross-python-proof.json)
fingerprints those unchanged files; the [original difference](e0b2-difference.diff)
retains the six numerical serialization discrepancies.

The remaining pre-parse block was checked on the frozen Windows source tree:

- All 16 offline generator/test entries pass after the E0b2 correction: sky,
  stars, propwash, suspension/support references, MT8 data/intake and Monster Car 2.
- All six actual headless RCV entries pass: suspension CLI, support CLI,
  experiments, MT8 visual contracts and English/Spanish previews. Their shared
  checked-runner reports have zero engine errors/warnings.

[Verification](verification.json) links each result. Initial failed output is
retained alongside corrected runs. These are deterministic software checks;
they establish no physical, rendered-GPU or timing qualification.
