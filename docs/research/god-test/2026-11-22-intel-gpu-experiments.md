# Existing-Intel experiment protocol — 22 November 2026

The [corrected low-end plan](../../plans/low-end-gpu-performance.md) owns
execution order after the [adversarial audit](2026-11-22-intel-plan-adversarial-audit.md)
of main `85a2475f60029a4b6b09f23f643119bceea84a45`, with the Green/Club
follow-up refreshed against `843f357c07af842054f3ccd6728f93beca9a57ef`. The
[render-internals follow-up](2026-11-22-intel-render-internals.md)
retains sixteen code-linked candidates. This protocol owns admission, evidence
identity and comparison scope; a full tour is conditional, not the entry ticket
for every experiment.

Companion to the [investigation](2026-11-22-intel-gpu-investigation.md), under
VQ-07h-A2-R1 / PT1h-R15 / GOD-12/13. **Proposed hardware experiments, not completed
measurements.** Use the same currently owned Intel device for every paired
comparison. The earlier M1 records are context, not a new test dependency.

## 1. Establish the correct baseline

The [GOD TEST tour guide](../../../tools/godtest/PERFORMANCE_TOUR.md) owns its
launch, admission, output and acceptance procedure. Its `--graphics automatic`
option writes the first-run graphics bundle; it does **not** independently
select the product's renderer. In
[`runner.rendering_options()`](../../../tools/godtest/runner.py), renderer
`auto` resolves to Forward+ on Linux. Explicitly select Compatibility/OpenGL
to reproduce the current UHD 630 product recommendation.

This exact **full-tour offline preflight** was checked against source
`91d7d6dd`. It is retained for a later claim that actually needs the complete
three-aircraft scope; it is not the first command for L0/L1 attribution:

```sh
python3 tools/godtest/godtest.py performance-tour --dry-run \
  --repeats 3 --graphics automatic \
  --resolution 1920x1080 --window-mode borderless \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --scene-detail low
```

It expands nine complete cases: Stik, jet, Corsair, repeated three times.
Requested native physics, continuous frame watch, hardware monitoring and all
menu/circuit/shutdown phases remain enabled. The plan requests uncapped FPS and
VSync disabled. It does not prove actual renderer, scale, hardware coverage or
completion. The reported execution lease is planning information, not duration.

For execution, follow the guide's admitted route. The reviewed managed graphical
adapter is Windows-local/experimental; checked-pool SSH access does not by
itself authorize an alternate graphical launcher on an enrolled Linux host.
Use the existing owning session/authority and reconcile its capabilities with
the deployed host. Do not disable enrollment or change queue roots to bypass an
unsupported adapter. The earlier operator-owned Intel campaign does not turn
an unavailable route in this workspace into a live connection.

First reconcile the actual operated session and its existing admission. When
available, use the smallest affected Home or pilot-view comparison with matching
native binary/imports and retained engine/source receipts. Reuse a matching
current receipt; do not require a three-aircraft route pass or nine-case baseline
before a pixel/material screen. Expand to the existing complete tour only when
the change or final whole-session claim affects all three aircraft. Keep the
current Dummy-audio workaround for hosts without playback devices, and the
documented X11-through-Weston path constant. Compare Wayland separately only
for an attributed display/shutdown question.

If the required graphical route or mandatory monitoring is unavailable, record
that limitation and leave formal qualification open. Source changes, settings
design and deterministic checks can proceed. An existing functional container
lane is not a desktop performance route; no alternative launcher, validator
bypass or replacement machine is authorized by this protocol.

The older direct `--scripted` route is a technical workload. App arguments take
it before first-run player settings are loaded. It must not be described as
the current Automatic product behavior. Supported direct-route knobs include
`OPENRC_MSAA=0|2|4|8` and `--scene_detail=low|medium|high|extreme`; there is no
implemented direct `--render-scale` argument in `Reconstruction.startup_config()`.
Use the existing player settings or an owned debug session for scale trials.

## 2. Required identity and telemetry

Retain raw samples in the existing ignored/external evidence location. Publish
only concise, sanitized summaries, hashes and a recovery location. A hash of
this investigation's transcription is not a hash of the unavailable raw run.

