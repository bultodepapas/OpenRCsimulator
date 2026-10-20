# Extra 300S RC realism audit and corrections

2026-10-11 · EX-06/EX-08/EX-09 · **Status: audit and bounded corrections complete; engine evidence recorded. Physical acceptance and baseline application failures remain open.** Owner: [realism plan](../../EXTRA-300-PLAN.md).

The audit targets the Great Planes GPMA0236 64 in Extra 300S with an O.S. .61FX. Three evidence-backed inconsistencies were corrected: balancing the fuel-loaded inventory against an empty-tank datum, omitting the installed thrust angles from physics, and showing 12×8 blade pitch while selecting 12×6 in physics. Aerodynamic estimates were not fitted to make a scripted maneuver pass. The aircraft remains experimental.

2026-10-19 scope note: the original audit below predates the [installed finite-glow Extra](../../GLOW-ENGINES.md) and [current fuel system](../../FUEL-SYSTEM.md). Its prescribed-fuel masses, missing-shaft statements, yaw results and baseline failures describe those source snapshots. Current implemented scope and remaining work live in the [aircraft guide](../../EXTRA-300-PLAN.md).

## Sources and decisions

The [primary-source audit](EX-06/primary-sources.md) records the Great Planes manual and original plan, O.S. engine and propeller guidance, UIUC measured propeller data, and APC's propeller-type distinctions. The [implementation audit](EX-06/implementation-audit.md) follows generation, loading, forces, controls and conditional modules. The [generated derivation](../../../research/extra-300/ex05/derivation.md) is the current parameter calculation.

- Manual p43 specifies **empty-tank** balance. The generator now solves its estimated dry component inventory at that station before adding the unchanged 0.146 kg prescribed fuel. Additional virtual balancing mass is bookkeeping, not measured hardware or a ballast recommendation. The former dry CG was about 6.5 mm aft of the initial datum, still within the manual's stated adjustment range.
- The plan's 2° right / 0.5° down shaft installation now acts through the existing angled-thrust consumer. The CG-relative force arm comes from the transformed visual propeller hub. Thrust, reaction torque and rotor momentum share that axis. Wing and tail incidence retain their own datum.
- The visual blade pitch now matches the selected 12×6. Its Ct/Cp curves remain an explicitly borrowed APC 11×6 proxy; neither this consistency correction nor O.S.'s recommended size range identifies the prototype's actual propeller.
- Loaded CG changes intentionally propagate into mass, inertia, stability derivatives and gear reaction/stiffness derivation. The catalog's old “loaded CG at dry model datum” assertion was replaced with the dry-plus-fuel moment calculation at its original tolerance. Existing handling thresholds were retained.

## Flight behavior coverage

Independent reductions from the serialized inventory are retained in [configuration-comparison.json](EX-08/configuration-comparison.json). Other production aircraft and all four synthetic electric fixtures are byte-identical between these snapshots.

| Quantity | Before | After |
| --- | ---: | ---: |
| Loaded mass | 3.364321 kg | 3.419469 kg |
| Dry CG, aft of centerline LE | 0.115324 m | 0.108800 m |
| Loaded CG, aft of centerline LE | 0.108800 m | 0.102660 m |
| Virtual balance mass | 0.087321 kg | 0.142469 kg |
| Roll / pitch / yaw diagonal inertia | 0.166620 / 0.311965 / 0.455489 kg·m² | 0.166658 / 0.319867 / 0.463358 kg·m² |
| Estimated 1-g stall speed | 10.338 m/s | 10.422 m/s |
| Physical down / right thrust | 0° / 0° | 0.5° / 2° |

The following matrix covers the full behavior audit, including areas where the present model lacks enough evidence or mechanisms for physical acceptance.

