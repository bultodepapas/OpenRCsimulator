# UI-FS-08-R1 — Statistics observer cost at accepted ticks

2026-10-27. Working-tree change on baseline `b6e3fe7d4`, part of the owner-selected
"observers per frame" work. Headless CPU evidence on the Linux dev VM (Godot 4.8-beta1
official editor binary, shared host). No statistics rule, output or storage change.

## Finding and change

The fixed-wing statistics adapter samples every accepted 240 Hz tick and its detector
observes each sample. Two parts did avoidable work:

- `FixedWingAdapter.sample` called `gear_compressions`, three terrain samples per tick, only
  to derive `> 0.00001` contact flags. Above the contact law's own no-touch bound (gear
  reach over the terrain height bound) every flag is false, so `_compressions` returns one
  negative value per contact there. Invalid state, aircraft or surface table keep the
  original call; the session lake is always valid (`set_lake_context` refuses others).
- `Detector._add_speed_candidate` copied the speed window into typed arrays, sorted
  duplicates for the medians and looped over every value for stability. It now sorts packed
  copies natively and decides stability from the sorted extremes. The values are validated
  finite, the sorted order and medians are the same, and |v − median| (rounded) is monotonic
  on each side of the median, so checking the extremes is exact.

## Parity

- [`statistics_sample_pair.gd`](../../../../research/performance/statistics_sample_pair.gd):
  the baseline and candidate adapters on one real session through two descents with
  touchdown and a runway idle, 7,200 samples (2,907 ground-supported): all bytewise equal.
- [`statistics_detector_pair.gd`](../../../../research/performance/statistics_detector_pair.gd):
  identical real samples into the baseline and candidate detectors through a 30 s trimmed
  cruise and two descents, 12,960 ticks with 11,068 median candidates: returned events and
  complete `snapshot()` bytewise equal after every tick.
- Statistics scripts pass: detector (111), lifecycle (51), resets (48), store (49), writer
  (18), helicopter impact detector (26), statistics UI ([summary](tests.txt)).

## Cost

| Measurement | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| `sample()` per tick, descents only | 130.6 µs | 90.8 µs | −30% |
| `sample()` per tick, descents and runway | 140.4 µs | 109.8 µs | −22% |
| `observe()` per tick | 207.2 µs | 72.2 µs | −65% |

Whole-app airborne pairs (baseline from a hard-linked snapshot with both statistics files
from `HEAD`) were inconclusive: −9.0%, +8.1% and −3.7% with the baseline itself ranging
726–813 ms per simulated second ([raw](pairs.jsonl)). The component results are the
evidence; the whole-app share is below what three pairs on this shared host resolve.

## UI-FS-08-R2 — Composed terrain correction, 2026-11-06

External audit A6/F3 was reproduced on `84f4657814c157f1556f965861c0ab8623f48d8e`, Windows x86-64, Godot `4.8.beta2.official.cafc17a19` headless/reference. At the Club circuit tabletop, Stik NED `[39, -4, -0.755]` had physical wheel compressions `[0.01191764341364, 0.01281855653183, 0.01457621385286]` m, while the observer's field-only bound skipped all wheels. Its terrain sample also omitted the circuit, corrupting clearance and slope-relative attitude. R1's earlier equivalence claims apply to its tested scenes, not this raised terrain.

The adapter now reads `session.environment.ground()` and `ground_max_height()`, preserving malformed-table rejection and the authoritative `session.gear_compressions()` narrow query. It removes the observer's cached lake snapshot so accepted tick-zero lake/track changes use the current terrain. This changes statistics observations, not the simulation or classifier thresholds; existing historical records are not recalculated.

The new [`test_flight_statistics_terrain.gd`](../../../../app/tests/test_flight_statistics_terrain.gd) failed 19 of 82 checks before the repair and passes all 82 after it. Coverage includes the exact witness, near-tabletop clearance, ramps, rollers, banked turns, edges, runway/field controls, a terrain-relative roll discriminator, invalid surfaces/positions, rejected and accepted terrain changes, and unchanged simulation checkpoints during sampling. Production-adapter samples drive a complete staged touch-and-go, full-stop and next-takeoff sequence through the detector. These are geometry/classification fixtures, not a dynamically flown landing or physical validation.

Six focused suites pass **646 checks**: terrain (82), detector (173), lifecycle (73), ground accidents (68), intended hull-support sessions (53), and damage flight events (197). All six receipts are complete and pass with zero engine errors/warnings; source-model caveats remain printed. Lifecycle coverage includes exact observed/unobserved physics checkpoints, rollback and observer attachment. Import and draft parsing pass. The full app/visual suites and target-hardware performance were not run; this is not an FPS or physical-validation claim.

