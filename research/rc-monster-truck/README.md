# RC vehicle numerical benches

The [RCV plan](../../docs/plans/rc-monster-truck.md) owns vehicle integration and remaining steps. This directory contains runnable research tools; [dated results](../../docs/research/rc-monster-truck/RCV-04a/README.md) record their verification.

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
