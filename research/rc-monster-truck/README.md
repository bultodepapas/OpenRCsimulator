# RC vehicle research tools

The [RCV plan](../../docs/plans/rc-monster-truck.md) owns vehicle integration and remaining steps. This directory contains runnable research tools; dated results cover the [quarter car](../../docs/research/rc-monster-truck/RCV-04a/README.md), [four-corner support](../../docs/research/rc-monster-truck/RCV-04b/README.md) and [MT8 visual intake](../../docs/research/rc-monster-truck/RCV-14a/README.md).

## RCV-14a MT8 visual inspection

The supplied Bisonte MT8 draft can be inspected locally in Godot 4.7.2. The viewer loads the canonical `RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/MT8_Bisonte.glb` and the author's generated rig directly. It changes no authoring file and does not add a vehicle to the application catalog. Runtime bundling awaits the source-rights and binding work recorded in the intake report.

From the repository root on Windows:

```powershell
& ./research/rc-monster-truck/visual/preview.ps1
# Optional: -Language en -Pose cross -HideBody -ShowProxies
# Supply -Godot C:/Tools/Godot_v4.7.2-stable_win64_console.exe if needed.
```

The renderer needs a display. Drag the model to orbit; scroll to zoom. Use Tab/arrows/Space or the mouse for controls. FL/FR/RL/RR mean front-left/front-right/rear-left/rear-right as seen by a driver looking forward. Travel is in millimetres, positive for compression; positive steering turns left. The optional wheel animation shows the forward spin sign and does not move or drive the truck. The proxy toggle shows the six body/roof/side/bumper boxes; tire envelopes are not included. Reset restores camera, pose and wheel phase; visibility toggles remain as selected.

The inspector positions each posed truck just above its display floor. This is visual staging, not a gravity/contact solution. Its controls exercise the author's travel limits: −70 to +50 mm and ±30° steering. These are geometry limits, not calibrated physical parameters. The existing support bench has different synthetic dimensions and is deliberately not connected to this asset as if it were measured MT8 mechanics.

The scripts remain outside `app/`, so current game exports do not depend on the authoring directory. Linux/native Godot can launch the same inspector using an absolute script path:

```sh
GODOT="$(app/get-godot.sh)"
"$GODOT" --path app --audio-driver Dummy --script "$PWD/research/rc-monster-truck/visual/preview.gd" -- --lang=en --pose=cross
```

Save a screenshot and exit with `preview.ps1 -Capture C:/captures/mt8.png` or `--capture=/absolute/existing/directory/mt8.png`. The directory must already exist and the output filename must be fresh. Capture requires a real renderer; `--headless` is only for tests. The CLI refuses empty, duplicate or unknown options.

Verification commands (PowerShell):

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
$env:OPENRC_TEST_GODOT = $GodotRcv
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
$env:OPENRC_TEST_GODOT = $GodotRcv
python app/tests/test_rcv_support_cli.py
```

The new generator uses only the Python standard library. Regenerate its fixture with the same command without `--check` after an intentional reviewed oracle change. The canonical test runner includes both fixture-freshness and CLI suites, and discovers the numerical GDScript test automatically.
