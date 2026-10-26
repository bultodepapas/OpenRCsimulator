# GP-10: support query and bank-normal evidence

2026-10-25 local development evidence. GP-10b corrects the sign of the hull support normal on a sloping lake bed/bank. The retained checks below are bounded software evidence, not measured RC validation or a completed full-tree acceptance run.

## GP-10a query contract

`GroundSupport` adds `openrc-ground-support v1` as an observational query beside the existing force laws. [GroundTerrain](../../../../app/physics/ground_terrain.gd) remains the geometry owner; [GroundSurfaces](../../../../app/physics/ground_surfaces.gd) retains rectangle ordering and all existing friction values. [Environment.sample_support](../../../../app/sim/environment.gd) exposes the detached result. No new force, native contact solver, wheel state or kernel branch is installed.

| Interface | Implemented contract |
| --- | --- |
| `GroundSupport.prepare_legacy(surfaces, regions)` | Copies the validated stride-6 table and region provenance. Preserves GP-01 relief selected by historical rolling factors. SHA-256 binds format, geometry law, table bytes, relief bytes and ordered identities. Missing provenance is explicitly `unspecified`; the empty legacy fixture retains its documented flat dry-pavement meaning. |
| `GroundSupport.prepare_explicit(surfaces, relief_m, regions)` | Separate prepared geometry law with one relief amplitude per rectangle, including catchall. Changing friction cannot change this height field. Accepts the existing 0–7 mm qualified wave envelope only; this is an implementation bound, not a general terrain or RC limit. It is not enabled through stock sessions until all physical and rendered consumers migrate together. |
| `GroundSupport.sample(prepared, position_ned, velocity_ned, time_s, lake)` | Float64 NED metres, metres/second and nonnegative simulation seconds. The caller must keep the successful prepared object unchanged. Returns height-up, slopes, solid-surface velocity, outward unit normal, signed **vertical** gap and its nonunit gradient/rate, a vertical footpoint, material and geometry identity. Invalid input returns `ok=false`; it never silently becomes flat support. |
| `Environment.install_ground_registry(regions)` | Validates provenance against its current legacy table. `FlightSession.set_field` installs the builder's registry at the existing field boundary. Raw replay arrays retain existing force/checkpoint semantics; replacing or editing their values invalidates stale names before the next query. |
| `GroundSurfaces.validate/build` | Optional `material_id` requires a nonempty source. Historical v1 data without metadata stays valid. Authored region IDs are namespaced `field:<id>`; IDs longer than 122 characters use the disjoint `field_sha256:<digest>` namespace, preserving previously valid field files within the observation's 128-character bound. `__outside__` is reserved for catchall. Inclusive rectangle precedence is unchanged. |

The default runway is **maintained turf**, not asphalt. Its new identity follows existing source provenance and does not claim a new measurement. Mown and rough regions identify mown/long grass; the rotorpad keeps its historical reserved relief selector. Material metadata does not alter traction, rolling resistance, hull friction or generated aircraft data. Different material names alone do not install additional physical surface models.

For height-up `h(N,E)`, the returned gap is `g=-D-h`, with `grad(g)=(-h_N,-h_E,-1)` and `g_dot=grad(g).v`. The outward normal is `grad(g)/|grad(g)|`; `normal_velocity_mps` is therefore a distinct quantity. `closest_point_valid=false` and `gap_kind=vertical_height` prohibit interpreting this as Euclidean distance. Field derivatives are analytic. Covered lake derivatives retain the provider's 0.025 m finite-difference stencil and declare `derivative_method=provider_finite_difference`; their numerical accuracy is not relabeled exact.

Lake queries return the **static solid bed/bank**, not the moving water interface used for water impacts and propeller strikes. Lake identity contributes to the environment identity even outside coverage; covered results clear unknown bed material to `unspecified`. A configured vehicle road returns `unsupported_geometry` until it has an explicit adapter. No road, obstacle, deformable soil or moving-support capability is fabricated.