| Behavior or system | Audit and verification | Physical qualification remaining |
| --- | --- | --- |
| Trim and longitudinal stability | Actual six-axis session trim; 30 s hands-off flight; independently checked dry/wet mass properties | Measured inventory, inertia, drag, neutral point and trim versus speed |
| RC controls | Manual high/low linear throws converted through hinge geometry; both signs of all three axes at both rates; slew/trim retained | Installed servo speed/load response, pilot evaluation and actual transmitter endpoints |
| Roll, pitch and yaw | Existing roll-rate checks, 12 pulse cases, both controlled 30° turns; no self-leveling added | Identified control/damping/cross derivatives; slip and knife-edge coupling |
| Climb, glide and energy | Full-power climb, power changes, running-idle descent and stopped-engine glide; mechanical-energy diagnostic excludes fuel/thermal energy | Installed prop/engine load curve, drag polar, windmilling drag and measured climb/sink |
| Aerobatics | Existing inside-loop consistency case, sustained inverted trim, high-rate response | Outside loops, precision knife-edge, snaps, harriers/hover and linked routines lack independent acceptance; no 3D capability claim |
| Stall and spin | Existing power-on/off stall checks, both spin directions with explicit recovery pilot, timestep comparison | Identified low-Re polar, local stall progression, dynamic stall/hysteresis and repeatable pilot/flight evidence |
| Propulsion effects | Independent thrust/moment oracles, rotor-axis alignment, zero-RPM shutdown, throttle transient | Extra-specific shaft power balance, wake/swirl, P-factor and prop-disc normal force; qualitative takeoff yaw remains a gate |
| Ground, terrain and landing | Real rotating-wheel profile and session contact/crash path; park, taxi, takeoff and approach trials | Tyre/suspension/steering calibration, crosswind and rough-field trials, complete circuit and stopping-distance acceptance |
| Energy systems | Fixed half-tank inventory remains explicit; no battery, flaps, retracts or fuel-consumption module enabled | Fuel burn, changing CG/inertia and slosh are absent; fixed gear and no brakes are intentional |
| Wind and atmosphere | Shared air-relative flow and atmosphere tests; no Extra-specific weather retuning | Extra-specific gust, crosswind landing and altitude performance qualification |
| Reset, replay and damage | All-aircraft checkpoint/reset tests include Extra, engine mode and state; configuration identity and rendering/hinge contracts; shared crash suite | Crash thresholds are provisional; no flutter, aeroelasticity or measured damaged-flight model |
| Timing and performance | Native pinned Godot 4.7.2; 240/480 Hz trials; isolated Linux regression suite and whole-tick benchmark | Target-hardware graphical frame budget and pilot latency/feel assessment |

The [airborne results](EX-08/airborne-audit.md) and [ground results](EX-08/ground-audit.md) separate controller technique, numerical results and unresolved physical behavior. A feedback pilot can compensate for changed physics; its success does not validate the aircraft. Integrating body pitch rate alone does not prove a planar loop.

All 24 airborne and seven ground cases complete before and after; the changed build also completes all 31 at 480 Hz. Ground cases have no crashes. Largest airborne endpoint differences between 240 and 480 Hz are 0.0281 m altitude and 0.00831 m/s speed; ground touchdown differs by 0.002083 s. **Takeoff yaw remains a failed qualitative realism target:** the corrected configuration turns right in the unguided case and needs predominantly left corrective rudder, whereas the manual anticipates left turn/right correction. The probe retains normal flight trims and does not isolate individual yaw mechanisms. This is recorded as a remaining physical gap, not hidden by tuning.

## Evidence integrity and regression scope

Baseline app sources were frozen before implementation; after sources are that baseline plus only this change's model/data/test overlay. Source manifests are retained under [baseline](EX-06/baseline/source-manifest.json), [after](EX-06/after/source-manifest.json), and [Linux suite](EX-08/linux-suite-source-manifest.json). The Linux run uses a clean clone, pinned engine and LF-normalized text. Concurrent UI, weather, scenery, crash-visual and landscape edits were excluded from the comparison and preserved in the working tree. No shared force solver was changed and no golden trace was regenerated.

The independent [installation test](../../../app/tests/test_extra_installation.gd) passes 17 checks: dry longitudinal CG error 0.098 µm, visual/physical shaft error 2.02×10⁻⁸ and hub error 0.448 µm, plus independent Ct/Cp interpolation and `r × F − Q axis` checks. Running it against the old configuration rejects 11 checks. See [passing log](EX-06/after/installation.log) and [negative control](EX-06/baseline/installation-negative-control.log).

