# OpenRC GOD TEST implementation plan

Owner: performance tooling, coordinated with the PT instrumentation, VQ performance,
DT delivery, UI, controller, scenery and aircraft owners. Prefix: **GOD-01–13**.
Date: 2026-11-10. Status: implementation started; no completed hardware qualification.
This is the authoritative plan requested by the owner. The tool README will own
implemented commands; this document owns remaining work and acceptance evidence.

## 1. Purpose and acceptance boundary

Build an official automated benchmark of the real application: normal startup,
Home, aircraft selection, loading, physical flight, pause/resume, maneuvers,
best-effort landing and stopping, settings changes, Home and shutdown. It must
run a complete versioned suite or individual phases. Performance and coverage
are the primary outcomes; an aircraft accident must not erase earlier samples.

Questions: did startup/loading regress; where do hitches occur; does simulation
keep real time; what do night, weather, aircraft, scenery and graphics cost; does
memory grow across repeated flights; how does a candidate compare with a baseline?
Software execution and target-host performance are separate from physical realism,
pilot acceptance, radio qualification and package delivery.

Primary resolution: **1920×1080**. Above-1080p, including 1440p/4K, follows;
720p is the final compatibility priority. Record requested and actual dimensions.

## 2. Inspected infrastructure and constraints

The proposal was developed against main `18000e97`; implementation starts from
the current working tree, which includes concurrent uncommitted work. Every run
must retain its actual source identity rather than inherit that historical SHA.

| Existing component | Reuse | Constraint |
| --- | --- | --- |
| `tools/debug/debugctl.py` | Launch, session ownership, menus, settings, input, state, close | Debug templates only; keep explicit session identity |
| `research/performance/loading_probe.gd` | Home/Fly observations and lifecycle contracts | Loads AppRoot directly, so it does not establish full intro/startup |
| `research/performance/sustained_flight.gd` | Continuous physical flight, health and identity patterns | Its no-pause/no-contact qualification contract remains strict |
| `research/performance/sustained_input.gd` | Normal keyboard seam and 60 Hz pilot over 240 Hz physics | Current circuit/field/condition admission is bounded |
| `app/scenery/takeoff_pilot.gd` | Stik throttle ramp, heading hold, rotation and climb | Estimated Stik controller, not a fleet autopilot |
| `tools/trailer/*director.gd` | Takeoff, roll and approach experience | Capture routes and direct-command ownership are different workloads |
| `app/sim/landing_maneuver.gd` | Approach, flare and rollout reference | Experimental calm, wash-off Stik condition only |
| `FrameSamples`, `FrameDiagnostics` | Frame times, bounded streams and counters | Preserve metric meaning, availability and existing consumers |
| `.orfl` recorder/replay | State, accepted inputs and sparse interventions | Numerical replay is not whole-scene graphical replay |
| `tools/godot/run_checked.py`, resource sampler | External watchdog, errors and OS resources | Keep PID, clocks, sample coverage and channel limits explicit |

Critical routing facts:

1. Startup animation requires no user arguments; current AppRoot treats user
   arguments as direct-flight routing. A new `--godtest` user argument must not
   silently bypass Home. Opt-in environment/manifest activation must preserve it.
2. Technical simulation pause differs from the player's pause-menu action.
3. Physical weather editing is a Home route. In-flight paused lighting/sky editing
   has a separate route. Follow accepted product workflows and read back values.
4. Production Home preparation can overlap loading. Its effective policy and dwell
   belong to workload identity; an experiment with preparation off is distinct.
5. Preserve existing sustained-flight rejection of pauses, holds, crashes and
   contacts. GOD TEST needs its own explicit phase-aware verdict.

