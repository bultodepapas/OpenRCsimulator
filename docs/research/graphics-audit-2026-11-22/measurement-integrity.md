# Two additional measurement gaps — 22 November 2026

Frozen application/tool source: `7940a4081e10994f34c858c4acac3d7a1a271464`. The new GOD TEST work materially improves evidence quality; these findings extend that review. They are not a claim that the recorded Windows or Mac runs are invalid. Existing runs need their raw timestamps and focus receipts checked before either defect can be attributed to them.

**Outcome:** the lead reproduced wrong phase attribution in the unmodified Python reducer with two synthetic, correctly hashed frame streams. Four additional synthetic focus-receipt cases show that initial-focus/override fields are ignored while a later-loss counter is rejected. No application, compositor, physical focus event, GPU or hardware campaign was launched.

The [final evidence JSON](phase-focus-evidence.json) records the source hashes, probe hash, Python version, all six cases and results. The [reproducer and instructions](../../../research/performance/graphics-audit-2026-11-22/README.md) use the existing repository artifact builders and actual `analysis.report` / `validate_stream`; they do not reimplement the reducer.

## M01. Initially unfocused Wayland can receive the seatless focus override

### Source trace

After startup/monitor arming, [`_observe_window_focus`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/godtest_driver.gd#L681) waits up to ten seconds. Its override predicate is an unfocused window, `DisplayServer.get_name() == "Wayland"`, and the existence of the application probe. It does not establish that the compositor is headless or lacks a keyboard seat. It then installs a probe returning `true` and records `window_focus_probe_override = "wayland_without_keyboard_focus"`.

[`AppRoot`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L1764) uses that probe to decide whether flight should start paused. The [`reducer`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godtest/analysis.py#L561) considers counted focus-loss events, allowing those confined to startup, but does not inspect either the recorded initial-focus boolean or override identity.

An ordinary Wayland desktop whose window never acquires focus can satisfy the same predicate as a seatless compositor. With no subsequent focus-loss event, this path does not get the ordinary loss rejection. That conflicts with using the result as an interactive-desktop performance screen under the [tour's focus contract](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godtest/PERFORMANCE_TOUR.md#L159). Other eligibility checks can still fail; this finding does not assert an observed full-tour false success.

### Offline evidence

The final witness uses a synthetic requested startup → selection → shutdown workload with two intervals per recorded phase and a synthetic Wayland label. Unlike a startup-only workload, this requested phase list would reach the driver's focus-observation call. All timestamps, draw counters and focus receipts are fabricated fixture inputs, not captured OS events.

| Input receipt | Reducer data | Performance classification | What the check establishes |
| --- | --- | --- | --- |
| Initially focused, no later loss | `valid` | `single_run_screen` | Control packet is accepted |
| Initially unfocused, no override, no later loss | `valid` | `single_run_screen` | Initial-focus field is not an eligibility guard |
| Initially unfocused, recorded Wayland override, no later loss | `valid` | `single_run_screen` | Override field is not an eligibility guard |
| One injected loss after startup | `ineligible` | `not_qualified` | Existing loss rejection still works |

These cases do not simulate a complete three-aircraft tour or demonstrate a physical Wayland failure. The unfocused/no-override packet is an intentionally mutated negative control; normal current AppRoot exposes the probe, so the Wayland driver would ordinarily install the override. The override-present case corresponds to the relevant source pathway. `single_run_screen` is the reducer's classification of synthetic packets; all case outputs remain distinct from hardware qualification. The absence of a focus guard is combined with the independently inspected driver path to establish the risk.

### Bounded repair and proof required

Keep an explicit seatless-compositor diagnostic mode ineligible for interactive qualification. For an ordinary interactive run, require observed focus and no synthetic override. If a special compositor exception is needed, bind it to an admitted, explicit environment identity and keep its evidence category distinct. Do not infer absence of a seat from a timeout.

Exercise an initially focused desktop, a real seated desktop that stays unfocused, an admitted seatless compositor, focus gained late, and a new loss after loading. Preserve the product's pause behavior and existing loss counters. A source or offline fixture cannot replace that target-platform check.

## M02. Focus-wait frames receive the next phase's index

### Source trace

The driver [ends startup/monitor arming, awaits focus, and only then begins selection](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/godtest_driver.gd#L152). While no phase is active, its [`_process`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/godtest_driver.gd#L755) still records `phase_index = phases.size()`. [`_begin`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/godtest_driver.gd#L838) subsequently assigns that same index to selection.

The [stream reducer](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godtest/analysis.py#L90) groups intervals by index. [Report construction](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godtest/analysis.py#L490) attaches those aggregates to the phase without reconciling the sample extents against `start_usec`, `end_usec` or the driver's phase-frame count. Multiple frames of waiting can therefore be included in selection's distribution, elapsed denominator and raw draw-progress count.

This differs from the documented policy of assigning a single boundary-crossing interval by its endpoint. The witnesses align every interval exactly with the declared boundaries; they contain no crossing ambiguity.

### Reproduced counterexamples

| Synthetic case | Declared selection only | Current reported selection | Consequence |
| --- | --- | --- | --- |
| 100 × 10 ms wait intervals plus one 400 ms wait stall, then 100 × 10 ms selection intervals | 100 frames; 1,000 ms; 100 interval-derived FPS; max 10 ms; no interval >100 ms | 201 frames; 2,400 ms; 83.75 interval-derived FPS; max 400 ms; one interval >100 ms | A stall entirely before selection appears in selection |
| 600 × 10 ms wait intervals, then 20 × 40 ms selection intervals | 20 frames; 800 ms; 25 interval-derived FPS; p95 40 ms | 620 frames; 6,800 ms; about 91.18 interval-derived FPS; p95 10 ms | Smooth waiting dilutes the reported selection statistic |

Both reports return `data = valid` with no issues. The second example deliberately uses a short 0.8 s selection to make the attribution visible; it is not a statistically qualified performance sample. Selection is not one of the active-flight phases scored against the 18 ms flight target, so this is not evidence that that target falsely passed.

The fixture assigns positive synthetic draw counters throughout. The resulting inflated per-phase render counts demonstrate incorrect attribution, not acceptance of a real phase with no draw progress. Physical presentation remains unobserved.

### Bounded repair and proof required

Make the focus wait an explicit recorded phase, or use an explicit unassigned state understood by all reducers. A boundary-aware reducer can additionally reconcile monotonic phase extents, frame counts and stream receipts, applying a defined rule to crossing intervals and refusing unexplained mismatches. Simply discarding all transition intervals could hide the very stalls the tool is meant to expose.

Check immediate focus, delayed focus with a wait-side stall, long smooth waiting followed by slow selection, a chunk boundary inside the wait, aborted focus acquisition, repeats, shutdown, and real boundary-crossing intervals. Retain independent tests for hash corruption, clock discontinuity, draw progression and later focus loss. Re-reduce existing raw runs before changing their conclusions; immediate focus need not produce this contamination.

## What the new stutter map can and cannot attribute

The current [stutter map](../god-test/2026-11-21-stutter-map.md) is valuable detection evidence. Its phase labels are wider than individual user actions:

- `selection` configures devices, aircraft, landscape, start, weather, sky seed and time; it is not just aircraft model selection.
- `menu_settings` and `menu_controls` begin by opening Pause, then open the target, dwell, close and resume.
- `settings` opens Pause and the lighting dialog, changes lighting and sky, applies, dwells and resumes.

Align watcher incidents with operation markers before blaming a constructor, Apply, teardown or loading stage. Do not relabel the first Windows 2.798 s interval as an aircraft-load diagnosis. The [menu report](menus-and-transitions.md) traces candidate costs independently of those broad intervals.

Current resource observers provide host-clock windows; there is no automatic uncertainty-bounded join to the engine's phase clock. A one-hertz device-utilization sample cannot isolate a 300 ms menu operation, and device utilization does not by itself identify the responsible process. Prefer existing diagnostics, including the [debug bridge's pipeline counters](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/debug_bridge.gd#L1779), with operation markers and bounded overhead. Preserve separate CPU, GPU, callback and actual presentation evidence.

## Verification record

The final script was executed once after independent review refined the focus cases to include selection. Its two phase examples and four focus cases passed their assertions against exact audited bytes for the seven reducer modules, existing fixture helper and driver listed in the JSON. That is a listed-file identity check, not a hash of every transitive import or the whole application. The initial exploratory run remains local; the committed receipt describes only the final script and cases.

The evidence and menu reviewers challenged the counting, source reachability, fixture assumptions and statistical interpretation. Their corrections are reflected above. No current rendered FPS gain or repaired production behavior is claimed. See [current-main evidence](current-main-and-tests.md) and [the experiment priorities](priorities-and-validation.md).
