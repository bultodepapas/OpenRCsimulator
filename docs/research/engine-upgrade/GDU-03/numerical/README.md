# GDU-04: frozen cross-engine numerical comparison

2026-10-25, Windows x86-64. Official Godot 4.7.2
`ed1daf0bf` and official 4.8-beta1 `4d10419ca` produce **byte-identical**
results in this bounded comparison. The production simulation sources, accepted
aircraft data, golden records and `.orfl` compatibility contract were not edited.

| Check | Result |
| --- | --- |
| Nine fixed-wing aircraft × calm/turbulent weather | All 18 cases identical, 960 accepted ticks and 961 rows per case |
| Compared numeric trajectory streams | 9,625,376 bytes per engine identical |
| Five seeded PCG32 streams | All 20,480 words and their advancing 64-bit RNG states identical; both engines also match the existing independent Python recurrence |
| Five seeded OU turbulence streams | Initial samples and 20,480 updates identical, including float64 samples and RNG state |
| Imports and numerical probes | All four checked invocations passed, zero errors/warnings |
| Comparator negative controls | Four tests passed: equality, signed-zero difference, exact int64 divergence and truncated-stream rejection |

The aircraft are Jensen Das Ugly Stik 60, its three finite-fuel glow variants,
Extra 300S .60, P-51D Mustang 120, Avanti S A200 P100RX, Turbo Lumber Evolution
and F4U Corsair 250. The experiment uses normal session setup, then restores the
same baseline checkpoint in both engines and applies the same frozen downstream
command tape. It compares every accepted body/previous/auxiliary/continuous state,
input, discrete mode and load. [Tool and command](../../../../../research/engine-upgrade/gdu04/README.md).

The copied dependency closure has 248 files from the experimental worktree at
`a6c2ce38a80a44327392367520c828b42ba0acda`. Both engine snapshots use the same
exact bytes. The [source manifest](source-manifest.json) records them;
[comparison and execution identities](comparison.json) retain engine hashes,
case hashes, frozen checkpoint/tape hashes, checked invocations and the root audit.
Full streams, copied projects and raw logs remain outside Git under
`D:/OpenRCsimulator-experiments/gdu04-numerical-20261025/`.

The root audit found all 99 included simulation/physics/failure/input scripts and
all 18 copied aircraft physical JSON files equivalent after LF normalization;
the tested fixed-wing physical JSON files match exact bytes. Raw checkout
differences are line endings. Eleven other JSON files differ in presentation,
authoring or importer provenance: customization, four aircraft model manifests,
five Workshop presentation manifests (four Stik and one Timber), and the
power-insulator Godot version.
Those differences do not change the numeric fixture. This evidence precedes the
planned Timber 4.8 import-measurement provenance regeneration and does not qualify
that later importer result.

The [follow-up provenance audit](../imports/README.md) verifies the later
Timber/insulator version-only regeneration and rechecks all 117 numeric input
files against current root and the frozen full-suite tree. The historical
comparison and its original identities remain unchanged.

The [final-core rerun](final-core/README.md) repeats the comparison after the
math-boundary and invalid-start corrections. All 28 final output streams match
both original engines' outputs byte-for-byte.

The initial attempt completed both engine probes but failed in Python analysis
because the existing wind oracle imports sibling modules. Adding its directory
to the research runner's import path resolved analysis; `--compare-only` reused
the completed outputs after checking source/probe hashes and invocation status.
The engine executable hashes are therefore explicitly recorded as measured at
analysis time. No successful simulation run was repeated or its output rewritten.

This supports GDU-04a/b only for these four-second frozen trajectories and seeds.
It does not establish all maneuvers, ground-contact transitions, helicopters,
trucks, other platforms, trim-solver equivalence or performance qualification.
It is separate from **GDU-04c**: a 4.7.2 `.orfl` still requires its original engine
identity for exact replay; no cross-version replay claim is made. Physical
validation and the remaining [upgrade gates](../../../../plans/godot-4.8-upgrade.md)
remain separate.
