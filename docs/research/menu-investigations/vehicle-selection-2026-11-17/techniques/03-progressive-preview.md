# T03 — Progressive presentation with a separate lightweight preview

**Decision:** immediate named thumbnails are core UX; a separate 3D proxy is a conditional UI-VS-04/09 experiment. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

Can the player inspect the correct vehicle promptly while a more detailed representation is still being prepared?

Queries used included `site:github.com/KhronosGroup/glTF MSFT_lod progressively loaded levels of detail materials` and `site:doc.babylonjs.com glTF progressive loading MSFT_lod onReady onComplete`. Useful terms are **progressive loading**, **first meaningful preview**, **proxy asset**, and **render LOD versus load granularity**.

## Primary evidence and transfer limits

The [Khronos-hosted MSFT_lod specification](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Vendor/MSFT_lod/README.md) describes loading lower-detail representations before higher ones and identifies Babylon.js as an implementation. [Babylon's loader API](https://doc.babylonjs.com/typedoc/classes/BABYLON.GLTFFileLoader) exposes a maximum LOD count starting from the lowest. Accessed 2026-11-17. This supports the design pattern, not a claim that Godot/OpenRC implements that extension.

The pinned engine's [built-in extension registry](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/gltf/gltf_document.cpp#L7008-L7027) does not list MSFT_lod directly, and OpenRC's [Creator preflight](../../../../../app/workshop/creator/glb_preflight.gd#L234-L251) admits only its explicit extension subset. This proposal uses independently generated accepted assets, not an unsupported import switch.

## Application to OpenRC

Define three observable levels: metadata/skin thumbnail; optional lightweight 3D preview; requested full-detail preview. They retain one source-qualified vehicle/skin identity but have different readiness labels. A thumbnail or proxy never satisfies the full-detail performance endpoint.

For one measured expensive model, generate a small menu-only asset through the model owner's pipeline. Preserve silhouette, selected skin, overall dimensions, neutral pose and stable camera framing. Remove only presentation-irrelevant detail approved by that owner. The proxy contains no simulation authority and is never handed to flight as an accepted physical model.

Give the proxy an independent file and explicit dependency closure. Loading the full GLB and then simplifying it does not avoid that initial load. Referencing an original full-resolution texture prevents assuming a small texture closure or lower residency, although reduced geometry or a shared already-resident texture could still help; measure the complete cold and warm paths. Its descriptor must identify source geometry, appearance, recipe and quality tier. A missing skin mapping falls back to the correct static thumbnail, not another livery.

Explicit selected activation queues the full preview, admitted through the existing safety gate and memory reservation; only a still-selected generation may refine. Focus/hover alone remains thumbnail-only unless separately admitted prediction justifies a lightweight tier. A memory/failure fallback can retain a clearly labeled thumbnail or proxy, but does not satisfy the full-ready gate. Explicit launch can proceed through the activity's normal validated path. An old refinement completion cannot replace a newer selection.

Atomically swap the validated, still-current full candidate once construction is complete, then mark detailed readiness only after observing its requested visible frame. Any offscreen warmup is a separate T19 experiment and does not count as that visible endpoint. A fade is optional presentation, has no minimum duration, and must not extend acceptance latency. Include simultaneous thumbnail/proxy/full resources in the transition budget; a crossfade can increase peak residency.

## Counterexample and risks

For already-fast small models, loading two 3D representations can increase both total work and memory. A visibly inaccurate proxy can mislead skin selection. Embedded distance LODs inside an eagerly imported asset can improve rendering without reducing file reads, decoding or creation. Separate the proxy experiment from texture residency (T17) and geometry encoding (T18).

## Experiment and decision gate

Compare thumbnail→full with thumbnail→proxy→full for the same heavy stock asset, with and without immediate Fly. Record time to correct thumbnail, first proxy draw, full requested draw, cumulative CPU/I/O, memory overlap, first-use shader cost and launch readiness. Include rapidly abandoning the selection.

Accept the proxy only if it provides useful earlier inspection without unacceptable additional full-ready/launch cost or misleading appearance. Reject it when the extra tier mostly duplicates work. The static-thumbnail route remains the simple baseline and low-memory fallback.

**Plan impact:** UI-VS-04/09 can trial one separately loadable preview tier after attribution; UI-VS-01 must label representation readiness without changing selected identity.
