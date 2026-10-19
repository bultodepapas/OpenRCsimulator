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
