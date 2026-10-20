# AI flight companions

Status: experimental airborne slice, 2026-10-20. The remaining work and release
gates live in [the implementation plan](../AI_FLIGHT_COMPANIONS_PLAN.md).
[Verification and measured limits](research/ai-companions/AFC-00-06/README.md).
Follow-up evidence: [qualified profiles](research/ai-companions/AFC-02/README.md),
[cost attribution and equivalence](research/ai-companions/AFC-00-R1/README.md),
and [lifecycle checks](research/ai-companions/AFC-03-R1/README.md).

## Use

1. Choose **Club field** and a fixed-wing player aircraft on Home.
2. Open **More flight details → Flight companions**, enable companions,
   choose **1–3**, and Apply.
   Start with one; additional aircraft substantially increase CPU cost.
3. Fly. The companions launch airborne in separated circuits north of the runway.
4. **Pause → Session options → Flight companions** shows the current population.
   Apply changes, then **Restart flight** to rebuild the roster. Changes made here
   stay with this flight unless **Save these settings as the default** is selected.
5. **Remove companions now** immediately clears their sessions, models and audio.
   Restart brings back the configured roster. To keep them off, disable and Apply.
   Cancel discards the dialog draft.

Off is the default. Each companion uses the bundled Jensen Das Ugly Stik 60,
an experienced circuit controller, independent full aircraft dynamics, and a
bounded spatial engine voice. There are no duplicate cameras or field soundscapes.
Player aircraft selection does not change the AI aircraft.

The seed selects starting phase/direction and per-aircraft turbulence seeds.
Repeatability requires the same aircraft data, source, weather and initial roster.
The current roster is created only at tick zero; settings do not add aircraft
midflight. Menus, focus/controller holds and a stopped player simulation also stop
the companion clock.

## Current limits

| Setting or behavior | Available now |
| --- | --- |
| Field | Club field only; normal fixed-wing flights |
| Qualification | Exact aircraft, field, pilot and solver source identities; Godot 4.7.2 at 240 Hz. Changed or unavailable sources and other tick rates refuse admission |
| Weather | Reference atmosphere; mean wind ≤1.5 m/s, gust ≤0.6 m/s, updraft ≤0.15 m/s, turbulence RMS ≤[0.15, 0.15, 0.08] m/s |
| Aircraft/activity/skill | Ugly Stik circuits, experienced pilots |
| Population | Experimental fixed roster of 1–3; higher counts refused |
| Avoidance | Predicted closest approach biases heading/altitude; no guaranteed separation from arbitrary player maneuvers |
| Aircraft contact | Disabled; overlapping airplanes do not exchange contact forces |
| Terrain/scenery | Launch checks the nominal circuit corridor against actual session terrain, lake and collision proxies; ordinary contact/crash checks remain active. Only the player changes shared scenery damage |
| Crash/fault fallback | That companion stops, its voice is silenced, and status identifies it; restart or Remove clears it |
| Logging/checkpoints | Optional fixed-roster diagnostic capture links per-aircraft logs; no fleet restore or decision replay. A player-only paired checkpoint cannot save/restore while companions remain |
| Technical routes | Scripted flight, trace/capture, Workshop, synthetic electric demos, experimental aircraft-data routes and Natural Random do not admit companions |

Takeoff/landing cycles, other models, low passes, aerobatics, overtaking activities,
pilot difficulty choices, incidents, comic scenarios and busy-skies presets are
still planned. No control advertises them as available. No model, physics law,
solver frequency or golden flight was retuned to make this slice work.

The measured three-companion CPU workload misses the plan's initial fleet budget.
This is not a 60 fps or target-hardware qualification. A one-companion, 20-minute
headless flight completed all 288,000 ticks with stable node/object/resource counts
after 50 lifecycle cycles, including 10 visual/audio cycles. The three-companion
multi-seed endurance matrix, rendered soaks, finite-fuel recovery, fleet replay,
full crash presentation, translation coverage and platform package checks remain open.

## Developer entry points

Direct launches ignore Home preferences:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --quick-flight --companions=1 --companions-seed=20261020
```

`--companions=0` explicitly disables companions. Counts above 3, invalid seeds and
unsupported enabled configurations fail before the flight is accepted.

### Diagnostic capture

Add `--companions-record=<new absolute directory>` to a direct launch with
enabled companions. Quote the whole argument if the path contains spaces:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --quick-flight --companions=1 "--companions-record=C:/captures/companions-001"
```

The directory must not exist. The recorder starts at the common tick-zero
boundary, writes `manifest.json` and `player.orfl` plus `companion-<slot>.orfl`,
then writes `summary.json` when closed. **F11** marks every stream at the same
tick; **F10** closes the cohort. `FLEET REC` shows elapsed simulation time. Pause
adds no ticks. A normal stop, restart, reconfiguration, removal or flight exit
closes the current capture before sessions are replaced. Restart does not start
another recording or reuse the directory. The path is never saved in preferences.
`--flight-log` and `--companions-record` cannot be used together.

Capture stops automatically after 28,800 accepted ticks (120 simulated seconds).
It permits at most four streams, each using the existing 512 MiB file limit,
16 MiB packet limit and 240-row buffer. Manifest and summary are each limited to
256 KiB. This is an opt-in diagnostic using synchronous existing log writes and
close-time file hashing; recording latency and rendered performance remain
unqualified. Do not use a recording run as the uninstrumented performance baseline.

