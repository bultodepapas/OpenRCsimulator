# Flight logging and replay

Current source feature, 2026-10-14. Owner: physics/simulation, FL-01…04.
Records fixed-wing flights for handling investigations. The existing **T** CSV trace,
helicopter recorder and truck recorder retain their own contracts.

## Quick start

1. Launch the simulator normally and fly any fixed-wing aircraft.
2. Press **F10** to start. A `REC` badge shows elapsed simulation time.
3. Press **F11** at the start of a maneuver or when a response feels wrong.
4. Press **F10** to finish. Restart, aircraft/weather changes and leaving the flight
   close the current recording. Start another recording explicitly for the next flight.
5. Keep the `.orfl` file and note the maneuver, expected response and observed response.

Files go to `user://flight_logs/`:

| Platform | Default location |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\OpenRC Simulator\flight_logs` |
| Linux | `~/.local/share/godot/app_userdata/OpenRC Simulator/flight_logs` |
| macOS | `~/Library/Application Support/Godot/app_userdata/OpenRC Simulator/flight_logs` |

The full path is printed in the console. Pausing records an event and flushes the
buffer; it adds no simulated flight time. F11 marks a simulation tick, not wall time.
Recording can begin midway through a flight; it captures the complete initial
physics checkpoint, including current propulsion, wind RNG and actuator state.

To launch directly into a recording from the repository root:

```powershell
python tools/flight_log/flight_log.py record --out "tmp/my-flight.orfl"
```

The launcher finds the native Windows Godot in `.tools`, `GODOT`, or PATH. Use
`--godot <path>` to select the [pinned engine](TOOLS.md#developer-setup).
`--aircraft gp-extra-300s-60` selects another catalog ID. Record mode waits for normal
application exit unless an explicit timeout is supplied. Export/replay default to
300 seconds; increase `--timeout` for long recordings. Never kill the app just to
stop recording: press F10, then close it normally.

Equivalent engine command, also usable without Python:

```powershell
& $GodotWindows --path app -- --quick-flight --flight-log=C:/captures/roll.orfl
```

Use a new file name. Existing recordings and analysis outputs are never overwritten.
The native recorder is included in the application; Python and Godot source scripts
are only needed for offline analysis. This feature is not a claim about previously
published download packages.

## Export, inspect and replay

Python 3 and the repository's Godot build are sufficient; no pip packages are needed.
Run from the repository root. Output directories must not already exist.

```powershell
python tools/flight_log/flight_log.py export tmp/my-flight.orfl --out tmp/baseline
python tools/flight_log/flight_log.py summarize tmp/baseline/flight.csv --out tmp/summary.json
python tools/flight_log/flight_log.py replay tmp/my-flight.orfl --out tmp/exact
python tools/flight_log/flight_log.py compare tmp/baseline/flight.csv tmp/exact/flight.csv --out tmp/exact-comparison.json
```

Export produces plain `flight.csv` plus a JSON report containing aircraft/weather
metadata, events, source identity, completion and recording statistics. CSV has a
normal first-row header and no metadata prelude. Reports and CSV belong together.
JSON reports show at most 10,000 events and expose `events_omitted` beyond that;
the original log retains all recorded events.

Exact replay restores the original accepted aircraft snapshot and environment,
feeds the recorded commands into the actual fixed-step solver, and checks each
body/auxiliary/continuous state, discrete mode, force/moment and derived air sample
byte for byte. It stops at the first discrepancy. The original engine, timestep and
solver source fingerprint must match. Different platforms are not presumed to
match: a successful comparison establishes only the run actually checked.

This replay is a numerical research tool. It exports the re-simulated flight for
analysis; it is not a 3D video player and does not reproduce cameras, smoke or sound.
Export works independently of current solver identity. Exact replay currently
requires available solver source fingerprints; compiled packages without source
fingerprints must be analyzed from a matching source checkout, and compatibility
is still checked rather than assumed.

## Compare a physics change

Preserve the baseline recording before changing data or code. Generate a candidate
aircraft through its owning source pipeline or the Workshop; never hand-edit accepted
generated aircraft data. Keep the candidate separate from the original.

```powershell
python tools/flight_log/flight_log.py replay tmp/my-flight.orfl --candidate C:/experiments/candidate.json --out tmp/candidate
python tools/flight_log/flight_log.py compare tmp/baseline/flight.csv tmp/candidate/flight.csv --out tmp/comparison.json
```

Candidate mode is explicitly **open loop**: it preserves the baseline body's position,
velocity and attitude, internal initial state, and post-conditioning command tape.
It uses candidate mass/inertia/configuration and the current solver. It does not
solve a new starting trim, replay device/rate/expo changes, or model pilot adaptation.
Layout, integration-law and checkpoint admissibility checks still apply; incompatible
candidates are rejected. An external starter/cut/mixture intervention replays its
recorded state edit at the same tick. Treat such intervals carefully when comparing
different propulsion configurations.

In particular, the R02 wing-wake state changed from a coefficient to velocity in
m/s. Equal array lengths do not make those checkpoints compatible. Use the original
source for historical exact replay. A new-law experiment must prepare a valid new
initial wake explicitly and retain the shared body/command scenario, as in the
[physics-audit comparison](research/physics-audit-2026-10-14/remediation/R11/README.md).
That experiment does not reconstruct an unrecorded mid-flight wake history.

Reports identify baseline/current solver fingerprints and whether they differ.
For an aircraft-only experiment require `solver_changed: false`; for a solver
experiment hold aircraft data fixed. Change one cause at a time. Do not label a
candidate run as an exact replay or as physical validation.

Comparison requires matching ticks, times and `cmd_*` controls. It reports first
numerical divergence, per-channel differences and separate position, velocity,
angular-rate and attitude errors. Quaternion comparisons account for `q` and `-q`
representing the same attitude. Summaries include duration, ranges and RMS values.
They do not assign realism scores or universal pass/fail thresholds.

## Plot with an existing free tool

Use [PlotJuggler](https://github.com/PlotJuggler/PlotJuggler) and its
[official CSV loader](https://github.com/PlotJuggler/pj-official-plugins/tree/main/data_load_csv).
Download it separately; no charting application is duplicated or bundled here.
Load `flight.csv`, choose `t_s` as the time column, and overlay baseline/candidate
channels. The export uses the loader's ordinary CSV structure; a particular native
PlotJuggler release has not been qualified in this repository.

Useful groups:

| Investigation | Overlay |
| --- | --- |
| Stick feel / lag / saturation | `raw_pitch`, `stick_pitch`, `cmd_pitch`, `srv_pitch`, `q_radps` (and roll/yaw equivalents) |
| Pitch response / pull-up | `cmd_pitch`, `srv_pitch`, `tas_mps`, `alpha_rad`, `q_radps`, `My_Nm`, `down_m` |
| Roll and adverse yaw | `cmd_roll`, `srv_roll`, `p_radps`, `r_radps`, `beta_rad`, `Mx_Nm`, `Mz_Nm` |
| Power response | `cmd_throttle`, `engine_rpm`, `Fx_N`, `tas_mps`, relevant continuous-state columns |
| Gear / braking | `cmd_gear_down`, `cmd_wheel_brake`, gear auxiliary states, loads and body motion |
| Flaps | `cmd_flaps`, the `aux_N` at metadata `flap_aux_index`, `srv_pitch`, airspeed, angle of attack and loads |

Use F11 event ticks in the report to select intervals. A practical session is a short
settled segment, a small isolated step/doublet, neutral recovery, then a repeat at a
different speed. Record the pilot's expectation separately. Compare forces using
their own `loads_t_s`, not the endpoint timestamp.

## Recorded data and timing

| Data | Meaning |
| --- | --- |
| `tick`, `t_s` | Exact integer accepted tick; time is `tick × dt`. Initial sample plus every accepted tick, normally 240 Hz. |
| Position / velocity / quaternion / rates | Float64 NED position in m; body FRD velocity in m/s; body-to-NED `[w,x,y,z]`; body rates in rad/s. These are committed endpoints. |
| `Fx_N`…`Mz_Nm`, `loads_t_s` | Body force/moment excluding gravity, from RK4 k1 at the interval start. At tick 0, initial loads. A mid-flight initial row retains the preceding step's k1 time. |
| `raw_*`, `stick_*` | Session input sample and shaped virtual/radio stick commands. These are not USB packets; keyboard raw throttle is a rate request. No HID identifiers or device enumeration are recorded. |
| `cmd_*` | Commands actually supplied to the physics tick, after input conditioning/rates/trim, before failures/servo dynamics. Gear/brake and flap channels only where supported. |
| `engine_rpm`, `srv_*` | Accepted shaft RPM and actual normalized servo outputs. |
| `aux_*`, `continuous_*`, `mode_*` | Complete owner-defined internal arrays, preserving float64 and int64. Includes active wheel/wake/turbulence/energy/propulsion states. Layout/law descriptions are in report metadata and [FlightSession](../app/sim/flight_session.gd). Unused subsystems add no arrays. |
| Air channels | Endpoint true airspeed, angle of attack, sideslip and NED wind. No extra aerodynamic force evaluation. |
| Events/interventions | Markers, pause/resume, stop/fault/reset reason; sparse changes outside integration, such as starter, mixture or cut, retain exact affected arrays before the next tick. |
| Initial context | Accepted model, physical ground/collision/lake setup, weather, checkpoint, engine/build/source identity. Captured once, not repeated per tick. |

Body velocity is not air-relative velocity. Positive `down_m` points down; altitude
above the NED datum is `-down_m`, which is not terrain clearance. Servo values are
fractions of maximum throw, not degrees. [Aircraft units/signs](AIRCRAFT_CONTRACT.md#coordinates-signs-and-units)
remain authoritative.

The optional flap channel is normalized 0–1. Its accepted actuator position is retained
in the auxiliary array; `flap_aux_index`, `flap_input_index`, `flap_max_angle_deg` and
`flap_law` identify the layout and interpretation. Multiply actual fraction by the
maximum angle for degrees down. Elevator servo output includes the authored flap mix;
`cmd_pitch` remains the pilot demand before mixing/failures. A recording with this
actuator cannot be replayed against a model that removes its state. Clean historical
recordings remain exportable and require their original source for exact replay.
The existing **T** CSV route uses `openrc-trace v12` with explicit `cmd_flaps`,
`flap_fraction` and `flap_deg` columns when flaps are installed.

The log does not collect rendering frames, audio, GPU counters, operating-system
telemetry, calibration files or network traffic. Wall-clock observer cost is an
aggregate diagnostic and never enters physics. Detailed per-surface/RK-stage force
breakdowns remain focused research probes.

## Durability, cost and limits

The recorder is disconnected when off. It buffers at most 240 samples and 240 small
events, then writes a block and flushes; it does not retain a growing flight in RAM.
Writing/serialization is synchronous and happens on the simulation thread. This
bounds memory, but slow disks can still cause frame stalls; use a local disk and
measure on the target machine. The short fleet probe observed roughly 7–10 ms of
logger work across 260 ticks in the first run (roughly 10–13 ms in a later run), not a
target-hardware performance qualification.

Each `.orfl` file starts with `ORFL0001`. Packets contain a bounded little-endian
32-bit length, SHA-256 digest and Godot Variant payload. Object decoding is disabled.
The header, ordered data blocks and footer are versioned. The footer contains row
counts, final tick and an ordered digest chain. This detects corruption, truncation,
reordering and dropped blocks; it is not a cryptographic signature proving authorship.

Limits: 16 MiB per packet, 512 MiB per file (normal stop reserves footer space), and
864,000 flight ticks, i.e. one simulated hour at 240 Hz. The initial aircraft/world
snapshot also has to fit the packet bound. Start another file for a longer session.
No automatic deletion or rotation removes previous flights.

Abrupt termination may lose the current unflushed block and leaves no completion
footer. Normal export/replay rejects such files. Recover verified **diagnostic data**
explicitly:

```powershell
python tools/flight_log/flight_log.py export tmp/interrupted.orfl --recover --out tmp/recovered
```

Recovery exports only complete, checksum-verified prefix blocks and labels the report
`complete: false` with a reason. It never certifies replay and cannot recover a damaged
header or unflushed samples. A partial CSV without its report can be mistaken for a
complete flight: retain both files. Disk/size errors stop recording visibly while
leaving the simulator available; inspect the resulting file before using it as evidence.

## Verification and developer workflow

```powershell
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_flight_log.gd
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_flight_log_ui.gd
python -m unittest discover -s tools/flight_log -p "test_*.py"
```

`app/test.sh` discovers the GDScript tests. The native UI test can also run without
`--headless`, saving an ignored capture under `tmp/`. Tests use isolated inputs and
disposable log files; no golden flights or accepted aircraft data are rewritten.

| Step | Delivered boundary / proof |
| --- | --- |
| FL-01 | Existing-code audit, primary sources and reuse decision. |
| FL-02 | Bounded recorder, tick observer, F10/F11 and direct-launch integration. |
| FL-03 | Strict reader, prefix recovery, CSV, exact replay and explicit candidate experiments. |
| FL-04 | Fleet observer equivalence/replay, corruption/cap/lifecycle checks, Python analysis and native UI verification. |

[Source research and measured evidence](research/flight-logging/FL-01/README.md).
These are software checks; independent measurements and RC pilot feedback remain
necessary for physical accuracy and flight feel.
