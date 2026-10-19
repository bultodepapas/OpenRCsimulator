# UI-03-R1 / VQ-01c — runtime audit

2026-10-19. Godot 4.7.2-stable (`ed1daf0bf`), desktop Compatibility.
One confirmed diagnostic-trace loss and two regression-harness defects were repaired. A stage-air reuse experiment was
rejected because its complete-workload gain did not clear the existing 5% gate.
This report does not qualify aircraft physics, a release, or target hardware.

## Source and measurement boundaries

The working tree was already dirty and other tracks continued changing and committing
it. Measurements used a separate frozen application based on `0b5a6b6d`, with file
hashes retained in the evidence. The copy initially caught a temporarily removed
`windsock.gd`; that failed launch is retained and excluded. The three matching wind
files and sibling aircraft-authoring JSON were then copied before measurements.
The initial candidate snapshot changes only AppRoot and its new regression test.
The final verification copy also includes the two test repairs described below and
the parse-only sibling audio-bus generator required by an existing test preload.

The lead ran and reviewed integration checks; Luna Max agents independently audited
lifecycle, resources and simulation cost. No staging, commit or push command was
issued by this audit. External shared-tree commits subsequently included the quit
files; their verified hashes remained unchanged. Shared history was preserved.

Host: Ryzen 9 5900X, 24 logical CPUs; RTX 3090, NVIDIA OpenGL 617.42 / Windows driver
32.0.16.1742; Windows display reported 3840×2160 at 120 Hz; Balanced power plan.
Native probes requested 1280×720, 4× MSAA, VSync and a 60 FPS cap, with Dummy audio.
The workstation and foreground were not reserved from other activity. No screenshot
readback occurred during the frame samples. Imported/shader/OS cache temperature was
not controlled. These limits prevent a hardware acceptance or small-speedup claim.

## Confirmed defect and repair

**P1: closing the OS window discarded an active T-key diagnostic CSV recording.**
Godot's automatic close bypassed `AppRoot.quit_app()`. `Main._exit_tree()` closes the
separate F10 flight log, but did not save the in-memory diagnostic Recorder.

An external Windows probe posted actual `WM_CLOSE` to its owned Godot window after
the Recorder had collected samples. Both variants used the same frozen application,
runway start and a real Recorder subclass that redirects only the destination into
scratch storage:

| Observation | Baseline | Candidate |
| --- | ---: | ---: |
| Automatic close acceptance | true | false |
| Samples when close was requested | 24 | 24 |
| Samples at process exit | 25 | 37 |
| CSV saved | no | yes |
| Recorder still recording at exit | true | false |
| Process exit code | 0 | 0 |

The deferred candidate handler accepts additional real ticks before saving; the row
counts are not a timing comparison. The candidate preserves all recorded rows.

The [AppRoot repair](../../../../../app/app_root.gd) owns automatic-close policy only
while attached, restores the host policy on removal, coalesces same-frame requests
and routes deferred close through the existing save/discard policy. Home Quit uses
the same route. Save failures appear on the active screen, including Workshop, or
open Pause for a direct flight. A later explicit Quit retains the existing discard
behavior. No audio-drain policy or simulation law was added.

The [targeted regression](../../../../../app/tests/test_ui_quit.gd) fails 13 checks on
the baseline and passes on both the frozen candidate and current shared tree. It
covers real CSV output, failed saves, duplicate notifications, explicit retry,
Workshop's suspended recorder and host-policy restoration. Its files are test-owned.
The initial candidate test fixture omitted the Recorder's `note` property and did
not drain test audio; its misleading zero-exit/error log is retained. The corrected
fixture uses the existing UI cleanup helper and finishes without engine errors or
retention warnings.

