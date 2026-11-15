# CPU and frame-time audit integration

## Current reconciliation (2026-11-15)

**Reviewed main:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`, committed
2026-11-15 at 11:42:39 UTC. It is 151 commits ahead of the Round 3 snapshot
`45d86d250f6e38a3d9b60d30c01bdc2396571efe`.
This is a documentation and evidence intake: current source and retained evidence
were checked, but no new simulator benchmark, FPS improvement or runtime
qualification was produced by this integration.

This report remains the authoritative reconciliation for these three performance
audit rounds. The [original reports and patches](../../external%20Audits/performance-audit-sources-2026-11-09/README.md)
are now available in the repository. The [evidence intake](performance-audit-intake-2026-11-15/README.md)
records archive provenance, exact exclusions, two private attachment URL redactions
in one historical ledger snapshot, and verification. A separate
[link-edit manifest](performance-audit-intake-2026-11-15/public-link-redactions.json)
records publication-required personal-link handling in 25 older audit records:
three links now reach repository copies and 51 are explicit omissions. Findings,
measurements and ordinary citation URLs remain unchanged by those link edits.
The earlier statements below that attachments were unavailable describe the
November 9 intake; they no longer describe availability. Original source documents
and their dated claims remain unchanged. **A33 includes these continuations;
A34 remains the separate five-finding audit.**

### Current repository and platform state

- The pinned getter selects **Godot 4.8.beta2.official.cafc17a19**. Project physics
  is **240 Hz**, a 4.167 ms tick period. The default renderer is Compatibility;
  the ARM64 feature override selects Mobile for Apple Silicon. Record the actual
  runtime renderer and overrides in every comparison.
  [Getter](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/get-godot.sh#L4-L5),
  [project settings](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/project.godot#L48-L66).
- Native simulation admission now includes Linux x86-64, receipt-gated Windows
  x86-64 source/debug installations, and restricted macOS ARM64 routes. Windows
  release packages still select the reference path. A supported source path does
  not prove that a particular binary, package or scenario has been admitted.
  CR-22e's older Linux-only description is historical.
  [Current admission](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/native_stage.gd#L409-L457),
  [Windows qualification scope](native-kernel/NK-4/README.md).
- Open draft PRs at inspection were
  [#12](https://github.com/bultodepapas/OpenRCsimulator/pull/12) (Temporal camera-cut ordering and M1 execution qualification),
  [#11](https://github.com/bultodepapas/OpenRCsimulator/pull/11) (bounded circuit cache and parked ORM reads),
  and [#10](https://github.com/bultodepapas/OpenRCsimulator/pull/10) (tool report/debug contracts).
  PR #12 head `bffe0ed522efc4e0ab7336ef60d401c4cf4d712d` is 26 commits ahead
  of main, with main as its merge base. It remains a draft and is not merged.
  Conversely, an open PR does not prove all its ideas remain absent: circuit/ORM
  improvements are already recorded in the completed ledger.
- At the recorded inspection, [MetalFX source controls](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453317)
  passed, [Windows test queue regressions](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453322)
  failed, and [main CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445)
  completed with failure. The Windows run reported 164 tests, two failures and three
  skips. Both failing assertions compare a short `RUNNER~1` path with its expanded
  `runneradmin` form in `tools/testqueue/test_pool_mcp.py`; this is evidence of
  mismatched path expectations, not proof of a simulator or runtime queue failure.
  The current preflight passed and all five UID sidecars identified by Round 3
  exist. Do not repeat that historical UID blocker as a current failure.
  Main CI also reports one failed controls-setup assertion about the Save/Discard/Keep editing
  choices in [units 0](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801393947),
  and stale D11g provenance for `Cmq.source`, `CLq.source` and `Cnr.source` in
  [integration 0](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801393957).
  [Units 2](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801394013)
  and [units 5](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801393986)
  additionally failed to load their source-bound shaft and weather fixtures; each
  log reports a fixture-manifest or source-identity mismatch without distinguishing
  which one. The downstream CI required gate also failed. Final main CI totals are
  **17 successful, 5 failed and 4 skipped jobs**, with no cancelled or timed-out jobs.
  The five failures include that aggregate gate, so there are four failing test jobs.
  Their underlying causes and any player-visible or physical consequences were not
  established by this intake. Linux NK-3 and Windows NK-4 qualification jobs passed,
  as did Mac ARM64 experimental fixed-wing source correctness; the latter does not
  establish M1 execution or general performance/distribution qualification. RC
  native production checks passed on Linux and Windows. The successful release
  cross-export is not native package execution, and the GitHub release job was skipped.
  Exact observation time, source blobs, PR heads and run URLs are in
  [repository-state.json](performance-audit-intake-2026-11-15/repository-state.json).

### Findings reconciled against current source

| Finding | Current classification | Evidence and remaining boundary |
| --- | --- | --- |
| Controller binding index and engine-voice interpolation | **Implemented** | Original A33 changes are retained; the November 9 Windows component measurements below remain source- and workload-specific. They are not new measurements of this revision. |
| Timber paint-grid integer keys | **Implemented** | Current `timber_visual_details.gd` uses integer keys; the existing follow-up retains exact geometry comparisons and 20.0–20.7% lower cold-repair component medians. Warm repair and displayed-frame gains were not established. |
| Companion endpoint roots and saturated turn-rate reuse | **Implemented in the current interval-CPA scorer** | Untraced scoring uses 33 roots instead of 65 per threat/bank: one initial endpoint and 32 CPA roots. The old endpoint-minimum patch is obsolete. Trace calculations, admission identities and encounter limitations remain as recorded below. Companions are optional, so this does not automatically benefit ordinary solo flight. |
| Packed u16 shadow-index reads | **Implemented** | [VQ-04a](visual-quality-implementation/VQ-04a/collection-decoder-20261109/README.md) retains 2.1–2.3% lower pooled collector medians and 126 identical PNGs from the native 1080p trial, including 256² masks and 1080p receivers. The temporary buffer is a memory cost; this is not a VRAM reduction or FPS result. |
| Full/proxy traversal fusion and native gather | **Research; earlier variants rejected** | The full/proxy collector still has separate passes. The subsequent VQ-04a single-pass trial ranged from 4.2% slower to 4.3% faster, while the native gather changed bytes and was 36–40% slower. Any new fusion design must differ materially and re-prove geometry, fallback and memory behavior. |
| Crash valuation and archive writes | **Original synchronous-work proposal substantially superseded** | Normal-flight Main enables background valuation and archival. [CR-22e](crash-damage-investigations/CR-22e/README.md) retains rendered Windows improvement evidence and unresolved first-crash spikes. Snapshot copying, explicit retry and lifecycle waits still require their existing contracts. |
| Contact-event allowed-key map | **Still open; unqualified candidate** | [`_event_keys_are_known`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/aircraft_contact_events.gd#L415-L422) constructs the 25-key map for each validation. Hoist only the immutable membership map; retain the event key loop, `TYPE_STRING` check, `str(key)` conversion and both validation boundaries. |
| Meadow asset triangle counts | **Still open; loading/layout candidate** | [`layout`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/scenery/runway_meadow.gd#L93-L119) still requests metadata per retained plant. A per-layout positive-count cache can reduce successful positive-count metadata copies from O(P) to O(U), U at most eight current asset IDs; misses remain uncached. Preserve missing/invalid asset diagnostics and deterministic order. |
| Airborne gear/contact observer | **Still open; numerical and lifecycle research** | Eligible accepted ticks still call `gear_compressions(sim.state)`. Normal unscripted flight can enable accident reports by default even though a bare session defaults off. Prove a conservative bound or same-state reuse before skipping work; altitude alone or an RK last-load snapshot is insufficient. |
| Incident evidence refresh | **Narrower residual opportunity** | [`_refresh_report_evidence`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/economy/incident.gd#L1028-L1046) deep-copies summaries and journal when pending evidence refreshes an existing report. It does not run unconditionally every frame. Dirty/serial tracking, detached worker snapshots and retry semantics constrain reuse. |
| Stage-owned temporal wind remainder | **Historical research candidate, outside production** | Point queries still perform the temporal remainder inside the mode loop. Rebase and qualify the retained patch before use; its historical applicability and preliminary timing do not prove applicability or a gain at this SHA. Preserve ordered reductions, source admission, fleet and replay gates. |
| Circuit cache and ORM reuse | **Known implemented work** | Keep the bounded-residency and supported-resource contracts in the completed ledger. PR #11's draft state is not an instruction to reapply the old patch. |

Current source anchors supplement the detailed historical reports:
[Timber keys](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/aircraft/timber_visual_details.gd#L404-L425),
[companion scorer](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/ai/companions/pilot.gd#L398-L458),
[observer](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/flight_session.gd#L2720-L2737),
[normal-flight enablement](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/main.gd#L1290-L1305),
[archive worker boundary](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/economy/incident.gd#L1385-L1411),
[wind mode loop](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/wind_spatial_field.gd#L330-L334).
This intake did not run or bisect game-performance regressions. Current CI
failures are recorded above with their specific observed scope.

### Senior-developer action order

1. **Capture a controlled rendered baseline before claiming more FPS.** Use a
   recorded input tape on the same aircraft, scenery, seed, 240 Hz simulation,
   resolution, graphics settings, engine and admitted backend. Include ordinary
   solo flight, a windy flight, ground roll/contact, first and repeated crash,
   Timber cold load and an explicitly enabled companion scenario. Measure CPU
   and GPU frame time, physics/accepted-tick and observer cost, loading milestones,
   p50/p95/p99 frame time and spikes over the chosen frame budget. Alternate
   baseline/candidate runs; separate cold and warm runs and retain contention
   markers. Physical input latency needs a separate input-to-display measurement.
2. **Qualify the bounded contact-key change if profiling shows material cost.**
   With three active wheel events per tick at 240 Hz and two validations per event,
   the conditional workload is 1,440 map constructions and 36,000 key insertions
   per second. Airborne/no-event cases do not incur that count. A read-only static
   map removes those constructions without changing O(K) event-key validation.
   Test every allowed key, unknown keys, StringName/non-string rejection, empty
   events and both producer/consumer boundaries. Operations saved are not
   milliseconds or FPS saved.
3. **Qualify the meadow cache as loading work.** The historical 4,492-plant layout
   and roughly 130 ms whole-layout screen do not measure the proposed saving.
   Cache only successful positive triangle counts within one layout call, making
   lifetime/invalidation local. Compare exact ordered output for all qualities,
   changed library contents on a new call, missing assets and budget boundaries.
4. **Profile the residual crash/contact costs before broader changes.**
   CR-22e already moved valuation/serialization work off the normal frame path.
   Its retained Windows evidence reports Ugly Stik impact `_process` falling
   from 38–65 ms to 8.3–8.9 ms, and P-51 scenery impact from 158–171 ms to
   8.9–10.7 ms under the documented scenarios. Fresh first-crash and physics-tail
   anomalies remain unexplained; those historical runs do not establish current
   whole-game stability. For observer changes cover composed terrain/lake/track,
   accepted non-unit quaternions, live/retracting gear geometry, contact transitions,
   histories, rollback and restore. For evidence refresh preserve revision/serial
   publication, terminal writes, sticky failures and explicit retry. The 60-tick
   archive throttle only applies to eligible evidence-only, nonterminal,
   non-forced updates after an earlier archive; it is not a global write-rate cap.
5. **Treat wind and further mesh collection as separate experiments.**
   Attribute their share of total cost and prove the appropriate native/reference
   and visual identities. If an optimization speeds a component by factor s and
   that component occupies fraction f of frame time, the ideal serial speedup is
   1 / ((1 - f) + f / s). Synchronization, overlapping CPU/GPU work and changed
   bottlenecks can reduce that benefit. Do not add historical component percentages
   together or multiply them into an FPS claim.

The existing [performance probe contract](../../research/performance/README.md)
owns reproduction. The [native workflow](../../research/native-kernel/README.md)
owns admission and qualification. This branch preserves candidates for review;
it changes no `app/` runtime, shader, project or engine settings.

## Original November 9 intake record

The following is the historical intake and implementation record. Its
measurements, source identities, availability notes and uncompleted gates retain
their original date and scope.

Reconciled the [supplied report](../../external%20Audits/cpu-mathematical-optimization-2026-11-09.md)
against `ca529cb88476a22fbb1c8edf957d6917ab9b6042`. The linked external HTML,
patch and ZIP were not available locally; the implementations were checked against
current source and reconstructed with permanent regression checks. Intake SHA-256:
`242f50409140c802214bf88a927345d2da82ddc9e18ace453082f8745cbc086a`.

## Retained production changes

- **D6-GP controller resolution:** lazily index valid occupied flight/both-context
  buttons once per resolution. Preserve declaration order, explicit Clear/remap,
  AUX ownership, unknown bindings, contexts and detached result ownership. No
  cross-event cache or profile invalidation protocol is introduced.
- **G3b engine voice:** inline the identical interpolation expression within the
  finite, normalized oscillator domain. Keep the original helper loop for unusual
  initial state or a short table, including its existing diagnostic behavior.
  Smoothing, phase update, PCM allocation and simulation remain unchanged.
- **PT1-CI / G3a fixtures:** add both Stik 6S generators to the expected ordered
  roster and the electric Stik's explicit two-blade audio expectation. Exact roster
  coverage and fail-stop checks remain intact.

The controller regression compares the original scan across **1,344** cases spanning
all 32 capability combinations, overrides and AUX conflicts; the complete extended
suite passes **1,451** checks. Controller actions, binding audit (14), profiles (74),
conditioning (57) and integration (27) pass. Voice (78), engine-sound (28) and
engine-audio integration (147) pass, including exact PCM/state comparisons and
simulation/checkpoint isolation. The WSL CI phase suite passes all **11** tests,
including every ordered generator failure boundary.

## Windows component measurements

Godot `4.8.beta2.official.cafc17a19`, native Windows x86-64, headless/Dummy.
Seven alternating baseline/candidate pairs, 500 warmup resolver calls per variant,
2,000 complete resolver calls per timed batch. The baseline is the original source
at `ca529cb88`; current-source hashes and raw batches are retained in the
[compact evidence](performance-report-2026-11-09.json).

| Component | Baseline median | Candidate median | Reduction |
| --- | ---: | ---: | ---: |
| Full airplane automatic bindings | 356.954 µs/call | 119.171 µs/call | 66.6% |
| Rates/restart automatic bindings | 167.003 µs/call | 113.376 µs/call | 32.1% |
| Fully explicit bindings | 87.956 µs/call | 88.398 µs/call | No useful gain; median 0.5% higher |
| Radio bindings | 57.959 µs/call | 59.319 µs/call | No useful gain; median 2.3% higher |
| Voice, per generated audio second | 5.447 ms | 2.989 ms | 45.1% |

Audio batches render 512 blocks of 512 stereo frames at 22,050 Hz after preparation
and 100 warmup blocks per variant. Each pair starts both oscillators in the same
state and checks exact final state. This saves about **2.46 ms per generated audio
second per voice** in this fixture. Shared development-host measurements are
component screens, without a controlled thermal/power campaign. They do not
establish whole-game FPS, GPU cost, physical-input latency or listening quality.
An initial screen showed the same direction: 65.4%, 32.3% and 43.9% reductions
for the two automatic-binding fixtures and voice. The reusable
[probe and reproduction contract](../../research/performance/README.md)
retain the same workloads with explicit baseline/output paths and source hashes.

HEAD advanced concurrently to `a188a1d1b` during the final checks and incorporated
the six production/test/CI edits plus the retained wind patch. The two optimized
runtime source hashes remained unchanged; the compact evidence records both
revisions. No commit or publication was performed by this task.

## Wind candidate retained outside production

The [apply-ready candidate](../../research/wind/temporal_phase_candidate.patch)
implements one temporal-remainder array per immutable stage query, preserving
point-dependent phase reductions, trigonometry and ordered sums. It includes
**1,463** permanent checks: historical Windows fixture bytes, 8/24/64 modes,
real signed-zero construction, invalid queries/refusals, live noise callbacks,
provider/configuration replacement, subclass/factory overrides, retained sampler
rebinds and actual FlightSession activation. Fourteen existing affected wind and
environment suites also passed during development, including powered fleet,
checkpoint continuation, midpoint rollback, wash and tailless replay checks.

One preliminary stock-Stik 24-mode full-session pair measured **4.256 → 3.925 ms/tick**
median batch cost. All three baseline/candidate final-state hashes matched, as did
the untimed counting replay; both completed nine restore checks. Batch means vary
substantially, so this is a screening result, not an accepted speedup or tick-tail
latency claim. The final guard/test refinements were not separately timed.

**The wind candidate is not enabled.** All four changed reference files participate
in the NK-3 mirrored-source identity. Applying it invalidates the previously
qualified native receipt across the fleet, including calm weather. A source
installation would fall back to GDScript and packaged admission would fail until
fresh native qualification. The four production files were restored byte-for-byte,
and each again matches its original installed receipt hash. No receipt was edited.

Before promotion, follow the [native qualification/install workflow](../../research/native-kernel/README.md#verification-and-local-installation)
on an isolated pinned Linux snapshot, compare exact baseline/candidate input-tape
trajectories and run controlled paired session measurements. Keep source identities
with every oracle/fleet/replay result. Do not reuse the existing binary's old evidence.

Offscreen afterimage culling, F10 hashing and indexed
shadow preparation retain the report's separate visual, numerical, lifecycle and
target-hardware gates. Existing concurrent shadow/tractor changes were preserved.
Full required CI, exports and physical device/audio qualification remain separate;
the focused checks here do not establish them.

Raw local runs remain under `tmp/perf-report-input-audio-20261109`,
`tmp/perf-report-components-20261109`, `tmp/perf-report-wind-20261109` and
`tmp/perf-report-final-20261109`. Early test-fixture/CLI mistakes and the native-Windows
shell-fixture attempt are retained as failed/inconclusive runs, not passes.

## A33 follow-up: Timber grid and current companion scorer

Integrated the second supplied report against clean baseline
`7e8ce3a4d0ea88943979ff0403fbb3cfeb3c3fe9`. Its external patch/archive were not
attached. Intake SHA-256:
`1c29eb499445efe92fc9239190a403962448ce1b392a9a10df7d2f70adc79988`.
The [compact evidence](performance-followup-2026-11-09.json) retains both timing
screens, exact source/engine and Timber source/import identities, checked-run
receipts and encounter comparisons. The reusable
[probe contract](../../research/performance/README.md) owns reproduction.

- **TT-21:** use the existing `Vector3i` cell coordinates as paint-index keys.
  Builder and lookup change together; geometry, tolerances, bucket/material order
  and empty/missing-bucket behavior remain unchanged. Actual cold/warm repaired
  arrays, serialized LOD records, formats, names and transforms match the baseline.
  Source meshes remain unchanged. Renew only the exact current paint identity;
  the distributed kit's legacy identity stays unchanged.
- **AFC-04:** the current AFC-04-R9 scorer already uses interval closest approach
  and arc-error bounds, so the older report's endpoint-minimum rewrite is obsolete.
  Skip unused endpoint roots after sample zero when tracing is off, preserving
  every interval calculation and traced endpoint. This reduces 65 roots to 33 per
  threat/bank, rather than the older scorer's 33-to-one claim. Reuse the first
  original saturated `lerpf`/turn-rate result locally; do not substitute the target
  bank at that transition. Renew the pilot raw hash, normalized behavior-source
  hash and profile's manifest hash. Solver, engine, circuit and aircraft pins stay
  unchanged.
- **PT1-CI:** both UID omissions named in the report were already fixed. Generate
  the missing `test_companions_behavior_manifest.gd.uid` and the new paint-grid
  test's UID with the pinned editor. The exact tracked-sidecar gate passes with
  these candidate additions in a temporary Git index; the real index is unchanged.

Native Windows 11 Pro, Ryzen 9 5900X, official Godot
`4.8.beta2.official.cafc17a19`, editor binary, headless/Dummy. Each screen uses five
alternating ABBA/BAAB groups, ten adjacent pairs per workload. Cold repair clears
the repair cache in an already-imported warm process; instantiation and comparison
are outside timing. Command batches follow 300 warmup/parity calls. Source
identities remain unchanged across both screens.

| Component | First baseline → candidate | Repeat baseline → candidate | Observed reduction |
| --- | ---: | ---: | ---: |
| Complete cold Timber repair | 408.928 → 327.025 ms | 391.243 → 310.242 ms | 20.0–20.7%; all 20 pairs faster |
| Command, one nearby threat | 987.711 → 926.315 µs | 991.025 → 934.695 µs | 5.7–6.2%; 18/20 pairs faster |
| Command, three nearby threats | 1875.776 → 1688.287 µs | 3494.746 → 2906.585 µs | 10.0–16.8%; 19/20 pairs faster |

These are shared-host component screens. Absolute command costs vary substantially
between screens; power, thermal state and competing work were not controlled.
Warm repair moved in opposite directions (−3.4% and +1.8% savings), so no warm-path
benefit is claimed. No displayed FPS, GPU cost, frame percentiles, 1080p readiness,
physical input latency or peak-memory improvement is established.

The retained probe passes **1,626 checks**, including 600 exact score/trace cases,
600 command/latch comparisons and actual imported-mesh cold/warm comparisons.
The final **14 affected suites pass 1,222 checks**: prediction (350), paint grid
(157), LOD/paint identity (58), profiles (52), behavior manifest (39), pilot (24),
clearance (20), terrain/traffic (60), manager (53), encounters (191), session (65),
session failures (24), traffic lifecycle (40) and actual Timber stock/custom skins
and material lifetime (89). The expanded prediction and grid tests also pass
against the baseline sources. Analytic ramp references cover samples 7, 8, 9 and
32 in both directions. Import and checked execution report no engine errors.

Seven 12-second real-session encounters plus the repeat have identical result
objects, state/control digests and trajectory CSV bytes (SHA-256
`bda3a6c8190a8869c9222ba8d52ef9912c6c717b6c6c204b38fa3ed44e65ad9b`).
The deliberately conflicting parallel two-threat fixture still misses separation
in both versions; this remains a survey, not expanded operating qualification.
Baseline Timber text matches the commit after CRLF normalization; its measured
raw hash and the Git blob hash are retained separately. Raw local runs are in
`tmp/perf-followup-20261109`. Required full CI, exports and native 1080p/sustained
qualification remain pending. No commit, push or publication was performed.

The subsequent [VQ-04a packed-index follow-up](visual-quality-implementation/VQ-04a/collection-decoder-20261109/README.md)
retains a modest native shadow-collection improvement, exact 1080p image parity
and the rejected traversal/gather experiments. Geometry collection remains
synchronous; complete-flight and first-interactive-frame qualification stay open.
