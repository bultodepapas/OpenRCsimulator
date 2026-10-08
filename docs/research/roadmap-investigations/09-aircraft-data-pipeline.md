# 09 — Aircraft configuration, data schema and the geometry-to-physics pipeline

**Status:** research knowledge base, 2026-10-06. **Serves:** every aircraft track (Ugly Stik D1/D1-R1, Extra EX-05/06/09, Avanti AV-05/06, P-51 P51-05/06/11/12), Gate F follow-ups (E0a/E0b local surfaces), M4 G2/G4 (shaft, fuel), the `openrc-aircraft` format's evolution v1 → v2, menu/catalog (UI-05), future user-made aircraft. Cross-cutting: registered step prefix `DATA-` (the original research tables below used `X-DATA-`). **Read with:** [aircraft_data.gd](../../../app/physics/aircraft_data.gd), [aircraft_catalog.gd](../../../app/app_state/aircraft_catalog.gd), [test_aircraft_data.gd](../../../app/tests/test_aircraft_data.gd), [Extra derivation](../../../research/extra-300/ex05/derivation.md), [P-51 derivation](../../../research/p51/p51-05/derivation.md), [Extra integration audit](../extra-300-integration-audit.md), [Avanti integration audit](../avanti-s-integration-audit.md), [extra-aircraft-tooling 11–12](../extra-aircraft-tooling/10-12-inspection-loading-aero.md) (ResourceLoader, XFOIL/AVL), [RESEARCH.md](../../../RESEARCH.md) ("JSBSim is a physics component…", "glTF is a candidate interchange format…", "Community aircraft packages and format evolution").

## Current execution policy — audit reconciliation, 2026-10-06

