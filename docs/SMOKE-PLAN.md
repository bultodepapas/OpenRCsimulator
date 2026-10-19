# RC smoke: engine exhaust and auxiliary pump

2026-10-19 · Revision 6 · Step prefix: **SM-**

**Status:** Stik glow exhaust and optional pump are integrated. Software and native Windows visual verification are recorded in [SM-00…09](research/smoke-investigations/SM-00-09/README.md). Real-radio, other-platform and target-display acceptance remain open.

**Owns:** `app/render/smoke/`, optional aircraft exhaust anchors, `app/input/smoke_aux.gd`, AUX profile extensions, `app/ui/smoke_aux_assignment.gd`, smoke tests and `tools/smoke/`. Main/FlightSession integration reads existing propulsion, geometry and M5 weather; physics equations and aircraft data are unchanged. Research stays in [rc-exhaust-smoke](research/rc-exhaust-smoke.md) and [smoke investigations](research/smoke-investigations/README.md).

## Intended behavior

The Stik's authored hollow muffler mouth emits faint oil-bearing glow exhaust while RPM indicates firing. An optional presentation smoke pump adds a white trail at sufficient operating load. Turning it off stops births immediately; existing puffs expand, drift and fade. RPM and throttle gates are estimates, not engine temperature or smoke-oil measurements. Smoke never writes flight state, AETR commands, aircraft data or traces.

