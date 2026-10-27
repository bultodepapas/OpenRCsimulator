# RC smoke: retained qualification gates

Checked 2026-10-20 · Prefix **SM-**. This document retains acceptance gates for the SM-00…15 baseline. The [SM-16–25 master execution plan](../SMOKE_SYSTEM_MASTER_PLAN.md) owns the current overhaul sequence; its work is not complete merely because runtime code is integrated. [Current behavior and authoring](SMOKE.md), [Workshop profiles](AIRCRAFT-WORKSHOP.md), [commands](../tools/smoke/README.md) and [AE-24 evidence](research/aircraft-editor/AE-24/README.md) have separate homes. The [SM-16–23 evidence record](research/smoke-investigations/SM-16-23/README.md) owns overhaul receipts and remaining limitations.

SM owns `app/render/smoke/`, optional model exhaust interfaces, smoke AUX/assignment integration, smoke tests and `tools/smoke/`. AE owns editor/profile work, AS generated attachment bindings, M5 weather and FUEL admitted fluid inventory/consumption. Coordinate shared interfaces through the [ownership registry](README.md#tracks-plans-and-step-ids).

## Remaining SM-00…09 acceptance

| Step | Open work / required evidence |
| --- | --- |
| SM-00/01 | Qualify other GPU/OS backends and each new installation's authored outlet. The original Windows/RTX 3090 campaign does not qualify another backend or aircraft. |
| SM-02 | The shared stock/profile service reads accepted source observations. Complete cut/depletion/windmilling/restart and fractional presented-time alignment qualification. The retained `--smoke-backend=legacy` comparison path still uses its historical RPM/load proxies; do not treat that comparison as source-latch evidence. Physical emissions/temperature/mixture calibration stays a measurement gate. |
| SM-03/04 | Real-radio/SDL mapping and reconnection review; fake-device passes do not close hardware acceptance. |
| SM-05/06 | Current-source rendered flight/night/intersection review and pilot/target-display acceptance. Preserve explicit fixture labels and comparable views. |
| SM-07/08 | Fresh packages on supported platforms, long native memory soak and isolated target-GPU cost. Bounded allocations and capped desktop timings are not those results. |
| SM-09 | Preserve shared wind/time and off-camera aging through changes. Spatial wake/thermal/damage effects require separate mechanisms and evidence. |

Retain legacy reruns in the [original evidence record](research/smoke-investigations/SM-00-09/README.md); record overhaul reruns/failures in [SM-16–23](research/smoke-investigations/SM-16-23/README.md). Smoke changes must preserve physical state/trace parity; do not re-record golden flights for a presentation change.

<a id="future-user-customization--proposed-sm-10-onward"></a>
<a id="user-customization--sm-10-onward"></a>

## Delivered SM-10…15 baseline and retained gates

The [Workshop guide](AIRCRAFT-WORKSHOP.md#supported-adjustments) owns editing; [SMOKE](SMOKE.md) owns current v2 fields, companion v3 outlets, immutable migration, cached transforms and allocation. The integrated service permits eight authored outlets with four enabled in any source/show mix and at most 768 particles total. It replaces the legacy pool; `--smoke-backend=legacy` is retained for comparison pending native acceptance. Stop emission and explicit plume fitting extend the preview. Cross-platform, dense-overlap, long soak, measured scene cost and physical emissions acceptance remain open.

Keep source-coupled engine exhaust separate from a user-requested show effect. Engine exhaust follows a supported, authored outlet and the engine's operating state. A colored or wingtip/tail show plume is a presentation choice; it does not assert engine exhaust, fuel chemistry, smoke-fluid inventory, or a physical smoke system. Visual profiles leave mass, forces, controls, flight state and physical trace values unchanged. A future installed smoke-fluid system needs the separate FUEL contract.

Implemented presets include **Classic Exhaust**, **Twin Ribbons**, **Tail Comet** and **Rainbow Burst**. Their tints are display choices. A tail-end slot is distinct from a tail surface; expose only model-authored mounts and never infer one from the origin. Coordinate with [AE's presentation contract](plans/aircraft-editor.md#55-accepted-presentation-contract-and-remaining-work); AE owns editing/profile, [AS owns bindings](plans/aircraft-standardization.md#workbench-customization-bindings), and SM owns rendering/scheduling.

Use precise, friendly labels instead of an unexplained “duration” or “volume” control:

| Setting | Meaning |
| --- | --- |
| **Puff lifetime** | How long each emitted puff exists before it fades. It does not control how long new puffs are emitted. |
| **Burst duration** | How long a one-shot request emits new puffs. Existing puffs continue through their own lifetime after the burst ends. |
| **Trail persistence / length** | How far the visible wake remains behind the aircraft. It emerges from speed, puff lifetime, emission spacing and wind; it is not the same as burst duration. Any length target is approximate and view-dependent. |
| **Density / emission rate** | V2 separates an optical fullness proxy from requested puffs/s, capped by resolved allocation. V1 amount remains historical compatibility data. Neither field is smoke mass or fluid flow. Width, lifetime and wind still affect the resulting trail. |
| **Resource endurance** | Time supported by a real smoke-fluid supply and consumption model. This is not implemented and must not be presented as a tank, remaining quantity, refill or endurance until an admitted smoke-fluid law and qualified aircraft inventory define its source, units and draw-down under the [fuel standard](FUEL-SYSTEM.md). Shared finite-fuel support does not enable smoke-fluid consumption. |

| Step | Implemented baseline; remaining work | Acceptance evidence |
| --- | --- | --- |
| SM-10 | Historical profile v1, named colors and presets delivered; explicit v1/v2 readers and reviewed migration now live in the current contract. Broader family/user acceptance remains open. | Source selection and labels cannot imply unsupported hardware or emissions. Color changes affect appearance only; no raw JSON or free-form coordinates enter the UI. |
| SM-11 | Source/show slots are generated for five visual families. The current v3 contract uses stable source/anchor IDs and a legacy adapter. Vantage has show-only tailpipe capability; Extra lacks a verified source, electric installs have no ordinary exhaust, and HX-700/X-Cell pairing remains unverified. Additional mounts/families and clearance review remain open. [Current coverage](SMOKE.md#runtime-selection-and-fleet-coverage). | Validate transformed position/orientation, datum/CG/scale, legacy models and absent slots; show settings cannot invent an exhaust source. |
| SM-12 | Per-emitter colors, width, shapes, amount and multi-color presets delivered; dense overlap and measured cost remain open. | Evaluate all enabled emitters against one total particle/GPU budget, distance LOD and transparency bounds. Colors/materials remain isolated per instance and emitter; appearance leaves physical identity and trace values unchanged. |
| SM-13 | Hold/burst/pulse, puff lifetime and up to eight palette steps delivered. Approximate trail-length targeting remains pending. | Integer-tick schedules and native 30/60/144 FPS birth-color checks pass on the recorded renderer. Stop/fade/expiry and pause remain independent; fluid endurance stays behind FUEL. |
| SM-14 | Shared wind, pause/reset and bounded profile lifecycle delivered; long flight/soak and other backends remain open. | Flight uses presented-session wind/ticks; preview uses an isolated clock/wind and stationary or illustrative straight-pass pose. Recorded native pause/reset/8.9 s offscreen aging checks pass; measured total cost remains unqualified. |
| SM-15 | Presets, emitter selection, colors/timing, shared history, profiles, reviewed reuse, stationary/six-second moving preview and isolated saved-build thumbnails delivered. Stop emission and explicit plume fitting are integrated in the overhaul; native UI/complete-plume review and a possible scrubber remain separate work. | Preview labels its illustrative running-source sample and runs no flight simulation. [Moving-pass evidence](research/aircraft-editor/AE-24/README.md#moving-preview-pass-ae-24b2--sm-15) covers bounded pose/mount/lifecycle checks and two native families. Copy preserves the physical recipe; [thumbnail scope](research/aircraft-editor/AE-24d-1/README.md), full UI, migration, hardware and platform acceptance stay with AE. |

### Retained implementation evidence and renderer constraints

These subphases retain acceptance requirements for the delivered baseline and future extensions. [AE-24 evidence](research/aircraft-editor/AE-24/README.md) resolves the earlier isolated pause/reset assertions with production-renderer probes; the [investigation](research/aircraft-editor/AE-00/README.md) remains dated evidence. Cross-platform quality/cost is still open.

| Subphase | Deliverable and required proof |
| --- | --- |
| SM-10a / SM-11a | Versioned profile validator and legacy-outlet adapter, coordinated with AE-02a/AS. Source exhaust follows accepted running/source gates; explicit show capability cannot be inferred from propulsion. Unknown slot, version or mount rejects before building emitters. |
| SM-12a | Delivered: shared 768-particle profile allocation, fixed before playback, with per-emitter material/seed state and retained birth RGB. The historical 96+768 renderer is selected only by the explicit legacy comparison flag; it does not supplement the new service. V2 demand allocation is bounded by the same total; further capacity/LOD changes need measured quality/cost and residual-lifecycle proof. |
| SM-13a | Pure tick-based held/burst/pulse/palette scheduler with bounded events and explicit precedence. Flight uses session ticks; preview uses its isolated playhead ticks. Identical request tapes must give identical CPU event logs at 30/60/144 fps; GPU images use a separately established tolerance. |
| SM-13b | Render-boundary probe before sequence UI: events crossed inside one draw interval must preserve their ordering without repeatedly changing uniforms for unconsumed GPU requests. Define a bounded per-birth event representation or another measured strategy; keep at most one unconsumed request per emitter. No global TIME or wall-clock timer. |
| SM-14a | Profile bounds/history support eight-second lifetimes and Tail Comet; legacy six-second constants remain separate. Native offscreen expiry passes. Moving/rotated mounts, all LOD edges, dense overlap and full flight cost remain acceptance gates. |
| SM-14b / SM-15a | Production-renderer pause/reset, stop/residual aging and offscreen expiry probes pass on the recorded backend. Preserve rewind/>0.1 s reset semantics, repeated switch/return and pre-activation rollback; extend soak/platform/hardware coverage before closing acceptance. |

The [pinned GLES3 implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/particles_storage.cpp) does not support manual `emit_particle`, subemitters, built-in ribbon trails or 3D SDF particle colliders. A fan or ribbon-shaped plume must use a supported, measured approach. Retain current swept births and `CUSTOM` phase/age/random/opacity semantics until a replacement passes native probes. Multiple emitters share the [AE/VQ performance and evidence gates](plans/aircraft-editor.md#58-performance-and-evidence-gates); reducing birth density is not proof of reduced allocation or GPU cost.

These are presentation and authoring gates, not a promise that every aircraft has smoke hardware or that smoke effects are physically measured. Keep real-radio, physical-emissions, FUEL and platform qualification separate from a successful customization UI.