This follows the official [Godot 4.7 quit-request contract](https://docs.godotengine.org/en/4.7/tutorials/inputs/handling_quit_requests.html).

## Performance experiment: retain the baseline

The default Stik's active, noncoupled wheel evaluator computed redundant stage air
data. A scratch-only callback reused that stage's data for aerodynamics, ground and
wash work. Coupled P-51 and Timber evaluators use other paths and were not changed.

Three alternating reference/candidate pairs used the real detached session/input
callback followed by the simulation callback, scenery collision included. Every run
completed 2,400 warmup and 12,000 measured 240 Hz ticks: 10 + 50 **simulated** seconds,
not real-time gameplay. Per-tick clock intervals exclude hashing and health checks.

| Pair | Reference median, µs | Candidate median, µs | Gain |
| --- | ---: | ---: | ---: |
| 1 | 1109 | 901 | 18.76% |
| 2, reversed order | 931 | 925 | 0.64% |
| 3 | 938 | 893 | 4.80% |

Median of run medians: **938 → 901 µs, 3.94%**. Variation is material and the complete
workload does not clear the 5% adoption gate. The isolated stage result (~5.65%) is
not a complete-workload gain. No performance candidate was integrated.

All six numeric trajectory fingerprints are exactly
`89ba9165b28639f1f2aff8848ae22ba61fd2b5d50bf2fa26b810980909f1645f`.
Reset-stage load/derivative bytes also agree. The fingerprint covers body, auxiliary,
continuous state, inputs, modes and loads; it is not every Session/checkpoint/event
field or physical validation. No golden flight was re-recorded. The executed scratch
probe was modified after measurement without retaining its original source. Its
recorded SHA-256 identifies the unavailable version; the packaged post-run probe is
explicitly not that version. This reproducibility gap further limits the timings to
diagnostic evidence and precludes adopting the candidate from this campaign.

## Native frames, loading and resources

The initial native live-input frame collector completed 3,476 samples over 60.206 s
after warmup. Whole-sample p95/p99 were **22.324/31.065 ms**, but the simulation
paused at tick 6478. Only 4,159 simulation ticks advanced between sample endpoints.
This is not a valid uninterrupted flight or frame-pacing acceptance result. The
observer did not capture a pause cause; a node-count increase is not proof of focus
loss or a crash. Render timers exclude scripting and physics.

A final short native flight completed **15.022 s / 878 frames**, unpaused, with no
fault, pause event or engine error. It advanced 3,582 ticks between sampled frame
endpoints. Wall-frame p50/p95/p99 were **15.937/30.439/36.531 ms**. Its 984 observer
samples, including warmup, measured render CPU p50/p95 **2.012/3.060 ms** and GPU
**3.305/4.721 ms**. The frame-sampled, smoothed simulation-step monitor had p50/p95
**1.534/1.832 ms**. Engine process/physics monitors are retained sampled aggregate
values, not a per-method script profile. The shorter duration, different warmup and
shared-host conditions prevent comparison with the earlier sample. The timing tails
remain an investigation target; these observations do not establish their cause.

A separate five-cycle real Home/Fly probe measured:

| Phase | Time |
| --- | ---: |
| Home first draw from app-source load | 7.593 s |
| Home first draw, engine elapsed | 11.831 s |
| First Fly first draw | 5.014 s |
| Later Fly first draws | 2.678–2.913 s |

These miss the proposed loading targets. The first flight was paused at tick zero;
the later four reached tick 12. One process is not five process-cold repetitions.

A subsequent candidate **20-cycle** Home/Fly memory observation completed with all
first draws unpaused. Every Home return had **617 nodes, zero orphan nodes, 549
resources and 3,778 objects**. Video-memory accounting plateaued at **421.21 MiB**
after cycle two. Static-memory samples ranged **176.67–178.71 MiB**, with intermittent
peaks and retained observer samples. This establishes bounded observed object counts,
not an allocation/RSS/driver-leak proof. Shutdown observed zero remaining playbacks
after 303.346 ms. This does not replace the 50-cycle/30-minute soak or real-device
audio qualification.

The maple-tree warning is a deliberate static-render fallback: its single-sided bark
material fails the wind-material contract. Per-frame HUD array copies/sorting and
unchanged paused shader writes remain low-priority profiling candidates, with no
demonstrated full-workload adoption result.

## Verification and remaining findings

The frozen candidate's initial 15-script campaign has nine clean scripts and six non-clean
scripts (including the zero-exit RC menu error). The failing Workshop legacy adapter,
Extra startup/checkpoint and atmosphere checks, and all four golden replays also fail
on the unchanged baseline. Their logs are retained, rather than weakening assertions
or changing goldens. Several are being addressed by independent tracks; current-tree
point-in-time results and final repaired-file hashes are recorded separately in the
verification ledger. The live-tree follow-ups are not an immutable qualification of
all concurrently edited source. Current runway, checkpoint, atmosphere and RC-menu checks pass after parallel
track updates. The current Extra data changed its level-start speed from 17 to 22 m/s and
its checkpoint test passes; this audit did not make or physically validate that change.

Two additional, independently reproduced harness defects were fixed:

- `test_runway_transaction.gd` overrode a turbine evaluator with three arguments after
  its parent acquired two optional arguments. The old script fails check-only parsing;
  the corrected signature forwards both arguments, and all **32** transaction checks
  pass. No rejection assertion was weakened.
- `test_workshop_trial.gd` removed physical IDs from its synthetic legacy aircraft but
  left modern tank references and tank-relative balance data. The supposedly valid
  historical source was rejected before the adapter/presentation assertions. The
  helper now removes the ID-bound fuel module and associated balance claims, deriving
  the legacy inventory CG as in the existing contact-contract fixture. A separate
  aircraft-validity assertion distinguishes fixture rejection from adapter failure.
  Before: **37 checks, 2 failures**. After: **38 checks, zero failures**.

The four golden flights still fail with exactly the same numeric errors on baseline,
initial candidate and current tree. This audit does not identify those differences
as either intended physics changes or defects; the owning physics track must
reconcile them before claiming golden/release acceptance. No golden was changed.

Final current-tree checks, full parse results and unresolved failures are listed in
[verification-summary.json](verification-summary.json). The scoped Linux check-only
pass completed **1,043/1,043 scripts**, with zero errors, warnings or timeouts; all
source hashes matched its frozen Windows copy. It predates the final Workshop fixture
edit, which was separately compiled and executed in both the current tree and frozen
candidate with 38/38 checks passing. Snapshot exclusions and all 1,043 per-file logs
are retained. This is not a parse assertion about other tracks' later untracked drafts.
The complete `app/test.sh`, full capture/export matrix,
physical input devices, independent pilot flight, other operating systems' gameplay
and the long soak were not completed. Linux check-only parsing is not Linux gameplay
acceptance. The remaining priorities are current golden/reference reconciliation,
loading/first-preview stalls, qualified full-session CPU/frame pacing and broader
memory/platform validation.

| Priority | Status and next acceptance gate |
| --- | --- |
| P1, fixed | Window-close trace loss: actual owned-window close saves every recorded row; failed save remains visible and blocks the first close; lifecycle tests pass without retention warnings. |
| P1, open | Four existing golden mismatches: explain the source/reference divergence and restore intended replay acceptance through the owning physics track. |
| P2, fixed | Two regression-harness defects: valid historical input reaches the adapter checks; overridden signatures parse; 38 Workshop and 32 transaction checks pass. |
| P2, open | Loading and frame pacing: isolate the expensive stages on a controlled host and meet the existing documented loading/CPU/frame gates during an uninterrupted representative session. |
| P3, open | Longer resource/device/platform validation: complete the existing 50-cycle/30-minute soak and relevant input/export/platform gates. |

No crash or unbounded object/resource growth was reproduced in these scoped runs.
The stage-air optimization failed its 5% complete-workload gate and was rejected;
no FPS or runtime performance improvement is claimed.

Reproduction commands and raw artifacts are indexed by [manifest.json](manifest.json). Long reports,
logs and probe sources are gzip-compressed; decompress outside `app/`. The existing
[performance tool guide](../../../../../research/performance/README.md) owns the
normal CPU/loading commands. `window_close.py` and its sibling probe reproduce the
owned-window close test; destination files must be new. Dated source snapshots are
identified by hashes rather than assumed to match a moving branch.
The full WIP snapshots remain in local scratch storage; hashes alone cannot recreate
uncommitted source from a clean clone. The packaged native observer includes pause
logging added after the first long sample; its earlier source was not separately
frozen. Exact-source retention must precede any future adoption-quality timing run.

## Follow-up campaign — source drift and loading attribution

The second campaign froze 2,990 application/source inputs from the concurrent WIP at
`a518147ab`, including matching sibling authoring JSON and the test audio helper.
The frozen files, rather than that commit alone, define the measured source. Three
Luna Max investigations covered replay provenance, loading attribution and lifecycle.
The lead ran the native measurements and reviewed their scope. The only production
change from this follow-up adds two missing scenery construction timing fields.

The fresh native live-input baseline completed **30.001 s / 1,778 frames**, unpaused
and fault-free, with no pause events. Frame p50/p95/p99 were
**16.669/18.713/20.066 ms**; maximum **345.523 ms**. At that largest interval the
simulation advanced exactly 12 ticks, respecting the configured catch-up bound.
It advanced 7,132 ticks between the measured frame endpoints. This is steady trimmed
flight on the shared workstation, without physical-device or independent pilot
qualification. It is not a comparison against the earlier campaign's different WIP.

A separate inclusive `Main._process` instrumentation run opened Pause at tick 35
with a menu hold and no crash/fault. It is excluded from active-flight qualification.
Its paused presentation p50/p95 costs were **957/1,461 µs** overall, **69/116 µs** in
HUD work and **7/12 µs** in the history/audio segment. That evidence does not justify
a HUD ring-buffer rewrite or establish the cause of the native frame stall.
The temporary instrumentation was confined to retained scratch sources.

The native real Home/Fly attribution probe completed three cycles, each unpaused at
first draw (tick 12), with zero orphan nodes. Home first draw from source loading was
**6.197 s**. Fly first draws were **3.270, 2.136 and 1.870 s**; Home returns were
**0.986, 0.970 and 1.003 s**. Nested inclusive measurements showed initial Home field
construction at **2.385 s**, including **1.442 s** in scenery attachment. Later scenery
attachments took approximately **0.26–0.29 s**. First flight creation took **1.206 s**,
and later creations approximately **0.23 s**. Nested intervals overlap and must not be
added. This is attribution, without an optimization comparison or controlled cold caches.

A second native split measured first-flight resource load at **1.456 s**, but warm
loads at **0.529/0.545 ms** and instantiation at **0.055/0.063 ms**. The earlier
approximately 0.23 s warm creation cost did not reproduce. A separate headless probe
confirmed that a strong PackedScene reference avoids reload, but the measured warm
cost is too small to justify retaining it. No scene cache was integrated. These runs
do not establish a loading speedup or explain all host/cache variation.

The existing scenery statistics omitted `ImportedVegetation.build` and
`Population.build`. A [four-line change](../../../../../app/scenery/scenery.gd) adds
their inclusive build/attachment timings to `stats.timing_ms`. In one native cold
build, these accounted for **353.655 + 120.608 = 474.263 ms** out of **1,047.639 ms**.
The recorded phases consequently covered **99.8%**, compared with **54.5%** without
the two fields in that same sample. Warm values were **2.64–4.58 ms** for vegetation
and **5.39–7.86 ms** for population. This improves profiling coverage; it changes no
geometry, resource ownership, gameplay or physics law and makes no FPS claim.

The seven native builds in that campaign all reported finite, nonnegative values for
both fields. Three Home/Fly cycles remained unpaused at first draw with zero orphan
nodes. The initial revised diagnostic overlay redeclared a local variable and failed
parsing before gameplay; its source/log are retained and excluded. The corrected
overlay passed check-only and native execution. The production change contains only
the four timing lines, without the temporary overlay.

All four freshly recorded scratch maneuvers self-replayed at **zero body error**, with
auxiliary and discrete agreement. The four stored goldens still fail with the same
errors as before. Comparing stored and regenerated records shows identical input
transition ticks and discrete modes, but different trim-derived commands, body
velocity/attitude and auxiliary values at tick zero. The command tapes are not
byte-identical. This establishes a different initial trim before integration starts.

History shows subsequent finite-fuel, mass/balance and aerodynamic-data changes while
the replay harness/policy remained unchanged. That supports source/reference drift;
the old records' dirty stamps and missing aircraft/config hashes prevent reconstructing
their exact source. The glide stamp's commit object is unavailable locally. Current
self-consistency does not establish physical accuracy or authorize replacing references
from unrelated WIP. No stored golden or assertion was changed.

The independent lifecycle review found no additional defect on the supported
single-AppRoot route. Concurrent AppRoots can conflict over the shared close policy;
the production entry installs one root, so this remains an embedding limitation.

Final verification on the current shared tree passed **126/126 scenery assertions**
and three native Home/Fly cycles without engine errors. The frozen baseline and
instrumented-copy scenery suites each passed the other **125** assertions but failed
the existing 800 ms cold-build gate (**2,671.082 / 863.248 ms**). These runs have
different host/cache histories; the current pass does not establish a speedup or
close the target-hardware loading gate. No budget, reference or assertion was relaxed.
The integrated file's bytes match the reviewed, parsed and natively exercised candidate.

The follow-up commands, source identities, raw measurements and final experiment
decision are retained in [round-2/manifest.json](round-2/manifest.json) and
[round-2/verification-summary.json](round-2/verification-summary.json). The full suite,
export/device matrix, long soak and qualified full-session frame/CPU gates remain open.
The official [Godot 4.7 profiler guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html)
describes manual inclusive microsecond timing; [Performance monitor documentation](https://docs.godotengine.org/en/4.7/classes/class_performance.html)
notes that some monitor values can lag by up to one second. Sampled engine counters
are not independent per-frame or per-method measurements.

## Round 3: frozen-source review and blocked qualification

The next snapshot was clean commit `122889b8e846b501dc17ffd610e60bf340bd4786`;
SHA-256 identities cover its 2,955 tracked app files. A 45-second live-input native
run is excluded from steady-flight acceptance: a connected XInput controller changed
the controls, followed by a crash at tick 2,412 (10.05 simulation seconds) and pause.
Its copied import cache also referenced an absent ignored native installation.
The installation was restored only after its binary hashes and source digest matched
the receipt; no corrected performance run was completed.

A bounded fixed-trim diagnostic probe and three injected timing scripts passed
Godot 4.7.2 check-only. They were not run natively. The Linux full-suite attempt
failed before `app/test.sh`: WSL returned I/O errors reading the engine and system
tools, including `timeout` (wrapper exit 126), then failed to start. No round-3
unit, full parse or integration coverage is claimed. A separate review found path
mapping and aggregate-status defects in the unused scratch shell orchestrator;
that orchestrator was never a suite result.

The construction review rejected duplicate vegetation-spec reuse as too small to
justify a performance change. Prior WIP construction timings are distinguished
from current static input counts. The tooling guide now names the actual D10-R2
sideslip-only pending check and flag; recovery assertions remain mandatory. No
threshold, golden flight or physics law was changed in this round.

At the user's cleanup request, the disposable round-3 checkout was removed after
verifying its clean pinned source. Its commit and file identities remain available;
the prepared probe needs that snapshot recreated before running. The older WIP
snapshots and unique evidence were preserved with NTFS storage compression. All
24 remaining registered worktrees exist and resolve a Git HEAD; three sampled
older source files still match their recorded hashes. The shared tree advanced
independently during the audit; results are qualified only for their identified sources.

[Round-3 results and artifact identities](round-3/verification-summary.json) retain
the failed native sample, wrapper logs, prepared probe and rejected experiments.
The complete app suite, unexplained frame-stall root cause, long soak and target
platform/device qualification remain open.

## HUD-12 / AUD-03 — presentation follow-up, 2026-10-19

This separate campaign starts from `d42ce9048`. The native application was flown,
restarted and visually inspected on the RTX 3090. The connected gamepad closed the
throttle during that exploratory flight; its pauses/crashes make its 60-second
frame sample unsuitable for active-flight qualification. No flight law, input
mapping, aircraft data, material or golden flight was changed.

Three bounded repairs remove presentation work:

- Hidden diagnostics no longer query air/gear/flap data, format labels or sort the
  performance window every frame. An initial diagnostic snapshot and explicit
  capture refresh remain available. Visible diagnostics keep their original frame
  cadence; showing diagnostics/performance independently refreshes current data.
- Hidden transmitter overlays no longer rebuild their gimbal drawings. Current
  sticks return on the first visible refresh. Fuel/failure warnings and the existing
  10 Hz sensor sampling remain active independently of diagnostic visibility.
- Each Soundscape configuration prepares one immutable foliage PCM loop for its
  four separate players. Source bytes, wrap guards, seeded offsets, playback
  instances and detach/reattach behavior are preserved. The local cache expires at
  the end of configuration. **3,043,284 derived PCM bytes (2.90 MiB)** are avoided
  per configured soundscape; this is buffer accounting, not measured process RSS.

The [executed CPU probe](presentation-follow-up/diagnostics_probe.gd) times the
production `Main._process` callback after real session/kernel ticks outside the
timed interval. Each process runs 60 warmup and 1,200 measured callbacks, with two
240 Hz ticks per declared 120 Hz frame. This is a headless callback benchmark,
with soundscape disabled, not a GPU, whole-frame or FPS measurement.

| Pair | Reference p50/p95, µs | Candidate p50/p95, µs |
| --- | ---: | ---: |
| 1 | 1072 / 1470 | 808 / 1178 |
| 2, reversed order | 549 / 841 | 475 / 780 |
| 3 | 558 / 863 | 448 / 670 |

Median of process medians: **558 → 475 µs, 14.87% less callback CPU time**. The
first pair was substantially slower; the shared host was not reserved. All six
processes completed 2,520 ticks unpaused and without a simulation fault. All
measured numeric state/input fingerprints match
`85b32f24fac7c878d4eff7c60e863650bbf84a2b5614c7606bde87035e0750f0`.
This digest covers body, auxiliary and continuous state, inputs and tick, not every
session/event/checkpoint field or physical validation.

[Raw samples, process order and source hashes](presentation-follow-up/results.json)
retain the comparison. Reproduce with the pinned console engine, `--headless
--path app --audio-driver Dummy --script <probe> -- --subject=<Main script>
--output=<new JSON path>`. The reference Main is the exact Git blob
`146c5b8ffa50bde42c032612fc8a232f2d51c24d` at `d42ce9048:app/main.gd`;
the candidate uses `res://main.gd` and the recorded candidate file hashes.

The extended overlay test reports **127 checks, zero failures**; the soundscape
test reports **168 checks, zero failures**. Running those assertions against
disposable reference-script copies produces six expected failures in each suite.
Battery/fuel overlays, keyboard input, frame collection, failure UI, camera routing
and changed-script parsing have separate [verification records](presentation-follow-up/verification.json).
Unrelated concurrent Workshop edits were preserved. The full app suite and export
were not run. A separate native comparison did not publish a report and was stopped
after Computer Use was cancelled with physical Escape; no native FPS improvement
or completed before/after visual qualification is claimed.

### US-V09c / SM-01…09 — second presentation follow-up

2026-10-19, independently frozen at `e6d946480`. Concurrent Workshop, customization
and simulation edits were preserved in the primary checkout. The isolated candidate
changes only visual control posing and legacy smoke uploads; imported/generated
metadata from its native editor run was not transferred.

`Airplane.apply_controls()` batches the Stik's surface and throttle pose before the
existing linkage solver runs. Previously `apply_surfaces()` solved every linkage,
then `apply_throttle()` solved them all again. Standalone calls retain immediate
updates; finite-glow variants and other adapters retain their previous paths.
The new regression compares all node transforms/visibility and linkage branch,
endpoint and closure state across **512 poses in eight aircraft**. All agree exactly,
including throttle reversals, moving roots, standalone calls and a missing-throttle
fallback. The existing linkage verifier passes **376 checks**; the model verifier
passes **919 checks**.

Legacy smoke now submits birth-only uniforms only while spawning. Residual puffs
still receive live wind and precisely the same aging requests. Fully dormant
emitters skip material lookup/uploads while retaining interval/pose and bounds
bookkeeping, so the next birth uses the current segment. The extended smoke suite
passes **62 checks**; its five new optimization assertions fail on the unchanged
reference emitter. No shader, emission rate, particle capacity/lifetime, physics,
flight input or generated aircraft geometry was changed.

The same callback probe ran three alternating process pairs, with 60 warmup and
1,200 measured frames and real 240 Hz ticks outside each timed render callback.
Soundscape was disabled. These are headless CPU timings on a shared development
host; they are separate from the first presentation campaign and from native FPS.

| Pair | Reference p50/p95, µs | Candidate p50/p95, µs |
| --- | ---: | ---: |
| 1 | 809 / 1177 | 494 / 869 |
| 2, reversed order | 648 / 1006 | 632 / 953 |
| 3 | 692 / 1045 | 579 / 862 |

Median of process medians: **692 → 579 µs, 16.33% less callback CPU time**. Pair 2's
improvement is only 2.47%; host variation is material. All six runs finish at tick
2,520 without pause/fault, and their measured numeric fingerprints match the first
campaign's `85b32f24…0750f0`. No golden flight was re-recorded.

The existing native smoke review ran reference, candidate and unchanged-reference
repeat on Godot 4.7.2 Compatibility / RTX 3090: **27 checks, zero failures, 70
captures and 511 presented intervals per process**. All 42 smoke-over-background,
background and smoke-mask pairs agree pixel for pixel. Of the aircraft-inclusive
images, 12 have small differences (at most 17 pixels, maximum channel delta 15/255).
Repeating the unchanged reference also varies in 11 images (at most 12 pixels,
maximum channel delta 7/255). The exact source of that variation is unresolved;
this establishes neither blanket pixel identity nor a new image tolerance.

Eight current-tree focused invocations pass, including control-pose parity, linkage,
smoke, overlays, keyboard input, camera routing, model verification and Main parsing,
with no engine/script errors in their logs. [Verification](presentation-follow-up/round-2/verification.json),
[source hashes, raw timing records and reproduction notes](presentation-follow-up/round-2/results.json)
and [decoded-pixel comparisons](presentation-follow-up/round-2/gpu-comparison.json)
retain the limits and proof. The exact candidate patch and executed probes are
retained alongside them. Full app suite, package/export and native FPS acceptance
remain open.
