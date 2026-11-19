# Photographic-site qualification protocol

2026-11-19. Proposed implementation checks, not executed runtime results.
This refines E1–E5 in the [original validation study](../2026-11-18/validation-and-budgets.md);
its memory arithmetic, platform boundaries and Gate P ownership remain applicable.
[Contracts](implementation-contracts.md) define the design.
[The plan](../../../plans/photorealistic-flying-sites.md) is the only status ledger.

The [hybrid comparison plan](hybrid-experiments.md) adds HX01–HX06 fixtures for
existing real trees, clean replacements, local ground, shadows/reflections and
moving-view limits. Its table maps them to these Q groups and existing steps;
it does not add another status ledger or waive a Q gate. Fixed-eye hybrids can
be compared during SC-PHOTO-02; moving-camera admission remains separate.

## Admission sheet before an experiment

Record source commit, clean/dirty state, Godot version and binary hash, import
configuration, exact site/field/inventory/presentation identities, renderer/API,
simulation backend, OS/GPU/driver and output/drawable/internal 3D pixels.
Record physical aircraft/configuration, input source, wind/time, camera/FOV law,
reconstruction, V-sync, shadow/detail settings and requested/effective policies.

Name the evidence class: **analytical**, **source inspection**, **headless
numerical**, **rendered fixture**, **live hardware**, **export package** or
**pilot review**. A result cannot silently change class. Every case records
pass/fail/inconclusive, the exact scoped claim and unresolved limitations.
“Inconclusive” does not close an acceptance gate.

Before a real capture is accepted, set the per-host process/peak memory cap,
qualified landing/occlusion region and critical landmark limits. The proposed
numeric thresholds below are starting decisions, not measurements. Any revision
must precede the acceptance run and retain its reason; do not relax a limit
retroactively to turn a failed result green.

## Q01 — analytical transform and synthetic renderer

**Owner/steps:** rendering/CAM, SC-PHOTO-02. **Findings:** R07, part of R03.

Use the C01 cardinal directions, a translated station and a nontrivial
three-axis rotation. Include a large triangle crossing the panorama seam,
near-pole views, a ground plane and two opaque boxes at independent known
ranges. Validate serialization, matrix direction, image-row convention and
NED-to-render conversion. Retain a small input manifest and expected projections.

Exercise exact east/west and exact polar directions in the actual sky/proxy
shader, using an odd-pixel diagnostic target or a direct shader fixture as
appropriate. CPU atan2 assertions do not settle shader zero-denominator behavior.
Give first/last rows and columns contrasting diagnostic values and inspect
several mip levels, distinguishing polar bleed from longitude-edge clamping.

The checked-in [analysis script](../../../../research/photorealistic-flying-sites/optics_review.py)
has six cardinal UV assertions and ten rotated direction round trips; its
[receipt](../../../../research/photorealistic-flying-sites/optics_review_receipt.json)
is analytical evidence only. The implementation must separately exercise the
actual Godot material and imported texture.

For the rendered reference, compare known projected fiducial centers and
occlusion edges at 120°, 75°, 45°, 30°, 15°, 6° and 1° **vertical** FOV, multiple
headings and nonzero pitch/roll, at 1920×1080. Use markers or an offline resampling
reference whose extraction uncertainty is below the proposed **2 output pixel
maximum**; if source sampling cannot locate a marker to that accuracy, replace
the synthetic fixture or mark the measurement inconclusive. Do not attribute a
low-resolution marker's width to a transform error.

Test baseline filtering, mipmaps enabled/disabled and every proposed compression
route separately. Verify wrap color and mip behavior, not just matching edge
texels. Shader/loader errors are failures. Repeat the accepted method on exact
Compatibility, Mobile/Metal and the applicable Forward+ target; an untested
combination remains unqualified.

## Q02 — real-site calibration and optical detail

**Owner/steps:** capture/CAM/scenery, SC-PHOTO-01/07/09. **Finding:** R01.

Freeze fitting and held-out observations before calibration. Include runway
corners, landing reference marks, near hard edges and distant horizon features.
Report each point's angular residual and output x/y residual at the seven Q01
FOVs, with measured uncertainty and visibility. Do not average critical failures
away with many easy horizon points.

