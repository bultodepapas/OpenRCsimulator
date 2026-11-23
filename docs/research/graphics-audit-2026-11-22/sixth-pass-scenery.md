# Sixth pass: residual scenery construction and disabled-feature lifetime

Source: main `85a2475f60029a4b6b09f23f643119bceea84a45`. This pass inspects existing guards and residual construction. No current scene-build time, GPU residency or FPS gain is measured here. Counts describe source operations and logical data, not driver uploads or draws.

## W04 — stars still materialize thousands of records after the catalogue cache

### Reachability and work

The world builds stars when it has a nonempty time-of-day state and either time is flowing or solar elevation is below 2 degrees. Explicit lighting can disable that state. A live refresh reuses a valid existing star node; stars are not rebuilt on every appearance edit or frame. The staged world builder still executes the whole sky stage between checkpoints. [World sky stage](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/world.gd#L508-L529), [refresh and reuse](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/world.gd#L683-L739).

The existing content-keyed cache retains the parsed intrinsic catalogue. Each fresh `Stars.build` still reads the source, transforms the direction of each star, appends a `{dir, colour, flux}` dictionary, and issues three MultiMesh instance setters per star. The shipped catalogue contains 5,080 stars:

| Residual operation | Count per successful fresh build |
| --- | ---: |
| Placement dictionary and basis transform | 5,080 each |
| Transform/color/custom-data setter calls | 15,240 total |
| Float32 instance-buffer values | 101,600 |
| Logical full-buffer payload | 406,400 bytes, about 397 KiB |

This is **one MultiMesh**, not 15,240 draws. Sources: [builder and placements](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/stars.gd#L87-L156), [catalogue-count check](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/tests/test_world_stars.gd#L57-L64), [existing rendered buffer check](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/research/performance/stars_build_probe.gd#L56-L70).

### Prior work and native experiment

FW-24-R1 already implemented the catalogue cache. Its historical Windows 5900X/RTX 3090, Godot 4.7.2 Compatibility experiment reported warm whole-component medians of process medians of 16.618 ms before and 8.140 ms after caching. Shared-host load/caches were uncontrolled; these are neither the current source nor an old integrated GPU result. The remaining 8.140 ms cannot be assigned to the setter boundary. External A24's below-horizon shader and frozen-date orientation work is a separate issue. [Historical cache evidence](../visual-quality-implementation/VQ-01c/loading/stars/README.md).

First attribute current file read, cache lookup, placement materialization, resource creation and setter work. If material, compare a compact native producer that returns the existing 20-float-per-instance layout and uses the engine's whole-buffer setter. Preserve per-world ownership of mesh, materials and MultiMesh; cache immutable prepared data only under the actual source identity. Godot documents a native producer plus a single linear buffer assignment as an available batching path. [Official MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

A scripted packed-buffer control is necessary: naively replacing 15,240 engine setters with 101,600 GDScript scalar assignments may lose. C++ also pays extraction, validation, copying and ownership costs. The existing probe is a **GDScript probe running with a real rendered Godot backend**; it is not an existing native batch producer or proof that this proposed batch wins.

Preserve actual Transform3D/Color float32 packing, order, directions, luminosity, world latitude/LST, cloud/shader inputs, same-length source edits and independent world resources. Preserve current malformed-data behavior: the loader checks JSON/container/format but does not fully validate every row. Do not imply arbitrary malformed rows already recover cleanly. Keep public `placements()` behavior and a supported fallback. Compare buffers on a real renderer; dummy/headless buffer readback is insufficient. Reuse the existing stars probe and world-star, Moon-edit, presentation-refresh/context and staged-build tests, extending them to the proposed bulk boundary. Measure complete first-presented sky and cold/warm world loading, not only the isolated builder.

## Lower-priority disabled-feature leads

### Campfire Off: eager resource construction, with animation already guarded

Default fields build the static hearth and its campfire owner even when the independent flame preference is Off. Loading the script preloads the flame atlas; construction creates five sprites with materials, an eight-slot ember MultiMesh and a shadowless OmniLight before hiding them. The permanent hearth/collision must remain. [World construction](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/world.gd#L543-L585), [effect construction](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/campfire.gd#L59-L156).

FW-67–74 already delivered the disabled-frame animation guard and immediate catch-up on enable. `configure(false)` still applies exposure/light setup once; Off does not imply zero lifecycle writes. [Existing repair](../field-world/FW-67-74/README.md), [current frame guard](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/world/campfire.gd#L183-L208).

The remaining hypothesis is never-enabled construction/residency: defer effect resources and the atlas's preload path until first enable, then retain them across subsequent toggles. Measure before changing the existing eager-node contract. This may only shift cost into the first visible settings transition. Current tests require hidden nodes, stable counts/reuse and immediate application of the latest clock, wind, exposure and lighting. Compare initial Off/On, repeated toggles, pause, world restore/free and first drawn effects. Asset manifest bytes do not establish imported texture format, sharing or actual RAM/VRAM.

### Birds Off: distinguish the technical no-build switch from visual departures

The technical `scenery_birds=off` already skips construction. The live bird-density preference can instead construct the layer with zero visible instances. Shipped data contains 39 birds in two groups; settled Off can scan those 39 state entries looking for pending transitions. At 60 actual callbacks/s that is 2,340 simple visits/s, not evidence of a material bottleneck. Initial hidden rows get no instance transform/custom-data setters. On→Off intentionally lets visible birds depart before settling; removing the owner would break departure and re-enable behavior. [Build eligibility](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/scenery/scenery.gd#L441-L465), [runtime polling](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/scenery/birds/birds_runtime.gd#L34-L70), [pending scan](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/scenery/birds.gd#L177-L182).

SC-BIRD-08 already optimized validation and reports older loaded-machine headless build times around 11–15 ms, polling around 4 microseconds/frame and lighting commits around 80 microseconds. Those are not current Off-path or target-hardware measurements, but they argue against presenting 39 visits as a large discovery. [Prior evidence](../scenery-implementation/SC-BIRD-08/README.md).

Only investigate deferred initially-Off geometry if construction/residency matters in a real profile. Preserve the lightweight preference/conditions owner, current sun/cloud state, departure/reversal rules, frozen/wrapping clocks and invalid-source behavior. The existing bird benchmark builds before its timed frame loop; it does not measure creation or first-enable latency. Use the scenery builder's existing construction timing plus explicit first-enable/first-draw spans, then compare actual presented frames.

## Screened paths with no new material finding

Flags use a field-owned cue list, skip unnecessary wind queries through `needs_wind`, publish only changed motion revisions, and throttle detailed projected-size checks. Explicit Static drops the motion object; Auto at Low means Basic, not Static. Windsocks reuse fixed topology/handles and reject repeated timestamps. People gaze already has quality, cadence and dirty-write guards. Upstream position-array preparation can still occur without a gaze owner, but with the default-disabled companion fleet and its bounded count this is a small attribution lead. [Field observation](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/field.gd#L449-L477), [flag guards](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/flag.gd#L148-L239), [existing cadence decisions](../../plans/optimization-priorities.md).

Ambience synthesis already has a bounded cache and documented concurrent-cold/exit behavior. The prior passes own grass culling, skyline/glare, shadows, light buffers, lake/reflection, rain first-use and wind preparation. This pass does not reclassify those as new opportunities. Keep sustained frame cost, one-time hitches and retained memory separate when prioritizing old hardware.
