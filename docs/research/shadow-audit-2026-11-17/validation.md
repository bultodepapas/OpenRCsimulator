# Validation, reproduction and remediation handoff

Baseline: `3c91936ab8f9064daa798311b5fb3e89e28d3754`. This is a completed source/module audit with explicitly unrun native acceptance cases. It does not certify the user's displayed frame or a production performance improvement.

## Executed campaign

| Check | Result | Meaning |
| --- | --- | --- |
| Exact-source closure | 36 selected app files matched baseline Git blobs: 34 runtime dependencies and two existing tests | Selected modules are unchanged; this is not a full production project |
| Checked minimal-project import | Passed, no checked engine warnings/errors | Selected dependency closure parses/imports on the pinned engine |
| Existing `test_shadow_collection.gd` | 77 passed, 0 failed | Preserves existing geometry-order, threshold and source-isolation controls |
| Existing `test_shadow_blur.gd` | 50 passed, 0 failed | Preserves existing blur parity, edge and ownership controls |
| New audit `probe.gd` | 29 passed, 0 failed | Reproduces the scoped routing, geometry, cache and telemetry observations below |
| Five GLB source inventories | All matched baseline Git blobs | Source material metadata only; no imported-material or render-pass qualification |
| Full application, GPU rendering and export packages | **Not run** | No screenshot, FPS, native VRAM or fleet-wide quality claim |

The retained campaign totals **156 assertions**, excluding import. It used the official Linux x86_64 `4.8.beta2.official.cafc17a19` executable, headless display, Dummy audio and isolated user directories. The checked runner enforced a timeout, completion marker and warnings-as-errors. These are portable CPU/state/geometry checks on a private runner, not a substitute for shared-host graphics admission.

### Exact reproduction

From a checkout containing the unchanged audited production files and the committed audit directory:

```bash
python3 docs/research/shadow-audit-2026-11-17/repro/run.py \
  --source . \
  --godot /absolute/path/Godot_v4.8-beta2_linux.x86_64 \
  --out tmp/shadow-audit-reproduction-01
```

The output must be new. The runner refuses a different executable SHA-512 or a production dependency that does not match the frozen Git tree. It creates a minimal project without the application's autoloads, copies existing tests without editing their bytes, imports first and invokes the repository [checked runner](../../../tools/godot/README.md). It does not download an engine or modify saved game settings. On an enrolled/shared host, use the [test queue](../../../tools/testqueue/README.md) and required session ownership; do not bypass admission with the private-runner example.

The exact Linux engine SHA-512 is:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

[source-manifest.json](evidence/source-manifest.json) binds production dependencies, harness, checked-runner dependencies and the minimal project. [campaign.json](evidence/campaign.json) records the four command verdicts. [copy-checksums.json](evidence/copy-checksums.json) maps retained raw logs/reports back to their original paths and hashes. [observations.json](evidence/observations.json) records numerical/state outputs. Absolute scratch paths in the raw reports are provenance, not portable reproduction paths.

### Audit-specific controls and their limits

| Observation | Control that makes it useful | Limit |
| --- | --- | --- |
| 12 technique/renderer resolver combinations | All four techniques across three supported renderer-name inputs | Pure policy calls; not three GPU sessions |
| 35° local hinge motion leaves installed mask mesh unchanged | Fresh collection changes, installed vertex bytes and redraw count remain unchanged | Demonstrates stale representation; no rendered artifact score |
| Alpha-zero and opaque boxes supply identical 12-triangle mask geometry | Same shape, different source material; mask material replacement inspected | No image/coverage/readback test |
| Source y=2→12 m keeps receiver at y≈0.05 m | Two source heights | Fixed plane only, not a slope/roof screenshot |
| Fixed 2° raw/bounded directions yield 19.9878 vs 4.70463 m offset per metre height | Calls the production direction/project helpers | Raw result already includes denominator clamp; not physical cotangent at 2° |
| 0.2° rotation gives 49.2667 mm projected displacement | Synthetic 3 m +Z point; actual 6 m box refresh reuses at 0.2° and redraws at 0.3° | Counterexample at minimum blur; not an aircraft wingtip, clipping or visible jitter proof |
| Selected 8192, diagnostic 4096 | Actual resolver and actual diagnostic function | Headless skips live atlas setter; no 8192 GPU allocation observed |
| Native eligibility true, actual light disabled | Explicit source veto | Intentional policy precedence; misleading global interpretation is the concern |
| Seeds 101…105 exhaust four pending entries | One retained material, only last seed required; retry and last-consumer cleanup | Synchronous admission; no completed GPU bake, paced UI change or FPS result |

No helper reimplementation substitutes for the production behavior being tested. Numerical controls exercise small purpose-built inputs. Module checks deliberately separate arithmetic/ownership from visual severity.

## Native scenario matrix

**Status for every case below: not run in this audit.** These are concrete acceptance cases for the findings, not fabricated passing evidence. Start at **actual 1920×1080**, then test above 1080p, then 1280×720 fallback. Record actual acquired/rendered/output dimensions rather than trusting the requested window size.

