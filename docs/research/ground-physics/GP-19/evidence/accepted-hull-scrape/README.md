# GP-19d: accepted hull-friction scrape audio

2026-10-26. The existing soft-hull force owner now supplies optional loaded
friction observations at accepted endpoints, and the existing crash-audio pool
consumes bounded short scrape grains during render updates. **550 selected
production checks across seven invocations pass with zero engine diagnostics**
and warnings treated as errors. [Report](report.json), [exact promotion
identity](production/promotion.json) and [inventory](manifest.json) bind this
scope. This is software qualification of the existing flat-solid law and audio
routing; native output, listening and performance remain open.

## Physical observation and presentation ownership

`FlightSession.hull_scrape_observation()` is a derived detached nine-key packet:
schema, version, tick, generation, law_identity, available, sampling, contacts and
reason. Its seven-key loaded rows carry contact_id, point_ned, normal_force_n,
tangent_force_ned_n, relative_tangent_velocity_ned_mps, friction_power_w and
material_id. IDs use the existing bound hull probes. Material is the existing
solid-support query's observational identity; that query does not replace the
flat hull normal/height or invent intended support/component damage.

The optional diagnostic branch follows the existing positive-normal-force guard
inside `HullContact.loads`; it uses the already-computed tangent force and point
velocity. `P_t = -Ft dot vt` is **instantaneous endpoint power**, not accepted
interval work, heat or damage. Overlap/sliding speed with zero clamped normal
load yields no loaded friction row. Loaded zero-slip or zero-power observations
produce no friction grain. `loads_at_properties` forwards the same optional
observation using the owner's accepted live fuel mass, CG and inertia; it never
reuses constant-build stiffness for finite-fuel geometry.

The method refuses pending source configuration before reading source layouts,
and lake-enabled scope is explicitly unavailable. Its cache is derived,
invalidated by accepted state/layout/field binding plus reset/restore, and absent
from physical checkpoints. Default load expressions, arithmetic order and return
envelopes stay unchanged. No new force, aircraft authoring, checkpoint field,
statistics classifier, heat/damage accumulator or audio asset is introduced.

Director's accepted callbacks run after Session commits contact IDs. They capture
SI data without touching native players. Malformed/unavailable observations clear
queued grains and request cancellation; render stops tagged slots before fresh
grains. The first positive-power endpoint queues immediately, so a short brush
does not wait the 120 ms sustained-grain interval. Up to 64 detached grains wait for
render; cues older than 0.25 **accepted simulation seconds** expire. This is not a
wall-clock latency bound on a slow or stalled host.

The existing generic `scrape.wav` and authored gain/pitch envelope remain. Its
retained provenance is original offline synthesis, not a downloaded hull
recording or calibrated acoustic efficiency. A reference of 100 W is a presentation
normalization. Tagged scraping uses the existing seven one-shot slots plus fire
voice, no additional bus/pool. Terminal impact, water and reset clear the living
scrape layer before exclusive aftermath. Legacy sliding-audio calls are
suppressed in accepted mode; visual trails and non-sliding thuds remain.

Pause/manual step, rewind/gaps/rate/generation replacement and detached packets
cannot replay stale cues. Reattach is intentionally silent until one deferred
bus-settle prime. Valid pre-setup contexts with null Simulation are safely inert.
Existing initialized callers retain their behavior.

## Production checks

| Script | Checks | Retained receipt |
|---|---:|---|
| Frozen pre-change load bytes, same-law diagnostics and independent virtual work |367|[force](production/checks/hull-force-r4znzrst/report.json)|
| Accepted scheduling, malformed/oversized/numeric domain, deferred cancellation, queues and pool lifecycle |46|[audio](production/checks/hull-audio-lt15lb0t/report.json)|
| Actual Session/source IDs, checkpoint parity, live fuel properties, pause/restore/reset/reject/reattach/null setup and water handoff |44|[Session](production/checks/hull-session-xnxf3m0e/report.json)|
| Existing CrashAudio |12|[legacy audio](production/checks/crash-audio-47x7e5yl/report.json)|
| Existing soft-contact physics |36|[soft contacts](production/checks/soft-contacts-3uol3syn/report.json)|
| Existing full-scene marks/scuffs and continuing wingtip brush |23|[feedback](production/checks/soft-feedback-oneg3yv9/report.json)|
| Existing full-scene water/dry aftermath and cleanup |22|[water](production/checks/water-director-_sqc71ar/report.json)|

