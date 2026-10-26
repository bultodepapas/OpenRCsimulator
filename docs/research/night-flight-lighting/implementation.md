# FW-RGB implementation and qualification

2026-10-25. The user approved implementation after the [masterplan](../../night-flight-lighting-masterplan.md). This record covers the integrated RGB renderer, profile and Workshop implementation. It does not close pilot gate FW-N or establish hardware performance.

## Boundaries and decisions

- Extend the existing `AircraftLights`/`NightKit`; retain `AircraftLightState` AUTO/ALL/NAV/OFF, 17:30 local-time behavior and session reset policy. Historical profiles use the old lazy path.
- Presentation envelope v3 adds a required data-only `lighting` field. Explicit v1/v2 readers retain their schemas and identities. The existing v1 smoke migration still produces a reviewable v2 proposal; lighting editing then extends it to v3.
- The concurrently introduced v4 envelope retains lighting and adds mechanical audio. Lighting edits preserve v4 and its audio payload; they never downgrade it to v3.
- The initial RGB slice retained companion v3 and advanced `source_proof_version` to 3. FW-RGB-04 now adds creator layout schema v1 through source v3 / companion v4, keeping proof version 3 and its existing ordered 23-source inventory. Historical companion readers remain explicit.
- Reuse the immutable variant store, bundle format, trial freeze, shared Workshop history and atomic recovery transactions. Recovery adds an optional strictly bounded lighting editor buffer; historical snapshots remain readable.
- Separate the visual identity from compiled flight identity. Lighting never changes the solver state, propulsion, battery drain or recorded controls.
- Derive kit geometry through the established fitter and honor existing root `light_anchors`, `light_groups`, imported lens bindings and articulated gear gates. Profile data carries no paths, transforms or executable code.
- Use per-instance pattern phase and exposure. Phase derives from displayed simulation time; Workshop owns an independent 240 Hz preview clock. No shader uses engine `TIME`.
- Keep the existing sky, moon, atmosphere, runway and scene exposure. Do not enable compulsory bloom or change global tonemapping for RGB.
- Field spot validation reserves two of Compatibility's eight per-mesh slots for paired aircraft landing lights. The accepted default field uses five spots. Decorative RGB spill uses the separate OmniLight budget.
- Airspeed response uses a presentation scale of 0–40 m/s; this is not an aircraft limit. Roll/pitch reactions consume accepted body rates; no render-side flight model is added.
- Pausing freezes the displayed pattern phase and inhibits new show-effect events. Faults and crashes also inhibit new events; reset clears transient pools and resumes the existing AUTO policy.
- Apply brightness and animated envelopes after the emitter's exposure cap, so dark-adapted worlds do not flatten breathing/chase modulation. Lamp `source_color` values are decoded only once. True airspeed uses m/s and the documented 40 m/s visual response scale.
- Reconcile profile visibility after dynamic gear updates, including paired landing lamps/beams, and retain unsupported equipment groups. Known imported `light_red`/`light_green` lenses follow their semantic navigation zones; unmapped emissive materials retain group controls with an explicit warning.

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
| Pattern evaluator, including airspeed units | 18 checks, 0 failed |
| Lighting save/load, bundle round trip, recovery and rejected-save preservation | 10 checks, 0 failed |
| Existing Workshop store / bundle / draft recovery / profile transfer | 141 / 28 / 102 / 22 checks, 0 failed |
| Workshop lighting editor, shared sequence Undo/Redo/pending/recovery, additive v1/v2 migration and v4 audio preservation | 0 failures |
| Pure cue editing / standalone sequence editor | 25 / 33 checks, 0 failed |
| Workshop preview / existing smoke preview / customization integration | 0 failures / 113 checks, 0 failed / 0 failures |
| Aircraft customization / smoke bindings / legacy fitted kit / P-51 dynamic mounts | 159 / 28 / 36 / 13 checks, 0 failed |
| Customization generator reproducibility | 13 tests, passed |
| Presentation source closure | 203 checks, 0 failed |
| Renderer capabilities, gear gates, lamp patterns and imported emissions | 30 checks, 0 failed |
| Real RGB flight controls, paused cue suppression and reset | 11 checks, 0 failed |
| Shared aircraft light controls, including helicopter | 173 checks, 0 failed |
| Workshop shell trial / return, including missing Home display preferences | 0 failures |
| Native Compatibility 1920×1080 | Inspected Workshop and full-moon flight; save/restart/load/Test fly, L and Restart passed; clean exit, 0 leaked objects |
| Forward+, higher-resolution matrix and GPU budgets | Unqualified |
| Pilot orientation and night flight acceptance | Open, FW-N |