Use these separate judgments:

| Judgment | Proposed first-site rule |
| --- | --- |
| Initial survey screen | Retain original 4 px median / 8 px maximum at 90° horizontal FOV, 1920×1080, with uncertainty reported |
| Landing and hard-occluder registration | At actual task views, begin with a maximum 4 output px at 1080p for designated critical hard edges; use measured error plus uncertainty, not fit residual alone |
| Extreme zoom outside critical features | Report background magnification and residuals at 6° and 1°; pilot review may accept softness, not incorrect aircraft visibility |
| Unknown or inadequate measurement precision | Inconclusive; improve survey/fixture or reduce the qualified feature/region claim before release |

The four-pixel critical-edge target is deliberately demanding and **not claimed
achievable at 1° from an ordinary 16K panorama**. If a critical occluder is used
at that zoom, it must pass or its location/representation/site choice must change.
The first field should keep the operational flight corridor clear of unresolved
complex foreground silhouettes. A generic “extreme zoom is degraded” label
does not waive Q03 at those features.

Record actual source resolution, crop, lens calibration, retouching and any
upscaling. At higher outputs, state the corresponding angular criterion and
review readability on the actual display; do not imply that a rescaled 1080p
image qualifies a native panel. Keep camera laws unchanged.

## Q03 — independent visibility, clipping and contact geometry

**Owner/steps:** scenery/CAM/GP, SC-PHOTO-02/04/09. **Findings:** R02, R03.

**Phase split:** 02 uses only independently known synthetic geometry, clipping
and visibility. Surveyed real-feature/photo checks below belong to 04/09 and do
not block the disposable rendering-method decision before a site is captured.

For every flight-relevant hard feature, retain independently measured near/far
ranges and uncertainty. Place the test aircraft or a clearly dimensioned test
volume wholly before and wholly behind those ranges. Choose separation greater
than the combined survey/geometry uncertainty; exercise close-to-boundary cases
separately as sensitivity tests, not certain truth labels.

Test gaps in fences, isolated posts, tangent paths and overlapping nearer/farther
objects. Compare against measured volumes and the photograph, not solely the
same proxy that renders the depth. Record false occlusion and false visibility
as distinct failures. Foliage can have several depths and translucent coverage;
a single opaque surface must not be treated as an exact reconstruction.

Sweep all admitted camera headings/FOVs around the nearest **visible** proxy
fragments. Check the effective near plane after camera updates, not just after
initial assignment. At the farthest relevant object, place the aircraft on
both sides with independently justified separations; record near/far/depth
format and inspect flicker, clipping and ordering on each renderer.

Retain the original proposed 5 cm maximum visual/support mismatch over the
flat landing region, excluding separately declared turf microrelief. This is
a world-space support check, not a substitute for Q02's image registration.
Analytical swept hit/miss/time/normal fixtures validate contacts independently
of depth rendering. Repeat essential visual checks at all admitted texture and
detail tiers; physical hashes and accepted numerical state must remain invariant.

## Q04 — independent color reference and world refresh

**Owner/steps:** FW/TOD/rendering, SC-PHOTO-02/05. **Finding:** R06.

**Phase split:** 02 proves the synthetic transfer/reference and candidate
aircraft appearance. Integrated World refresh, settings and site restoration
below close in 05; they are not prerequisites for the disposable spike.

Use known neutral and multichannel ramps, shadows, midtones, highlight shoulders
and clipped samples. Produce expected output outside the runtime shader under
the explicitly selected transfer/exposure/tonemap chain. Begin with a simple
uncompressed reference path before testing compression or stylistic grading.

Compare background and proxy **each against that reference**, then against
each other. Proposed synthetic patch target: at most **2 code values per RGB
channel in an 8-bit output** for uniform interior patches, plus absolute
per-channel mean signed error no greater than **1 code value** over named
unclipped patches. Report sample count and full errors; exclude edge filtering
from this patch test and measure it separately. Apply these reference-path
limits before compression, then qualify compressed output separately. Retain
capture precision. A different output format
needs an explicit equivalent tolerance. This is a synthetic transfer check,
not a universal color-fidelity guarantee for photographed grass.

