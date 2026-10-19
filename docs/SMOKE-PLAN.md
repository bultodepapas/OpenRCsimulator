# RC smoke: remaining qualification and proposed customization

Checked 2026-10-19 · Prefix **SM-**. SM-00…09 are integrated; [current behavior and architecture](SMOKE.md), [tool commands](../tools/smoke/README.md) and [dated evidence](research/smoke-investigations/SM-00-09/README.md) have separate homes. This plan owns remaining gates and future SM-10…15 work, not a second runtime specification.

SM owns `app/render/smoke/`, optional model exhaust interfaces, smoke AUX/assignment integration, smoke tests and `tools/smoke/`. AE owns editor/profile work, AS generated attachment bindings, M5 weather and FUEL admitted fluid inventory/consumption. Coordinate shared interfaces through the [ownership registry](README.md#tracks-plans-and-step-ids).

## Remaining SM-00…09 acceptance

| Step | Open work / required evidence |
| --- | --- |
| SM-00/01 | Qualify other GPU/OS backends and each new installation's authored outlet. The original Windows/RTX 3090 campaign does not qualify another backend or aircraft. |
| SM-02 | Connect accepted combustion/source-running state to smoke and verify cut, depletion, windmilling and restart. Current crash/fault plus RPM gates are a proxy. Retain physical emissions/temperature/mixture calibration as a separate measurement gate. |
| SM-03/04 | Real-radio/SDL mapping and reconnection review; fake-device passes do not close hardware acceptance. |
| SM-05/06 | Current-source rendered flight/night/intersection review and pilot/target-display acceptance. Preserve explicit fixture labels and comparable views. |
| SM-07/08 | Fresh packages on supported platforms, long native memory soak and isolated target-GPU cost. Bounded allocations and capped desktop timings are not those results. |
| SM-09 | Preserve shared wind/time and off-camera aging through changes. Spatial wake/thermal/damage effects require separate mechanisms and evidence. |

Use the existing [evidence record](research/smoke-investigations/SM-00-09/README.md) for reruns and failures. Smoke changes must preserve physical state/trace parity; do not re-record golden flights for a presentation change.

## Future user customization — proposed SM-10 onward

Everything in this section is pending. The [current guide](SMOKE.md) owns the single-outlet renderer's fixed appearance, lifetimes and budgets, with dated evidence retained. No user-facing color, mount, burst-duration or resource-endurance editor is implemented.

Keep source-coupled engine exhaust separate from a user-requested show effect. Engine exhaust follows a supported, authored outlet and the engine's operating state. A colored or wingtip/tail show plume is a presentation choice; it does not assert engine exhaust, fuel chemistry, smoke-fluid inventory, or a physical smoke system. Visual profiles leave mass, forces, controls, flight state and physical trace values unchanged. A future installed smoke-fluid system needs the separate FUEL contract.

Simple future examples are **Classic Exhaust** (automatic effect at a supported exhaust outlet), **Twin Wingtips** (for example, red left and blue right display plumes when both named slots exist), and **Tail Accent**. Color swatches such as white, gray, blue and red are display tints only. A rear-fuselage or tail-end slot is distinct from a slot on the horizontal or vertical tail surface; show only mounts declared for that aircraft's model and verified by its owner. Do not offer arbitrary coordinates, infer a mount from the model origin, or enable a slot whose placement is absent or unvalidated. Coordinate with [AE's profile contract and delivery packages](plans/aircraft-editor.md#55-presentation-contract-to-implement); AE owns the editor/profile, [AS owns generated slot bindings](plans/aircraft-standardization.md#workbench-customization-bindings-proposed), and SM owns rendering/scheduling.

Use precise, friendly labels instead of an unexplained “duration” or “volume” control:

| Setting | Meaning |
| --- | --- |
| **Puff lifetime** | How long each emitted puff exists before it fades. It does not control how long new puffs are emitted. |
| **Burst duration** | How long a one-shot request emits new puffs. Existing puffs continue through their own lifetime after the burst ends. |
| **Trail persistence / length** | How far the visible wake remains behind the aircraft. It emerges from speed, puff lifetime, emission spacing and wind; it is not the same as burst duration. Any length target is approximate and view-dependent. |
| **Smoke amount / visual fullness** | The perceived plume thickness, shaped by width, opacity and particle birth rate/density. It is a rendering control, not smoke mass or fluid volume. Offer Fine/Standard/Full first; qualified shape presets can include a narrow ribbon, soft cloud or wide fan. |
| **Resource endurance** | Time supported by a real smoke-fluid supply and consumption model. This is not implemented and must not be presented as a tank, remaining quantity, refill or endurance until an admitted smoke-fluid law and qualified aircraft inventory define its source, units and draw-down under the [fuel standard](FUEL-SYSTEM.md). Shared finite-fuel support does not enable smoke-fluid consumption. |

| Step | Pending work | Acceptance evidence |
| --- | --- | --- |
| SM-10 | Define a compact visual profile with named color swatches and presets; keep source-coupled exhaust distinct from show-effect plumes. | Source selection and labels cannot imply unsupported hardware or emissions. Color changes affect appearance only; no raw JSON or free-form coordinates enter the UI. |
| SM-11 | Extend model-owned attachments and replace the single-mouth bootstrap with stable-ID emitter bindings; retain the legacy outlet/source gate. Distinguish source outlets from show mounts, including a shared outlet only when explicitly show-capable. | Validate reviewed wingtip, rear-fuselage and tail-surface/fin slots, transformed position/orientation, clearance, datum/CG, legacy models and absent slots. Show settings cannot invent an exhaust source. |
| SM-12 | Add bounded per-emitter color, width, shape and smoke-amount presets, including multi-color combinations on compatible named slots. | Evaluate all enabled emitters against one total particle/GPU budget, distance LOD and transparency bounds. Colors/materials remain isolated per instance and emitter; appearance leaves physical identity and trace values unchanged. |
| SM-13 | Expose hold/burst, puff lifetime/fade and approximate trail persistence separately; later add bounded pulses, alternating colors and rainbow sequences. | Use flight simulation time or the isolated preview playhead, never a wall-clock timer. Stop/fade/expiry and pause are independent; old puffs retain birth color. Seeds/settings produce the same schedule at different render rates. Fluid endurance stays behind FUEL. |
| SM-14 | Preserve shared wind, pause/reset/reload/return behavior and bounded processing across simultaneous emitters. | Flight puffs use presented-session wind/time; editor puffs use a deterministic preview clock/pose path and frozen preview wind. Pause freezes age, reset clears requests, off-camera aging is correct and total cost stays bounded. Preview inputs never alter trial weather or physics replay. |
| SM-15 | Deliver the smoke integration portions of AE-24b/c/d jointly: presets, emitter selection, colors, linked pairs, amount, timing, preview and saved profiles. | Extend existing undo/redo/save/copy/return with per-page reset and profile edits. Preview uses a bounded pose path plus labeled read-only source samples, or show effects only; no extra flight runs. Follow AE for UI, migration and portable-profile acceptance. |

### Implementation subphases and renderer constraints

These subphases refine SM-10…15; none is implemented by adding it to this plan. The [2026-10-19 investigation](research/aircraft-editor/AE-00/README.md) confirms retained birth RGB on one native Compatibility path, but leaves its isolated pause/reset assertions unresolved. Preserve the existing SM-00…09 evidence and reproduce those observations before attributing them to production behavior.

| Subphase | Deliverable and required proof |
| --- | --- |
| SM-10a / SM-11a | Versioned profile validator and legacy-outlet adapter, coordinated with AE-02a/AS. Source exhaust keeps its existing running/source gates; explicit show capability cannot be inferred from propulsion. Unknown slot, version or mount rejects before building emitters. |
| SM-12a | One emitter's tint/amount/shape, then an authored pair and three-slot profile. Reuse birth RGB; material/seed state is per instance/emitter. Start with 864 total allocated slots, partitioning the 768 show slots before playback; this is a measured candidate, not a quality promise. Changing `amount` restarts, so live reallocation cannot erase residuals silently. |
| SM-13a | Pure tick-based held/burst/pulse/palette scheduler with bounded events and explicit precedence. Flight uses session ticks; preview uses its isolated playhead ticks. Identical request tapes must give identical CPU event logs at 30/60/144 fps; GPU images use a separately established tolerance. |
| SM-13b | Render-boundary probe before sequence UI: events crossed inside one draw interval must preserve their ordering without repeatedly changing uniforms for unconsumed GPU requests. Define a bounded per-birth event representation or another measured strategy; keep at most one unconsumed request per emitter. No global TIME or wall-clock timer. |
| SM-14a | Lifetime-aware bounds/history/growth and cleanup, then the proposed 8 s Tail Comet. Current 6 s constants cannot qualify it. Test moving/rotated mounts, world-space endpoints without a second emitter transform, 150/300/600 m LOD edges, wind and offscreen time exceeding the maximum life. |
| SM-14b / SM-15a | Diagnose pause/reset GPU completion, then integrate bounded preview and frozen trial profiles through AE-10a/24b/c. Test stop/residual aging, reset, rewind/>0.1 s discontinuity, switch/return and repeated lifecycle. Preserve source/show distinction and previous-flight rollback for detectable pre-activation failures. |

The [pinned GLES3 implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/particles_storage.cpp) does not support manual `emit_particle`, subemitters, built-in ribbon trails or 3D SDF particle colliders. A fan or ribbon-shaped plume must use a supported, measured approach. Retain current swept births and `CUSTOM` phase/age/random/opacity semantics until a replacement passes native probes. Multiple emitters share the [AE/VQ performance and evidence gates](plans/aircraft-editor.md#58-performance-and-evidence-gates); reducing birth density is not proof of reduced allocation or GPU cost.

These are presentation and authoring gates, not a promise that every aircraft has smoke hardware or that smoke effects are physically measured. Keep real-radio, physical-emissions, FUEL and platform qualification separate from a successful customization UI.