[The query test](../../../../app/tests/test_ground_support_query.gd) passes **114 checks**: independent finite differences and virtual work, curved relief, lake banks, profile/friction independence, boundary priority, material validation and identity changes, input/result detachment, stale registry invalidation, bed-versus-water semantics, unsupported roads, long authored IDs and real session/checkpoint noninterference. It verifies lake-only law metadata and a current lake checkpoint roundtrip; rejection of a historical pre-change lake checkpoint is not claimed without a retained old fixture. [Checked report](checks/query/report.json), [raw log](checks/query/engine.log). Both new test scripts are automatically included by `app/test.sh`'s `tests/test_*.gd` unit loop.

## GP-10b: positive-down lake slope correction

[LakeSurface](../../../../app/physics/lake_surface.gd) reports `ground_down_m` and its north/east derivatives positive **down**. [HullContact._lake_normal](../../../../app/physics/hull_contact.gd) previously used their negatives as the horizontal normal components. That expression has the wrong sign: for a plane `D=d_N N+d_E E+d_0`, the outward unit normal and signed separation are

```text
L = sqrt(1 + d_N^2 + d_E^2)
n = (d_N, d_E, -1) / L
g = (d_N N + d_E E + d_0 - D) / L
g_dot = n . v_NED; compression x = -g
```

The fix converts the lake derivatives to height-up slopes, then calls `GroundTerrain.normal_from_up_slopes(-d_N,-d_E)`. This shared helper constructs the same outward NED normal used by height-up terrain consumers. The changed hull branch supplies loads, terminal severity and contact velocity projections for both constant and live mass-property routes. It does not retune stiffness, damping, friction, thresholds or the lake terrain itself.

The independent plane counterexample uses `d_N=0.2`, `d_E=0` and tangent velocity `(1,0,0.2) m/s`. Its geometric gap is constant. The old normal `(-0.2,0,-1)/sqrt(1.04)` nevertheless reports closing speed `0.4/sqrt(1.04)` = **`0.39223227027637 m/s`**. The corrected normal reports zero. [The focused test](../../../../app/tests/test_hull_support_normal.gd) retains the old executable expression from baseline `b85ce1047a3e7798ab22b330675fc0c9e4bce912` as a counterexample; it does not update a frozen fixture to hide the change.

For a planar spring/damper, `U=1/2 k x^2`, outward reaction `F=(k x+c x_dot)n` and `x_dot=-n.v`. Thus `F.v+U_dot=-c x_dot^2` while the reaction is unclipped. The focused fixtures use `x=0.01 m`, `k=1000 N/m`, `c=50 N s/m`: tangent travel leaves the normal load at `10 N` and introduces no damper reaction; pure approach at `0.4 m/s` produces `30 N` and `8 W` of damper loss. Tangential friction remains a separate dissipative reaction. These fixtures do not claim the same energy identity for a curved normalized-height gap.

### Identity and preservation

`HullContact.law()` retains its prior no-lake bytes. `LAKE_NORMAL_LAW="positive-down-bank-gradient-normal-v2"` names the changed lake behavior. The session integration appends this constant to the configuration/checkpoint identity only when soft hull contacts and a lake are enabled, and emits trace metadata `hull_lake_normal_model` for that route. This separates the intentional lake change from unchanged no-lake runs; it does not promise old lake checkpoints/replays are equivalent.

The focused test pins the baseline no-lake law SHA-256 (`03963546ff5efa6a694583c9d9cc19e5ca9d6b24663d6be140aba0544de57291`) and exact float64 serialized force bytes for one flat contact. It also checks the two planar tangents for positive/negative north/east slopes, a nonidentity body attitude and nonzero body rates, force direction/work, observation projections, actual-lake constant/live-mass load parity at zero CG shift, terminal severity parity and invalid normal rejection.