The existing [handling test](../../../app/tests/test_extra_handling.gd) passes all 12 checks before and after. Thirty-second trim, roll rates, inside-loop response, full-up stalls and scripted spin recovery retain their original tolerances. [Before](EX-06/baseline/handling.log), [after](EX-06/after/handling.log).

The [verification summary](EX-08/verification-summary.json) accounts for **all 199 unit-script files and 27 downstream suite sections**. After the original suite stopped at an existing atmosphere assertion, the remaining entries were executed independently. Resource import, generator checks, float64 guard, transcendental/shader checks and all-script parsing completed. There are **186 passing unit files and 13 baseline-present failed files**; all 27 downstream sections pass after the E5a fixture repair below. The suite is not green. The [failure triage](EX-08/regression-triage.md) reproduces and identifies every remaining failure, including the Linux-only extreme-atmosphere Stik case. [Initial log](EX-08/full-suite.log), [continuation](EX-08/full-suite-continuation.log), [per-section results](EX-08/full-suite-continuation.json).

The 16 UI test files were repeated with a fresh, unique XDG data/config/cache directory per process because a baseline UI reproduction could have overlapped the first continuation's preferences. The [isolated UI results](EX-08/isolated-ui.json) reproduce the same seven failed UI files; those results supersede the first UI pass. Concurrent work was preserved.

All four aircraft data/render contracts, checkpoint/reset checks, unchanged-aircraft golden flights, four real-app trimmed-flight traces, input/radio checks, weather/atmosphere CLI checks and 30/60/144 fps state-independence sections pass. Extra's model verifier also passes. The live working tree independently passes the [17 installation](EX-08/live-installation.log) and [12 handling](EX-08/live-handling.log) checks without engine errors. Geometry and physics generators reproduce on Windows and the clean Linux clone.

The E5a research fixture had retained `_settled_wash()`, which omitted GP wheel states and made all 12 setup cases fail even on the [old aircraft baseline](EX-08/baseline-e5a-wheel-layout-failure.log). Its initialization now calls `_settled_continuous()`; no force law or tolerance changed. The full [E5a rerun](EX-08/e5a-verification/verification.json) passes 21 geometry/contact checks and 63 session checks at 240/480/960 Hz. The original failure remains in the continuation log and is superseded by that rerun. E5b's separate pitch-threshold/patch checks also pass. This repairs useful Extra regression coverage instead of counting setup rejection as a flight result.

The Extra whole-tick benchmark on this shared Windows workstation (Ryzen 9 5900X, native Godot 4.7.2) reports 390.8 → 435.4 µs/tick from trim and 331.6 → 455.6 µs/tick from the 15°-alpha start, each the best of three 2,400-tick batches. [Baseline](EX-06/baseline/bench.log), [after](EX-06/after/bench.log). Component timings also vary; these non-interleaved busy-host runs cannot attribute the difference to the installation change. They are below 500 µs locally, but do not establish tail latency, sustained low-altitude contact cost, rendered FPS or the owner's slowest-machine performance gate.

## Adding physical evidence next

1. Identify the installed propeller, muffler and engine setup; measure RPM/thrust/torque versus throttle and advance speed. Introduce shaft/wake/asymmetric-prop modules only with their own explicit data, consumers and signed force/moment tests.
2. Measure dry/wet mass, CG and inertia of the reference build. Identify the wing section and obtain suitable Reynolds-number polars. Verify stalls and spin recovery against independent observations before retuning the generic envelope.
3. Measure gear loads/deflection and rolling behavior; compare low-rate tail-up takeoff, rudder correction and powered landing with a qualified RC pilot. A complete circuit must preserve state between phases.
4. Qualify wind/crosswind, aerobatic sequences and graphical performance on target hardware. Keep the model experimental until those gates have evidence.

The [reproduction and RC rate guide](../../../research/extra-300/ex06/README.md) gives generation commands, probe runners and manual-derived low-rate settings. This completes the bounded installation correction without claiming that undocumented flight characteristics have become measured facts.

## 2026-10-16 — Runway startup (EX-08-R1)

