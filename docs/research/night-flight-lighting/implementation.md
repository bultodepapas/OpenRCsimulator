# FW-RGB implementation and qualification

2026-10-25. The user approved implementation after the [masterplan](../../night-flight-lighting-masterplan.md). This record covers the first integrated RGB renderer, profile and Workshop implementation. It does not close pilot gate FW-N or establish hardware performance. The exact test results below are updated after integration.

## Boundaries and decisions

- Extend the existing `AircraftLights`/`NightKit`; retain `AircraftLightState` AUTO/ALL/NAV/OFF, 17:30 local-time behavior and session reset policy. Historical profiles use the old lazy path.
- Presentation envelope v3 adds a required data-only `lighting` field. Explicit v1/v2 readers retain their schemas and identities. The existing v1 smoke migration still produces a reviewable v2 proposal; lighting editing then extends it to v3.
- Keep companion schema v3 because this slice adds no authored mount fields. Advance its independent `source_proof_version` to 3 to pin the new rendering closure. A future authored lighting binding schema remains a separate versioned extension, not a fabricated registry.
- Reuse the immutable variant store, bundle format, trial freeze, shared Workshop history and atomic recovery transactions. Recovery adds an optional strictly bounded lighting editor buffer; historical snapshots remain readable.
- Separate the visual identity from compiled flight identity. Lighting never changes the solver state, propulsion, battery drain or recorded controls.
- Derive kit geometry through the established fitter and honor existing root `light_anchors`, `light_groups`, imported lens bindings and articulated gear gates. Profile data carries no paths, transforms or executable code.
- Use per-instance pattern phase and exposure. Phase derives from displayed simulation time; Workshop owns an independent 240 Hz preview clock. No shader uses engine `TIME`.
- Keep the existing sky, moon, atmosphere, runway and scene exposure. Do not enable compulsory bloom or change global tonemapping for RGB.
- Field spot validation reserves two of Compatibility's eight per-mesh slots for paired aircraft landing lights. The accepted default field uses five spots. Decorative RGB spill uses the separate OmniLight budget.
- Airspeed response uses a presentation scale of 0–40 m/s; this is not an aircraft limit. Roll/pitch reactions consume accepted body rates; no render-side flight model is added.

## Implemented data contract

`app/render/lighting/lighting_profile.gd` owns the closed `openrc-aircraft-lighting` v1 payload and presets. The envelope accepts `inherit`, `preset`, `custom` and `disabled`; explicit disabled is never interpreted as a missing profile. The thirteen initial semantic zone IDs match existing kit nodes. Effect anchors are `vfx_tip_left` and `vfx_tip_right`, resolved from the existing fitted tips.

Limits include 32 zones, eight colors per pattern, 32 sequence cues, a 60-second sequence, 24 KiB lighting payload, 6,144 lighting JSON nodes, and two enabled effect anchors. Numeric booleans, nonfinite values, unknown keys, duplicate IDs, invalid colors, unsupported versions and invalid cue references are rejected before rendering. The outer profile is bounded at 64 KiB and 8,192 nodes.

Presets are Classic RC, Night Radian, Neon RGB, Night Aerobatics, Festival / Fireworks and Custom. Night Radian is an inspired lighting treatment, not a new aircraft or an assertion that solid imported foam is translucent. Selecting a preset materializes its values; it is not a mutable name-only reference.

## Qualification record

Pinned engine: `4.8.beta1.official.4d10419ca`. Primary visual target: 1920×1080. Checked runner logs are retained under ignored `tmp/godot-checks/`; no generated screenshots are committed.

| Check | Result |
| --- | --- |
| Lighting profile validator | 55 checks, 0 failed |
| Presentation v1/v2/v3 validation and identity | 85 checks, 0 failed |
| Combined renderer, persistence, preview and flight | Pending integration |
| Native Compatibility 1920×1080 | Pending |
| Forward+, higher-resolution matrix and GPU budgets | Unqualified |
| Pilot orientation and night flight acceptance | Open, FW-N |

## Remaining masterplan work

Automatic fitted strips are the baseline. Authored internal foam shells/emission masks, arbitrary creator-authored paths and portable binding authoring need their own asset/schema implementation and acceptance. They are not inferred from opaque model surfaces. Hardware-tier budgets, distance-based simplification across companion aircraft, and a broad native renderer/resolution matrix remain acceptance work. The existing night scenery is reused; no new moon/sky renderer is claimed.