### Native evidence and limits

Native runs used Windows, Godot `4.8.beta1.official.4d10419ca`, Compatibility/OpenGL 3.3 and an NVIDIA RTX 3090 (driver 617.42), at 1920×1080. They establish functional integration and a visual inspection on this machine, not a frame-time budget or low-end qualification. The final run recorded no engine/script errors; the log retained the existing aircraft-data warning and construction/catch-up hitch events.

- `tmp/debug-bridge/20261025-173300-49957/`: night-preview exposure calibration; clean exit.
- `tmp/debug-bridge/20261025-174003-54749/`: Festival preview inspection. This run found the direct-route Test fly null display-preference bug, subsequently fixed and covered by `test_workshop_integration.gd`.
- `tmp/debug-bridge/20261025-180145-50975/`: final-source Save/Test fly and saved build used by the next process. The separate `--time-of-day=20:00` SDR snapshot retained exposure 0.6 and was too dark for night visual acceptance. No global environment change is included in FW-RGB to mask that existing path's limitation.
- `tmp/debug-bridge/20261025-180417-47870/`: loaded the same saved Festival revision after process restart, using `--time_of_day=night` (Home's **Night, full moon** route). Inspected pilot, chase, close-up and underside orbit views; existing sky, moon, field lights and shape remained visible. Shots 005/006 compare a breathing interval under the same adapted exposure (about 49,131); shot 007 samples the 8.1-second Festival cue with both spark pools. These three shots use a frozen presentation pose and explicitly supplied visual clocks for repeatable effect inspection, not a live-flight performance measurement. Normal pause and cue behavior is separately covered by the real-flight test. L selected NAV; Restart restored AUTO. Exit reported no crash and zero leaked objects.

The full-moon capture also exposes a bright lake-reflection artifact outside the lighting rig. That scenery issue and the SDR fixed-time route remain visual qualification limits. Captures/logs stay in ignored `tmp/`; no images are added to Git. Reproduce the supported night scene with Home's night preset or the existing `--time_of_day=night` argument, rather than interpreting the similarly named SDR snapshot flag as equivalent.

### FW-RGB-09 sequence authoring

`app/workshop/lighting_sequence.gd` supplies clone-then-validate cue edits; `app/ui/workshop_lighting_sequence.gd` supplies the expandable Workshop editor. Users can add, duplicate, move and remove cues, edit duration/cycle/palette, and choose enabled zone/effect targets. Structural edits and Apply cue enter the existing shared presentation history. Pending fields block Save/Test fly and navigation; Cancel restores accepted state. A bounded optional `sequence` buffer extends the existing recovery object without changing its version or rejecting historical four-field lighting buffers. No renderer, accepted lighting schema or simulation source was changed for this package.

The 32-cue/60-second caps remain authoritative in `LightingProfile`. Cue targets become Sequence zones; zones losing their final cue return to steady lighting. At least one cue must retain a zone target, including when other cues are effect-only. Navigation targets require releasing the existing orientation lock. Editor timing is quantized to the existing 240 Hz clock. Playback uses Restart preview and Play preview; no scrubbing or second clock is introduced.

Additional native receipts (same pinned engine/GPU/1080p setup):

- `tmp/debug-bridge/20261025-190807-47870/`: duplicate/reorder, invalid-duration Save/Test fly guard, accepted 2.5-second duration, Undo to 4 seconds / Redo to 2.5 seconds, saved five-cue revision and preview playback. Shot 002 shows the cue list/actions; shot 003 shows palette/targets and saved status. Clean exit, zero leaked objects.
- `tmp/debug-bridge/20261025-191014-47870/`: separate process, same isolated profile; loaded that revision and verified five cues and 600 ticks in the first cue. Final component labels and 200% text scale inspected at 1920×1080 (shots 001/002); restored 100% and Test fly loaded the custom rig. Clean exit, zero leaked objects, no engine/script errors.

The earlier `20261025-190653-47870` launch encountered a transient concurrent physics signature edit in `slipstream.gd`/`swirl_loads.gd`. It was stopped; it is not acceptance evidence. The subsequent app parse and the two runs above passed after that external edit settled. No physics files were edited by this package. Native receipts establish UI behavior, not hardware performance or pilot acceptance.

### FW-RGB-04 authored layouts and reviewed upgrades

Source v3 / companion v4 adds `lighting_layout` v1. Python and runtime readers enforce closed fields, semantic IDs, descendant paths, numeric/vector/width limits and nondegenerate bounded polylines. `Airplane.build` projects validated data; the existing kit resolves it per instance, preserves builder-owned point anchors, and retains fitted equipment for omitted or missing hosts. Authored strips track complete host transforms. Empty geometry creates an empty diagnosed kit rather than nonfinite lamp coordinates. The six shipped family declarations are intentionally empty: legacy placement is retained, and no manually tuned stock layout or translucent skin is claimed. See the [creator contract](../../AIRCRAFT-LIGHTING.md#creator-authored-layouts-fw-rgb-04).

The unchanged whole-companion hash makes older saved pins stale. `presentation_rebind.gd` provides an explicit, nonmutating proposal for the same physical manifest and visual family; Workshop reviews it and creates an unsaved copy. Original revisions are preserved. Only binding pins may change; missing references, future schemas and nonempty smoke are refused. This does not prove old/new descriptor equivalence or repair physical dependencies.

Additional checks on the pinned engine: authored layout validation/transforms/fallback/admission **28**, proposal **18**, Workshop review/cancel/Undo/Redo/save-copy preservation **11**, all passed. Existing customization **159**, presentation **85**, source proofs **203**, smoke bindings **28**, RGB rig **30**, kit **36**, P-51 moving mounts **13**, Home cache **118**, and lighting persistence **10** passed. The sequence Workshop regression also passed. Final Workshop integration passed with zero failures, including trial return, retained physical state and direct Pause entry without Home services. Generator validation/reproducibility passed **17 Python tests** both in the workspace and a fresh sparse clone with the scoped candidate files applied (`tmp/fw-rgb-layout-clean`). That check covers generation, not a fresh exported application.

Native Windows/Compatibility/RTX 3090, 1920×1080: `tmp/debug-bridge/20261025-193239-47870/` loaded the actual earlier five-cue build, reviewed its stale bindings, accepted and saved a new identity with five cues/600 ticks in cue 1. It exposed a dialog wrapping issue, fixed afterward. `tmp/debug-bridge/20261025-193450-47870/` loaded the new copy after process restart; the original still offered update review. Shot 002 verifies the corrected dialog wrapping. Cancel preserved the original. The new copy entered Test fly with the first cue still 600 ticks. Both runs exited cleanly with zero leaked objects; no engine/script errors were recorded. Later dialog copy/theme-refresh polish retains the same wrapping layout and is covered by the focused Workshop regression. No asset art/performance/pilot qualification is inferred from these receipts.

### FW-RGB-05 authored path progression and complete cue updates

Authored strip geometry now stores cumulative normalized host-local path distance in UV.y. The RGB material explicitly selects it; automatic fitted strips keep the established axis projection. This corrects patterns that collapsed on paths perpendicular to the canonical axis or folded when an authored path doubled back. Unequal segments receive proportional pattern space. Host transforms retain the station colors; nonuniform scaling stretches their world spacing. No per-frame mesh rebuild, new rendering subsystem or profile-schema change is introduced.

The previous 48-write guard could discard part of a simultaneous cue update and still record its signature as complete. The closed set of nine lamp meshes and five strips now has a justified 84-uniform maximum per `advance`, plus a separate 23-uniform allowance per synchronous `set_mode`. Only exact semantic mesh names enter this set; landing-beam aliases remain in the Light3D path. Unrelated kit meshes retain their materials. Guard failures are diagnosed, and cue signatures remain pending until all three pattern uniforms succeed. These are bounds on individual operations, not whole-scene GPU or per-frame CPU qualification.

Checks on the pinned engine: `test_lighting_path.gd` passes **5 headless checks**; `test_lighting_rig_budget.gd` passes **18**, including two real cues across all thirteen zones/fourteen materials, dirty-cache worst case, mode gain after a full advance, exhausted-guard retry and alias/unknown-mesh preservation. Existing rig **30**, layout **28**, patterns **18**, fleet kit **36**, P-51 mounts **13**, source proofs **203** and Python generation **17** pass. Generated companion source hashes were refreshed through the existing generator. Draft budget tests initially had incorrect preset/signature/gain expectations; these were corrected to use the full Custom profile, resolved cue state and effective brightness before acceptance. No simulation source or flight golden was changed by this package.

The actual shader fixture also passes **11 checks per renderer** at **1920×1080** on Windows / RTX 3090: Compatibility (OpenGL 3.3, driver 617.42), Forward+ and Mobile (Vulkan 1.4.351). It first reproduces the old axis-projection error (red where the third segment should be blue), then samples correct forward, reverse and rotated/scaled path colors. Captures were visually inspected; the fixture is a ribbon on black, not aircraft art or pilot-readability acceptance. Final captures are under ignored `tmp/fw-rgb-path/final-gl_compatibility/`, `final-forward_plus/` and `final-mobile/`; checked-runner receipts use labels `rgb-path-final-gl_compatibility`, `rgb-path-final-forward_plus` and `rgb-path-final-mobile`. All native runs completed without engine/script errors. This tests the Mobile renderer on this desktop GPU, not mobile hardware performance.

Reproduce with the pinned checked runner and `res://tests/test_lighting_path.gd`: omit `--headless`, select `--rendering-method gl_compatibility|forward_plus|mobile`, and use `--resolution 1920x1080`. Optionally append `-- --capture-rgb-path=<absolute-directory-under-tmp>`. Headless runs explicitly skip pixel checks. Captures remain outside Git.

### FW-RGB-12 aircraft support feedback

The rig now exposes a detached, read-only `capability_report()` from its actual configured bindings. It returns only requested zones/effects, canonicalizes paired landing hardware, distinguishes unsupported groups from missing fittings/anchors, and preserves lazy inherited/disabled states. The report allocates no aircraft nodes or effect pools. Review corrected an initially overstrict assumption: VFX needs a mapped live tip and render world, not an enabled navigation light or navigation-group admission. Likewise, a compatible semantic mesh already consumed by the rig remains available even if absent from the legacy group-membership list.

Workshop shows enabled/available counts first, with **View aircraft support** for details and per-zone/effect reasons in advanced controls. Missing hardware does not discard choices, disable editing, or manufacture a flight-validation failure. Feedback follows applied lighting settings; it never writes presentation data or pending buffers. Original/Draft, day/night, identical-profile refresh, aircraft replacement and a missing preview root all clear or refresh the report appropriately. No persisted schema, physics or preference change is included.

Checked engine results: new capability tests **19**, new Workshop integration tests **16**, existing rig **30**, presentation source proofs **203**, and Python generation **17**, all passed. The existing Workshop lighting/sequence/recovery regression passed with zero failures. The first Workshop fixture incorrectly counted disabled optional Custom zones as enabled; it now explicitly enables all thirteen. A concurrent source-proof mismatch interrupted a later run before generation was refreshed; that run was stopped and is not acceptance evidence. Final checks used the current generated companion.

Native Windows / Compatibility / RTX 3090 at 1920×1080: `tmp/debug-bridge/20261025-203650-47870/` inspected the collapsed summary, expanded support details (shot 002), missing dorsal-light reason (shot 005), and readable 200% text layout (shot 006). Enabling and applying the missing dorsal light changed **8 of 8** to **8 of 9** available while retaining a valid build (shot 007). Original comparison displayed its own message; returning to Draft restored the count and selected-zone reason. Text scale returned to 100%. The app exited cleanly with zero leaked objects and no engine/script errors; existing inertia-warning and scene/catch-up hitch events remain in the log. Captures stay under ignored `tmp/`. This delivers capability messaging within FW-RGB-12, not its remaining preset art pass or FW-N pilot acceptance.

## Remaining masterplan work

Automatic fitted strips are the shipped baseline. Creator point mounts and bounded strip polylines now have a versioned contract; a fleet placement/art pass remains. Authored internal foam shells/emission masks and arbitrary VFX attachment paths remain separate asset/schema work. They are not inferred from opaque model surfaces. Workshop cue-list authoring is implemented. Timeline scrubbing and arbitrary keyframe tracks remain outside this package. Hardware-tier preferences, scene-wide budgets across companion aircraft, and a broad native renderer/resolution matrix remain acceptance work. The existing night scenery is reused; no new moon/sky renderer is claimed.

The plausible foam candidate's [source manifest](../../../assets/aircraft/turbo-lumber-evolution/source-manifest.json) still limits use to internal evaluation with D1/TT-17 packaging clearance pending. FW-RGB-07 therefore has no approved distributable skin asset in this audit. Resolve asset eligibility and the explicit raw-asset proof inventory before adding masks; the RGB renderer does not infer translucency from opaque imported skins.
