# RC vehicle research tools

To use the integrated Bisonte, start with [Drive and experiment](#drive-and-experiment). For acceleration, use the [pinned native build guide](native/README.md). Current test results and captures are in the [runtime evidence](../../docs/research/rc-monster-truck/RCV-runtime/README.md).

The [RCV plan](../../docs/plans/rc-monster-truck.md) owns vehicle integration and remaining steps. This directory contains runnable research tools; dated results cover the [quarter car](../../docs/research/rc-monster-truck/RCV-04a/README.md), [four-corner support](../../docs/research/rc-monster-truck/RCV-04b/README.md) and [MT8 visual intake](../../docs/research/rc-monster-truck/RCV-14a/README.md).

## RCV-14a MT8 visual inspection

The supplied Bisonte MT8 draft can be inspected locally in Godot 4.7.2. The preview still loads the canonical `RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/MT8_Bisonte.glb` and the author's generated rig directly. The user authorized inclusion and modification of this delivery; the reviewed [bundled GLB](../../app/assets/vehicles/mt8-bisonte/MT8_Bisonte.glb) and spec are pinned in the app, with the runtime [rig adapter](../../app/vehicles/ground/mt8_rig.gd) and [model adapter](../../app/vehicles/ground/mt8_model.gd). The runtime model is experimental and is not a calibration of a production RC truck.

From the repository root on Windows:

```powershell
& ./research/rc-monster-truck/visual/preview.ps1
# Optional: -Language en -Pose cross -HideBody -ShowProxies
# Supply -Godot C:/Tools/Godot_v4.7.2-stable_win64_console.exe if needed.
```

The renderer needs a display. Drag the model to orbit; scroll to zoom. Use Tab/arrows/Space or the mouse for controls. FL/FR/RL/RR mean front-left/front-right/rear-left/rear-right as seen by a driver looking forward. Travel is in millimetres, positive for compression; positive steering turns left. The optional wheel animation shows the forward spin sign and does not move or drive the truck. The proxy toggle shows the six body/roof/side/bumper boxes; tire envelopes are not included. Reset restores camera, pose and wheel phase; visibility toggles remain as selected.

The inspector positions each posed truck just above its display floor. This is visual staging, not a gravity/contact solution. Its controls exercise the author's travel limits: −70 to +50 mm and ±30° steering. These are geometry limits, not calibrated physical parameters. The existing support bench has different synthetic dimensions and is deliberately not connected to this asset as if it were measured MT8 mechanics.

The inspection scripts remain outside `app/`; the game consumes its reviewed, bundled copy and adapter rather than resolving the authoring directory at runtime. Linux/native Godot can launch the same inspector using an absolute script path:

```sh
GODOT="$(app/get-godot.sh)"
"$GODOT" --path app --audio-driver Dummy --script "$PWD/research/rc-monster-truck/visual/preview.gd" -- --lang=en --pose=cross
```

Save a screenshot and exit with `preview.ps1 -Capture C:/captures/mt8.png` or `--capture=/absolute/existing/directory/mt8.png`. The directory must already exist and the output filename must be fresh. Capture requires a real renderer; `--headless` is only for tests. The CLI refuses empty, duplicate or unknown options.

The canonical `app/test.sh` runs intake freshness, Python mutation tests, visual articulation and both inspector languages. Focused native commands (PowerShell):

```powershell
python -B research/rc-monster-truck/asset_intake.py --check
python -B research/rc-monster-truck/test_asset_intake.py
$RcvGodot = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
& $RcvGodot --headless --path app --audio-driver Dummy --script (Resolve-Path 'research/rc-monster-truck/visual/test_mt8_visual.gd').Path
& $RcvGodot --headless --path app --audio-driver Dummy --script (Resolve-Path 'research/rc-monster-truck/visual/test_preview.gd').Path
```

[asset_intake.py](asset_intake.py) inventories source hashes, geometry, articulation, materials and remaining handoff findings. Generate its JSON with the same command without `--check` only after reviewing a changed delivery. [mt8_visual.gd](visual/mt8_visual.gd) separately pins the reviewed GLB/spec/rig bytes before loading the author rig; a changed file refuses preview until explicitly reviewed and repinned. `.gitattributes` preserves those delivery bytes across checkouts. The adapter maps accepted source node names directly; no source pivots are renamed. It accepts complete four-corner poses, rejects invalid/nonfinite/out-of-range input before changing any node, and converts positive forward spin to the delivered negative local-X angle.

## RCV-04a suspension bench

Implemented: a float64, two-mass vertical quarter-car model, strict quantity/provenance validation, an independent matrix-exponential reference, and headless CSV/JSON experiments. It does not depend on Blender. It is not a selectable truck, the full ground-vehicle data contract, a checkpoint format, or a calibrated RC vehicle.

| File | Role |
| --- | --- |
| [quarter_car.gd](../../app/physics/ground_vehicle/quarter_car.gd) | Equilibrium, forces, derivative, energy and two-substep RK4 |
| [suspension_bench_data.gd](../../app/physics/ground_vehicle/suspension_bench_data.gd) | Executable strict `openrc-suspension-bench`, version 1 contract |
| [suspension_bench.json](suspension_bench.json) | Hand-authored synthetic input; every quantity carries value, unit, kind and source |
| [generate_suspension_reference.py](generate_suspension_reference.py) | Independent standard-library Python matrix exponential; source of the generated fixture |
| [suspension_reference.json](fixtures/suspension_reference.json) | Generated damped/undamped reference and oracle consistency checks; never edit by hand |
| [run_suspension_bench.gd](run_suspension_bench.gd) | Standalone release, drop and moving-road experiments |
| [test_rcv_suspension.gd](../../app/tests/test_rcv_suspension.gd), [CLI tests](../../app/tests/test_rcv_suspension_cli.py) | Numerical, input-contract and real-process export checks |

State order is `[z_s, z_u, v_s, v_u]`: sprung and unsprung heights in upward metres, then upward velocities in m/s. This local test coordinate is deliberately distinct from the aircraft NED/FRD convention. Parameters entering the kernel must have passed the loader; direct kernel calls assume four finite state values, finite road heights, positive finite `dt`, and a deterministic road callback. No engine vector types hold simulation state.

For masses `m_s,m_u`, spring rate `k_s`, damping `c_s`, rest separation `L`, tire stiffness `k_t`, radius `R`, gravity `g`, and prescribed road height `h(t)`:

```text
spring compression = L - z_s + z_u
F_s = k_s (L - z_s + z_u) + c_s (v_u - v_s)
tire compression = max(R + h - z_u, 0)
F_t = k_t max(R + h - z_u, 0)
m_s a_s = F_s - m_s g
m_u a_u = F_t - F_s - m_u g

static z_u = R + h - (m_s + m_u) g / k_t
static z_s = z_u + L - m_s g / k_s
```

The suspension spring is bilateral; the tire force is unilateral. The spring rate and damping are effective vertical wheel rates, not shock rates or Blender dimensions. There is no tire damping, friction, spin, steering, suspension travel stop, linkage geometry, variable chassis inertia or body collision. Do not use these equations to infer rollover or whole-vehicle jump behavior.

Energy includes both masses' kinetic and gravitational energy, spring energy and compressed-tire energy. For this model, `dE/dt = F_t * dh/dt - c_s * (v_s-v_u)^2`. A moving road supplies energy. Stationary-road energy conservation applies only with zero damping; damped motion must lose energy, with separately bounded contact-crossing integration error.

Each public tick contains **two fixed equal RK4 substeps**, each evaluating road height at all four stage times. The shared integrator's `axpy` is reused; its quaternion-normalizing finalizer cannot process this four-value state. At 240 public Hz the internal RK4 rate is 480 Hz. This bounded choice passed the synthetic fixture; arbitrary user parameter combinations are not automatically numerically qualified.

## Run on Windows

From the repository root with the [pinned engine](../../docs/TOOLS.md):

```powershell
$GodotRcv = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
$RcvRunner = (Resolve-Path 'research/rc-monster-truck/run_suspension_bench.gd').Path
New-Item -ItemType Directory -Force .tools/rcv | Out-Null
& $GodotRcv --headless --path app --audio-driver Dummy --script $RcvRunner -- --scenario=drop --hz=240 --duration=2 --out=../.tools/rcv/drop.csv
```

The script path is resolved before launching Godot. `--out` and an optional `--profile` are resolved relative to **`app/`**, unless absolute or `res://`/`user://` paths. The output directory must exist. `--out` must end in `.csv`; its companion replaces that extension with `.json`. Neither path may replace the input profile. Existing output files are replaced.

| Option | Values / behavior |
| --- | --- |
| `--scenario` | `release` (default): raise sprung mass 10 mm from equilibrium; `drop`: raise both masses 50 mm; `bump`: prescribed 5 mm sine-squared road lift between 0.25 and 0.45 s |
| `--hz` | 240 (default), 480, 960, 1920 public ticks and output samples per second |
| `--duration` | Default 2 s; positive, at most 30 s, and a positive integer number of ticks |
| `--profile` | Optional `openrc-suspension-bench` v1 JSON; default is the synthetic profile beside this guide |
| `--out` | Required CSV path; absolute paths are recommended for external automation |

The `bump` scenario is a moving vertical support input. It does not implement a wheel rolling horizontally over an obstacle or establish obstacle-envelope contact. All quantities are experimental, except the explicitly chosen conventional gravity. The runner exports every public tick including time zero, so a one-second 240 Hz run has 241 rows. CSV includes both positions/velocities, spring/tire forces and compressions, damper power, mechanical energy and boolean contact. JSON records model/run format, input-byte SHA-256, output SHA-256, completion, public rate/substeps, counts and ranges. Profile validation consumes the same byte snapshot used for its hash.

Malformed inputs or non-finite execution exit with status 1; success exits 0. A runtime or write failure can leave partial output. Consumers must require exit 0, `complete: true`, the expected sample count and a matching CSV hash; a previous summary alone does not prove a new run succeeded. This research CLI is not a transactional vehicle session.

## Verify or regenerate

```powershell
python research/rc-monster-truck/generate_suspension_reference.py --check
& $GodotRcv --headless --path app --audio-driver Dummy --script res://tests/test_rcv_suspension.gd
$env:OPENRC_TEST_GODOT = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64.exe').Path
python app/tests/test_rcv_suspension_cli.py
& $GodotRcv --headless --path app --audio-driver Dummy --script res://tests/test_golden.gd
```

Regenerate the independent fixture with `python research/rc-monster-truck/generate_suspension_reference.py` only after reviewing an intentional oracle/input change. The Python generator has no third-party dependencies and uses `exp(A*t)` by scaling, Taylor series and squaring, independently of the GDScript RK4. Its linear solution is valid only while contact persists; dense contact checks are included. The GDScript test independently verifies its parameter values match the profile.

The canonical Linux/CI [app/test.sh](../../app/test.sh) runs fixture freshness, CLI tests, source guards, script parsing and all `test_*.gd` scripts. No aircraft golden data is regenerated by this track. Passing this bench is software verification; measuring a real truck and qualifying a complete vehicle tick remain future work.

## RCV-04b four-corner support

The [four-corner kernel](../../app/physics/ground_vehicle/four_corner.gd) couples sprung-body heave, roll and pitch to four independently moving vertical hub masses: seven coordinates and seven rates in `PackedFloat64Array`. It is a small-angle vertical test rig. It does not implement horizontal driving, yaw, full rigid-body rotation, suspension linkage transport, travel stops, friction, wheel spin, body collision or rollover. It is not the production truck mechanical-state decision.

Coordinates are **x forward, y left, z up**, with corners **FL, FR, RL, RR**. Positive roll raises the left side; positive pitch lowers the nose. This bench frame differs from the aircraft body FRD frame and the model's Godot rendering frame. The state is:

```text
[body_z, roll, pitch, hub_z_FL, hub_z_FR, hub_z_RL, hub_z_RR,
 body_vz, roll_rate, pitch_rate, hub_vz_FL, hub_vz_FR, hub_vz_RL, hub_vz_RR]
```

Linear/angular coordinates use m/rad and rates use m/s or rad/s. At corner `i`, the body mount height is `z + y_i*roll - x_i*pitch`; its speed uses the same linear mapping. Each corner uses the quarter-car force laws. A suspension force contributes `[F_s, y_i*F_s, -x_i*F_s]` to the three body generalized loads and `-F_s` to its hub. Tire load acts on the hub once. The body mass and four hub masses are disjoint; fixed roll/pitch inertias belong only to the constrained sprung assembly. No full-vehicle angular-momentum claim follows from these linearized equations.

The [support profile](support_bench.json) has its own strict [loader](../../app/physics/ground_vehicle/support_bench_data.gd), `openrc-support-bench` version 1. The sprung mass is **total**, while unsprung mass, spring/damper/tire coefficients, radius and rest separation are **per corner**. Additional quantities are roll/pitch inertia, front/rear axle x stations relative to the sprung CG, and half track. All four corners currently share constitutive parameters. Arbitrary nonempty profile IDs identify separately named experiments; the source-byte hash distinguishes exact recipes. Unknown fields and invalid quantities fail closed.

`equilibrium` solves the coupled three-coordinate support system, then reconstructs the four hub heights. Under positive gravity it requires four positive tire loads; it refuses a saddle/road geometry whose four-contact solution needs a tensile ground force. This is not an active-set solver for three-wheel parking. With exactly zero gravity, a planar road permits a neutral pose with uncompressed tires/springs; a nonplanar road cannot satisfy that neutral condition and is rejected. The loader also refuses full-radius tire compression and inverted spring mounts in the default flat pose. Extreme ill-conditioned geometry can fail the pivoted solve.

The two equal RK4 substeps per public tick are retained and separately qualified by the [14-state independent reference](fixtures/support_reference.json), generated by [generate_support_reference.py](generate_support_reference.py). The generator builds mass, stiffness and damping matrices from the elastic-energy Hessian; its generalized matrix exponential reuses scalar matrix primitives from the earlier Python oracle. Symmetric heave reduces to the earlier quarter-car implementation. Changing axle stations relative to the CG is a synthetic rig experiment, not a physically consistent real ballast move; actual ballast must also update the full mass/inertia inventory later.

## Run four-corner experiments

From the repository root:

```powershell
$GodotRcv = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
$RcvSupport = (Resolve-Path 'research/rc-monster-truck/run_support_bench.gd').Path
New-Item -ItemType Directory -Force .tools/rcv | Out-Null
& $GodotRcv --headless --path app --audio-driver Dummy --script $RcvSupport -- --scenario=front_left_bump --hz=240 --duration=2 --out=../.tools/rcv/support-run01.csv
```

The runner accepts `--scenario=heave|roll|pitch|front_left_bump|drop`; `--hz=240|480|960|1920`; `--duration` (default 2 s, positive integer tick count, maximum 30 s); optional `--profile`; required `--out`; and `--timing=true|false` (default false). Path resolution follows the quarter-car runner. **Choose a fresh output basename:** this runner refuses an existing CSV or JSON sidecar, avoiding stale success metadata after a failed new run. Runtime failures can still leave a partial CSV with no success summary; require exit 0, completion, expected row count and matching CSV hash.

| Scenario | Initial condition / support input |
| --- | --- |
| `heave` | Raise the sprung body by 5 mm from equilibrium |
| `roll` | Add 0.01 rad positive roll |
| `pitch` | Add 0.01 rad positive pitch |
| `front_left_bump` | Prescribe a 5 mm sine-squared vertical lift at the FL support between 0.25 and 0.45 s |
| `drop` | Raise body and all hubs by 30 mm |

These are stationary rig experiments, including a moving support input, not a truck driving over a spatial obstacle. The runner stops if a sampled state is nonfinite or absolute roll/pitch exceeds 0.1 rad. It does not clamp angles or right the body. That bound protects this runner's declared small-angle scope; it is not a validated physical envelope or an internal-stage peak detector.

CSV contains all 14 states, four road heights, per-corner tire/spring force and compression/contact, total energy and damper loss. The versioned JSON sidecar identifies input/CSV hashes, model/state layout, rate/substeps, **public-tick sampled** force/angle peaks and contact counts. Internal-stage peak contact loads remain a future production trace requirement.

Optional timing warms a separate state for 240 ticks, resets to the original initial condition, then measures each `Rig.step`: both substeps and all road callbacks. It reports nearest-rank median/p95/p99/max and costs of steps whose contact flags differ at the next public sample. It excludes telemetry, output, rendering, session, tires' tangential mechanics and obstacle queries. Timing does not change simulation time/state or CSV output. These diagnostics cannot establish the plan's complete-truck 500-microsecond budget.

```powershell
python research/rc-monster-truck/generate_support_reference.py --check
& $GodotRcv --headless --path app --audio-driver Dummy --script res://tests/test_rcv_support.gd
$env:OPENRC_TEST_GODOT = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64.exe').Path
python app/tests/test_rcv_support_cli.py
```

The new generator uses only the Python standard library. Regenerate its fixture with the same command without `--check` after an intentional reviewed oracle change. The canonical test runner includes both fixture-freshness and CLI suites, and discovers the numerical GDScript test automatically.

## RCV-05+ full vehicle runtime experiments

The first ground-vehicle activity is now connected to the app. This research README is the canonical operating and experiment guide for the experimental Bisonte path. The dated [runtime evidence record](../../docs/research/rc-monster-truck/RCV-runtime/README.md) preserves garage, laboratory and drive captures, bounded checks, isolated package results and integration findings without duplicating operating commands.

### Drive and experiment

The estimated drivetrain provides 5.2 N m per wheel and a 120 rad/s torque-fade endpoint. Its four curves imply 624 W peak mechanical power; tire grip still limits acceleration. The lower estimated CG and 85/15 front/rear brake allocation improve launch and stopping stability. Reduce speed before bends and ramps; large steering inputs can still produce a skid or rollover. See the [current driving comparisons, physical assumptions and optimization evidence](../../docs/research/rc-monster-truck/RCV-handling/README.md).

Select **RC cars · Bisonte MT8** at the lower right of Home. The truck starts paused on the aircraft runway, in the same airfield used by Home and flight. The garage's **Driving controls** selector chooses a recognized gamepad when available, otherwise keyboard. Release the controls, wait for **Controls ready**, then select **Drive**, press Enter or the gamepad's Menu/Options button. Alternatively, launch the project with `-- --vehicle=mt8-bisonte`. This entry preserves the saved aircraft selection and carries Home's lighting and sky into the drive. The supplied Blender model and scripts are authorized by their owner for inclusion and modification.

| Action | Keyboard / mouse | Xbox / PlayStation |
| --- | --- | --- |
| Forward / reverse | W / S, or up / down arrows | RT / R2 forward; hold B / Circle + RT / R2 for reverse |
| Steer | A / D, or left / right arrows | Left stick |
| Brake | Space | LT / L2; overrides acceleration |
| Continue / garage | Enter / Esc | Menu / Options toggles |
| Camera | C cycles chase, operator, orbit and circuit overview; right-drag and wheel adjust the close view | X / Square while driving, or garage camera button |
| Recover and repair | R | Y / Triangle while driving, or garage recovery button |
| Headlights | L or garage lights button | Garage lights button |
| Record / stop and export | F9 or garage recording button | Garage recording button |

The garage selection belongs only to this car session; it does not change aircraft profiles or saved flight/menu devices. Choose **Keyboard** there to drive without the gamepad. Other devices cannot drive or navigate the garage, and a newly connected gamepad never takes over an active session. Raw radios, unmapped joysticks and steering wheels do not yet have a car mapping; their presence does not block keyboard driving. The car uses the fixed driving scheme above rather than aircraft channel/action remaps. Prompts follow the recognized device family.

Steering and triggers have matching neutral/output deadzones (12% and 4%); input above the deadzone retains proportional control and reaches full travel. Focus loss, disconnection and invalid samples pause the activity; returning focus never resumes automatically. After a disconnect, choose a connected gamepad or **Keyboard** in the garage, release its controls, then continue explicitly. The click samples the current controls, so a newly held trigger cannot reuse a previous neutral sample. Recovery marks the run as assisted. Reset starts a new valid run. Neither operation silently qualifies a landing or experiment. [Controller audit, native captures and verification](../../docs/research/controller-support-2026-10-14/README.md#rcv-05-r1-car-controller-audit).

Choose **Free drive** or **Physics lab**. The location selector provides the runway center/end and, in the default field, circuit entries for ramps, the wall slalom and rollers. The operator camera uses the field's pilot station. Lab changes apply by an explicit reset: gravity 0–2×, grip 0.15–2×, spring rate 0.5–2×, damping 0.25–2×, and 0–1.5 kg ballast at 0.03–0.35 m height. Ballast updates mass, CG and inertia together. The body toggle exposes the suspension; contact markers and travel plots are read-only views of the accepted simulation state.

The production activity reuses `FieldLoader`, `World`, `GroundSurfaces` and `GroundTerrain`, including the resolved lake bed. The default runway is short grass, not asphalt. Terrain heights/normals and surface factors come from the aircraft field; truck tire coefficients remain estimates. The default field now has a dirt obstacle circuit north of the runway, connected by an access lane at E=-10 m. Its two banked bends, two tabletops, three rollers and five wall boxes share authored geometry with the RC contact sampler and renderer. The initial spawn remains on the runway. Custom fields do not receive this fixed layout. Select **Circuit overview** to locate the loop; enter **Circuit · Ramps** for the eastbound jump straight, **Circuit · Rollers** for the westbound rhythm straight, or **Circuit · Wall slalom** for the infield branch. Approach the ramps straight and release throttle before landing; start the wall slalom slowly. Geometry, sources and checks are in the [track evidence](../../docs/research/rc-monster-truck/RCV-track/README.md). The course belongs to the RC activity; it does not alter aircraft flight/contact equations. Decorative scenery does not become a truck collision solid, and lake-bed contact does not add buoyancy or water drag.

The synthetic `practice.json` course remains a research fixture through `Session.prepare_default()` and the explicit `use_practice_fixture` test seam. Existing jump, bump and friction campaigns keep their original terrain and identities; it is no longer the player's default environment or a menu destination.

Dust follows moving, contacting tires on dirt/grass; asphalt and airborne wheels do not emit it. Body and tire grime accumulate during the drive. Headlights follow Home's lighting and can be toggled with **L**; brake and reverse lamps follow the controls independently. The laboratory lists each wheel's travel in millimetres alongside normal load and slip. These render effects do not alter accepted physical state.

Impacts can dent the private body mesh, move the bumpers inward and reduce propulsion. The HUD reports condition and remaining drive authority. Severe suspension bottoming is recorded as estimated damage, but does not change spring/damper parameters or detach wheels. **R** recovers, repairs and cleans the truck while marking the run assisted. Reset starts an intact valid run. See [effects, damage and suspension evidence](../../docs/research/rc-monster-truck/RCV-effects/README.md) for scope, assumptions and captures.

**Save state / Restore** uses `user://rcv/checkpoint.json`. Version 3 preserves the physical state, damage/contact episode state and the controls actually applied after propulsion derating. Checkpoints are tied to the vehicle, course, solver and backend build; older/incompatible states are refused and accepted restores remain paused. Restoring preserves damage but clears cosmetic grime and particles. Version 3 recordings export CSV plus JSON identity/event metadata under `user://rcv/`, including damage and requested/applied controls. The ten-minute recording limit pauses with the data retained. Export failures retain the recording and prevent a destructive reset, parameter change, restore or exit until saving succeeds.

The [strict RC audit](../../docs/research/rc-monster-truck/RCV-audit/README.md) corrects contact-damage attribution, interrupted-recording provenance, save recovery, landing scoring and render-input/setup failures. Damage snapshot version **2** retains 19 float64 values but changes impact classification; earlier damage-version checkpoints are refused, so start a new run. Failed checkpoint replacement preserves the previous file; if rollback also fails, the garage shows its backup path and Restore can discover compatible backups after restarting. Fault-interrupted recordings remain exportable and are explicitly marked invalid. No power-loss or concurrent multi-process save guarantee is claimed.

The optional [native evaluator](native/README.md) is installed in this working tree for Windows/Linux x86_64. Generated libraries are ignored by Git: a fresh checkout requires the documented pinned build/install procedure to enable acceleration. Other installations use the GDScript reference backend. The reference backend exceeds the 240 Hz tick budget. Recent native Session measurements also exceed the 4.167 ms P95 budget in some runs; sustained target-machine qualification and the stricter 500 µs target remain open. See the [current timing scope and values](../../docs/research/rc-monster-truck/RCV-handling/README.md).

The research-only [runner](run_experiments.gd) uses the same strict vehicle/course loaders and 240 Hz dynamics kernel as the activity, currently one RK4 substep per public tick. Regression and step-refinement checks passed; target-machine performance qualification remains open. It injects controlled initial states directly because the interactive Session intentionally has no state-injection API. `braking` records four matched trials in one CSV (asphalt, gravel, grass and slippery); `bump` starts at the synthetic bump lane; `drop` starts 0.45 m above the supported start pose; `rollover` records neutral releases at 35°, 55° and 75° about the right-side tire line. The 35°/55° pair straddles a fixed-ground-edge `atan2(half_track, CG_height)` comparator. A second approximate spherical tire-center normal-moment estimate is derived from the tire radius and static compression; the 55°/75° pair brackets that estimate. Neither reference is a compliant-truck acceptance bound. The runner records per-wheel contact loss, per-probe hull contact, roll and slip. The [Python analyzer](analyze_recording.py) verifies source and recording hashes, independently checks sprung-plus-hub system center-of-mass ballistic motion before contact, reconstructs analytical bump heights and both rollover geometry references from raw profile data, and reports ideal constant-friction braking distances alongside the observed traces. The sprung chassis alone can depart from free-fall motion because suspension forces transfer motion internally.

Run a deterministic scenario from the repository root on Windows:

```powershell
$RcvGodot = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
$RcvOut = (New-Item -ItemType Directory -Force '.tools/rcv/experiments').FullName
$RcvRunner = (Resolve-Path 'research/rc-monster-truck/run_experiments.gd').Path
& $RcvGodot --headless --path app --audio-driver Dummy --script $RcvRunner -- --scenario=braking --duration=3 --output="$RcvOut/braking.csv"
python -B research/rc-monster-truck/analyze_recording.py "$RcvOut/braking.csv" --output "$RcvOut/braking.analysis.json"
& $RcvGodot --headless --path app --audio-driver Dummy --script $RcvRunner -- --scenario=rollover --duration=3 --output="$RcvOut/rollover.csv"
python -B research/rc-monster-truck/analyze_recording.py "$RcvOut/rollover.csv" --output "$RcvOut/rollover.analysis.json"
```

The runner accepts only `--scenario=braking|bump|drop|rollover`, required `--output=<fresh .csv>`, and optional `--duration=<seconds>` (default 3 s, maximum 15 s). Duration must represent a whole number of 240 Hz public ticks. The output directory must already exist; the runner refuses to replace either CSV or JSON sidecar. The CSV stores the full 31-value state and wheel/hull contact diagnostics at each public tick. The JSON sidecar binds the run to exact vehicle and course identities and the CSV hash. The analyzer requires `complete: true`, complete sample counts, monotonic tick times and matching bytes before producing a report.

The separate [activity jump driver](drive_jump_landing.gd) uses the actual activity, supported `jump_start` location and accepted driver controls, without state injection or recovery. Launch it as an external Godot `--script` with `-- --throttle-ticks=300 --output=<absolute-fresh.json>`; the existing parent directory is required and throttle duration must be 1–1200 ticks. Optional `--gravity-scale=0..2` applies the same explicit laboratory experiment and records its distinct identity. The driver records the actual accepted control tape and its hash, backend/model/course identities, wheel contacts, AIR-to-ground HUD transition and 120 settling ticks after the first landing. Its success gate additionally requires the existing landing toast, which needs more than 0.08 s airborne. The observed first hops were shorter and therefore correctly fail that additional gate; inspect the outcome instead of treating any written trace as success or extrapolating that window to later jumps.

The run inputs are all estimates where the original delivery supplied geometry only. Surface friction, masses, spring/damper values, motor/brake torque and inertias are not measured. The drop oracle applies only to the complete sprung-plus-hub center of mass before first contact. The bump check verifies that renderer/course geometry matches the analytic road function; it does not validate point-probed obstacle enveloping. The braking reference is ideal constant-friction kinematics and does not establish real stopping performance. The rollover experiments show only how this estimated model responds to the 35°/55° balance comparison and 75° over-center release; they do not validate a real rollover threshold, recovery or handling. The interactive R key performs a manual recovery that invalidates the run; natural self-righting qualification remains open.

### Bounded Windows runtime and package verification

Run the bounded Windows runtime and package evidence tools into a fresh evidence directory. Use the regular Godot executable for the Python-managed subprocesses; the timeout controller must own the actual process. The runtime verifier retains one log per check and a JSON receipt. The package verifier copies the current working-tree app without its import cache, includes the existing aircraft export plugin's external authoring proofs, and writes a Windows export, logs and a receipt.

```powershell
$RcvGodotApp = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64.exe').Path
$RcvEvidence = Join-Path $env:TEMP ("openrc-rcv-" + [guid]::NewGuid().ToString("N"))
python -B research/rc-monster-truck/verify_runtime.py --godot $RcvGodotApp --out (Join-Path $RcvEvidence 'runtime')
python -B research/rc-monster-truck/verify_package.py --godot $RcvGodotApp --out (Join-Path $RcvEvidence 'package')
```

Add `--include-menu` to the runtime verifier to also run the broad Home and Home-layout regressions. The truck menu transition test always runs. To verify RC independently when another aircraft's export proof blocks the shared application export, use `--isolated-rc --require-native` with a new package output directory. This changes only the disposable snapshot entry point and does not qualify the full application release. A separate `--isolated-rc --reference-backend` run verifies the compiled GDScript fallback without generated native artifacts.

The package verifier embeds its cost entry in the disposable project before exporting. Official Godot 4.7 release templates disable path overrides, so passing an external `--script` to a release executable would not prove that the benchmark ran. Successful cost evidence must identify `debug_build: false` and the expected backend. Package startup success and the two performance gates are reported separately.

Each runtime check has a 300-second timeout; package import, export and startup steps have 360-second timeouts. A timeout is a failed check even if a report was written. Inspect each receipt's status and check exit codes. The package report is a fresh copy of the current working-tree app plus required export proofs; it is not a clean Git clone or evidence for other operating systems. These bounded checks do not establish physical validity or target-machine frame pacing.

Run the generator freshness/mutation checks and process-level experiment tests with:

```powershell
$RcvGodot = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64.exe').Path
$env:OPENRC_TEST_GODOT = $RcvGodot
python -B research/rc-monster-truck/build_vehicle_data.py --check
python -B research/rc-monster-truck/test_vehicle_data_generator.py
python -B research/rc-monster-truck/test_experiments.py
```

These tools verify deterministic software behavior, not the remaining gates in the [active RCV plan](../../docs/plans/rc-monster-truck.md). Do not mark the vehicle calibrated, physically validated, roll-qualified or performance-qualified from these synthetic experiments.
