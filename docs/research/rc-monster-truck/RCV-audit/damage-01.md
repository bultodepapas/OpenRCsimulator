# Damage boundary audit 01

Date: 2026-10-14. This audit reviews the bounded gameplay damage estimate attached to the MT8 ground vehicle. The damage values and thresholds are estimated gameplay parameters; these results do not calibrate or validate physical damage.

## Finding and change

The previous contact law treated drops in `total_energy_j` as impact energy after subtracting estimated wall-friction work. That telemetry also changes with rolling resistance, suspension and tire damping, and other mechanical dissipation. In the pre-fix 480-tick tangent corridor reproduction, the vehicle had four wheel-wall contacts and no hull contact, yet the law accumulated 3.8277 J of wall-episode energy and added 0.01015 front-body and 0.00609 drive damage. Total mechanical energy fell 12.204 J over the run; the residual was not an isolated collision-work measurement.

The current law requires a scalar translational speed drop of at least 0.05 m/s on an accepted fixed tick before contact energy can accumulate, with contact speed at least 0.4 m/s. It still derives the bounded event energy from total-mechanical-energy change after subtracting endpoint-averaged wall-friction work, so this gate reduces false wear in the tested cases but does not isolate collision work from braking, rolling loss, or suspension and tire dissipation.

Wall-contact episodes now include wheel-only contacts. When an event crosses the 2 J deadband, a hull-wall load routes the estimate to the body region and drive derate; a wheel-only wall load routes it to the contacting suspension corners. Separation clears the active episode energy. Bottoming damage now requires compressing travel while crossing the trigger or increasing beyond the stop; pre-existing overtravel while extending does not create a new event. Invalid zero quaternions, malformed contact evidence, negative contact loads, invalid model radii, and non-finite derived event energy are rejected before snapshot commit.

Snapshot semantics use damage version 2. The packed snapshot remains exactly 19 float64 values with its existing indices; propulsion throttle remains the only operational damage effect.

## Reproductions

The production-kernel fixtures run with Godot 4.7.2 stable. Full captured output is in [damage-01.log](damage-01.log), produced by [audit_damage.gd](../../../../research/rc-monster-truck/audit/damage/audit_damage.gd).

| Fixture | Evidence | Result |
| --- | --- | --- |
| Supported wheel-only tangent corridor, 480 ticks at 240 Hz (2 s) | Four wheel-wall contacts; no hull contact. Total energy fell 12.204 J, integrated wall-friction work was 8.221 J, and the residual was 3.983 J. | No body, drive, suspension, or episode-energy wear. |
| Supported hull-wall scrape, 240 ticks, wall friction coefficient 0.01 | Hull-wall load reached 375.0 N; road wheels stayed in contact; no wheel-wall contacts. Total energy fell 6.881 J, wall-friction work was 3.733 J, and the largest per-tick speed drop was 0.00294 m/s. | No damage fractions or drive wear. |
| Lateral wheel-only impact, 3 m/s | On tick 2, wheel-wall load reached 155.64 N, hull-wall load was zero, speed fell 0.1995 m/s, and total energy fell 2.344 J. | The two contacting suspension corners each reached 0.00647 damage; body and drive damage stayed zero. |
| Head-on hull-wall impact, 8 m/s | First contact at tick 112; hull-wall load 1469.02 N; speed fell 0.9105 m/s and total energy fell 31.946 J on the first contact tick. | Front-body damage was 0.1472 and drive damage 0.08832 at first contact; the impact remains represented. |

The focused unit test reports 175 checks and 0 failures. The damage-session replay/checkpoint test reports 19 checks and 0 failures; its captured output is in [damage-02-tests.log](damage-02-tests.log). The audit fixtures and tests are behavioral checks only; the last column is the configured estimate, not a physical severity claim.

Commands:

```powershell
python -B research/rc-monster-truck/verify_runtime.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/rcv-damage-audit --only test_rcv_damage test_rcv_damage_session damage-contact-audit
```

## Limits

The gate measures scalar translational speed loss. It can undercount angular or glancing impacts whose translational speed changes by less than 0.05 m/s. During an accepted contact event, the remaining total-energy residual can still include braking, rolling resistance, suspension damping, tire dissipation, and stored-energy changes; the current telemetry does not isolate normal collision work. The two no-wear scrape fixtures show behavior for those specific supported, low-speed-loss conditions and do not establish universal scrape immunity. Model strengths, deadband, power cap, and damage fractions remain estimated and need calibration against measured RC-vehicle impacts before they can support physical claims.

The damage sidecar does not alter `VehicleDynamics` or the native contact kernel. The retained model and kernel identities for this run are:

| File | SHA-256 |
| --- | --- |
| `app/physics/ground_vehicle/vehicle_damage.gd` | `abb5599fecd0623a358b14a493c9d11e1b0b236ede85c35125b70b83a8792197` |
| `app/physics/ground_vehicle/vehicle_dynamics.gd` | `957b3398d114ae57c71c455c1f1054f9b4646a793712d6e9f719aeef5d6a1a22` |
| `app/data/vehicles/ground/mt8_bisonte.json` | `425f2a3fe810f82d609ad2b9dd9618b9fb45bcd813df57873cd8bc8759a750a5` |
| `research/rc-monster-truck/audit/damage/audit_damage.gd` | `9b60e1e8e97fc13d2d075bc0be25ac3bdea7b91707a3e20237e8d45496b6b7f7` |
| `app/tests/test_rcv_damage.gd` | `58e64a0fdf8cce748b1a9f0cef8083619937aeb061d743da020544e7acc8143e` |
| `app/tests/test_rcv_damage_session.gd` | `16c176a4edf681263ba309d28d838e9892ef0a02012ab00616cf3107bcbd8287` |
