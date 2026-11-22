# GOD TEST on main: integration audit and recommended changes

Date: **2026-11-22**. Owner: **GOD-12-R3**, with repairs belonging to
**GOD-12-R2a–g / GOD-13-R2** and their existing UI, scenery, physics and platform owners.

Audited main: [`7940a4081e10994f34c858c4acac3d7a1a271464`](https://github.com/bultodepapas/OpenRCsimulator/commit/7940a4081e10994f34c858c4acac3d7a1a271464).
Comparison implementation: [`7a403ea059830913192696138020fd78ec458820`](https://github.com/bultodepapas/OpenRCsimulator/commit/7a403ea059830913192696138020fd78ec458820).
All source line references below refer to that audited main, not a later moving branch.

The [authoritative plan](../../plans/god-test.md) owns implementation status.
This report answers the owner's request to inspect what reached main, compare it
with the agreed tour, and recommend corrections. It preserves the
[November 20 audit](2026-11-20-plan-audit.md),
[November 21 hardening evidence](2026-11-21-measurement-hardening.md), and
[subsequent three-host stutter observations](2026-11-21-stutter-map.md) as dated records.

## 1. Verdict

**Main contains a useful V1 diagnostic tool and the earlier measurement hardening.
It does not contain the agreed scenic takeoff–roll–crash V2 tour.** The current
three-aircraft command starts airborne, flies a runway orbit, visits Pause,
Settings and Controls, applies a lighting change, returns Home and closes. The
operating guide correctly distinguishes this from V2. A V1 `coverage=complete`
result therefore cannot establish completion of the owner's requested sequence.
See [catalog](../../../tools/godtest/catalog.py#L11-L30),
[tour construction](../../../tools/godtest/catalog.py#L148-L160), and
[implemented route](../../../tools/godtest/PERFORMANCE_TOUR.md#L62-L104).

The integration also introduced **three measurement/eligibility defects**: the
focus wait is assigned to selection statistics; the fullscreen drawability
exception is trusted beyond its declared scope; and an unfocused Wayland window
can receive a product-focus override without proof of a seatless compositor.
These deserve correction before using new runs for timing comparisons. Three
additional existing weaknesses affect takeoff evidence, independent lap verification
and direct queue admission. Sections 4 and 5 distinguish defects from unfinished
acceptance work; this is not a claim that every open plan item is a regression.

**Verification:** 210 GOD TEST, 64 queue/platform and 31 frame-watcher Python checks
passed: **305 checks in total**. Five additional offline counterexamples reproduced
the behavior recorded in [the machine-readable evidence](2026-11-22-main-audit-probes.json).
No Godot process, GPU monitor, remote worker or new target-hardware campaign was
launched. The existing stutter map was reviewed, not independently remeasured.
No application/runtime fix or performance improvement is delivered by this audit.

## 2. What reached main successfully

The following prior hardening files are byte-identical between the comparison
commit and audited main: `admission.py`, `resource_coverage.py`, `gpu_coverage.py`,
`pace_windows.py`, `godtest.py` and `tour_report.py`. The authoritative plan is also
unchanged. `analysis.py`, `render_evidence.py`, `runner.py` and the runtime driver
have subsequent changes. This is a content comparison; it does not depend on a
particular merge or cherry-pick history.

| Area | Main assessment | Boundary to retain |
| --- | --- | --- |
| Original requested mode and renderer | Preserved: a requested rendered case needs positive runtime and per-phase raw evidence; the old silent-headless-success finding is no longer current | The new transition exception needs M02 below; physical presentation is still unobserved |
| CPU/GPU monitoring | Preserved: raw required fields, owner clocks, poll gaps, stop boundaries and observer identities are checked | Poll coverage is not phase attribution or proof that the sampled GPU rendered the app |
| Local simulation pace | Preserved: tick-derived windows and lag expose slow-then-catch-up behavior hidden by a phase average | Incomplete windows and tails remain inconclusive; no statistical regression qualification |
| Automatic managed deadline | Preserved: the expanded roster receives a calculated lease; nine default cases plan 14,924 seconds | Direct preset admission still bypasses that minimum; the allowance is not a completion guarantee |
| Suite reconstruction and resume | Preserved: selected cases are rebuilt from evidence, source/engine/host identities are checked, and planned slots survive interruptions | Nonselected failed-attempt artifacts are not all independently revalidated |
| Native backend preflight | Added: Windows/Linux can refuse a stale native install before a rendered launch | The runtime backend remains authoritative; this is not native or package qualification |
| Portable CI | The tooling workflow now includes pushes to main and a Linux/Windows/macOS Python matrix | Hosted contract checks are not physical GPU or exported-package results |
| Hardware diagnosis | A new record contains Windows, M1 and Linux rendered observations, including failed Linux cases | These are single-pass, differently sourced diagnostics, not a comparable three-host baseline |

Sources: [success predicate](../../../tools/godtest/godtest.py#L82-L97),
[monitoring and pace contract](../../../tools/godtest/PERFORMANCE_TOUR.md#L263-L345),
[admission budget](../../../tools/godtest/admission.py),
[native preflight](../../../tools/godtest/runner.py#L166-L207),
[portable workflow](../../../.github/workflows/godtest-tooling.yml),
[stutter map](2026-11-21-stutter-map.md).

Two additional workload changes must remain explicit in future comparisons:
the driver now mutes the Master bus, and it retains the weather preset's own
turbulence seed while using the manifest seed for the sky. The seed change avoids
turning an exact preset into a configuration outside the Mac native domain. Compare
effective audio and weather identity, not just a manifest's single `seed` value.
These changes are recorded in [the driver](../../../app/debug/godtest_driver.gd#L263-L323);
they are not evidence that an old and new run had identical workload cost.

## 3. Comparison with the owner's requested tour

| Agreed requirement | What the three-aircraft command does on main | Assessment |
| --- | --- | --- |
| Ugly Stik → Avanti jet → Corsair | Expands that fixed roster; checks selected, loaded and model identities | Implemented V1 foundation |
| Home browsing and all three aircraft previews before flight | Selects the aircraft assigned to the current case | Full preview/panel route absent |
| Accelerate on the runway and take off | Requires an airborne start in `performance-tour`; jet/Corsair maneuver profiles are refused | Absent from this tour |
| Low climb and a right turn | Flies an experimental orbit at the broader 20–140 m AGL V1 band | The requested low departure corridor and signed turn proof are absent |
| Country club/pavilion, trees and separate rural house visible | The tour requests no farmhouse phase and has no pavilion/tree visibility gates | Absent; runway proximity cannot prove this view |
| One circuit, or two in the same flight | One position-based orbit per cycle; `--cycles 2` returns Home and loads again | Single-orbit foundation exists; V2 two-lap contract absent |
| Traverse several Home and Pause options without changing settings | Visits two Pause configuration screens; a later phase intentionally applies lighting | Does not meet read-only Home/Pause browsing |
| Horizontal 360° roll followed by recovery | Not included in the tour; older Stik-only roll has weaker endpoint evidence | Absent from the three-aircraft route |
| Intentionally crash after successful earlier phases | An aircraft crash is treated as flight loss | Expected-impact mode absent |
| Observe aftermath, inspect wreck and current damage report | No crash-report traversal or terminal-incident binding | Absent |
| Detect FPS drops and stutter, with CPU/GPU observations | Callback frame streams, watcher, pace, process and supported-device sampling exist | Useful, subject to the defects and scope gaps below |
| Repeat on MacBook, Linux GPU and Windows | Standalone diagnostics and platform-specific capabilities exist | Complete admitted and qualified V2 campaigns remain open |

Evidence: [V1 manifest and admission](../../../tools/godtest/catalog.py#L11-L30),
[aircraft restrictions](../../../tools/godtest/catalog.py#L104-L118),
[driver cycle](../../../app/debug/godtest_driver.gd#L169-L205),
[pilot landmarks](../../../research/performance/godtest/pilot.gd#L64-L88),
[actual menu/settings phases](../../../app/debug/godtest_driver.gd#L427-L550),
[crash rejection](../../../app/debug/godtest_driver.gd#L729-L737), and the
[V2 acceptance contract](../../plans/god-test.md#4a-planned-scenic-and-crash-tour).

## 4. Confirmed defects and verification weaknesses

Priorities are local to this audit. **P1** means repair before trusting the affected
measurement or rendered eligibility decision. **P2** means required for reliable
coverage or campaign execution. These priorities do not claim a player-facing
crash, security incident or demonstrated failure on all hardware. There is no P0
finding supported by this review.

### M01 — P1: focus waiting contaminates selection statistics

**New since the comparison commit.** Startup and `monitor_arm` end before
`_observe_window_focus()`, which can await frames for ten seconds. The next
`_begin("selection")` occurs afterwards. While no phase is active, `_process`
still writes `phase_index = phases.size()`: exactly the index subsequently assigned
to selection. The reducer groups those intervals by index without joining their
end timestamps to the phase's start/end events.

This is more than the documented single interval crossing a boundary. Multiple
callbacks can end **before selection begins**, yet contribute to its mean FPS,
percentiles, hitch counts and raw draw evidence. The event-bounded selection
duration excludes the wait. A seatless Wayland setup can exercise the full wait.
Sources: [phase sequence](../../../app/debug/godtest_driver.gd#L149-L173),
[focus wait](../../../app/debug/godtest_driver.gd#L681-L701),
[collector and phase IDs](../../../app/debug/godtest_driver.gd#L755-L847),
[reduction](../../../tools/godtest/analysis.py#L90-L159).

**Reproduced offline:** four one-second waiting intervals followed by 100 ten-ms
selection intervals, all assigned the next phase index, produce **20.8 FPS and
1,000 ms p99**. Reducing the one-second selection interval alone produces
**100 FPS and 10 ms p99**. Both synthetic streams have valid hashes and contiguous
clocks. This establishes the attribution error; it is not a measured target-host
slowdown. The fixture's true selection bounds are defined explicitly, not supplied
to a reducer API that currently has no such join.

**Change:** give readiness/focus waiting its own phase or an explicit unassigned
state. Preserve every interval, but validate raw-to-phase membership against the
event bounds. Keep a declared policy for the one boundary-crossing interval.

**Acceptance:** delayed focus cannot change selection's sample count or distribution;
wholly pre-start/post-end intervals cannot establish that phase's drawing; first
and crossing intervals remain accounted for without gaps or double counting.

### M02 — P1: an unverified transition label bypasses drawability

**New since the comparison commit.** The producer's exception is described as a
macOS fullscreen transition, but its condition accepts every native display. The
reducer accepts `render_window_transition=1` plus positive draw delta without
independently verifying OS, startup phase, the mode-change event or the two-second
window. The same exempted intervals contribute positive in-phase drawing.
Sources: [producer](../../../app/debug/godtest_driver.gd#L761-L790),
[raw validator](../../../tools/godtest/render_evidence.py#L90-L136),
[phase eligibility](../../../tools/godtest/render_evidence.py#L247-L254).

**Reproduced offline:** the existing Windows request fixture with four one-second
**selection** intervals, all `drawable=0`, positive draw counters and the transition
bit, returns raw phase `complete` and overall rendering `complete`, with no mode
event supplied. Removing only the bit makes the same phase incomplete. The raw
receipt reports zero ordinary undrawable intervals and four transition intervals.

This is a contradictory retained-evidence counterexample. The normal producer
restricts its bit to startup and two seconds; this audit does not claim it emitted
the impossible selection fixture. The defect is that independent revalidation
does not enforce those restrictions, and the producer does not enforce the claimed
platform restriction.

**Change:** if the Mac exception is retained, bind it to an independently validated
platform and startup mode event, exact interval bounds and a single transition.
Retain actual undrawable counts separately from any admitted exception. Require
genuine drawable progress in the phase and describe physical presentation as
unverified until independently observed.

**Acceptance:** wrong phase, unsupported platform, missing/stale event, an interval
outside the bound, zero draws and a wholly undrawable phase cannot pass. Preserve
a positive fixture and target-host evidence for the narrowly supported transition.

### M03 — P1: unfocused Wayland windows receive an implicit focus override

**New since the comparison commit; source-confirmed, not hardware-reproduced.**
After waiting, any unfocused Wayland window with the relevant property receives
`app.window_focus_probe = func(): return true`. The code labels this
`wayland_without_keyboard_focus` without proving that the compositor lacks a
keyboard seat. It records the override but the reducer checks focus-loss event
counts, not the initially unfocused state or the override. A window that was
already unfocused need not emit a new loss event.
Sources: [override](../../../app/debug/godtest_driver.gd#L681-L701),
[focus verdict](../../../tools/godtest/analysis.py#L561-L568).

This changes the product's focus condition and can make an unsupported desktop
state look like an eligible rendered diagnostic. The analysis comment that the
driver requires focus before selection is also stronger than the implementation.

**Change:** require an explicit functional-test mode and verified compositor
capability for a seatless override. For an interactive performance campaign,
require observed focus before selection and reject an active override. Keep these
workloads separately identified; do not silently disable the product behavior.

**Acceptance:** test an already-unfocused real Wayland desktop, a verified seatless
compositor, delayed focus and subsequent focus loss. Their eligibility outcomes
must differ explicitly. Confirm real desktop behavior on the intended Linux host.

### M04 — P2: isolated takeoff admits an airborne initial state

**Existing weakness.** The actual CLI dry run
`run ugly-standard --entry isolated --phase takeoff --dry-run` resolves to
`start=airborne` with `phases=[takeoff]`. The isolated-entry planner forces airborne
start, and the catalog accepts the combination. The pilot's takeoff completion
predicate only requires AGL above 18 m, upward velocity and more than five simulated
seconds. It does not establish initial wheel support or a departure from the runway.
Sources: [planner](../../../tools/godtest/godtest.py#L330-L333),
[validation](../../../tools/godtest/catalog.py#L104-L118),
[pilot](../../../research/performance/godtest/pilot.gd#L171-L175).

**Reproduced:** the manifest is admitted by the actual CLI. Completion from that
state is a source-derived risk; no flight was executed in this audit.

**Change:** either define isolated takeoff as a real ground fixture with verified
support and runway containment, or refuse it. Add independent acceleration,
rotation, wheel-separation, clearance and climb evidence. A climbing airborne
initial state must never earn takeoff coverage.

**Acceptance:** the current dry run is refused or resolves to an explicitly admitted
ground fixture; a synthetic airborne state fails the takeoff observer; positive
ground departures are verified for each calibrated V2 aircraft.

### M05 — P2: lap revalidation accepts an aggregate with zero samples

**Existing weakness.** The in-app observer is meaningfully stronger than a heading
counter: it checks winding, quadrants, annulus, a duration minimum, large bearing
jumps and protected-region crossings. However, it does not bound every gap and
displacement against time and speed. The independent Python reducer validates
aggregate receipt assertions and does not reconstruct the path or validate
`accepted_samples`. Sources: [observer](../../../research/performance/godtest/runway_circuit.gd#L64-L113),
[receipt validation](../../../tools/godtest/analysis.py#L169-L184),
[coverage consumer](../../../tools/godtest/analysis.py#L550-L553).

**Reproduced offline:** an otherwise plausible receipt with `accepted_samples=0`
returns `True`; a zero-winding control is correctly rejected. This does not prove
the real observer generates such a receipt or invalidate any historical flight.
It demonstrates that the independent verifier cannot establish the claimed path.

**Change:** retain bounded accepted samples or independently checkable gate receipts
and reconstruct winding/corridor evidence. Bind count, start/end ticks, maximum
gap, speed-consistent displacement and session/lap identity. For two laps, retain
distinct, non-overlapping segments and excursions rather than duplicate receipts.

**Acceptance:** reject zero/missing samples, speed-inconsistent small jumps, large
time gaps, reused segments and altered aggregate fields; accept genuine one- and
two-lap traces with the same frozen contract for all aircraft.

### M06 — P2: direct queue presets accept an impossible campaign lease

**Existing, documented gap; the automatic managed CLI is improved.** Nine default
cases have 8,100 seconds of scenario deadlines and calculate a 14,924-second lease.
Yet `presets.validate("godtest", {"argv": ["performance-tour", "--repeats", "3"],
"timeout": 1})` accepts one second. Omitting the timeout accepts the generic
3,600-second default. The direct preset validates only the generic 1–21,600-second
range and allowed arguments. Sources: [preset](../../../tools/testqueue/presets.py#L34-L36),
[Godtest arguments](../../../tools/testqueue/presets.py#L77-L83),
[calculated budget](../../../tools/godtest/admission.py#L51-L80),
[existing disclosure](../../../tools/godtest/PERFORMANCE_TOUR.md#L136-L146).

**Reproduced offline:** both short budgets are accepted; no job was submitted.
This can terminate a correctly admitted campaign before its roster finishes. It
does not imply a false successful benchmark or a defect in the hardened automatic CLI.

**Change:** make the authority validate the full expanded roster against the
matching frozen source and reject an inadequate lease before preparation/launch.
Avoid trusting an unbound caller-provided budget. Declare queue-wait and
pre-adapter preparation bounds separately from the execution lease.

**Acceptance:** direct and automatic routes agree on the minimum for the same
snapshot, repeats and cycles; 1 s, 3,600 s and over-ceiling jobs are refused before
an engine starts; no aircraft is dropped to make a request fit.

## 5. Important open acceptance work

These are inherited requirements or incomplete capabilities, not newly discovered
runtime regressions. They remain necessary to deliver the owner's actual test.

### 5.1 Flight, scenery, menus and the deliberate crash

Implement a versioned V2 profile with all three aircraft calibrated before running
an acceptance campaign. Keep the original 30–60 m scenic AGL proposal provisional
until clearance, speed, turn radius and camera framing have been measured and
frozen. Resolve pavilion, tree group and the separate farmhouse from current scenery.
Seeing a nearby aircraft position does not establish that the house or trees were
visible in the rendered view. Use the plan's view gates and matched visual evidence
without silently changing the timed route or hiding observer cost.
The [V2 contract](../../plans/god-test.md#4a-planned-scenic-and-crash-tour) owns these
requirements; the existing [pilot](../../../research/performance/godtest/pilot.gd#L64-L107)
does not implement them for this tour.

The older Stik maneuver endpoints also need stronger proof before reuse: a target
heading 90° to the right does not establish the direction taken, and integrated
body x-rate plus final attitude does not establish a horizontal aileron roll.
Use signed accepted turn progress, ordered orientation gates, accepted controls,
bounded altitude/track/energy excursions and a separate stable recovery dwell.
The current approximately 10 Hz trajectory omits orientation and accepted control
channels. See [maneuver logic](../../../research/performance/godtest/pilot.gd#L201-L212),
[completion](../../../research/performance/godtest/pilot.gd#L272-L277), and
[trajectory schema](../../../app/debug/godtest_driver.gd#L131).

For Home and Pause, freeze exact panels, actions, order, first/repeat visits and
dwell. Check draft, effective and persisted settings after **each** action and
observe synchronous publications: a setting can change live and be reverted on
Close, so endpoint equality is insufficient. Aircraft selection in the private
profile is the explicit exception. Bind preview aircraft/livery/generation and
readiness before giving credit for a drawn preview. Sources:
[menu observer](../../../app/debug/godtest_driver.gd#L427-L481),
[live draft publication](../../../app/ui/settings_screen.gd#L1337-L1345),
[reversion](../../../app/ui/settings_screen.gd#L1394-L1403),
[preview lifecycle](../../../app/ui/home_scene.gd#L326-L363).

Arm an expected aircraft impact only after the required flight/menu/roll gates.
Bind the new post-arm terminal event to the same session and current incident
revision; an incident ID may already exist before impact. Require an admitted
contact region and calibrated impact bands, active aftermath observation, then
Inspect wreck → reopen the accident report → expanded damage details → Home.
Do not pause presentation before the aftermath window ends. Reject early/unarmed,
harmless, wrong-region, archived or unrelated reports, and keep application failure
separate from an expected aircraft accident. Current code rejects crashes, and the
product can show an archive or a settled nonterminal report; report existence alone
would be a weak acceptance test. Sources:
[crash rejection](../../../app/debug/godtest_driver.gd#L628-L645),
[archive path](../../../app/main.gd#L1343-L1361),
[settled report](../../../app/main.gd#L3092-L3094),
[wreck/report UI](../../../app/ui/accident_report.gd#L1335-L1366).

### 5.2 Resource measurements still cannot explain an individual hitch

The new owner-clock checks are valuable. They do not join host samples to engine
phase timestamps with measured uncertainty, and CPU/GPU observation starts after
bridge readiness and setup. The current runner explicitly excludes that earlier
startup scope. Approximately one-second device-wide samples cannot by themselves
assign a 300 ms menu stall to a GPU or CPU cause. Sources:
[runner scope and startup](../../../tools/godtest/runner.py#L332-L395),
[GPU scope](../../../tools/godtest/hardware.py#L1-L7),
[remaining measurement contract](../../plans/god-test.md#13-execution-steps-and-evidence-ledger).

Add bounded host/engine clock anchors, uncertainty-aware phase joins, process
coverage from launch, and positive renderer-to-sampled-device identity. Keep raw
readings and unavailable channels. Use the existing profiler/timeline tools for
attribution hypotheses and verify those hypotheses with matched ablations.
Keep physical presentation, callback cadence and simulation pace separate; a
phase-average ratio of 1.000 does not exclude local slow-then-catch-up behavior.

### 5.3 Platform support is not uniform campaign support

| Target or route | Current capability | Required before the requested acceptance claim |
| --- | --- | --- |
| Windows workstation | Rendered standalone tour and an experimental Windows-local managed adapter; NVIDIA sampling | Repeated V2 campaign, renderer/device binding, target conditions, complete evidence and owned teardown |
| Apple Silicon MacBook | Source-editor isolation, native-domain checks and AGX sampling; a retained mirrored 1080p M1 diagnostic | Native-panel primary run; test 1080p separately when available without blocking that panel result; actual output/drawable/internal pixels, thermal/power and native/backend identity |
| Linux NVIDIA/AMD | Standalone rendered path and supported vendor samplers | Admitted graphical campaign route on the intended host and independently verified device/conditions |
| Linux Intel UHD 630 | Real-GPU checked-script lane on primis; a separate shared-container Godtest diagnostic exists | Intel utilization adapter and full-campaign admission/evidence; checked-script support cannot substitute for the tour |

The primis worker's graphics lane is real progress. Its remote adapter accepts only
checked test/tool scripts and rejects recognized timing-script names and declared
performance workloads; it does not inspect arbitrary script semantics. The guide
defines the lane as functional and limits performance and physical-panel claims.
The stutter map's Linux campaign used a
different shared container. Do not describe the entire Linux GPU route as absent,
or treat the two routes as equivalent. Sources:
[primis guide](../../tools/primis-testlab.md),
[checked-only remote adapter](../../../tools/testqueue/remote_agent.py#L576-L609),
[Godtest managed limits](../../../tools/godtest/PERFORMANCE_TOUR.md#L124-L154),
[Linux diagnostic](2026-11-21-stutter-map.md#linux-intel-uhd-630-megatron-ct-206).

The Godtest sampler has no Intel utilization backend and only NVIDIA on Windows.
Even supported telemetry is not bound to Godot's actual renderer device.
Unsupported mandatory monitoring must remain incomplete; optional unavailable
temperature/power counters need not invalidate unrelated evidence.
See [sampler capabilities](../../../tools/godtest/hardware.py#L440-L455). The
[Apple panel policy](../../plans/apple-silicon-performance.md#L308-L310) keeps an
available 1080p comparison separate and does not let it block the named panel result.

### 5.4 Retention, retries, storage and comparison decisions

Resume now binds host/boot, engine, frozen inputs and observers and refuses
uncertain ownership. Preserve those improvements. The missing layer is an
append-only, hash-checked **all-attempt** ledger: current retry history contains
summaries, while suite reconstruction and HTML reopen the selected runs. A deleted
or corrupted earlier failed attempt is not independently revalidated as part of
that complete history. Retain selection/exclusion reasons, missing slots and
failures; provide verified relocation instead of relying on original absolute
paths. Enrolled standalone resume is explicitly unsupported. Sources:
[resume](../../../tools/godtest/godtest.py#L118-L267),
[selected-run validation](../../../tools/godtest/tour_report.py#L311-L360),
[HTML links](../../../tools/godtest/tour_report.py#L248-L275).

Storage preflight checks one snapshot plus 512 MiB on the output volume. Mac runs
then create per-case source/import clones and a profile on the user's home volume.
The campaign needs a budget for the full roster, streams, retries, retained failures,
profiles and recovery reserve on each real volume, plus early clone-capability
and volume-compatibility checks. No disk-full condition was induced in this review.
Sources: [snapshot reserve](../../../tools/godtest/runner.py#L97-L110),
[Mac isolation](../../../tools/godtest/isolation.py#L49-L90).

Separate execution, data integrity, route coverage, monitoring, absolute targets,
baseline regression and hardware qualification in the primary report. The current
code correctly keeps `hardware_qualified=False` and labels repeat summaries as
median/range rather than a regression test. Three repeats are a useful first screen,
not automatic statistical confidence. Define baseline/candidate pairing, order,
cache/thermal policy, sample sufficiency and observer-overhead limits before
claiming an optimization. Sources: [child verdict](../../../tools/godtest/analysis.py#L618-L624),
[suite presentation](../../../tools/godtest/tour_report.py#L240-L242), and the
[comparison contract](../../plans/god-test.md#10-comparisons-and-observer-cost).

## 6. Performance problems worth investigating next

The following values are **reported in the retained November 21/22 diagnostic
record**, not newly measured by this audit or proven to persist at the audited
main. They are callback/stall observations, not display-presentation latency or
established root causes. The record uses different source revisions across hosts.
Source for this table: [stutter map](2026-11-21-stutter-map.md).

| Investigation priority | Retained observation | Next discriminating investigation |
| --- | --- | --- |
| 1. Linux loading and simulation pace | 36–45 s loading intervals; Stik about 13 FPS and 0.63 sim/wall; jet/Corsair about 9 FPS and 0.44/0.43, both hitting the circuit wall deadline | Reproduce on an admitted idle host with native receipt; correlate loading timeline and process/GPU evidence; compare the fixed Medium workload and the product's Automatic/Low as separately named cases |
| 2. Loading on Windows and M1 | Windows loading up to about 1.1 s; M1 2.65–2.85 s | Separate decode/preparation, upload and scene attachment; retain first-load and repeated-load distributions |
| 3. Menu transitions | Settings about 0.28–0.32 s; Controls about 0.42–0.76 s across these hosts | Profile first and repeated opens of the exact panel; test screen/resource lifetime and preparation hypotheses without changing product behavior to hide the cost |
| 4. M1 Home and flight | Initial Home 42–51 FPS; jet/Corsair mean circuit 79/74 FPS with tails and a reported 94–96% mean GPU utilization | Verify pixels, thermal state and sampled-device scope; use matched view/graphics ablations and independently observed CPU/GPU timing |
| 5. Teardown | Linux Stik required a forced kill | Separate close request, flush, thread/resource shutdown and owner cleanup; reproduce with retained logs and process-tree evidence |

The record also reports a 2.8 s first Windows selection interval, a retried Windows
Corsair after focus loss, and an unrecorded M1 thermal history. Preserve those
observations and failed attempts. They make the map useful for selecting work,
but prevent a clean cross-host ranking or a before/after performance conclusion.

Before using the map as a baseline, add a lightweight index with full source and
dirty-input identities, engine/native receipts, workload/observer hashes, all
attempts, exact retrievable artifact locations and checksums. The current record
says the raw evidence is outside Git but gives no such locator/hash index. Missing
access here is an audit limitation, not proof that the raw files were lost.

**Terminology correction:** the watcher distinguishes long intervals flagged as
`ABSOLUTE_STALL` from a confirmed main-thread hang. A long callback interval alone
should be called a stall, not a proven freeze. The existing
[watcher test](../../../tools/debug/test_frame_watch.py#L361-L365) explicitly
has a stall with no confirmed hang; the
[confirmation path](../../../tools/debug/frame_watch.py#L638-L693) owns that stronger
claim. This correction does not disprove the map's numeric observations.

## 7. Recommended implementation order

Use the existing plan and tooling; a new skill or parallel benchmark framework
would not close these gaps. Split the next work into reviewable changes with
evidence specific to each behavior.

| Order and owner | Concrete change | Exit evidence |
| --- | --- | --- |
| 1 — GOD-12-R2g, PT/UI | Fix M01–M03: explicit focus phase/state, timestamp-bound frame attribution, narrow independently checked draw exception, explicit seatless functional mode | The counterexamples reject the unsupported claim; valid startup, selection and mode transitions still pass; targeted real desktop verification |
| 2 — GOD-13-R2, TQ/DT | Close M06; preflight whole-campaign storage and platform capability; retain all attempts and owned cleanup | Direct/automatic budgets agree; short/unsupported jobs refuse before launch; failed-artifact corruption and interrupted recovery remain visible |
| 3 — GOD-12-R2a/b/e, pilot/scenery | Freeze V2 profiles; implement all-three takeoff, signed right turn, scenic/view gates, one/two laps and roll/recovery; fix M04/M05 | Positive flight evidence plus airborne, wrong-turn, invisible-house, jump/gap, reused-lap and false-roll negative fixtures |
| 4 — GOD-12-R2c, UI | Fixed Home/preview and Pause routes with per-action state/publication guards | Three-preview generation binding, first/repeat panel timing and changed-then-reverted setting rejection |
| 5 — GOD-12-R2d, CR/UI | Arm impact after prerequisites; preserve active aftermath and inspect the current terminal incident/report | Early/unarmed/wrong-region/stale-report negatives; visible wreck/report interaction and clean return/teardown |
| 6 — GOD-12-R2f/g / GOD-13, PT/VQ/DT | Add resource clock joins/device binding and target evidence index; execute matched V2 campaigns, then investigate and remeasure optimizations | Full required roster on each target; actual pixel/host/backend identity; all failures retained; repeated paired results and observer-cost bounds |

Steps 3–5 can develop in isolated fixtures once their contracts are frozen, but
their final acceptance depends on the measurement and admission corrections.
Keep each aircraft's calibration separate and keep numerical physics/model changes
under their existing owners. Extending a timeout alone would hide neither low FPS
nor slow simulation; lowering detail is a new workload, not proof of optimization.

The plan also needs two small reconciliations in its next status update: section
11 still points at the old rendered-success gap as current even though the prior
hardening fixed that original path; the R1 evidence row should link the newer
diagnostics while preserving their non-qualifying scope. The operating guide's
claim that every zero-draw interval invalidates a phase is broader than the current
per-segment positive-progress rule. State the actual policy and its limits rather
than converting an isolated zero-draw observation into unsupported presentation
claims. Sources: [plan](../../plans/god-test.md#11-outcome-and-recovery-contract),
[guide](../../../tools/godtest/PERFORMANCE_TOUR.md#L311-L324),
[accumulator](../../../tools/godtest/render_evidence.py#L104-L136).

## 8. Verification and reproducibility

The audit used a clean source checkout at the pinned main, compared the relevant
files with the prior implementation, and commissioned three independent read-only
reviews: flight/menu/crash, measurement, and platform/execution. The lead checked
their source evidence and reran the five retained offline counterexamples. The
requested helper profile was Terra/max under repository guidance; observed runtime
model/effort metadata was unavailable and is not claimed as verified.

| Executed check | Observed result | Scope |
| --- | --- | --- |
| `python3 -B -m unittest discover -s tools/godtest -p 'test_*.py'` | 210 passed, 8.872 s | Python scenario, evidence, monitoring, isolation, report and resume contracts |
| `python3 -B -m unittest tools.testqueue.test_integration tools.testqueue.test_adapter_completeness tools.testqueue.test_contracts tools.testqueue.test_request_limits tools.testqueue.test_graphics_lane` | 64 passed, 1.179 s | Queue integration/contracts/limits and graphics-lane fixtures |
| `python3 -B -m unittest discover -s tools/debug -p test_frame_watch.py` | 31 passed, 2.830 s | Frame-watcher lifecycle and incident fixtures |
| Dated offline audit reproducer | Five counterexamples reproduced | M01, M02, M04, M05 and M06; M03 is source-level evidence |
| Reproducer provenance and document references | 21 source hashes and the script hash verified; isolated modified-source fixture refused; 79 local references checked | Report/reproduction integrity; no simulator-performance claim |

Environment: Linux x86_64, Python 3.12.14. The unit-test execution times are tooling
durations, not simulator performance measurements. No full app suite, GDScript
parser/runtime check, hosted CI result, target desktop or exported package was
verified in this report-only task. Existing hardware observations were assessed
from their committed summary; their external raw bundles were not available through
that record's links. The audit is source and offline-contract evidence only.

Reproduce the counterexamples on source bytes matching the audited commit:

```sh
python3 -B research/performance/godtest/audit_main_20261122.py
```

The [reproducer](../../../research/performance/godtest/audit_main_20261122.py) checks
its listed local probe inputs against embedded hashes without a Git fetch, runs no
engine/queue/GPU job, and emits the
[retained JSON](2026-11-22-main-audit-probes.json), including 21 source hashes and
the script hash. Exit zero means the historical defects were reproduced, **not**
that performance or coverage passed. After a fix, add new regression evidence;
do not rewrite this historical result to look clean.