[ROADMAP revision 5](../../../ROADMAP.md#execution-order-and-release-gates) supersedes the mandatory v2/unified-tool proposals below. The detailed code counts, aircraft table and uncommitted-work notes are a **pre-integration snapshot**, not the current catalog. P-51 shaft/slipstream and Avanti turbine are committed; four aircraft load. [DATA-1](../aircraft-validation/DATA-1/README.md) adds the P-51 geometry build, runtime compile and physics/report derivation checks to CI; five stale-copy cases verify failure in an isolated clone.

- [D1-R2](../aircraft-validation/D1-R2/README.md) applies the shared finite numeric/provenance table contract to shaft power curves. Ground-support validation remains D1-R3; do not infer that every nested field has been exhaustively tested.
- [DATA-2a](../aircraft-validation/DATA-2a/README.md) bounds the existing 801-point stall search without changing sampled extrema or solved angles. Full loader-call medians improve from 121–124 ms to 13.9–15.8 ms across four aircraft with warm OS file caches. DATA-2's 15 ms fleet target remains open; this is behavior preservation, not independent stall calibration.
- [C7-R2](../trace-integrity/C7-R2/README.md) identifies configured physics and recording-start auxiliary state. [DATA-3](../aircraft-validation/DATA-3/README.md) adds exact-byte aircraft input identity in metadata v2, separates the legacy rounded semantic hash, and verifies saved input files. C7-R2 v1 needs an explicit archival reader option; unversioned headers remain unsupported.
- Extract proven duplicated helpers incrementally (DATA-5). Preserve independent aircraft derivations and generated-output checks.
- DATA-8 requires a concrete consumer that v1 cannot represent cleanly. H8 state ownership, PT2, additional v1 aircraft and per-strip polars do not depend on a component-tree migration.
- The v2 sketches, mass shapes, packages and solver ideas below remain research options. Choose a bounded consumer before turning an option into required architecture.

## Summary (original research snapshot)

- **v1 works and is strict:** every number is `{value, unit, kind, source}`, one fixed unit per field, per-field ranges, sign rules for a statically stable airplane, and cross-checks (span × c = S, fin derivatives = fin force × arm, inventory CG = flight CG, gear ω·dt < 0.1). Keep this contract in v2; it is the project's best asset.
- **v1 encodes one airplane shape:** one trapezoid wing (3 strips per side), exactly one horizontal and one vertical tail, three named controls (aileron/elevator/rudder), one engine + one propeller, a fixed list of 33 whole-aircraft derivatives. V-tails, elevons, flaps, retracts, twins, biplanes and gliders cannot be described without new code paths.
- **v1 is already growing by optional keys** (uncommitted work in the tree on 2026-10-06: `propulsion.kind` = `glow_prop|turbine`, `shaft`, `thrust_angles`, `normal_force`, `slipstream.pieces`, signed tail-wheel steering). That is the right migration style; v2 should formalize it, not replace it.
- **Established simulators split the same way** (reference, mass with shaped point masses, aero, reusable propulsion parts, contacts, control components) and use two aero philosophies: coefficient oracle (JSBSim, CRRCSim, Gazebo AdvancedLiftDrag, our v1) vs geometry elements (X-Plane, YASim, Aerofly, PicaSim, our post-Gate-F local surfaces). v2 = **geometry component tree as authority + whole-aircraft derivatives as an optional validation oracle**.
- **The geometry → physics pipeline exists twice** (`research/extra-300/ex05/derive_physics.py`, 549 lines; `research/p51/p51-05/derive_physics.py`, 683 lines) with copied helpers, and each `geometry.json` has its own ad-hoc schema. Unify into one tool with a shared geometry schema; AVL (GPL, run offline, never bundled) as an optional backend.
- **Load cost is dominated by one solver, not JSON:** measured on the dev VM, JSON parse 0.6–1.0 ms per file (35–42 kB), `validate_and_derive` 110–119 ms, of which ≈111 ms is the stall-start bisection (`_envelope`). Irrelevant for 3 aircraft; 5–6 s for a 50-aircraft mod list. Fix before mods.
- **Mass/inertia:** inventory boxes + parallel axis are right; add JSBSim-style shapes (tube, cylinder, sphere, ball). The Stik's inventory gives Jyy 2.11× the m·b²-scaled UltraStick25e value (loader warning, measured today); D10 already flagged Iyy. Measure one real airplane (bifilar pendulum) before trusting inventories.
- **Variants as overlays:** RFC 7396 merge patch works only on objects, so v2 must key components by ID (objects, not arrays). CG/fuel/prop variants become small patch files, validated after resolution.
- **Mods:** JSON + glTF only, under `user://aircraft/<id>/`; never `.tres/.res/.pck` from users (embedded scripts execute on load; packs replace `res://` paths by default). License metadata per layer: data, model, livery.
- **Schema tooling:** JSON Schema 2020-12 for editor IntelliSense and CI; the GDScript loader stays the authority (physics rules a schema cannot express). Test that both reject the same mutations.

## Code snapshot before aircraft integration

**Loader** ([aircraft_data.gd](../../../app/physics/aircraft_data.gd), 565 lines committed; +195 uncommitted lines from AV-05/P51-06/12 at writing time):

| Area | v1 behaviour (committed) | Limit it imposes |
| --- | --- | --- |
| Format gate | `format` must equal `"openrc-aircraft v1"` exactly | No version negotiation or migration path |
| Quantity | `_q(path, node, unit, lo, hi, size)`: exact unit string, kind ∈ {manual, measured, borrowed, estimated, derived}, non-empty source, finite, range | Units are non-ASCII strings (`kg·m2`, `N·s/m`, U+00B7); no conversion; compound table units appear ad hoc (`"rpm, W"`, `"N·m, N·m/krpm"` in the uncommitted shaft code) |
| Reference | `wing_area`, `wing_span`, `mean_chord` (= S/b, ±1 %), `aero_reference_point`, `planform` rectangular/tapered (root/tip) | One trapezoid; MAC lives only in evidence text |
| Balance / inventory | `plan_cg`, `firewall`, `cg_tolerance` (≤ 5 mm); items `{name, mass ≤ 5 kg, position ±2 m, size box}`; CG and inertia derived; inventory CG must equal plan CG per axis | Single configuration; item mass cap 5 kg; only boxes |
| Plausibility | `mass_range`, `inertia_reference` (UltraStick25e scaled by m·b²) → warnings at 0.5–2× | One reference airplane for every class |
| Aero | 33 fixed coefficient names with sign rules; `envelope` (CL_max/min, blend width, CD90, sideslip blend; stall start solved by bisection); `surfaces` (horizontal, vertical, limits) with exact fin consistency (1e-8) | One fin, one stab, three strips per side (`WING_STATIONS_PER_SIDE = 3` in [aero.gd](../../../app/physics/aero.gd)) |
| Propulsion | engine (max static rpm 1k–50k, idle, lag, peak power) + propeller (D, offset, rotor inertia, Ct(J)/Cp(J) tables) | One engine, one prop (turbine branch in progress) |
| Controls | `max_throw.{aileron, elevator, rudder}` 1–60°, one `servo_full_throw_time` | No flaps, gear, throttle curve, mixes, per-servo rates |
| Ground | `crash_hull` (≥ 4 points) required; `landing_gear` optional (≥ 3 contacts, ω·dt < 0.1, ζ 0.05–2, tyre friction) | Point springs only: no floats, skids, retract state |
| Identity | `id`, `data_sha256 = sha256(JSON.stringify(raw, "", true))` | Hash of a re-serialization without `full_precision`, not of the file bytes (see Pitfall 6) |

**Data files** (all committed, all load; counted today):

| File | Origin | kinds (manual/measured/borrowed/estimated/derived) | Mass | Gear |
| --- | --- | --- | --- | --- |
| [jensen_ugly_stik_60.json](../../../app/data/aircraft/jensen_ugly_stik_60.json) | hand-authored (D1, D1-R1, E1/E2) | 9 / 0 / 37 / 85 / 13 | 2.885 kg, 20 items | tricycle |
| [gp_extra_300s_60.json](../../../app/data/aircraft/gp_extra_300s_60.json) | generated by `ex05/derive_physics.py` | 9 / 11 / 7 / 59 / 51 | 3.364 kg, 22 items | hull only |
| [p51d_mustang_120.json](../../../app/data/aircraft/p51d_mustang_120.json) | generated by `p51-05/derive_physics.py` | 4 / 8 / 5 / 86 / 55 | 18.209 kg, 29 items | hull only (retracts as mass) |

**Pipeline.** `source.json` (P-51 only) → `build_geometry.py` → `geometry.json` → `compile_geometry.py` → `app/aircraft/*_geometry.gd` (visual, generated, `--check` for staleness) and, separately, `derive_physics.py` → `app/data/aircraft/*.json` + `derivation.md`. Facts:
- Each `geometry.json` has its own keys (Stik: `equipment`; Extra/P-51: `gear`, `propeller`, `spinner`; Avanti: `schema`, `revision`, `controls_deg`, `installation`). Shared: model axes nose −Z, right +X, up +Y, metres, an `evidence` map.
- Three frames coexist: model (−Z nose, +X right, +Y up), physics LE frame `[x_aft, y_right, z_up]` from the wing LE at the centreline, body FRD about the CG. The loader converts LE → FRD in `inertia_about`, `_hull_body`, `_landing_gear`.
- Both derive scripts read the Stik JSON (Extra copies the O.S. .61FX engine and APC 12×6 tables; P-51 copies conventions and local-surface limits): editing the Stik makes both outputs stale. This is an implicit library dependency.
- Duplicated helpers: `note`, `q`, `shoelace`, `helmbold`, `flap_tau`, `station_centres`, `check_consistency`; P-51 adds `bem_tables` (blade-element/momentum prop), `thrust_at`, `drag_at`.
- CI ([ci.yml](../../../.github/workflows/ci.yml)) runs `--check` for the Stik/Extra/Avanti geometry compilers and the **Extra** derivation; the P-51 `build_geometry`, `compile_geometry` and `derive_physics` checks are **not** in CI (`test.sh` runs only the P-51 `compile_appearance --check`). Today `p51-05/derive_physics.py --check` reports `derivation.md` stale because another track's uncommitted edit adds slipstream/gear rows — expected mid-step, but CI would not have caught it after commit.
- `test_aircraft_data.gd` exercises **only the Stik** (43 mutation rejects plus direct checks); Extra/P-51 are covered by their own handling tests and verify scripts.

**Catalog** ([aircraft_catalog.gd](../../../app/app_state/aircraft_catalog.gd)): ID → name, summary, status (flyable / experimental / preview), data path; visual builder resolved by `render/airplane.gd`. Hard-coded `ENTRIES` const: no discovery, no user folder.

**What is missing for the next tracks:** flap/gear commands and actuators (P51-11, Avanti), multi-surface tails (V-tail, twin fins), mixers, multiple power units, configurations/variants (fuel, CG, prop), airfoil/Re data per section, a shared geometry schema, a version migration path, a user aircraft folder, license fields.

## Theory and models

### How established simulators describe an aircraft

| Simulator | How an aircraft is described | Lesson for us |
| --- | --- | --- |
| **JSBSim** (LGPL 2.1) | XML `fdm_config`: `fileheader` (author, `license`, `reference`, `limitation`), `metrics` (S, b, c, `AERORP`, `VRP`), `mass_balance` (Ixx…Iyz, `emptywt`, `pointmass` with `form shape=tube/cylinder/sphere/ball`), `ground_reactions` (`contact` BOGEY/STRUCTURE, spring/damping/rebound, friction, `max_steer` 360 = caster, `brake_group`, `retractable`), `propulsion` (engine/thruster in reusable files, tanks), control channels (gain, summer, `kinematic` traverse position/time, PID), `aerodynamics` (6 axes, each a sum of `function` = `product` of properties and `table`s). `unit=` per element, converted at load [1–8] | Units on every number; reusable part files; kinematic actuators; header with license and limitations; aero as data |
| **Aeromatic** | Full JSBSim model from type, weight, span, length, engines; inertia from Roskam formulae then ×1.5 "to enhance control response feel" [9,10] | A generator that tunes feel destroys provenance |
| **YASim** (FlightGear) | Geometry elements + `approach`/`cruise` targets; a solver adjusts drag, lift and elevator incidence until both trim [11,13]; raising power makes it "reduce lift and increase drag so that your specified cruise speed will still be met" [12] | Targets are checks, never fitting knobs |
| **X-Plane** | Blade element: wings, stabs, props in ≤ 10 elements per side; 2-D airfoil data corrected for AR, taper, sweep [14] | Same idea as our post-Gate-F strips; airfoils as separate data |
| **CRRCSim** (GPL 2) | `CRRCSim_airplane version="2"`: multilingual `description`, `changelog`, `aero` derivatives (CL_a, Cm_q, CD_CLsq…), several `config` blocks (mass_inertia + aero overrides + power), `wheels` (spring, damping, `max_force` = crash, brake, steering mapping), `launch` presets, elevon "delta-mix"; `units` 0/1 per section [15]; electric chain battery → shaft (J, folding brake) → DC motor (k_M, R_I, I₀) → gearbox → propeller [16] | Closest RC precedent: oracle + variants + electric chain + launch presets |
| **PicaSim** (PolyForm NC, ideas only) | `Aeroplane.xml` aerodynamic blocks, wheels, hinge points; shared aerofoil files; x fwd, y left, z up [17] | Component tree + airfoil library |
| **RealFlight / Accu-RC** | In-app "Edit Aircraft" for physics only (meshes from 3-D tools) [18]; Accu-RC "workbench" adds/changes servos, blades, motors, avoiding "guessing parameters that don't relate to real life modelling" [19] | Editor UX built from real RC parts |
| **Aerofly** | `.tmd`: rigid bodies, joints, aerowings/fuselages with stations, actuators, engines; dynamics feed graphics/sound one way via `output` objects [20,21] | One-way physics → render (we already do this) |
| **ClearView** | Coefficient multipliers (`liftConst`, `elevWashCoef`) [22] | Knobs without geometry or units cannot be traced |
| **Gazebo AdvancedLiftDrag** (Apache 2.0) | Whole-aircraft derivatives, `alphaStall`, sigmoid blend `M`, flat-plate `CD_fp_k1/k2`, control-surface derivative lists [23,24]; PX4 tool: YAML surfaces → `.avl` → AVL → parsed derivatives → SDF, ≤ 2 controls of a type, no stall [25] | Structurally our v1 oracle; precedent for AVL import |
| **OpenFlightSim** (UMN, MIT) | Python dict: aero from VSP/AVL, `mass_kg`, `inertia_kgm2`, mixer `surfEff` matrix, actuators (6 Hz, 20 ms, 1° freeplay, ±30°), gear k from ω_n → JSBSim XML [26–28] | Our borrowed source; generator + mixer precedent |
| **AeroSandbox** (MIT) | `Wing` → `WingXSec` (`xyz_le`, chord, twist, airfoil) → `ControlSurface` (symmetric, hinge chord fraction); MAC/ac helpers; AVL/XFoil wrappers [29,30] | Cleanest geometry model |
| **AVL** (GPL) | `.avl` Sref/Cref/Bref, `SURFACE`/`SECTION Xle Yle Zle Chord Ainc`, `AFILE/NACA`, `CONTROL name gain Xhinge XYZhvec SgnDup`; `.mass` rows `mass x y z Ixx Iyy Izz` [31,32] | Our sections and inventory map 1:1 |
| **RCForge** (MIT) | Component JSON (wings, motors, batteries, servos) with units and sources; per-design rights in THIRD_PARTY_NOTICES [33] | Same philosophy; rights per design |

Common pattern: **geometry elements as authority** (X-Plane, AeroSandbox, Aerofly) with **derivatives as an oracle** (Gazebo, JSBSim, our D9a), exactly what Gate F chose; plus point masses with shapes, reusable part files, kinematic actuators, an explicit mixer matrix, configurations, and header metadata with license and limitations.

### Fidelity ladder for aircraft data

| Level | Aircraft is | Aero source | Mass source | Example |
| --- | --- | --- | --- | --- |
| L0 | v1 file: reference + 33 derivatives + one tail pair | borrowed/derived oracle | inventory boxes | today |
| L1 | v2 component tree; derivatives optional oracle | handbook build-up from geometry (current derive scripts, unified) | inventory with shapes | X-DATA-7…10 |
| L2 | + section polars (Re-dependent), multi-panel wings, any number of tails and power units | VLM (AVL) cross-check, polars from UIUC/XFOIL/NeuralFoil | measured CG + one measured inertia | X-DATA-12…14 |
| L3 | + configurations in flight (flaps, retracts, fuel burn), user aircraft | flight-identified corrections, labelled `measured` | per-configuration | X-DATA-15+ |

### Mass and inertia from an inventory

Per item i (mass mᵢ, centroid rᵢ relative to the CG in body FRD, intrinsic tensor Iᵢ about its own centroid):
`J = Σ [Iᵢ + mᵢ (|rᵢ|² E − rᵢ rᵢᵀ)]`, products `Jxy = −Σ mᵢ xᵢ yᵢ` (+ intrinsic). The loader already does this for boxes (`inertia_about`). Shape intrinsics (axis = long axis; standard results):

| Shape | I_axis | I_perpendicular |
| --- | --- | --- |
| box a×b×c | m(b²+c²)/12 | m(a²+c²)/12, m(a²+b²)/12 |
| solid cylinder r, L ("cylinder") | m r²/2 | m(3r² + L²)/12 |
| thin tube r, L ("tube") | m r² | m(6r² + L²)/12 |
| solid sphere ("ball") | 2/5 m r² | same |
| thin shell ("sphere") | 2/3 m r² | same |
| point | 0 | 0 |

Wings and tails: distribute the panel's mass over the same equal-area strips the aero uses (mass ∝ strip area, estimated), so taper moves mass inboard consistently with the planform. Fuselage: 2–4 tube segments between stations. Check against nondimensional radii of gyration `R̄x = (2/b)√(Jxx/m)`, `R̄y = (2/L)√(Jyy/m)`, `R̄z = (2/ē)√(Jzz/m)`, `ē = (b+L)/2` (Roskam's form, used by Aeromatic [9]). Today (computed from the inventories, box intrinsics):