| Case | Controlled scene/action | Required observation | Findings |
| --- | --- | --- | --- |
| N01 | Opaque Corsair/Extra/P-51 and a thin external blocker; fixed sun; matched Native/Projected/Auto | Wing→body, gear/strut contact, external occlusion and attributed ground darkness; unoccluded surface color control | 01, 02, 13, 14 |
| N02 | Same root pose, neutral/full controls, installed gear up/down and wing fold | Shadow follows local geometry, visibility and detachment; no unnecessary full-mesh recollection | 03, 05, 23 |
| N03 | Runway, slope, elevated ramp, roof/intervening object, shoreline | Correct receiving surface or declared fade/limitation; height uses valid receiver relationship | 04, 20 |
| N04 | Opaque, alpha-0.5 custom body, scissor/hash leaf card, blended canopy, two-sided thin surface | Actual imported/shader cast/receive state; preserved openings and source isolation | 01, 05, 18 |
| N05 | Fixed and equivalent flowing sun at 2°, 12°, 45°; same Home/Fly/field | Consistent declared Sun cue; distinct Vertical aid; physical sunlight/camera contract unchanged | 06, 09, 21 |
| N06 | Small/large aircraft, slow pitch/roll/yaw and sun motion through reuse thresholds | Exact-refresh reference, temporal edge displacement and mask update counts; no clipping/lag at accepted tolerance | 07, 19 |
| N07 | Fixed-wing, helicopter, ground vehicle, multirotor, airship and available preview routes | Technique/cue setting has truthful coverage in every activity, including switch/restart | 01, 08, 14, 26 |
| N08 | Full, reduced and zero celestial strength; Sun/Vertical/Off; Home→Fly | Agreed nighttime aid policy, moon/sun handover and saved/local override precedence | 09, 20, 21 |
| N09 | Five-plus paced and rapid cloud-seed changes with ground/sky consumers | Ready/pending/failed stale entry retirement, shared-seed retention, cancellation and retry, analytic fallback parity | 10, 15 |
| N10 | Moving cloud shade crosses runway, near-grass, aircraft, building and water | Coherent spatial direct-light attenuation without double application or ambient/exposure changes | 15, 16 |
| N11 | One landing spotlight and one field flood, then bounded simultaneous selection | Useful obstacle occlusion, offscreen blockers, stable budget/hysteresis and light motion | 17, 25 |
| N12 | Shelters, fence/slats, benches, people, tree/grass alpha and wind/LOD transitions | Explicit caster coverage, preserved openings, coherent deformation and no allocation popping | 05, 18 |
| N13 | Propeller and rotor stopped/start/fast/stop at several presentation rates | Declared coverage, no opaque frozen disc, flicker or stale silhouette; accepted visual clock | 03, 19 |
| N14 | Wreck on flat/sloped/elevated contact, lit and moonless; fade/reset | Declared ambient/direct composition, correct contact and lifetime | 04, 20 |
| N15 | Initially Off/Native/Projected/Auto; first enable; repeated toggles; retained worlds and source destruction | Cold CPU collection, constructed resources, native allocations/retirement and accepted activation images | 10, 11, 12, 22, 23 |
| N16 | Low→Ultra→Off, Near/Far, Hard/Soft, Keep/Revert/restart and engine-off override; separate concurrent display-mode timeout trial | Requested policy, applied owner revision, actual light/range/angle and renderer receipt agree; shadow-only previews do not start the display safety timer | 13, 14, 24 |
| N17 | Identical ordinary flight with reflection/weather/scene-detail factors separately controlled | Whole-view CPU/GPU cost, timestamp freshness, p50/p95/p99, memory and image workload identity | 11, 12, 22, 23, 24, 25 |
| N18 | Installed/exported packages, resize, pause/reset, vehicle switch and scene return | No source-only success; correct engine/runtime/asset provenance and lifetime with normal gameplay | 26 and affected fixes |

Use the fleet's existing aircraft identifiers/authoring contracts; test mechanisms only on models that actually have them. Cover the user's failing aircraft first once identified from a live frame or saved reproduction. A good still of a different aircraft cannot close that complaint.

### Renderer, device and material axes

Run the supported route on a named NVIDIA GPU, a named Radeon GPU and the actual Apple/other platform route being claimed. Include the modest-hardware baseline if promoting a Standard preset. Record device and driver rather than treating a vendor family as a result. Historical RTX 3090 captures do not qualify today's source on all NVIDIA devices; Ryzen CPU timing is not Radeon rendering evidence; M1 bounded RT execution does not qualify full aircraft RT.

Keep actual Standard Compatibility, High Forward+, ARM64 Mobile, custom NVIDIA/AMD engines and optional Metal experiments separate. A feature unavailable on one route needs an honest fallback; do not call a skipped case passed. Include default paint, a supported custom alpha paint and emissive overlays so a darkening change cannot conceal unsupported material participation.

### Image and motion controls

