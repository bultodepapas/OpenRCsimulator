# OpenRC Simulator: second systems, physics and FPS audit

**Date:** 28 November 2026

**Audited production source:** [8d4169f8febfd7d78a028eaa817414217a54f24b](https://github.com/bultodepapas/OpenRCsimulator/commit/8d4169f8febfd7d78a028eaa817414217a54f24b)

**Branch:** [audit/swarm-systems-fps-2026-11-28-r2](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/swarm-systems-fps-2026-11-28-r2)

## Outcome

This follow-up investigates code beyond the [first swarm audit](https://github.com/bultodepapas/OpenRCsimulator/blob/audit/swarm-physics-fps-2026-11-28/docs/research/swarm-audit-2026-11-28/README.md). It records **six additional software defects**, **four bounded performance opportunities**, an admission extension to an existing turbine finding, and two quantified limitations already acknowledged by their governing designs.

The branch contains reports, executable witnesses, independent calculations, experimental C++ comparisons and compact receipts. Production code remains at the audited source. A successful counterexample probe means that the finding was reproduced. It does not mean that the product has been repaired.

All six requested roles participated with GPT-6.2 Astra and ultra reasoning requested: aircraft physicist, pure mathematician, senior application developer, senior native developer, game/performance developer and independent verifier. With four available execution slots, the lead rotated the specialist roles and retained ownership of Git and Godot runs. The model description records the invocation configuration, not a separate attestation of serving infrastructure.

## Evidence map

| Document | Scope |
| --- | --- |
| [Independent verification](verification.md) | Per-finding verdicts, challenges, prior-art checks and evidence limits |
| [Aircraft physics](specialists/aircraft-physics.md) | Turbine admission and the documented rotor inflow domain |
| [Mathematics](specialists/mathematics.md) | Wave contact counterexample and oblique gate-crossing analysis |
| [Application](specialists/application.md) | Race-book ownership and controller draft lifecycle |
| [Native engineering](specialists/native.md) | Stage reuse and retractable-context C++ comparisons |
| [Game performance](specialists/game-performance.md) | Skyline invalidation, expired splash work and Birds Off |
| [CI review](ci-review.md) | Exact-baseline GitHub failures and provenance |
| [Reproduction guide](../../../research/swarm-systems-audit-2026-11-28/README.md) | Probe boundaries, checked runner, files and hashes |

Source lines in the specialist reports refer to the pinned production commit. The new baseline includes changes made after the first audit; its CI status must be evaluated separately.

## Additional defects

P2 is a medium engineering priority with a reproduced correctness or qualification failure. P3 is a narrower workflow defect. These priorities do not estimate incident frequency or physical risk.

| ID | Priority | Finding | Discriminating evidence |
| --- | --- | --- | --- |
| R2-SW-01 | P2 | An admitted turbine governor target can exceed the session's hard RPM limit | A custom endpoint +0.5 RPM above maximum loads, then faults after 1,235 accepted ticks; exact-maximum control accepts 2,400 ticks and +1.5 RPM is rejected at load |
| R2-SW-02 | P2 | Tree detail changes leave the pilot skyline cache stale | At a fixed eye, Full→Off gives cached visibility 0 versus fresh 1; Off→Full gives cached 1 versus fresh 0; moving 2.1 m corrects both |
| R2-SW-03 | P2 | Ground-global initialization invokes an editor-only renderer query at runtime | Exact-source Compatibility CI logs an editor-only-query error followed by duplicate global registration and fails its visual-capture gate |
| R2-SW-04 | P2 | Water entry and exit between samples can produce a clean collision miss | Stock waves and the full aircraft hull/gear miss a 0.100 mm immersion on the full tick; the same motion split at the crest produces a terminal water hit |
| R2-SW-05 | P2 | Overlapping FPV book owners can overwrite newer race summaries | Two preloaded scene owners leave a 75 s personal best after an earlier 60 s finish; a fresh second reader preserves 60 s and both finishes |
| R2-SW-06 | P3 | An unsaved duplicated controller profile becomes unreachable after switching | The draft remains in memory while the picker offers only the saved original and New; Save asks the user to select the unavailable draft |

### R2-SW-01 — Validate the governor's reachable operating range

The loader tolerates up to one RPM of endpoint mismatch. The governor uses the admitted endpoint as a real target, while the session rejects any stage above its strict maximum. Those contracts disagree.

The custom and stock sessions begin at the same normal calculated trim, approximately 93,100.656303 RPM. The test assigns full throttle to the reference simulation input. The altered record reaches tick 1235 at 153,999.994916 RPM and refuses the next tick. Its governing exponential reaches the hard limit 4.04647 ms into that 4.16667 ms interval. Body state, RPM and tick remain unchanged on refusal, so the atomic transaction guard works.

Reject an out-of-range target, or canonicalize explicitly tolerated rounding before flight admission. Preserve exact and just-inside endpoint controls and test sustained full throttle. This is a raw custom-record defect; the untouched catalog control passes. Native source contains the same strict limit, but native runtime reachability was not executed. [Physics evidence](specialists/aircraft-physics.md)

### R2-SW-02 — Include visible skyline geometry in the cache identity

The live tree setting changes registered-node visibility. A fresh skyline ignores hidden geometry, but the glare cache only rebuilds after sufficient eye displacement or replacement. A stationary pilot can retain the old answer after either toggle direction.

The witness uses the real preference policy, worker and glare cache with a registered ordinary mesh standing in for a tree. The headless renderer cannot provide the production MultiMesh transform buffer. It proves stale cache input to retinal bleaching and off-screen glare; it does not establish a stock screenshot defect, and on-screen glare has its own depth information.

Invalidate by visible-geometry revision while preserving worker cancellation, gradual rebuilding and stable-setting reuse. Check toggles while a job is pending, then capture a stock canopy sightline on a real renderer. [Game evidence](specialists/game-performance.md)

### R2-SW-03 — Separate exported/headless registration from runtime introspection

A recent initialization change asks RenderingServer for all global shader parameters before conditionally adding the ground flag. In the exact-baseline Linux Compatibility capture, that query emits an error because it is editor-only. The attempted add then reports that the name already exists.

The evidence is a rendered GitHub CI capture through the atmosphere-field test fixture, production World/Main and real ground/grass materials. A PNG was saved, yet the checked capture correctly failed on the engine errors. There is no claim of a customer crash, corrupted pixels or measured performance loss.

Choose a supported initialization strategy that handles the normal project-owned global and the separate exported pack case without runtime list introspection or duplicate adds. Validate both absent and preexisting registration in Compatibility and the relevant native renderer paths. [CI evidence](ci-review.md)

### R2-SW-04 — Bound the surface between clear collision samples

The stock lake's two wave crests coincide at the prescribed tick midpoint. Both endpoints of a 0.24 m path clear the surface by 0.094763 mm, while the midpoint lies 0.100 mm beneath it. The whole-tick subdivision rule chooses one interval and never observes a penetrating sample.

The full aircraft query uses unchanged hull and extended gear at a constructed constant-attitude pose. It returns no event. The first-half query selects the right main gear and returns a terminal water contact. An independent calculation places entry at roughly 14.18% of the tick and exit at 85.82%. Clear-throughout and wet-at-start controls pass.

This is a collision-detector counterexample on prescribed states, not a recorded live trajectory. The existing moving-water impact-speed repair concerns contacts that have already been detected. A fix should conservatively bound penetration before discarding a two-clear-endpoint interval, subdivide uncertain intervals earliest-first and report budget exhaustion explicitly. Merely adding one midpoint sample repairs this fixture without proving all phases. Keep the 240 Hz simulation clock unchanged. [Mathematical proof](specialists/mathematics.md)

### R2-SW-05 — Publish race summaries from a current shared state

Each activity loads its race book and later writes a complete updated copy. If two owners load before either finishes, the second can replace the first owner's newly committed summary. Different courses lose an entry; the same course can lose the better time and undercount finishes.

The probe uses two actual scene objects in one process, synthetic terminal records and production callbacks/file writes. In the same-course case, 60 s followed by 75 s leaves 75 s and one finish. Opening the second owner after the first save leaves 60 s and two finishes. Both individual attempt files survive in these four scenarios. This demonstrates stale summary publication, not destruction of the authoritative attempt files or a fully flown two-window session.

Use an atomic merge/transaction or an authoritative attempt-derived rebuild strategy. A fresh read immediately before an unlocked write is insufficient for genuinely simultaneous writers. Preserve idempotency, record identity, invalid attempts and failed-save recovery. [Application evidence](specialists/application.md)

### R2-SW-06 — Keep every dirty controller draft selectable

Duplicating a saved profile creates a new profile identity and caches its edits under that identity. Switching away retains the draft, but the picker enumerates saved profiles plus New. New selects a different draft context. Saving the original then advises selecting the hidden dirty copy and leaves Controls open.

The real Controls widget retains the copied name and roll-axis edit in memory. Visiting every picker choice cannot restore it. Explicit discard closes the dialog and preserves the saved original. An immediate-save duplicate control persists correctly. The draft remains in memory until explicit discard; the saved original stays intact.

Expose dirty duplicate drafts in the picker, or enforce a recoverable save/discard transition before leaving one. Keep stable identities and test multiple drafts, device changes and immediate save. [Application evidence](specialists/application.md)

## Extension to prior turbine evidence

**R2-EXT-01 — An admitted positive capture-flow table can become negative at normal idle.** AV-14 already documented end-segment extrapolation at extremely low RPM in the stock map. The new witness uses positive knots at 100,000 and 150,000 RPM; the loader admits them even though their extrapolation is negative at the ordinary 44,000 RPM idle.

After the public runway reset and one accepted reference tick, the custom record reports −0.012 kg/s captured airflow and −1.84644 N gross thrust. Stock reports +0.06571 kg/s and +1.84644 N. Component controls show the lateral momentum reaction also changes sign. This is captured air, not fuel flow.

Validate finite positive capture flow throughout the admitted running range, including extrapolated endpoints if that policy is retained. Positivity matters because the nozzle calculation divides by the reference flow. Count this as a newly demonstrated admission consequence of AV-14, not a second discovery of linear extrapolation. [Physics details and controls](specialists/aircraft-physics.md)

## Performance opportunities

None of these experiments measures FPS. Counts describe work at a particular boundary; they cannot be converted into a whole-frame gain.

| ID | Candidate | Verified work | Scope and remaining gate |
| --- | --- | --- | --- |
| R2-PERF-01 | Stop resynchronizing expired splash visuals | Each 60-frame ordinary and held arm calls 960 droplet hides and 180 material clocks at elapsed 3.2 s, all visuals invisible | Preserve sunk-aircraft pose, shadows, camera, audio and checkpoint semantics; actual GPU/frame cost unmeasured |
| R2-PERF-02 | Avoid settled Birds Off scans and environmental recomputation | 120 pending checks over 39 hidden states imply 4,680 visits; six sun changes cause six reapplications with zero drawn primitives | Modest stock roster; preserve departures, live re-enable and current lighting |
| R2-PERF-03 | Carry the already computed native propeller pair within the stage | Per 24 eligible stage calls, emitted pow calls fall 348→300 with quasistatic wash and 396→300 with transported wash | 480 component trials preserve tested words/status/FP flags; qualified native package and complete-flight performance remain open |
| R2-PERF-04 | Reuse immutable ground context during retractable-gear updates | On this build, warm accepted component updates avoid 528 named vector-copy bytes without the lake or 1,216 with stock-size lake buffers | Counted copy traffic, not retained memory or measured whole-tick cost; actual bridge/package path still needs qualification |

For R2-PERF-01, the measured method calls and inspected implementation imply 1,920 MultiMesh setters and 720 shader parameter assignments in each 60-frame arm. The instrumented subclass forwards the stock methods. The test manually drives real Main callbacks after a synthetic impact snapshot was placed in the session’s crash state. Skip only unchanged splash visuals; Main can still require the aircraft sink pose on each presentation update.

For R2-PERF-02, the per-state total is inferred from the actual false-return scan, not an instruction-level counter. Fully hidden buffers already avoid per-bird transform/custom-data writes. Layer construction supports live re-enable and is not itself a correctness defect.

R2-PERF-03 applies an existing reuse idea to the current native port. Earlier E0b6p/H14 work and the reference path already discuss or perform reuse. The fresh result is a bounded native component comparison. R2-PERF-04 counts only named copied vectors and uses stock dimensions with synthetic terrain/state geometry. Neither experiment installs or qualifies a native backend. [Native evidence](specialists/native.md) · [Game evidence](specialists/game-performance.md)

### Recommended FPS campaign

Begin with the two native candidates for steady-flight CPU work, then measure dormant presentation paths separately. The expired splash is specific to the post-impact screen; Birds Off has a small stock state count. Keep construction/entry stalls separate from sustained flight.

Use the pinned engine and qualified native compiler/package on the target OS. At 1920×1080 first, fix aircraft, field, weather, input tape, camera, renderer, quality and power state. Include the spatial-weather/wash combinations and retractable gear in extended, moving and retracted states, with and without water context. For presentation, include splash creation, pause/resume, expiry, restore and a second event; for birds include Off at startup, departing to Off and re-enabling.

Alternate baseline and candidate after equal warmup. Collect run-level median/p95/p99 frame time, simulation tick time, accepted simulated time per wall second and CPU/GPU attribution. Check required parity, failure, replay and visual gates before accepting a change. A lower workload count supports testing a patch; it does not establish higher FPS.

## Tests and evidence limits

- **19 unchanged Godot test invocations passed** on this source: controller conditioning/integration/profile hardening, ground-vehicle and multirotor input, RC input, scalar propulsion, water checkpoints, spatial weather/session/propulsion, birds, skyline, turbine/continuous turbine, helicopter inflow, lake surface/collision, race records and controller profile creation.
- **Nine new Godot witnesses passed** through the checked runner, including controls and the two known-domain characterizations. The final turbine witness reports 34 checks, rotor 33, wave collision 12 and gate 7. Other witnesses emit structured results.
- **Two C++ A/B component experiments** and an independent mathematical oracle are retained. Native validation is limited to these standalone components on GCC 14.2.
- **Exact-baseline GitHub CI is not green.** The retained snapshot and failed-job triage are in the CI review. In-progress jobs are not counted as passes.

The host has no hardware GPU or /dev/dri and no installed native stage library. The qualified Linux compiler pin is GCC 13.3, while the component compiler is 14.2. Headless reference results do not qualify native runtime, displayed graphics, physical controllers, real-aircraft handling or a frame-rate improvement. The unchanged skyline test explicitly skips its MultiMesh readback checks under the headless renderer.

Two additional probes quantify prior limitations: the HELI-04 normalized inflow guard near zero thrust, and the race director's declared chord-scoring policy near an oblique gate edge. They are retained as evidence, not added to the six defect count. Earlier collision, wake, replay, fold, HUD, RGB and spatial-air-overwrite findings were excluded from the new count.

See the [independent ledger](verification.md) for rejected wider claims and the [reproduction guide](../../../research/swarm-systems-audit-2026-11-28/README.md) for exact hashes, logs and commands.