The Extra's generated contacts lacked the optional breakaway factor required by the static runway solver. Its [source pipeline](../../../research/extra-300/ex05/derive_physics.py) now declares 1.25 as the shared E3b1/Stik engineering estimate, explicitly unmeasured on the Extra. The runtime allows the Extra's selected runway start; no force law or generated geometry was changed. The generated physics, derivation and Workshop descriptor reproduce in a fresh sparse checkout with this change overlaid.

`test_extra_runway.gd` passes 16 checks at 240 and 480 Hz: three supported wheels, six seconds at rest, then three seconds of full throttle and prescribed elevator without crash or propeller strike. Existing installation, airborne handling and stiction checks pass. The [fleet/UI evidence](../menu-investigations/UI-06b/README.md#2026-10-16--fleet-runway-default-ui-06d-r3) covers the product route, defaults and restart behavior. This supports an experimental software startup path, not physical taxi/takeoff validation.

The pre-change [baseline ORFL](../../../research/extra-300/ex05/extra-runway-baseline-20261016.orfl), [CSV/export metadata](../../../research/extra-300/ex05/baseline-export-20261016/flight.csv), [exact replay report](../../../research/extra-300/ex05/baseline-exact-20261016/replay.json) and [comparison](../../../research/extra-300/ex05/baseline-exact-comparison-20261016.json) preserve 261 rows through tick 260. The exact replay passed before the source/data change with `complete: true`, `solver_changed: false` and zero numerical differences.

Adding three wheel anchors expands the auxiliary layout from 5 to 14 values and moves the wake value from index 4 to 13. The ordinary [candidate replay correctly rejects the incompatible checkpoint](../../../research/extra-300/ex05/candidate-replay-20261016/replay.json). The separate [paired report](../../../research/extra-300/ex05/candidate-paired-20261016/paired-report.json) and [common-channel CSV](../../../research/extra-300/ex05/candidate-paired-20261016/paired-common.csv) run both old and new aircraft data under the same current source, using the complete recorded tick/input tape. The explicit projection preserves body/controls/wake and initializes the added airborne anchors to zero. All 13 body-state and six force/moment channels have zero differences across all 261 rows.

The paired report has `complete: true` and `solver_changed: true`: changing the session's aircraft allowlist changes the source fingerprint relative to the recording. This is neither exact replay of the old recording nor equivalence of the extended state. The two data configurations are compared under one current solver; ground behavior is checked separately above. No golden flight was re-recorded.

Reproduce the paired comparison into a new output directory (never overwrite retained evidence):

```powershell
& $GodotWindows --headless --path app --script "$PWD/research/extra-300/ex05/compare_runway_candidate.gd" -- --out=res://../tmp/extra-paired-review
```

The [comparison script](../../../research/extra-300/ex05/compare_runway_candidate.gd) refuses existing outputs, incomplete recordings and auxiliary interventions that need another layout projection. Its integrated rerun reproduced all 261 zero-difference rows with the recorded source/configuration identities.

## 2026-10-19 documentation recheck

Checks ran in a concurrently edited tree, not a frozen qualification baseline. Geometry, appearance and aircraft-generator `--check` commands pass; the native model verifier passes 123 checks. Original EX-08 envelope results above do not establish current verification.

- `test_extra_installation.gd` cannot parse at line 149 (unexpected backslash).
- `test_extra_handling.gd` passes initial 22 m/s trim/hold/roll checks, then aborts on a failed maneuver trim and times out at 90 s; it is not a passing suite.
- `test_extra_runway.gd` fails two of 16 checks, the takeoff assertion at both 240/480 Hz. This fixture raises throttle without requesting the installed glow starter; runway support itself remains implemented.
- The actual CLI produces 721 finite rows over three seconds with finite-glow combustion and consumption. The existing glow trace inspector passes and the aircraft-input bytes match. The conventional `check_trimmed_flight.py` rejects this glow base format, including in the current Extra `app/test.sh` route; that acceptance path remains pending.

The local CLI observation is neither package qualification nor physical validation. Close the current test/runner gaps before renewing software-envelope or full-suite acceptance. Source-PDF metrology and rendered capture review were not repeated; the ignored original PDFs are absent here.