| Aircraft | m (kg) | Jxx, Jyy, Jzz (kg·m²) | L (m) | R̄x, R̄y, R̄z |
| --- | --- | --- | --- | --- |
| Ugly Stik | 2.885 | 0.115, 0.387, 0.484 | 1.32 (plan) | 0.262, 0.555, 0.576 |
| Extra 300S | 3.364 | 0.167, 0.312, 0.456 | 1.23 (inventory extent) | 0.274, 0.493, 0.515 |
| P-51D 1/4 | 18.21 | 2.84, 5.58, 7.76 | 2.46 (kit) | 0.280, 0.450, 0.495 |

The Stik's R̄y is the outlier (loader warning: Jyy = 2.11× the scaled UltraStick25e; ROADMAP D10: inventory Iyy 1.7× Roskam-typical). Probable cause: the virtual balancing mass (0.284 kg at 0.85 m aft, D1-R1) and point-like engine/tail items. A **measured** inertia (bifilar/trifilar pendulum on the owner's airplane; textbook method, not fetched here) is worth more than any refinement of the inventory.

### CG, neutral point and static margin

With the ARP at the wing-body aerodynamic centre and x positive aft, moving the reference from ARP to CG: `Cmα,CG = Cmα,ARP + CLα (x_CG − x_ARP)/c_ref`, `SM = −Cmα,CG / CLα` (fraction of c_ref; ×c_ref/MAC for % MAC). Today: Stik 15.8 %, Extra 12.9 %, P-51 12.0 % of c_ref (derivation reports: Extra 12.5 % MAC, P-51 11.5 % MAC). Neutral point from a VLM (AVL `x_np`) vs the tail-volume formula `x_np ≈ x_ac,wb + η V_H (CLα,h/CLα)(1 − dε/dα) c̄` is a cheap cross-check (X-DATA-12).

### Plausibility gates (loader warnings, never errors)

