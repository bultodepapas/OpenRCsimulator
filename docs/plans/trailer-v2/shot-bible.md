# Trailer 2.0 — shot bible and vehicle research

All figures here are *composition proposals*, not flying instructions or results from actual filming. Every proposed shot is pending capture/approval.

## A. F4U Corsair over reflected lake — signature sequence (T01, T12–T14)
**Goal:** an unforgettable image of the Corsair, its paint scheme and its real-time mirrored shape passing over the Club field lake. Show airframe and lake in the same shot, shoreline/trees as scale reference and a discernible moving mirrored silhouette.

- Camera: shore-level ~0.4–1.5 m above the lake mean plane as a first artistic test, three-quarter front/side tracking, moderately long lens and a second low-wide safety angle. Place water in lower 30–55% of frame; keep horizon, wings and reflection inside frame.
- Lighting: calm wind, bright fair/broken cloud, low-to-medium sun angle. Golden hour version only if silhouettes and actual water mirror remain recognizable; don't choose a black backlit paint scheme as the first demonstration.
- Flight: plan a low smooth approach with useful banking/roll only if physics and terrain permit; the nominal 2–5 m height idea is a *visual target subject to safety/actual crash margin*, not an authorized flight profile.
- Mirror technology: the current [planar lake adapter](../../../app/render/lake/lake_planar_reflection.gd) requires High/Forward+ and OPENRC_LAKE_REFLECTIONS=planar. Its [2026-10-22 Windows RTX3090 proof](../../research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md) used a Vantage Jet, **not** the Corsair. It was optional/default-off, not a guaranteed shipped High effect.
- Skin sequence: select a curated handful of high-contrast Corsair liveries, then capture identical camera/flight views or a qualified presentation-only live material switch. Edit on beats; each livery's **reflected color must match**. A skin changes **between takes or in presentation/edit**, not player-controlled mid-flight.
- Capture variants: clean wide / close crossing / livery changes / independent water control shot / final wide; compare with planar OFF. Reject if mirrored shape clips, disappears, mismatches skin, or only appears as a static cubemap tint.
- Fallback: documented jet moving reflection, but keep the Corsair over lake as a genuine non-reflection shot instead of inventing a mirror.

## B. Full current fleet — specific visual cue for each (T04)
| Selection | Filming character | Proposed camera | Sound and identity |
|---|---|---|---|
| Ugly Stick | dependable baseline takeoff | ground pilot then chasing low | gasoline prop |
| Ugly Stick Electric 6S | electric contrast | close side high-wing pass | motor/electric tone |
| Extra 300S | fast aerobatics | tracking/close three-quarter roll | prop and air |
| P-51D Mustang | elegant warbird power | sunlit crossing at distance | radial/warbird character; use actual game audio |
| F4U Corsair | folding wings, retracts, 13 available stock liveries | macro mechanism plus water hero | engine character and gear |
| Vantage Jet | speed / turbine | low crossing to camera | turbine spool/doppler |
| Turbo Lumber Evolution | gentle STOL/high wing | low runway-side camera | electric airflow |
| MoonRunner X99 | flying-wing silhouette | silhouette against sky, elevon turn | electric pusher |
| X-Cell helicopter | rotor mechanics and control | close side hover → short forward pass | rotor sound; inspection rig distinct from playable |
| ION R5 FPV | gate action | actual quad FPV view | fast motor, race-gate feedback |
| RC blimp (5 m) | playful variety | slow orbit/side float | softer electric propulsion |
| Bisonte MT8 | dirt, wheel motion, jump, chassis | tire-high tracking plus side landing | electric motor/tires |
| MONSTER CAR 2 | nitro powertrain, dirt/dust, headlights/neon | low nose/tire + ramp | actual game nitro engine, clutch/exhaust |

**Car detail — Bisonte:** film actual electric 4WD approach, ramp takeoff, full airborne trajectory, tire landing, shocks settling and lateral dirt slide. Pair low wheel perspective with a side shot where airtime is obvious. No inventing a car race/time-trial.