| Layer | Required record | Interpretation |
| --- | --- | --- |
| Source/executable | Commit and dirty-input digest, engine version/hash, native binary/receipt, driver/tool versions. | Source-only, package and hardware results are different claims. |
| Workload | Aircraft/model, scene/landscape/collision identity, camera, fixed view or real circuit, time/weather/seed, graphics identity, phases and raw frame stream. | Preserve the same route and effective settings within a pair. |
| Display/rendering | Engine adapter/vendor/API, renderer, DRM render-node mapping/BDF, Weston renderer, Wayland versus X11, output/drawable/internal 3D dimensions, actual scale, HDR2D, AA enum and sample count, reconstruction, VSync/cap, Home budget state, experimental flight dynamic-resolution request/support/status. | A compositor can use hardware while the app uses another adapter; verify both. A saved scale is not proof of actual pixels. Keep flight dynamic resolution Off during fixed attribution. |
| Host GPU | Per-engine busy/time observations, actual/requested/configured maximum clocks, package/GPU power and temperature where available, thermal/power-limit indications, timestamped i915 errors/reset counters. | Render, video, copy and compute engines are distinct. Frequency alone is not utilization; device totals include other processes. |
| Process/CPU | Existing process CPU/RSS/threads/I/O, thread hot spots when necessary; actual CT CPU quota/cpuset/weight and `cpu.stat` throttling deltas. | 100% process CPU is one logical CPU; 6 assigned threads do not imply six exclusive physical cores. |
| Memory | Existing module sizes/slots/channels/configured speed; host available memory, swap activity and PSI; actual CT `memory.current`, `memory.stat`, `memory.events`, `memory.swap.current`, high/max limits and pressure. | Resolve the process's cgroup and relevant ancestors; container-visible `/proc/meminfo` alone is insufficient. Do not add overlapping RSS/shmem/engine counters. |
| Shared work | GPU clients and co-tenant workload class/activity, capture/encoder state, timestamps and thermal settling. | Keep services unchanged by default. A past one-time stop permission is not a new standing maintenance window. |
| Cache | Godot user-profile/cache identity, Mesa cache path/state/hit statistics, imports and process state. | Fresh process, fresh profile and cold driver cache mean different things. |

Use existing `render`, `frames`, `layers`, `memory` and `frames watch` through
the [debug bridge](../../../tools/debug/README.md), and the existing
[resource sampler](../../../tools/godot/README.md). For fields they lack, the
admitted host operator can collect bounded read-only Intel/OS observations:

- Resolve the render node through sysfs and `lspci -nnk`; retain vendor/device
  and driver identity. Avoid relying on a hardcoded `card0`/`card1` numbering.
- If already available with appropriate read access, retain Intel GPU Tools
  per-engine/clock JSON or supported DRM `fdinfo` counters with device identity,
  units, monotonic query brackets and an owned process lifetime. Check the
  installed tool's help/version for its exact invocation. Do not change kernel
  permissions or give the container additional device privileges to get a number.
- Treat unsupported or denied PMU/temperature/power fields as unavailable.
  Do not fabricate zero values. Per-client cumulative engine time requires two
  ordered samples; account for engine capacity, duplicated client IDs, resets,
  process restarts and elapsed-time units. It is not device-wide busy percent.
- Keep detailed traces, Mesa shader statistics and thread profiling in separate
  diagnostic runs. Measure observer-off versus observer-on overhead before
  accepting the instrumented workload as a reference.

These observations supplement the artifact set. They do not add an Intel
backend to the current GOD TEST validator: its automatic Intel utilization
coverage remains unavailable until a reviewed implementation consumes it.
A diagnostic comparison may report its supported observations and explicit
unknowns, but cannot claim to pass a validator whose mandatory fields are
missing. Building that backend is not a prerequisite for source attribution or
offline implementation; formal hardware qualification remains separate.

## 3. Controlled experiment matrix

Run one applicable experiment at a time, stopping once the evidence settles the
decision. IDs below are stable references, not a requirement to execute every
row. Start with I0/I6 inventory and the Green/Club G0–G2 screen below. Its result
selects I1 pixels, I3 ground or a focused Club feature; a faster Green alone does
not select ground or one object. I5 loading is a separate workstream whose
hardware captures still serialize. I2 is conditional
because current Automatic already disables main AA. I4/I7/I8/I9 are deferred
until evidence identifies their question. Shared-host admission, memory
headroom and clean teardown remain required. No row requires different physical
hardware.