Reproduce with the [checked script runner](../../../tools/shared.md#one-godot-script). Local raw receipts are in ignored `tmp/statistics-terrain-f3/checks/`; no images are required. Candidate SHA-256: `app/statistics/fixed_wing_adapter.gd` = `797906a2db3cf3e896776a7dec7183c63f517af239d7ef4b3fe04a545e63c232`; `app/tests/test_flight_statistics_terrain.gd` = `6ed26271fe4685515828b4ffe805392de4a4d5c32ebe55a6347876c34e3a2046`.

## UI-FS-08-R3 — restored-branch sampling (2026-11-07)

A24 §3: the service supplies an eligibility callable to the fixed-wing observer. Tick and terminal-contact callbacks check it before constructing samples; the consumer retains its own guard for reentry. Restore does not disconnect/reconnect observers or change their signal positions. Explicit suspend/resume retains its lifecycle behavior, including a resumed uncredited branch whose later Restart restores sampling.

The dedicated eligibility regression passes 35 checks, including paired accepted checkpoint/ORFL rows, real hull crashes, contact/damage parity, reentry, failed saves and suspend/restart transitions. Lifecycle (74), terrain (82), ground accidents (68), damage events (197), hull sessions (53), writer (18) and statistics UI (73) also pass on pinned Windows headless beta2. See the [checked evidence index](../../menu-investigations/UI-32/audit-20261107-checks.json). No macOS complete-session timing, FPS or physical-landing qualification is claimed.

## UI-FS-03-R1 — Deletion commit and recovery (2026-11-07)

A14 F15 distinguished a refusal before the deletion fence from a committed deletion with cleanup pending and a completed deletion. The store publishes only read-back-verified survivors; the service invalidates cached and uncached queries and HUD summaries, or makes history unavailable if safe survivors cannot be established. Pending cleanup is read-only and cannot repeat the destructive action; reopening attempts forward recovery. The open screen, controls and confirmation follow the same outcome.

On pinned Windows Godot 4.8 beta2, the deletion Store/Service regression passed **207 checks**, and the UI regression passed **27 checks**, including an injected committed-fence interruption through the real Store and Service. A separate native Windows run held the final fence without delete sharing: the committed-pending result showed the durable deletion, disabled management and retained Close focus. [Shared checked evidence](../../menu-investigations/UI-32/audit-20261107-r5-checks.json).

## UI-FS-06-R1 — Admission context and history (2026-11-07)

A14 F16 replaces preference-derived practice metadata with the accepted flight's admission snapshot and resolved seed. A schema-aware history adapter validates scenario identity, keeps unsupported legacy practice context unknown, and separates recorded accepted failure activations from enabled practice. Scenario edits and checkpoint restoration invalidate stale context for future restarted records; existing records remain unchanged. Expanded details show exact stored airborne seconds; detail columns and long history titles wrap.

Pinned Windows headless checks passed **38 failure-event checks**, **35 context checks** and **61 layout checks**. The failure suite includes a real accepted activation at tick 4,800 with paired physical checkpoints; its same-tick terminal closure is synthetic. The layout cases use synthetic, schema-valid Store records at a 1920×1080 logical viewport in English and Spanish at 100% and 200% text. Independent native Windows Compatibility-renderer review on the RTX 3090 passed at actual 1920×1080 for those locale/scale combinations. Some existing labels and diagnostic notes remain English; the existing Spanish translation of Off as Ninguno also remains. See the [shared checked evidence](../../menu-investigations/UI-32/audit-20261107-r5-checks.json) for retained results.

These checks do not qualify physical controllers, assistive technology, required CI, target-hardware performance or physical flight behavior.

## Integration checks and scope, October–November 2026

Implementation evidence, **2026-10-25**: UI-FS-00…06 have runtime code and focused regression coverage; their complete acceptance columns remain open pending UI-FS-08. Detector 65, store 49, resets/reducer 48, lifecycle 51, background writer 18 and UI 49 checks passed at integration (280 focused checks total). Lifecycle includes byte-identical observed/unobserved physics state/checkpoints, failed reload rollback, accepted reload configuration identity, a background snapshot completed while live time advances, durable recovery, independent epochs and 100 attach/detach cycles. UI-FS-07 is deliberately unimplemented. Runtime/store bounds and the snapshot-versus-journal implementation decision are documented in [the current guide](../../../FLIGHT-STATISTICS.md#storage-and-implementation-boundaries). A10 is explicitly not passed: the 10,000-record synchronous benchmark took 3.118–5.802 seconds; automatic saves now run off-thread, while large-history management/indexing still need work. Human A8/A9, target-hardware A10 and packaged-upgrade A12 are not implied by software tests.

Additional UI-FS-08 software evidence: affected overlay-manager (198), responsive Pause (422), aircraft-contact/session (63), economy-checkpoint (65), flight-log (3,247) and Workshop-trial (44) checks passed, as did the Pause route/lifecycle suite. Native 1080p screen captures at 100%/200% text were inspected. The dedicated [statistics debug scenario](../../../../tools/debug/scenarios/flight_statistics.txt) passed with no engine errors and zero leaked objects at shutdown: it verifies modal input isolation, exact restart/start totals, no artificial reset coverage gap, and retained Home statistics. These checks do not substitute for the complete app suite or the human/performance gates.

The full debug-bridge smoke also passed: 28 steps, seeded UI exploration, repeated flight/Home cycles with no growing node/resource counters, and zero leaked objects at exit. This run used isolated checkout `f3d0a163c` plus the final statistics and test-helper fixes, avoiding concurrent rendering edits in the shared tree. Its initial failure exposed a smoke-helper loop that repeatedly cancelled Workshop's unsaved-change guard; recovery now discards only that known guard using the current language, with a regression protecting unrelated statistics dialogs. The Python helper suite passed (25 tests, one platform-specific skip). The complete `app/test.sh` run has not finished successfully and remains an open merge gate; smoke is not a substitute for it.

UI-FS-08-R1 (2026-10-27) lowers the per-tick observer cost without changing any output: the adapter skips gear-compression terrain samples above the contact law's no-touch bound, and the detector decides speed medians and stability from natively sorted packed copies. Samples, events and snapshots are bytewise equal in paired real-session runs; `sample()` −30% in flight, `observe()` −65%. [Evidence](README.md).

UI-FS-08-R2 (2026-11-06) corrects external audit F3: the observer now uses the session's composed ground and maximum height, including the RC circuit, and follows accepted lake/track replacements. The earlier R1 equivalence evidence did not cover raised circuit terrain. [Regression and scope](README.md#ui-fs-08-r2--composed-terrain-correction-2026-11-06); physics laws and stored historical statistics are unchanged.

UI-FS-03 checkpoint scheduling (2026-11-01): a controlled pending writer reproduced a second automatic commit immediately after the first five-second checkpoint. Periodic requests now use the in-flight snapshot's time while it is pending; event, pause and retry requests remain independent, and another five simulated seconds during a long write still requests a follow-up. The checked lifecycle test passed 73 checks, including 17 controlled scheduler assertions and byte-identical observed/unobserved physics state and checkpoints; the writer test passed 18, storage passed 148, and counter resets passed 86. This establishes the scheduling behavior, not a measured frame-rate improvement or large-history qualification.

## Design references reviewed on 2026-10-25

The original design review consulted these sources. Its pilot perspectives were design reviews and did not include interviews or human acceptance tests.

| Official source, checked 2026-10-25 | Supported inspiration | Decision for OpenRC |
| --- | --- | --- |
| [RealFlight Evolution](https://store.steampowered.com/app/2069310/RealFlight_Evolution/) | Virtual Flight Instructor and game-like skill challenges | Offer optional practice goals beside practice tools. The listing does not establish educational efficacy or a landing formula. |
| [X-Plane 12 manual, logbook](https://x-plane.com/manuals/desktop/12/) | Per-flight aircraft, date, duration, landings and cumulative time | Adopt a small durable logbook and aircraft rollups. Omit full-scale IFR, cross-country and airport fields with no RC purpose. |
| [Microsoft Flight Simulator 2024 accessibility/features](https://www.flightsimulator.com/accessibility-msfs-2024/) | Precision-landing challenges and separate assistance contexts; also timed and low-altitude events | Borrow optional accuracy/control practice and contextual comparisons. Do not borrow speed/proximity incentives or public rankings. |
| [DCS 2020 manual, Logbook](https://www.digitalcombatsimulator.com/upload/iblock/ed6/87v22jwd1xh51i3rgki944xsf503istq/DCS_User_Manual_EN_2020.pdf) | Pilot profiles, mission statistics and awards | Personal history can support modest milestones. This dated manual is inspiration, not a claim about today's DCS behavior. |

Tradeoffs resolved: airborne-start practice earns time and valid landing events, but never a takeoff credit; otherwise the available airborne-only landscapes would hide useful beginner practice. Touch-and-goes count as landing events within one flight, not as extra completed flights. Damage-free means **no observed disqualifying incident under the recorded model/rules**, not proof of an undamaged physical aircraft. Unknown evidence earns neither success nor failure. Experienced-pilot recommendations for approach-speed/sink grading remain optional until aircraft-specific references are validated; arbitrary full-scale tolerances will not gate the essential statistics.

The experienced-pilot review also checked the [FAA airspeed glossary](https://www.faa.gov/air_traffic/publications/atpubs/pcg_html/glossary-a.html) and [Airplane Flying Handbook, chapter 4](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/05_afh_ch4.pdf) for the air-relative/ground-relative distinction. [FAA stabilized-approach guidance](https://www.faa.gov/newsroom/safety-briefing/stabilized-approach-and-landing) supports treating a go-around as a sensible decision; its full-scale procedures do not establish RC scoring tolerances. The accepted aircraft `start_speed` is a launch reference, never an assumed landing `Vref`. We chose a provisional 0.5 s support window and no 15 s touch-and-go deadline over the specialist's stricter suggested windows: bounce rejection also uses re-ascent hysteresis, while an arbitrary rollout deadline would penalize aircraft with different ground handling. These product choices require the fleet cases in UI-FS-02.
