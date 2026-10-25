# FW-RGB implementation and qualification

2026-10-25. The user approved implementation after the [masterplan](../../night-flight-lighting-masterplan.md). This record covers the integrated RGB renderer, profile and Workshop implementation. It does not close pilot gate FW-N or establish hardware performance.

## Boundaries and decisions

- Extend the existing `AircraftLights`/`NightKit`; retain `AircraftLightState` AUTO/ALL/NAV/OFF, 17:30 local-time behavior and session reset policy. Historical profiles use the old lazy path.
- Presentation envelope v3 adds a required data-only `lighting` field. Explicit v1/v2 readers retain their schemas and identities. The existing v1 smoke migration still produces a reviewable v2 proposal; lighting editing then extends it to v3.
- The concurrently introduced v4 envelope retains lighting and adds mechanical audio. Lighting edits preserve v4 and its audio payload; they never downgrade it to v3.
- Keep companion schema v3 because this slice adds no authored mount fields. Advance its independent `source_proof_version` to 3 to pin the new rendering closure. A future authored lighting binding schema remains a separate versioned extension, not a fabricated registry.
- Reuse the immutable variant store, bundle format, trial freeze, shared Workshop history and atomic recovery transactions. Recovery adds an optional strictly bounded lighting editor buffer; historical snapshots remain readable.
- Separate the visual identity from compiled flight identity. Lighting never changes the solver state, propulsion, battery drain or recorded controls.
- Derive kit geometry through the established fitter and honor existing root `light_anchors`, `light_groups`, imported lens bindings and articulated gear gates. Profile data carries no paths, transforms or executable code.
- Use per-instance pattern phase and exposure. Phase derives from displayed simulation time; Workshop owns an independent 240 Hz preview clock. No shader uses engine `TIME`.
- Keep the existing sky, moon, atmosphere, runway and scene exposure. Do not enable compulsory bloom or change global tonemapping for RGB.
- Field spot validation reserves two of Compatibility's eight per-mesh slots for paired aircraft landing lights. The accepted default field uses five spots. Decorative RGB spill uses the separate OmniLight budget.
- Airspeed response uses a presentation scale of 0–40 m/s; this is not an aircraft limit. Roll/pitch reactions consume accepted body rates; no render-side flight model is added.
- Pausing freezes the displayed pattern phase and inhibits new show-effect events. Faults and crashes also inhibit new events; reset clears transient pools and resumes the existing AUTO policy.

## Implemented data contract

`app/render/lighting/lighting_profile.gd` owns the closed `openrc-aircraft-lighting` v1 payload and presets. The envelope accepts `inherit`, `preset`, `custom` and `disabled`; explicit disabled is never interpreted as a missing profile. The thirteen initial semantic zone IDs match existing kit nodes. Effect anchors are `vfx_tip_left` and `vfx_tip_right`, resolved from the existing fitted tips.

Limits include 32 zones, eight colors per pattern, 32 sequence cues, a 60-second sequence, 24 KiB lighting payload, 6,144 lighting JSON nodes, and two enabled effect anchors. Numeric booleans, nonfinite values, unknown keys, duplicate IDs, invalid colors, unsupported versions and invalid cue references are rejected before rendering. The outer profile is bounded at 64 KiB and 8,192 nodes.

Presets are Classic RC, Night Radian, Neon RGB, Night Aerobatics, Festival / Fireworks and Custom. Night Radian is an inspired lighting treatment, not a new aircraft or an assertion that solid imported foam is translucent. Selecting a preset materializes its values; it is not a mutable name-only reference.

Workshop exposes presets first, then zone enable/brightness, palette colors, pattern/cycle, telemetry response, and optional spark/trail/burst kind, intensity and lifetime. Invalid or unapplied advanced values block Save/Test fly. Shared Undo/Redo and draft recovery retain accepted profiles and pending color text. Navigation lock protects color/pattern editing; it is not an attitude-responsive renderer. Custom exposes all thirteen semantic zones, subject to the aircraft's supported groups and fitted equipment.

The preview owns its environment, exposure and clock. Its night setting uses exposure 8.0 with ambient/key/fill energies 0.025/0.025/0.015; daytime settings are unchanged. This calibration is a Workshop inspection view, not a replacement for the world's night exposure. Ground geometry receives the bounded real light spill. No global shader exposure or time value is changed by preview playback.

Per rig, decorative spill is capped at two shadowless OmniLights and fades out from 20 to 40 m. Show effects permit two anchors, each with at most 32 spark instances or 63 ribbon segments, fading from 60 to 120 m. Pattern materials are owned by the instance; emission does not stand in for real illumination. These are enforced allocation limits, not measured frame-time promises.

## Qualification record

Pinned engine: `4.8.beta1.official.4d10419ca`. Primary visual target: 1920×1080. Checked runner logs are retained under ignored `tmp/godot-checks/`; no generated screenshots are committed.

| Check | Result |
| --- | --- |
| Lighting profile validator, including JSON round trips and numeric rejection | 64 checks, 0 failed |
| Presentation legacy/current validation and identity | 85 checks, 0 failed |
| Pattern evaluator | 17 checks, 0 failed |
| Lighting save/load, bundle round trip, recovery and rejected-save preservation | 10 checks, 0 failed |
| Existing Workshop store / bundle / draft recovery / profile transfer | 141 / 28 / 100 / 22 checks, 0 failed |
| Workshop lighting editor, additive v1/v2 migration and v4 audio preservation | 0 failures |
| Workshop preview / existing smoke preview / customization integration | 0 failures / 113 checks, 0 failed / 0 failures |
| Aircraft customization / smoke bindings / legacy fitted kit / P-51 dynamic mounts | 159 / 28 / 36 / 13 checks, 0 failed |
| Customization generator reproducibility | 13 tests, passed |
| Presentation source closure | 203 checks, 0 failed |
| Final renderer gates, flight pause and shell trial regression | Final verification in progress |
| Native Compatibility 1920×1080 | Preview inspected; final flight check in progress |
| Forward+, higher-resolution matrix and GPU budgets | Unqualified |
| Pilot orientation and night flight acceptance | Open, FW-N |

## Remaining masterplan work

Automatic fitted strips are the baseline. Authored internal foam shells/emission masks, arbitrary creator-authored paths and portable binding authoring need their own asset/schema implementation and acceptance. They are not inferred from opaque model surfaces. Sequence playback and validation are implemented; editing cue lists is currently data-only, with Workshop allowing Sequence on zones that already have saved cues. A visual cue timeline remains future work. Hardware-tier preferences, scene-wide budgets across companion aircraft, and a broad native renderer/resolution matrix remain acceptance work. The existing night scenery is reused; no new moon/sky renderer is claimed.
