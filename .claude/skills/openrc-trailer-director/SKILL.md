---
name: openrc-trailer-director
description: Direct the OPEN RC SIMULATOR gameplay trailer as a cinematic short using a current screenplay, documented game capabilities, strong actions, specific camera moves, and visual beats. Use for creative concepts, shot lists, storyboards, trailer pacing, and scene alternatives.
license: MIT
metadata:
  author: OpenRC Simulator trailer preproduction
  version: "0.1.0"
  domain: filmmaking
  related-skills: shot-list, scene-breakdown, color-script, camera-cinematography, openrc-trailer-continuity
---

# OPEN RC SIMULATOR — trailer director

## Read before directing

1. Read docs/plans/trailer-v2/README.md and docs/plans/trailer-v2/cinematic-script-r2.md. The current script is the source of story beats; an earlier storyboard is not additional footage.
2. Consult the real source or the current product feature record for every claimed game function. If no current runtime evidence exists, write "proposed — validate during capture."
3. Distinguish actual interactive gameplay, real game UI, documented presentation-only choreography, and editorial montage. The previous v9.13 trailer showed both real footage and staged size/formation effects.
4. Until a later explicit production request, produce only plans and documents: no engine changes, no footage claims, no generation, and no automatic downloads.

## Directing goal

The audience should feel: "I can fly, race, drive, modify, and try my own model in one RC sandbox." Lead with playing, not specs. Retain the Corsair orbiting livery shot **and** the low lake mirror shot. Include other supported aircraft skins as distributed visual accents. Make the jet's inverted low fly-by, ION R5 LED gates, helicopter forward motion, both distinct trucks, colored smoke, night RGB, 10/100/500% Stick comparison and genuine widgets easy to identify. Do not sacrifice the 13-choice roster to any single hero.

## Shot grammar

For every sequence produce this compact shot card:
- ID and script beat / emotion / viewer takeaway.
- Scene and playable model, current evidence status, intended game mode.
- Shot size, camera source (actual game camera or *separate cinematic director*), direction, height, FOV/lens feeling.
- Subject action with a visible beginning and completed payoff.
- Camera start, camera end, speed/ease, screen direction and stable anchor.
- Time of day, cloud/wind, lighting/skin/smoke and field.
- Duration target and relationship to the music, not invented song BPM.
- Real audio cue and the cut transition.
- What must remain unchanged; what fails the shot; fallback if not filmable.

Each camera move earns its place. Suggested vocabulary: locked ground-pilot, fly-by, chase, orbit, closeup; for the ION R5 only, rigid onboard FPV with chase/pilot; trucks have their own chase, operator and orbit choices. "Cockpit" instruments are **widgets**, not proof of an airplane interior camera.

## Dramatic composition rules

- Cold open must show the game within five seconds. Do not put a long logo first.
- Put the actual vehicle relatively large in frame for identification; no tiny helicopter, tiny jet or only glowing dots in night sky.
- Alternate 1-second ensemble/roster cuts with 3–12-second hero chapters. Make the Corsair lake reflection breathe for recognition.
- Use motivated match cuts: rotor to truck wheel, FPV gate to wing strut, giant/mini across fixed runway landmark, daylight to night matching bank angle.
- For livery changes, preserve pose/camera/lighting and ensure lake mirror corresponds; do not present editing as an in-flight paint UI.
- For 3-size formation, film actual Workshop flight examples and label the simultaneous comparator as cinematic choreography.
- Include a clean view → Player widget → classic instrument preset sequence that never hides the model.
- Vehicle sounds are part of the direction: radial prop, turbine, electric quad, helicopter rotor, monster truck nitro, electric Bisonte.
- Night lighting is only beautiful if the aircraft body, RGB and context remain visible.

## Deliverable

A director's scene table with no more than 2–3 alternate angles per hero shot, plus a list of strongest three hooks, weakest three proposed shots, music pause positions, frame-safe titles, continuity constraints and genuine release limitations. When improving the script, create a new numbered revision instead of silently overwriting a locked historical cut.

## Reality gates

The inverted jet is a real flight trial target until demonstrated. The Corsair's planar reflection is experimental High with an explicit flag; earlier RTX3090 jet results do not confirm Corsair. Quad race gates are local; there is no online multiplayer. Creator preview is not the same as eligible Creator trial. Blood screen effects require a qualified person/pilot strike; cracked lens is a separate effect. Never invent aircraft skins or model-import compatibility.

Related source: docs/research/cinematic-trailer/revision-9-2026-10-29.md; app/render/camera/camera_rig.gd; app/vehicles/multirotor/multirotor_camera.gd; app/render/overlays/overlay_settings.gd; tools/trailer/capture_formation.gd.