Canonical references: [tool index](../tools/README.md), [debug bridge](../../tools/debug/README.md),
[performance tools](../../research/performance/README.md), [capture directors](../../tools/trailer/README.md),
[logging](../FLIGHT-LOGGING.md), [kernel](../STACK.md#boundaries-and-data-flow),
[performance gates](global-performance-visual-quality.md).

## 3. Architecture

The Python orchestrator resolves manifests, captures source/build identity, creates
a fresh output/profile, launches and owns one process, enforces wall deadlines,
collects artifacts and reduces reports. Reuse the debug launcher/bridge rather
than introduce a competing remote-control protocol. One rendered run at a time.

An opt-in in-app observer survives scene transitions, records monotonic phase
boundaries and controls the scenario. A benchmark pilot observes accepted float64
state and sends bounded ordinary controls. Target 60 Hz pilot updates, retaining
the normal automatic 240 Hz session/kernel ticks. No per-tick socket polling.
No pose rewriting or manual physics stepping during a continuous run. No changes
to aircraft laws, generated data or vehicle branches in the shared kernel.

Three workloads remain distinct:

| Mode | Meaning | Main use |
| --- | --- | --- |
| Adaptive | Feedback pilot follows declared objectives | Complete user-like benchmark |
| Input tape | Fixed accepted input/tick interventions | Controlled behavior investigation; trajectory may diverge with new physics |
| Visual path | Presentation follows a controlled path | Renderer attribution; no physical-flight claim |

Rendered input-tape integration is new work; do not relabel the existing offline
`.orfl` replay as graphical replay. Preserve `complete`, identity and `solver_changed`.

## 4. Reference flight: ugly-standard-v1

Initial duration estimate: 5–8 minutes, to be replaced by observations. Aircraft:
`jensen-das-ugly-stik-60`; Club Field; runway start; calm physical weather; clear
sky; fixed daytime; explicit pilot camera and graphics profile; fixed seed set.

| Phase | Action and exit evidence |
| --- | --- |
| startup | Normal process/intro/Home route; record readiness and drawing separately |
| home | Declared visible dwell; observe menu fluency and preparation |
| selection | Explicit Stik selection; accepted choice, response and preview readiness |
| configuration | Read back field, day, weather and runway selection |
| loading | Fly signal through product route; feedback, ready, first draw, interactivity |
| preflight | Control ownership, flyability and expected holds checked |
| takeoff | Progressive throttle, heading hold, rotation; wheel separation and climb |
| climb_right | Gain clearance and turn right into the declared departure corridor |
| farmhouse | Fly through a declared gate around the selected rural house |
| flag | Return through the flag overflight corridor with terrain/object clearance |
| pause | Open normal pause menu; acknowledge the accepted paused tick |
| pause_hold | Wait at least five monotonic wall seconds from acknowledgement |
| resume | Normal continue action; first new tick/draw and recovery windows |
| right_circuit | Another right-hand circuit within speed/height/corridor limits |
| roll | Observe a complete accumulated rotation and controlled exit |
| recover | Level within declared tolerances for a minimum interval |
| large_loop | Complete vertical maneuver with sufficient energy/height |
| recover | Stabilize before approach |
| approach | Join final; one go-around maximum by default |
| landing | Record contact, attitude, sink, bounce, containment and accident |
| stop | Observe ground speed below the profile threshold for a minimum interval |
| settings | Exercise accepted lighting/graphics transitions and read back effects |
| environment | Return Home, change physical weather and load another flight |
| home | Observe release/retention at a comparable quiet boundary |
| shutdown | Close owned process; retain engine errors, exit status and teardown |

The complete route includes the rural house. `ugly-club-short-v1` is a separately
named fast route; it cannot substitute for complete-route coverage.

| Landmark | Scenery ID | North/east metres at proposal inspection |
| --- | --- | --- |
| Pavilion | `pavilion` | -22 / 0 |
| Flag | `flagpole` | -16 / 8.5 |
| Main rural house | `farm-farmhouse` | 591.5 / 321 |
| Second rural house | `countryside-farmhouse` | 750 / 625 |

Resolve IDs from scenery and retain actual coordinates/content identity. Moving a
landmark may remain executable but changes comparability. Camera/FOV/zoom matter:
aircraft proximity does not prove an object was visible or expensively rendered.
Pilot and chase-camera cases are separate; record autozoom and projected size.

## 5. Pilot and calibration

State machine: PREFLIGHT → TAKEOFF → CLIMB → NAVIGATE → PAUSE → RESUME → ORBIT →
ROLL → RECOVER → LOOP → RECOVER → APPROACH → FLARE → ROLLOUT → STOP.

Every phase declares prerequisites, target, command limits, success condition,
simulation deadline, wall deadline, abandonment reason and bounded recovery.
Navigation uses passage gates/corridors, not exact-point coincidence. Terrain
clearance comes from the environment; negative NED down alone is not AGL.
Roll/loop completion uses accumulated attitude/trajectory evidence, not an Euler
angle wrapping back to zero. Maneuvers require energy, clearance and usable state;
unmet prerequisites become missing coverage rather than changed physical laws.

Pilot profiles are separate from aircraft data and contain:

- aircraft/controller/profile identity and supported starts;
- takeoff throttle ramp, rotation/climb targets and heading limits;
- cruise speed, bank/radius/clearance and command limits;
- aerobatic entry/recovery limits;
- approach speed, glide path, alignment, configuration and flare;
- available brakes, stop threshold and go-around policy;
- calibration evidence, supported conditions and unresolved limits.

Calibrate capability admission, trimmed/accepted starts, straight flight, takeoff,
navigation, maneuvers and landing in that order. Reserve conditions/seeds not used
for tuning. Freeze the resulting profile and its failures. Existing Stik controllers'
approximately 12 m/s references are condition-specific estimates, not fleet values.
After physical changes, run the frozen pilot first; preserve failure before creating
a new calibrated profile. Adaptive corrections and saturation remain observable.

| Family | Flight/landing adaptation |
| --- | --- |
| Standard Stik | First full route and calibrated landing |
| Electric 6S Stik | Energy/propulsion-aware variant; separate approach/stop proof |
| Extra 300S | Aerobatic profile; independently admitted landing |
| Vantage Jet | Wider/faster route, deceleration and runway-distance requirements |
| P-51D / F4U | Capability-aware warbird configuration, own approach and contact limits |
| Turbo Lumber | Slow/STOL route, contact/rollout workload |
| MoonRunner X99 | Supported launch/airborne start; no wheel-landing assumption |
| Helicopter | Vertical departure/hover/translation/return; dedicated session and landing |

Query the catalog and accepted capabilities. Hidden technical variants are an
explicit suite, not silently included in player-fleet coverage. Unsupported profiles
are visible omissions. New vehicle families require their own adapters and gates.

Landing means aligned approach, near-level wings and controlled sink, not zero
pitch. Retain air/ground speed, lateral error, roll/pitch/yaw, contact-point sink,
first contact, bounces, containment, damage, distance and time to stop. Proposed
initial stop criterion: <0.5 m/s ground speed for three simulation seconds, reviewed
per aircraft. No unlimited retries. Reset creates a new attempt ID and discontinuity.

## 6. Isolated phases

`continuous` reaches a phase through prior flight; `isolated` creates a declared
initial fixture before measurement. An isolated landing does not prove a complete
circuit or reproduce its fuel, memory, thermal or resource history. Checkpoint
reuse must satisfy the existing model/configuration identity contract. A new
condition prepared for changed physics is not an exact old checkpoint restore.
Record setup, preparation/warmup, measured interval and origin on every phase.

## 7. Suites and options

| Suite | Scope |
| --- | --- |
| smoke | Startup, loading, short flight, pause, Home and close |
| all | Explicit versioned standard battery |
| startup/loading | Process/intro/Home, selection, first/subsequent Fly and return |
| flight/pause | Selected routes or repeated pause/resume |
| transitions | Settings, lighting, sky, physical weather, aircraft and field |
| fleet | Admitted aircraft with explicit profile/coverage inventory |
| graphics | Presets and independent available controls |
| memory | Repeated Home/Fly cycles in the same process |
| soak | Declared prolonged workload and degradation |
| stress | Admitted demanding combinations |
| matrix | Budgeted combinations with risk/pair coverage |

`all-v1`: complete daytime Stik, nighttime Stik, jet circuit, pause cases, accepted
environment transitions, second-field case, ten lifecycle-screen cycles and close.
Its membership is frozen/versioned. Ten cycles do not establish the longer gates.
`--dry-run` prints expanded cases/order/repetitions/resources and estimated duration.

Dimensions: aircraft/variant; supported start; day/dusk/moonlit/dark/evolving time;
wind direction/speed/gust/turbulence; visual sky; landscape; camera/FOV/zoom;
geometry/grass/tree density and distances; lights/shadows/reflections/effects;
companions; requested/installed physical backend; renderer; output and internal
resolution/reconstruction; VSync/FPS cap; audio; finite fuel/battery; profile/cache
and lifecycle history. Reject unsupported combinations before launch.

Physical weather and visual sky remain independent. A visual electrical storm
does not imply rendered rain or a new precipitation law. "Native" is not a
renderer name; record the actual driver/method and selected hardware.

## 8. Startup, clocks and pause measurement

Supervisor `process_launch` is an external monotonic observation. Internal markers:
startup_entered, first_draw_observed, home_ready, home_drawn, selection_requested,
selection_ready, fly_requested, loading_feedback_drawn, flight_ready, flight_drawn,
flight_interactive. Define each precisely; readiness, drawing and physical display
presentation are separate. Align process clocks explicitly or report unavailable.

Keep Home dwell/preparation policy and resource-import state. A fresh process is
not a cold OS/shader cache. Name process-cold, warm, fresh profile and unknown
cache states accurately. Do not silently purge or modify the user's caches.

Pause protocol: reach stable flight; open normal pause; acknowledge paused tick;
wait five real seconds from acknowledgement; normal continue; observe new tick and
draw. Record request/ack latency, actual hold, menu frame times, physical tick/state
invariance, resume-to-tick/draw, worst transition interval, first-second and five-second
windows and recovery. Attribute boundary-crossing frames explicitly without loss
or double count. Paused samples stay outside active-flight distributions. Technical
simulation pause is a separate case. Unexpected holds/focus pauses cannot masquerade
as the intended pause.

## 9. Metrics and targets

Per-phase and per-run output: loading intervals; frame p50/p95/p99/max/count;
hitch counts/runs/durations over declared 16.67/33.33/50/100 ms thresholds; accepted
ticks and simulation/wall ratio; steps/frame; available CPU/GPU metrics; OS RSS and
motor allocation/resource counters; render draws/primitives; trajectory/error/input
and saturation; retained resources/teardown; faults, missing channels and limits.
GPU unavailable/unverified is not zero. Overlapping CPU/GPU intervals are not added.
Resource-sampler peaks are sampled peaks. Short phases emphasize raw intervals,
maxima and events rather than a poorly supported p99. Keep first-use hitches visible;
warmup is separately labeled and never silently erases the user experience.

Inherit owning-track targets, preserving their definitions and stricter limits:

| Existing target | Definition/limit |
| --- | --- |
| 60 Hz pacing | Process-loop p95 ≤18 ms, p99 ≤25 ms |
| Simulation pace | Active simulation/wall ratio 0.99–1.01 |
| Home | ≤5 s process-cold / ≤3 s warm under defined protocol |
| Fly | ≤2 s under defined protocol |
| Hitches | Attribute repeatable gameplay intervals >50 ms |
| Lifecycle | 20-cycle screen; DT-12 separately requires 50 cycles and 30-minute soak |

These are goals, not established performance. Keep Gate P's original 500 µs/tick
regime/statistic scope; a whole-session average cannot replace it. Uncapped throughput
and intended VSync/capped pacing are different claims.

## 10. Comparisons and observer cost

Freeze A/B sources and intended intervention. Match other workload/hardware/driver/
power/display/renderer/backend/audio/settings identities. Alternate role order;
start with three pairs, expand to five or more when variation prevents a decision.
Use run/phase-level paired changes; correlated frames are not independent trials.
Report absolute target compliance and baseline regression separately. Preserve
failed/excluded runs and predeclare exclusion rules. Changed route/coverage cannot
produce an unconditional whole-flight percentage. Compare equivalent segments.

Instrument levels: standard (frames/phases/bounded health/trajectory), diagnostic
(additional counters/profiling/logging), visual (captures/video). Screenshot readback
or heavy profiling stays in a separate diagnostic pass; do not capture on a hitch
inside an acceptance run. Preserve pilot while changing only audited observers in
overhead controls. Never subtract noisy observer time from individual frame times.
`.orfl` is explicit and matched across roles. Reuse bounded streaming and existing
OS resource/Perfetto tools; no new profiler or growing in-memory full-flight arrays.

## 11. Outcome and recovery contract

| Outcome | States |
| --- | --- |
| Execution | Completed, timeout, process failure, refused configuration |
| Data | Complete, partial, invalid, unavailable channel |
| Coverage | Complete, partial, skipped phase, unsupported case |
| Performance | Target met/missed, regression, inconclusive, no baseline |
| Flight | Completed, recovered, landing failed, accident |

An accident after full navigation preserves earlier metrics; an accident before
the rural house leaves route coverage incomplete. Invalid solver state, focus loss,
non-drawing window, unexpected backend fallback and stream-cap prefix cannot yield
an unconditional rendered pass. Keep every attempt and its boundary. A suite may
continue independent cases, but strict success requires all mandatory coverage.
Exploratory collection preserves useful partial data without changing that rule.
External watchdog terminates only the owned process tree and retains diagnostic
prefixes; a prefix never establishes a completed soak.

## 12. Declarative interface and files

Initial format: versioned JSON, using existing Python/Godot support. YAML authoring
can follow if justified. Manifests name launch route/profile/resolution, aircraft/
start/pilot, environment and seeds, graphics/camera profile, route and ordered phases,
measurement level and explicit policies. Expanded profiles contain numeric targets,
tolerances, bounds and deadlines. Validate unknown fields, types, finite values,
units, identifiers, capabilities, references and contradictory options.

Proposed CLI (implemented commands must be documented in the tool README):

```text
python tools/godtest/godtest.py list
python tools/godtest/godtest.py all --dry-run
python tools/godtest/godtest.py all
python tools/godtest/godtest.py run ugly-standard
python tools/godtest/godtest.py run ugly-standard --time night
python tools/godtest/godtest.py run jet-circuit --weather gusty --time sunset
python tools/godtest/godtest.py run ugly-standard --weather calm --sky electrical_storm
python tools/godtest/godtest.py run ugly-standard --phase pause --entry continuous
python tools/godtest/godtest.py run ugly-standard --phase landing --entry isolated
python tools/godtest/godtest.py run ugly-standard --repeats 3
python tools/godtest/godtest.py memory --cycles 50
python tools/godtest/godtest.py soak --minutes 30
python tools/godtest/godtest.py fleet
python tools/godtest/godtest.py matrix --profile nightly --dry-run
python tools/godtest/godtest.py compare --baseline <run-a> --candidate <run-b>
python tools/godtest/godtest.py report <run-id>
```

`compare` reduces existing artifacts. A future campaign command may prepare/run
versions explicitly; comparison must not unexpectedly launch hours of tests.

Initial ownership:

```text
tools/godtest/                 CLI, manifests, profiles, schemas, tests and reducers
research/performance/godtest/  prototype scenario/pilot scripts before production admission
app/debug/godtest_*.gd         minimal opt-in runtime observers/adapters after parsing
docs/plans/god-test.md         this plan and pending work
tmp/godtest/<run-id>/          fresh ignored outputs
```

Run artifacts: requested/resolved manifest, identity, execution, events.jsonl,
phases, existing frame report/stream, OS resources, bounded trajectory CSV, engine
log, JSON/HTML report, attempts and optional diagnostics/`.orfl`. No automatic image
commits. Preserve only selected lightweight accepted evidence in the owning research
home; raw logs/captures stay ignored or in retained external evidence.

Identity includes commit plus dirty/untracked inputs, actual executable/engine/package/
native libraries/imported resources, aircraft and physical data, field/scenery/collision,
resolved landmarks, pilot/route/camera/suite, seeds/initial energy, CPU/GPU/OS/driver,
actual backend/renderer, output/internal dimensions, reconstruction/VSync/cap/audio
and instrument level. Snapshot mutable inputs for long/paired runs; never stash
another owner's work. Verify macOS profile isolation separately from Windows/Linux.

## 13. Execution steps and evidence ledger

Status is maintained only here; tool instructions describe implemented commands.

| ID | Work | Required proof / current status |
| --- | --- | --- |
| GOD-01 | Inventory, boundaries, scenario contract and registration | Source inspection complete; this plan records design; runtime inventory pending |
| GOD-02 | CLI, strict manifests, profiles, fresh outputs, list/dry-run | Pending implementation and invalid-input checks |
| GOD-03 | Owned launch, profile, supervision, timeout and partial results | Pending real process success/failure evidence |
| GOD-04 | Normal startup and Home/Fly instrumentation | Pending markers preserving intro/Home, draws/readiness and effective selection |
| GOD-05 | Phase collector, bounded frame/resource/event joins | Pending boundary/integrity/overflow tests and observer-cost control |
| GOD-06 | Normal input adapter, takeoff, climb and navigation | Pending Stik circuit with trajectory/control evidence |
| GOD-07 | Rural house, flag, five-second pause/resume | Pending continuous route and pause/tick history |
| GOD-08 | Roll, loop, recovery and prerequisite refusal | Pending observed maneuvers and failures retained |
| GOD-09 | Approach, landing, stop and bounded go-around | Pending continuous attempt plus isolated fixture distinction |
| GOD-10 | Night, sky/weather, field, jet and aircraft profiles | Pending capability rejection, effective readback and per-profile evidence |
| GOD-11 | Comparison and JSON/HTML report | Pending paired comparison, equivalence and invalid-artifact rejection |
| GOD-12 | Cycles, soak, hardware and overhead | Pending 50-cycle/30-minute evidence; preserve finite-energy limitations |
| GOD-13 | CI, scheduled GPU runs and package lane | Pending separate source/debug/release scope and actual package instrumentation |

Order: contracts/CLI → supervised normal startup → collectors → basic pilot →
landmarks/pause → aerobatics/landing → variants/comparison → long campaigns/packages.
Each delivery must parse and pass relevant focused checks before integration.

## 14. Verification and completion

Meaningful checks cover schema/capabilities, route preservation, clocks and phase
boundaries, ownership/deadlines/close, stream corruption/truncation/overflow, partial
results, source mismatch, comparator equivalence and pilot command integration.
Use existing frame/diagnostic/loading/debug/catalog/controller/takeoff/landing tests
when affected. Deliberate failures run on disposable copies. Existing required CI
remains required; do not habitually run the complete app suite for each local edit.

Rendered acceptance runs are serial, visible/focused, at verified 1080p on named
hardware. Headless proves contracts, not GPU qualification. Source/debug results
do not qualify release packages; the current bridge is disabled in release templates.
Minimal package instrumentation/external observation requires its own delivery.

Cadence: focused local/PR checks; selected rendered GPU comparisons; versioned nightly
`all` and bounded matrix; independent long campaigns; package checks for release
candidates. Do not change shared hardware/system power preferences silently.

The first usable version must launch normally, select the stock Stik, attempt the
full reference sequence and settings transitions, close, report per-phase frames/
loading/resources/coverage/flight outcome, run isolated phases, preserve failures
without false approval, and compare only eligible equivalent artifacts. Success of
an implementation check is not a claim that all pilot/hardware gates have passed.
