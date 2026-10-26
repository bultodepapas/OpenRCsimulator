# GP-12 finite electric source evaluation

2026-10-26 · **742 assertions across three production scripts, all passed**, with required completion markers, warnings treated as errors, and zero engine diagnostics. Official Windows Godot `4.8.beta1.official.4d10419ca`, headless. [Scoped report](report.json), [source and dependency hashes](manifest.json).

This foundation evaluates finite batteries through the existing common body/wheel/shaft stage. It does **not** integrate a battery boundary or enable advanced ground physics on stock aircraft. The current contact policy explicitly refuses `source_policy="finite_battery"`; complete-path source localization remains the policy owner's work. The earlier [GP-11 broad-suite failure](../../../GP-11/broad-suite/README.md) is a separate frozen cohort.

| Production script | Checks | Receipt |
| --- | ---: | --- |
| Finite-source state and shared aircraft stage | 384 | [report](checks/test_aircraft_ground_battery/report.json) |
| Existing fixed-voltage torque split | 162 | [report](checks/test_aircraft_ground_source/report.json) |
| Existing fixed-voltage aircraft composition/runtime fixtures | 196 | [report](checks/test_aircraft_ground_electric/report.json) |

## Owners and APIs

[AircraftGroundElectric](source/app/physics/aircraft_ground_electric.gd) preserves `prepare`/`evaluate` and their original law, and adds `prepare_dynamic`/`evaluate_dynamic`. Both routes use one shared aerodynamic, propeller, wash and common-stage assembly. Dynamic state order remains `[wash..., relative shaft RPM, existing battery block..., wheel rim m/s...]`. Stage-local ambient kelvin and cooling m/s are explicit inputs. All prepared routes remain launch-unavailable and require fixed hubs, fixed gear, fixed axes and constant mass.

[AircraftGroundSource](source/app/physics/aircraft_ground_source.gd) adds `electric_dynamic`, reusing the same torque decomposition as the fixed bus. It obtains current from the existing `ElectricSupply` or `PackEcm` law. Electromagnetic drive is `Kt*I_motor`; the full finite bearing capacity `Kt*I0` remains exclusively an internal shaft row in the **same contact QP**, including at rest, with motor off, or after pack exhaustion. The old net `shaft_torque_nm` already includes bearing loss and is not supplied as drive torque.

The complete propeller wrench is included once in the external aircraft wrench at its fixed reference datum. Subtracting the hub-force moment extracts the local rotor couple for additional relative-spin work only. Shaft RPM is relative to the body, with `sigma=RPM*2*pi/60`; it is not absolute inertial rotor speed. The common mechanical power sample includes external datum-wrench power, local aerodynamic couple times relative spin, and electromagnetic drive times relative spin. It does not add motor copper loss or pack heat as mechanical work.

[AircraftGroundBattery](source/app/physics/aircraft_ground_battery.gd) supplies `initial_block`, `valid`, `evaluate` and `supervise_endpoint`. Its input installation is normalized, admitted AircraftData; it introduces no alternative raw-authoring validator or hardware defaults. Existing battery blocks and all existing source-point fields/rates are preserved byte exactly in the tested configurations:

| State | Continuous or sampled |
| --- | --- |
| Weak-cell/pack charge Q, terminal energy E, pack electrical loss H | Continuous; `Qdot=-Ipack`, `Edot=Vbus*Ipack`, existing loss law |
| Average/weak RC branch voltages, pack temperature, filtered voltage | Continuous, existing PackEcm rates |
| ESC output limit, phase, debounce/ramp timer | Zero derivative; updated **once after the accepted outer tick** |
| Detected cell count | Zero derivative; detected once at pack connection |

`supervise_endpoint` returns a copy and changes only the three sampled supervisor slots. A discriminating soft-cut case proves two half-tick samples differ from one outer-tick decision. Root trials, contact pieces and refinement attempts must not sample the ESC. Ordinary accepted Q=0 disconnects motor and auxiliaries; PackEcm's remaining RC/thermal/filter dynamics are retained. Connected Q=0/negative-charge and negative-RPM continuations require explicit trial authorization and cannot pass accepted-state validation. No shaft clamp, impulse projector or second integrator exists in the adapter.

## Evidence and limits

Independent pre-promotion captures bind the **complete** original prepared dictionary and three complete fixed-stage results at 0/3,000/8,000 RPM. The new test pins SHA256 of their Variant-byte hexadecimal encodings, so post-promotion parity is not a comparison of one function with itself. See the unchanged [capture log](before-checks/fixed-before-capture/engine.log), [driver](drivers/capture_fixed_before.gd), [two prior sources](source-before/app/physics/) and [minimal patch](implementation.patch). Both original law strings remain unchanged; the finite route has separate law identities.

The new suite compares every returned existing source field and every battery rate byte exactly, checks loaded/airborne stages and nonunit RK-stage attitudes, tests malformed selector types without engine errors, and closes independently assembled generalized kinetic-gradient power. Largest observed motor-port residual: **4.55e-13 W**; pack-terminal/motor-plus-auxiliary residual: **4.39e-13 W**; mechanical stage residual: **5.69e-14 W**. Terminal energy and pack loss retain their existing meanings; no additional chemical-energy or recoverable RC-energy model is claimed.

All **269** listed physics/sim/failure scripts, app-data JSON files and selected test dependencies have identical [before](main-source-before.json) and [after](main-source-after.json) hashes across the final three invocations. Four promoted files are retained as exact source snapshots. This is a scoped current-main receipt, not a complete repository/source checkout or a full-suite pass. Raw checked reports/logs retain their original command paths and timestamps unchanged; [origins](origins.json) bind the copies. No frozen GP-10/11 payload or flight golden changed.

Finite-battery contact integration still requires source roots evaluated on the **same complete split candidate path**, including duration-dependent halfkicks and existing whole-piece admission. Nesting legacy `ElectricBatteryStep`/`ElectricStop` or `ResourceEventStep` RK4 would create separate numerical/projection ownership. Mechanical shaft capture stays in the common impulse solve; a charge transition must not create a second body/shaft/wheel impulse. Source descriptors/event ordering and outer-tick publication remain unimplemented here. Moving hubs, steering integration, fuel/turbine sources, physical calibration, native audio/rendering and target-device/1080p performance remain outside this result.

Reproduce the scoped collection from the matching source snapshot using the existing checked runner (Bash):

```bash
for name in aircraft_ground_battery aircraft_ground_source aircraft_ground_electric; do
  python3 tools/godot/run_checked.py --out-dir tmp/gp12-finite-source-repeat \
    --warnings-as-errors --timeout 180 -- "$(app/get-godot.sh)" \
    --headless --path app --script "res://tests/test_${name}.gd"
done
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/finite-source-evaluation/checks
```

The retained invocations additionally require each script's exact completion marker. [Fresh Git/autocrlf receipt](attribute-roundtrip.json) verifies retained byte preservation; its post-verification receipt is excluded from its own manifest and roundtrip snapshot.
