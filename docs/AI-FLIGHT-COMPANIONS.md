# AI flight companions

Status: experimental airborne slice, 2026-10-25. The remaining work and release
gates live in [the implementation plan](../AI_FLIGHT_COMPANIONS_PLAN.md).
[Verification and measured limits](research/ai-companions/AFC-00-06/README.md).
Follow-up evidence: [qualified profiles](research/ai-companions/AFC-02/README.md),
[cost attribution and equivalence](research/ai-companions/AFC-00-R1/README.md),
[lifecycle checks](research/ai-companions/AFC-03-R1/README.md),
[moving-encounter failures and selection repair](research/ai-companions/AFC-04-R1/README.md),
[avoidance clearance repair](research/ai-companions/AFC-04-R2/README.md), and
[sound, labels and accessible controls](research/ai-companions/AFC-05-R1/README.md).
The [stopped-traffic and maneuver-continuity repair](research/ai-companions/AFC-04-R7/README.md)
corrects frozen-aircraft forecasts and preserves held avoidance through observation
gaps. Its candidate verification is separate from source-profile admission.
The [terrain/traffic separation repair](research/ai-companions/AFC-04-R8/README.md)
prevents low terrain clearance from creating or prolonging an avoidance maneuver
when traffic is clear; terrain recovery and candidate-turn ranking remain separate.
The [fresh Windows checkout receipt](research/ai-companions/AFC-02/controller-dependency-checkout/verification.json)
records 1,200 successful script parses and all 16 companion regression groups;
its source snapshot and checkout corrections are explicit.
The [later controller promotion](research/ai-companions/AFC-00-R3/README.md#runtime-promotion-2026-10-21)
skips redundant clear-trajectory scoring and restores source-bound admission after
the separately verified solver merge. It changes no activity or population limit.
The [observation optimization](research/ai-companions/AFC-00-R5/README.md) preserves
the complete snapshot while sampling wind once and computing only airspeed.
Its actual one/three-companion regression matches all 1,200 observation rows;
observation, manager, recording and profile tests pass 267 checks.

The [Godot 4.8 qualification](research/engine-upgrade/GDU-03/companions/README.md)
records 148/148 checks on both 4.7.2 and 4.8-beta1, with byte-identical sampled
trajectories and scenario metrics. Admission now requires the exact official
4.8-beta1 build and the qualified source identities; this does not broaden the
weather, population or activity limits below.

The [2026-10-21 Windows working-tree parser gate](research/ai-companions/AFC-20-R1/parser-gate-20261021/README.md)
passes all 1,207 scripts with zero failures, engine errors or warnings and an
unchanged source manifest. The separate [Main/companions shell regression](research/ai-companions/AFC-00-R5/checks/main-shell-20261021/verification.json)
passes 49 checks with both the crash-context and observation changes present.
This is current-tree integration evidence; full application tests, a fresh
checkout of this snapshot and packaged exports remain open.

## Use

1. Choose **Club field** and a fixed-wing player aircraft on Home.
2. Open **More flight details → Flight companions**, enable companions,
   choose **1–3**, and Apply.
   Start with one; additional aircraft substantially increase CPU cost.
3. Fly. The companions launch airborne in separated circuits north of the runway.
4. **Pause → Session options → Flight companions** shows the current population.
   Apply flight-setting changes, then **Restart flight** to rebuild the roster.
   Sound and label settings apply immediately. Changes made here stay with this
   flight unless **Save these settings as the default** is selected.
5. **Remove companions now** immediately clears their sessions, models and audio.
   Restart brings back the configured roster. To keep them off, disable and Apply.
   Cancel discards the dialog draft.

Home and Pause Help include these controls and their current limits in English
and Spanish.

Off is the default. Each companion uses the bundled Jensen Das Ugly Stik 60,
an experienced circuit controller, independent full aircraft dynamics, and a
bounded spatial engine voice. There are no duplicate cameras or field soundscapes.
Player aircraft selection does not change the AI aircraft.

**Companion engine volume** controls only companion voices; zero mutes them.
**Show companion labels** is Off by default. When enabled, the labels follow the
actual aircraft, respect scene depth and the selected 50–1000 m camera-distance
limit, and disappear for stopped/crashed companions. These controls never select
a camera or change flight dynamics. Apply commits the draft; Cancel discards it.

The seed selects starting phase/direction and per-aircraft turbulence seeds.
Repeatability requires the same aircraft data, source, weather and initial roster.
The current roster is created only at tick zero; settings do not add aircraft
midflight. Menus, focus/controller holds and a stopped player simulation also stop
the companion clock.

## Current limits

| Setting or behavior | Available now |
| --- | --- |
| Field | Club field only; normal fixed-wing flights |
| Qualification | Exact aircraft, field, pilot, circuit-base dependency and solver source identities; official Godot `4.8.beta1.official.4d10419ca` at 240 Hz. Changed or unavailable sources, engine builds and other tick rates refuse admission |
| Weather | Reference atmosphere; mean wind ≤1.5 m/s, gust ≤0.6 m/s, updraft ≤0.15 m/s, turbulence RMS ≤[0.15, 0.15, 0.08] m/s |
| Aircraft/activity/skill | Ugly Stik circuits, experienced pilots |
| Population | Experimental fixed roster of 1–3; higher counts refused |
| Presentation | Immediate engine volume/mute; optional depth-tested labels with a distance limit; English/Spanish controls |
| Avoidance | Wind-aware bank candidates with reaction/response allowance and maneuver hold/release. Horizontal avoidance retains a local-terrain altitude target floor; general containment/recovery remains unqualified |
| Aircraft contact | Disabled; overlapping airplanes do not exchange contact forces |
| Terrain/scenery | Launch checks the nominal circuit corridor against actual session terrain, lake and collision proxies; ordinary contact/crash checks remain active. Only the player changes shared scenery damage |
| Crash/fault fallback | That companion stops, its voice is silenced, and status identifies it; restart or Remove clears it |
| Logging/checkpoints | Optional fixed-roster diagnostic capture links per-aircraft logs; no fleet restore or decision replay. A player-only paired checkpoint cannot save/restore while companions remain |
| Technical routes | Scripted flight, trace/capture, Workshop, synthetic electric demos, experimental aircraft-data routes and Natural Random do not admit companions |

Takeoff/landing cycles, other models, low passes, aerobatics, overtaking activities,
pilot difficulty choices, incidents, comic scenarios and busy-skies presets are
still planned. No control advertises them as available. No model, physics law,
solver frequency or golden flight was retuned to make this slice work.

The separate [sortie research](research/ai-companions/AFC-09-R2/README.md) physically
flies takeoff, circuit, landing and runway-exit trials through the existing session
seam. Four of eight directional/weather sorties pass the original 22 gates plus
current full-airframe clearance, geometric wheel support, end-corridor compliance
and a continuous 0.25 s clear dwell. Three exit turns cross the end boundary;
west headwind clears the runway but still exceeds the approach speed ceiling.
These results keep runway activities out of the runtime fleet. All eight recordings
replay exactly. Their 245,035 common-prefix CSV rows match the historical flights
across every column; different stopping points remain explicit. The controller and
physics are unchanged, and the 50-sortie campaign and abort/go-around gates remain open.
In a separate [earlier-arrival trial](research/ai-companions/AFC-08-R1/README.md),
moving only the predicted arrival target 2 m upstream resolves east-south's exit
failure under the existing gates. The measured end margin is +0.259 m, touchdown
moves 2.005 m upstream, and the supported taxi start moves 1.971 m upstream.
All CSV columns match through tick 18028; the first changed command is at 18029,
and the complete candidate recording replays exactly. This one research case
does not change the historical matrix or enable runway activities.

The [production-controller survey](research/ai-companions/AFC-04-R4/README.md)
passes the 30 m player-separation target in six head-on/crossing cases per weather,
each flown for 60 seconds. The intentionally conflicting two-threat spawn is
reported separately and fails separation. Earlier failed crossing tapes remain
retained. The production migration passes its circuit matrix and six exact crossing
replays on the recorded source snapshot. The local-terrain floor causes documented
trajectory differences from the research controller. Its 3 m prediction uncertainty
is an engineering allowance. The [current-source prediction measurement](research/ai-companions/AFC-04-R6/README.md)
observes horizontal error up to 5.047 m at eight seconds while the same bank target
remains active, so 3 m is not a valid hard bound even in that fixture. The traced
and ordinary flights match and all four recordings replay exactly; this does not
establish a replacement bound or static containment. The 35 m local-terrain altitude target floor is not a
guaranteed flight-path clearance. Static candidate constraints, general recovery
and multi-seed endurance remain open.

The measured three-companion CPU workload misses the plan's initial fleet budget.
The [promoted-controller Windows baseline](research/ai-companions/AFC-00-R4/README.md)
measures p95 frame times of 8.186/17.175/52.017 ms with one/two/three companions.
One passes the frame gate; two and three fail. All three pass the clock-pacing
gate in this single neutral-trim workload, which does not qualify all-visible
traffic or a supported population ceiling. The [earlier baseline](research/ai-companions/AFC-00-R2/README.md)
uses a different controller/world snapshot and is not a causal speedup comparison.
The isolated [observation microbenchmark](research/ai-companions/AFC-00-R5/checks/observation-abba-20261021/README.md)
averages 23.74 versus 16.80 microseconds per call in paired blocks on one prepared
state. This supports the observation change, but does not measure total flight or
frame cost and does not raise the experimental population ceiling.
A one-companion, 20-minute
headless flight completed all 288,000 ticks with stable node/object/resource counts
after 50 lifecycle cycles, including 10 visual/audio cycles. The three-companion
multi-seed endurance matrix, rendered soaks, finite-fuel recovery, fleet replay,
full crash presentation, complete feature translations and platform package checks remain open.
The first qualification target is the user's Windows 11 / Ryzen 9 5900X / RTX 3090
machine; native Linux/macOS tests and independent RC pilot review remain external
release gates. The selected machine has not yet qualified a busy-skies count.

The [external-session regression supplement](research/ai-companions/AFC-01-R1/README.md)
passes 65 equipment/start checks and 24 failure-onset/rollback checks. This verifies
software parity through the companion stepping seam; it does not add models,
runway activities or incidents to the available companion settings.

## Developer entry points

Direct launches ignore Home preferences:

```powershell
.tools/Godot_v4.8-beta1_win64_console.exe --path app -- --quick-flight --companions=1 --companions-seed=20261020
```

`--companions=0` explicitly disables companions. Counts above 3, invalid seeds and
unsupported enabled configurations fail before the flight is accepted.

### Diagnostic capture

Add `--companions-record=<new absolute directory>` to a direct launch with
enabled companions. Quote the whole argument if the path contains spaces:

```powershell
.tools/Godot_v4.8-beta1_win64_console.exe --path app -- --quick-flight --companions=1 "--companions-record=C:/captures/companions-001"
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
| `app/ai/companions/traffic_index.gd` | Bounded swept-bounds candidate query, tested independently; runtime integration pending |
| `app/ai/companions/static_trajectory.gd` | Continuous obstacle/protected-footprint and terrain clearance for bounded geometric paths; controller integration pending |
| `app/ai/companions/fleet_record.gd` | Fixed-roster capture manifest, common-clock monitoring and bounded existing per-session writers |
| `app/data/ai/companions/aircraft/`, `fields/` | Source-bound Stik/Club profiles and measured circuit scope |
| `app/ai/companions/pilot.gd` | Float64 guidance, control demands and proximity response |
| `app/ai/companions/circuit_controller.gd` | Source-bound original circuit guidance and legacy low-speed fallback |
| `app/ai/companions/manager.gd` | Stable tick snapshots, population ownership, scenery-mask publication |
| `app/ai/companions/agent.gd` | One external-driver session and its render/audio adapter |
| `app/ai/companions/observation_airdata.gd` | Airspeed-only snapshot calculation, with a bit-parity regression against the authoritative physics airdata calculation |
| `app/sim/flight_session.gd` | Validated external commands, spawn and single-tick seam |
| `app/render/crash/presentation_context.gd` | Explicit session/model/field and pose/wind inputs for the existing player crash director; companion attachment and global effect budgets pending |
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

The current controller predicts eight seconds at 0.25-second intervals using
air-relative banked turns plus wind displacement. It scores eleven bank choices
from −25° to +25° plus the nominal turn against all prepared threats. A 0.9-second
reaction allowance, 0.75-second bank-response ramp, two-second minimum hold and
one-second clear interval limit late reactions and oscillation. Missing observations
preserve an already-held maneuver until its hold and clear dwell expire; otherwise
no-traffic circuit commands remain in the unchanged base. Invalid/low-speed predictions retain the
legacy response. These are approximate forecasts; the predicted vertical rate is
held only over the reaction interval, and neither model-error bounds nor arbitrary
player maneuvers are qualified. Diagnostic traces are optional, bounded and off by
default. Controller latch state is explicit for research checkpoint continuation.

Profiles are validated once per manager launch, before replacing a live roster.
They bind both the wrapper and the actual inherited circuit script; a missing,
extra or mismatched dependency refuses admission.
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
`test_companions_encounters.gd`, `test_companions_clearance.gd`, `test_companions_traffic_index.gd`, `test_companions_trajectory.gd`,
`test_companions_profiles.gd`, `test_companions_airspace.gd`, `test_companions_lifecycle.gd`,
`test_companions_record.gd`, `test_companions_dialog.gd`, `test_companions_presentation.gd`, `test_companions_layout.gd`,
and `test_companions_shell.gd`.
The long qualification matrix lives outside the regular unit suite in
`research/ai-companions/pilot_probe.gd`. The same directory contains a two-minute
production manager check with full scenery collision, complete callback cost
measurements, native render probes, and `encounter_probe.gd` for bounded moving
traffic and recorded two-threat flights. See the evidence reports for invocations
and the distinction between failed flight gates and successful log replay.

The independent traffic-index contract and continuous closest-approach oracle
are recorded in [AFC-12 R1](research/ai-companions/AFC-12-R1/README.md). Its bounded
allocation and zero omitted synthetic conflicts do not establish a supported
aircraft count or replace flight qualification.

The [static trajectory checker](research/ai-companions/AFC-12-R2/README.md) passes 40 geometric checks, including the real field, sparse-index/full-scan agreement and bounded maximum workload. It remains a reusable helper pending controller/context binding; it does not qualify maneuver containment.

The [predictor binding probe](research/ai-companions/AFC-04-R5/README.md) passes
13 research checks: the same nominal path clears an off-path obstacle but its swept
segment hits a wall between otherwise clear sample endpoints. The current traffic
predictor still scores that route positively. This exposes the missing static
constraint using synthetic inputs; zero path-error allowance establishes no
tracking bound, and runtime commands are unchanged.

The [offline checkpoint and decision-replay proof](research/ai-companions/AFC-22-R1/README.md)
passes 79 post-migration checks, including exact physical/controller continuation,
nondefault avoidance latch restore, source mismatch and rechecksummed log tampering.
The [promoted-controller rerun](research/ai-companions/AFC-22-R1/pilot3842-20261021/README.md)
also passes all 79 checks with the current pilot and merged solver profile.
It is a research harness; the live application still has no fleet restore UI or
shared-world incident journal.
