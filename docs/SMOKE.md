# RC smoke: current behavior and renderer contract

Checked 2026-10-19. This guide owns the legacy SM-00…09 renderer; [Aircraft Workshop](AIRCRAFT-WORKSHOP.md) owns editable profiles and their exact endpoint coverage. The [remaining plan](SMOKE-PLAN.md) owns qualification. [Player controls](FIRST-LAUNCH.md#3-fly), [legacy tools](../tools/smoke/README.md) and [dated evidence](research/smoke-investigations/SM-00-09/README.md) retain their scope.

A selected custom smoke profile uses the separate bounded multi-emitter renderer and suppresses the legacy pool. Profile smoke is intentionally available on a detached variant's technical trace/capture route; `--smoke=off` suppresses both paths and `--smoke-pump=on` supplies a show request. Source and show effects remain distinct. [AE-24 evidence](research/aircraft-editor/AE-24/README.md) records the profile renderer and isolated preview checks.

## Legacy supported sources

| Configuration | Current smoke source |
| --- | --- |
| Base Stik and finite-glow Stik variants | The shared model's authored hollow muffler mouth; faint exhaust and an optional presentation pump. |
| P-51D | An estimated RC canister outlet at the radiator exit, with a presentation pump; not the decorative full-size stacks. [Installation evidence](research/p51-realism/P51-11a/README.md#engine-smoke-p51-v12). |
| Extra, Ventage Jet, electric Timber | No authored RC exhaust source; no smoke rig is inferred. Electric conversions are also excluded by source kind. |

Flight creates a rig only for one validated model outlet whose kind matches normalized propulsion. Home, static `--capture`, `--trace` and scripted routes do not create it. `--smoke=off` disables the feature; `--smoke-pump=on` supplies the keyboard-side technical request, subject to source/load gates and controller selection.

## Operating behavior and limits

The renderer uses RPM to estimate firing and throttle to gate pump output. Pump OFF stops new births immediately; residual puffs expand, drift and fade. Crash/fault state suppresses output.

**Accepted combustion/source-latch integration remains pending.** `main.gd::_update_smoke()` passes crash/fault validity as its running flag; it does not read `glow_state().running` or `propulsion_source_running()`. Thus RPM is still a proxy during cut, windmilling or depletion. Finite combustion and fuel simulation exist in their owning systems; passing smoke tests does not establish that smoke follows those accepted source states.

The historical `glow_prop` kind also admits the P-51 gasoline shaft installation. Its shared visual treatment is not an identified gasoline/glow emissions model. Mixture, temperature, opacity, jet speed, entrainment and pump-load thresholds remain uncalibrated for smoke. No smoke-fluid draw-down or endurance is implemented. The [fuel standard](FUEL-SYSTEM.md) does not activate a smoke-fluid system merely because inventory mentions a tank.

Keyboard, semantic gamepad actions and assigned radio AUX can request the pump where available. AUX validation is separate from AETR; axis endpoints define proportional flow/reversal, while buttons use held or press-edge behavior. Matching-device OFF/release evidence is required after selection or profile/connection changes. Assignment and recalibration preserve valid independent mappings and reject conflicts.

## Renderer and lifecycle

[exhaust.gd](../app/render/smoke/exhaust.gd) consumes the optional model `exhausts` metadata: finite model-local position, normalized direction, positive radius, supported kind and explicit pump capability. The model-root transform supplies the authoritative datum/CG conversion. The renderer reads flight/weather; it does not write physics or physical traces.

Each rig allocates 96 exhaust and 768 pump particles, with 1.25/6-second lifetimes. Both use world coordinates, fixed seeds, a generated 64² mask, alpha billboards, depth sorting and proximity fading. Birth density decreases with distance; this does not reduce allocated capacity.

One presented simulation interval is submitted per draw. [process.gdshader](../app/render/smoke/process.gdshader) interpolates births between mouth poses using fractional birth time, then entrains them toward shared session wind. Existing off-camera puffs continue aging and receiving weather updates. Bounds/history are bounded; this is a visual approximation, not fluid/solid coupling.

Pause freezes age. Reset/reload/checkpoint restoration clears requests and particle history; checkpoints do not carry a smoke replay. Rewind or an interval over 0.1 seconds primes a fresh presentation. The [2026-10-19 recheck](research/smoke-investigations/SM-00-09/README.md#2026-10-19-documentation-recheck) distinguishes focused software checks from the original GPU campaign. Real-radio, rendered/platform, soak and target-display acceptance remain separate gates.