`test_lake_covered_sampling` remains unchanged. Its hull reference freezes `prop_disc_depth` and inherits other production helpers; it is a covered-query/prop parity check, not an independent frozen oracle for the old hull normal. The new plane tests provide that missing independent check.

### Retained checks and source identity

The native Windows runs used Godot `4.8.beta1.official.4d10419ca`, headless with Dummy audio, on a working tree based on `b85ce1047a3e7798ab22b330675fc0c9e4bce912`. Run start times and exact commands are in each report. The focused run began `2026-10-26T00:02:59.729546+00:00` (2026-10-25 local). These two source hashes identify the hull change and focused test at that run:

| Source | SHA-256 |
| --- | --- |
| [hull_contact.gd](../../../../app/physics/hull_contact.gd) | `cb9d0397554cc100a6b04ff0034abf827d9d55d1f27e3bea5e7ced87e3036b2a` |
| [test_hull_support_normal.gd](../../../../app/tests/test_hull_support_normal.gd) | `8f776a03eac2a8de653404f365fc7fe02525c102d42410e783fa7350b5867c03` |

All four retained reports have `complete=true`, `ok=true`, process exit zero and zero engine errors/warnings. Reports and logs are copied byte-for-byte, including their original absolute execution paths and recorded log SHA-256 values.

| Script | Observed result | Report / raw log |
| --- | --- | --- |
| `test_hull_support_normal.gd` | **70 checks, 0 failed**; required completion marker enforced | [report](checks/bank-normal/report.json), [log](checks/bank-normal/engine.log) |
| `test_dynamic_mass_contact.gd` | **38 checks, 0 failures** | [report](checks/dynamic-mass/report.json), [log](checks/dynamic-mass/engine.log) |
| `test_lake_covered_sampling.gd` | **761 checks, 0 failed** | [report](checks/lake-covered/report.json), [log](checks/lake-covered/engine.log) |
| `test_lake_collision.gd` | All lake collision checks passed | [report](checks/lake-collision/report.json), [log](checks/lake-collision/engine.log) |

To reproduce from a checkout with the source changes, follow the [checked runner guide](../../../../tools/godot/README.md), including its one-time import for a fresh resource cache, then run:

```powershell
$gp10Godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
python tools/godot/run_checked.py --out-dir tmp/gp10-checks --label bank-normal --timeout 60 --require-text '70 checks, 0 failed' -- $gp10Godot --headless --path app --audio-driver Dummy --script res://tests/test_hull_support_normal.gd
python tools/godot/run_checked.py --out-dir tmp/gp10-checks --label dynamic-mass --timeout 90 -- $gp10Godot --headless --path app --audio-driver Dummy --script res://tests/test_dynamic_mass_contact.gd
python tools/godot/run_checked.py --out-dir tmp/gp10-checks --label lake-covered --timeout 90 -- $gp10Godot --headless --path app --audio-driver Dummy --script res://tests/test_lake_covered_sampling.gd
python tools/godot/run_checked.py --out-dir tmp/gp10-checks --label lake-collision --timeout 90 -- $gp10Godot --headless --path app --audio-driver Dummy --script res://tests/test_lake_collision.gd
python tools/godot/summarize.py docs/research/ground-physics/GP-10/checks
```

The final command verifies the retained collection without requiring its original absolute paths. The reports' wall times are command durations, not physics performance measurements.

### Remaining physical limits

The existing curved-terrain approximation still uses `x=(D+h)/L`, with `h` positive up and `L=sqrt(1+|grad h|^2)`, alongside `x_dot=-n.v`. Its actual derivative has an additional term:

```text
x_dot = -n.v - x * L_dot/L
```

Correcting the lake normal sign does not remove this mismatch, make a vertical footpoint the closest point, or qualify generic hills and deep penetration. Exact distance/normal/work agreement requires a closest-point formulation or a separately qualified approximation envelope. Lake slopes also retain their provider finite-difference stencil.

