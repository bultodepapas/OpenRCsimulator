# AE-12/13 — measured component mass and balance

**Date:** 2026-10-19  
**Status:** Fixed-station measured-mass editing, source-state mass/CG checks, and a derived one-component inverse proposal are implemented. Component movement, added ballast, mount matching, and physical acceptance remain open.

## Implemented boundary

The mass editor accepts an `openrc-aircraft v2` source only when its complete authored physical-identity inventory resolves. A direct edit is exactly `{id, mass_kg, source}` and addresses the stable inventory ID, not a display name or array index. The mass must be finite and within the v2 inventory bound `[0.001, 5.0] kg`; the required measurement description is nonblank, at most 256 characters, and has no control characters. At most 32 component records can be edited together. Unknown, duplicate, stale, virtual reference-build, and finite-liquid-fuel IDs refuse the whole operation.

Stations, component dimensions, source balance plan, fuel definition, and geometry remain fixed. The loader is the final validator and recomputes total mass, the inventory CG, and all six stored inertia terms. When the inventory CG shifts, CG-relative propeller/turbine thrust and intake offsets are re-referenced so the existing structural locations remain fixed; source LE-frame slipstream points are preserved. No mount envelope or physical hardware replacement contract exists yet, so the editor cannot move a component, add ballast, or claim that an available inventory row matches a replacement part.

The read-only mass/CG report and inverse proposal require the source-declared weighing state. `empty_tanks` excludes only the authored finite-liquid and feed-line IDs; `as_inventory` is accepted only when there is no finite liquid fuel. The report uses x aft, y right, z up in metres and the source `balance.cg_tolerance` for each CG axis. It reports mass residual without inventing a mass tolerance.

The optional inverse solve holds all stations fixed and solves one selected component mass from observed total mass. It rejects proposals outside the schema mass range, source plausibility mass range, selected weighing-state membership, observed CG tolerance, or authored `balance.plan_cg` tolerance. A successful result is a loader-checked `kind: derived` proposal with `applied: false`; it is not stored as a component measurement.

## Numerical basis and evidence

For inventory component masses `mᵢ` at LE-frame positions `rᵢ`, the report uses `M = Σmᵢ` and `CG = Σ(mᵢrᵢ)/M`. The fixed-station proposal uses `mₖ = M_observed − Σᵢ≠ₖmᵢ`, then checks the resulting three-axis CG. The FAA handbook describes datum/station arms and component moments (`weight × arm`); NASA Glenn presents the center-of-gravity weighted integral and its numerical-sum interpretation. [FAA Pilot’s Handbook of Aeronautical Knowledge, ch. 10](https://www.faa.gov/sites/faa.gov/files/12_phak_ch10.pdf), [NASA Glenn, Center of Gravity](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/center-of-gravity/).

The aircraft loader computes each inventory box’s centroidal inertia plus its parallel-axis contribution in the body FRD frame. The backend test independently builds all nine tensor cells from `m((r·r)I − rrᵀ)` plus each box’s intrinsic inertia, then compares the six stored entries without calling the loader’s inertia helper. The axis conversion and point-mass/parallel-axis terms are consistent with the documented structural frame and implementation in [JSBSim `FGMassBalance`](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGMassBalance.html). This is a software cross-check, not a physical inertia measurement.

The native fixture uses the Jensen Das Ugly Stik 60 source (`jensen-das-ugly-stik-60`). It stages a synthetic `+0.0001 kg` engine-mass delta (`0.5500 → 0.5501 kg`) with an explicitly marked software-only source description. This is not a scale reading. The frozen trial records compiler `openrc-aircraft-workshop-v1-measured-mass-1`, base SHA-256 `5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007`, and resolved-model SHA-256 `93adc60709e85b42100a4d1c733902c4023715b58a3482025d3a79713a1847e3` in the comparison artifact.

| Result | Before | Synthetic measured-mass candidate |
|---|---:|---:|
| Total mass | 2.8786621384 kg | 2.8787621384 kg |
| CG, LE frame `[x aft, y right, z up]` | `[0.1093924374, 0, 0.0002083760] m` | `[0.1093807868, 0, 0.0002083687] m` |
| Inertia `[Jxx, Jyy, Jzz, Jxy, Jxz, Jyz]` | `[0.1157352479, 0.3692385128, 0.4661175402, −0.0095400000, 0.0073651028, 0.0005484989] kg·m²` | `[0.1157353521, 0.3692499279, 0.4661288928, −0.0095400000, 0.0073650958, 0.0005484989] kg·m²` |

The native capture exercises the actual Workshop modal, safe-default Cancel focus, Cancel without mutation, a dirty-field selection-change guard, stable-ID staging, full compiler acceptance, creation of a new draft from a saved legacy record, preservation of that original record, one Undo/Redo entry, and exact `Trial.freeze` identity. It uses isolated temporary variant/recovery roots and removes them after recording evidence.

| Capture | Native result |
|---|---|
| English, 1920×1080, text 100% | [Workshop PNG](native/workshop-en-1920x1080.png), [dialog PNG](native/measured-components-en-1920x1080-text-100.png), [JSON](native/capture-en-1920x1080.json), [log](native/capture-en-1920x1080.log) |
| Spanish, 1280×720, text 200% | [compact preview PNG](native/workshop-es-1280x720.png), [dialog PNG](native/measured-components-es-1280x720-text-200.png), [JSON](native/capture-es-1280x720-text-200.json), [log](native/capture-es-1280x720-text-200.log) |

Each native capture passes 28 assertions on Windows with Godot 4.7.2 and OpenGL Compatibility on an NVIDIA GeForce RTX 3090. The full-model side views project 143,770 mesh vertices inside their preview frames. At Spanish 200%, the capture enters Workshop’s compact preview mode to show the full aircraft. The modal’s initial view includes the component selector, source mass, mass label/input, Cancel, and Apply; measurement source and analysis actions remain reachable through vertical scrolling. Both footer actions stay within the modal and window. The dialog suite also tests Spanish text and 200% layout.

Focused verification: `test_workshop_mass_edit.gd` — 66 checks; `test_workshop_mass_ui.gd` — 21 checks; `test_workshop_mass_recipe.gd` — 39 checks. Together these cover stable-ID reorder/rename resolution, no-op and source immutability, exact schema bounds, fuel/virtual-mass refusals, impossible targets, independent tensor values, and fixed structural locations on Stik, P-51, Avanti turbine, and Timber electric records. The recipe suite covers immutable Store/Bundle paths, compiler identity, actual airborne and runway session qualification, and a 60-tick software fixed-tape run. The native capture runner is [`capture_mass.gd`](../../../../research/aircraft-editor/capture_mass.gd); each JSON file retains the current mass backend, dialog, compiler/trial, loader, identity, test, rendering, and capture-helper SHA-256 records.

## Limits and next gates

The current capture and flight checks are software verification only. No aircraft was weighed, no CG or inertia was measured, and no physical flight acceptance was performed. Existing source provenance may remain estimated/manual; entering a measurement description does not upgrade other quantities or validate the fixture value. The current entry form records only mass and a bounded description; date, instrument calibration, uncertainty, component serial/part identity, and evidence attachments belong to the future guided-measurement work.

AE-12b still needs a source-pinned mount/hardware contract before any move or ballast operation can be enabled. AE-13b still needs richer measurement provenance and a reviewed measurement-to-source workflow. Any future evaluator must preserve explicit fuel ownership, fixed source stations unless authorized mount data exists, source plan CG, and physical acceptance as a separate gate.