**Car detail — MONSTER CAR 2:** film nitro exhaust, realistic audio state from its procedural two-stroke, dust/grime and complete jump/landing. Stage one dusk take with headlights and running lamps (L), auxiliary LEDs (K), and green underbody neon (N); actual brake lamps respond separately. Source [MONSTER CAR 2 guide](../../../research/rc-monster-truck/monster-car-2/README.md) states **no reverse gear**; do not imply reverse from a steering shot. Capture nitro service/garage only if a supporting micro-cut genuinely needs it.

## C. Daylight to night and active VFX (T05–T08)
Film separate, physically rendered afternoon, golden hour, blue hour and night takes with matched aircraft direction and horizon. RGB patterns from supported Workshop profiles and a short close night pass are the visual payoff. Show sufficient body, not only floating lights. If night smoke is active, verify the aircraft's supported smoke emitter and palette; not all Extra profiles have stock smoke. Storm lightning must illuminate an identifiable aircraft or landscape. Rain droplets are on-lens visual presentation, not aerodynamic rain physics.

## D. Tiny/giant contrast (T09–T11)
Ugly Stick Workshop supports 10%, 100%, 500% **scale** on that model's implementation. Approximate wingspans: 0.1524 m, 1.524 m, 7.62 m. Show real Workshop controls then separate qualified trial flights with fixed landmark/camera position to make scale credible. A three-model formation may be a *cinematic comparator* but must be labeled presentation-only, not an actual multi-pilot feature. Do not apply these values to Corsair, jet or blimp.

## E. Creator + imports (T15–T17)
Use a compatible sample and genuine current Creator UI: import → orient/size → weight and balance → powered configuration/controls → paint → review → eligible test flight. Supported route lists include STL, self-contained GLB, compatible ClearView ZIP and **development-only newer Phoenix .mod**. Imported physics are explicitly estimated or based on disclosed donor, not converted faithfully from any source. Saved Creator planes cannot yet be selected and flown from normal Home. [Creator implementation](../../../app/ui/aircraft_creator.gd), [v0.3.0 release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.3.0).

## F. Camera crash, cracked glass, red curtain (T18–T20)
Three different captures, not one interchangeable effect:
1. **Ground/material crash**: actual dirt/grass/mud/water contact drives grime, water spray or dust on a near camera.
2. **Lens crack**: actual near high-speed surface contact, eligible camera in **closeup or fpv**, grime enabled; source [lens stack](../../../app/render/lens/lens_stack.gd) uses ~12 m/s threshold. Visual cracked camera glass is NOT broken aircraft canopy physics.
3. **Red splatter/curtain**: requires a **person/pilot contact** that the session recognizes, with impact effects enabled. A normal crash to terrain never counts as a blood hit. No simulated real human injury is implied.
4. Record an age-rating-friendly replacement of #3 using only dust, spray, splatter or crack (not red people-impact).
5. Lens quality includes **Ultra**, impacts Off/Curtain/Splatter; scripted/director sessions may default OFF unless explicit capture arguments are passed. [Lens settings](../../../app/render/lens/lens_settings.gd); [lens project plan](../lens-screen-effects.md).

## Cinematographer's rejection tests
No airplane smaller than the visual concept requires; no black night plane; no water reflection with wrong livery; no frozen ticks/rotors; no front-heavy car jump with landing cropped; no titles over a wing, reflection or UI text; no camera angle used 5 times in one minute; no claim of normal multiplayer/AI close formation, in-flight player skin swaps, cinematic player replay, universal import or high-performance FPS from offline rendered Movie Maker.

## Capture-side documentation template
Future shot manifest: Txx, exact commit and build/engine SHA, Windows GPU/driver, effective renderer, resolution/fps, vehicle/skin, landscape, date/time/time-of-day, sky/wind, scene detail/lighting/shadows, optional planar flag, lens-impact settings, camera type/FOV/position, director/controls, launch command, tick and crash evidence, frame/audio identities, source rights and director approval. Do not store filmed media or music on this docs branch.
