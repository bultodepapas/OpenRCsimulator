# RCV-36 — Monster Car 2 powertrain update

Date: 2026-10-15. This evidence covers a scoped update to the estimated Nitro kernel. The shared body solver, vehicle data and 33-value state layout remain unchanged. The preceding same-tape baseline was captured before the kernel edit and retained beside this report.

## Changes

The engine now has a hard stall gate at 1 rad/s: throttle cannot restart a stopped engine or burn fuel until the explicit service start action seeds engine speed. Fuel flow is capped by the remaining inventory over the requested tick, and telemetry reports the bounded instantaneous flow and throttle accepted after that cap. `engine_running`, `engine_spinning` and `combustion_active` distinguish fuel-backed operation from a free-spinning or stalled flywheel.

The centrifugal clutch follows signed engine-to-wheel slip. Positive clutch torque transfers power from engine to wheels; negative torque lets an overrun wheel back-drive the engine and applies engine braking. Gear efficiency is applied in the direction of power flow. A stateless per-tick impulse cap uses the engine inertia and four wheel-spin inertias, after the engine's free combustion/drag change, to prevent clutch transfer from reversing the remaining slip in the isolated drivetrain estimate. The torque and power checks cover both directions. The body kernel still handles contact and tire forces.

The state remains float64 with the original 31 body values followed by engine angular speed at index 31 and remaining fuel at index 32. Telemetry adds `throttle_fraction`, `fuel_flow_kg_per_s`, signed normalized `clutch_slip` in [-1, 1], raw `clutch_slip_rad_s`, `engine_spinning` and `combustion_active`. The flow is an instantaneous, fuel-bounded estimate for the supplied `dt`; it is stateless and is not a hidden record of the preceding midpoint integration rate.

Fuel remains an inventory state and does not reduce body mass, inertia or CG as it burns. The supplied simulation data lists a 118.1 g `Tanque_Combustible` component, while the Blender mass script assigns the translucent tank an effective density of 380 kg/m³ described as a half-load approximation. The source does not define usable fuel volume or resolve how that approximation relates to the separate estimated 100 g starting inventory. The runtime therefore retains its estimated initial fuel inventory without changing body mass, to avoid double-counting an unverified tank load. Fuel slosh, moving CG, mixture and thermal dynamics remain unmodeled.

## Evidence

The frozen [baseline receipt](baseline/baseline.json), [recording](baseline/session-baseline.csv) and [metadata](baseline/session-baseline-recording.json) preserve the pre-edit run. The [candidate receipt](candidate/session-candidate.json), [recording](candidate/session-candidate.csv) and [metadata](candidate/session-candidate-recording.json) preserve the same 480-tick, 240 Hz control tape. Both runs completed with 481 samples, 33 state values and exact checkpoint/replay; their control-tape SHA-256 matches.

The [comparison receipt](candidate/comparison.json) reports `complete=true` and `solver_changed=true`. It compares recorded controls and all 33 state values, verifies the baseline and candidate CSV/metadata hashes, and retains a per-state [delta trace](candidate/state-delta.csv). The first state difference occurs at tick 84; the maximum absolute difference is 1.58×10⁻¹⁰ in wheel spin. Engine-speed and fuel traces are identical over this tape. The solver identity changed because the adapter behavior and version changed, even though this particular drive tape exercises almost entirely the same engine-leading torque path.

Focused checks passed: [Nitro dynamics 30/30](candidate/nitro-test-candidate.log), [vehicle data 35/35](candidate/bisonte-vehicle-data.log), and [shared vehicle dynamics 55/55](candidate/bisonte-vehicle-dynamics.log). The session verifier is [retained here](candidate/session-candidate.log). These checks establish software behavior and replay repeatability for this backend; they do not calibrate the estimated engine or establish physical handling accuracy.

The retained standard-library [comparison tool](../../../../../research/rc-monster-truck/monster-car-2/rcv36/physics/compare_replay.py) accepts a baseline directory, a candidate directory containing `session-candidate.csv` and `session-candidate-recording.json`, and a session verifier JSON or log:

```powershell
python research/rc-monster-truck/monster-car-2/rcv36/physics/compare_replay.py `
  --baseline-dir docs/research/rc-monster-truck/RCV-36/physics/baseline `
  --candidate-dir docs/research/rc-monster-truck/RCV-36/physics/candidate `
  --candidate-report docs/research/rc-monster-truck/RCV-36/physics/candidate/session-candidate.json `
  --output docs/research/rc-monster-truck/RCV-36/physics/candidate/comparison.json
```

`complete` indicates that the receipts, exported artifacts, same tape and exact candidate replay were verified. `solver_changed` is reported independently. A complete comparison can have differing state traces; it does not mean the changed solver is physically equivalent.
