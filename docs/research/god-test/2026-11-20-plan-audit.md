# Independent audit of GOD TEST and the three-aircraft tour

Date: 2026-11-20. Scope: **GOD-12-R3 / GOD-13-R2**, the complete GOD TEST plan,
implemented three-aircraft V1 tooling and proposed scenic/crash V2 contract.
Audited revision:
[`66f2e75d545c4c79907e604082a7d4a2a6e4f1b8`](https://github.com/bultodepapas/OpenRCsimulator/commit/66f2e75d545c4c79907e604082a7d4a2a6e4f1b8).
The checkout was clean at the start. The [plan](../../plans/god-test.md) owns current
requirements/status; the [operating guide](../../../tools/godtest/PERFORMANCE_TOUR.md)
owns implemented commands and limitations. This record preserves the audit's source
identity and findings rather than redefining those contracts.

## Verdict and method

**Do not treat V1 command success as a qualified rendered benchmark. V2 is a
strengthened design, not an implemented or acceptance-ready workload.** A genuine
rendered-success gap and operational incompatibilities were found in V1. Other
findings are missing or insufficient acceptance predicates in the proposed design;
the mere absence of explicitly planned V2 code is not reported as a regression.

Three independent source-read-only reviews examined flight/UI/crash coverage,
measurement/statistical decisions and platform/execution/evidence lifecycle. The
lead checked material findings in original source and ran bounded offline probes.
No simulator, engine, remote worker or target-hardware campaign was launched. No
runtime source, physics, aircraft data or historical benchmark evidence was changed.
The audit edits requirements and guides; code-level defects below remain open.

Priority **P1** means a coverage/validity claim or the documented operating route
can be wrong; resolve or explicitly exclude that claim before promotion. **P2**
means measurement interpretation, repeatability or evidence retention needs a
stronger contract. P2 does not permit an unsupported result to pass.

| ID | Priority | Finding | Required implementation/proof owner |
| --- | --- | --- | --- |
| A01 | P1 | Requested rendering can become successful non-rendered collection | GOD-12-R2g |
| A02 | P1 | Automatic managed commands/deadlines and recovery differ from examples | GOD-13-R2 |
| A03 | P1 | Per-action settings and preview readiness can be falsely accepted | GOD-12-R2c |
| A04 | P1 | Takeoff, right turn, laps and roll need independent geometric proof | GOD-12-R2a/b |
| A05 | P1 | Scenery proximity/frustum presence does not establish visibility | GOD-12-R2a/e |
| A06 | P1 | An unrelated report/contact can satisfy a weak crash predicate | GOD-12-R2d |
| A07 | P1 | Phase resource attribution lacks clock and temporal-coverage proof | GOD-12-R2f |
| A08 | P1 | Device, physical host and drawable pixels are not fully bound | GOD-12-R2e/f; GOD-13-R2 |
| A09 | P2 | Tail statistics, stutter definitions and startup scope can be overstated | GOD-12-R2f/g |
| A10 | P2 | Whole-phase pace and summary success can hide target misses | GOD-12-R2g |
| A11 | P2 | A/B decision, achieved workload and observer-cost rules need closure | GOD-12-R2e/g |
| A12 | P2 | Failed attempts and absolute-path evidence are incompletely revalidated | GOD-12-R2g; GOD-13-R2 |
| A13 | P2 | Campaign storage, preparation and same-run host conditions lack proof | GOD-13-R2; GOD-12-R2e/f |

## Rendered success gap

**A01.** [`analysis.report`](../../../tools/godtest/analysis.py) derives `rendered`
from both the runtime flag and requested headless mode, then conditions renderer,
display and native-backend checks on that derived result. It does not reject false
rendering for a requested non-headless case. The
[driver](../../../app/debug/godtest_driver.gd) records per-phase drawing, undrawable
intervals and no-draw observations, but the reducers do not enforce every phase's
drawing proof. [`_tour_success`](../../../tools/godtest/godtest.py) accepts an
otherwise valid/complete suite if no case reports rendered.

The offline probe below returned true for that predicate. This is a source-level
counterexample, not a reproduced native-window failure. The suite still reports
`performance=not_qualified`; the defect is successful execution reporting for a
requested rendered workload, not a falsely asserted hardware qualification.

**Correction:** requested mode must remain authoritative. Require drawable state
and draw progression for every required measured phase; unexpected no-draw is a
failure, not a headless downgrade. Preserve actual headless functional success as
a separate case. The plan and guide now name this gap explicitly; runtime remains
unchanged and the rejecting fixture/guard remains required.

## Admission and execution

**A02.** The V1 guide's examples passed `--godot` and `--out`, but enrolled execution
delegates to the queue and [`presets.validate`](../../../tools/testqueue/presets.py)
rejects those worker-owned options. The automatic
[`integration.run`](../../../tools/testqueue/integration.py) leaves GOD TEST at the
3,600-second default. Nine default cases declare 8,820 seconds through
[`godtest.main`](../../../tools/godtest/godtest.py), excluding some preparation costs.
The automatic path can expire with valid later slots unattempted.

An initial broad objection was narrowed after further source inspection: **not all
managed execution is blocked**. The existing
[`testctl submit`](../../../tools/testqueue/testctl.py) accepts an explicit timeout
up to 21,600 seconds with a frozen snapshot and worker-owned engine/output. This is
the experimental **Windows-local** route;
[`worker.external_simulators`/`desktop_ready`](../../../tools/testqueue/worker.py)
do not establish a Linux/macOS graphical adapter. Checked-pool SSH availability is
not a substitute. Worker preparation before process creation is outside the later
execution timer, so that timeout alone is not an end-to-end deadline.

Standalone tour `resume` is expressly refused on an enrolled host, and the managed
GOD TEST preset does not accept that command. Even unenrolled resume refuses a
started case with missing execution/verified-shutdown evidence or changed host/boot.
There is no current reconciliation-receipt input that makes an otherwise refused
retry admissible. A fresh campaign may be required; editing receipts is not recovery.

**Correction:** scope standalone examples, document the explicit Windows route and
its receipts, reject insufficient full-campaign budgets, and track platform admission,
bounded preparation and source-bound recovery separately. No admission bypass or
automatic remote collection is introduced by the documentation.

## Flight, menus and crash coverage

**A03.** [`settings_screen.gd`](../../../app/ui/settings_screen.gd) publishes live
presentation changes and can restore the saved draft on Close/Revert. A before/after
comparison can therefore pass after the timed workload was temporarily changed.
[`home_scene.gd`](../../../app/ui/home_scene.gd) uses generation-checked asynchronous
preview requests and cached models; a ready signal alone is not a matching drawn
preview or a cold load.

**Correction:** observe draft/effective/saved values and publication/commit events
through each navigation action, including synchronous mutations; a later revert does
not erase failure. Bind preview readiness to aircraft/livery/generation and subsequent
drawn dwell. Freeze panel/action IDs, repeat visits and prefetch policy. Preserve the
explicit aircraft-selection exception and distinguish known cache state from first
observation. Neither direct UI-handler timing nor drawn readiness is physical
input-to-display latency.

**A04.** The existing [`pilot.gd`](../../../research/performance/godtest/pilot.gd)
Stik takeoff completion uses altitude/climb/time rather than independent wheel
separation. A target heading alone cannot distinguish a right turn from a longer
left turn. Its roll integrates body x-rate and final bank; coupled-axis motion can
invalidate an interpretation as a horizontal 360° roll. The
[`runway_circuit.gd`](../../../research/performance/godtest/runway_circuit.gd)
observer rejects large angular jumps and protected-region crossings, but not every
small displacement against elapsed time. These are V1 limits, not proof that a real
pilot teleported or that a historical lap was invalid.

**Correction:** require ground support/containment, normal acceleration/rotation and
sustained wheel separation; signed right-turn progress; continuous corridor and
time/displacement checks; separate non-overlapping lap segments; signed orientation
checkpoints and stable roll recovery. Keep per-aircraft calibration/held-out cases.
The current 10 Hz trajectory and final pilot receipt lack several required channels;
V2 must supply bounded independent evidence with admitted cadence/gap limits.

**A05.** The [pilot camera](../../../app/render/camera/camera_rig.gd) follows the
aircraft from the field. Aircraft proximity or frustum inclusion does not establish
that the pavilion, trees or distant house is recognizable rather than obscured or
subpixel. An easy high route may also avoid the intended scenic workload.

**Correction:** separate pavilion-plus-tree-group and farmhouse gates with resolved
IDs, drawable pixel/occlusion/visible-size/dwell predicates and continuous low transit.
Independently check visual evidence and bind it to the actual source/profile/view.
A matched visual pass needs explicit correspondence; it cannot prove a divergent
timed trajectory. Same-run capture/visibility instrumentation must establish its
overhead before timing qualification. Exact feasible gates remain calibration work.

**A06.** [`main.gd`](../../../app/main.gd) can load an archived accident report and
show settled reports after nonterminal contacts. A report's presence does not prove
the requested terminal crash. [`accident_report.gd`](../../../app/ui/accident_report.gd)
minimizes the card for Inspect wreck; it must be reopened before inspecting details,
and some reports can already be expanded. Menu/focus holds can suspend the
[crash presentation](../../../app/render/crash/director.gd) while wall time advances.

**Correction:** bind arming, accepted terminal contact, current session/attempt and
live non-archived incident/report identity. The current-flight incident ID may predate
arming; require its new terminal event/revision afterward, not a newly allocated ID.
Retain actual trigger, tick, detected contact point/surface,
position, speed and attitude inside frozen bounds. Reject prior airborne damage,
unarmed/wrong-region accidents and harmless contact as terminal proof. Keep the
accepted event tick and wall observation uncertainty; the
[impact snapshot](../../../app/physics/impact_snapshot.gd) is a tick-boundary and
interpolated observation, not exact physical wall time or proof of the physically
first contact point. Measure Inspect wreck →
reopen → expanded details, including state/draw readiness, before opening Pause to
return Home. Preserve expected aircraft accident and application success separately.

## Measurement and conclusions

**A07.** [`ResourceSampler`](../../../tools/godot/resource_samples.py) and the
[GPU sampler](../../../tools/godtest/hardware.py) use Python monotonic clocks;
[phase events](../../../app/debug/godtest_driver.gd) use Godot ticks. The
[reducer](../../../tools/godtest/analysis.py) explicitly leaves these domains
uncorrelated. At 1 Hz, even aligned polls may miss a subsecond event. CPU
`required_coverage=complete` checks required fields/counters/stop state but does not
bound poll or final gaps; the GPU sampler has a separate bounded-gap policy.

**Correction:** require clock domain/epoch/units, bracketed alignment/drift uncertainty,
sample acquisition intervals and per-channel start/inter-sample/end coverage.
Overlapping observations stay ambiguous; unresolved short phases are unavailable.
Preserve whole-device GPU and direct-PID CPU scope. Correlation alone is not a cause.

**A08.** [`tour_report.py`](../../../tools/godtest/tour_report.py) compares renderer
metadata and sampled-device inventory independently. An unrelated sampled NVIDIA GPU
does not establish utilization of an Intel renderer. Software-adapter name rejection
is not positive physical-device proof. Window/viewport coordinates do not establish
Retina drawable/internal pixels. Engine byte equality does not establish an official
pin or complete platform bundle provenance. The exploratory
[`compare`](../../../tools/godtest/analysis.py) omits some physical-host, observer
and monitoring checks required by the written policy.

**Correction:** retain positive host/device association, actual rendering/native
backend, independent pin/library provenance, requested and actual pixel layers and
same-run identities. Fix the plan's blanket 1080p sentence to preserve native Retina
priority. Unsupported Intel/Windows-AMD utilization remains unavailable. Keep
exploratory comparator eligibility separate from hardware eligibility.

**A09.** The [phase reducer](../../../tools/godtest/analysis.py) assigns a full
callback interval to its end phase; that conserves totals but cannot localize the
cause of a boundary-crossing stall. Fixed-threshold phase runs differ from watcher
relative-stutter episodes; bounded incident snippets do not supply full per-phase
watch totals. Tail status can become available with only one tail frame. Startup
watching begins after Home, resource sampling after bridge readiness, and the first
in-app interval is a bootstrap span.

**Correction:** expose detector/formula identity, sample/duration/tail support,
boundary overlaps, clipped runs and missing intervals. Report short-event raw
intervals/maxima/repeated latencies; do not qualify underpowered tails. Preserve
unobserved startup and callback-versus-presented-frame scope. No missing channel is
zero, and no invented split of a long interval establishes exact impact/UI cost.

**A10.** The phase-total simulation/wall ratio can mask lag followed by catch-up:
five seconds at 0.5× followed by five at 1.5× averages 1.0. The existing stream has
tick/time/hold observations, but the
[suite phase rows](../../../tools/godtest/tour_report.py) omit simulation pace and
the normal observations surface pacing/loading misses without equal prominence for
simulation misses. [`_tour_success`](../../../tools/godtest/godtest.py) intentionally
does not mean the screen met its performance targets.

**Correction:** expose whole-phase and predeclared local active-flight pace/lag in
primary JSON and HTML, with sufficient windows and hold exclusions. Separate
collection success, absolute target compliance, regression and hardware qualification.
Do not infer any of those from a green exit code or a summary median alone.

**A11.** Expanding three pairs to five or more after looking at results needs a
declared stopping/decision rule. Fixed aircraft order confounds cross-aircraft cost
with warming; the same planned crash profile can yield different actual contact
energy/surface/effects. Existing observer controls were described but not explicitly
bound to the new V2 qualification proof.

**Correction:** freeze affected metrics/workload, practical effect, exclusions,
pair/block order, uncertainty and stopping rules; account for multiple comparisons
when making inferential claims. Compare within aircraft on the same verified host
and achieved route/view/impact envelope. Require measured observer overhead and
preserve the owning [performance gate](../../plans/global-performance-visual-quality.md#gates-to-freeze-in-vq-01c).
Three repeats do not establish the separate five fresh/five warm loading protocol,
20/50-cycle lifecycle requirements or 30-minute soak.

## Retention and host resources

**A12.** [`resume`](../../../tools/godtest/godtest.py) retains earlier attempt summaries,
but [`report_tour`](../../../tools/godtest/tour_report.py) validates and displays the
selected case paths rather than every failed-attempt artifact. A missing earlier
failure can remain invisible in the rebuilt selected-case report. Revalidation
follows ancestor suites and [absolute frozen roots](../../../tools/godtest/runner.py).

**Correction:** require a visible, integrity-checked per-slot attempt ledger with
selected/excluded reasons. Until implemented, retain/review all referenced attempts
and ancestors manually. Preserve original source/import/profile paths; a verified
relocation contract is new work. A successful retry cannot erase the earlier failure.

**A13.** The initial [snapshot reserve](../../../tools/godtest/runner.py) is one
copy plus 512 MiB, while the [Mac adapter](../../../tools/godtest/isolation.py)
creates a private launch tree per case. APFS clone failure has no silent copy
fallback. Separate host-state diagnostics or a one-time preflight do not prove
conditions remained stable throughout a tour.

**Correction:** preflight actual volumes, clone compatibility, full-roster evidence
growth and recovery margin. Bound preparation, capture and cleanup independently.
Retain costed same-run power/thermal/background observations or leave affected
comparisons inconclusive. Large queue artifact/status responses need bounded
collection validation; this audit did not measure a response-size failure. Preserve
local attempt evidence rather than assume a status reply archives the campaign.

## Offline probes and verification scope

The lead ran this source-only probe on the audited revision; it creates no test
output, submits no queue job and imports no simulator runtime:

```sh
python3 -B - <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path('tools/godtest').resolve()))
import godtest
from tools.testqueue import presets
args = godtest.parser().parse_args(['performance-tour', '--repeats', '3', '--dry-run'])
cases = godtest.plan(args)
managed = presets.validate('godtest', {'argv': ['performance-tour', '--repeats', '3']})
print(len(cases), sum(c['timeout_s'] + 80 for c in cases), managed['timeout'])
for argv in (['performance-tour', '--godot', '/pinned/Godot', '--out', 'tmp/audit-no-launch'],
             ['resume', 'tmp/audit-no-launch']):
    try:
        presets.validate('godtest', {'argv': argv})
    except ValueError as error:
        print(error)
result = {'data': 'valid', 'coverage': 'complete', 'performance': 'not_qualified',
          'cases': [{'rendered': False, 'monitoring': {'complete': False}} for _ in cases]}
print(godtest._tour_success(result))
PY
```

Observed: **9 cases; 8,820 s tour estimate; 3,600 s automatic managed timeout**.
The guide flags were refused as worker-owned; `resume` was refused as a managed
execution command; the final success-predicate probe printed **True**. These probes
establish the identified source behavior only, not an observed GPU or native-window
failure. Independent reducer inspection also confirmed one-frame tails and the
missing simulation-pace fields in suite rows; no broad test count is claimed.

The integrated revision changes only five Markdown documents. Validation consists
of source/claim review, local path/anchor checks, `git diff --check` and an independent
review of the integrated correction. The previous
[three-aircraft headless evidence](2026-11-20-performance-tour.md) is unchanged and
retains its original scope. No new hosted CI or target-hardware result is claimed.

## Closure and remaining work

The accepted corrections are now requirements in the plan, with implemented V1
limitations visible in both tool guides. GOD-12-R2a–g own the pilot, UI, crash,
monitoring and report work; GOD-13-R2 owns admitted campaign execution and evidence
lifecycle. V2 qualification must reject missing numeric profile values and exercise
the plan's positive/negative coverage matrix before target measurements.

Retained strengths include frozen source/import identities, private profiles,
predeclared full aircraft slots, selected-case raw-stream revalidation, unavailable
counters distinct from zero, ordinary controls over fixed 240 Hz physics and the
separation of aircraft accidents from application failures. The audit strengthens
those contracts rather than replacing the existing tools.

Still unverified: feasible/calibrated low routes and roll profiles for all aircraft;
actual same-run visibility/impact evidence; platform-specific device/clock/monitor
proof; native target readiness; sustained host conditions and observer cost; complete
recovery/relocation; required CI for a future implementation; actual MacBook, Linux
GPU and Windows qualification. Documentation completion closes the audit task,
not any of those runtime or hardware gates.
