# Field world plan: one landscape, day and night

Written **2026-10-10**, revision 2 (implementation started the same day after the owner's go-ahead). **Status (2026-10-10): FW-01/FW-02 done with byte parity; FW-03 partial (time of day only); FW-20/21/22/23/24 engineering-verified; field lights and the aircraft night kit (FW-31…35) delivered as a first slice; Gates FW-U and FW-N open (owner flight pending).** Step prefix: **FW**, registered in [docs/README.md](README.md#step-id-namespaces); gates **Gate FW-U** (unification) and **Gate FW-N** (night).

**Try it:** `$(app/get-godot.sh) --path app -- --quick-flight --time_of_day=golden_hour` (presets: dawn, sunrise, morning, noon, afternoon, golden_hour, sunset, blue_hour, night, night_dark; or `--time=HH:MM --date=YYYY-MM-DD --lat= --lon= --utc_offset=`). Contact sheet: `tools/world/capture_times.sh`.

- **Builds on:** [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md) (L), [VISUAL-QUALITY-PLAN](VISUAL-QUALITY-PLAN.md) (VQ), [SCENERY-PLAN](SCENERY-PLAN.md) (SC), the [landscape improvement proposal](research/landscape-improvement-2026-10-07/README.md), [WIND-PLAN](WIND-PLAN.md) (M5 `wind_vec`).
- **Evidence:** [FW-02](research/field-world/FW-02/README.md), [FW-20](research/field-world/FW-20/README.md), [FW-23](research/field-world/FW-23/README.md), [FW-24](research/field-world/FW-24/README.md), [FW-35](research/field-world/FW-35/README.md).
- **Owns:** `app/render/world/` (composer, conditions, ephemeris, sky state, stars, field and aircraft lights), `app/data/sky/`, `app/data/fields/lights.json`, `assets/sky/`, `tools/world/` (parity, sky table, star list, time-of-day captures), `app/tests/test_world_*.gd`. Planned: `app/data/fields/<id>/` (field folder), `app/data/conditions/`. Everything else is touched through its owner.

## 1. Why

The simulator has **one flying field built by four parallel efforts**. Each one is good and well proven; together they now cost more to change than to extend. Today there is no time of day: the sun is fixed at azimuth 225°, elevation 45° (`Spec.ATMOSPHERE`), so dusk and night are impossible.

### What "several landscapes in parallel" means, concretely

| Duplication | Where (verified 2026-10-10) | Cost |
| --- | --- | --- |
| **Four plans** for one field | LANDSCAPE (L, en), VISUAL-QUALITY (VQ, legacy es, sequences the L steps), SCENERY (SC, en), improvement proposal (Phases 0–8 mapped to L) | Status and decisions in several places; O-1/O-2/G-1 style cross-requests between tracks |
| **Two worlds at runtime** | Default field vs scenery-on (`--scenery=on`, `OPENRC_SCENERY`, `app/run-landscape.sh`) | Two sets of baselines; the owner flies a field different from the one that looks best |
| **Five world-assembly call sites** | `main.gd` `_build_world`, `ui/home_scene.gd`, `scenery/capture_views.gd`, `scenery/runway_scenario.gd`, `render/visual_evidence.gd` each wire environment + sun + field + clouds | Every new world feature (moon, lights) must be added five times |
| **Five data files, five formats, one place** | `fields/default.json` (`openrc-field v1`), `fields/grass.json` (`openrc-grass v1`), `fields/horizon.json` (`openrc-horizon-profile v1`), `scenery/default.json` (`openrc-scenery v1`), `scenery/models/*.json`; terrain v1 planned | No single "field" object; a second field means copying five files by hand |
| **Three wind-motion implementations** | `tree_wind.gdshaderinc`, `scenery/motion.gdshader`, sway in `near_grass.gdshader` | Wind (M5) must be wired three times |
| **Two contact-shadow builders** | `render/flight_cue_shadows.gd`, scenery `shadow_material()` in `scenery.gd` | Different looks for the same physical effect |
| **Four placement tools** | `tools/trees/place.py`, `tools/grass/place.py`, `tools/scenery/place.py`, `tools/terrain/gen_terrain.py` | Separate hashes; only the terrain one uses `lowbias32` |
| **Two palettes** | Grass/tree colours in `Spec`/shaders vs `scenery/palette.gd` themes | Autumn scenery on spring grass (SC-23 still asks the landscape track for a ground tint) |
| **Six capture harnesses** | `app/capture.sh`, `tools/scenery/capture.sh`, `tools/ground/`, `tools/grass/`, `tools/atmosphere/`, `tools/trees/` captures | Slow to run all; easy to miss one |
| **Overlapping steps** | L11b ↔ SC-16/17 (flowers), L15e ↔ SC-19a (ambience), L19 ↔ SC-20 (birds), VQ-06 ↔ SC-24 (quality tiers), L10 ↔ SC-06/07 (cues vs props) | Ownership questions instead of progress |

## 2. Goals

1. **One field, one world:** one validated field object, one composer, one capture entry, one plan. No visual change while unifying (byte-identical captures and traces).
2. **Time of day:** a physically grounded sun, moon and sky from date, time and location: dawn, golden hour, blue hour, moonlit night, dark night.
3. **Night flying that is realistic and flyable:** club floodlights, lit windsock, obstacle lights, a lit aircraft (LED kit), a living horizon of village and road lights.
4. **Creative life:** moments that reward looking around, each one sourced, deterministic and optional.

**Non-goals:** a new renderer (Compatibility stays: web export, deterministic captures), photo fields, collisions with scenery (still L14), weather physics (M5).

## 3. Rules every step keeps

These are the project's existing rules, restated because night work breaks them easily.

- **Determinism:** never `TIME`; animation from `sim_clock`/`wind_vec`; every frequency a multiple of 1/1024 Hz (L0d). Flashing lights included: 30 flashes/min = 0.5 Hz = 512/1024 Hz.
- **Visual only:** `--trace` and golden flights byte-identical in every step. The sky, lights and time never feed `sim/`/`physics/`.
- **Simulation-grade maths stays float64:** ephemeris and sidereal time in GDScript `float`, never `Vector3`/`Basis` (`app/test.sh` guard applies if the code lives in `sim/`).
- **Data discipline:** every number `{value, unit, kind, source}`; guessed values labeled; offline generators are integer-only and committed with SHA-256 and a `--check` mode.
- **Readability first:** each step re-runs the L6c readability kit; night adds its own kit (FW-36).
- **Budgets** stay those of LANDSCAPE-PLAN (landscape ≤ 300 draws, ≤ 1 M primitives, ≤ +15 MB download; frame time judged on the owner's slowest machine). Night has its own sub-budget (§7).
- **Drafts outside `app/`** until they parse; `app/test.sh` before every commit.

## 4. Target architecture

```
conditions (date, time, lat/lon, visibility, clouds, season, quality, layers)
        │
        ▼
 World.build(field, conditions) ──► { root, environment, lights, clock hooks }
        │          used by: flight (main.gd), Home, captures, runway scenario, evidence
        ├─ Sky & light ── ephemeris (sun, moon, LST) → sky LUT → sky shader, fog, sun/moon lights, exposure
        ├─ Ground ─────── surfaces, horizon rings, (terrain L12+)
        ├─ Vegetation ─── treeline cards, near trees (L8), near grass
        ├─ Cues ───────── windsock, pilot station, barrier, contact shadows
        ├─ Scenery ────── club, countryside, landmarks (tiered, not a separate world)
        └─ Lights ─────── light pools (analytic) · bulbs and halos · ≤ 4 real lights · aircraft kit
                     all shaders include render/world/common.gdshaderinc:
                     hash · wind sway · fog · field_lights() · night perception
```

| Piece | Decision | Why |
| --- | --- | --- |
| **Field** | `app/data/fields/<id>/field.json`, format `openrc-field v2`: a manifest that names its layers (surfaces, cues, treeline, grass, horizon, scenery, lights; terrain later). One loader returns one validated field or refuses the whole field | A second field (paved, Mediterranean) becomes one folder. v1 files convert with a tool; both load byte-identically during the transition |
| **Conditions** | `openrc-conditions v1` (`app/data/conditions/*.json` presets) + one resolver for CLI/env/settings. Existing flags (`--visibility`, `--scenery_*`, `OPENRC_SCENERY*`) stay as aliases | One place decides what world is built; Home and flight cannot diverge |
| **Composer** | `render/world/world.gd`, the only code that creates `Environment`, sun/moon lights and the field node | Five call sites become one; new features land once |
| **Shared shader library** | `render/world/common.gdshaderinc`: Hoskins hash, wind sway, fog formula, `field_lights()`, night perception | Wind and lights arrive in every material at once |
| **Scenery** | A layer with quality tiers (`landmark`/`standard`/`ornament`). "Scenery off" = the tier set that reproduces today's default field | Gate SC still decides the default; it becomes a tier choice, not a second world |
| **Fixed sun compatibility** | `conditions.sun_override = {az 225°, el 45°}` is the default preset until Gate FW-U | Every existing capture stays byte-identical; the ephemeris is used only when a time is chosen |

## 5. Steps

Each row is one small change with one proof, keeping `app/test.sh` green. Pending L and SC steps keep their IDs and status in their own plans; this plan links them and does not duplicate them.

### Phase FW-A: Unify (no visual change)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| FW-00 | **This plan**; owner decisions D-1…D-6; register prefix and gates; agreement of the landscape, visual and scenery tracks | Decisions recorded in DECISIONS; registry row added | — | ✅ 2026-10-10: registered (registry, AGENTS, ROADMAP); the owner's go-ahead adopted D-3…D-6 as proposed; D-1/D-2 (merging plans and owners) await the other tracks |
| FW-01 | **Parity baseline:** one manifest of every existing capture (default and scenery-on), golden flights and traces, with SHA-256. `tools/world/capture.sh` calls the existing harnesses (no rewrite yet) | Two runs give the same manifest; a changed PNG on a copy fails | FW-00 | ✅ 2026-10-10, **changed**: [`tools/world/parity.sh`](../tools/world/parity.sh) renders 89 views through all assembly sites plus the trace (creation timestamp excluded); repeated runs identical ([FW-02](research/field-world/FW-02/README.md)). Golden flights stay with `app/test.sh` |
| FW-02 | **One composer** `render/world/world.gd`; the five call sites call it | FW-01 manifest unchanged; trace bytes unchanged; `grep` finds no `Atmosphere.environment()` outside the composer | FW-01 | ✅ 2026-10-10: flight, Home, scenery views and runway scenario call `World.build/update` (the atmosphere fixture keeps its field seam; `visual_evidence.gd` only reads). Images and trace content identical ([FW-02](research/field-world/FW-02/README.md)) |
| FW-03 | **Conditions** `openrc-conditions v1`, presets `default`, `hazy`, `clear`; one resolver; old flags as aliases with a deprecation note | Unit tests: precedence CLI > env > settings > preset; 12 refused mutations; FW-01 unchanged | FW-02 | ◐ 2026-10-10: [`conditions.gd`](../app/render/world/conditions.gd) resolves time, date, place and 10 sun-event presets (command line, then environment); no time = legacy. Visibility/scenery flags and a data file still to fold in |
| FW-04 | **Field folder** `openrc-field v2` + `tools/world/migrate_field.py` (v1 → v2, `--check`). Loader validates all layers together; the export filter includes the folder | v1 and v2 give byte-identical captures; clean-clone export of all three presets loads `default/`; mutations refused | FW-03; visual track (owns `field_loader.gd`) | — |
| FW-05 | **Shared shader library:** hash, wind sway, fog from one include; remove the three wind copies | Captures byte-identical (or a stated FLIP bound if float evaluation order must change); `TIME` ban still passes | FW-02 | — |
| FW-06 | **Shared placement hash:** `tools/world/hash.py` (`lowbias32`, integers only) used by the four placers | Each placer's committed output byte-identical under `--check` | FW-00 | — |
| FW-07 | **One contact-shadow builder** for flight cues and scenery | Captures within the scenery and cue proofs' tolerances; draws not higher | FW-02 | — |
| FW-08 | **One palette and season:** `conditions.season` drives ground tint, tree tint and scenery palette together (delivers SC-23's ground request) | Default season byte-identical; L6c readability per season | FW-03, FW-05 | — |
| FW-09 | **Scenery as tiers:** one switch through conditions; `app/run-landscape.sh` becomes a preset alias; quality tiers wired to VQ-06 presets (closes SC-24's open part) | Standing SC proofs (trace identity, readability); default still off until Gate SC | FW-03; Gate SC unchanged | — |
| FW-10 | **One plan:** open L/SC/VQ steps mapped into a table in this plan; VQ (legacy Spanish) and the improvement proposal archived once their open items are mapped; LANDSCAPE and SCENERY keep their done rows as history | Link check from a fresh clone; registry and AGENTS updated in the same change | FW-00 (D-1) | — |
| **Gate FW-U** | **"Is there one field, and did nothing change?"** | FW-01 manifest identical; one composer; one field object; one capture command | FW-01…FW-10 | — |

### Phase FW-B: Finish the day field (pointers, not copies)

Status of these lives in their plans. Recommended order inside the unified world:

| Item | Owner step | Why now |
| --- | --- | --- |
| Human acceptance of the field | Gate L, Gate SC | Night builds on a day look the owner has accepted |
| Near 3D trees (≤ 1k triangles) | L8 | Floodlights and the moon expose card trees close to the pilot |
| Paved field and asphalt | SC O-6 → a second field folder `paved/` | Proves FW-04; asphalt makes night light pools readable |
| Wind on trees, grass, flags, windsock | L15a–c with M5 | One wiring point after FW-05 |
| Terrain physics | L12–L14 | Unchanged; the field folder gains a `terrain` layer |

### Phase FW-C: Time of day (sky and light)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| FW-20 ✅ 2026-10-10 ([evidence](research/field-world/FW-20/README.md)) | **Ephemeris** in float64: sun position (NOAA solar calculator, after Meeus), moon position and phase (Meeus ch. 47, truncated), local sidereal time. Inputs: date, local time, latitude, longitude, time zone | Against published reference values: sun ≤ 0.05°, moon ≤ 0.5° (targets, estimated), at 6 dates × 3 latitudes; phase within 2 % | FW-03 | — |
| FW-21 ✅ 2026-10-10, **changed** ([FW-23](research/field-world/FW-23/README.md)): a 1-D table per 0.5° of sun elevation (zenith, haze, sunward lobe, sun and cloud-deck transmittance) from `tools/world/sky_table.py` (single scattering plus Hillaire's isotropic multiple scattering; `--check` in `app/test.sh`), anchored at 45° to the calibrated look; it keeps the sky shader's form and the L2 fog equality | **Twilight sky LUT**, offline: precomputed atmospheric scattering (Bruneton 2017 implementation, BSD-3, as reference; our own integer-output Python port) for sun elevation −18°…+90°. Committed PNG + sidecar with SHA-256; `--check` | Byte reproducible; at 45° it matches today's Hosek fit within 3 levels in the horizon/zenith bands; Earth's shadow and Belt of Venus present at −2° | FW-20 | — |
| FW-22 ✅ 2026-10-10: one lobe term in sky, ground and grass fog; engine fog keeps the uniform haze | **Sky shader reads the LUT;** haze and ground fog colour from the same LUT row (L2's single source of truth, extended); sun disc colour from extinction | L2 equality test (sky = fog = ground haze, within 1 level) at 7 sun elevations; no `TIME`; the default preset stays on the legacy path until Gate FW-U, then one deliberate re-baseline | FW-21 | — |
| FW-23 ✅ 2026-10-10: one directional light (brighter of sun and moon), scripted adaptation (lit runway included), planar shadow held at ≥ 12°, anchored ambient colour ([engine finding](research/field-world/FW-24/README.md)) | **Light rig:** sun and moon `DirectionalLight3D`s, colour and energy from the LUT; sky ambient; **scripted exposure** from scene luminance (auto-exposure is Forward+ only in 4.7), smoothed on the sim clock; planar shadow follows the dominant light and fades below ~8° elevation (estimate) | Exposure curve unit tests; captures at 9 times of day; white wing L\* p99 < 95 (L3 rule) at every time | FW-22 | — |
| FW-24 ✅ 2026-10-10, **changed**: geometry stars instead of a cubemap ([evidence](research/field-world/FW-24/README.md)) | **Stars and moon:** Yale Bright Star Catalog (BSC5, factual data; licence review D-7) baked offline to a star cubemap (magnitude → brightness, B−V → colour), rotated by LST in the sky shader; visible magnitude limited by sky brightness; moon disc with phase terminator and faint earthshine; cloud deck occludes both | Orion and the Big Dipper at their computed positions for a fixed date (≤ 0.5°); no star visible at noon; byte repeat | FW-20, FW-22 | — |
| FW-25 ◐ 2026-10-10: cloud colour follows the deck's transmittance and skylight; cloud shadows by night not yet switched off | **Clouds through the day:** cloud colour from the LUT (pink/orange undersides at sunset, moonlit grey at night, dark silhouettes against stars) | Captures at −4°, 0°, +4°, night; cloud shadows (L15d) off when the sun is below 0° | FW-22 | — |
| FW-26 ◐: moonlight drawn cooler (labeled convention); no scotopic grade yet | **Night perception:** scotopic desaturation and blue shift below a luminance threshold (Thompson, Shirley & Ferwerda 2002; Kirk & O'Brien 2011). Probe first: `Environment` adjustments vs the shared include; choose by readability and determinism | Night readability kit (FW-36) improves or holds; no effect above the threshold (day captures unchanged) | FW-23 | — |
| FW-27 ◐: presets and clock on the command line; menu entry requested from UI-07; "time flows" not started | **Time controls:** presets (dawn, morning, noon, golden hour, blue hour, moonlit night, dark night) and "time flows" (default frozen). Sky radiance re-render quantised to ≤ 1 per second, like clouds. Menu entry requested from UI-07 | Same conditions → same pixels; pause freezes time; trace unchanged | FW-23; menu track | — |

### Phase FW-D: Night lighting

Constraints measured from the Godot 4.7 docs (to confirm in FW-30):
- Compatibility renders **at most 8 omni + 8 spot lights per mesh**. Our ground is one 40 km mesh and scenery is merged per 40 m cell, so real lights cannot be the main tool.
- Shadowed positional lights render in **extra passes**: no shadows on artificial lights.
- **No light projector textures and no decals** in Compatibility.
- **No auto-exposure** (Forward+ only).
- Glow works with a reduced feature set; it stayed byte-repeatable in L1b.

So lights come in four tiers, all driven by one `lights` layer in the field:

| Tier | Technique | Cost | Used for |
| --- | --- | --- | --- |
| 1. Light pools | `field_lights()` in the shared include: up to 32 point/spot lights as uniform arrays (like the ground's 32 surface rectangles), smooth inverse-square window, cone, colour temperature | 0 draws; per-pixel cost measured in FW-30 | Light on ground, grass, trees and scenery |
| 2. Bulbs and halos | One MultiMesh of unshaded camera-facing quads; halo size from haze; brightness through the fog formula | 1–2 draws | Every visible fixture, near or 5 km away |
| 3. Real lights | ≤ 4 `SpotLight3D`/`OmniLight3D`, no shadows | Measured in FW-30 | Lighting the **airplane** near the runway and pits |
| 4. Aircraft kit | Emissive LED strips and nav lights on the airplane + one small real light | ≤ +3 draws (estimate) | Seeing attitude at night |

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| FW-30 ◐ 2026-10-10: engine source and captures answered the colour questions ([FW-24](research/field-world/FW-24/README.md)); light cost on the owner's GPU still to measure | **Probe (scratch copy):** cost of 4 unshadowed lights on merged meshes; the per-mesh limit on the ground; `field_lights()` with 8/16/32 lights; glow and halo determinism; height fog in Compatibility. llvmpipe for repeatability, owner GPU for cost | Report with numbers; chosen light count and halo method | FW-05 | — |
| FW-31 ✅ 2026-10-10, **changed**: a separate validated [`lights.json`](../app/data/fields/lights.json) (`openrc-field-lights v1`, 11 refused mutations) until FW-04's field folder | **`lights` layer** in `openrc-field v2`: fixture type, position, height, colour temperature, intensity, beam, schedule, flash pattern, each sourced. Research: FAA AC 70/7460-1 (obstruction lighting, L-864 red flashing for wind turbines, synchronised), FAA L-807 lighted windsock, street-lamp colour temperatures (HPS ≈ 2,000 K, LED 3,000–4,000 K) | Loader tests; refused: fixtures in the flight box above the SC height rule, unknown flash patterns, frequencies not multiple of 1/1024 Hz | FW-04, FW-30 | — |
| FW-32 ⏸: not needed for the first slice: three real shadowless spots stay inside the per-mesh limit | **Light pools** in ground, grass, tree and scenery shaders | Pool radius and falloff match the data (pixel probe); day captures unchanged (lights off when sun > 0°); +0 draws | FW-31 | — |
| FW-33 ✅ 2026-10-10: [`light_sprite.gdshader`](../app/render/world/light_sprite.gdshader): flux-conserving minimum size, hue-preserving display cap, flashing on `sim_clock` | **Bulbs and halos** | ≤ 2 draws; a 5 km bulb fades by the L2 transmittance; byte repeat | FW-31 | — |
| FW-34 ✅ 2026-10-10: two 8 m LED floods and a floodlit windsock; the exposure adapts to the lit runway | **Club floodlights:** 2–4 pole floods over runway and pits as real lights + pools | Airplane lit within the flood cone (L\* probe); counters within the night budget | FW-32 | — |
| FW-35 ◐ 2026-10-10 ([evidence](research/field-world/FW-35/README.md)): nav lights, tip strobes and landing light from model bounds; belly strips need model anchors (D-8) | **Aircraft night kit** with the model teams: anchors (wingtips, fin, belly) from each catalog geometry; red left, green right, white tail strobe; a different-colour belly strip so upright and inverted read apart (RC night-flying practice; source in the step). New `render/aircraft_lights.gd` attaches to `airplane` without renaming nodes or hinges | Every `verify_*` contract passes; strobe on `sim_clock`; captures for each catalog aircraft | Model teams | — |
| FW-36 | **Night readability kit:** L6c extended to dusk, moonlit and dark night, with and without the kit; blinded images | Thresholds proposed from numbers; owner scores the kit | FW-34, FW-35 | — |
| **Gate FW-N** | **"Can I fly a full session at dusk and at night, and is it beautiful?"** The owner flies the Gate 2 maneuvers at blue hour and at night | Ratings; frame time p95 on the slowest machine; budgets met; decisions in DECISIONS | FW-20…FW-36 | — |

### Phase FW-E: Life and wonder (optional; each one step, each behind Gate FW-N)

Every item is visual only, deterministic, sourced and measured against readability. Ordered by value per effort (estimate).

| ID | Idea | Realism anchor | Technique |
| --- | --- | --- | --- |
| FW-40 | **Wind-turbine obstacle lights** flashing red in unison | FAA AC 70/7460-1: synchronised red flashing for turbine farms | Tier 2 bulbs on `sim_clock` |
| FW-41 | **Lit windsock** | FAA L-807 (floodlit or internally lit) | Tier 1 pool + emissive sleeve |
| FW-42 | **Pavilion festoon lights** and warm window glow | Club evenings | Tier 2 bulbs + emissive windows |
| FW-43 | **Village at dusk:** sodium street lamps and windows that switch on at sunset and off progressively after 23:00; **light-pollution glow** on the sky toward the village | HPS colour, schedules | Bulbs; azimuthal sky term |
| FW-44 | **Floodlit church** and a **farm yard light** | Common rural lighting | Pools on facades |
| FW-45 | **Distant road traffic:** headlights and tail lights on an analytic path at 2–3 km | — | Bulbs on a closed curve, hash-spaced |
| FW-46 | **A car arriving at dusk** down the dirt track, headlights sweeping the grass, parking in the row | — | Spot pool + analytic path; on a fixed schedule |
| FW-47 | **Pilots with red headlamps** in the pits | Red light preserves dark adaptation | Small bulbs on procedural people |
| FW-48 | **Glow-stick runway markers** (green/yellow) | Common at RC night-fly events (source in the step) | Bulbs |
| FW-49 | **An airliner crossing high** with nav lights and strobes at night; a **contrail** by day | Real overflight altitudes | Analytic path ≥ 9 km |
| FW-50 | **A satellite pass** after sunset: a moving point visible only while sunlit at altitude | Orbital geometry (sun below horizon, satellite in sunlight) | Shadow-cone test in float64 |
| FW-51 | **Fireflies / glow-worms** at meadow margins on summer nights | *Lampyris noctiluca*, June–July in Europe | Analytic points near flower strips |
| FW-52 | **Bats at dusk** along the treeline (replace birds after sunset) | Crepuscular behaviour | SC-20 flock, dusk schedule |
| FW-53 | **Morning ground fog** in low areas at dawn | Radiation fog | Height fog if FW-30 confirms it in Compatibility |
| FW-54 | **Golden-hour long shadows** of trees on the field | Low sun geometry | Planar shadow cards, clamped length |
| FW-55 | **Seasons through the date:** sun path, ground tint, leaf colour and flowers follow the month | Ephemeris + FW-08 | Data only |
| FW-56 | **Real sky for the owner's field:** latitude/longitude of their club → correct sun, moon and stars | Pairs with L17 | Conditions preset |
| FW-57 | **Night event day:** more cars, floodlights, a food truck, music from the pavilion | SC parking-lot idea "fun-fly day" | Scenery preset |

## 6. Ownership and coordination

| Track | What this plan asks | What it promises |
| --- | --- | --- |
| Visual quality / landscape | Composer in `render/world/`; `field_loader.gd` v2; shared include in their shaders; sky LUT in `sky.gdshader` | Byte parity until Gate FW-U; their proofs kept |
| Scenery | Scenery as a layer and tiers; shared shadows, hash and palette | Gate SC still decides the default; trace identity kept |
| Menus (UI) | Time-of-day and season choice in Home/settings (UI-07); one conditions resolver | `app_root.gd` lifecycle respected |
| Model teams | Light anchors per aircraft; approve `aircraft_lights.gd` | No node, hinge or appearance file touched |
| Physics | Nothing | Never reads or writes `sim/`/`physics/` state; traces identical |
| Wind (M5) | `wind_vec` once, through the shared include | Consumer only |
| Desktop delivery | Export filter for the field folder and LUT/star textures | Download budget respected |

D-2 decides whether this becomes one **Field world track** that takes over the landscape, visual and scenery paths, or stays a coordination plan.

## 7. Budgets (proposed; estimates until FW-30)

| Measure | Day (unchanged) | Night addition |
| --- | --- | --- |
| Visible draws, landscape | ≤ 300 | ≤ +12 (bulbs 2, floods ≤ 4 lights' extra cost, aircraft kit 3, spare 3) |
| Shadow-pass draws | 0 | 0 (no shadowed artificial lights) |
| Per-pixel lights | — | ≤ 32 pools; reduced to the FW-30 measured value if needed |
| Textures | ≤ 2048 px | Sky LUT ≤ 256 × 128; star cubemap ≤ 6 × 512² |
| Download | ≤ +15 MB | ≤ +3 MB |
| Sky radiance updates | ≤ 1/s (clouds) | ≤ 1/s (sun/moon movement) |
| Frame time | p95 on the owner's slowest machine | Same, measured at night |

## 8. Risks

- **Banding at night.** The output is LDR RGBA8; dark gradients band most. Sky keeps `use_debanding`; ground and pools get a deterministic hash dither in the shared include.
- **"Realistic" night is black.** Physical illuminance falls from ~100,000 lux (sun) to ~0.25 lux (full moon) and ~0.001 lux (starlight) (borrowed, typical values). Render perceived night, as cinema's day-for-night, through the exposure curve and FW-26; readability decides.
- **The airplane disappears at night.** Real RC night flying depends on LED kits; FW-35 is a hard requirement for Gate FW-N, not decoration.
- **Light limits per mesh.** The merged ground and cells cannot take many real lights; pools carry the field lighting.
- **Unification breaks parity silently.** FW-01's manifest guards every FW-A step; float evaluation order changes need an explicit FLIP bound.
- **Ownership collisions.** FW-A touches files of three tracks. Run `git status` before shared edits; agree each touch before it lands.
- **Twilight colours by taste.** The LUT comes from a physical model with a reproducible generator; artistic changes are labeled.
- **Scope creep.** Phase FW-E stays behind Gate FW-N; one idea per step.

## 9. Decisions for the owner

| # | Question | Proposal |
| --- | --- | --- |
| D-1 | Merge the plans into this one? | Yes: this plan becomes the field's single plan; VQ and the improvement proposal are archived after mapping; LANDSCAPE and SCENERY keep their done history |
| D-2 | One track owning landscape, visual and scenery paths? | Yes, a "Field world track"; otherwise keep the three owners and use this plan for coordination only |
| D-3 | Scenery default after unification? | Unchanged until Gate SC; then "balanced" tier by default |
| D-4 | Default time of day? | Today's fixed 45° sun until Gate FW-U; then "morning" preset at the reference location |
| D-5 | Reference location and date for presets? | The owner's club latitude/longitude if shared; otherwise 40° N, 3.7° W (estimated), 21 June |
| D-6 | Time flows during a flight by default? | No (frozen, deterministic); "time flows" as an option |
| D-7 | Ship the Yale Bright Star Catalogue derivative? | The distribution has no explicit licence; the game uses only positions, magnitudes and colour indices (facts). Confirm before a release |
| D-8 | Belly LED strips for every aircraft? | Ask each model team for two anchors (fuselage belly line, wing underside line) in their generated geometry: model bounds include wheels and propeller |

## 10. Suggested order

FW-00 → FW-01 → FW-02 → FW-03 → FW-04 → FW-05 → FW-20 → FW-21 → FW-22 → FW-23 → FW-30 → FW-31 → FW-32 → FW-33 → FW-35 → FW-34 → FW-24 → FW-36 → Gate FW-N, with FW-06…FW-10 in parallel once FW-02 lands and Gate FW-U before the deliberate sky re-baseline. FW-40 and FW-41 are the first wonders: cheap, sourced and visible from the pilot station.

## Sources (to verify and cite in each step's evidence)

- Godot 4.7 docs: [renderer feature comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [lights and shadows](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html) (8 omni + 8 spot per mesh in Compatibility), [CameraAttributes](https://docs.godotengine.org/en/4.7/classes/class_cameraattributes.html) (auto-exposure Forward+ only), [environment and post-processing](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html) (glow in Compatibility).
- J. Meeus, *Astronomical Algorithms*, 2nd ed. (sun, moon, sidereal time); NOAA Global Monitoring Laboratory solar calculator.
- E. Bruneton, F. Neyret, "Precomputed Atmospheric Scattering", 2008; E. Bruneton's 2017 reference implementation (BSD-3).
- Yale Bright Star Catalogue, 5th revised ed. (Hoffleit & Warren), CDS V/50, copy from SAO TDC ([provenance](../assets/sky/PROVENANCE.json); licence review D-7).
- W. B. Thompson, P. Shirley, J. A. Ferwerda, "A Spatial Post-Processing Algorithm for Images of Night Scenes", 2002; A. G. Kirk, J. F. O'Brien, "Perceptually Based Tone Mapping for Low-Light Conditions", 2011.
- FAA AC 70/7460-1 (obstruction marking and lighting); FAA AC 150/5345-27E (wind cones) and L-807 lighted windsock.
