# Flight logging and replay

Current fixed-wing workflow; marker debrief added 2026-10-28. Owner: physics/simulation, FL-01…05.
Records fixed-wing flights for handling investigations. The existing **T** CSV trace,
helicopter recorder and truck recorder retain their own contracts.

CSV export validates declared input roles, and replay checks those roles against the
restored aircraft. Historical logs without named layouts retain their original
4/5/6/7-channel interpretation. A malformed or conflicting declaration is refused
before export; matching channel counts alone cannot authorize replay. The versioned
fixed-brake branch now connects to Session/Main for explicitly admitted brake
hardware, with its own law/index metadata and optional flap channel. Legacy fixed
and retractable roles remain unchanged. [Reader guard](research/ground-physics/GP-12/evidence/input-role-replay/README.md)
and [control integration](research/ground-physics/GP-12/evidence/fixed-brake-input/README.md)
have separate source identities. Legacy Trace v17 carries the added role; its generic
inspector does not establish physical validation, and older physics validators refuse it.

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

For prepared runway, airborne/half-power, hand-launch and reload routes, rejected
reset candidates leave the old flight and recording intact.
After physical commit, the reset notification closes the old recording before the
new tick0 sample. Its footer and any intervening pause event use the explicitly
captured old checkpoint/tick, not the new flight. A publication observer fault
closes that accepted boundary and pauses the new flight; it does not undo the
physical reset. Reload uses the explicit commit receipt: refusal cannot be called
reloaded, and a committed observer fault cannot claim the previous flight was
retained. Intentional successful airborne fallback remains a separate accepted
replacement. Restore uses the same transaction and old closing context: refusal
leaves the old writer open, while accepted restore closes it before the kernel's
automatic pause, without a stepped sample. It remains paused replay with disabled
live input and the existing noncredit statistics branch. A committed observer
fault remains an accepted, paused restored frame. Pending weather selection now
closes the old recording through the same guarded context, without a tick or
statistics credit; its subsequent explicit reset still owns the physical start.
Pending shaft selection now uses the same guarded context and explicit physical reset requirement. [Shaft selection contract](research/ground-physics/GP-14/README.md#accepted-pending-shaft-selection-gp-14i). [Start contract](research/ground-physics/GP-14/README.md#common-start-and-reload-transactions-gp-14e),
[restore contract](research/ground-physics/GP-14/README.md#accepted-restore-publication-gp-14f),
[weather selection contract](research/ground-physics/GP-14/README.md#accepted-pending-weather-selection-gp-14h).

After [developer setup](TOOLS.md#developer-setup), run from the repository root.
Select your installed engine, then launch a recording:

```powershell
$env:GODOT = 'C:\Tools\Godot_v4.7.2-stable_win64_console.exe' # Set to your installed path.
python tools/flight_log/flight_log.py record --out "tmp/my-flight.orfl"
```

For Linux/Bash, set `export GODOT="$(app/get-godot.sh)"` and use `python3` in the
commands below. Engine selection is `--godot <path>`, then `GODOT`, then the pinned
Windows console executable in `.tools`. A supplied executable name can resolve
through PATH; the launcher does not automatically search for a Linux engine.
`--aircraft gp-extra-300s-60` selects another catalog ID. Record mode waits for normal
application exit unless an explicit timeout is supplied. Export/replay default to
300 seconds; increase `--timeout` for long recordings. Never kill the app just to
stop recording: press F10, then close it normally.

Equivalent engine command, also usable without Python:

```powershell
& $env:GODOT --path app -- --quick-flight --flight-log=C:/captures/roll.orfl
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
body/auxiliary/continuous state, discrete mode, force/moment, derived air and live mass sample
byte for byte. It stops at the first discrepancy. The original engine, timestep and
solver source fingerprint must match. Different platforms are not presumed to
match: a successful comparison establishes only the run actually checked.

This replay is a numerical research tool. It exports the re-simulated flight for
analysis; it is not a 3D video player and does not reproduce cameras, smoke or sound.
Export works independently of current solver identity. Exact replay currently
requires available solver source fingerprints; compiled packages without source
fingerprints must be analyzed from a matching source checkout, and compatibility
is still checked rather than assumed.

## Debrief marked maneuvers

```powershell
python tools/flight_log/flight_log.py debrief tmp/my-flight.orfl --out tmp/my-debrief
```

Use the same engine selection as replay (`--godot` or `GODOT`). The command first
runs the existing **exact replay** and then writes `debrief.json` beside
`flight.csv`, `replay.json` and `godot.log`. It needs a complete source log and
its compatible engine/solver. Existing output directories are refused.
`--timeout` bounds the Godot replay (default 300 seconds), not the subsequent
offline CSV reduction. There is no candidate or recovered-prefix debrief mode.

The `openrc-flight-debrief v1` document preserves the replay report, including
aircraft/configuration metadata, solver identities and events, plus SHA-256 hashes
of the source log, replayed CSV and replay report. The CLI produces its own
checked artifacts; it does not certify an arbitrary supplied CSV/report pair.
It refuses incomplete replay, omitted events, changed sources/solver identity,
invalid marker order/range and inconsistent row counts, tick bounds or timestamps.
On a reduction failure, retain the existing replay artifacts for diagnosis; no
successful `debrief.json` is produced.

F11 starts a marked inspection window. Equal-tick markers retain their ordered
labels together. The report includes the unmarked prefix, intervals between
distinct markers and the final marked tail. With no markers, it reports one
unmarked flight. A marker on the first or last tick can create a zero-duration
window with one state sample and no command intervals. A marker is the pilot's
label, not an automatically recognized maneuver.

- State statistics use **`[start_tick, end_tick]`**; adjacent windows share their
  boundary state. Altitude is `-down_m` relative to the local NED datum, **not
  terrain-relative AGL**. Other endpoint channels include TAS, alpha/beta and
  body rates. Values include start/end, delta and min/max, with units in names.
- Commands, sampled servos and loads use **`(start_tick, end_tick]`**. Row `k`
  describes the command for `k−1→k`; the first endpoint's preceding command is
  excluded. `loads_t_s_range` retains the loads' earlier sampling times. These
  are sampled ranges, not extrema proven between simulation ticks.
- `endpoint_samples` and `interval_samples` expose the distinction. State
  endpoint counts overlap across windows; interval counts partition the flight.

Debrief reads rows incrementally and keeps per-window accumulators; storage
scales with the bounded marker list rather than the number of flight rows.
It reports measurements from a numerical replay, without pilot grades, causal
diagnoses, handling recommendations or physical-validation claims. Use the
existing PlotJuggler workflow below to inspect curves. In-app coaching and
candidate branching are future work in [MOONSHOT](../MOONSHOT.md#6-first-engineering-transformation-flight-intelligence-from-verified-flight-records).
[FL-05 evidence](research/flight-logging/FL-05/README.md) records validation.

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

Equal array lengths do not establish compatible state semantics. For example, the
R02 wake changed from a coefficient to velocity in m/s. Historical exact replay
requires its original source; a new-law experiment needs a valid initial wake and
the same body/command scenario. The [retained comparison](research/physics-audit-2026-10-14/remediation/R11/README.md)
does not reconstruct unrecorded mid-flight wake history.

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
| Fuel / balance | `mass_kg`, `cg_offset_x_m`, `cg_offset_y_m`, `cg_offset_z_m`, propulsion state and body motion |

Use F11 event ticks in the report to select intervals. A practical session is a short
settled segment, a small isolated step/doublet, neutral recovery, then a repeat at a
different speed. Record the pilot's expectation separately. Compare forces using
their own `loads_t_s`, not the endpoint timestamp.

## Recorded data and timing

| Data | Meaning |
| --- | --- |
| `tick`, `t_s` | Exact integer accepted tick; time is `tick × dt`. Initial sample plus every accepted tick, normally 240 Hz. |
| Position / velocity / quaternion / rates | Float64 NED position in m and body FRD velocity in m/s at the fixed body datum; body-to-NED `[w,x,y,z]`; body rates in rad/s. These are committed endpoints. |
| `Fx_N`…`Mz_Nm`, `loads_t_s` | Body force/moment excluding gravity, from RK4 k1 at the interval start. At tick 0, initial loads. A mid-flight initial row retains the preceding step's k1 time. |
| `raw_*`, `stick_*` | Session input sample and shaped virtual/radio stick commands. These are not USB packets; keyboard raw throttle is a rate request. No HID identifiers or device enumeration are recorded. |
| `cmd_*` | Commands actually supplied to the physics tick, after input conditioning/rates/trim, before failures/servo dynamics. Gear/brake and flap channels only where supported. |
| `engine_rpm`, `srv_*` | Accepted shaft RPM and actual normalized servo outputs. |
| `aux_*`, `continuous_*`, `mode_*` | Complete owner-defined internal arrays, preserving float64 and int64. Includes active wheel/wake/turbulence/energy/propulsion states. Layout/law descriptions are in report metadata and [FlightSession](../app/sim/flight_session.gd). Unused subsystems add no arrays. |
| Air channels | Endpoint true airspeed, angle of attack, sideslip and NED wind. No extra aerodynamic force evaluation. |
| `mass_kg`, `cg_offset_*_m` | Accepted endpoint mass and live CG vector from the fixed body datum O in FRD. New logs declare four mass values in `layout.mass`; historical logs without this block remain exportable. |
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
The separate **T** CSV route includes `cmd_flaps`, `flap_fraction` and `flap_deg`
when flaps are installed. Current interactive recordings use `openrc-trace v14`
for accepted mass/CG or `v15` for finite-liquid stores and their source latch.
The `mass_kg` and `cg_body_x_m`/`cg_body_y_m`/`cg_body_z_m` channels use offsets
from O. Metadata `mass_base_trace_format` retains the underlying propulsion/atmosphere
layout. Glow traces declare their v3 line/source state through `openrc-glow-trace v2`;
readers keep explicit compatibility for historical layouts. Active fixed-wing
Recorder callers provide the accepted `mass_properties` callback. See the
[fuel standard](FUEL-SYSTEM.md); older technical traces retain their declared versions.

The log does not collect rendering frames, audio, GPU counters, operating-system
telemetry, calibration files or network traffic. Wall-clock observer cost is an
aggregate diagnostic and never enters physics. Detailed per-surface/RK-stage force
breakdowns remain focused research probes.

## Durability, cost and limits

The recorder is disconnected when off. It buffers at most 240 samples and 240 small
events, then writes a block and flushes; it does not retain a growing flight in RAM.
Writing/serialization is synchronous and happens on the simulation thread. This
bounds memory, but slow disks can still cause frame stalls; use a local disk and
measure on the target machine. Historical [fleet probe timings](research/flight-logging/FL-01/README.md)
do not qualify current target-host performance.

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

The native analysis CLI checks report writes and flush errors before announcing
success. A report-output failure returns nonzero and names the path and filesystem
error; partial output is not accepted evidence. Always check process status along
with the report. For retained engine diagnostics, wrap native invocations with the
[checked Godot runner](../tools/godot/README.md).

## Verification and developer workflow

```powershell
& $env:GODOT --headless --path app --audio-driver Dummy --script res://tests/test_flight_log.gd
& $env:GODOT --headless --path app --audio-driver Dummy --script res://tests/test_flight_log_ui.gd
& $env:GODOT --headless --path app --audio-driver Dummy --script res://tests/test_flight_log_report_write.gd
python -m unittest discover -s tools/flight_log -p "test_*.py"
```

`app/test.sh` discovers the GDScript tests. The native UI test can also run without
`--headless`, saving an ignored capture under `tmp/`. Tests use isolated inputs and
disposable log files; no golden flights or accepted aircraft data are rewritten.

[FL-01…04 source research, implementation and verification](research/flight-logging/FL-01/README.md).
These are software checks; independent measurements and RC pilot feedback remain
necessary for physical accuracy and flight feel.
