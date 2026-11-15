# OpenRC Simulator Performance Handoff Round 3 November 9 2026

Prepared for the senior developer responsible for OpenRC Simulator. This continuation identifies avoidable work introduced or exposed by recent changes, supplies three narrowly scoped candidate patches, and sets acceptance gates for frame pacing, loading time and numerical correctness.

**Decision:** first measure the complete crash-cost observer path and its archive publications; in parallel, qualify the small contact-key and meadow changes. Requalify the current companion scorer independently. The previous pilot patch is incompatible with the new interval-distance calculation.

**Evidence status:** source inspection and exact-text patch construction are complete. No new Godot execution, component timings, native GPU measurements or FPS improvement was verified in this pass. The pinned-engine extraction did not yield a valid executable, and the execution service subsequently failed. The supplied patches are review candidates, not merge-qualified changes. No production commit, pull request, external message or merge was created.

# Revision and existing audit status

| Item | Reviewed state |
| --- | --- |
| Repository | [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator) |
| Target branch | main |
| Commit | [45d86d250f6e38a3d9b60d30c01bdc2396571efe](https://github.com/bultodepapas/OpenRCsimulator/commit/45d86d250f6e38a3d9b60d30c01bdc2396571efe) |
| Commit time | November 9, 2026, 20:57:35 UTC |
| Commit subject | Add comprehensive tests for crash cost common coverage |
| Final head check | Main still pointed to this SHA during the closing review |
| Prior comparison | 300dc4e82cc6975b6f4e808cb4b2b845a0240ded; seven subsequent commits |
| Engine pin | 4.8.beta2.official.cafc17a19 |
| Simulation | 240 accepted physics ticks per simulated second; maximum 12 catch-up steps per rendered frame |

The [consolidated audit](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/external%20Audits/CONSOLIDATED-AUDITS.md) and [completed-work ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/external%20Audits/COMPLETED-AUDIT-WORK.md) were read before reviewing the current implementation. Current source and recent changes were then checked independently. The new findings below are not additional counts of the previously recorded audio/input cleanup, bounded circuit mesh cache, shared ORM readback, thermal/wind preparation, source-identity caching or raw-telemetry bounds.

Recent changes include companion restore/rejection handling and the CR-40 contact-cost pipeline. The ledger optimizations in this report concern that current implementation. They are **new performance opportunities**, not demonstrated performance regressions. CR-40 already deliberately bounds evidence and throttles a subset of archive writes; those guarantees must survive optimization.

[Draft PR 11](https://github.com/bultodepapas/OpenRCsimulator/pull/11) and [draft PR 10](https://github.com/bultodepapas/OpenRCsimulator/pull/10) remained open and unmerged. Some related work has reached main through other commits, so PR status alone is not implementation evidence.

The old missing UID files for worn-ground material and the farm-tractor test are repaired on current main. Current [CI run 42697915670](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42697915670) instead fails its selection/preflight job on five missing or invalid tracked UID sidecars: seed_allocator.gd, report_archive.gd, test_companions_external_rejection.gd, test_companions_restore.gd and test_crash_cost_common_coverage.gd. Downstream jobs were skipped. This is a release-validation blocker, not an FPS finding.

[Project settings](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/project.godot#L44-L76) select Compatibility normally, Mobile for the Apple Silicon feature override, and allow other product-quality paths such as High/Forward+. Record the actual runtime renderer in every capture; a result from Linux headless or Compatibility does not qualify Apple Silicon Mobile/Metal. Windows/Linux x86_64 and Mac renderer paths require their own relevant checks.

# Prioritized work

| Priority | Candidate or investigation | Player impact being targeted | Current evidence |
| --- | --- | --- | --- |
| 1 | Attribute crash-cost observer and evidence/archive work | In-flight CPU work and occasional frame stalls | Current default path traced; no timing |
| 1 | Reuse the immutable contact-event key lookup | Grounded/taxi/contact CPU work | Exact small source candidate and key-set check |
| 1 | Reuse meadow triangle counts within one layout | Field construction and transition delay | Exact small source candidate; historical workload only |
| 2 | Omit discarded companion endpoint distances | CPU work while companions plan around traffic | Exact current-source candidate; mathematical dependency proof |
| 2 | Prove a conservative airborne contact-observation fast path | Accepted-tick CPU cost during clear flight | Deferred numerical research |
| 2 | Requalify the prior Timber spatial-key change | Cold Timber visual repair/load | Source hunks remain portable; old timings are historical |
| 3 | Fuse full/proxy shadow face collection | Qualified Corsair bind or rebind delay | Known opportunity; memory and fallback risks remain |
| 3 | Index damage-profile rules with explicit ownership | Grounded incident processing | Source hypothesis; allocation and invalidation tradeoff |

No row above is a measured whole-game speedup. The low implementation risk of the small patches makes them suitable first experiments; it does not establish that they dominate frame time.

# Contact-event validation

## Expensive work and execution path

Normal interactive Main enables cost observations in [_begin_accident_ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/main.gd#L2869-L2880). At each accepted tick, [FlightSession._observe_contact_tick](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/sim/flight_session.gd#L2619-L2636) samples wheel compression and constructs support events. The event constructor validates them; the incident consumer validates them again. The proposed optimization retains both checks.

[_event_keys_are_known](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/sim/aircraft_contact_events.gd#L415-L422) currently creates an empty dictionary and inserts every common and optional key on every invocation. There are nine common and sixteen optional keys. The input event then undergoes membership and key-type checks.

For a three-wheel aircraft with three compressed wheels throughout a steady 240 Hz interval:

- 3 × 240 = 720 support events per simulated second.

- Two validations per event produce 1,440 temporary allowed-key dictionaries.

- 25 insertions per dictionary produce 36,000 repeated insertions per simulated second.

These are conditional operation counts, not allocations measured by a profiler. An airborne aircraft without positive support does not produce that three-event workload.

## Candidate and equivalence

Replace the reconstructed membership dictionary with one read-only 25-entry constant. Keep the original event.keys() traversal, TYPE_STRING test, str(key) conversion, payload validation, ordering and duplicate consumer validation. The cost changes from constructing and populating K entries plus checking E event keys to checking E keys against a shared table. K is the fixed value 25, so the gain is reduced constant work rather than a different asymptotic class in the current schema.

The fetched source was transformed at single, exact anchors; the generated patch was replayed against those bytes and reproduced the candidate exactly. A separate structural check confirmed that the constant contains exactly the union of the nine common and sixteen optional string keys, with no duplicates. This does not substitute for GDScript parsing or execution.

Godot's pinned [Dictionary contract](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Dictionary.xml) and [analyzer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/gdscript/gdscript_analyzer.cpp#L5409-L5433) support constant-dictionary immutability. Runtime construction inside the existing function is not automatically hoisted into such a constant.

The new retained storage is one 25-entry lookup per loaded script. Exact allocator overhead is implementation-dependent. There is no numeric approximation and no GPU transfer.

## Verification and risk

The principal maintenance risk is schema drift: the shared map could diverge from the two existing key arrays. Add a two-way set-equality invariant and exercise every allowed key, unknown and missing keys, StringName and other non-String keys, malformed measurements, NaN/infinity, typed dictionaries, duplicated observations and input ownership. Keep invalid input refusal unchanged.

Run the existing contact-events, cost-producer, incident, round-two, checkpoint and accident-integration checks through the checked runner. Benchmark complete three-wheel event construction plus Incident.observe, alongside total accepted session/observer time.

Direct iteration over the dictionary would additionally avoid event.keys(), but the pinned iterator performs a next-key hash lookup. Treat that as a separate A/B variant; the supplied conservative patch retains the original array traversal.

# Damage evidence and archive publication

## Why this deserves frame-time attribution first

[Main._update_accident_report](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/main.gd#L2844-L2866) invokes Incident.flush() from the rendered-frame path. Moving work outside an accepted physics callback avoids doing it inside that transaction, but it still occupies the main thread before later frame work.

Following damage, continuing support can update the latest contact tick even without a new financial decision. [_record_summary](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/economy/incident.gd#L704-L761) marks evidence pending. [evaluate_pending and _refresh_report_evidence](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/economy/incident.gd#L902-L932) then duplicate the summary, journal and confirmed facts; the game-assessment branch copies the summaries again. This can occur on rendered frames that will not write an archive.

[flush and _write_archive](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/economy/incident.gd#L1266-L1308) validate and encode the report, write its temporary file, call file.flush(), close it and rename it. For a nonterminal, same-revision, evidence-only report, the current interval is 60 accepted ticks: approximately four eligible publications per simulated second at 240 Hz. **This is not a global maximum.** Changed financial revisions, terminal state and forced lifecycle retries can bypass that particular throttle.

CR-40 already avoids rerunning the price optimizer for evidence-only updates. Do not describe its current behavior as a full economic recalculation every frame, or remove periodic evidence to reduce work. The [CR-40 implementation contract](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/docs/research/crash-damage-investigations/CR-40/README.md) requires persistent evidence and lifecycle handling.

## Concrete optimization design

First add scoped timing around evidence materialization, archive encode/validation, file publication and the whole Main observer slice. Correlate archive generations and accepted ticks with raw frame intervals; measure healthy taxi and post-damage taxi separately.

If copying dominates, keep cumulative accepted-tick summaries in their existing owner and publish an immutable report snapshot only at the required observation boundary. An explicit report version should determine which consumers need a fresh snapshot. Check the currently public report reads and UI ownership before changing their freshness; moving an early return above evaluate_pending would change observable state.

If file publication dominates, a bounded worker can receive an already-owned immutable snapshot. It should keep one in-flight publication and one replacement latest snapshot, tagged with incident identity, source identity, generation, revision and accepted tick. Publish completions on the main thread only if they still belong to the active generation. Preserve failure reporting, no-spin retry behavior, terminal/reset/exit barriers, temporary-file ownership and rename ordering. Never pass the live mutable report to a worker or allow an older completion to overwrite a newer incident.

This trades bounded extra snapshot memory for less main-thread encode/write work. Snapshot creation still costs time; storage latency is shifted, not eliminated. A queue growing with frame rate is unacceptable.

## Acceptance

Exercise ordinary clear contact, persistent support after repairable damage, fresh higher-severity damage, terminal events, reset/aircraft change during a write, failed open/write/rename, retry, restore and process exit. Compare ordered evidence, financial revisions and final archive content against the original. Measure p95, p99, maximum frame interval and counts above 16.67, 33.33 and 50 ms, including frames immediately surrounding publications. No current hitch or millisecond saving has yet been measured.

# Runway meadow catalog reuse

## Repeated deep copying

[runway_meadow.layout](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/scenery/runway_meadow.gd#L94-L139) first generates and caps candidates, applies the quality filter, then requests an entire asset record for every retained plant merely to read source_triangles. [ImportedVegetation.get_asset](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/scenery/imported_vegetation.gd#L90-L112) resolves the ID and returns a recursive dictionary duplicate. Nested bounds, dependencies and texture metadata are copied even though this consumer needs one integer.

The current recipes and substitutes use at most eight asset IDs. The [November 3 author measurement](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/docs/research/grass-meadow-techniques-2026-11-03.md#L47-L53) reported 4,492 final high-tier plants and approximately 130 ms for complete layout on an RTX 3090 Compatibility configuration. Those are historical observations from a different source state. They neither isolate copying time nor establish the current baseline.

For an equivalent retained set, a local scalar cache reduces successful catalog deep copies from 4,492 to at most eight, eliminating at least 4,484 copies, or about 99.82 percent of those successful copy calls. It does not imply a 99.82 percent reduction in layout time.

## Proposed ownership and cost

Create triangle_counts within one synchronous layout() invocation. After the existing quality filter, look up the asset ID. On a miss or nonpositive value, call the original API; cache only positive integer counts. Leave nonpositive or invalid results uncached, so the original repeated failure behavior remains.

Before, copying work scales with P × R, where P is the retained candidate count and R is the nested record-copy cost. After, it scales with S × R plus P small dictionary probes, where S is the distinct successful species count. Extra retained memory is O(S) scalar entries; it is released when layout returns. The other colony, mask, sorting, terrain and output construction work remains unchanged.

Per-call lifetime is the invalidation rule: changes to the catalog between calls are observed automatically. The proposal assumes the internal catalog is not concurrently modified during a synchronous layout call. It does not change the shared catalog API or return aliased records.

## Where the player benefits

[Field construction](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/field.gd#L318-L330) builds this layer for the default field when attached scenery and the meadow setting are enabled. Meadow defaults On and is available across quality tiers and renderer paths. This candidate targets field construction and transitions. It does not reduce the number of grass instances, triangles, shader operations or per-frame GPU draws.

## Verification

Compare complete ordered output dictionaries with byte-exact serialization, plus unchanged inputs, at low/balanced/high and unknown quality. Cover shifted field/pilot geometry, exclusions, polygon and clearance boundaries, all-blocked layouts, repeated IDs and aliases, invalid/missing/zero/negative counts, mutation between calls and exact triangle-budget overflow/refusal.

Use complete-layout paired timings, not just get_asset microbenchmarks. Then measure field construction with the actual species resources. Compare MultiMesh buffers, transforms, tint/custom data, AABBs and lifecycle ownership, followed by native 1080p visual checks. The source candidate appears behavior-preserving under its stated ownership assumption, but no parse, engine parity or timing result has been obtained.

# Current companion scorer

## A new valid simplification

The current [pilot scorer](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/ai/companions/pilot.gd#L424-L447) computes an endpoint distance at every forecast sample. For every sample after index zero, interval_distance is immediately overwritten by the synchronized segment closest-approach calculation. The endpoint value is used afterward only when include_trace is true.

Therefore compute that endpoint square root only for sample zero or a requested trace. Retain the entire relative-segment distance calculation, arc/chord error subtraction, clamp, minimum reduction, threat priority, terrain margin and trace output.

With the current 8-second horizon and 0.25-second step, there are 33 samples and 32 intervals. For one threat in an untraced score, the current code performs 33 endpoint square roots and 32 segment square roots. The candidate removes 32 endpoint square roots, their three scalar squares and two additions, while adding a conditional per sample. For valid finite inputs, all used floating-point expressions retain their original order and arguments; the intended error budget is exact equality, not a tolerance-based approximation.

At a nominal 60 planning decisions per simulated second, one threat and one untraced score per decision would omit 1,920 endpoint roots per second. Conflict handling can score the baseline and eleven bank candidates, plus a held candidate in some states. Actual traffic, eligibility and diagnostic traces determine the call count. Root-count reduction is not scorer-time or FPS reduction.

The pinned [GDScript compiler](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/gdscript/gdscript_compiler.cpp#L2214-L2229) emits the runtime initializer, and [math3d.sqrt_](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/math3d.gd#L46-L47) calls sqrt directly. The existing computation is not made unnecessary by constant folding. A runtime counter is still useful when validating the actual binary.

## Why the old pilot patch must be retired

The scorer now uses closest approach along synchronized chords:

```math
\tau_* = \operatorname{clamp}\!\left(-\frac{\mathbf r_0\cdot\Delta\mathbf r}{\Delta\mathbf r\cdot\Delta\mathbf r},0,1\right),
\qquad
d_* = \lVert\mathbf r_0 + \tau_*\Delta\mathbf r\rVert .
```

The zero-motion branch and the existing arc-deviation bounds remain part of the current implementation. Endpoint minimum and interval closest approach are different quantities. A relative trajectory from −10 m to +10 m has endpoints 10 m away but passes through zero separation. With a 5 m requirement, endpoint-only scoring would incorrectly call it clear.

Do not mechanically rebase the earlier endpoint min/sqrt patch or carry its historical speed/parity results onto current main. Reusing a saturated turn rate is a separate prior candidate and needs its own current-source qualification.

## Verification and admission

Compare all score fields and controller decisions exactly with traces off and on. Include interval crossings, perpendicular 2 m offsets, tangency, zero relative motion, ties, threshold neighborhoods, multiple threats and their ordering, terrain-horizon kinks, held-maneuver transitions and input immutability. Add private-scorer NaN/overflow/signed-zero stress to detect changed refusal or diagnostic behavior without treating those inputs as qualified flight states.

The pilot and its profile are source-bound. The patch deliberately does not change the profile hash. Use an isolated differential fixture first; renew the source qualification and encounter/replay evidence through the owning process before changing admission. A blind hash replacement is not validation.

The added branch may offset some saved work. Measure complete held-command scoring and complete companion/session workload in alternating fresh-process pairs, then test the ordinary player-plus-companion scenarios on native hardware.

# Larger opportunities requiring qualification

## Airborne wheel observation

The new [accepted-tick cost observer](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/sim/flight_session.gd#L2625-L2636) invokes gear_compressions even in clear flight. Ordinary surface/track/lake contexts can reach per-wheel terrain work through [Ground.compressions](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/ground_contact.gd#L423-L450) and [GroundWheels.compressions](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/ground_wheels.gd#L216-L233). Three wheels at 240 Hz imply up to 720 wheel-terrain queries per simulated second that a proven clear-air path could avoid.

The statistics adapter already has a [no-touch shortcut](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/statistics/fixed_wing_adapter.gd#L140-L154), but copying it into the new owner is not automatically correct. The new owner retains exact previous compression values for contact lifecycles and transaction rollback. Geometry and terrain can be mutable, and state validation accepts finite nonzero quaternions rather than universally guaranteeing a unit rotation.

A suitable first research domain is the concrete stock session with validated current contact geometry, finite bounded operands and ordinary terrain, excluding uncertain lake/track/retract/custom paths. Compute a conservative height interval using the same current rotation and contact arithmetic as the wheel law. Only skip terrain queries when every contact is provably above the maximum terrain height by a justified floating-point margin. Fall back on equality, uncertainty, nonfinite data, unsupported context or lifecycle transition. Do not choose an arbitrary epsilon without bounding arithmetic error.

The conceptual sufficient condition is:

```math
\min_i h_i > H_{\max} + \varepsilon_{\mathrm{bound}} .
```

Here the height calculation, maximum terrain bound and rounding margin must all apply to the actual admitted state and current geometry. A body-center height and stale nominal reach are insufficient for the full mutable domain.

Preserve ground-to-air ended events and air-to-ground new events. If using a nonpositive marker instead of exact negative compression, explicitly qualify the changed private-state representation and rollback contract. The kernel's last_loads is evaluated at the pre-step state, so it is not an accepted-endpoint receipt; reusing an RK stage would sample the wrong state.

Run differential takeoff, landing, teleport, inversion/non-unit attitude, threshold, lake/track, retraction, restore/reentry and invalid-state cases, then whole accepted-session timing. This is distinct from the existing A24 near-ground statistics reuse opportunity and remains research.

## Full and proxy shadow collection

This is a known continuation, not a new discovery. [The proxy collector](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/aircraft_shadow_proxy.gd#L42-L136) first calls the full collector and then traverses included meshes again. The [pinned Mesh implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/mesh.cpp#L524-L530) obtains a cached TriangleMesh, but [TriangleMesh.get_faces](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/math/triangle_mesh.cpp#L503-L522) still allocates and expands an ordered face array on every call. Those exact beta2 source files were fetched and checked in this pass.

A fused traversal could use each mesh-local face array for both the full transformed stream and its LOD stream before discarding it. Retain the original full ArrayMesh construction and renderer-derived bounds, then the current proxy guard and fallback. The prior Corsair fixture has 321,191 full triangles, so the redundant expansion covers 963,573 positions: 11,562,876 logical bytes with three float32 components, about 11.03 MiB. This is data volume, not a measured peak-memory reduction or time estimate.

Admission is narrow: matching stock Corsair asset/manifest, midnight livery, no custom skin, pinned engine and non-headless Compatibility in eligible ordinary sessions. It is bind/rebind work, including geometry collection when the projector initially starts disabled; it is not a repeated per-frame collector.

Fusion can increase peak live memory by holding accumulated full and proxy CPU arrays together. It can also reorder resource reads and diagnostics before the old full-mesh early exits. Preserve snapping, full-face order, hidden ancestors, transforms, propeller exclusion, degenerate and nonfinite bounds behavior, malformed/unsupported LOD fallback, metadata and failure reasons. Invalid distance thresholds must not trigger proxy decoding.

Require exact full/proxy buffers, bounds and fallback comparisons, complete bind timing and peak RSS/engine/VRAM measurements. Native 1080p mask/activation checks remain a separate gate. The earlier decoder-only experiment was not an end-to-end win and is not being promoted.

## Damage-profile indexing

DamageAssessment.resolve repeatedly scans ordered zones for persistent contact events. Indexing by source and probe could reduce repeated searches, but _damage_profile is conventionally private and mutable; a persistent cache without an immutable owned admission copy could silently become stale.

A lower-risk exploratory alternative is a lazy index scoped to one synchronous multi-event observe batch, preserving first-match ordering and discarding the index before return. It avoids cross-tick invalidation, but building a map every batch may cost more than the small scan. A persistent index requires explicit ownership and rebuild rules for begin, rebind, restore and permitted mutation. Keep public resolve behavior unchanged. Measure the complete incident batch before adding this complexity.

## Prior Timber change

The Timber visual-details, custom-skin and Timber LOD-test files are unchanged between the prior target and this revision, so the previous Vector3i-key source hunks remain portable. That does not make the old multi-file patch safe to apply wholesale: its pilot/profile hunks are stale, and two UID additions now already exist upstream.

Requalify the isolated Timber change with current input identity, cache admission, asset bytes and existing visual-LOD tests. Its earlier component result concerns cold visual repair; a cache hit can bypass that work. Do not present it as an in-flight FPS gain.

# Measurement and acceptance protocol

## What was and was not measured

| Evidence | Status in this continuation |
| --- | --- |
| Repository, branch, source SHA and open PR state | Verified through GitHub and scoped source inspection |
| Existing audit and completed-work classification | Cross-checked |
| Three candidate transformations | Constructed against exact fetched source; single-anchor and text-replay checks passed |
| Contact constant membership | Exact 9 plus 16 key-set equality checked |
| GDScript parse or unit/integration execution | Not performed successfully |
| Component CPU timing | No new valid measurement |
| Native CPU/GPU frame time, FPS and percentiles | No new measurement |
| Visual parity, input-to-display latency | Unverified |
| Production improvement merged or published | None |

The available execution environment was Linux x86_64 with nine CPUs in its affinity set and no available /dev/dri device or display session. Physical CPU/RAM and target GPU characteristics were not established for a valid benchmark. The attempted pinned engine installation failed; its retained executable did not match the required hash and could not provide the pinned version. It is inadmissible for comparisons. Subsequent command-service failures also prevented creating and running fixtures. These are environment failures, not a diagnosis of the game.

The earlier GPU/CPU author observations and the prior audit's component benchmarks are historical context only. No current average FPS, p95, p99 or saved milliseconds has been inferred from them.

## Establish comparable scenarios

Use one clean current baseline and separate candidate snapshots, keeping exact code/data/asset/engine hashes. Test one change at a time before an aggregate candidate. Start at native 1920×1080, then 2560×1440 and any additional shipping targets; use 720p only as a fallback or a deliberate resolution-scaling diagnostic.

Record CPU/GPU models, RAM, OS, driver, power mode, display refresh, official engine version, editor versus exported build, actual renderer, resolution/scaling, MSAA, quality, VSync/FPS cap, native-kernel admission, input device and simulation configuration. Record aircraft, field, weather/time seed, camera, companions, meadow, shadows, logger and overlays. Test debug and release exports separately rather than transferring editor timings.

Use these matched scenarios:

1. Stik idle and taxi with three supported wheels, then the same route after a reproducible nonterminal damage event. Separate contact processing from archive publication.

2. Clear airborne solo flight over the same field, then takeoff/landing and a terrain-near maneuver. This targets the proposed observation bound and transitions.

3. Companion traffic at explicit counts and seeds: clear baseline, crossing conflict and held maneuver, with diagnostic traces separately enabled.

4. Default-field construction at low/balanced/high meadow settings, warm and cold paths recorded separately.

5. Eligible Corsair bind/rebind and cold Timber visual repair, plus their cache-hit paths.

6. A representative normal flight with default presentation, followed by a separate developer-overlay/logger run to attribute observation overhead.

For steady-state tests, warm up for at least 30 seconds and capture at least 120 seconds per run. Use at least five alternating baseline/candidate pairs on an otherwise quiet machine; extend only when noise or a remaining gate requires it. A baseline-again control helps detect drift. For loading tests, repeat complete operations in fresh processes with documented warm/cold resource-cache state; import time and runtime loading are different measurements.

## Instrument the correct boundaries

The displayed simulation step_usec is a 0.05 exponential moving average of part of the kernel step. It ends before later bookkeeping and observers, and excludes earlier session/fleet work. A low HUD value therefore cannot exonerate contact-cost or companion processing.

Measure separately: total accepted-session CPU, kernel evaluation/integration, fleet planning, contact/incident observers, report materialization, archive encode/write/rename, total process work and render submission/GPU work. Correlate frame intervals with accepted tick counts and publication generations.

Godot's pinned [RenderingServer documentation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/RenderingServer.xml#L4164-L4178) says viewport CPU rendering time excludes scripts and other subsystems. Enable viewport timing explicitly, account for frame setup and all drawn viewports, and verify that the renderer supports meaningful values. Headless results are not GPU results. Process-loop intervals are not presentation timestamps.

Existing frame telemetry can itself serialize, hash and flush every 512 sampled frames in streaming mode. Keep that mode identical in comparisons and measure its observer effect; use bounded-memory capture and post-run serialization where the existing workflow supports it. This is a documented instrumentation limitation, not a newly established game defect.

For each run report total-frame mean, p50, p95, p99, maximum, frames exceeding 16.67/33.33/50 ms, CPU/GPU distributions, physics steps per render, simulated-time/wall-time ratio and memory peaks. Compute average FPS as total frames divided by total elapsed time. Do not average instantaneous FPS values or substitute a 1 Hz FPS display for the frame-time distribution.

With 240 Hz and a maximum of 12 steps per frame, real-time catch-up requires at least 20 rendered frames per second in sustained conditions. At 15 FPS the cap admits at most 180 steps per wall second, or 75 percent of the configured simulation rate. Raising the cap does not remove the bottleneck and can amplify catch-up load. Preserve the fixed timestep and current interpolation contract during optimization.

Input latency requires timestamps from input receipt through accepted command tick and rendered/presented response, or a target-device optical/high-speed-camera test. main already disables accumulated input; proposing that setting again would repeat implemented work. Lower CPU cost can reduce latency only if it advances the actual critical path.

## Interpret the result

Amdahl's law relates local speedup to whole-frame benefit:

```math
S_{\mathrm{total}} = \frac{1}{(1-f)+f/s}.
```

Here f must be the measured fraction of the relevant serialized critical path and s the measured component speedup. For illustration only, doubling a component that accounts for 5 percent of that path improves the whole path by about 2.56 percent. CPU/GPU overlap, VSync, I/O stalls and frame-tail events require separate treatment; FPS cannot be projected from operation counts alone.

Promote a patch only when its required exact/parity/refusal checks pass, the source-bound admission is current, the complete relevant workload improves beyond run-to-run variability, and the target frame-time tails and lifecycle behavior do not regress. Full required CI remains a separate final gate.

# Candidate patches awaiting Godot checks

These diffs were constructed from the exact GitHub file contents at the reviewed commit. Textual hunk replay reproduced each candidate, and the contact-key map passed a structural set-equality check. They have not been parsed, executed, benchmarked or applied to production. The pilot diff intentionally leaves its admission/profile pin untouched and must first run in a differential fixture.

| File | Baseline Git blob SHA |
| --- | --- |
| app/scenery/runway_meadow.gd | 3fbf1e2a691746c6f9bc00bae23e12c7596248b6 |
| app/sim/aircraft_contact_events.gd | 5c64279aa7e6a387bb3442adb74567dca50c32c5 |
| app/ai/companions/pilot.gd | ab2ac53a6dbc8714f3ffabef029be845c5fab41f |

## Meadow scalar reuse

```diff
diff --git a/app/scenery/runway_meadow.gd b/app/scenery/runway_meadow.gd
--- a/app/scenery/runway_meadow.gd
+++ b/app/scenery/runway_meadow.gd
@@ -107,12 +107,17 @@
 	var keep_root := sqrt(keep_fraction)
 	var surface_rects := _surface_rects(field)
 	var triangles := 0
+	var triangle_counts := {}
 	for plant: Dictionary in candidates:
 		if float(plant.group_u) >= keep_root or float(plant.member_u) >= keep_root:
 			continue
 		var asset_id := str(plant.asset_id)
-		var source_triangles := int(PlantLibrary.get_asset(asset_id).get("source_triangles", 0))
+		var source_triangles := int(triangle_counts.get(asset_id, 0))
 		if source_triangles <= 0:
+			source_triangles = int(PlantLibrary.get_asset(asset_id).get("source_triangles", 0))
+			if source_triangles > 0:
+				triangle_counts[asset_id] = source_triangles
+		if source_triangles <= 0:
 			continue
 		if triangles + source_triangles > MAX_SOURCE_TRIANGLES:
 			push_error("Runway meadow exceeds its %d source-triangle budget" % MAX_SOURCE_TRIANGLES)
```

## Contact-key constant

```diff
diff --git a/app/sim/aircraft_contact_events.gd b/app/sim/aircraft_contact_events.gd
--- a/app/sim/aircraft_contact_events.gd
+++ b/app/sim/aircraft_contact_events.gd
@@ -30,6 +30,15 @@
 	"crossing_fraction", "time_fraction", "probe_source", "probe_id", "lake_id",
 	"material", "obstacle_kind", "obstacle_part", "response_class", "response_status", "rule",
 ]
+# Keep this set exactly equal to _COMMON_KEYS + _OPTIONAL_KEYS.
+const _KNOWN_EVENT_KEYS := {
+	"format": true, "event_type": true, "event_id": true, "tick": true,
+	"source": true, "contact_id": true, "lifecycle": true, "policy": true, "response": true,
+	"point_index": true, "measure": true, "point_ned": true, "normal_ned": true, "velocity_ned": true,
+	"crossing_fraction": true, "time_fraction": true, "probe_source": true, "probe_id": true, "lake_id": true,
+	"material": true, "obstacle_kind": true, "obstacle_part": true, "response_class": true,
+	"response_status": true, "rule": true,
+}
 
 
 ## Normalizes the source feed and emits one flat event for each active or ended hull contact.
@@ -413,11 +422,8 @@
 
 
 static func _event_keys_are_known(event: Dictionary) -> bool:
-	var allowed: Dictionary = {}
-	for key: String in _COMMON_KEYS + _OPTIONAL_KEYS:
-		allowed[key] = true
 	for key: Variant in event.keys():
-		if typeof(key) != TYPE_STRING or not allowed.has(str(key)):
+		if typeof(key) != TYPE_STRING or not _KNOWN_EVENT_KEYS.has(str(key)):
 			return false
 	return true
```

Keep the existing keys() iteration for this first variant. The key-set invariant must compare both directions against _COMMON_KEYS + _OPTIONAL_KEYS; an equal entry count alone cannot detect a substituted or misspelled key.

## Discarded companion endpoint distance

```diff
diff --git a/app/ai/companions/pilot.gd b/app/ai/companions/pilot.gd
--- a/app/ai/companions/pilot.gd
+++ b/app/ai/companions/pilot.gd
@@ -427,8 +427,10 @@
 			var north_delta: float = positions[offset] - own_north
 			var east_delta: float = positions[offset + 1] - own_east
 			var down_delta: float = positions[offset + 2] - own_down
-			var distance: float = AvoidanceMath.sqrt_(north_delta * north_delta
-				+ east_delta * east_delta + down_delta * down_delta)
+			var distance := 0.0
+			if include_trace or sample_index == 0:
+				distance = AvoidanceMath.sqrt_(north_delta * north_delta
+					+ east_delta * east_delta + down_delta * down_delta)
 			var interval_distance: float = distance
 			if sample_index > 0:
 				interval_distance = _relative_segment_distance(
```

The placeholder 0.0 is overwritten by the existing segment calculation for every later untraced sample. It is never a substitute for a used segment distance. Keep the exact sample-zero and traced arithmetic and all current CPA code.

# Senior developer execution order

1. Restore a valid pinned engine and clear the five current UID/preflight failures using the repository workflow. Verify executable identity; do not change expected hashes to accept an invalid binary.

2. Establish the current native 1080p baseline with normal input and the actual runtime renderer. Add narrow timing around the new ledger boundaries before changing archive policy.

3. Qualify contact-key reuse and meadow scalar reuse in separate candidates. Keep their complete-workload timing separate from helper counters.

4. Rebuild the current pilot differential/encounter fixture and compare exact decisions before renewing the profile qualification. Split it from the prior bundle and from the saturated-turn-rate experiment.

5. Requalify the isolated Timber change. Investigate the airborne bound, damage publication worker and shadow fusion only with the ownership, lifecycle and memory conditions described above.

6. Run the affected integration and replay gates and required CI on the stable final source. Capture paired native target results before making an FPS, stutter or latency improvement claim.

A representative checked-command pattern, after the owning workflow has imported the intended source snapshot:

```bash
task_godot="$(app/get-godot.sh)"
python3 tools/godot/run_checked.py --label contact-parse --timeout 90 -- \
  "$task_godot" --headless --path app --audio-driver Dummy \
  --check-only --script res://sim/aircraft_contact_events.gd

python3 tools/godot/run_checked.py --label contact-events --timeout 90 -- \
  "$task_godot" --headless --path app --audio-driver Dummy \
  --script res://tests/test_aircraft_contact_events.gd

python3 tools/godot/run_checked.py --label runway-meadow --timeout 90 -- \
  "$task_godot" --headless --path app --audio-driver Dummy \
  --script res://tests/test_runway_meadow.gd
```

Also run the relevant existing test_crash_cost_producers, test_crash_cost_incident, test_crash_cost_round2, test_economy_checkpoint and test_accident_integration scripts for the contact candidate. The accident integration scope uses a 180-second timeout. Meadow needs imported-vegetation, exclusion/mask and affected field checks. Companion and shadow changes require their source-bound encounter, collector/fallback and native gates.

Inspect each checked runner report and engine log, including diagnostics and completion markers; exit status alone is insufficient. The [shared verification guide](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/docs/tools/shared.md#L17-L39) and [checked runner contract](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/tools/godot/README.md#L1-L28) define the required workflow. Focused passes do not establish complete CI, target GPU or physical-controller qualification.

**Delivery status:** this report contains new source findings, three concrete unqualified patches, independent challenge results and a reproducible validation plan. No fresh runtime improvement is being claimed. The next evidence that should change the ranking is complete observer/frame attribution and matched component timings on a valid current build.
