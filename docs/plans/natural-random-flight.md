# Natural Random flight mode

**Date:** 2026-10-13. **Status:** initial runtime implementation; software evidence and remaining acceptance are tracked [here](../research/natural-random/README.md). Pilot handling, full readability and target-hardware acceptance remain open. **Owner:** Natural Random track, coordinated with UI, M5-W/M5-ATM, TOD/FW and the simulation/aircraft owners. **Step IDs:** NR-00…09 ([registry](../README.md#tracks-plans-and-step-ids)).

**Outcome:** choose **Natural Random / Aleatorio natural** from Home, see a short briefing, and fly a stock airplane in a believable, varied day. Some flights are calm; others have substantial wind. The aircraft remains readable in the qualified flying area. Restart repeats the same conditions; another draw creates another flight.

The current scenario contract requires the default field. Select **Club field** on Home; Green paradise disables Natural Random with an explanation. Landscape registration and selection are owned by [L21–L24](landscape-selection.md); this mode does not switch landscapes automatically.

This is recreational free flight. It adds no score, mandatory maneuver, aircraft modification, hidden failure or artificial control assistance. The randomizer composes existing simulator inputs; the flight solver remains authoritative.

## 1. Scope and evidence

The initial audit used the working tree on 2026-10-13, based on commit `5b924758`, including existing uncommitted work. Graph discovery was followed by current-source inspection because several indexed symbols had stale line ranges. The table records the baseline that informed implementation; dated software results live in the linked evidence, separately from physical-validation claims.

| Current code / authoritative guide | Observed behavior | Consequence for this mode |
| --- | --- | --- |
| [app_root.gd](../../app/app_root.gd): `show_home()`, `start_flight()`, `restart_flight()`, `end_flight()`; [menu guide](../MENU-PLAN.md) | Home resolves choices into `main.tscn`; failed interactive startup restores Home. Successful normal launches save start/weather/lighting. | Introduce an explicit launch request; a random draft must not overwrite the user's normal-flight preferences. |
| [home.gd](../../app/ui/home.gd), [screen_stack.gd](../../app/ui/screen_stack.gd), [screen.gd](../../app/ui/screen.gd) | Shared screens, focus restoration, input isolation and named session holds already exist. | Add one screen using these components. Do not create another menu/input framework. |
| [aircraft_catalog.gd](../../app/app_state/aircraft_catalog.gd); [Workshop guide](../AIRCRAFT-WORKSHOP.md) | Seven shipped configurations, five visual families. `can_fly()` includes experimental entries. Workshop passes a detached `workshop_trial` into the flight. | Stock provenance, random eligibility and physical-validation status are three separate concepts. Never draw from Workshop storage. |
| [main.gd](../../app/main.gd): `_ready()`, `_weather_options()`, `_build_world()` | Accepts `aircraft_id`, `field_path`, `start_choice`, `weather_config`, `lighting_config` before entering the tree. Builds the model/world, configures weather and checks session startup. | Reuse the actual interactive launch path and its failure reporting. Do not implement a second flight setup routine. |
| [flight_session.gd](../../app/sim/flight_session.gd): `setup_weather()`, `reset()`, `_reset_airborne_start()`, `_reset_selected_runway_start()` | Weather affects trim and initial state. Airborne reset adds wind in body coordinates to preserve trimmed airspeed. Runway setup solves contact under initial wind. | Configure weather before accepting the start. Use trimmed airborne starts for the first release; preserve physical wind handling. |
| [wind_config.gd](../../app/physics/wind_config.gd), [wind guide](../WIND-PLAN.md) | Strict weather v1/v2/v3 inputs; mean wind, repeating gusts and seeded turbulence. Existing recipes include calm, steady, crosswind, gusty, updraft, turbulent and gentle practice. | Generate bounded combinations using the current kernel. Schema maxima are not suitable random ranges. |
| [atmosphere.gd](../../app/physics/atmosphere.gd), [atmosphere guide](../ATMOSPHERE-PLAN.md) | Field elevation, temperature, QNH and relative humidity derive density and engine charge through weather v3. | Draw compatible atmosphere inputs and let the existing model derive their effects; never randomize density or thrust separately. |
| [time_of_day_config.gd](../../app/environment/time_of_day_config.gd), [time_of_day_lighting.gd](../../app/render/time_of_day_lighting.gd), [time guide](../TIME-OF-DAY-PLAN.md) | Strict, scene-local astronomical lighting configuration and fixed-time snapshots exist. | Resolve a readable solar position into this configuration; store it with the scenario. |
| [conditions.gd](../../app/render/world/conditions.gd), [world.gd](../../app/render/world/world.gd), [world guide](../FIELD-WORLD-PLAN.md) | Legacy Home presets/passing evening and TOD snapshots are separate routes. `World.build()` changes shared world/atmosphere state and clears old progression for a snapshot. | Do not combine both clocks, inherit passing evening, or build a second live world merely to preview a draw. |
| [render/atmosphere.gd](../../app/render/atmosphere.gd): `visibility_m`, `_visibility_from_args()` | Artistic default/hazy/clear visibility presets exist through `--visibility`; they are shared render state, outside the weather and lighting contracts. | Keep current visibility in v1. NR-07 must give any randomized haze explicit scene-local ownership and recording. |
| [main.gd](../../app/main.gd): `_trace_meta()`, `checkpoint()`, `restore_checkpoint()`; [visual_checkpoint.gd](../../app/app_state/visual_checkpoint.gd) | Physics identity, weather and visual history already have strict recording/checkpoint contracts. Progressing visual checkpoint acceptance remains limited. | Keep scenario metadata outside weather/lighting dictionaries; extend envelopes deliberately instead of adding unrecognized keys. |
| [menu redesign](../MENU-REDESIGN-PLAN.md), [camera](camera-views.md), [overlays](flight-overlays.md), [aircraft standardization](aircraft-standardization.md) | Current and proposed features coexist; UI-22…29 are not prerequisites for a working screen. Other vehicle families have their own integration gates. | Deliver on today's shell, then move the same action into Home v2. Admit future content only after explicit qualification. |

No assets or dependencies are required for the first release. Reuse the current aircraft, field, clouds, sounds and widgets. If later cloud work needs assets, evaluate existing freely downloadable assets and their licenses before authoring replacements.

## 2. What “standard aircraft” means

The initial pool contains the following **unmodified shipped configurations**, with one entry per familiar airframe:

| Catalog ID | Airplane | Policy |
| --- | --- | --- |
| `jensen-das-ugly-stik-60` | Jensen Das Ugly Stik 60 | Baseline sport trainer. |
| `gp-extra-300s-60` | Great Planes Extra 300S .60 | Stock aerobatic airplane; retain its experimental status note. |
| `p51d-mustang-120` | P-51D Mustang 1/4 | Stock warbird; retain its experimental status note. |
| `sebart-avanti-s-a200-p100rx` | Ventage Jet | Stock jet; airborne only, existing gear/flaps limitations remain. |
| `turbo-lumber-evolution` | Turbo Lumber Evolution | Stock electric STOL airplane; existing flaps/assist limitations remain. |

`stik-glow-55ax-2t` and `stik-glow-fs64v-4t` are also shipped stock configurations, not user modifications. Defer their admission to a later eligibility revision: this keeps the initial qualification matrix bounded and avoids making the Stik three times as common. If admitted, draw airframe family first and configuration second.

Do not filter solely by `status == FLYABLE`: that would leave only the base Stik. Preserve the current experimental disclosures in the briefing. “Standard” does not claim flight validation.

Eligibility must be explicit and default to **excluded** for new catalog entries. Each allowed ID must also resolve to packaged data, pass normal aircraft validation, have a valid visual binding and support the required start/environment. Missing or invalid content produces an error, never a substituted model. Exclude `PREVIEW`, Workshop variants/trials, external experimental data overrides and synthetic propulsion demos. Do not change scale, mass, CG, surfaces, motor, propeller or tuning.

## 3. Player experience

### Home and briefing

Add **Natural Random / Aleatorio natural** beside the existing Fly action, using the existing Home scrolling layout. Keep ordinary Fly as the usual primary action. The new action opens a briefing screen and draws once.

```text
Home → Aleatorio natural

ALEATORIO NATURAL
Turbo Tronco Evolución · Avión estándar
Mañana luminosa · Brisa suave
Viento desde el E: 2,0 m/s · Incremento de ráfaga: 0,6 m/s
Inicio en vuelo · Campo actual

[Volar]   [Otro vuelo]   [Volver]
Detalles: condiciones, estado del modelo y código del vuelo
```

The example values are illustrative. With turbulence active, do not describe mean-plus-gust as an absolute maximum: show “gust increment” or a labeled estimated range instead. Display wind **from** direction, speed, gust character, time/light, airplane and start type. Show density/temperature and seed in Details, not raw dictionaries or solver settings in the main flow.

- **Fly:** launch exactly the displayed, accepted candidate. Disable duplicate activation while preparing.
- **Another flight:** generate a new candidate. Do not change the current Home aircraft, weather, lighting or preferences.
- **Repeat last flight:** appears after a random flight has been accepted. Reopening Natural Random from Home still draws a new draft; this secondary action replaces that draft with the last accepted scenario and refreshes the briefing. Fly then launches that exact selection. Keep the last accepted record unchanged by unlaunched rerolls.
- **Back / Esc:** discard the draft and restore focus to the Natural Random button.
- Use a static aircraft thumbnail/name from existing resources for v1. Keep the ordinary Home backdrop; do not pretend it previews the candidate's weather. No extra running simulation or world behind the briefing.
- Source strings remain English and Spanish translations go through `es.po`. Keyboard and mouse use the existing stack; radio sticks remain isolated from menu focus. Respect current HUD, audio, display, controls and camera preferences/behavior.

One balanced random distribution is enough for v1; no difficulty/settings wizard is required. A future “More relaxed / Varied / More wind” choice may change recipe weights after qualification, without changing aircraft physics.

### In flight, pause and restart

The accepted scenario belongs to that flight. Enter/Fly must not leak into throttle or another flight action. Preserve low-throttle arming, focus-loss pause, calibration and named holds. Detached preparation remains held/input-disabled; successful launch uses the current interactive key-masking and arming handoff. V1 adds no post-launch confirmation, countdown or new hold for the pilot to release.

**Restart / R** repeats the same aircraft, complete weather selection, turbulence seed, lighting and start. It resets to time zero, including gust phase and existing turbulence state initialization. It never draws a new seed. **Continue** resumes without resetting anything. Crashes keep the same restart semantics.

For v1, new draws start from Home: use **End flight**, then open **Natural Random** again. Remember the last accepted scenario in application memory to offer **Repeat last flight** as described above. This avoids replacing a live flight with a second world while both share rendering globals. A pause shortcut that ends the current flight and opens the briefing can be added later, labeled explicitly as ending it; it must retain the existing trace-save failure behavior.

Today wind/atmosphere editing is Home-only; lighting can be edited from pause. Preserve that availability in v1 and keep briefing details read-only. The pause lighting editor must read the active random flight's conditions, not unrelated normal-flight preferences. Applying an edit makes the scenario **Custom from Natural Random**, records that change and preserves the existing lighting history/restart rules. The edited lighting becomes that flight's restart selection. Show this distinction; do not keep claiming the original seed regenerates an edited flight. Do not persist that edit into normal-flight defaults automatically. Any later weather editor for an active scenario follows the same explicit context policy, coordinated with UI-26.

## 4. What to randomize

| Quantity | First release | Constraint / reason |
| --- | --- | --- |
| Airplane | Yes, equal probability across the five eligible IDs | Resolve a stock aircraft before choosing its compatible conditions. |
| Mean wind speed and direction | Yes | Validated per-aircraft recipe envelope; meteorological `from_deg`, NED internally. |
| Gust amplitude, duration, interval and delay | Yes, together | Smooth existing gust kernel; modest vertical component; a grace interval before the first repeating gust. |
| Turbulence strength, correlation time and seed | Yes | Reuse current seeded correlated turbulence; do not add random control inputs or per-frame forces. |
| Morning/day/late-afternoon lighting | Yes | Fixed astronomical snapshot in the readable solar window; no unexpected darkness during a long flight. |
| Temperature, humidity and QNH | Yes, through coherent recipe bands | Weather v3; derived density/charge and re-trim must succeed. |
| Field | Current field only | One qualified production field today; no invented field catalog or randomly moved obstacles. |
| Start position, attitude and speed | Established trimmed airborne start | No random stall, inverted spawn, low-altitude surprise or arbitrary initial velocity. |
| Cloud coverage/haze | Later NR-07 | Current cloud rendering exists, but there is no validated scene-local random sky-appearance input in the lighting contract. |
| Time progression, runway start | Later NR-08 | Need clock/readability and wind/runway lifecycle qualification respectively. |
| Controls, rates/expo, calibration, assists, camera, HUD, volume | Never chosen by this mode | These are pilot preferences or aircraft behavior, not weather. |
| Aircraft dimensions, CG/mass, powerplant, damage/faults, fuel/battery depletion at spawn | Never chosen by this mode | Healthy stock starting state; normal subsequent propulsion/resource behavior remains. |
| Rain, snow, icing, lightning, wet friction, thermal columns, ridge/obstacle rotor | Not in v1 | No random menu option should imply missing physical or visual behavior. Each needs its owning model and acceptance first. |

### Coherent weather recipes

Draw a **weather recipe**, then draw its related values. Avoid uniform independent draws across every validator's full range. Keep weather selection constant during a flight; the existing gust/turbulence kernels supply time variation.

Initial design targets below are **estimated gameplay candidates**, not measured climate frequencies, certified RC operating limits or accepted flight envelopes. NR-03 qualifies and may narrow them before release.

| Recipe | Target weight | Mean speed | Horizontal gust increment | Character |
| --- | --- | --- | --- | --- |
| Calm air | 20% | 0–0.5 m/s | 0–0.2 m/s | Include genuinely still draws: all wind/gust/turbulence zero. |
| Gentle breeze | 40% | 0.5–3 m/s | 0.2–0.8 m/s | Center around existing `gentle-practice`; occasional small corrections. |
| Lively afternoon | 25% | 3–5 m/s | 0.5–1.5 m/s | Noticeable drift and gusts, still useful for circuits and aerobatics. |
| Windy day | 15% | 5–8 m/s | 1–2 m/s | Deliberate stronger-wind variety; clearly briefed and enabled only for qualified airplane/condition pairs. |

Use smooth bounded distributions concentrated near recipe centers. Start with turbulence RMS bands of 0–0.08, 0.05–0.2, 0.15–0.4 and 0.25–0.6 m/s per horizontal axis respectively, and a smaller vertical RMS. Proposed gust durations are 3–8 s, periods 12–30 s with period strictly greater than duration, and initial delay 5–10 s. Use correlation times around 2–6 s and keep vertical gust amplitude at or below 0.3 m/s in v1 candidates. Exact bands belong in versioned recipe data after qualification.

These are separate from `WindConfig.validate()` caps: 15 m/s mean, 8 m/s gust, ±8 m/s vertical gust and 3 m/s RMS per axis are input limits, not recommended fun settings. OU turbulence has unbounded statistical tails: a “3 sigma” screen is a diagnostic, never a guaranteed peak or a reason to clip the physics process.

Select the aircraft first, then normalize weights over that aircraft's qualified recipes. This avoids repeated whole-scenario rejection silently favoring faster aircraft. Publish effective per-aircraft weights in the qualification evidence. Validation/runtime failures indicate a defect or incompatible content; report them, rather than silently retrying until something flies. Bounded geometric/time sampling may try at most 16 candidates, then return a readable failure.

For airborne flight, direction can span 0–360°; qualification checks initial drift, ground track and distance from the pilot for the actual spawn. Do not equate ground speed with airspeed. Include headwind, tailwind and crosswind cases; reject recipe combinations that immediately leave the qualified view or require exceptional recovery at handoff. Do not scale control authority, wind or aircraft coefficients invisibly to make a bad combination pass.

### Daylight and atmosphere

Proposed light weights: 25% early morning, 50% daytime and 25% late afternoon. Use solar elevation, not a universal wall-clock hour. Solve within the current synthetic reference location/date using `SolarPosition.evaluate()`, then validate the resolved `openrc-lighting v1` configuration.

For initial candidates, use rising sun around 6–20° for early morning, above 20° for daytime and descending sun around 8–25° for late afternoon. The lower limits are provisional readability filters; rendered/pilot acceptance can raise them. The existing FW dawn preset is below the horizon and TOD's dawn target is −6°: neither should be reused blindly for “early morning with a visible airplane.” Keep a single fixed snapshot; a flight cannot drift into night.

Keep date, reference location and elevation explicit and internally consistent. Do not infer the field's geography from the player's computer timezone, randomize latitude, or claim live local weather. The current synthetic field may use a declared sea-level scenario context; future field metadata must supply elevation/location before automatic admission.

Use coherent provisional temperature/humidity bands: cooler, more humid early mornings; warmer daytime; moderate late afternoons. Suggested qualification envelope: 12–30 °C, 30–80% RH, QNH 1000–1025 hPa. Sample a recipe's weather together, keeping field elevation fixed. QNH is not station pressure: use `Atmosphere.evaluate()` to derive the latter. This envelope describes fictional practice days, not weather observations. Do not vary clouds or terrain friction merely because humidity was selected.

## 5. Implementation boundaries

The initial implementation uses the following boundaries:

| Path | Responsibility |
| --- | --- |
| `app/scenarios/scenario_config.gd` | Validate/copy the scenario envelope, supported capabilities, versions and identities. Delegate nested weather/lighting validation to their current owners. |
| `app/scenarios/natural_random.gd` | Pure bounded generation from an explicit request, seed and qualified catalog/recipe view; no scene, preference or simulation mutation. |
| `app/data/scenarios/natural_random_v1.json` | Five stock IDs, reviewed recipe bands/weights, field context and per-aircraft eligibility. Descriptive metadata distinguishes estimates from qualification evidence. |
| `app/ui/natural_random_screen.gd` | Briefing, reroll, details, repeat and focus behavior using `Screen`/`Widgets`. |
| `app/tests/test_natural_random_*.gd`, `app/tests/test_ui_natural_random.gd` | Generator contracts, real launch integration, lifecycle, input and preference isolation. |
| `research/natural-random/`, `docs/research/natural-random/` | Qualification runner and accepted traces/captures/pilot results, created when evidence exists. |

Shared edits stay small: Home signal/button, `app_root.gd` launch-request routing, pause/conditions context, `main.gd` scenario identity/trace seam, Spanish strings and UI fixtures. Coordinate any simulation start changes with the simulation owner. Do not modify aircraft generated data, render/model builders, wind equations or RK4 for this feature.

### Resolved scenario contract

Use a new outer format such as **`openrc-flight-scenario v1`**. It contains:

- Mode ID, schema/generator/recipe versions, master seed and pinned engine/build identity.
- Stock catalog ID; source-data and model identities from the bytes/manifest actually accepted; field ID and identity. Bind these during preparation, then freeze the accepted record.
- Start selection, complete validated weather config and complete validated lighting config. No undocumented overrides or retained references to mutable preference dictionaries.
- Recipe ID, required capability list and qualification-policy version. Unknown required capabilities or newer unsupported versions fail with a specific error.
- Provenance (`generated` or `customized`), parent scenario identity for edits, and a digest of canonical resolved content. Display text is derived/localized, never parsed back into configuration.

Keep the scenario envelope out of `openrc-aircraft`, `openrc-weather` and `openrc-lighting`: those formats reject extra fields. Aircraft capability data remains authoritative; mode eligibility is an additional policy, not a duplicate aircraft model.

Use an isolated `RandomNumberGenerator` for generation, with separately derived stable streams for aircraft, recipe, wind, atmosphere and lighting. Specify a versioned SHA-256-based derivation over canonical seed/tag bytes and fixed ID ordering; do not rely on dictionary iteration or a process-specific hash. Turbulence receives its own uint32 seed and thereafter stays entirely within the existing simulation checkpoint/rollback machinery. No draw in `_process()`, camera rendering, preview, RK stages or HUD reads.

Choose a uint32 master seed for v1 so JSON stores it exactly. Any future int64 state must use native checkpoint encoding or strings. Seed reproduction is scoped to the recorded generator, recipe, catalog and engine versions. Godot documents the RNG algorithm as an implementation detail, so a seed alone is not a cross-version flight archive ([Godot RNG reference](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html), [4.7 seed/state guidance](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/math/random_number_generation.rst)). The fully resolved record is the authority; mismatched aircraft content must not silently reproduce a different airplane.

For v1, generation has no hidden recent-aircraft history. Rerolls may select the same airplane with other conditions. If a later no-repeat policy is added, encode its exclusions in the request so seeded generation remains reproducible.

### Launch and failure handling

1. **Draft:** generate/copy detached data and validate format, eligibility, field context and nested configs. Prepare the real aircraft/weather/start through existing session APIs while held and input-disabled; do not advance a tick or build a live world for the briefing. Cache only against source/recipe identities, invalidating on changes.
2. **Launch request:** give `app_root.gd` an explicit resolved request, rather than driving Home's persistent `set_aircraft()`, weather Apply or time setters. Ordinary Fly adapts its current choices to the same seam without changed behavior. Direct CLI/capture/trace routes remain isolated from interactive preferences.
3. **Commit from Home:** reuse `start_flight()`'s candidate lifecycle. Set all flight inputs before `add_child()`, verify `startup_error`, aircraft/model identity and `is_flyable()`, and bind the accepted scenario only on success. Validate again if source content changed after briefing; require a fresh displayed candidate rather than silently changing it.
4. **Failure:** free candidate nodes/recorder, retain the draft and explain the specific rejection. Restore Home and its exact normal selections. Rebuild/restore its world context as necessary: merely reattaching the old Home node does not prove that `World._flow`, `Atmosphere.state`, exposure and shader globals survived candidate setup. Test failure after world creation, not only early format errors.
5. **Persistence:** random launches do not save their aircraft/start/weather/lighting into normal-flight defaults. Keep the last scenario in memory. Branch `app_root._on_time_of_day_applied()` by flight context: it currently updates normal preferences for every interactive pause edit. Random edits update the scenario/restart selection only; ordinary pause edits retain their existing persistence. Existing explicit HUD/language/settings changes retain their normal persistence. No new preferences schema is needed for the MVP.

Do not claim an atomic live-flight swap. The first release launches candidates only from Home. The candidate preparation path must not use Workshop as a transport or leave a `workshop_trial`/external-data override attached.

### Repeat, recording and checkpoints

Restart uses the resolved scenario and existing `FlightSession.reset()`; repeat from Home rebuilds the same resolved start. The same input tape, accepted content, environment and compatible build must yield the same simulation trace within the project's existing replay policy. A seed repeats conditions; it does not reproduce a human pilot's input history or guarantee identical rendered particles/audio.

Add optional versioned scenario metadata to `main._trace_meta()`, following the current visual-context approach. Preserve weather/source fingerprints and CSV columns. Record complete resolved settings or a companion record with an integrity hash; never identify a flight solely as “Random.” Manual edits must update provenance and any relevant timeline using existing editor semantics.

Do not insert new fields into sealed physics/visual checkpoint dictionaries. If exporting a scenario together with a technical checkpoint, use a validated outer envelope around the existing native checkpoint, including the existing water wrapper where present. Missing scenario metadata in an older checkpoint means “context unavailable”; clear any previous random label instead of attributing stale conditions. Full save-game/replay UI remains outside this mode's first release.

## 6. Readability and flight qualification

“The airplane is visible” is an acceptance gate, not something a solar-angle check can establish alone. Qualify all five aircraft against bright sky, cloud and terrain backgrounds, early/late light, wind headings and their actual initial poses. Keep existing camera aids available; never quietly modify the plane's physical size or the pilot's camera choice.

Use production captures at 720p and 1080p from the pilot view, at 50/100/150 m and representative circuit attitudes (level, banking, approaching and departing). Check initial framing, silhouette and attitude recognition, runway/background contrast and sun proximity. Compare airplane-on/off masks using existing capture techniques; do not substitute pixel thresholds for an owner/pilot reading test. Test the smaller Timber/Stik as well as the larger P-51. Define the accepted viewing envelope in evidence; do not promise visibility at arbitrary distance or after the pilot flies into the sun.

For each admitted airplane/recipe, run real session starts and representative flown circuits/recoveries with fixed seeds, including all wind quadrants and the atmosphere corners. Inspect airspeed, ground drift, angular response, clearance and pilot workload. A trim success or a finite ten-second trace alone does not qualify controllability. Strong-wind draws need an explicit pilot acceptance entry; the 15% target is not grounds to promote a failing combination.

Performance: generation/preparation runs only when drawing or launching. Keep per-tick scenario cost at zero. Measure draw/launch latency, steady-flight frame time and the existing 240 Hz physics budget on target hardware. Repeated draw/back/fly/end cycles must not accumulate nodes, audio players, connections or global-world state.

## 7. Incremental delivery

NR-01/02/04/05 and the core NR-06 lifecycle are implemented. The table retains the full acceptance obligations: numerical checks do not close NR-03 pilot/readability qualification, and NR-06 broader release gates remain open. NR-07…09 are future work. Required evidence uses the NR prefix; existing owner gates remain open unless their owner accepts the corresponding evidence.

| ID | Work | Proof / status |
| --- | --- | --- |
| NR-00 | Audit current code, define stock policy, UX, boundaries and acceptance; register this plan. | This document; documentation only, 2026-10-13. |
| NR-01 | Scenario envelope and five-ID eligibility/recipe source; strict nested validation and identities. | Invalid/unknown/preview/Workshop/new-family records rejected; all five stock configurations resolve; input dictionaries stay unchanged. |
| NR-02 | Pure seeded generator, independent streams, weights and bounded sampling. | Fixed known seeds; order independence; boundary cases; deterministic 10,000-seed distribution report; zero global-RNG/physics mutation. |
| NR-03 | Qualify per-aircraft recipes and daylight/atmosphere/start combinations; freeze initial recipe revision. | Real-session matrix, directional/corner traces, readability captures and pilot review. Numerical success and physical validation labeled separately. |
| NR-04 | Extract the launch-request seam and integrate detached preparation, failure recovery and scenario ownership. | Normal Home/direct routes retain behavior; failures before/after world build restore Home globals and preferences; successful starts use exactly the briefed payload. |
| NR-05 | Home action and briefing, EN/ES, details/reroll/repeat, input/focus/arming behavior. | Real UI automation and native captures, small-window/long-text checks, held-key and high-throttle cases, no duplicate launch. |
| NR-06 | Restart/crash/editor provenance, optional trace metadata, lifecycle and first-release handover. | Same-scenario restart/replay, changed-settings labels, failed trace save, 20 menu/flight cycles, full regression suite and exported build smoke. First playable release: NR-01…06 all accepted. |
| NR-07 | Scene-local sky appearance: clear/fair/scattered/cloudier recipes and qualified haze using existing resources, with FW/TOD ownership. | Explicit versioned visual config, coherent sunlight/ambient/cloud shadows where supported, trace/checkpoint identity and readability/performance proof. No global `Spec` mutation or claim of rain physics. |
| NR-08 | Optional wind-aware runway starts and bounded daylight progression, delivered as separate substeps. | Persist selected runway end through reset/checkpoint; reject unsupported Jet/gear cases; day progression uses simulation time, pause/reset/history and cannot unexpectedly lose the accepted visibility window. |
| NR-09 | Admit additional stock configurations/fields; optional recipe preference and export/import of resolved scenarios. | Explicit capability/eligibility conformance, family-balanced selection, content-version mismatch errors, migration and package tests. No automatic admission of Workshop, helicopters, drones or trucks. |

NR-01/02 can be developed outside `app/` until scripts parse, as required by repository guidance. Integrate only parse-valid scripts. Do not change golden flights for a menu feature; investigate any change to unchanged configurations.

### Verification map

Use [TOOLS](../TOOLS.md) for the pinned engine, complete `app/test.sh`, captures and platform commands. [NR evidence](../research/natural-random/README.md) records the focused checks actually run, their commands and their limits; it does not claim a complete application-suite or pilot acceptance run.

| Area | Existing checks to retain / extend | New defect-focused coverage |
| --- | --- | --- |
| Catalog / stock source | [test_aircraft_catalog.gd](../../app/tests/test_aircraft_catalog.gd), [test_workshop_integration.gd](../../app/tests/test_workshop_integration.gd) | User variant cannot enter the pool; a new preview or unsupported catalog ID is not automatically eligible; stock aircraft hashes/model bindings match accepted flight. |
| Menus / settings | `test_ui_home`, `test_ui_home_layout`, `test_ui_aircraft`, `test_ui_pause`, `test_ui_screen_stack`, `test_ui_language` in [tests](../../app/tests/) | Cancel/reroll/start failure preserve normal selections and file contents; random pause-light edits change scenario/restart lighting while normal preferences and their file remain unchanged; ordinary pause edits still persist. End flight → Home → Natural Random → Repeat last flight restores the accepted selection. Check text/focus, key leakage and direct-route settings isolation. |
| Starts / weather / atmosphere | `test_start_choice`, `test_ui_runway`, `test_wind_flight`, `test_wind_turbulence`, `test_atmosphere_flight`, `test_ui_weather`, `test_ui_atmosphere` | Actual mean/gust/turbulence and density applied before trim/reset; source-invalid and failed-trim rejection; reproducible restart, no custom physics scaling. |
| Lighting / globals | `test_ui_field_world_time_of_day`, `test_time_of_day_session`, `test_time_of_day_render`, `test_ui_time_of_day_pause` | Passing evening → random fixed morning → failed launch → restored Home; no stale flow/exposure/cloud state; edits use active scenario context. |
| Trace / checkpoint | `test_checkpoint_integrity`, `test_replay_integrity`, `test_wind_trace`, `test_visual_checkpoint`, `test_time_of_day_checkpoint` | Recorded identity matches loaded bytes and resolved values; no RNG advance on render/pause; no stale random provenance after restore. Any new outer envelope rejects tampering. |
| Flight / visual / package | Current trace/capture/export workflows | Five-aircraft recipe matrix; pilot reading/handling; windy and calm examples; no late assets missing from export; target-hardware latency and node counts. |

The seed sweep checks configuration validity and distribution cheaply; it must not instantiate 10,000 worlds. Use a smaller named boundary matrix for expensive real-flight/render checks. Run deliberate malformed-input or code mutations only on disposable copies, following the existing repository policy.

## 8. Future compatibility and handover

The durable seam is **mode → resolved scenario → existing flight session**. Other modes can later produce the same envelope while keeping their own rules. New fields advertise location, elevation, available starts and supported environment features. New aircraft opt in through stock provenance, capabilities and handling evidence. Helicopters, multirotors and ground vehicles require their own session adapters and recipe qualification; their presence in the repository is not eligibility.

Dynamic weather, fronts, thermals and precipitation would change physical state/history and belong to M5 and the corresponding surface/propulsion owners. Visual cloud coverage belongs to FW/TOD. Keep those extensions explicit, versioned and rejectable; avoid a generic plugin system or unsupported enum values in the first implementation.

For NR-08 runway work, [ground_start.gd](../../app/physics/ground_start.gd) already offers `threshold(field, east_bound)`, but the selected session start currently uses its default eastbound end. Add an explicit, recorded runway-end selection through the session contract; choose the qualified end with a headwind, check crosswind/ground equilibrium and persist that choice through reset. Do not rotate the rendered airplane independently of physics or use the one-shot `reset_on_runway()` helper as a persistent launch policy.

After acceptance, put operating instructions in the current menu guide/FIRST-LAUNCH, commands in TOOLS and accepted rationale in DECISIONS. Keep the NR qualification evidence, consolidate this plan's remaining rationale into its authoritative guide, and remove the completed plan per the repository documentation conventions.