Five runner markers include exact assertion counts. The two previously unmeasured
full-scene tests require the literal `checks, 0 failed`; their 23/22 counts are
independently verified from the pinned raw logs. All seven reports are complete,
exit 0, warnings-as-errors and diagnostic-free. The existing soft-contact suite
also retains the Avanti six-second belly slide ending near 0.04 m/s and finite
state. These synthetic cases do not calibrate contact compliance or sound.

The actual Session fixture observes a banked Stik wingtip through accepted
contact signals before rendering. Observed/unobserved sessions retain complete
checkpoint equality. A separate live-fuel pair verifies the same invariant;
half/full tank queries verify actual dynamic response and CG. Rejected physics
emits no accepted audio. The water-cancellation fixture injects an old queued
grain/tag without starting Dummy playback, then exercises the real Director
handoff. Native slot/mixer lifetime still needs its own gate.

## Earlier scopes, independent review and transport

The [original 10-check audit](before/checks/) records the concrete distinction
between geometric sliding and actual clamped friction. The corrected
[501-check draft cohort](draft501/identity/receipts.json) predates two defensive
sim-null guards and a cue-age comment correction. Its exact seven earlier source
files are retained with [digest reconciliation](draft501/source-reconciliation.json).
Those bytes were reconstructed from the final files by removing only the stated
guards/comment/test addition, then verified against the already-retained earlier
manifest; no numerical baseline was regenerated. The [affected 44-check rerun](final-guards/checks/)
repeats 40 cases and adds four. These counts remain separate from production.

The [independent source review](independent/review.md) has 14 new adversarial
checks plus 367 force and 44 Session reruns, 425 executions; the411 repeated checks
are not counted as new tests. Its original [numeric defect](independent/numeric-boundary.json)
shows a finite float64 position 1e50 becoming a nonfinite render vector. The fixed
validator refuses values outside the float32 render domain while accepting a
supported large 1e30 position, with no arbitrary geographical location bound.

Rejected parse, API and test-oracle attempts remain under [rejected](rejected/).
The real draft `sim.tick_rate` API error was fixed with `1/sim.dt()`. Earlier
immediate cancellation/comment and invalid-queue behavior is retained as
[superseded](superseded/immediate-cancellation-draft/), not current acceptance.
The independent overstrict float32-gain assertion is retained too. No failed or
superseded receipt is relabeled as a passing current-source check.

The [9132-byte force fixture](fixture/hull_friction_reference.bin), its
[one-time frozen-source generator](fixture/freeze_reference.gd) and
[capture receipt](fixture/capture-check/) preserve pre-change numerical output.
Raw fixture SHA256 is
`66f4a8e91c6b5161db938ac3a3deadbed9993829703fcffdd00755937e082811`;
the old HullContact source is
`aa9cd474975d8e529dea14fef46baa0c6208ca78652ba28e8203773a04024e92`.
The installed fixture has explicit `-text`, and this subtree preserves all raw
snapshots/receipts. [Transport](transport.json) verifies raw-copy hashes and Git
autocrlf clean-filter invariance; it is not a full application fresh-clone/export
claim. Eight promoted payload hashes still match at packaging. Other current
inputs are selected snapshots, not a complete concurrently edited source closure.
Historical promotion handoff notes that say pending describe their original time;
this README and production receipts define the integrated status.

Root's existing native fleet wrapper now pins 44 selected source identities,
including this chain. Earlier reusable captures missing those identities cannot
qualify current accepted ground/mechanical/scrape behavior. No new native capture
has run. Native output/headroom/listening, combined scene budgets, target-host
frame cost, advanced interval-work adapters, suspension/damage layers and the
full GP-19 plan remain open.
