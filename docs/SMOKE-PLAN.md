# RC smoke: remaining qualification and customization

Checked 2026-10-19 · Prefix **SM-**. SM-00…09 and the bounded SM-10…15 software baseline are integrated. [Legacy behavior and architecture](SMOKE.md), [Workshop profiles](AIRCRAFT-WORKSHOP.md), [commands](TOOLS.md#aircraft-workshop) and [AE-24 evidence](research/aircraft-editor/AE-24/README.md) have separate homes. This plan owns remaining qualification, not a second runtime specification.

SM owns `app/render/smoke/`, optional model exhaust interfaces, smoke AUX/assignment integration, smoke tests and `tools/smoke/`. AE owns editor/profile work, AS generated attachment bindings, M5 weather and FUEL admitted fluid inventory/consumption. Coordinate shared interfaces through the [ownership registry](README.md#tracks-plans-and-step-ids).

## Remaining SM-00…09 acceptance

| Step | Open work / required evidence |
| --- | --- |
| SM-00/01 | Qualify other GPU/OS backends and each new installation's authored outlet. The original Windows/RTX 3090 campaign does not qualify another backend or aircraft. |
| SM-02 | Profile smoke reads accepted combustion state. The legacy path retains crash/fault plus RPM proxies; complete its accepted-source integration and cut/depletion/windmilling/restart matrix. Physical emissions/temperature/mixture calibration stays a measurement gate. |
| SM-03/04 | Real-radio/SDL mapping and reconnection review; fake-device passes do not close hardware acceptance. |
| SM-05/06 | Current-source rendered flight/night/intersection review and pilot/target-display acceptance. Preserve explicit fixture labels and comparable views. |
| SM-07/08 | Fresh packages on supported platforms, long native memory soak and isolated target-GPU cost. Bounded allocations and capped desktop timings are not those results. |
| SM-09 | Preserve shared wind/time and off-camera aging through changes. Spatial wake/thermal/damage effects require separate mechanisms and evidence. |

Use the existing [evidence record](research/smoke-investigations/SM-00-09/README.md) for reruns and failures. Smoke changes must preserve physical state/trace parity; do not re-record golden flights for a presentation change.

<a id="future-user-customization--proposed-sm-10-onward"></a>

## User customization — SM-10 onward

The [Workshop guide](AIRCRAFT-WORKSHOP.md#supported-adjustments) owns implemented endpoint coverage, presets and profile bounds. Color/amount/width, ribbon/cloud/fan, hold/burst/pulse, timed palettes and stationary preview playback are implemented. The profile renderer allocates 768 particles total and replaces the legacy effect while selected; it does not add another legacy pool. Resource endurance remains absent. Cross-platform, dense-overlap and measured performance acceptance remain open.

Keep source-coupled engine exhaust separate from a user-requested show effect. Engine exhaust follows a supported, authored outlet and the engine's operating state. A colored or wingtip/tail show plume is a presentation choice; it does not assert engine exhaust, fuel chemistry, smoke-fluid inventory, or a physical smoke system. Visual profiles leave mass, forces, controls, flight state and physical trace values unchanged. A future installed smoke-fluid system needs the separate FUEL contract.

Implemented presets include **Classic Exhaust**, **Twin Ribbons**, **Tail Comet** and **Rainbow Burst**. Their tints are display choices. A tail-end slot is distinct from a tail surface; expose only model-authored mounts and never infer one from the origin. Coordinate with [AE's presentation contract](plans/aircraft-editor.md#55-accepted-presentation-contract-and-remaining-work); AE owns editing/profile, [AS owns bindings](plans/aircraft-standardization.md#workbench-customization-bindings), and SM owns rendering/scheduling.

Use precise, friendly labels instead of an unexplained “duration” or “volume” control:

| Setting | Meaning |
| --- | --- |
| **Puff lifetime** | How long each emitted puff exists before it fades. It does not control how long new puffs are emitted. |
| **Burst duration** | How long a one-shot request emits new puffs. Existing puffs continue through their own lifetime after the burst ends. |
| **Trail persistence / length** | How far the visible wake remains behind the aircraft. It emerges from speed, puff lifetime, emission spacing and wind; it is not the same as burst duration. Any length target is approximate and view-dependent. |
| **Smoke amount / visual fullness** | The perceived plume thickness, shaped by width, opacity and particle birth rate/density. It is a rendering control, not smoke mass or fluid volume. Offer Fine/Standard/Full first; qualified shape presets can include a narrow ribbon, soft cloud or wide fan. |
| **Resource endurance** | Time supported by a real smoke-fluid supply and consumption model. This is not implemented and must not be presented as a tank, remaining quantity, refill or endurance until an admitted smoke-fluid law and qualified aircraft inventory define its source, units and draw-down under the [fuel standard](FUEL-SYSTEM.md). Shared finite-fuel support does not enable smoke-fluid consumption. |

| Step | Implemented baseline; remaining work | Acceptance evidence |
| --- | --- | --- |
| SM-10 | Profile v1, named colors and presets delivered; broader family/user acceptance remains open. | Source selection and labels cannot imply unsupported hardware or emissions. Color changes affect appearance only; no raw JSON or free-form coordinates enter the UI. |
| SM-11 | Stable-ID source/show slots are generated for five visual families. Additional mounts/families and broader clearance review remain open. | Validate transformed position/orientation, datum/CG/scale, legacy models and absent slots; show settings cannot invent an exhaust source. |
| SM-12 | Per-emitter colors, width, shapes, amount and multi-color presets delivered; dense overlap and measured cost remain open. | Evaluate all enabled emitters against one total particle/GPU budget, distance LOD and transparency bounds. Colors/materials remain isolated per instance and emitter; appearance leaves physical identity and trace values unchanged. |
| SM-13 | Hold/burst/pulse, puff lifetime and up to eight palette steps delivered. Approximate trail-length targeting remains pending. | Integer-tick schedules and native 30/60/144 FPS birth-color checks pass on the recorded renderer. Stop/fade/expiry and pause remain independent; fluid endurance stays behind FUEL. |
| SM-14 | Shared wind, pause/reset and bounded profile lifecycle delivered; long flight/soak and other backends remain open. | Flight uses presented-session wind/ticks; preview uses a stationary model and isolated clock/wind. Recorded native pause/reset/8.9 s offscreen aging checks pass; measured total cost remains unqualified. |
| SM-15 | Presets, emitter selection, colors/timing, shared history, profiles, reviewed reuse, stationary preview and isolated saved-build thumbnails delivered. Moving pose passes and scrubber remain pending. | Preview labels its illustrative running-source sample and runs no flight simulation. Copy lists applied/skipped settings and preserves the physical recipe. See [AE-24d.1 thumbnail scope](research/aircraft-editor/AE-24d-1/README.md); full UI, migration, hardware and platform acceptance stay with AE. |

### Implementation subphases and renderer constraints

These subphases retain acceptance requirements for the delivered baseline and future extensions. [AE-24 evidence](research/aircraft-editor/AE-24/README.md) resolves the earlier isolated pause/reset assertions with production-renderer probes; the [investigation](research/aircraft-editor/AE-00/README.md) remains dated evidence. Cross-platform quality/cost is still open.

| Subphase | Deliverable and required proof |
| --- | --- |
| SM-10a / SM-11a | Versioned profile validator and legacy-outlet adapter, coordinated with AE-02a/AS. Source exhaust keeps its existing running/source gates; explicit show capability cannot be inferred from propulsion. Unknown slot, version or mount rejects before building emitters. |
| SM-12a | Delivered: shared 768-particle profile allocation, fixed before playback, with per-emitter material/seed state and retained birth RGB. The legacy renderer retains its separate 96+768 budget only when no custom smoke profile is selected. Further capacity/LOD changes need measured quality/cost and residual-lifecycle proof. |
| SM-13a | Pure tick-based held/burst/pulse/palette scheduler with bounded events and explicit precedence. Flight uses session ticks; preview uses its isolated playhead ticks. Identical request tapes must give identical CPU event logs at 30/60/144 fps; GPU images use a separately established tolerance. |
| SM-13b | Render-boundary probe before sequence UI: events crossed inside one draw interval must preserve their ordering without repeatedly changing uniforms for unconsumed GPU requests. Define a bounded per-birth event representation or another measured strategy; keep at most one unconsumed request per emitter. No global TIME or wall-clock timer. |
| SM-14a | Profile bounds/history support eight-second lifetimes and Tail Comet; legacy six-second constants remain separate. Native offscreen expiry passes. Moving/rotated mounts, all LOD edges, dense overlap and full flight cost remain acceptance gates. |
| SM-14b / SM-15a | Production-renderer pause/reset, stop/residual aging and offscreen expiry probes pass on the recorded backend. Preserve rewind/>0.1 s reset semantics, repeated switch/return and pre-activation rollback; extend soak/platform/hardware coverage before closing acceptance. |

The [pinned GLES3 implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/particles_storage.cpp) does not support manual `emit_particle`, subemitters, built-in ribbon trails or 3D SDF particle colliders. A fan or ribbon-shaped plume must use a supported, measured approach. Retain current swept births and `CUSTOM` phase/age/random/opacity semantics until a replacement passes native probes. Multiple emitters share the [AE/VQ performance and evidence gates](plans/aircraft-editor.md#58-performance-and-evidence-gates); reducing birth density is not proof of reduced allocation or GPU cost.

These are presentation and authoring gates, not a promise that every aircraft has smoke hardware or that smoke effects are physically measured. Keep real-radio, physical-emissions, FUEL and platform qualification separate from a successful customization UI.