Inspect the actual aircraft and shadow under the resulting captured-world
lighting. Exercise scene build, time refresh, cloud/appearance update, pause,
reset and return to Club/Green. The image must retain its captured policy and
the other sites must recover their requested behavior. A passed static seam
screenshot does not establish these transitions.

## Q05 — aircraft grounding and shadow ownership

**Owner/steps:** shadow/FW/scenery, SC-PHOTO-02/05/09. **Findings:** R04, R05.

**Phase split:** 02 uses a synthetic receiver and known baked-shadow patch to
select the method. Full settings/lifecycle behavior belongs to 05, and actual
surveyed-strip/pilot acceptance to 09.

Use a stationary aircraft, takeoff rotation, a low pass and landing. Cover
Auto, Native, Projected and Off, plus sun/vertical/off cue choices where offered.
For every case record requested policy, effective photo-ground owner and
self-shadow behavior. Sample near the pilot, through the existing native
fade band and beyond it. Inspect for zero-shadow gaps, duplicate ground shadows,
detachment, clipping, bias and wrong sun direction.

Include ground already in a photographed static shadow. Create a separate
synthetic sun-plus-ambient scene as the overlap oracle and compare an aircraft
shadow moving across its lit/shaded boundary. A mask candidate must show its
effect and limits, not merely make the shadow lighter everywhere. The selected
real landing strip must have a pilot-accepted grounding cue under the default
effective policy. Off remains a valid intentional preference.

Repeat after settings change, landscape switch, time refresh and reset, on each
required renderer. No final claim of native photo-ground support without an
actual receiver and passing captures. Saved global preferences must not be
rewritten to implement a photo fallback.

## Q06 — static scenery, surfaces, state identity and replay

**Owner/steps:** GP/SC/AS/NK, SC-PHOTO-04/04b/08. **Findings:** R08, R13, R14.

Validate nondestructible damage policy for photo-baked colliders. Hit a
representative obstacle above a normal break threshold, then make a second
collision/visibility check. If that ordinary impact is terminal for the aircraft,
query the still-active collision inventory with an independent probe and use a
separate rendered before/behind fixture **before resetting away the evidence**.
For a nonterminal response, a second live pass can additionally verify behavior.
Repeat separately after reset and checkpoint restore. The
photograph, visual depth and physical response remain coherent; aircraft damage
continues through its ordinary owner.

For any admitted material extension, vary friction/rolling parameters while
holding explicit relief fixed and verify support heights/normals are unchanged.
Then vary relief intentionally with material fixed. Verify rendering/contact
agreement, version/hash changes, native/reference admission and recorded replay.
A turf-only pilot does not need this extension but must document its material
estimates and reject mislabeled pavement.

Run same-backend accepted-state comparisons with the same physical world and
tick/input tape while changing visual resolution/shadows. Confirm complete
recording and exact physical/backend identity before interpreting replay.
Compare numerical outcomes separately from material/region provenance reports;
the pilot does not promise exact observational provenance. Ensure the selected
world fits collision bins and the existing log header/packet limits.
No visual replay player is assumed.

## Q07 — switching, supersession and memory retirement

**Owner/steps:** landscape/FW/UI, SC-PHOTO-03/07/08.
**Findings:** R10, R17.

Run Club → photo → Green → Club through synchronous and staged routes.
Inject bad version, missing image, wrong dimensions, failed load, unknown
capability and a reported allocation failure. Start candidate A, request B
before A completes, then request C. Under C06, A drains without publication,
B may be coalesced away, and only the current admitted request may activate.
No second large candidate starts while A still owns in-flight allocations.

Record scene, field/inventory, generation and World/Atmosphere/cloud owner
identities around each event. Assert that a stale candidate cannot install a
camera, light, field, saved selection or old snapshot. A retained flow-enabled
3D World continues its original refresh/time flow; a retained photo World keeps
updating under its frozen captured-appearance policy. Physical simulation time
remains separate. If the implementation
later permits overlapping candidates, add A-start/B-commit/A-fail as an explicit
owner-checked rollback test before broadening concurrency.

