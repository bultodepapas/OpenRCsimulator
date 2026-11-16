# AC-12: explicit normalized servo arrivals

Preregistered 2026-11-16, before any refinement flight using this versioned law.
Owner: AC-12 / AC-CV-06. This record supplements the [arrival study](AC-12-servo-knots-2026-11-16.md);
its private ramp-law results do not qualify this different law. G05 remains open.

## Candidate and admission

`normalized-slew-arrivals-v1` is an explicit aircraft-data selector, carried by
`openrc-creator-definition v4`. Versions 1–3 keep their historical compiler bytes.
The new law evaluates a normalized linear servo ramp followed by an exact target hold.
One rounded binary64 `abs(target - start) / rate` arrival controls the endpoint,
stage sampler and partition planner. This is a rounded-arithmetic definition;
it is not an exact-real arrival comparison. Numeric equality, including signed
zero, preserves the original start bits. Reached endpoints store target bits.
Distinct represented interior arrivals are never merged by an epsilon.
An unrepresentable absolute-clock partition refuses the entire tick.

The adapter installs the complete `joint-interval-v1` vehicle contract, with
body13, inputs4, aux4/5, continuous shaft/charge/energy/heat4 and modes1.
No servo trajectory survives the tick in hidden mutable session state.
Checkpoint v15 pins the law, callback protocol and explicit layout. Ordinary
restore cannot cross laws. Exact replay must validate the matching recorded
model, metadata and checkpoint and preserve the recorded physical frame.

Initial domain: conventional gearless single-tractor electric aircraft with
finite OCV/resistance battery, calm reference atmosphere, airborne/hand-launch
starts and explicitly selected GDScript reference backend. Pack ECM, flaps,
propwash transport/slipstream, spatial weather, failures, scenery/lake/track
collision contexts, soft hull contact and practice offsets are refused.
These restrictions also apply before reset/restore and during stepping.
Native execution and unrestricted interactive qualification are not implied.

## Fixed campaign

Campaign identity: `ac12-normalized-slew-arrivals-v1-20261116`.
The new [driver](../../../research/aircraft-creator/ac12/servo_arrival_campaign.gd)
uses exactly C01–C17 from the historical `campaign.gd`, each with its four
unchanged tapes: pitch doublet, roll doublet, rudder kick and throttle step.
Only the explicit definition version and servo selector change. No new trim,
geometry, package, command amplitude, time edge, start or environment is chosen
to improve a failed result. X/N follow-up cases are excluded from this registration.

All **68 cells** run six simulated seconds at **240, 480 and 960 Hz**, sampled
at the common 240 Hz boundaries: 1,440 rows, each 17 binary64 values. Every cell
records its own fresh 240 Hz baseline and requires complete exact replay from
tick 0 through 1,440, with 1,441 replay rows and `solver_changed=false`.
An older baseline, recovered prefix or candidate replay cannot satisfy this gate.

The historical seven metrics, formulas, floors, tolerances and maximum ratio
0.75 are used without modification. A failure remains a failure. Every cell's
initial physical frame, environment and canonical command edges must match
across rates before its refinement result can be interpreted. All 68 registered
cells must complete and pass; missing/refused cells cannot be omitted from the
denominator. A completed measurement is not automatically flight qualification.

The five diagnostic cells from the original current-source audit may additionally
run the already defined 240/480/960/960/1920/1920/3840 calibration sequence.
Report them separately; they neither replace a failed 68-cell result nor change
floors, thresholds or the registered acceptance rule. Any subsequent change to
the physical law requires a new source identity and a separately declared campaign.

## Evidence retention and release boundary

Before dispatch, retain the exact candidate snapshot manifest, source hashes,
entrypoint hash and pinned engine identity. Each audit report inventories the
actual source closure, engine binary, compiled aircraft and definition. Retain
every exact sample buffer, complete baseline `.orfl`, CSV, replay receipt and
checked-runner result outside Git. Independently recompute each metric from
the retained binary rows and verify all referenced hashes and sample counts.
Failed attempts and incomplete evidence remain explicitly labelled.

The initial adapter checks passed 49 assertions on native Apple Silicon; an
expanded frozen test also reached a checked pass on Apple Silicon and Windows.
Mac collection is still pending intermittent SSH recovery. Those are component
results, not campaign, physical, packaged-target or 1080p qualification.
The versioned compiler and exact-replay extensions are isolated candidates
pending their own checks. No new-law refinement flight has run at registration.

G05 numerical closure is only one dependency of the ClearView first-flight
milestone. Source appearance, confirmed moving parts, provenance/rights,
persistence, Home/restart, lifecycle and packaged desktop/1080p evidence retain
their independent gates in the [import plan](../../plans/clearview-aircraft-import.md).