Computed today: wing loading Stik 62 g/dm², Extra 70 g/dm², P-51 133 g/dm²; static T/W (Ct₀ ρ n² D⁴ at max static rpm) Stik 1.46 (41.3 N at 2.885 kg; ROADMAP's 1.6 predates the D1-R1 mass), Extra 1.25, P-51 1.79; 1-g stall 9.5 / 10.3 / 13.6 m/s. Proposed gates per declared class (bands estimated from RC practice, unverified; tighten with data): SM 5–25 % MAC (sport/scale), 0–10 % (3D/aerobatic), wing loading per class (glider ≪ trainer < warbird/jet), T/W > 1 for 3D (hover), R̄x,y,z in 0.2–0.6, CLmax 0.8–1.6 without flaps. A gate result is a warning shown in the aircraft card and the derivation report, not a refusal: realistic odd aircraft must load.

### Section polars and Reynolds number

Re = V c / ν (ν = 1.46e-5 m²/s, as the derive scripts): Stik 3.1e5 (c 0.305 m, 15 m/s), Extra 3.4e5, P-51 7.3e5 (c 0.487 m, 22 m/s), foamie 1.1e5 (0.2 m, 8 m/s), 3D foamie 8.2e4 (0.15 m, 8 m/s), DLG tip 3.3e4 (0.08 m, 6 m/s). Polars must therefore carry Re (and transition assumption) and be tabulated in Re as well as α; a borrowed full-scale polar at Re 3e6 is wrong for every RC case. Sources: UIUC measured polars (dataset-specific GPL-style terms, see RESEARCH.md), XFOIL (GPL, offline), NeuralFoil (MIT, XFOIL-trained, `analysis_confidence`) — all already surveyed in RESEARCH.md; the schema need is: `airfoil` reference per section → polar file `{Re: [...], alpha: [...], CL, CD, Cm, source, kind}`.

## Implementation options and trade-offs

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| A. v1 forever, optional keys | No migration; works now (turbine, shaft) | Fixed names can't become lists; key soup | Until v2 lands, then freeze v1 |
| B. JSBSim XML | Mature, documented | Property-function evaluator in GDScript; imperial defaults; no `kind/source` | Borrow ideas only |
| C. Godot `.tres` | Inspector, typed | 32-bit `Vector3`; embedded scripts run on load [34]; Python can't write it cleanly | No |
| D. **v2 JSON component tree** + converter + JSON Schema + loader authority | Keeps the evidence contract; lists; variants; mod-safe | Loader rewrite; golden equivalence to prove | **Recommended** |
| E. Derive everything at load in GDScript | One source | BEM/drag build-up in the game; slow; hard review | No: derive offline, validate at load |
| F. Fit to targets (YASim) | Scarce data | Hides errors | Offline report only |

**Recommendation for this repo.** Option D in small steps: (1) freeze and describe v1 (schema, CI checks, cheap load); (2) unify the derive tools on a shared geometry schema; (3) introduce v2 behind a converter whose proof is bit-identical golden flights for all three aircraft; (4) only then add capabilities (mixers, actuators, multiple surfaces/power units, variants, packages).

### openrc-aircraft v2 — sketch (not code)

Principles: objects keyed by ID (merge-patchable, stable diffs); every number keeps `{value, unit, kind, source}`; ASCII units (UCUM-style `kg.m2`, `N.s/m`, `1/rad` [35]; project codes like `rpm` registered in one table); tables carry column units; one frame per file declared once.

```json
{
  "format": "openrc-aircraft v2", "id": "gp-extra-300s-60",
  "meta": {"name": "…", "class": "aerobatic", "status": "experimental",
           "licenses": {"data": "MIT", "model": "MIT", "livery": "CC-BY-4.0"}, "references": ["…"], "limitations": ["…"],
           "generated_by": {"tool": "tools/aircraft/derive.py", "version": "…", "inputs": {"geometry": {"path": "…", "sha256": "…"}}}},
  "frame": {"origin": "wing LE at the centreline", "axes": "x_aft y_right z_up", "unit": "m"},
  "reference": {"S": {}, "b": {}, "c_ref": {}, "mac": {}, "mac_le": {}, "arp": {}},
  "surfaces": {"wing": {"mirror": true, "panels": {"p1": {"root": {"le": {}, "chord": {}, "twist": {}, "airfoil": "naca0013"}, "tip": {}, "strips": 3}},
                        "controls": {"aileron": {"panel": "p1", "span": {}, "chord_fraction": {}, "limits": {}}}},
               "stab": {"mirror": true, "…": {}}, "fin": {"mirror": false, "dihedral": {"value": 90, "unit": "deg", "kind": "manual", "source": "…"}}},
  "bodies": {"fuselage": {"stations": {}}},
  "power": {"engine": {"type": "glow", "$use": "components/engines/os-max-61fx.json"},
            "prop": {"type": "propeller", "driven_by": "engine", "$use": "components/props/apc-12x6-sport.json", "hub": {}, "axis": {}}},
  "actuators": {"ail_r": {"type": "servo", "rate": {}}, "flaps": {"type": "kinematic", "detents": {}, "traverse_time": {}}},
  "mixer": {"inputs": ["roll", "pitch", "yaw", "throttle", "aux1"], "outputs": {"ail_r": {"roll": -1.0}, "ail_l": {"roll": 1.0}}},
  "mass": {"items": {"engine": {"mass": {}, "position": {}, "shape": {"form": "cylinder", "radius": {}, "length": {}}}}, "flight_cg": {}},
  "ground": {"contacts": {"main_l": {"type": "wheel", "retract": "gear"}}, "crash_hull": {}},
  "oracle": {"coefficients": {"CLa": {}}, "tolerance": {}}, "envelope": {}, "start": {"level_speed": {}}
}
```

| v2 element | Replaces / adds | Needed by |
| --- | --- | --- |
| `surfaces.*` with panels (N), strips, airfoil, `mirror`, dihedral (any, 90° = fin) | v1 single trapezoid + `aero.surfaces.horizontal/vertical` | V-tail, twin fins, biplanes, cranked/elliptic wings, gliders |
| `controls` on surfaces + hinge geometry + limits | `controls.max_throw` triple | flaperons, elevons, ruddervators, flaps, spoilers |
| `actuators` (servo rate/deadband; kinematic detents + traverse time) | one `servo_full_throw_time` | P51-11 flaps/retracts, airbrakes, per-servo rates |
| `mixer` (sparse matrix inputs → actuators, per-flight-mode later) | hard-coded roll/pitch/yaw mapping | flying wings, V-tails, crow, snap-flap, 3D mixes |
| `power` units (`glow`, `gas`, `electric`, `turbine`, `none`) driving thrusters (`propeller`, `jet`, `edf`), any count; `$use` library | single engine + propeller | twins, gliders (none), jets (AV-05), electrics |
| `mass.items` with `shape` and optional `component` link; `flight_cg` | boxes only | inertia quality, fuel/battery variants (G4) |
| `ground.contacts` typed (`wheel`, `skid`, `float` later) with optional `retract`; `crash_hull` | wheels only | retracts, tail-draggers, floats, belly-landers |
| `oracle` optional: whole-aircraft derivatives + tolerance | mandatory `aero.coefficients` | keeps D9a test oracle and borrowed-data aircraft; derived ones may omit |
| `meta.licenses`, `meta.generated_by.inputs` hashes | — | mods, provenance chain |

**Variants as overlays.** A variant is `{"format": "openrc-aircraft-variant v2", "base": "<id>", "id": "cg-aft-5mm", "patch": {…}}`, an RFC 7396 merge patch (null deletes, objects merge, arrays replace wholesale [36]) — hence ID-keyed objects everywhere. The loader resolves base + patch, then validates the **result** in full; the resolved document gets its own hash. Typical variants: CG fore/aft, fuel full/empty, prop swap, flaps fixed down, wheels vs floats.

**Versioning and migration.**
- `format` string names the major version; v2 loader accepts v1 by converting in memory (`migrate_v1()`), never by keeping two physics paths.
- An offline `tools/aircraft/migrate_v1_to_v2.py` writes v2 files; proof = model dictionary equality (0 ulp) and golden flights bit-for-bit for all three aircraft.
- Additive changes inside v2 are minor (`"openrc-aircraft v2.1"` optional keys); a loader refuses a newer minor only when it meets an unknown **required** key (`"requires": ["mixer"]` list), and warns on unknown optional keys (current behaviour for unknown coefficients).
- `$schema` in a file is an editor hint, not the version (JSON Schema docs: dialect ≠ data format; RESEARCH.md).

**Schema validation.** JSON Schema 2020-12 (`$defs` for the quantity type, `unevaluatedProperties: false` on closed objects, `prefixItems` for fixed vectors [37]) lives at `app/data/schema/openrc-aircraft-v2.schema.json`; VS Code picks it up via `$schema` or `json.schemas` [38]. The GDScript loader remains the authority for physics rules (signs, cross-consistency, gear ω·dt, envelope solvability). A shared mutation suite runs both and requires agreement on "shape" errors.

**Generated vs hand-authored.** Rule: a file is either hand-authored (Stik today) or generated (Extra, P-51) — never both. Generated files carry `meta.generated_by` with input hashes and are checked by `--check` in CI. Hand corrections to a generated aircraft go into the generator's inputs (geometry, kit values, an `overrides.json` with its own sources), so the chain `source.json → geometry.json → physics.json` stays reproducible.

### The geometry → physics pipeline

1. **One tool** `tools/aircraft/` (Python 3, stdlib core): geometry (planform, MAC, sweep, tail polygons), handbook aero (today's Helmbold/DATCOM, tail volume, strip theory, drag build-up), BEM prop (from P-51), mass (shapes), emitters (v1, v2), report. The two scripts become thin per-aircraft configs; proof: both `--check` byte-identical.
2. **Shared geometry schema** (`openrc-geometry v1`): surfaces as sections (LE xyz, chord, twist, airfoil, control hinge fraction) — the AeroSandbox/AVL shape; bodies as stations; installation (thrust line, hub, axis); gear points; equipment. Each aircraft's `compile_geometry.py` keeps its visual-only extras under `visual`.
3. **Optional backends**: `avl` writes `.avl` (SURFACE/SECTION/CONTROL) and `.mass` from the inventory, runs AVL 3.52 pinned and offline as a separate process (GPL; outputs are data; never bundled), parses derivatives and `x_np`, stores inputs, logs and executable hash [25,31,32]; `vspaero` likewise (NOSA 1.3) [39]. Outputs are `kind: derived` with the backend in `source`, compared with the handbook values in the report; disagreement is a report line, never an automatic override.
4. **AVL validity.** AVL documents quasi-steady limits |p b/2V| < 0.10, |q c/2V| < 0.03, |r b/2V| < 0.25 [31]. The Stik's flown full-aileron roll is p b/2V = 0.131 (148°/s at 15 m/s) — sport RC rolls already exceed AVL's range; a 3D plane at 360°/s, 12 m/s, b 1.5 m gives 0.39. Use AVL for small-perturbation derivatives only; the envelope and post-stall stay with the local-surface model.
5. **Mass**: inventory with shapes → CG, J, R̄; balancing mass solved (as D1-R1) and labelled `derived`; fuel/battery items tagged `consumable` for G4.
6. **Gates** computed and printed in the report and as loader warnings.

### Aircraft classes the schema must not preclude

| Class | Schema features needed | v1 blocker |
| --- | --- | --- |
| Sport/trainer (.40–.60) | today's set | — |
| Thermal / slope gliders | `power: none`; multi-panel high-AR wings (polyhedral); flaps/camber, crow mix; low-Re polars; launch presets (bungee/winch/hand, CRRCSim `launch` [15]); ballast item variants | single trapezoid; propulsion required; `level_speed` ≥ 5 m/s is fine |
| DLG (discus launch) | launch preset with initial ω and v; tiny chords (Re 3e4) | as above; polars |
| Electric foamies / 3D | throws 45°+ (v1 allows 60°), big control chord fractions, prop-wash over most surfaces (E0b), hover (T/W > 1, start at V ≈ 0), electric chain (battery, motor Kv, ESC) | `level_speed` ≥ 5 m/s; no electric power type |
| Turbine jets | `turbine` + `jet` thruster (in progress, AV-05), retracts, flaps, airbrakes (kinematic actuators), wheel brakes, fuel burn, speeds > 60 m/s | `level_speed` ≤ 60 m/s; no actuators |
| Twins | ≥ 2 power units with positions, rotation senses, per-engine throttle mix (single-engine-out) | single engine |
| Biplanes | ≥ 2 wings with stagger, decalage, gap; interference factor between them (Munk's stagger theorem — textbook, not fetched) | one wing |
| V-tail / elevons / flying wings | surfaces at any dihedral; mixer; reflex airfoils; Cma from wing alone | fixed horizontal/vertical pair; fin consistency rule |
| Floatplanes | `float` contacts (buoyancy volume, hydrodynamic drag, step); water surface type in ground table | wheel springs only |
| Giant scale (120 cc+) | item masses > 5 kg, positions > 2 m, spans > 4 m (40 % aerobats ≈ 3 m are fine) | caps in `_q` ranges |
| Towing / glider tow | tow hook point + release; rope as a two-body constraint (sim side) | no attachment points |
| Helicopters / multirotors (out of scope) | rotors with blade element or thrust maps, swashplate/flight-controller mixer, gyro; CRRCSim has a separate heli format [15], JSBSim models an AH-1 [3], RCForge quads [33] — a different vehicle type, `"vehicle": "rotorcraft"` reserved | everything |

## Godot / GDScript notes

- **Measured load cost** (Godot 4.7.2 headless, dev VM, 20 repetitions, scratch benchmark not in the repo): `JSON.parse_string` 0.65–1.04 ms; `AircraftData.load_file` 111.6–119.0 ms; `_envelope` alone 110.6 ms; `JSON.stringify(...).sha256_text()` 0.84 ms. The bisection runs 60 iterations × 801 samples × 2 sides ≈ 96 k `Aero.lift_alpha` calls. Mitigations: coarse-to-fine extreme search, or golden-section on the unimodal peak, or a cache keyed by the envelope inputs' hash. Proof must show the solved angles unchanged to ≤ 1e-12 rad and goldens untouched.
- **Determinism.** JSON numbers are doubles; Godot's JSON has one number type and stringify converts numbers to float [40]. Integer-like fields (counts, `strips`) must accept `float` with an integral check. All derived values stay in `float`/`PackedFloat64Array` (the float64 guard applies to `physics/`).
- **Hashes.** `data_sha256` hashes `JSON.stringify(raw, "", true)` (sorted keys, `full_precision = false`). Godot documents `full_precision` as the switch that guarantees exact decoding [40], so the current hash is of a possibly lossy re-serialization. For provenance, hash the **file bytes** (`HashingContext` over `FileAccess.get_file_as_bytes`) plus, for resolved variants, the canonical full-precision text.
- **Resource vs JSON.** Keep JSON: diffable, writable from Python, no code execution. `.tres` can embed GDScript that executes on load (the MIT `godot-safe-resource-loader` exists precisely to scan for it, by blacklist) [34].
- **Hot reload (D7).** `FlightSession.reload()` already re-loads, re-trims and keeps the previous aircraft on invalid data. For authoring, an optional debug-only mtime poll (`FileAccess.get_modified_time`, Godot 4 API; not re-verified for 4.7) could trigger it; never in release.
- **Export.** Presets ship `include_filter="data/*.json"`; the exported smoke flight proves files in `data/aircraft/` are packed. Keep every v2 data file (components, polars, variants, schema) as `.json` under `data/` so presets need no change; add an export smoke that loads **every** catalog ID (Avanti audit item).
- **Mods via `user://`.** `user://` maps to the per-OS app-data folder; `res://` is read-only once exported [41]. Load user aircraft from `user://aircraft/<id>/` with `FileAccess`/`DirAccess`; visuals via runtime `GLTFDocument.append_from_file` + `generate_scene` [42]. Do **not** use `ProjectSettings.load_resource_pack` for user content: packs can contain scripts and by default replace existing `res://` files [43].
- **Catalog scale.** Listing must read a small manifest only (name, class, status, licenses, thumbnail); full validation + trim only on Fly. With the current 111 ms solve, validating 50 packages up front would block the menu ≈ 5.6 s.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| JSBSim XML conventions | Element vocabulary (mass_balance, pointmass forms, contacts, kinematic, fileheader) | LGPL 2.1 (code) | [1–8] | Ideas and names only; no code |
| Aeromatic / AeromatiC++ | First-guess full model from a few inputs | (repo, not checked) | [9,10] | Cross-check only; note its ×1.5 inertia "feel" factor |
| CRRCSim airplane v2 + power docs | RC-specific schema: configs, wheels, launch, electric chain | GPL 2 | [15,16] | Ideas; compare parameter sets for gliders/electrics |
| AVL 3.52 | VLM derivatives, `x_np`, trim, modes | GPL | [31,32] | Offline backend, run as external process, pinned, outputs stored as data |
| PX4 AVL automation | Precedent: YAML surfaces → `.avl` → parsed derivatives | BSD-3 (PX4; not re-checked) | [25] | Read its `input_avl.py`/`avl_out_parse.py` structure, write our own |
| Gazebo AdvancedLiftDrag | Derivative + sigmoid + flat-plate model, parameter names | Apache 2.0 | [23,24] | Comparison of our oracle structure; parameter naming |
| OpenFlightSim | UltraStick25e data (already borrowed), mixer/actuator/gear dict pattern | MIT | [26–28] | Keep citing at the pinned commit; mixer matrix idea |
| AeroSandbox | Geometry data model, MAC/ac helpers, AVL/XFoil wrappers, weights | MIT | [29,30] | Optional dependency of `tools/aircraft` backends (pin version) |
| OpenVSP / VSPAERO | Parametric geometry + panel/VLM aero | NOSA 1.3 | [39] | Optional backend; never bundled |
| NeuralFoil, XFOIL, UIUC polars | Section polars vs Re | MIT / GPL / dataset terms | RESEARCH.md | Polar files with Re and source |
| JSON Schema 2020-12 + `jsonschema` (Python) | Shape validation, editor IntelliSense | spec open; validator MIT (not re-checked) | [37,38] | CI + VS Code; loader stays authority |
| godot-safe-resource-loader | Shows the `.tres` script risk | MIT | [34] | Argument for JSON-only mods; not a dependency |
| RCForge | JSON component aircraft with sources; per-design rights | MIT | [33] | Compare schemas; license-per-design precedent |
| UCUM | ASCII unit grammar (`kg.m2`, `N/m`, `s-1`) | Regenstrief terms | [35] | Adopt the syntax for v2 unit strings (no library needed) |

## Parameters and data

| Quantity | Typical RC value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| O.S. MAX-61FX engine mass | 0.55 | kg | manual | O.S. catalog via Stik/Extra inventories |
| DA-120 with ignition | 2.45 | kg | manual | P-51 `source.json` (Desert Aircraft) |
| JetCat P100-RX turbine | 1.08 (2011 manual; accessories unclear) | kg | manual | [avanti-s-turbine-research](../avanti-s-turbine-research.md) |
| Standard servo (.60 size) | 0.045 each | kg | estimated | Stik inventory |
| Giant-scale servo | 0.08 each | kg | estimated | P-51 inventory (0.16 kg per pair) |
| Receiver | 0.025 (.60) / 0.12 incl. switches (120 cc) | kg | estimated | Stik / P-51 inventories |
| Receiver battery 4.8 V 600 mAh | 0.105 | kg | estimated | Stik inventory |
| Fuel (half tank) | 0.12 (.60) / 0.37 (120 cc) | kg | estimated | inventories |
| Main retracts + struts + wheels (120 cc) | 2.0 | kg | estimated | P-51 inventory |
| UltraStick25e mass, J | 1.959; 0.07151, 0.08636, 0.15364 | kg; kg·m² | borrowed | OpenFlightSim [27] |
| UMN actuator model | 6 Hz bandwidth, 20 ms delay, 1° freeplay, ±30° | Hz, s, deg | borrowed | OpenFlightSim [27] |
| Wing loading | 62 (Stik), 70 (Extra), 133 (P-51) | g/dm² | derived | files, computed here |
| Static T/W | 1.46, 1.25, 1.79 | 1 | derived | files, computed here |
| Static margin | 15.8, 12.9, 12.0 | % c_ref | derived | files, computed here |
| R̄x, R̄y, R̄z | 0.26–0.28, 0.45–0.56, 0.50–0.58 | 1 | derived | inventories, computed here |
| Section Re | 3e4 (DLG tip) … 7.3e5 (P-51) | 1 | derived | V c/ν, computed here |
| AVL quasi-steady limits | pb/2V < 0.10, qc/2V < 0.03, rb/2V < 0.25 | 1 | manual | AVL doc [31] |
| v1 caps that block classes | item ≤ 5 kg, span 0.3–4 m, positions ±2 m (hull ±3 m), level speed 5–60 m/s, max static rpm ≤ 50 000 | — | manual (code) | aircraft_data.gd |

## Validation

**Verification (known answers):**
- Converter: v1 → v2 → model dict equals v1's model dict exactly (all three aircraft); golden flights replay bit-for-bit through the v2 path.
- Schema/loader agreement: the existing ≈45 Stik mutations + new ones are rejected by both the JSON Schema (shape errors) and the loader; physics-only rules (signs, fin consistency, ω·dt) are rejected by the loader alone, listed explicitly.
- Shapes: inertia of a solid cylinder, thin tube, ball and shell against closed forms to 1e-12; parallel-axis and products already tested for boxes.
- Unified derive tool: Extra and P-51 outputs byte-identical to today's committed files (`--check`).
- AVL backend: a rectangular AR 6 wing at small α — CLα within a few % of Helmbold; antisymmetric aileron gives zero CL; mirrored geometry gives zero Cl at β = 0; refining the lattice changes non-zero derivatives < 2 % (criterion proposed in extra-aircraft-tooling 12).
- Variants: `cg-aft` patch moves CG by the patched amount; base file hash unchanged; resolved file passes full validation.

**Independent validation (real RC behaviour):**
- Measure the owner's airplane: CG by scale (two-point weighing), Iyy/Izz by bifilar pendulum; replace `estimated` inventory results with `measured` J and compare with the inventory (target: explains the R̄y outlier).
- Compare derived derivatives against the UMN Ultra Stick identified modes (D8b chain) after any pipeline change: modes must not drift unexplained.
- For each new aircraft, kit-manual CG range and throws reproduce the manual's balance point and "flies with X mm"; flown roll rate / stall speed vs owner videos (D8b method).

**Mutation tests that must fail:**
- Edit a geometry input without regenerating → CI `--check` fails (add P-51 build/compile/derive checks to CI first).
- Variant patch introduces an array element instead of an ID-keyed object → refused with a message naming the path.
- Unit `kg·m2` written with U+22C5 (⋅) or `kg*m2` → refused with a suggestion (`kg.m2`).
- A user package containing `.gd`, `.tres`, `.res`, `.pck`, `.scn` → refused before any load.
- Mixer that leaves an actuator without input, or an input driving nothing → refused.
- Twin with mirrored engines but identical rotation sense declared as counter-rotating → loader cross-check fails.

## Pitfalls and risks

1. **Silent re-normalisation (MAC vs S/b).** v1 uses c_ref = S/b; derivatives from AVL/literature use MAC. Mitigation: v2 stores both, every coefficient set declares its reference lengths and ARP; the converter rescales and the report shows both.
2. **Frames drift.** Three frames (model, LE, body) already exist; a v2 that adds a fourth (AVL) will create sign bugs. Mitigation: one frame per file declared in `frame`, conversion only in named functions with round-trip tests; AVL import test with an asymmetric known case.
3. **Fitting knobs creep in** (YASim/Aeromatic ×1.5 lesson). Mitigation: generators may not tune to "feel"; any correction factor is a labelled input with source and appears in the sensitivity sweep.
4. **Golden-flight churn during migration.** Mitigation: v2 loader produces the **same** runtime model dict for v1 files; goldens are re-recorded only for deliberate physics changes (existing rule).
5. **Library coupling.** Extra and P-51 already read the Stik file; `$use` libraries make that explicit but also spread changes. Mitigation: library files are versioned by content hash in `generated_by.inputs`; changing a library makes dependents stale in CI, which is intended.
6. **Weak fingerprint.** `data_sha256` hashes a non-full-precision re-serialization; two files differing in late digits could share a fingerprint in traces. Mitigation: hash file bytes; add the resolved-document hash for variants.
7. **Unit strings with look-alike characters** (`·` U+00B7 vs `⋅` U+22C5), comma-joined column units. Mitigation: ASCII unit grammar in v2; v1 strings accepted only through the converter.
8. **Load-time solver cost** (111 ms per file) multiplies with variants and mods. Mitigation: X-DATA-2 before packages; manifest-only listing.
9. **Mod security.** Godot resources and packs can run code. Mitigation: JSON + glTF + PNG/OGG only, extension allow-list, size limits, no `load_resource_pack` for user content.
10. **License mixing.** UIUC data terms, GPL tool outputs, kit-manual numbers, third-party liveries. Mitigation: `meta.licenses` per layer + `references`; the catalog shows them; CI refuses a package without them.
11. **v1 caps exclude whole classes** (5 kg item, ±2 m, 60 m/s). Mitigation: make caps class-aware in v2 (bounds from `meta.class`), keep tight defaults.
12. **Schema and loader disagree.** Two validators drift. Mitigation: shared mutation corpus run by CI against both.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| X-DATA-1 | Add the missing P-51 `build_geometry`, `compile_geometry` and `derive_physics --check` to CI next to the Extra ones | CI fails on a deliberately stale copy (mutation run on a scratch clone) and passes on `main` | — |
| X-DATA-2 | Make the envelope stall-start solve cheap (coarse-to-fine or golden-section) | `a1`, `n1` unchanged ≤ 1e-12 rad on 3 aircraft + 1,000 random envelopes; `load_file` ≤ 15 ms; goldens pass unchanged | — |
| X-DATA-3 | Fingerprint file bytes (`HashingContext`) alongside the current hash; write both in the trace header | Changing one late digit in a copy changes the byte hash; goldens untouched | — |
| X-DATA-4 | JSON Schema 2020-12 for **v1** (`app/data/schema/`), validated in CI with Python `jsonschema` | 3 files valid; every shape mutation in `test_aircraft_data.gd` also rejected by the schema (agreement table) | — |
| X-DATA-5 | Extract the shared derive library `tools/aircraft/` from ex05 and p51-05 | Both `--check` byte-identical; unit tests for `helmbold`, `flap_tau`, `shoelace`, `bem_tables` against hand values | X-DATA-1 |
| X-DATA-6 | Inventory `shape` forms (box default, cylinder, tube, ball, sphere, point) in v1 as an optional key | Closed-form inertia tests to 1e-12; three aircraft' J unchanged (no shapes used yet) | — |
| X-DATA-7 | Shared `openrc-geometry v1` schema; Stik/Extra/P-51 geometry files converted by script, visuals unchanged | `compile_geometry --check` byte-identical outputs; model-team verify scripts pass | X-DATA-5 |
| X-DATA-8 | v2 format + `migrate_v1_to_v2.py`; loader accepts v2 and v1 (in-memory migration), same runtime model dict | Model dict equal (0 ulp) for all three aircraft via both paths; all golden flights bit-for-bit | X-DATA-4 |
| X-DATA-9 | Controls as data: surfaces' control list + mixer matrix replace the hard-coded aileron/elevator/rudder mapping | Stik goldens bit-for-bit; a synthetic elevon wing: pure roll input gives zero net pitch moment at trim (hand-computed) | X-DATA-8 |
| X-DATA-10 | Kinematic actuators (detents, traverse time) for flaps and retracts | Flap 0 → 45° takes the declared time; P-51 trims at take-off flap with CL_trim ↑ and α ↓ (hand estimate); unblocks P51-11 | X-DATA-9 |
| X-DATA-11 | Variants as merge patches over ID-keyed objects (CG, fuel, prop) | `cg-aft` variant's short-period frequency moves as `SM` predicts (linearize.gd); base hash unchanged | X-DATA-8 |
| X-DATA-12 | Plausibility gates per class (SM, W/S, T/W, R̄, CLmax) as warnings in loader and report | Three aircraft give the documented warning set; a mutated SM 2 % triggers the warning, not an error | X-DATA-8 |
| X-DATA-13 | AVL backend in `tools/aircraft` (offline, pinned 3.52, not bundled) | Rectangular-wing known case; Stik/Extra derivative comparison table in the report; lattice-refinement < 2 % | X-DATA-7 |
| X-DATA-14 | Power units as a list (`glow`, `turbine`, `electric`, `none`) driving thrusters | Twin fixture: one engine out gives Cn = T·y/(q S b) to 1e-9; Stik goldens bit-for-bit | X-DATA-8 (and AV-05) |
| X-DATA-15 | Section polars with Re for local strips (UIUC/XFOIL/NeuralFoil-generated files) | Strip CL at small α reproduces the oracle within the D9a 1e-9 region rule where the polar is linear; Re interpolation tests | X-DATA-8, Gate F follow-ups |
| X-DATA-16 | Aircraft packages: `res://data/aircraft/<id>/` and `user://aircraft/<id>/` with manifest (meta, licenses), extension allow-list; catalog discovers them; manifest-only listing | A user package copied to `user://` appears on Home and flies; packages with `.gd/.tres/.pck` refused; 50 synthetic manifests listed < 50 ms | X-DATA-2, 8, 12 |

## Decisions to take now

1. **v2 = component tree with derivatives as optional oracle** (not JSBSim XML, not Resources). Recommended: yes; it matches Gate F.
2. **Objects keyed by ID, not arrays,** for every list a variant may touch (surfaces, controls, mass items, contacts). Needed now because new optional v1 keys (`slipstream.pieces`) are arrays and will become migration debt.
3. **Runtime files stay SI with one canonical unit per field;** unit conversion lives only in Python tools. v2 unit strings become ASCII (UCUM-style). Freeze the compound-unit spelling for tables (`columns` with units) before more tables land.
4. **Generated vs hand-authored is exclusive per file,** generated files carry input hashes, every generator's `--check` runs in CI.
5. **Mods are data only:** JSON, glTF, images, audio. No scripts, no `.tres`, no PCKs from users — decide before the first community aircraft.
6. **License fields per layer** (data, model, livery) required for any aircraft that ships or is shared.
7. **No automatic fitting to performance targets;** targets are gates and report lines.
8. Owner decision: **measure one real airplane's CG and inertia** (Stik) to anchor inventories.

## Sources

1. JSBSim team, "Forces and moments" (reference manual), https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/forces-and-moments/ — fetched.
2. JSBSim, "Documentation for JSBSim" (XML schema), https://jsbsim.sourceforge.net/JSBSim.xsd.html — fetched.
3. JSBSim team, aircraft directory, https://github.com/JSBSim-Team/jsbsim/tree/master/aircraft — fetched.
4. JSBSim, FGMassBalance class reference, https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGMassBalance.html — fetched.
5. JSBSim, FGLGear class reference, https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGLGear.html — fetched.
6. JSBSim, FGPropulsion class reference, https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGPropulsion.html — fetched.
7. JSBSim, FGKinemat class reference, https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGKinemat.html — fetched.
8. JSBSim, FGAerodynamics class reference, https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGAerodynamics.html — fetched.
9. JSBSim, "What Aero-Matic does", https://jsbsim.sourceforge.net/aeromatic-doc.html — fetched.
10. JSBSim team, Aeromatic repository, https://github.com/JSBSim-Team/aeromatic — search result only.
11. FlightGear wiki, "YASim", https://wiki.flightgear.org/YASim — search result only (HTTP 403 on fetch).
12. C. Olson, "Dynamics (physics) modelling and flight simulation", https://gallinazo.flightgear.org/uas/resolution/simulation-modelling/ — fetched.
13. Buckaroo's Hangar, "YASim approach and cruise settings", https://buckarooshangar.com/flightgear/yasimtut_approach_cruise.html — fetched.
14. Wikipedia, "X-Plane (simulator)" (blade element description), https://en.wikipedia.com/wiki/X-Plane_11 — search result only.
15. CRRCSim 0.9.13, "Airplane file format version 2", https://sources.debian.org/data/main/c/crrcsim/0.9.13-3.2/documentation/file_format/airplane02.html — fetched.
16. CRRCSim 0.9.13, "Power and propulsion", https://sources.debian.org/data/main/c/crrcsim/0.9.13-3.2/documentation/power_propulsion/power_propulsion.html — fetched.
17. D. Rowlands, PicaSim "Customisation", https://rowlhouse.co.uk/PicaSim/customisation.html — fetched.
18. Wikipedia, "RealFlight" (aircraft editor), https://www.realflight.com/ — search result only (the Wikipedia article URL found earlier is a 404 on 2026-10-06).
19. Robitronic, "RC Flight Simulator by AccuRC", https://robitronic.com/en/accurc-simulator.html — search result only (dead link: 404 on 2026-10-06).
20. IPACS, aerofly wiki "aircraft:tmd", https://aerofly.com/dokuwiki/doku.php/aircraft:tmd — fetched.
21. IPACS, "tmEdit Manual", https://www.aerofly-sim.de/download/software/tmedit/manual — search result only.
22. ClearView RC, "Plane model parameter definitions", https://www.rcflightsim.com/ClearViewPlaneModelParameterDefinitions.html — fetched.
23. Gazebo Sim 8, `AdvancedLiftDrag` API, https://gazebosim.org/api/sim/8/classgz_1_1sim_1_1systems_1_1AdvancedLiftDrag.html — fetched.
24. Gazebo, gz-sim LICENSE (Apache 2.0), https://github.com/gazebosim/gz-sim/blob/gz-sim8/LICENSE — fetched.
25. PX4, "Advanced Lift Drag (AVL) Automation Tool", https://docs.px4.io/main/en/sim_gazebo_gz/tools_avl_automation — fetched.
26. UASLab, OpenFlightSim LICENSE (MIT), https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/LICENSE.md — fetched.
27. UASLab, OpenFlightSim `Utilities/UltraStick25e.py`, https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Utilities/UltraStick25e.py — fetched.
28. UASLab, OpenFlightSim `AeroOpenFlight.xml`, https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml — fetched.
29. P. Sharpe, AeroSandbox `geometry.wing` source, https://aerosandbox.readthedocs.io/en/master/_modules/aerosandbox/geometry/wing.html — fetched.
30. P. Sharpe, AeroSandbox repository (MIT), https://github.com/peterdsharpe/AeroSandbox — fetched.
31. M. Drela, H. Youngren, AVL documentation, https://web.mit.edu/drela/Public/web/avl/avl_doc.txt — fetched.
32. M. Drela, AVL home (3.52, GPL), https://web.mit.edu/drela/Public/web/avl/ — fetched.
33. RCForge repository (MIT), https://github.com/adithya-s-k/RCForge — fetched.
34. derkork, godot-safe-resource-loader (MIT), https://github.com/derkork/godot-safe-resource-loader — fetched.
35. Regenstrief / UCUM Organization, "The Unified Code for Units of Measure", https://ucum.org/ucum — fetched.
36. P. Hoffman, J. Snell, RFC 7396 "JSON Merge Patch", 2014, https://www.rfc-editor.org/rfc/rfc7396 — fetched.
37. JSON Schema, "2020-12 release notes", https://json-schema.org/draft/2020-12/release-notes — fetched.
38. Microsoft, "Editing JSON with Visual Studio Code" (`$schema`, `json.schemas`), https://code.visualstudio.com/docs/languages/json — search result only.
39. NASA, OpenVSP repository (NOSA 1.3), https://github.com/nasa/openvsp — search result only.
40. Godot Engine, `JSON` class reference (stable), https://docs.godotengine.org/en/stable/classes/class_json.html — fetched.
41. Godot Engine, "File paths in Godot projects", https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html — fetched.
42. Godot Engine, "Runtime file loading and saving", https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html — fetched.
43. Godot Engine, "Exporting packs, patches, and mods", https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html — fetched.