| ID | Question and controlled comparison | Keep fixed / retain | Decision rule and limitation |
| --- | --- | --- | --- |
| I0 / L0 | Is the current product profile actually being tested? Explicit Compatibility/OpenGL and current Automatic effective bundle. | Same source/engine/native backend, effective settings, output/internal dimensions, named affected phase and telemetry availability. | Wrong renderer, software fallback, missing identity or forced shutdown invalidates the affected claim. Fix that evidence gap before a performance conclusion; source work need not wait. |
| I1 / L1 | Does pixel work dominate? Start with existing 75% versus 67%; compare 100% versus 75% only where the saved baseline is actually 100%. | Output 1920×1080, same camera/world, main MSAA off, equal thermal state. Hold Home's effective multiplier constant for the component A/B and verify production adaptation separately. | A repeatable frame-time response supports pixel sensitivity, not a unique ALU/bandwidth diagnosis. Existing 75% gains are not new gains. Check distant-aircraft readability and UI sharpness. |
| I2 / conditional L4 | What is a target's AA marginal cost? Main off versus 2× only if that choice is at issue; inspect projected-shadow AA independently. | Same scale, renderer, camera/materials and cache state; record effective target, enum and sample count. | Current main AA is already Off. Do not count disabling it again, or assume it disables aircraft-shadow AA. Preserve edge/thin-wing/motion readability. |
| I3 / L2 | Which terrain term is expensive? Existing reversible `ablate` screen, then one bounded Simple/Full material candidate only if current attribution supports it. | Separate fixed Home and flight views; keep geometry, physical scenario, effective scale, light and AA identical; review day/night, runway, pad, track and shoreline. | Cached GPU polls and layer hiding are diagnostic leads only. Do not qualify deletion of collidable scenery or lake/track. Accept only repeated matched whole-workload improvement and preserved cues. |
| I4 / deferred | Does a specific remaining Compatibility problem justify Mobile/HDR investigation? Compare only after that question is established. | Same Intel, camera, internal resolution and AA, recorded effective HDR/color format; matching warmup and safe recovery. | No general renderer migration follows from newer API support. Speed alone cannot justify lost night detail; a Mobile-only improvement need not beat GL. |
| I5 | Is the startup freeze compilation or recurring loading? Separate Godot-cache-cold/Mesa-warm, both-warm, and isolated both-cold conditions. | Same scene/order/source/audio path; separate owned profiles/cache directories and retained cache states; retain time-to-first-usable-frame and worst frame. | A cache-dependent stall identifies first-use work. Remaining warm stalls need a stage/thread trace. No deletion of shared/player caches; OS-cache state stays explicitly uncontrolled unless measured. |
| I6 | Are host limits active during slow intervals? Observe the unchanged workload with synchronized CPU/cgroup/memory/thermal counters. | Same GL baseline and co-tenant state; compare counter deltas over the run, not historical totals. | Rising reclaim/pressure/throttling/reset evidence supports further attribution. High temperature or allocated swap alone does not prove a frame bottleneck. |
| I7 | Does sharing materially change the game? If an existing operator-authorized window permits, pair the same baseline with one co-tenant workload state changed. | Same cache/temperature/scene, service state and restoration receipt; per-engine activity and service health. | Without controlled state change and matched conditions, report correlation only. Do not stop Frigate or another service just to complete this row. |
| I8 | Is Mesa version a reproducible factor? One supported/pinned user-space candidate versus 25.0.7 on the same Intel host. | Same kernel, engine, assets, compositor, effective settings and labelled warm caches; record actual loaded libraries and rollback identity. | A repeated gain/regression justifies that version finding. It does not attribute all remaining cost to Mesa or support a simultaneous kernel change. |
| I9 | Is display backend trading throughput for reliability? Existing X11/Weston versus Wayland/Weston only if the shutdown issue needs a bounded reproducer. | Same workload and current engine; own processes; retain cleanup evidence and watchdog-safe limits. | A forced kill is a failure, not a faster run. Throughput and clean shutdown are separate results; no physical-presentation claim from a headless compositor. |

### Green Paradise and Club field isolation

This same-day follow-up makes the user's dominant-feature hypothesis testable.
The cases below are local experiment labels inside L0/L1 and the existing
owners, not new project tracks. They are proposed experiments: none was run by
this documentation revision.

Source checked against `main` at `843f357c07af842054f3ccd6728f93beca9a57ef`,
including its flight dynamic-resolution experiment and newer Club scenery.
This refresh supersedes the earlier same-day source snapshot for these cases.
Pinned links below identify new code absent from the investigation branch's
runtime; the plan update does not merge or claim to implement that code.

**Hypotheses to distinguish:** one expensive pass/feature; several cumulative
costs or an interaction; shared ground/sky/aircraft work; an ineffective setting
or different renderer/pixel workload; CPU/driver/host pressure; and first-use
loading. Do not assume the answer must be a small visible object.

#### What Green actually removes

