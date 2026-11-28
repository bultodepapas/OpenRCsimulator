# EDF-00-R1: Independent audit of the EDF implementation plan

**Date:** 2026-11-21. **Audited proposal:**
`719c3cc6b8e3ac32d2f62e08b6df9b646925361f`.
**Runtime/source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
**Delivery:** `research/edf-propulsion-2026-11-21`, [PR #18](https://github.com/bultodepapas/OpenRCsimulator/pull/18).

**Historical policy note:** this records the R1 review. The later owner's native
requirement and [EDF-00-R2 native contract](native-runtime-design.md) supersede
R1's permission for an EDF reference product fallback, including the T17
disposition below. Current EDF admission refuses missing native capabilities;
reference execution is an explicit verification tool. Other R1 evidence and its
dated CI observations remain historical records.

The user requested a skeptical external audit of the original plan. Three fresh
source-read-only reviewers, without the original drafting conversation, examined
physics, repository integration and evidence/acceptance. The lead independently
checked material source, equations and primary references, then integrated the
corrections. This is an independent design review within the project workflow,
not hardware certification or an external organization's endorsement.

## Assessment

The original family separation and coupled-mechanics direction remain useful.
The proposal nevertheless needed substantive correction before implementation:
its blanket domain-refusal wording conflicted with the current event locator,
it overlooked existing spatial-wind behavior, and several validation statements
could pass a model that conserves the wrong energy or has inadequate accuracy.
The implementation plan and research documents now state discriminating
contracts, executable synthetic arithmetic and separate evidence dependencies.

All dispositions below are **document/specification corrections**. No EDF
runtime, inherited physics repair, aircraft data or CI policy was implemented.
The [plan](../../plans/edf-propulsion.md) remains the authoritative work sequence.

## Findings and dispositions

P1 means a prerequisite to the indicated implementation/claim; P2 is a bounded
fidelity, verification or product requirement. These are not deployed incident
severities. IDs below review the proposal; EDF-A IDs in the
[repository audit](repository-audit.md) identify current source boundaries.

| ID | Priority / gap | Counterexample or source evidence | Correction and required proof |
| --- | --- | --- | --- |
| R1-01 | P1 — event probes versus physical domain | `EventStep` evaluates negative trial RPM before locating a legal stop; unconditional refusal aborts before refinement. Battery exhaustion has analogous charge probes. | Separate measured support, admitted physical continuation and locator-only moving-side extension. Include zero-speed fan load, bound probes or qualify a guarded composition. T11 tests analytic stop time, momentum and coincident exhaustion/contact. EDF-A13. |
| R1-02 | P1 — existing spatial wind overlooked | `WindFlow` already returns station-local velocity with body rotation and ambient gradient; EDF is absent from station admission. Adding rotation again produces a different velocity. | Register EDF intake and consume the stage receipt once. T03 uses uniform/gradient wind, nonzero rate, datum shift and stale receipts. EDF-A12. |
| R1-03 | P1 — windmilling and pack initialization | Glide trim currently sets RPM to zero. A freewheel equilibrium may be nonzero; a discharging pack cannot have every state derivative zero. | Separate stopped/freewheel/no-root branches and instantaneous versus conditioned trim at declared SOC/T/controller state. Preserve real resource derivatives and expected first-tick drift. T15; EDF-A14. |
| R1-04 | P1 before playable integration — sibling product contracts | Catalog `data` means ideal; `battery_data` means finite pack. Avanti stock show smoke is turbine-bound, and legacy sound excludes only `electric_prop`. | Generate honest ideal-lab/pack paths with pack default, select an EDF-safe smoke profile/exclusion, and support or disable legacy audio explicitly. T21/T22 cover both siblings and actual start/restart routes. |
| R1-05 | P1 for physical claims — static data do not identify the full law | Published voltage sweeps correlate RPM/current/thrust. They do not identify inertia, independent shaft torque, off-curve combinations, incidence or installed moments. | Store joint support/cells and output-specific evidence; never expand extrema into a measured box. Test alternative fits with independent transient/wind-on data. EDF-02b/09 and T02/T06. |
| R1-06 | P1 for a usable plan — synthetic and physical tracks conflicted | The proposal allowed an estimated playable model but also required measured-map support and placed physical calibration before flight. Withheld digitized points are not independent acquisitions. | EDF-02a/10a permits bounded, fully estimated software experiments. EDF-02b/09/10b/14 requires independently acquired data for physical claims. Missing data leaves physical cards inconclusive without blocking synthetic development. |
| R1-07 | P1 — incomplete mechanical-energy oracle | With locked inertia, relative rotor speed and axial body rotation, energy includes `J_r Omega (a_s dot w)`. Omitting it can misdiagnose or conceal work. | Add the exact constant-parameter coupled-energy identity and a one-axis fixture: 19 J and 18 W, checked independently of runtime. T04/EDF-03/04. |
| R1-08 | P1 — individually plausible windmill signs can create energy | `V=20 m/s`, `F_x=-1 N`, `Omega=100 rad/s`, `Q_fan=-1 N m` gives +80 W under the declared complete quasi-steady uniform-flow boundary. | Apply the scoped vector wrench/shaft passivity check jointly, including interpolation interiors. Do not apply it without required flow/storage terms in spatial/unsteady or incomplete boundaries. T05. |
| R1-09 | P2 — polarization energy mistaken for heat | Fixed one-RC example: 0.60 W OCV-to-terminal difference, 0.35 W dissipation, 0.25 W storage. Variable tau/R adds a parameter-work issue. | Add the exact fixed-parameter pulse/rest oracle. Keep variable-parameter residual and terminal-versus-chemical energy scope explicit; no new full-chemistry claim. T07. |
| R1-10 | P1 — convergence without production-step accuracy | For `y'=-480y`, RK4 at 240 Hz is stable but gives 1/3 instead of exp(-2), about 146% relative error; finer steps converge. | Freeze per-observable/time-horizon budgets before acceptance. Require 240 Hz accuracy and refinement with unchanged command/controller sampling schedule. T10; numerical stability alone cannot pass. |
| R1-11 | P2 for physical decisions — undefined uncertainty semantics | A 3% standard uncertainty and 3% expanded uncertainty can produce the same arithmetic pass but imply different coverage. Correlated points are not independent repeats. | Predeclare error/normalization, Ue interpretation, coverage, covariance/systematics, run units and campaign decision. Preserve the project inequality; missing protocol is inconclusive. V01–V06. |
| R1-12 | P2 — overbroad opposite-spin/stator fixture | Reversing unchanged pitched rotor/stator hardware is not reflection symmetry; zero exit swirl alone does not exclude inlet angular momentum. | Test signed-axis conventions and fully mirrored fixtures with correct polar/axial transforms. Ideal cancellation assumes zero upstream and downstream axial flux and no other axial fluid moment. T04. |
| R1-13 | P2 — finite-disc body-rate approximation | A locked rotor's center can have zero air velocity while its blades move through air with body roll. | Declare center-point map limits and bound omitted rate/vorticity loads or add identified inputs. Avoid singular rate/RPM admission at starts; retain relative-stator speed for back EMF. T03. |
| R1-14 | P2 — current-peak bandwidth | Algebraic averaged current omits inductance and switching/commutation. A millisecond L/R transient is not its instantaneous waveform. | Specify sensing/sample/filter bandwidth and compare equally filtered bus-current peaks; exclude phase/switching protection claims without separate identification. T08/V02. |
| R1-15 | P2 before playable integration — refusal without recovery | Repeated ticks against the same out-of-domain accepted frame can stall without a clear user outcome. | One visible paused/fault state, reason, preserved frame/clock, accurate recorder status and reset/Home path; no automatic law/backend change. T06/T21. |

The closing review also removed residual wording conflicts: physical acquisition
protocols freeze on their own track before final held-out observations; large-fan
stands may start synthetic; loss-based shaft-power estimates retain provenance;
refinement preserves command/controller sampling; and pack defaults preserve a
saved supported choice. T01/T17 now distinguish invalid map integrity (rejected
under both backends) from native-specific incompatibility with valid reference
inputs (eligible for an explicitly identified preparation fallback).

The physics closing pass fixed the rotational energy datum to the live CG and
made the passivity boundary exclude external heat/mass injection or account for
their energy flux. The three reviewers reported no further blocking issue within
their stated source-only review scope after these corrections; this is not a
completed implementation or physical validation gate.

## Evidence added and choices retained

The source register now includes the omitted DS-130 static chart, MIT's motor
model derivation, TI's winding-current/commutation explanation, and NIST's
combined/expanded/reporting uncertainty guidance: **S25–S30** in the
[source study](physics-and-sources.md#8-source-register-and-acquisition-limits).
The NASA EDF paper was rechecked for its separate validation observations,
unavailable shaft-torque measurement and inadequate wind-off-to-wind-on power
extrapolation. These sources motivate boundaries; they do not calibrate the A200.

Retained decisions and rejected expansions:

- Keep a distinct EDF family, separate shaft load and total installation wrench,
  fixed 240 Hz kernel, explicit native/reference identities and the turbine sibling.
- Keep 128/152/195 mm as independently specified experiments; no measured fit or
  pack-current compatibility is inferred from manufacturer ranges or mass examples.
- A general CFD, bidirectional drive or full electrochemical solver is not required
  for a bounded synthetic first slice. Its approximations and unsupported modes
  remain visible and constrain physical promotion.
- The four-load multirotor bus and unfinished fixed-gear electric-ground helper
  are precedents, not drop-in finite-pack retractable-A200 implementations.
- Retain EDF-A01/A02's limited claims. Their source/algebra evidence does not prove
  a failing shipped flight. The inherited turbine repair remains a separate task.

## Reproducible audit arithmetic

[calculations.py](../../../research/edf-propulsion/calculations.py) now emits six
additional analytic groups: coupled energy, invalid windmill passivity, fixed-RC
storage, stable-but-inaccurate RK4 refinement, within-tick rotor stop, and spatial
station flow. Their values and scope are in [calculations.json](calculations.json).
They are independently derived fixture expectations, not executions of the
future EDF implementation. The [research index](README.md#verification-and-delivery)
records completed checks for the revised candidate.

## CI blocker verified during the audit

The original candidate's [CI run 1191](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44911323231)
completed with failure. [Release preflight](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44911323231/job/136867565672)
stopped because these 13 UID sidecars were not tracked:

```text
app/landscapes/phoenix_flight.gd.uid
app/landscapes/phoenix_flight.gdshader.uid
app/landscapes/phoenix_images.gd.uid
app/landscapes/phoenix_library.gd.uid
app/landscapes/phoenix_objects.gd.uid
app/landscapes/phoenix_source.gd.uid
app/landscapes/phoenix_zip64.gd.uid
app/tests/test_landscape_import.gd.uid
app/tests/test_landscape_import_images.gd.uid
app/tests/test_landscape_import_zip64.gd.uid
app/tests/test_phoenix_flight_calibrations.gd.uid
app/ui/landscape_import.gd.uid
app/ui/phoenix_panorama.gdshader.uid
```

All 13 are absent in baseline `57abea0` as well. The baseline and audited proposal
have identical `app` trees and identical `tools/ci/release_preflight.py` blobs.
Thus this is an **inherited release-source omission**, not an EDF documentation
regression. CI orchestration/host-admission regressions passed, but application,
native, export and visual jobs were skipped; the required aggregate failed.

The owning source/import work must generate the missing sidecars with the pinned
editor and review/commit them with their source before required CI can clear.
This audit does not invent UIDs, weaken preflight or claim skipped tests passed.
The latest PR checks remain authoritative for subsequent revisions.
