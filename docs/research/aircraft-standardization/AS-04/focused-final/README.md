# AS-04: Final focused contract checks

2026-10-11 · Prefix: AS-

**Status: Passed.** The live v2 schema/loader harness and focused Godot contract tests completed with no failures.

The 62-case v2 harness on `app/` reported 60 expected schema/loader agreements and two intentional schema-pass/runtime-fail coupled constraints: the existing reference-area relation and the inverted all-zero-steering gear topology. All eight fleet positives and both v1 compatibility cases passed. Its JSON report and console log are retained in [AS-01](../../AS-01/schema-v2-loader-agreement.json) and [the matching log](../../AS-01/schema-v2-loader-agreement.log).

`test_aircraft_contract.gd` passed 1,906 checks; `test_aircraft_render_contract.gd` passed 170. The GP wheel-profile alignment is consistent: `load_file()` applies the same separate profile after either numeric derivation, while the contract test applies it to the explicit v1-derived model before comparing. The comparison retains wheel parameters and profile provenance, excluding only v2 identity metadata. No GP solver change was made. The contract test log contains the existing Jyy inertia data-quality warning and no script error. The runtime gear relation requires at least two contacts aft and one ahead of the plan CG for tricycle gear, and the inverse counts for taildragger modes; steering remains independent.

The offline combustion propeller range-audit compatibility update is documented in [its AS-04 note](range-audit-v2-compatibility.md), with its own [focused log](range-audit-v2-compatibility.log).

The synthetic authoring template passed offline structural validation and the production Godot file loader with no errors: [loader result and exact template hash](template-loader.json), [engine log](template-loader.log). This proves a usable shape/example, not physical calibration. The full suite's five stale battery diagnostic assertions were updated to the v2 error paths while retaining v2 inputs; all 67 checks passed natively and in the Linux continuation ([native log](test_electric_battery_data.log)).

See [provenance](provenance.json) for the pinned Godot version, source hashes, commands, and results; the two test logs are in this directory.