Include a multi-resource candidate and verify that requests within its group
remain within C06's concurrency/staging bound. Use existing cache-lifecycle
checks as one signal. Measure process and GPU
memory when available at accepted baseline, decode/upload peak, activation
overlap and after retirement. Proposed initial sequence: ten full site cycles,
with a bounded, predeclared settle observation after each. Record allocator
high-water behavior; require a bounded plateau within the host envelope rather
than expecting a driver to return exactly to its first byte count. Sustained
growth beyond the declared noise, allocator and cache envelope, or confirmed
stale candidate ownership after retirement, fails. Insufficient observation to
distinguish a plateau is inconclusive. Substantiate the GPU tier ceiling by
target-appropriate measurement or a conservative bound covering all photo
allocations; otherwise the device's memory subgate is inconclusive. Unavailable
counters are not zero usage, and unified memory is not counted twice.

Do not deliberately induce system OOM. Controlled loader/failure injection
proves recoverable error handling; ordinary target-hardware load measurements
prove the admitted resource envelope. They answer different questions.

## Q08 — cold-start recovery without hidden substitution

**Owner/steps:** UI/landscape/DT, SC-PHOTO-03/08/10. **Finding:** R09.

Cold-launch with a saved photo selection and, one at a time: missing sidecar,
missing image, corrupt descriptor, unavailable supported variant and missing
required physical data. Exercise both startup routes. There is no old Home.

Require a usable recovery screen, accurate reason, Retry, Choose another site
and Quit. Selecting another site is explicit and validates that site's own
identity. Check that the original saved preference persists before a successful
choice, a save failure is reported, and no default world is exposed under the
photo ID. Repeat when every available site is invalid. Automation must fail
clearly without interactive substitution.

Check keyboard/controller focus, localization and ordinary window/text scaling
through the existing UI harness; recovery must not depend on the failed photo
asset. Keep the saved restriction/selection behavior distinct from transient
in-flight cancellation.

## Q09 — route admission and survey-coverage notice

**Owner/steps:** UI/CAM/SC, SC-PHOTO-04a/06/08.
**Findings:** R11, R12.

A new runway-capable photo field permits its qualified ordinary start but
refuses Natural Random in both UI and route calls. Club's existing Natural
Random still works. Test saved stale activity choices, direct/keyboard requests,
camera cycling, CLI/debug requests, crash framing, magnifier, `--look_alt`,
Workshop and the vehicle-specific builders. Unknown capabilities fail closed
before session mutation; do not silently launch a nonphoto route with the photo
field's contacts.

The combined successful runway-start/Natural-Random refusal proof closes in
04a/08. Step 06 can develop its camera/activity refusals before that integration;
its own Q09 scope is capability guarding and coverage observation.

For coverage, exercise inside, exactly on the inclusive boundary, sphere partly
outside, continued outside flight, re-entry margin, start outside, pause/reset
and rapid accepted-tick crossings. Verify notice persistence/clearing and that
the observer does not write input or accepted simulation state. Check different
supported aircraft radii. A UI notice is not contact or geographic validation
beyond the surveyed volume.

Include actual admitted runway start and landing poses so the radius and
re-entry margin cannot leave the notice permanently active during ordinary
ground use. Below-ground padding of a monitoring bound is not a subsurface
survey or contact claim.

## Q10 — actual export inventory, identities and size

**Owner/steps:** DT/assets, SC-PHOTO-07/10. **Findings:** R15, R16.

Build each supported export with exact templates and inspect its resource
inventory. Resolve descriptor, field/inventory, chosen variants, fallback,
required notices and credits from the package with developer originals absent.
Check resource class/dimensions and physical identity through the correct
loader, not pre-import image hashes through FileAccess.

Measure deltas in final distributed archive bytes and summed logical file bytes
of the extracted installed tree. The control uses the same commit, engine,
templates and packaging settings, differing only in explicitly documented
site-content inclusion. Record both artifact hashes and file lists.
Apply the proposed 128/256 MiB caps in C07, with any
pre-approved revision recorded. Identify every shipped 4K/8K/16K derivative.
A source outside the Godot project is not automatically included by
all-resources mode; inspect the final archive and staged sidecars to establish
whether any release step shipped it. A resource under
`all_resources` is not excluded merely because code never selects it.

Negative packages missing one mandatory notice, field/inventory binding or
fallback must fail the relevant admission check. Verify offline startup, site
choice, takeoff/reset/return and recovery from the released package. No source
checkout or cached developer import can supply a missing file.