[Green's adapter](../../../app/landscapes/green_paradise/landscape.gd) builds a
rough plane with the shared [grass material](../../../app/render/ground.gd)
and returns an empty obstacle world. It does not build Club's field treeline,
flag/windsock/scenery birds, near vegetation or lake. Shared
[World](../../../app/render/world/world.gd), sky/sun/weather, aircraft and
aircraft-shadow paths remain. Green's logical field surfaces still feed ground
contacts; an empty obstacle inventory does not mean physics or ground vanished.

[Club](../../../app/landscapes/club_field/landscape.gd) also has a different
[ground setup](../../../app/render/field.gd): default-field photo maps/detail,
consolidated surface treatment and the horizon mesh. Ordinary Green does not
bind that same Club photo/detail path; the enhanced-grass research setting is a
separate override to record. Thus the Green/Club difference includes material,
geometry, coverage, scene and physical differences. It is a diagnostic screen,
not a one-variable speedup or a proposal to replace the principal landscape.

At the external review revision the [Club field builder](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/render/field.gd)
bound four authored pasture/hay/grazing parcels into the existing ground
draw; [worn-path materials](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/render/worn_ground_material.gd)
can copy the same data when enabled and bound (normally inactive at Low).
Green uses the shared revised shader but leaves this
[parcel count](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/render/meadow_surface.gdshaderinc)
at zero. **Meadow Off does not disable painted parcels**: it controls runway
plant colonies. Hiding Scenery after build does not undo those material bindings.
The changed [Club definition](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/data/scenery/default.json)
adds hedges, fences/gates, trees and trails. Its physical obstacle inventory also
changes through the separate collision builder; a visual object's
`collides: false` is not evidence of no physical proxy. Preserve the actual
world identity within Club tests. No source change establishes its own cost.

For a current run, include the fifth painted parcel, enclosed infield and current hedge materials in the frozen workload. Check the material bound to both turf and enabled worn shoulders. [Current field binder](../../../app/render/field.gd) · [Infield shader](../../../app/render/club_infield.gdshaderinc)

#### Cases and order

Use a qualified fixed-wing aircraft already available on the Intel installation.
Home's landscape selection, or the bridge's existing validated `catalog`/`setup`
flow, selects `green_paradise` and `club_field`. Keep the same aircraft/livery,
camera transform/FOV, lighting/weather/seed, renderer, native physics backend,
output/drawable/internal pixels, AA, frame cap/VSync and observer state. Record
the actual returned selection. The [tool owner](../../../tools/debug/README.md#agents-and-mcp-pt1h-r11)
owns command syntax; no new launcher or copied scenario framework is required.

Use an admitted campaign-owned isolated profile initialized with the declared
baseline where supported, with profile/cache identity recorded. Home/bridge
setup is persistent: landscape, aircraft/start/livery and related choices can
be saved, and selecting a time preset can clear an explicit lighting override.
If the existing profile is used, retain requested/effective values and ownership
for every affected selection, including custom lighting/weather and graphics,
then restore and verify them at campaign end through the owning paths. Preserve
intervening user changes instead of blindly overwriting a file. Record a failed
or conflicted restore and complete normal owned-session cleanup. Returning to
the previous landscape alone is not full preference restoration.

| Case | Procedure | What the result can decide |
| --- | --- | --- |
| G0 — inventory | On the admitted existing Intel session, record current effective settings, scene root, active geometry families, material bindings and secondary targets before changing anything. Set/read back experimental flight dynamic resolution Off and verify fixed scale in active flight. Identify switches already Off, absent or unsupported. | A usable target list; no timing claim. Do not test an imaginary `@trees` or `@reflections` switch. Record patched/stock engine support separately from old bridge GPU timings. |
| G1 — warmed Home screen | Visit Green, Club, then Green with the same parked aircraft and matched view. Warm each rebuilt world separately and record loading outside steady sampling. If a difference or order effect appears, counterbalance with Club → Green → Club in a matched later/interleaved run. | A repeatable Club cost or shared cost to investigate; not a feature attribution. Home has no flight simulation and uses a fixed shader clock, so this cannot exclude live animation costs. |
| G2 — matched airborne screen | Repeat as a separate pilot-view population, selecting airborne on both landscapes. Match initial state/view and accepted-time windows; keep away from differing contacts/obstacles. Record actual physical identities rather than calling them equal. | Whether the Home difference also occurs in the relevant flight view. Do not compare Club runway idle with Green airborne flight. |
| G3 — same-Club removal | Return to one fixed Club workload. Screen one active family/leaf or existing setting at a time: baseline A, changed state B, restored A. Start with the highest explanatory value from G1/G2 and the suspect matrix below. | A candidate contributor under that view. Preserve physical scene, other settings and ownership; visible masks are temporary diagnostic changes. |
| G4 — selective add-back / interaction | If G3 leaves a compound group unresolved or suggests cumulative/interacting costs despite small individual changes, create a reversible visual mask within the same Club world, then restore one family at a time against that same masked reference. Alternatively test only the two strongest candidates in the four On/Off combinations. | Cumulative/interaction evidence. This is not adding Club assets to Green or removing contacts; a grouped mask may require the bounded hook below. Do not sum individual hide deltas. |
| G5 — live confirmation | Repeat the selected candidate with accepted time advancing, matched wind/flight/camera and the same observation windows. Preserve the 240 Hz clock. Compare visible drawing and owner scheduling separately where needed. | Whether a frozen/static lead survives real motion. A paused screen cannot exonerate wind integration, birds, projected-mask refresh or other live CPU/GPU work. |
| G6 — product candidate | Restore all diagnostic masks, implement one bounded optimization/quality choice, and run the existing paired affected-workload and visual gates below. | A qualified change only when the evidence passes. Retain failed/incomplete attempts and rerank if the candidate does not help. |

**Home scale is a confound to resolve, not merely log once.** Its existing budget
can change scale after a landscape rebuild. For attribution, establish and
verify equal, stable effective scale throughout each window through the existing
owner; never fight it with a second continuous writer. There is no documented
public debug command to freeze this budget. If the current route cannot hold
it or match a stable state, mark the Home comparison inconclusive and use the
matched flight screen, or add a bounded reversible diagnostic hold to that
owner. Test production adaptation separately after attribution.

**Flight scale also needs an explicit owner check.** On current main a fresh eligible profile can request 30 FPS automatically when the renderer supports completed GPU timing. Compatibility/OpenGL uses fixed scale. For G0–G5 explicitly select Off, record the actual viewport scale throughout each window and restore the player's prior choice. Label dimensions calculated from the scalar as estimates until observed. [Current controller and defaults](../../plans/dynamic-resolution.md)

Do not run `@half_res` against an active flight controller. Both write the same
scale. A frozen ablation also suspends flight and can restore the controller's
ceiling, with a new evidence window on resume. Probe and controller restoration
can therefore change the intended A/B state. Disable adaptation first, inspect
scale/status after each phase, and reject ownership conflicts. Test adaptive
production behavior separately after fixed attribution through its
[existing owner](../../plans/dynamic-resolution.md).

The normal Home path loads saved preferences. A direct `--scripted` launch is a
different technical route and bypasses that first-run settings initialization.
It is usable only with an explicit matching configuration receipt; do not call
it the product's Automatic behavior. Switching landscape rebuilds Home and may
change the allowed start, cache state, residency and camera composition.

For a short airborne GOD TEST comparison, the current
[catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/tools/godtest/catalog.py)
supports the `green-paradise` case's `recover` phase with an airborne start and
either `green_paradise` or `club_field` landscape override. Reuse that case;
the named `performance-tour` requires Club and its runway/landmark phases
cannot simply be applied to Green. The
[operating guide](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/tools/godtest/PERFORMANCE_TOUR.md)
and [CLI help/parser](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/tools/godtest/godtest.py)
own syntax for `--dynamic-resolution-fps`, `--render-scale`, `--landscape` and
`--scene-detail`. Set Off (`0`), the same fixed scale and Low explicitly when
that is the declared baseline: an explicit scale overrides Automatic's scale,
and the harness seeds scene detail independently. Use separate fresh outputs.
This small case does not enable `require_native`, frame watching or hardware
monitoring by default, and the CLI has no `--require-native` flag. Selecting it
alone therefore does not enforce the tour's native backend/evidence contract.
Verify the actual native receipt and collect the required diagnostic evidence
through the admitted route; use a validated owned manifest when that route
needs the existing manifest-only fields. Missing tour-level monitoring does
not block a supported initial screen or turn it into full-tour acceptance.
The harness verifies the requested bilinear scale at the start/end of completed
pilot phases, not uninterrupted internal allocation. Check actual trajectories
and camera geometry before treating two closed-loop phases as paired. A direct
scripted route, this isolated harness and the saved product profile retain
distinct configuration receipts.

For G5, use an available repeatable/adaptive flown route or matched starting
states inside Club. Predeclare acceptable trajectory, accepted-time and camera
matching limits and record actual pose, inputs and clock; classify nonmatching
runs as leads only. An unfrozen A–B–A command does not automatically produce a
matched moving-flight comparison. Current [GOD TEST](../../../tools/godtest/README.md)
still lists fixed-input-tape rendered replay as pending, and
[numerical flight-log replay](../../FLIGHT-LOGGING.md) does not reproduce the
camera, smoke and sound presentation. Do not assume an existing rendered-tape
runner or exact cross-landscape replay equivalence. New replay tooling is not
a prerequisite for the initial screens.

#### Source-informed suspects and discriminating tests

The priority below is the value of the next test, not a measured cost ranking.
Discover literal runtime paths from the current scene; source names illustrate
families and do not authorize assuming a target exists.

| Suspect / when to prioritize | Existing discriminating control | Required split or limitation |
| --- | --- | --- |
| **Ground and broad pixel work — first screen**, especially ground-heavy Home or slow Green | Existing Native scale controls; the probe's `@half_res`; a discovered rough-ground node for a visual hide screen. Then a same-geometry diagnostic material if ground remains actionable. | At effective 75%, half-current-scale is 37.5% of native per axis, about 720×405 at 1080p. It is not 50% native or a quality recommendation. Hiding ground exposes sky and removes dependent reception; a same-geometry simple material is the stronger follow-up. |
| **Sky, sun and lens work — high explanatory value if Green remains slow** | Compare matched ground-facing and sky-facing orientations as a broad coverage screen; reuse existing Lens Off/effect choices. The probe has `@fog`/`@glow` for enabled Environment properties. | Split visible sky/cloud material, radiance refresh, directional-light shadow casting and lens/glare/afterimage. `@fog`, `@glow`, or hiding the Sun node is not a complete sky-off experiment. A cheap replacement sky or radiance-scheduling isolate is a proposed owned hook, not an existing flag. |
| **Trees, woods and decorative vegetation — prioritize if Club adds a repeatable cost** | Census field cards/detail plus separately built scenery/woodland; hide each discovered family, then isolate a relevant subset or density change. | `Field/treeline` and conditional `treelineDetail` are not all trees. `ImportedVegetationBatches` can include other vegetation. Technical `--hide_treeline` is partial; tree-wind Off affects imported animation, not all trees or drawing. More batches can add CPU/draw cost. |
| **New Club hedge, fences/gates and property batches — if the refreshed Club regresses** | Inventory the imported perimeter hedge, added trees, shared prop cells and worn access/stock trails separately; use discovered masks as coarse screens. | Additional trees are in imported vegetation batches, not the field treeline. Fences/gates share prop cells with other content; hiding a cell is not a fence-only result. Separate projected/contact owners and preserve the installed collision proxies. |
| **Painted pasture/hay/grazing parcels — a Club-specific material question** | A bounded reversible same-geometry material test that disables only the bound parcel work, covering the ground and any worn-path material that copies its uniforms. | Meadow Off and Scenery visibility do not disable this path. Green's default parcel count is zero. The extent/edge/noise work is a source suspect, not a measured regression; a missing material hook leaves it unisolated. |
| **Projected aircraft/windsock shadows — active auxiliary-work suspect** | Inspect per-target sizes/AA/update modes; screen the actual projector or receiver. Existing shadow settings and `@subviewports` can supply bounded leads. | Main `@msaa` does not control aircraft-mask 256²/4× AA; moving socks use a separate 512² mask. Hiding a receiver/caster is not equivalent to suppressing owner scheduling. Owners can re-enable a SubViewport; a held-state failure is inconclusive. Preserve the height cue in the eventual product. |
| **Native shadows — only when actually enabled** | `@shadows` toggles visible Light3D shadow casting. | It does not disable projected/contact/cloud shadows. The technical field-projector Off option falls back to legacy contact shadows; it is not “all shadows off.” Avoid counting an already-off baseline feature as a gain. |
| **Water and reflections — lake-visible or refresh-related case** | Discover Water and its separate ReflectionProbe; screen water drawing and probe work independently. Inspect actual planar-path reachability. | Hiding Water leaves the sibling probe's update logic; a ReflectionProbe is not a SubViewport. Stock Intel planar reflection is already Off. `--lake=off` changes the world/terrain context and cannot qualify a same-scenario rendering gain. A probe-scheduling isolate needs an owned hook if current controls cannot hold it. |
| **Windsock versus flag — quick separate witnesses, not one flag switch** | The default windsock cue and seeded flag cloth are separate nodes. Existing Flag animation Static tests its motion model; a leaf hide tests visible work. | Low Auto flags still resolve to Basic. Static keeps the mesh and some publication work and does not affect windsock. Hiding cues leaves cached field subscriptions; windsock hide can also suppress its silhouette. Inspect cloth/cue draw, CPU integration and shadow scheduling separately. |
| **Birds — test when present and live** | Existing Birds Off/Few/Normal/Many; verify live departure completes. Player Off before construction still allocates bird groups/buffers, initially with no birds visible. A separately matched technical `scenery_birds` construction switch can test avoiding the node, with its route/configuration recorded. | Green has no Club scenery birds. Live Off retains the node and polling; the fresh weak-GPU bundle selects Few, not Off. Frozen/Home observations cannot exclude live bird work. Technical no-build and player Off are distinct lifecycle experiments. |
| **Other scenery, HUD and effects — residual or stage-specific** | Existing lens/lighting/overlay controls, discovered groups and `@canvas`; inspect draw/CPU changes only for active consumers. | Whole Field/Scenery/Motion/Canvas hides change many systems and coverage. They select a family to split; they do not identify one object. Current scenery Off can remove physical scenery/lake; use visual masks for same-Club attribution. |

Sources: [field construction](../../../app/render/field.gd),
[scenery and birds](../../../app/scenery/scenery.gd),
[flag quality](../../../app/render/flag_quality.gd),
[flag runtime](../../../app/render/flag.gd),
[projected targets](../../../app/render/projected_shadow.gd),
[field target policy](../../../app/render/field_projected_shadows.gd),
[lake probe owner](../../../app/render/lake/lake_reflection.gd),
[water/probe construction](../../../app/render/lake/lake_terrain.gd),
[water material](../../../app/render/lake/water.gdshader),
[render probe](../../../app/debug/render_probe.gd), refreshed
[scenery batches](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/scenery/scenery.gd),
[hedge builder](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/scenery/imported_hedge.gd),
[trail geometry](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/scenery/ground_features.gd) and
[physical proxies](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/scenery/collision_world.gd).
Current Scene Detail keeps
collidable placements across tiers, but changes several visual/LOD fields and
therefore is not a single-feature isolation.

#### Use the existing tools without overstating their result

The [render-cost reference](../../../tools/debug/README.md#render-cost-pt1h-r9)
owns syntax and limits. `layers` inventories geometry/light descendants below
the active camera's scene root; use `find`/inspection for hidden or nongeometry
owners such as ReflectionProbe. `layers` can descend to eight levels, while
automatic `ablate` selection stops at four and caps its target list. Explicit
paths can identify deeper nodes. Prefer a small explicit target list after
discovery; absent, hidden, already-off and truncated targets are not negative
performance results.

The complete existing feature-key set is `@shadows`, `@fog`, `@glow`, `@msaa`,
`@half_res`, `@subviewports` and `@canvas`. There are no semantic `@trees`,
`@flag`, `@windsock`, `@birds`, `@water`, `@reflections`, `@sun` or `@sky` keys.
Other targets are literal Node3D paths relative to the reported root.

Existing `ablate` supplies interleaved A–B–A visibility/property screens and
attempts restoration. Its default ten warmup and sixty sample **frames** are
short diagnostics, not the time-based acceptance protocol. `freeze=true`
acquires only a flight simulation hold; Home has no such session, and camera
or visuals can still change. A live-motion question requires an explicit
unfrozen matched run. Respect controller/focus/hold refusals; do not force
resumption or disconnect a player's device to make the probe pass.

Inspect `skipped`, `skipped_reasons`, `truncated`, `overridden` and pause/target
restoration. A runtime owner can overwrite the probe's temporary value.
The target list is a discovery snapshot; newly created nodes/targets or a
currently disabled target that later schedules work may escape it. Recheck
the affected family during the window before claiming it was completely Off.
Restoration preserves intervening owner writes, so a successful command alone
does not prove the original workload was restored. Verify configuration,
visibility, targets, camera, pause and physical identity before the next case;
abandon an interrupted comparison without deleting its evidence.

The bridge's GPU observations remain delayed last readings with **unverified
freshness**. Real `ablate` rows are not a statistically significant GPU-cost ranking. Root
and secondary readings are separate and cannot be summed into current total
GPU time. Keep wall/process distributions, root render CPU, draw/primitive
counts, memory and any supported synchronized GPU observations. A repeatable
whole-frame change supports a contributor in that workload; it does not by
itself distinguish GPU shading from CPU submission or driver cost.

The new [completed-frame engine contract](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/tools/graphics/dynamic_resolution/README.md)
is separate: supported opt-in Vulkan/Metal 3 sampling returns a frame ID,
configuration generation, recording time, GPU duration and input/output sizes.
Its duration covers the viewport draw through its render target, excluding
presentation and other viewports. The controller checks freshness, order and
dimensions; the old bridge getter was not replaced. GOD TEST currently records
controller status changes and completed-frame identity/sizes, not a stream of
those fresh GPU durations. Do not infer pass or presentation timing from the
ordinary report or call the patch available on Compatibility.

The retained [Primis UHD 630 synthetic screen](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/docs/research/visual-quality-implementation/VQ-07/dynamic-resolution-primis-2026-11-22.md)
reported pixel sensitivity on a patched Mobile/Vulkan shader workload and a
virtual output. It is prior evidence, not a run by this audit or native-physics
flight/readability/presentation qualification. The product baseline remains
Compatibility at 75%; it has no supported feedback or range below the
experiment's 75% floor. A later patched Mobile candidate on the existing Intel
requires its own matched evidence and does not replace the fixed baseline.

Use the existing [frame recorder/watch](../../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15)
for time-based windows and raw intervals. A `frames` export is a snapshot of
past samples, not a command that runs the next measurement. Establish window
boundaries, reproduce the condition, then export; keep query/capture overhead
outside timed windows and observer ownership/cadence matched. If phase-to-sample
correlation is not available, add bounded phase markers to the existing tool
before making per-phase frame claims. Do not create a second profiler.

#### Removal, add-back and interpretation

A hide is a **net workload perturbation**, not a pure upper bound on an object's
cost. It may stop dependent passes, expose costly background, change overdraw
or leave CPU updates/allocations intact. A negative or slower hide therefore
does not prove that feature is free. Split drawing, owner scheduling and
construction-time allocation when the lead survives restoration and repeats.

For G4, restore the same masked reference between single-family additions.
If cumulative add-back is useful, reverse its order to expose order/cache
effects. For only the two strongest candidates X/Y, compare both On, X Off,
Y Off and both Off with interleaved full baselines. The frame-time contrast
`T11 - T01 - T10 + T00` can reveal an interaction beyond paired variation; it
does not assign additive percentages to the features. Avoid an exhaustive
matrix of every switch.

If Green remains slow, examine shared paths and actual configuration. If only
Club is slow, split Club families and its ground differences. If the return to
Green stays slow, investigate residency, compilation, ownership or host drift
before attributing the change to Club geometry. If the issue appears only with
motion, follow G5. If only cold entry fails, use I5/L3. A missing target,
overwritten state, unstable scale/camera or failed restoration makes that
comparison inconclusive, not a clean negative. Unavailable or freshness-unverified
GPU timing leaves GPU-specific/pass attribution inconclusive; a well-controlled,
repeated wall/process comparison can still establish a whole-workload contributor
with its CPU/GPU mechanism unresolved.

**Bounded missing hooks, only when required by a selected case:** reversible
semantic masks for all members of a visual family; separate draw/update
suppression for projected cues, flag/windsock and water/probe owners; a cheap
same-geometry ground/sky variant (including ground/worn parcel bindings if
selected); Home-budget hold and phase markers. Reuse
existing owners and debug infrastructure. Each hook must distinguish hidden,
unscheduled and never-created work, retain the installed physical world and
accepted clock, report whether it stayed applied, and restore on completion,
cancel, timeout, scene exit or disconnect. Mark it proposed until implemented
and checked; no undocumented flag is assumed to exist.

For each case retain source/native/engine identity, landscape/field/physical
hash, actual graphics state, camera/pose, accepted-time/wind state, target and
affected owners, lifecycle mode, A/B/restored-A intervals, observer/cache state,
draw/target activity, peak/retained memory, faults and restoration result.
Pre/post images are outside timed windows. Keep “inactive”, “no useful change”,
“candidate”, “interaction”, “overridden” and “unavailable” as distinct outcomes.
Diagnostic masks never become default quality settings without G6's product
and readability checks.

The method is consistent with [Godot's GPU-bottleneck guidance](https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html)
and [Intel's render-state experiments](https://www.intel.com/content/www/us/en/docs/gpa/user-guide/2025-1/run-render-state-experiments-with-frame-analyzer.html).
Those sources motivate controlled changes to pixel, material and draw work;
they do not establish that Intel GPA supports or is installed on this
Linux/OpenGL route. Existing project tools remain the first implementation.

### Pairing and acceptance

For fixed-view diagnostics, establish a warm stable reference, alternate A/B
order in at least three paired blocks, and return to the reference between
candidates. Retain all repeats, including failed or incomplete attempts. Use
time-based windows appropriate to the low frame rate, not a few favorable
frames. The bridge's existing `ablate` already uses A–B–A and restoration;
its unverified GPU deltas are deliberately not ranked or called significant.

For a promising product candidate, first run matched affected-view comparisons
on the same admitted host. Follow the [owning gate](../../plans/global-performance-visual-quality.md#gates-to-freeze-in-vq-01c):
at least three alternating pairs, 10 s warmup and 60 s measurement, or a stricter
applicable requirement. Expand to the complete three-aircraft tour only when
the whole-session scope or final claim requires it. Preserve native backend,
240 Hz physics, physical route and output targets. Compare phase p50/p95/p99,
longest stalls, time above 33/50/100 ms, sim/wall pace, memory and clean shutdown.
Inspect run distributions before pooling; correlated frames are not independent
experiments. Gain must exceed paired variability and reach the existing 5%
complete-affected-workload gate, or remove a named reproducible hitch/memory
defect, with no repeatable harmful tradeoff. Keep visual/presentation and formal
coverage evidence separate.

Twenty FPS is only the ideal catch-up floor for 12 steps/frame at 240 Hz.
Successful circuits should preserve sim/wall near 1 with no sustained slowdown;
startup/menu validity and the existing phase/coverage validators remain gates.
Do not relax them to turn an ineligible first Home into a pass. A cap/VSync
player-pacing campaign is separate from the uncapped capacity baseline.
The corrected plan's proposed 30-FPS usability checkpoint does not replace the
existing 60-Hz product or physical-presentation gates.

The main [investigation](2026-11-22-intel-gpu-investigation.md) distinguishes
observed outcomes, hypotheses and current code. This protocol creates no
runtime toggle, renderer default, driver setting, cache deletion or host change.

## 4. GitHub and offline verification scope

GitHub can check source contracts, plan expansion, metadata validation,
regression fixtures and documentation. The current CI's software-rendered
visual lanes cannot establish UHD 630 frame time, memory pressure, thermal
behavior or presentation. Preserve those gates; do not rename a CI capture
as Intel performance evidence.

Use [GOD TEST report/compare](../../../tools/godtest/README.md) and
[`frame_diagnose.py`](../../../research/performance/frame_diagnose.py) for their
own artifact formats. Do not feed tour output to the legacy reducer without
checking its schema. Do not run the older
[`graphics_ladder/ladder.py`](../../../research/performance/graphics_ladder/ladder.py)
unchanged on Linux: its documented implementation covers macOS and
Windows/NVIDIA and takes the non-Windows path as macOS.

Before accepting a new evidence bundle, recover the exact engine logs,
`execution.json`, manifest/frozen-source identity, graphics identity, frame
stream, phase/incident streams, CPU/GPU samples and ownership/cleanup receipts
defined in the tour guide. Hash the real files, preserve failures, and rebuild
reports from those files. A narrative's “valid” label or a screenshot of FPS
cannot replace that process.