A writer error, crash, simulation fault, clock mismatch or emitted shared-scenery
damage change closes the cohort as incomplete. Runtime recording errors appear in
status/HUD and the console without stopping flight. An explicitly requested
capture that cannot start refuses the launch. An interrupted process can leave
files without a summary/footer; retain them as incomplete evidence.

The versioned manifest identifies the fixed roster, capture-local generation zero,
engine/build, admitted profiles, selected capture/admission source hashes and
common tick origin. These hashes do not identify the entire application. Exact
session checkpoints/RNG state remain in the `.orfl` headers. The summary records
file hashes, sizes and tick/row counts. Its `complete` flag describes capture
closure and common-clock alignment, not replay verification. Use the existing
[flight-log workflow](FLIGHT-LOGGING.md#export-inspect-and-replay) on **every**
stream to check its footer and exact replay. Capture assumes fixed world geometry;
direct geometry edits without a damage signal are unsupported and are not
detected each tick. It does not restore pilot integrators, replay AI decisions,
reconstruct shared-world events or establish exact fleet equivalence.

| File | Responsibility |
| --- | --- |
| `app/ai/companions/config.gd` | Bounded settings and explicit CLI overlay |
| `app/ai/companions/profile_loader.gd` | Launch-time validation of aircraft, controller, solver, field and engine qualification |
| `app/ai/companions/airspace.gd` | Continuous static circuit clearance and person/shelter footprint exclusions at admission |
| `app/ai/companions/fleet_record.gd` | Fixed-roster capture manifest, common-clock monitoring and bounded existing per-session writers |
| `app/data/ai/companions/aircraft/`, `fields/` | Source-bound Stik/Club profiles and measured circuit scope |
| `app/ai/companions/pilot.gd` | Float64 guidance, control demands and proximity response |
| `app/ai/companions/manager.gd` | Stable tick snapshots, population ownership, scenery-mask publication |
| `app/ai/companions/agent.gd` | One external-driver session and its render/audio adapter |
| `app/sim/flight_session.gd` | Validated external commands, spawn and single-tick seam |
| `app/main.gd` | Launch/refusal, deferred restart, status and checkpoint boundary |
| `app/ui/companions_dialog.gd` | Draft settings; Home/Pause owners perform persistence |

These are programmatically composed nodes, matching the current Main/UI pattern;
there is no second Main scene per airplane. Every AI session owns its own
`VehicleModel`. The kernel remains unchanged.

The player keeps its original tick driver. On planning ticks, `before_step`
captures tick N states; the player's successful `stepped` signal plans every AI
against that same snapshot, then advances each once. Between planning ticks, each
agent validates and stages its held command without recomputing observations.
Aircraft planning runs at 60 Hz and aircraft physics at 240 Hz. A rejected player
step never advances companions. Player damage is mirrored after all AI finish that
tick, for use at the next boundary. Remove disconnects all three player observers;
reconfiguring the same manager reconnects them once.

Profiles are validated once per manager launch, before replacing a live roster.
Each newly loaded companion verifies its accepted aircraft data against that
qualification. The field comparison includes normalized geometry, so retaining
the `default` ID after editing the field cannot reuse the qualification. The
records describe only the existing two-minute calm/gentle circuit matrix. Stall,
approach and maneuver-entry speeds remain unknown; long-duration qualification
remains a separate gate. Profile values do not retune the pilot or aircraft.

Before replacing a roster, `airspace.gd` checks every requested altitude band
against continuous obstacle bounds. It uses a 10 m radial allowance, 2 m vertical
allowance, a sphere enclosing accepted hull/gear/propeller contact geometry, and
2 m additional obstacle clearance. These allowances are engineering estimates,
not guaranteed tracking bounds or a rendered-mesh certification. Terrain uses
the existing analytic height bound; lake water includes the maximum wave height.
People and shelter/pavilion proxy footprints receive a conservative 30 m
horizontal exclusion at every altitude, as does the pilot station. These proxies
do not describe a complete authored pits zone. A collision-disabled world is an
explicit empty inventory, with terrain and pilot-station checks still active.

The check runs once at admission and records the actual consumed bounds, terrain,
lake and corridor identity in detached `status().airspace_report` diagnostics.
Malformed inventories and obstructed corridors refuse the proposed roster while
preserving the existing one. This proves clearance of the nominal corridor only:
avoidance, recovery, failures and arbitrary player encounters can leave it.
Trajectory containment, general field keepout metadata and moving obstacles remain
open gates. Source qualification alone never claims session clearance.

The source identity checks currently require readable source scripts. Solver
qualification normalizes UTF-8 source line endings to LF; flight logs retain their
original raw source fingerprints. Compiled exports without readable sources refuse
enabled companions. Cross-platform flight and packaged qualification remain open.
Do not update a profile hash merely to bypass a refusal:
retain baseline/candidate evidence and qualify the changed sources first.

Run focused tests through `tools/godot/run_checked.py`:
`test_companions_config.gd`, `test_companions_session.gd`,
`test_companions_pilot.gd`, `test_companions_manager.gd`,
`test_companions_profiles.gd`, `test_companions_airspace.gd`, `test_companions_lifecycle.gd`,
`test_companions_record.gd`, `test_companions_dialog.gd`, and `test_companions_shell.gd`.
The long qualification matrix lives outside the regular unit suite in
`research/ai-companions/pilot_probe.gd`. The same directory contains a two-minute
production manager check with full scenery collision, complete callback cost
measurements, and native render probes. See the evidence report for invocations.
