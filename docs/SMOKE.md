# Aircraft smoke: runtime and authoring contract

Checked 2026-10-20. This guide owns current smoke behavior and onboarding. [Aircraft Workshop](AIRCRAFT-WORKSHOP.md) owns the editor flow; [tools](../tools/smoke/README.md) owns commands. The [SM-16–25 execution plan](../SMOKE_SYSTEM_MASTER_PLAN.md) and [remaining qualification](SMOKE-PLAN.md) retain open gates. The [SM-16–23 evidence record](research/smoke-investigations/SM-16-23/README.md) records overhaul checks and limitations, not physical emissions or complete native/platform acceptance.

<a id="avanti--ventage-jet-show-smoke-sm-11-r1"></a>

## Runtime selection and fleet coverage

[smoke_system.gd](../app/render/smoke/smoke_system.gd) is the common presentation boundary over the bounded GPU profile renderer. Stock and Workshop effects use the same scheduler, motion shader, authored outlets and accepted source observations. They read flight state and weather without changing forces, fuel, mass, controls or solver identity. Smoke-fluid consumption and endurance are not implemented.

| Configuration | Current capability |
| --- | --- |
| Base Stik and finite-glow Stik variants | Faint ordinary exhaust and a requested show pump share the hollow muffler outlet. Observations identify the actual installed engine. |
| P-51D | Ordinary exhaust and a requested pump share the estimated RC canister outlet at the radiator exit, rather than decorative full-size stacks. Gasoline appearance is separate from the historical `glow_prop` solver kind. [Installation evidence](research/p51-realism/P51-11a/README.md#engine-smoke-p51-v12). |
| Avanti / Ventage Jet | Requested white tailpipe show smoke, gated by accepted turbine operation. This is not ordinary visible turbine exhaust. |
| Extra 300S | Authored show mounts; no verified physical exhaust outlet. Source-exhaust onboarding remains open. |
| Electric Timber and electric conversions | No ordinary combustion exhaust. Authored show devices remain separate capabilities. |
| X-Cell research activity / HX-700 surrogate | Explicit empty capability. Engine/geometry pairing and outlets remain unverified; rotor RPM cannot authorize smoke or a borrowed fixed-wing mount. |

Stock ordinary exhaust follows accepted source operation. Stock show smoke starts OFF. **H**, semantic controller actions or assigned radio AUX request show smoke; source-bound devices additionally require accepted source operation. Cut, depletion, crash and fault suppress the corresponding births. A Workshop trial owns its full appearance selection: explicit empty smoke and all-disabled entries produce no smoke and do not fall through to stock or legacy effects. Invalid profiles cannot silently substitute another outlet.

`--smoke=off` suppresses smoke. `--smoke-pump=on` supplies a keyboard-side technical show request. Stock effects are omitted from static capture, trace and scripted routes; explicit trial profiles can use their technical presentation route. `--smoke-backend=legacy` retains the old stock renderer for matched comparisons until native acceptance permits retirement. It does not add another pool alongside a selected profile.

## Profiles and visual controls

[presentation.gd](../app/workshop/presentation.gd) reads strict profile v1 and v2. V1 retains its schema, identity and amount/motion policy; new profiles use v2. Both retain registered IDs, sRGB hex colors, ribbon/cloud/fan shapes, hold/burst/pulse timing, puff lifetime and up to eight palette swatches. Profiles carry no executable code, resource paths or arbitrary mount coordinates.

V2 separates optical density from requested birth rate. `amount` remains a required historical field; v2 uses density and emission rate. Optional v2 fields receive finite defaults during canonical validation:

| Field | Bounds | Default / meaning |
| --- | --- | --- |
| `density` | 0–2 | 1; optical fullness proxy, not aerosol mass. Zero suppresses visible births. |
| `emission_rate_hz` | 1–240 | 48 requested puffs/s, limited by allocation. |
| `jet_speed_mps` | 0–30 | 0.65 m/s; initial outward speed. |
| `dispersion_m2_s` | 0–2 | 0.1 m²/s; visual cross-section growth coefficient. |
| `buoyancy_mps` | −2–3 | 0.27 m/s; age-decaying visual drift. |
| `turbulence_mps` | 0–5 | 0.22 m/s; bounded coherent detail. |
| `drag_s` | 0.05–3 | 0.4 s; relaxation toward ambient motion. |
| `velocity_inheritance` | 0–1 | 1; outlet carrier velocity fraction. |
| `palette_mode` | `step`, `smooth` | `step`; smooth RGB interpolation is linear-light, alpha is linear. |
| `phase_offset_s` | 0–60 | 0; emission-palette phase offset. |

`width_m` remains 0.01–2 m and `lifetime_s` 0.1–8 s. These are visual metre/second controls, not manufactured dimensions or identified fluid coefficients. Width does not move the mount. Admitted uniform model scale is retained in the outlet basis and scales the physical birth aperture independently of plume width. Puff lifetime controls residual persistence; burst duration controls new emission. Neither is fluid endurance or a guaranteed trail length. Scale/aperture clearance and narrow fast trails still require qualification.

Palette color is sampled at birth and retained by each puff. Later edits do not recolor existing particles. Smooth transitions use bounded interval records rather than repeated unconsumed GPU requests. The schedule uses presentation time, never shader wall time. Flight supplies the fractional clock used for the displayed model pose and retains accepted source events until that clock reaches them. Focused schedule and native 30/60/144 FPS projection checks pass; complete flight-camera qualification remains open. The current wash sample can lead that clock by less than one physics tick.

## Runtime API, budgets and lifecycle

The renderer exposes `configure(profile, bindings)`, `play()`, `pause()`, `stop()`, `reset()`, `advance(dt, pose, wind, request, source_sample)`, `budget_info()` and `get_plume_bounds()`. Reset authorizes reconfiguration. [stock_profile.gd](../app/render/smoke/stock_profile.gd) selects stock appearance; the activity/session boundary supplies accepted source observations.

The v2 authored menu/profile permits eight outlets, with at most four enabled in any source/show combination. Their fixed allocations total **at most 768 particles**. V2 allocates from requested rate × lifetime, caps rates to available capacity and reports requested/resolved rates and saturation through `budget_info()`. Live residual pools are not resized or reassigned. V1 retains equal allocation. Birth thinning and distance LOD do not prove reduced allocated GPU work.

World-space puffs inherit outlet motion, outward velocity and qualified wash, then relax toward shared ambient wind. V2 adds coherent detail, diffusion-inspired growth and optical-depth opacity. Mutable materials/event buffers belong to individual emitters; immutable resources can be shared. This is a visual approximation, not fluid simulation, measured chemistry, obstacle coupling or validated rotor wash.

| Action | Behavior |
| --- | --- |
| Show OFF / Stop emission | Stops requested births; residuals age while presentation time advances. Ordinary exhaust follows its own source gate. |
| Pause | Freezes age, schedules and palette phase. Preview cannot advance retained flight smoke. |
| Reset/reload/checkpoint/rewind | Clears requests, puffs and history, then primes outlets. A physical checkpoint carries no smoke replay. |
| Missing mount / unsupported transform | Reports unavailable output; no fallback at the aircraft origin. |
| Hidden/offscreen plume | Residual processing remains bounded through expiry; returning views must not resurrect frozen puffs. |

Workshop preview separates Stop emission from Pause and Restart, and offers explicit plume fitting. Its source samples are illustrative and run no flight physics. Controller OFF/release and reconnect gates remain separate from AETR calibration; fake-device tests do not establish real-radio acceptance.

## Authoring outlets and sources

Edit [customization-bindings.json](../assets/aircraft/customization-bindings.json), then run its [generator](../research/aircraft-standardization/build_customization.py). Never hand-edit `app/data/aircraft_customization.json`. Authored source version 2 produces companion version 3. Preserve stable slot IDs where their purpose remains compatible.

Each outlet supplies `id`, `label`, `kind`, `pair`, `role`, `radius_m`, `emissions_preset`, `activation_policy` and `provenance`. Radius is authored in metres, bounded to 0.0001–0.1 m. Provenance is `authored`, `estimated` or `measured`, without implying validation. The closed preset set is `glow_two_stroke`, `glow_four_stroke`, `glow_installation`, `gasoline_two_stroke`, `turbine_show`, `independent_show`. This metadata describes presentation intent; coefficients and installation evidence still govern supported behavior.

| Attachment / purpose | Required binding |
| --- | --- |
| Local show mount | `node_path`, local `position_m`, normalized `direction`; `independent_request`. A source-gated local device also supplies `source_id`, `source_kind` and `source_and_request`. |
| Ordinary exhaust | `source_id`, `source_kind`, stable `anchor_id`; `source_running`, unpaired `exhaust` role. |
| Show pump at a physical outlet | The same stable source/anchor fields, `kind=show`, `source_and_request`. Several slots may share an engine/anchor. |

`source_kind` is the accepted solver kind (`glow_prop`, `electric_prop`, `turbine`), not chemistry. `$propulsion` is a stable installation-role alias for shared visual families: resolution obtains the actual `physical_propulsion_id` and verifies its kind. Other IDs name supplied installations. Aircraft names, RPM alone and decorative geometry cannot establish source capability.

At configuration the adapter supplies a source map, for example:

```gdscript
airplane["smoke_sources"] = {
    "engine_a": {
        "kind": "glow_prop",
        "anchors": {
            "left_exit": {"position": authored_left_position, "direction": authored_left_direction},
            "right_exit": {"position": authored_right_position, "direction": authored_right_direction},
        },
    },
}
```

The owning model pipeline supplies those render-boundary `Vector3` values. Articulated anchors may include a `Node3D` handle as `node`. Two descriptors referencing `engine_a` and different anchors consume one accepted engine observation and stop on its accepted cut/depletion event; they do not create duplicate engine state.

[aircraft_customization.gd](../app/render/aircraft_customization.gd) provides `resolve_smoke_bindings(airplane)` → `{ok, errors, handles}` and `update_smoke_transforms(handles)` → slot-ID/world-transform map. `smoke_transforms(airplane)` caches configuration; `invalidate_smoke_bindings(airplane)` discards that cache. Resolve at setup and update moving transforms without per-frame companion validation or source hashing. Missing/deleted handles, mismatched sources, nonuniform scale and shear fail closed. The returned basis retains uniform scale; normalize it when extracting a direction, and apply its scale once to authored bore radius. Datum/CG conversion remains in the model root.

Only `legacy_source_anchors()` maps legacy `exhausts[0]` to stable `physical_exit`. New models publish stable anchors directly. Companion v1/v2 readers remain explicit historical paths; new bindings have no positional source selectors.

## Migration, proofs and onboarding

Saved revisions remain immutable. `validate_stored()` preserves bounded future records as unavailable; stale model/slot/renderer pins cannot silently fly or rebind. Historical absence remains v1, while an explicit new v2 empty selection disables smoke. Library browsing does not rewrite records.

`migrate_v1(profile, old_bindings, new_bindings)` returns a proposed v2 profile and review report with old/new pins, slots, presets, activation policies and new settings. It requires the original companion, unchanged physical model/family and compatible selected IDs. It preserves old data and claims no visual equivalence: v2 density/rate/motion differ from v1 amount. Workshop can create a reviewed draft when the old profile still matches its supplied companion. Stale originals require their original bindings and explicit migration. Cross-version copy is not a migration shortcut; physical recipe identity remains separate.

Companion v3 declares `source_proof_version=2` and Godot 4.7.2. The closed v2 proof inventory contains ten LF-normalized text paths: customization adapter, proof reader, legacy exhaust/process shader, profile renderer/process shader/scheduler, shared service, stock presets and presentation schema. The seven-path proof v1 reader remains explicit. Unknown paths, altered bytes, mismatched versions and incomplete package proofs fail. No raw asset is currently admitted; a texture addition requires a deliberate closed byte-proof inventory and license/import receipt.

To onboard an aircraft:

1. Establish accepted propulsion and fuel family. Declare no source exhaust when evidence is absent; show capability may qualify independently.
2. Author stable node/anchor IDs, pose, direction, radius, binding, policy, preset and provenance through the owning pipeline. Distinct engines require distinct accepted observations.
3. Regenerate model/customization outputs and proofs. Preserve asset licenses and inspect suitable freely downloadable assets before creating replacements.
4. Test missing/invalid mounts, shared-engine outlets, cut/depletion/restart, scale/CG/rotation and unsupported transforms. Inspect an outlet overlay and plume from multiple native views.
5. Exercise stock/custom/empty/disabled selections through preview, immutable save/load, migration, bundle copy/import and Test fly, including controller OFF/reconnect.
6. Record resolved rates, allocation and scene cost with all intended emitters. Qualify overlap, fast trails, lifetime extremes, offscreen residuals, fractional timing and target platforms before claiming acceptance.

Retain dated evidence with the owning smoke/aircraft track. Software conformance, native visual preference and measured emissions remain separate results.