Whole-hull relief migration remains pending: ordinary hull support still uses its historical flat field outside the lake, while wheel terrain includes microrelief. Prop strikes intentionally distinguish the moving water interface from the solid bed/bank. No full round-wheel geometry, moving gear work, new material coefficients, soil model, hardware validation, rendered/audio acceptance or target-host performance qualification is established here.

## Combined integration receipts

The combined regression run used a detached `b85ce1047a3e7798ab22b330675fc0c9e4bce912` worktree with only the GP-10 runtime overlay. This separated the ground change from concurrent propulsion, audio and Workshop work. [Integration source identity](checks/integration-source-identity.json) records the eight changed runtime paths and input hashes. This run preceded the long-ID compatibility fix; that fix changes registry naming only and is covered by the final 114-check query test and the subsequent main surface regression.

| Regression script | Result | Checked receipt |
| --- | --- | --- |
| `test_ground_terrain` | 21 checks | [report](checks/integration-ground_terrain/report.json) |
| `test_ground_surfaces` | 29 checks | [report](checks/integration-ground_surfaces/report.json) |
| `test_field_surfaces` | 19 checks | [report](checks/integration-field_surfaces/report.json) |
| `test_ground_stage_queries` | 195 checks | [report](checks/integration-ground_stage_queries/report.json) |
| `test_sf_environment` | 27 checks | [report](checks/integration-sf_environment/report.json) |
| `test_lake_ground_contact` | All checks passed | [report](checks/integration-lake_ground_contact/report.json) |
| `test_lake_surface` | All checks passed | [report](checks/integration-lake_surface/report.json) |
| `test_soft_contacts` | 36 checks | [report](checks/integration-soft_contacts/report.json) |
| `test_checkpoint` | 92 checks | [report](checks/integration-checkpoint/report.json) |
| `test_checkpoint_integrity` | 149 checks | [report](checks/integration-checkpoint_integrity/report.json) |
| `test_aircraft_contact_session` | 63 checks | [report](checks/integration-aircraft_contact_session/report.json) |

All eleven invocations completed with zero failures and zero engine diagnostics. Their raw `engine.log` files sit beside the reports. Together with the five focused suites above, these are **16 distinct suites**, including **1,714 numbered checks** and three suites that report success without a total. This is a targeted regression set, not the full application suite.

After the compatibility correction, the concurrent main tree passed the [114-check query suite](checks/main-ground_support_query/report.json), [70-check hull suite](checks/main-hull_support_normal/report.json) and [29-check surface regression](checks/main-ground_surfaces/report.json), with zero engine errors/warnings. These **213 checks** repeat affected coverage; they are not added to the distinct total. The [before](checks/main-source-before.json) and [after](checks/main-source-after.json) inventories are identical across physics, simulation, failures, the surface data and the two new tests. They identify the actual combined source tested, including unrelated track changes, without claiming those changes as GP work.

[Frozen tapes and final candidate replay evidence](evidence/README.md) retain the pre-change exact replay and four changed-source Stik/P-51 air/ground comparisons. All **1,484 native sample rows** are byte-equal; official candidate reports must still say `solver_changed=true`. This is no-lake numerical preservation on those short scenarios, not evidence that the intentionally corrected lake behavior matches the old solver. No golden flight was rewritten.

Three existing `gpt-6.1-sol` high-reasoning specialists handled baseline/replay evidence, the hull-normal derivation, and query tests/independent review. Review found the long-ID compatibility regression; a failing test demonstrated it before the bounded, disjoint identity encoding was accepted. The parent integrated the geometry/material API and retained final decision ownership. This increment did not run six simultaneous specialists or establish hardware/physical calibration.

The [fresh-checkout receipt](checks/attribute-roundtrip.json) verifies all 131 retained raw artifacts (5,980,719 bytes) through an isolated Git commit and fresh clone with `core.autocrlf=true`. Every artifact and the root attributes file retained its SHA-256; the source remained unchanged during the check. The clone's checked collections passed 19 root, two baseline and four candidate invocations. This verifies artifact transport, not a new physics run.