The existing [export script](../../../../app/export.sh) checks all three packs
with a Linux host editor. That is package-resource inspection, not execution of
the Windows/macOS target binary. Record offline startup, rendering and
takeoff/reset checks separately on each admitted target OS/device with its
exported binary and effective renderer.

For a conditional codec trial, record `extensionsUsed`, `extensionsRequired`
and the pinned engine's registered glTF extensions; compare extension-only and
fallback-bearing files. Verify names/materials/extras after optimization and
the actual imported format. Loading through a PNG fallback is not compressed
extension acceptance.

## Q11 — timing, noise and resource qualification

**Owner/steps:** VQ/PT/DT/NK, SC-PHOTO-09. **Finding:** R18.

Use named hardware and the effective renderer/backend. Ordinary targets start
at 1920×1080; Apple Silicon Retina uses native physical-panel resolution and
separately reports output/drawable/internal 3D dimensions. Apply the existing
[Apple plan](../../../plans/apple-silicon-performance.md) and
[resolution policy](../../../../AGENTS.md#display-resolution-priorities).
A software renderer is image evidence only.

### Separate three workloads

1. A fixed-state/view rendering fixture diagnoses projection and pass costs.
   It does not claim full-flight performance.
2. A repeatable live workload uses the same aircraft, physical world and
   accepted-tick input sequence, with explicit view/FOV targets or a qualified
   render harness. The current offline flight-log CLI is not that visual driver.
   If a camera/view driver must be extended, scope it under existing tools before
   collecting paired evidence.
3. A representative pilot flight evaluates usability, takeoff/landing, tracking
   and ordinary frame pacing. Human flights are not treated as identical paired
   inputs for a one-millisecond GPU comparison.

Define regimes and markers before collection: ground/start, takeoff, near
low-pass/occlusion, distant zoom, cruise and landing. Pause/resume and cold/warm
loading are recorded separately from steady-flight distributions. Preserve the
original starting workload of ten minutes per qualified live run and at least
three matched pairs; adjust through the owning protocol with an explicit reason.

### Incremental GPU criterion

Use a supported GPU timestamp/profiler method; record its synchronization,
resolution and overhead. V-sync-disabled diagnostics can expose cost, but
present intervals or CPU frame duration do not become GPU elapsed time.

Baseline A keeps the **same physical field** and workload with one explicitly
identified fixed diagnostic presentation, assets and settings; B replaces that
presentation with the candidate. Record both complete presentation manifests.
The difference is net whole-frame GPU change, including changed occlusion, not
isolated photo-pass time. Use pass timings as a separate diagnostic. Also measure
panorama-only and full proxy/shadow composition to locate cost. Keep
reconstruction, output, aircraft and unrelated settings fixed.

The proposed default statistic is:

`D[p,r] = p95(GPU_B[p,r]) − p95(GPU_A[p,r])`, where `p` is the matched run
pair and `r` is the predeclared flight regime.

Name it a **paired difference of run-level p95s**, not “p95 of frame deltas.”
Alternate order across pairs (AB, BA, AB, or a predeclared balanced equivalent)
and retain every pair's result. Run at least two A-versus-A control pairs with
the same collection method. Before accepting B, compute a declared allowance
`W[r] = max_p(abs(p95(A2[p,r]) − p95(A1[p,r]))) + 2 × timer_resolution_ms`.
Use that fixed formula and retain the A/A samples. For this small pilot, report
`[min_p D[p,r] − W[r], max_p D[p,r] + W[r]]` per regime as an empirical range,
not a statistical confidence interval or a guarantee about future runs.

The existing proposed **1.0 ms incremental GPU budget** applies to each named
regime using that statistic. All expanded intervals below the limit support a
pass; an interval spanning it is inconclusive; a repeatable lower bound above
it fails. Missing GPU timing is inconclusive for this subgate. A deterministic
per-frame matched experiment may use p95 of paired deltas instead, but must
declare its matching and statistic in advance.

### Delivered pacing and physics

Measure complete exported live flight with normal chosen V-sync outside
graphics capture/profiling overhead. Target the original 60 fps class.
Proposed first-site pacing limits on a qualified 60 Hz configuration:

- p95 presented interval no greater than 1.1 frame periods (18.33 ms at 60 Hz).
- p99 no greater than 2 frame periods (33.33 ms at 60 Hz), with all missed-frame
  clusters reported.
- No steady-flight interval above 100 ms attributable to the site; retain raw
  stalls, including OS interruptions, and investigate rather than deleting them.
- No sustained simulation slowdown/catch-up growth; retain Gate P's 500 µs
  per-tick target and its owner-defined evidence.

These are proposal values, not existing project-wide gates. A different display
refresh/sync mode needs a predeclared equivalent frame-period rule. Report raw
p50/p95/p99/max and frame counts as well as pass/fail. A poor baseline does not
qualify merely because B adds little. Retain RAM/GPU peak/steady/retirement,
CPU/GPU cost, load duration and included variant. Native Mac remains an exact
domain decision; reference fallback is reported as such.

## Q12 — pilot acceptance and release decision

**Owner/steps:** scenery/CAM/DT with a pilot reviewer, SC-PHOTO-09/10.

Use the same accepted package and site. Complete a normal launch, runway start,
takeoff, low pass, distant attitude check, return/landing, reset and switch away.
Review aircraft silhouette/orientation against representative background areas,
landing height cues, photo-shadow grounding, zoom behavior and coverage notices.
Record the aircraft, display distance/scaling and reviewer observations, including
a rejected or confusing task rather than averaging it away.

Close the first release only with: independent projection/color/depth evidence;
correct contact/damage policy; supported routes; recoverable cold start and
switching; hardware budgets; rights and offline package completeness; and a
usable flight. SC-PHOTO-02 may pass while a real site or a platform remains
unqualified. A restricted release must list its actual supported combinations.

## Existing tools and receipts

Reuse current instructions instead of copying an alternate command catalog:

| Existing home | Use in this work |
| --- | --- |
| [Tool index](../../../tools/README.md) and [graphics guide](../../../tools/graphics.md) | Select focused capture/profiler checks; preserve renderer and resolution scope |
| [Debug bridge](../../../../tools/debug/README.md) | Existing live interaction, camera/state inspection and failure diagnosis |
| [Landscape tools](../../../../tools/landscape/README.md) | Current landscape setup/capture contracts |
| [Flight logging](../../../FLIGHT-LOGGING.md) | Numerical input/state identity and scoped replay, not an assumed visual player |
| [Test admission](../../../../tools/testqueue/README.md) | Shared-host ownership and focused test execution |
| [Original harness map](../2026-11-18/validation-and-budgets.md#existing-focused-harnesses-to-extend) | Field, landscape, camera, world, native and package checks |
| [Optional-resource test](../../../../app/tests/test_optional_resource_loading.gd) | Add cache lifecycle assertions for unselected, failed and released photo resources |
| [Field package check](../../../../app/tests/check_field_pack.gd) | Extend descriptor/inventory/notice/fallback coverage in actual exports |

A compact result receipt names case, source/build, physical and presentation
identities, exact stimulus, independent oracle, expected threshold, raw output
location/hash, measured outcome, exclusions, requested/effective settings and
remaining claim limitations. Large captures belong with the existing evidence
retention workflow; do not fill ordinary Git history with unnecessary images.

## Traceability

| Findings | Contract | Qualification cases | Existing step |
| --- | --- | --- | --- |
| R01 | C02 | Q02, Q12 | 01, 07, 09 |
| R02, R03 | C02 | Q01, Q03 | 02, 04, 06, 09 |
| R04, R05 | C04 | Q05 | 02, 05 |
| R06 | C03 | Q04 | 02, 05 |
| R07 | C01 | Q01 | 02 |
| R08, R13, R14 | C05 | Q06 | 04, 04b, 08 |
| R09 | C06 | Q08 | 03, 08, 10 |
| R10, R17 | C06, C07 | Q07 | 03, 07, 08 |
| R11, R12 | C05 | Q09 | 04a, 06, 08 |
| R15, R16 | C07 | Q10 | 07, 10 |
| R18 | C08 | Q11 | 09 |

This table maps requirements; it contains no second implementation-status ledger.