Freeze source/assets/import identity, aircraft dimensions, presentation pose, camera transform/FOV, time/weather seed, light energy/angle, exposure/tone mapping, AA/reconstruction and output scale. Repeat the baseline against itself first to establish capture noise. Compare full images and close inspection crops, but retain the unmodified full frames. Use a known unoccluded surface to detect unintended lighting changes.

Separate mask-oracle coverage from final color, and static fidelity from normal-speed temporal behavior. Include offscreen occluders, disocclusion, camera cuts and cascade/LOD boundaries. Examine acne, detached contact, doubled edges, thin-part loss, swimming, lag, shimmer and transparency independently. An image difference is not automatically a defect; image equality is not proof of realism. Keep the negative control where disabling the relevant caster/light removes the expected occlusion.

Reuse [shadow tools](../../../tools/shadows/README.md), [graphics captures](../../../tools/graphics/README.md), the [debug bridge](../../../tools/debug/README.md) and [tool index](../../tools/README.md). The old `vq04a_verify.py` has a specific pre-VQ-04a baseline contract; do not point it at arbitrary two current trees and relabel the result. The aircraft-proxy trial covers a deliberately narrow Corsair context and component timings. Extend a suitable fixture only when its current contract cannot express a concrete remaining case.

## Performance protocol

First correct SA-13/14 and name every relevant rendered view. Record root scene, native shadow passes, aircraft/field mask updates, cloud bake/fallback work, reflection/sky refresh and optional secondary views. Treat unverified/lagging GPU timestamps as unavailable. Disabling native light shadows alone is not a whole-shadow ablation; disabling all subviewports can remove unrelated work.

Separate cold scene/setup/first-use from warm steady flight and settings-transition hitches. Use the repository's admitted collector, a quiet owned graphics session, alternating baseline/candidate order and retained raw samples. The [owning VQ-01c measurement contract](../../plans/global-performance-visual-quality.md#4-measurement-and-acceptance-contract) requires 10 seconds of warmup and 60 seconds of sampling per run, with **at least three alternating baseline/candidate pairs**. Keep stricter owning-tool/track contracts and extend runs that miss periodic updates. Report sample count, discarded overlap/timeouts and observed workload. Do not claim savings from a one-frame counter.

Report CPU construction and frame work, GPU component and total time, frame-time p50/p95/p99, draw/primitive counts, mask refreshes, process RAM and measured GPU residency/peak allocation. Use Nsight Graphics, Radeon GPU Profiler or Metal/Xcode capture on their supported route for pass/resource attribution, separately from normal flight timing. Observer/capture overhead is part of the apparatus and must not be silently folded into the candidate gain.

Use the [owning acceptance gates](../../plans/global-performance-visual-quality.md#gates-to-freeze-in-vq-01c) for the target profile, including frame pacing, resources, startup and lifecycle; this audit does not replace them with a new universal FPS threshold. Optimization adoption requires a gain greater than paired variation **and at least 5% of the affected complete workload**, or removal of a named reproducible hitch/memory defect. Added visual work requires allocated headroom and the parent's combined-cost gate, not a separate allowance for every effect. Preserve image/motion acceptance and reject repeatable harmful tradeoffs. If geometry work moves from startup into first enable, report both costs. Do not sum independent component savings or convert an isolated mask speedup into whole-flight FPS.

## Existing work preserved

| Retained evidence | How to use it |
| --- | --- |
| [October 31 planning audit](../shadows-2026-10-31.md) | Historical beta1 source/technology research; its initial absence of dedicated settings is superseded |
| [S01–S03 implementation](../visual-quality-implementation/VQ-04b/S01-S03-2026-10-31/README.md) | Existing process-wide owner, saved controls, routing and scoped 1080p captures; broader motion/device gates remain |
| [S06 shelter follow-up](../visual-quality-implementation/VQ-04b/S06-shelters-2026-10-31/README.md) | Existing bounded native shelter work; not all scenery categories |
| [November 9 deferred startup](../visual-quality-implementation/VQ-04a/deferred-startup-20261109/README.md) | Aircraft GPU/materialization work already corrected; retained CPU geometry is an intentional separate contract |
| [November 9 aircraft proxy](../visual-quality-implementation/VQ-04a/aircraft-proxy-20261109/README.md) | Narrow exact-source Corsair optimization and component evidence; no automatic fleet extension |
| [Current MetalFX record](../desktop-delivery-investigations/DT-MAC-11a/README.md) | Actual bounded native RT progress and still-closed product gates; later sections supersede earlier uncompiled states |

## Closing a finding

Keep the SA identifier and canonical VQ-04b owner/step. Attach the failing reproduction, exact correction commit, source/engine/asset/setting hashes, targeted controls and the applicable native cases. Record unavailable/rejected cases explicitly. For performance claims include both component attribution and whole-flight measurements; for appearance include stills and normal-speed motion on named hardware. Preserve simulation outputs and physics fingerprints: these changes belong to presentation, not the flight kernel.

The audit branch itself closes **the investigation and evidence-delivery task**. Its findings remain open until those acceptance conditions are met; a green headless campaign does not close a visual or GPU gate.
