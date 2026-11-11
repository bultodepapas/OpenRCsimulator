# AV-17-R4: pitch derivative reference correction

2026-11-10. Implements review R1 with a bounded R0 accepted-command baseline.
Baseline commit `3699b237a417413f3942736bbfa2bb229a2d6125`; the working tree was clean
before this work. Concurrent display/UI/flag changes subsequently appeared and were
preserved. The recorded solver and aircraft hashes, rather than a claim of an entirely
frozen working tree, identify these physics comparisons. The [aircraft guide](../../../AVANTI-S-PLAN.md#5-november-review-implementation-sequence)
owns remaining work; the [original review](../review-2026-11-10.md) audits an earlier commit.
During integration another process committed the mixed working tree as `096f0574162408ba18b3440b6f833c4214346df8`.
That commit includes unrelated work and intermediate evidence; it is not substituted
for the per-run identities below. Subsequent integration fixes retain their own checks.

## Correction

AV-06 estimated `Cmq` about the authored inventory CG, but serialized that value where
the aerodynamic evaluator expects a moment about its ARP. The existing force transfer
then added the rate-dependent lift's pitch moment again. At zero alpha/beta:

`Cmq_O = Cmq_ARP + CLq * (x_O - x_ARP) / c`

The generator now subtracts that arm contribution before serialization. The only
aircraft quantity changed is `Cmq`: **−7.751139 → −8.165939**, with corrected provenance.
The effective reference-CG derivative becomes **−7.751139876**, instead of
−7.336339876. The independent tail-volume reconstruction from rounded loaded quantities
is −7.751168970. Its 0.0002 absolute tolerance accommodates serialization; the observed
defect is 0.4148. The force-transfer identity uses a separate 1e−8 tolerance.

O is the fixed authored CG, not the instantaneous fuel-dependent CG. Aero transfers
ARP → O; `LiquidFlight.evaluate` subsequently transfers the complete wrench O → live CG.
Neither transfer nor the shared/native law was changed. Recomputing the coefficient
at every live CG would suppress a physical arm effect and is deliberately avoided.
All stored pitch derivatives retain the ARP convention. Nonzero alpha requires the
existing wind-to-body force rotation in the transfer.

Dependent exact-byte bindings were refreshed through the Workshop and economics
generators. Before rebinding the authored cost sources, a whole-document comparison
confirmed that replacing only the new Cmq quantity with its baseline value/provenance
recovers the original aircraft document. Inventory, contact geometry, priced parts
and mappings are unchanged; this does not update the dated price research.

At a fixed state the correction changes only the global pitch-rate couple. Its
incremental rotational power is proportional to `delta_Cmq * q² <= 0`; it adds damping,
not a direct lift, drag or lateral-force retune. Different trajectories can nevertheless
accumulate different propulsion work, drag and energy. This is a convention repair,
not identification of the estimated physical damping.

## Verification

Windows x86_64, official Godot 4.8-beta2 `cafc17a19`, headless reference evaluation:

| Check | Result |
| --- | --- |
| New `test_avanti_pitch_reference.gd` on original aircraft | 21 checks, four intended target failures; no engine errors |
| Same regression on corrected aircraft | 21 checks, zero failures; alpha 0/4/8°, actual liquid stage at 100/50/0% usable fuel |
| Existing `test_regime_consistency.gd` | 113 checks, zero failures |
| Existing `test_avanti_handling.gd` | 47 checks, zero failures, including complete session traces, rolls and glide energy |
| Existing `test_liquid_fuel_session.gd` | 48 checks, zero failures, including exact continuation and exhaustion |
| AV-14 geometry/inventory and sensitivity | Six Python tests each, all pass |
| AV-06 generator `--check` | Pass in working tree and a fresh sparse clone of the baseline with the three owning generator/output files overlaid |
| Workshop descriptor / economics catalog / cost profile runtime suites | 126 / 102 / 67 checks, zero failures |
| Workshop LF/CRLF fresh-checkout regressions | Eight Python tests, all pass |
| Economics runtime / profile regressions | 35 / 15 Python tests, all pass |
| Economics regeneration `--check` | Pass in working tree and fresh sparse clone with reviewed source bindings and generated outputs overlaid |

[Checked reports and logs](verification/) retain the Godot runs and the intentional
baseline failure; [command results](verification/command-results.json) record the Python
and fresh-clone checks. A first launcher attempt used a relative executable path and failed
before Godot started; the successful absolute-path run supersedes it. No assertion or
golden flight was weakened/re-recorded to obtain these results. Required CI and package
qualification have not run for this working-tree change.

The red-run report names a temporary draft, byte-identical to the retained test:
SHA-256 `070609c364381ea371ef1828f2d6b736d7a69ee6203218e6db09c9d5523f7644`.
Reproduce its four intended failures by running the committed test with
`-- --aircraft=C:/DEVELOPMENT/OpenRCsimulator/docs/research/avanti-realism/AV-17-R4/baseline-aircraft.json`.
The same test without that argument must pass against current generated data.

The new regression holds air state at O when probing pitch rate. It exercises the
actual finite-liquid adapter, with the engine stopped, and measures its O → live-CG
transfer at three fuel states. This is not a derivative with velocity held at live CG:
that experiment would also require the corresponding `omega × offset` velocity change.

Local and global models remain distinct. At alpha 0°, local Cmq is −7.233907 versus
global −7.751140; at 4° they are −7.276397/−7.745854, and at 8° −7.357037/−7.742615.
The datum fix increases their discrepancy. Existing regime bands pass, but neither
those bands nor this new identity test establish physical agreement. R5/R6 remain open.

## Accepted-command comparisons

Retained [pulse](pulse.orfl) and [loop-entry](loop.orfl) recordings use the real
`FlightSession`/kernel/FlightLog with 240 Hz ticks, calm air, 29 m/s initial trim,
500 m datum altitude, half main-fuel capacity, clean flaps and retracted gear.
The fixture relocates the state after reset: reset-time `launch_state` metadata still
describes the original 30 m start. The recorded checkpoint and CSV tick zero are
authoritative for the actual 500 m comparison; this metadata discrepancy is not a
second launch or an in-flight intervention.
Commands are injected after device/rate/expo conditioning; `cmd_*` columns are
authoritative. Raw/stick columns do not describe those injected commands. These are
not normal UI/device-path recordings, pilot comparisons or proof of a planar loop.

The pulse holds one second, adds +0.04 normalized pitch for 0.5 seconds, then releases
for five seconds. Loop-entry applies full throttle from the first tick, adds +0.10
pitch after one second for six seconds, then releases for five seconds. Its initial
marker is historically named `trim_hold`, but that phase is full-throttle pre-acceleration.
Both preserve the baseline's initial state and commands in candidate replay.

| Comparison | Pulse | Loop-entry |
| --- | ---: | ---: |
| Duration / accepted ticks | 6.5 s / 1,560 | 12 s / 2,880 |
| Baseline exact replay | Complete, byte-exact | Complete, byte-exact |
| Candidate replay | Complete; `solver_changed=false` | Complete; `solver_changed=false` |
| Maximum pitch-rate difference | 0.003027845 rad/s | 0.022295173 rad/s |
| Maximum roll-rate difference | 0.000062492 rad/s | 0.000769455 rad/s |
| Maximum yaw-rate difference | 0.000042479 rad/s | 0.001329276 rad/s |
| Maximum attitude-angle difference | 0.001400530 rad | 0.100601989 rad |

See [pulse comparison](pulse-comparison.json), [loop comparison](loop-comparison.json),
and the paired CSV/replay reports in `pulse-exact/`, `pulse-candidate/`, `loop-exact/`
and `loop-candidate/`. The longer open-loop case accumulates up to 15.14 m component
position difference. That is a measured trajectory effect, not evidence of better
handling, a force/power residual closure, or a real-aircraft error bound.
The software correction is implemented, but the review's full handling/energy and
lateral-artifact interpretation gate remains open.

Baseline aircraft SHA-256: `048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd`.
Candidate: `77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9`.
Both use source-tree solver identity `6e8951de37d288138e43c07bb9e348ec31e7f920f4b9d74d6f0227827b95cdef`.
The [baseline aircraft](baseline-aircraft.json) and complete ORFL headers retain the
configuration and checkpoint; the replay reports retain markers, layout and backend.

## Reproduction

Use the [checked runner](../../../../tools/godot/README.md) and the exact pinned engine.
All output paths must be fresh. `record_pitch.gd` accepts `--aircraft=<absolute JSON>`
to regenerate the baseline fixture from the retained original data, and
`--maneuver=pulse|loop_entry`. It is research code, not a new recorder framework.

```powershell
python tools/godot/run_checked.py --timeout 120 --require-text 'complete=true' -- $GodotWindows --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/avanti-s/av17-r4/record_pitch.gd -- --out=C:/captures/new-pulse.orfl --aircraft=C:/DEVELOPMENT/OpenRCsimulator/docs/research/avanti-realism/AV-17-R4/baseline-aircraft.json
python tools/flight_log/flight_log.py replay C:/captures/new-pulse.orfl --out tmp/new-pulse-exact
python tools/flight_log/flight_log.py replay C:/captures/new-pulse.orfl --candidate C:/DEVELOPMENT/OpenRCsimulator/app/data/aircraft/sebart_avanti_s_a200.json --out tmp/new-pulse-candidate
python tools/flight_log/flight_log.py compare tmp/new-pulse-exact/flight.csv tmp/new-pulse-candidate/flight.csv --out tmp/new-pulse-comparison.json
```

Exact replay still requires the recorded solver sources/engine. A later changed-law
candidate cannot replace this baseline's exactness proof. Current native parity is
recorded separately below; no rendered, real-radio, pilot, physical or 1080p performance
qualification follows from these headless checks.

## Native comparison

The [Linux/WSL native report](native/README.md) records actual C++ execution on the
same corrected aircraft data: 3,500 sampled Avanti stages across seven weather cases
(including malformed/nonfinite probes), and three paired 64-tick trajectories.
All recorded comparisons match. Across the complete three-aircraft liquid-stage
oracle, 64,136 comparison records match and all nine trajectories complete. Native
stage/context counters and the exhaustion event establish execution rather than fallback.

The temporary build receipt was refreshed without installing a production backend.
The generator's later edit only corrected evidence links in its report; generated
aircraft bytes remained unchanged. See the [artifact manifest](manifest.json) for
retained file and candidate-source hashes. This bounded oracle does not qualify a
normal installed session, a Windows native backend, long flights or performance.

The [fleet-boundary record](native-boundaries/README.md) separately refreshes the
exact Avanti crosswind runway refusal pins in both fleet validators. Four actual
reset observations preserve the original frame and refusal outcome; aircraft,
setup and live-configuration hashes change with Cmq. Both validators accept the
two matched pairs and reject ten deliberate proof mutations. The existing Godot
policy suite passes 586 checks and the Python campaign suite passes 44 tests.
The actual fleet-case producer also emits two refusal rows accepted unchanged by
the campaign validator, with paired proofs identical to the captured observations.
These are pre-native refusals, not successful flights; installed-library checks
remain explicitly skipped. Historical pins and strict proof requirements remain intact.

## Historical fixed-brake gate

The [strict legacy gate](legacy-gate/README.md) admits the corrected Avanti only
when replacing its exact Cmq value/provenance block recovers the previously pinned
aircraft bytes. The historical pins and goldens remain unchanged. Its 25 Python
regressions include corrupt, duplicate and unrelated-change rejection.

A first run passed the numerical comparisons but correctly failed its final source
stability guard while unrelated flag, airship and Workshop edits continued. The
successful rerun used an isolated candidate with 1,898 inventoried entries: all
16 original beta1 goldens match, the beta2 same-host reference/candidate captures
match in full values and digests, and the brake suite passes 258 checks. All seven
checked reports and the final source/engine stability checks pass. This qualifies
that frozen candidate and these cases, not subsequent unrelated edits or required CI.
