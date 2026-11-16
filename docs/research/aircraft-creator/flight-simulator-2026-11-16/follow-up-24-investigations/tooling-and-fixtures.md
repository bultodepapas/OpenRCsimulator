# Tool evaluation and fixture backlog

**Date:** 2026-11-16. **Status:** proposed engineering backlog derived from [24 investigations](README.md); no new dependencies installed, vendored or qualified. The [AC-FS plan](../../../../plans/flight-simulator-aircraft-import.md) owns implementation. Tool names below are candidates with defined jobs and limits, not a recommendation to install all of them.

## Reuse the existing OpenRC boundaries

| Existing capability | Proposed use | Boundary |
| --- | --- | --- |
| [Creator source importer](../../../../../app/workshop/creator/source_importer.gd), [GLB preflight](../../../../../app/workshop/creator/glb_preflight.gd), [PNG checks](../../../../../app/workshop/creator/png_check.gd) | Re-admit every normalized visual from owned bytes | New adapters cannot broaden the strict subset or bypass limits implicitly |
| [Placement](../../../../../app/workshop/creator/placement.gd), [visual parts](../../../../../app/workshop/creator/visual_parts.gd) | Scale, datum and confirmed rigid controls | Node indices are identities; names are labels and may repeat; local-axis/origin and overlap rules apply |
| [ClearView import plan](../../../../plans/clearview-aircraft-import.md) | Coordinate archive, cancellation, observation and storage contracts | Share bounded primitives only after versioning and regression review |
| [Blender bridge](../../../../../tools/blender/README.md) | Optional author workflow and small original visual fixtures | Separate environment/tool setup; no player install requirement |
| [Skin tools](../../../../../tools/skins/README.md) | Evaluate `glb_inspect.py`, `paint_audit.py` and render evidence for fixture inspection | Existing stock-paint utilities are prior art; they are not MSFS converters or proof of Creator admission |
| [Measurement reducers](../../../../TOOLS.md#aircraft-measurement-reducers) | Mass, inertia, thrust and video measurements for target RC evidence | Retain uncertainty, calibration, actual equipment and measurement conditions |
| [Flight logging](../../../../FLIGHT-LOGGING.md) | Exact configuration/input/backend identity, replay and comparisons | Preserve the numerical gate and stock baselines; source-simulator agreement is a separate result |

Do not add a second aircraft store, direct runtime source loader or alternative physical schema. Use the ordinary Creator definition/compiler/package and immutable saved-version contracts after their existing gates are satisfied.

## Candidate tools and adoption decisions

| Candidate | Useful role and priority | Scope / adoption proof |
| --- | --- | --- |
| **Khronos glTF Validator** | First external evaluation candidate: independent structured format diagnostics | Apache-2.0 project; pin executable/release and dependencies. Its supported extension set is finite; a standards-valid model can still be unsupported by Creator. Run bounded/offline. [R21](packages-and-tools.md#r21-interchange-and-validation-tools) |
| **Blender + Khronos glTF export** | Optional manual preparation of rigid self-contained GLB | Record application/exporter version, units, applied transforms and exact export settings. Prove output through Creator admission and visual/hinge fixtures. [R01/R04](visual-and-legacy.md) |
| **Asobo MSFS 2020 glTF Blender IO** | Optional authoring-source bridge | Separately licensed Apache-2.0 plugin; package-built glTF is outside its documented import scope. Match documented Blender/add-on versions. No SDK compiler dependency selected. [R01](visual-and-legacy.md#r01-source-and-compiled-gltf) |
| **DirectXTex / texconv** | Evaluate DDS decoding and intermediate PNG generation | Qualify codec, orientation, alpha, color and workspace separately from material semantics. Component/dependency review required before redistribution. [R02](visual-and-legacy.md#r02-dds-and-material-fidelity) |
| **glTF Transform** | Evaluate individual graph/material/texture transformations | MIT project; begin with explicit operations and a source-to-output mapping. Broad optimize/flatten/join presets can destroy later motion bindings. [R22](packages-and-tools.md#r22-optimization-and-moving-parts) |
| **meshoptimizer / gltfpack** | Evaluate bounded mesh reduction for prepared exteriors | MIT project; preserve groups, nodes, materials and UV evidence explicitly. Preservation flags alone do not prove fidelity. Quantization/compression extensions must be normalized into the actual Creator subset. [R22](packages-and-tools.md#r22-optimization-and-moving-parts) |
| **ModelConverterX** | Optional owner-authorized legacy preparation | Author-operated tool with documented export limitations; exact build and permissions matter. No bundled or automatic conversion promise. [R05](visual-and-legacy.md#r05-modelconverterx-preparation) |
| **msfsLegacyImporter / fs-parse** | Read-only prior art for migration diagnostics and dialect handling | Legacy Importer is not a universal FS9/P3D converter; AIR uses another dump boundary. No root license was established for fs-parse in the original inspection. No code adoption selected. [R06](visual-and-legacy.md#r06-legacy-mdl-and-air-dialects), [original assessment](../sources-and-examples.md#tool-assessment) |
| **Assimp** | General interchange comparator only if a concrete format need emerges | Its advertised `.mdl` examples include other applications/games; this is not evidence of an MSFS MDL decoder. Library, dependencies and non-BSD test assets have distinct terms. [R21/R24](packages-and-tools.md) |
| **glTF Asset Generator / Sample Assets** | Selected standards fixtures alongside original cases | Generator MIT; Sample Assets require per-model credit/license review. Valid broader glTF is often an intentional Creator refusal case. [R24](packages-and-tools.md#r24-regression-corpus-and-asset-rights) |
| **XFOIL / XFLR5** | Later low-Re section/wing modeling experiments | Inspected source notices are GPL-2.0-or-later; XFLR5 reference is historical v6.10. Select and review an actual build separately. Retain convergence, transition and separation limits. [R13](physics-and-calibration.md#r13-low-reynolds-tools-and-airfoil-data) |
| **OpenVSP / VSPAERO** | Later geometry and aerodynamic comparison | OpenVSP source uses NASA Open Source Agreement 1.3. Pin solver version and reference area/span/chord; upgrading project files can affect control references. [R13](physics-and-calibration.md#r13-low-reynolds-tools-and-airfoil-data) |
| **UIUC / APC data and PropDBTools** | Evaluate actual small-propeller curves | UIUC experimental data and APC predictions retain different evidence kinds. PropDBTools' BSD-2-Clause code license does not license underlying datasets. Pin propeller family, diameter, pitch, RPM, Reynolds number and data terms. [R14](physics-and-calibration.md#r14-propeller-datasets-and-operating-limits) |
| **FSTelemetry / Flight Recorder** | Optional source-behavior research references only | MIT / GPL-3.0 repository notices do not grant simulator/SDK rights. A default one-second CSV interval cannot support fast RC response claims; a replay is not independent measurement. [R17](physics-and-calibration.md#r17-telemetry-and-independent-validation) |
| **JSBSim** | Optional independent equation/normalization comparator | LGPL-2.1 project; verify selected law/data provenance. Another simulation is not physical RC ground truth. [R17](physics-and-calibration.md#r17-telemetry-and-independent-validation) |

The six exact source revisions inspected for the interchange/fixture tools are in the [revision record](packages-and-tools.md#tool-revision-record). Those hashes document research, not installed release pins. Review all transitive components and artifact terms at adoption. No SDK sample aircraft, package compiler or restricted benchmarking workflow is required for the initial product path.

## Proposed bounded tool experiment

1. **Freeze the question.** Select one original fixture, an exact candidate release/build, its license/dependencies, supported input profile and expected output. Record explicit byte, memory, pixel, process, thread and time budgets before the trial.
2. **Retain source identity.** Capture the selected closure once; record hashes, declared versus detected dialect, material roles and expected parts. Preserve the captured original. For optimizer fixtures use an independently inspectable reference; a large real source need not already fit Creator limits.
3. **Run explicit transformations.** Use a dedicated temporary directory, rooted read/write access, no network resolution or source code execution, bounded workers and cancellation. Record each operation, its inputs/outputs, tool version and diagnostics. A timeout produces a failed stage, not an incomplete artifact accepted as complete.
4. **Evaluate independent boundaries.** Compare standards diagnostics, final Creator admission, known geometry/UV/material samples, control poses and resource consumption. Test the material/hinge semantics even when a third-party validator returns no errors. For originals outside admission bounds, never send them directly to the runtime importer to create a reference image.
5. **Decide narrowly.** Accept one explicit profile only if its intended outcomes pass; otherwise retain the prepared-GLB route or a declared limited result. Record refused/unsupported cases. A successful experiment does not expand the advertised simulator compatibility matrix by itself.

The proposed recipe record belongs to AC-FS-02's common dependency/provenance design, not a new standalone runtime format. It needs captured source and output identities, tool/build and operation parameters, dependency/profile versions, bounded execution observations, diagnostic severity and stage outcome, known-answer references, manual choices and artifact permissions. Repeating a recipe must distinguish reproducible semantic output from byte identity when a tool inserts timestamps or other nondeterministic metadata. Only exact admitted bytes enter an immutable saved revision.

## Twenty-four concrete fixture proposals

All rows below are **planned**, not generated or run by this documentation change. The first layer uses independently authored tiny fixtures with explicit expected answers. Optional real-aircraft cases cannot become required CI until their complete dependencies and rights are established.

| Fixture | Investigation / mechanism | Required assertion |
| --- | --- | --- |
| F01 | R01: ordinary glTF versus unsupported processed encoding | Declared path/name does not determine admission; required feature refusal is precise |
| F02 | R02: asymmetric UV, normal, ORM and alpha swatches | Channel/orientation/color known answers fail under deliberate swaps/flips |
| F03 | R03: complete, reduced, empty and missing LODs | Selection compares a declared expected inventory; missing evidence yields unknown completeness |
| F04 | R04: rigid mesh/group hinges and transformed parents | Neutral/endpoints/midpoint match independent coordinates; overlapping bindings refuse |
| F05 | R05: author-prepared GLB with declared source-to-output inventory | Texture/control loss is reported against that inventory; unsupported source is not admitted directly |
| F06 | R06: legacy headers, truncated records and absent AIR | Header is only a dialect hint; absent/unread AIR does not invent coefficients |
| F07 | R07: base, patch and changed base | Every effective value has provenance; removed patch values do not become guessed defaults |
| F08 | R08: cross-file system reference and competing mod | Missing source dependency stays visible without executing gauges or importing cockpit systems |
| F09 | R09: asymmetric engine/datum/CG landmarks | One recorded transform applies to geometry and physical proposals; final RC inventory owns CG |
| F10 | R10: payload versus water-ballast declaration | Source semantics are retained; unsupported ballast/tow/flex cannot authorize RC flight |
| F11 | R11: declared two-blade geometry and three-blade physics | Discrepancy remains explicit; target installation must be selected and confirmed |
| F12 | R12: readable CFG plus custom engine-control dependency | Source report cannot claim the complete flight behavior from CFG alone |
| F13 | R13: low-Re polar plus nonconverged/missing samples | Domain, solver and missing data survive; no extrapolated stall truth is silently created |
| F14 | R14: propeller curve, changed RPM and stopped shaft | Recompute advance ratio, respect family limits, and avoid division by zero |
| F15 | R15: pilot curve, actuator and surface trace | Distinct signals and signs expose double-applied expo/effectiveness |
| F16 | R16: identical `point.N[9]` under two compression modes | Ratio and feet decode differently; source ground tuning does not become a target spring law |
| F17 | R17: irregular timestamps, jitter and dropped samples | Trace reports insufficient temporal evidence instead of a fast-response fidelity claim |
| F18 | R18: legacy field magnitude/sign/autopilot roles | Role-specific active/unused/unknown status replaces blanket field removal |
| F19 | R19: common source, two attachments and two presets | Independent expected merge/reindex/rebind/transform results, unresolved forms diagnosed |
| F20 | R20: identical texture names with different bytes | Liveries remain isolated; missing base and model override are distinct outcomes |
| F21 | R21: standards-valid skin versus malformed accessor | Valid-but-unsupported differs from invalid; neither bypasses Creator preflight |
| F22 | R22: optimizer merges a rudder, renames nodes or changes UVs | Source correspondence detects semantic loss despite standards-valid output |
| F23 | R23: old/new source plus authored mass and renamed hinge | Manual values persist, conflicts are explicit, stale bindings invalidate, old revision survives |
| F24 | R24: valid saved definition paired with unrelated valid physics | Hash consistency alone cannot pass definition-to-physics correspondence |

Add the original plan's capture races, archive/path/case/Unicode ambiguity, expansion limits, cancellation, unavailable dependencies, persistence and packaged-target cases to this corpus; the table above extends that baseline. Each case should record input origin and permissions, exact revisions, tool recipe, expected stage outcomes, budgets, independent oracle and the owning AC-FS work package. Full-aircraft tests then compose these capabilities without replacing the smaller diagnostics.

## Numerical checks that make useful fixtures

These are mathematical examples, not new simulation results:

- With `V=10 m/s`, `D=0.25 m` and `n=100 rev/s`, `J=0.4`. Doubling `n` at fixed `V` gives `J=0.2`; assuming unchanged coefficients without consulting the new operating point is unjustified. At constant coefficients the dimensional factors alone are four for thrust and eight for power.
- A pitch of 4.7 inches at 6,500 RPM gives ideal geometric pitch speed `4.7 × 0.0254 × 6500 / 60 = 12.9328 m/s`; it is not the aircraft's achieved speed or a measured propeller curve.
- Moving 0.20 kg through 0.50 m within a 2.0 kg aircraft shifts total CG by 0.05 m if the other components remain fixed. Battery charge depletion does not remove that battery's mass under the existing closed-battery model.
- A source contact compression value `0.4` means a ratio when `set_max_compression=0`; when the documented mode is `1`, the same number is `0.4 ft = 0.12192 m`. Test the actual conditional tuple schema rather than infer from magnitude.

The source semantics and qualifications are in [R14–R16](physics-and-calibration.md); the [conversion specification](../conversion-and-scaling.md) remains authoritative for the proposed mapping. Physical claims still require the existing numerical campaign and independent target measurements.