The Stik declares its authored RC exhaust mouth. The P-51 declares an estimated canister outlet from its kit installation (CARF manual: internal MTW canister in a tunnel; outlet at the radiator exit is an estimate, [P51-11a](research/p51-realism/P51-11a/README.md#engine-smoke-p51-v12)), not its decorative full-size stacks. The Extra has no authored outlet. The healthy Ventage Jet turbine, electric Timber and electric Stik conversions stay clear. No exhaust is inferred at the model origin. Home and static `--capture` routes have no operating engine/history and remain smoke-free.

Controls and assignment are documented in [FIRST-LAUNCH](FIRST-LAUNCH.md#3-fly); reproducible commands live in [tools/smoke](../tools/smoke/README.md). `--smoke=off` disables the feature; `--smoke-pump=on` is an explicit technical flight/profile request.

## Implemented architecture

The optional render-model `exhausts` array carries a finite model-local `position`, normalized `direction`, positive `radius_m`, propulsion `kind` and explicit `pump` capability. The Stik builder publishes the same endpoint/direction used to build its hollow outlet. The render root already applies the authoritative datum/CG transform.

Two world-space GPUParticles3D systems allocate 96 short-lived exhaust puffs and 768 pump puffs (1.25 and 6 s). A shared original 64² soft mask is generated synchronously; there are no third-party assets or addons. Alpha billboards use field lighting, depth sorting, native 0.12 m proximity fading, no shadow pass, bounded history-derived visibility bounds and distance-dependent birth density. A runway A/B showed softer intersections; a dense low-speed pump cloud can still surround the airframe. Existing particles continue aging when off camera; no camera cull skips their weather updates.

The renderer submits exactly one presented simulation interval per draw, with `speed_scale=0` and explicit resource-RID queueing. A small particle shader uses Godot's fractional birth DELTA to interpolate mouth position/direction between presented poses, then entrains aircraft/exhaust momentum toward the shared M5 wind. Launch wash comes from the existing thrust/wake kernels. Puff expansion, small seeded eddies, entrainment time, exhaust jet speed, color and opacity remain visual estimates. This is not a fluid solver or calibrated emissions model.

Pause owners freeze particle age. Reset/reload clears requests and particles; a time seek or interval over 0.1 s primes a fresh presentation instead of connecting distant flights. `restart()` enables births, so reset calls it before explicitly disabling emission. Manual requests use `fixed_fps=1` to retain one fractional birth interval; ordinary native emitter interpolation alone did not fill the measured fast-flight gaps.

The optional `aux.smoke` binding is validated separately from AETR. Axis OFF/ON endpoints establish reversal and proportional flow; buttons explicitly select held-level or press-edge toggle. Assignment rejects AETR conflicts, other devices and ambiguous movement. Recalibration retains valid AUX or discards only the conflicting binding. Connection/profile changes require a fresh matching-device OFF event; polling an unreported SDL zero cannot arm it.

## Technical constraints from research

- SM-00 verified Godot 4.7.2 GPUParticles3D with Compatibility on native Windows/RTX 3090 before integration. Retain the probe when testing another backend.
- At 30 fps and 40 m/s the emitter moves about 1.33 m each frame. A prior isolated probe showed gaps for small quads. SM-00 must compare point births with native emission distributed along the travelled segment; ordinary visual interpolation is not proof of a continuous trail.
- Verify pause, restart, deterministic seeds, transparency order and particle aging while the emitter is fully off camera. A correct visibility AABB alone does not prove off-screen processing.
- Keep the auxiliary assignment separate from AETR, preserve it through radio recalibration and profile changes, and test it with the fake radio before a real-radio review.
- Old and new particles use `FlightSession.wind_at()` at the presented simulation time. Further spatial wind support follows that service; do not invent a second weather clock.
- Keep the smoke mask small and reproducible first. Add depth fading or a custom birth shader only if a rendered probe shows the native material is insufficient.

The recorded emitter tests and off-camera processing questions are in [investigation 02](research/smoke-investigations/02-clock-captures.md), [moving-emitter results](research/smoke-investigations/03-moving-emitter.md), [radio AUX](research/smoke-investigations/07-aux-radio.md), [pump behavior](research/smoke-investigations/08-pump-behavior.md), and [wind advection](research/smoke-investigations/09-wind-advection.md). The full tool/API/license survey remains in the [investigation index](research/smoke-investigations/README.md).

## Small steps and proof

| Step | Work | Status / proof required |
| --- | --- | --- |
| SM-00 | Compatibility probe: motion, timing, pause/reset, off-camera aging, transparency and seed. | Verified on Windows/RTX 3090; native swept births filled 90.1% of the sampled row versus 26.0% for point births. [Evidence](research/smoke-investigations/SM-00-09/README.md). |
| SM-01 | Validated exhaust model interface. | Stik mouth/direction are authored with the geometry; transformed-attitude and invalid-anchor checks pass. Other RC installations need their own anchors. |
| SM-02 | RPM-driven glow exhaust. | Integrated into real flight; stopped/invalid/electric/turbine cases stay clear. Startup/shutdown RPM fixtures are labeled: combustion operation is not yet simulated. |
| SM-03/04 | Pump request and assigned AUX axis/button. | Implemented with guided OFF→ON→OFF, 60 AUX/storage checks and 54 engine/main-scene checks. Gamepad AUX persists independently of its fixed flight profile. Physical radios/SDL platform mappings remain open. |
| SM-05/06 | Reproducible flight captures and appearance. | Production-scene interval captures, separate airplane/smoke/background layers, pause/reset, residual fading and attitude review are recorded. Pilot/display and further night/intersection tuning remain open. |
| SM-07/08 | Bounds, lifecycle, timing, provenance and export. | Bounded allocation, repeated resets, native timing and isolated import/pack checks are recorded. Other OS/GPU exports, long native soak and target-hardware acceptance remain open. |
| SM-09 | Shared wind advection. | Implemented now because M5 exists: the same uniform wind/gust/turbulence service drives old and new puffs. Spatial wake/thermal/damage effects require separate evidence. |

The implementation and its software proof do not close physical emissions, real-radio or all-platform acceptance. Keep those limits distinct from the integrated flight feature; do not re-record golden flights for smoke.

## Future user customization — proposed SM-10 onward

Everything below is pending; the implemented SM-00…09 behavior and evidence above are unchanged. The renderer currently uses one authored exhaust anchor per configured aircraft smoke rig, fixed engine/pump appearance, 1.25 s exhaust-puff and 6 s pump-puff lifetimes, and bounded 96/768-particle systems. It has no user-facing color, mount, burst-duration or resource-endurance editor.

Keep source-coupled engine exhaust separate from a user-requested show effect. Engine exhaust follows a supported, authored outlet and the engine's operating state. A colored or wingtip/tail show plume is a presentation choice; it does not assert engine exhaust, fuel chemistry, smoke-fluid inventory, or a physical smoke system. Visual profiles leave mass, forces, controls, flight state and physical trace values unchanged. A future installed smoke-fluid system needs the separate FUEL contract.

Simple future examples are **Classic Exhaust** (automatic effect at a supported exhaust outlet), **Twin Wingtips** (for example, red left and blue right display plumes when both named slots exist), and **Tail Accent**. Color swatches such as white, gray, blue and red are display tints only. A rear-fuselage or tail-end slot is distinct from a slot on the horizontal or vertical tail surface; show only mounts declared for that aircraft's model and verified by its owner. Do not offer arbitrary coordinates, infer a mount from the model origin, or enable a slot whose placement is absent or unvalidated. Coordinate with [AE's profile contract and delivery packages](plans/aircraft-editor.md#55-presentation-contract-to-implement); AE owns the editor/profile, [AS owns generated slot bindings](plans/aircraft-standardization.md#workbench-customization-bindings-proposed), and SM owns rendering/scheduling.

Use precise, friendly labels instead of an unexplained “duration” or “volume” control:

| Setting | Meaning |
| --- | --- |
| **Puff lifetime** | How long each emitted puff exists before it fades. It does not control how long new puffs are emitted. |
| **Burst duration** | How long a one-shot request emits new puffs. Existing puffs continue through their own lifetime after the burst ends. |
| **Trail persistence / length** | How far the visible wake remains behind the aircraft. It emerges from speed, puff lifetime, emission spacing and wind; it is not the same as burst duration. Any length target is approximate and view-dependent. |
| **Smoke amount / visual fullness** | The perceived plume thickness, shaped by width, opacity and particle birth rate/density. It is a rendering control, not smoke mass or fluid volume. Offer Fine/Standard/Full first; qualified shape presets can include a narrow ribbon, soft cloud or wide fan. |
| **Resource endurance** | Time supported by a real smoke-fluid supply and consumption model. This is not implemented and must not be presented as a tank, remaining quantity, refill or endurance until the [fuel, mass and balance contract](plans/fuel-mass-balance.md) defines the source, units, inventory and draw-down and the aircraft owner supplies qualified data. |

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
