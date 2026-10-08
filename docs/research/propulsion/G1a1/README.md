# G1a1 — Preserve source identity before building propeller tables

2026-10-08 · **Status: implemented and verified.** Offline import tooling only. G1a matched Sport 12×6 measurements and VAL-7 remain open.

## Change and finding

The [importer](../../../../research/propulsion/uiuc-import/README.md) turns an identified static or tunnel file into sorted, unique float64 knots with original source-line provenance. It rejects malformed rows, conflicting duplicate coordinates, float64 coordinate collisions and exact-byte hash mismatches. It preserves signed coefficients and separates a static source RPM column from a tunnel run label. Unknown coefficient-reference diameter and per-row tunnel RPM remain null. It performs no interpolation, fitting, extrapolation, force conversion or aircraft-data writes.

The source review confirmed a concrete normalization hazard: the APC Thin Electric 12×6 tunnel file ends with J=0.653931 followed by J=0.653026 repeated seven times. Removing only duplicate final rows still leaves decreasing J. Whole-file exact-decimal deduplication followed by explicit sorting produces 18 knots from 24 rows, preserving every original row number. Different values at the same coordinate are refused; silently averaging a repeat would introduce an unreviewed data-reduction decision.

A file hash establishes byte identity, not whether the manifest's propeller family, diameter or measurement claims are true. Four primary URLs and their listing context were inspected; the pinned readback retrieves those URLs independently and checks their hashes. Sport 11×6 and Thin Electric 12×6 are kept distinct from the simulator's Sport 12×6. No importer result closes that mismatch or validates higher RPM operation.

## Verification

[18 tests](tests.log) cover parser schemas, signed values, exact decimal duplicates, backward source order, original line numbers, conflicts hidden by binary rounding, float64 collisions/overflow/underflow, unknown diameter/RPM, strict metadata, byte identity and deterministic/refusing CLI behavior. [Five source mutations](mutations.json) fail their intended assertions: bypassed hash, ignored conflicting repeat, omitted sorting, invented tunnel RPM and ignored float64 collision. All mutations run on temporary copies; the copied unmodified control passes.

[Primary-source readback](source-readback.json) accounts for **74 rows** and preserves their numeric cells exactly. The [synthetic result](example-result.json) demonstrates output shape without redistributing the external datasets.

| Source | Rows → knots | Coordinate extent | Reordered |
| --- | ---: | --- | --- |
| Sport 11×6 static rd0488 | 16 → 16 | 1,752–6,259 RPM | No |
| Sport 11×6 tunnel rd0495, label 6000 | 20 → 20 | J 0.373–0.788 | No |
| Thin Electric 12×6 static 0629od | 14 → 14 | 1,046.667–7,546.667 RPM | No |
| Thin Electric 12×6 tunnel 0635od, label 6044 | 24 → 18 | J 0.333913–0.653931 | Yes |

Both tunnel RPM extents remain unknown. All four coefficient-reference diameters remain unknown in these imports; no catalogue diameter is substituted. These are source coordinate extents, not continuous coverage or uncertainty bands.

[Verification manifest](verification.json): all 18 tests and five mutations pass again in a fresh git clone with only the owned files overlaid. The synthetic CLI report is byte-identical. A second download into an empty external directory reproduces all four pinned hashes and the 74-row readback exactly. [Fresh-clone tests](fresh-clone-tests.log) · [Mutations](fresh-clone-mutations.json) · [Independent refetch/readback](fresh-clone-readback.json).

A Luna Max subagent reviewed the implemented parser, numerical identity rules, metadata and CLI. It found no material blocker and emphasized that manifest origin/applicability remains declared metadata; primary-source readback is separate evidence. No runtime code or dependencies changed, so this step requires no new full Godot suite.

## Primary sources and limits

- [UIUC Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html), Sport family listing and static/tunnel format context. [Static file](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_static_rd0488.txt); [tunnel file](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_rd0495_6000.txt).
- [UIUC Volume 4](https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html), Thin Electric family and coefficient-reference diameter caveat. [Static file](https://m-selig.ae.illinois.edu/props/volume-4/data/apce_12x6_static_0629od.txt); [tunnel file](https://m-selig.ae.illinois.edu/props/volume-4/data/apce_12x6_0635od_6044.txt).

Sources checked 2026-10-08; exact hashes are in the [source manifests](../../../../research/propulsion/uiuc-import/sources.json). Raw files and complete normalized source tables stay outside the repository. Source uncertainties, full RPM/J coverage, coefficient diameter resolution and matched intended-propeller evidence remain follow-up work. Existing G1b1 audit coverage is unchanged.

Ready-to-paste commit message:

```text
G1a1: import identified propeller source knots without inventing coverage

Proof: 18 parser/precision/CLI tests, five rejected mutations and 74
row readbacks across four pinned UIUC sources. Fresh-clone tests and
independent downloads reproduce identical reports. Preserve unknown
diameter/tunnel RPM; runtime/data unchanged, matched G1a remains open.
```
