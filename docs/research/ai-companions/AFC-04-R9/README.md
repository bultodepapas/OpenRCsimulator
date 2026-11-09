# AFC-04-R9: prediction and traffic-feasibility repair

2026-11-09, Windows x86_64, official Godot `4.8.beta2.official.cafc17a19`,
headless GDScript reference. Baseline commit `7b8ade33`. This implements a
bounded flight-control follow-up to the external AI improvement audit.
[Verification](verification.json) binds the runs and [195 unchanged flight inputs](source-manifest.json).
Unrelated economy, UI and localization work in the shared tree was preserved.

The production pilot now shares the circuit controller's snapshot-specific nominal
bank, including heading correction and clamped trim speed. Both forecast loops
use exact constant-turn segment displacement with a stable straight-flight limit.
Traffic clearance uses synchronized interval closest approach, subtracting both
arcs' chord deviations and the own vertical forecast's reaction-deadline kink.
Forecast minimum-distance diagnostics are lower bounds; their distance traces
remain endpoint samples. The existing 3 m model allowance is still an estimate,
not a measured flown-path bound. The 1e-9 m numerical tolerance is scoped to Club
coordinates, not certified for arbitrary large coordinates.

Traffic-feasible searched turns now precede steering preferences, including when
terrain recovery is active. An unsafe held turn yields to a feasible alternative.
If every searched turn is infeasible, acquisition maximizes the worst traffic
margin; an existing hold retains 2 m retarget hysteresis. This is best effort,
not qualified recovery. Static-path feasibility remains open. The diagnostic
`traffic_feasible_candidate_available` covers the nominal/grid search; a separately
scored held bank may also be feasible. Controller state v2 rejects v1 checkpoints
and preserves active holds and clear dwell through exact continuation.

| Check | Result |
| --- | --- |
| New production prediction regressions | 238 checks, zero failures |
| Existing pilot / clearance / terrain-traffic / traffic lifecycle | 24 / 20 / 60 / 40 checks, zero failures |
| Circuit extraction against the original base | 256 byte-identical packets, including legacy avoidance |
| Source-profile validation / manager / recording / observation | 44 / 53 / 156 / 21 checks, zero failures |
| Main/companions shell | Zero failures |
| Two-minute 1–3 aircraft calm/gentle matrix and deterministic repeats | 148 checks, zero failures |
| Final 60-second encounter surveys | All twelve nominal cases pass the 30 m player gate |
| Baseline AI and candidate AI/player/peer exact replay | Four complete 2,881-row replays, `solver_changed=false` |
| Research scheduler boundaries / tailwind / traffic suite | 79 / 19 checks and traffic suite pass |

The [matrix metrics](matrix/scenario_metrics.csv) and [one-second samples](matrix/flight_samples_1hz.csv)
match the earlier R5 files byte for byte. Minimum AGL is 34.310643 m, maximum
radial error 4.047822 m, minimum player separation 122.307210 m and minimum fleet
separation 121.744242 m. All six scenarios and both repeats finish 28,800 ticks.
The final production sources stayed frozen throughout these runs.

The [calm](surveys/final-calm.json) and [gentle](surveys/final-gentle.json) surveys
finish 14,400 ticks per case without refusal, fault or crash. Their lowest nominal
player distances are 55.744051 m and 53.110906 m. Both deterministic repeats
match. The deliberately conflicting two-threat fixture still fails: player/peer
minima are 28.999852/9.000000 m in calm and 28.999776/8.210137 m in gentle weather.
It is neither a passing case nor a production-admitted spawn.

The matched [baseline](surveys/baseline-crossing.json) and [candidate](surveys/final-comparison.json)
12-second surveys retain actual trajectories and tick identities. For seed
20261020 crossing-left, minimum player distance changes from 65.614460 m to
69.699018 m; its head-on case changes from 60.971020 m to 60.438387 m. The result
is not uniformly increased separation. The initial-conflict AI tape is unchanged
in physical CSV output; player and peer CSVs also match byte for byte across all
2,881 rows. These controlled inputs and [exact replays](replays/) do not establish
controller decision replay or physical realism. The two compressed AI tapes and
their original/stored identities are retained in [verification](verification.json).

Strict admission initially exposed an already-stale normalized solver pin.
The [official rebind receipt](../AFC-02/rebinds/2026-11-09-b98411b3-to-896989e0.json)
compares nine retained tapes against accepted solver commit `979819ec` and the
current committed solver: all nine 2,881-row CSVs match byte for byte. The solver
pin is renewed to `896989e0`; 37 Python rebind tests also pass. The controller
profile pins pilot `8e6dad42` and circuit base `3624536a`. Its strict 44-check gate
passes after renewal. [Normal app admission](production-admission.json), without
test overrides, observes three active airborne companions through 8,206 ticks
with zero faults/crashes. [Shutdown](production-stop.json) is unforced with no
crash or leaked objects; the launcher exit code is unavailable. Timing from this
headless run is not performance qualification.

The isolated AFC traffic research also repairs audit F13/F14. A matching observed
player entry consumes its grant and supports one later ticket confirmation across
restore. Grants reserve requeue capacity; saturated older v4 checkpoints are
rejected atomically. Wreck removal preserves the player's blocker until geometric
clearance in either callback order. Activity leases reserve the distinct union of
cooldown-history and active keys before completion, retirement or preemption;
overcommitted checkpoints are refused. Expired cooldown history still counts
toward 512, so a full history can continue blocking new keys. These modules remain
outside the production runtime. [Scheduler checks](schedulers/boundaries.json)
and independent review cover the repaired invariants, not runway flight behavior.

Reproduction uses the existing [checked runner](../../../../tools/godot/README.md),
`research/ai-companions/pilot_probe.gd`, `encounter_probe.gd` and
`avoidance/encounter_probe_gentle.gd`; their exact arguments are in [checks](checks/matrix.json).
Run `test_companions_prediction.gd` through the same runner. To reproduce the base
extraction check, extract `app/ai/companions/circuit_controller.gd` from baseline
commit `7b8ade33` to `tmp/afc-r9/legacy_circuit.gd` and copy the retained
[parity harness](base_parity.gd.txt) to `tmp/afc-r9/base_parity.gd`.
The [flight-log workflow](../../../FLIGHT-LOGGING.md) replays decompressed tapes
into new output directories. Research scheduler commands remain in their
[own guide](../../../../research/ai-companions/traffic/README.md).

General static containment, measured prediction-error bounds, arbitrary-player
avoidance, live fleet restore, later audit lifecycle/seed/status/timing changes,
cooperative activities, physical validation, packaged exports and 1080p hardware
performance remain separate AFC gates. No physics law, aircraft data or golden
flight was retuned, and no population/activity/weather scope was expanded.
