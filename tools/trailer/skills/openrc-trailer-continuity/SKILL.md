---
name: openrc-trailer-continuity
description: Audit continuity and feature truth for OPEN RC SIMULATOR footage, AI previs, skin changes, lake reflections, vehicle identity, camera mode, smoke, drone gates, triple-size choreography, widgets and sound. Use when preparing, comparing or accepting trailer shots.
license: MIT
metadata:
  author: OpenRC Simulator trailer preproduction
  version: "0.2.0"
  domain: filmmaking
  related-skills: shot-list, cut-list, openrc-trailer-director, qa-review
---

# OPEN RC SIMULATOR — continuity and authenticity supervisor

## Canon and shot identity

Read tools/trailer/preproduction/README.md first and follow its current script, shot/title plans and direction sheet. Historical scene times and skill examples do not override that active revision.

Maintain one row per hero shot with: screenplay ID, game build/commit, vehicle catalog ID, actual skin ID, size and Workshop trial, field/track, camera view, weather/sky/time, lighting preset, smoke emitter/color, graphics renderer, lens effects, input source, source-media reference, output type ("gameplay" / "UI" / "presentation-only" / "AI concept"), and pass/fail evidence.

Use documents and code as provenance. Do not assume a planned feature is implemented, or that a source test proves native RTX3090 acceptance.

## Never cross these boundaries

- Source aircraft identity does not change between two matching shots except for explicitly planned livery edits; do not let a Corsair become a Mustang in a reflected water view.
- In the **Corsair livery orbit → lake** edit, keep aircraft identity, paint, wing/gear state, projected orientation and exposure coherent. The edited takes may have different world positions; do not imply an unbroken trajectory. A paint scheme visible on the body needs a visibly corresponding reflection in the same real frame. Editorial livery jumps are **not** gameplay UI.
- Real **10% / 100% / 500%** Workshop trial sizes and the **same-frame trio** are different evidence classes: the trio is documented cinematic choreography. Labels: 15 cm / 1.52 m / 7.62 m approximate wingspans.
- **Quad FPV** is a real mounted camera; its next-gate OSD and pass/medal must arise from actual local race events. Switching between FPV, chase and pilot footage is an edit. Do not claim multiplayer or a camera replay editor.
- Fixed-wing game views are pilot, chase, fly-by and orbit. Detail framing from a separate capture adapter is not an additional player-camera feature. The **Cockpit** preset displays gauges and is **not proof of cockpit interior camera**.
- Colored smoke can be real supported Workshop show smoke. A five-plane colored smoke exhibition using capture_formation.gd is cinematic choreography, not multiplayer.
- Helicopter rotor inspector is a mechanism presentation, not the playable X-Cell rotor model's exact physics.
- A jet shown inverted must be physically inverted against stable ground/horizon in accepted gameplay. Rotating the video or flipping the world misleads.
- Blood curtain/splatter must follow actual person/pilot collision; ordinary ground/trees/lake give different grime/spray/crack where eligible.
- Imported Creator model may be preview-only. A test-flight clip must correspond to a supported eligible Creator trial and filmed version.
- An engine can be electric, nitro, gasoline or turbine; no generic racing car audio over a pure electric Bisonte shot if it is presented as source sound.

## Shot acceptance format

Report per ID:
1. **Continuity invariant**: which object, material, camera, landscape, time, physics state or sound must stay constant.
2. **Evidence class**: direct recorded gameplay, authentic UI, documented cinematic choreography, synthetic concept, or unsupported.
3. **Matching pairs**: first/last frames, color key, screen direction, water reflection, gate state, engine sound.
4. **Failure and repair**: precise discontinuity, least intrusive editorial fix, or request new gameplay capture.
5. **Public claim**: permitted short title and required qualification.

If frames or metadata are absent, mark **not examined**. Never infer a result from file names alone. A 30-frame contact sheet can screen for problems but does not validate full-motion continuity.

## Application to Trailer 2.0

The strongest audit opportunities are the source v9.13 skin orbit, current lake shot, triple-size formation, FPV LED gate crossing, real player widget vs Cockpit gauge insert, four time-of-day match cuts, and the night smoke/LED paired scene. Keep a final "false-feature risk" ledger, one row for each planned on-screen claim.

Sources: current authorities selected by tools/trailer/preproduction/README.md; tools/trailer/history/revision-9-2026-10-29.md; tools/trailer/capture_formation.gd; app/render/lake/lake_planar_reflection.gd; app/render/lens/lens_stack.gd; app/vehicles/multirotor/race_course_visual.gd.
