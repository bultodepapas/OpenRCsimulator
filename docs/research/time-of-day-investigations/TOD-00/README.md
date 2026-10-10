# TOD-00: time-of-day planning evidence

2026-10-10 · **Status: repository inspection and primary-source research recorded; no implementation, rendered experiment or flight validation.**

Owning plan: [TIME-OF-DAY-PLAN](../../../TIME-OF-DAY-PLAN.md). Scope: expand the time-of-day part of [Landscape L19](../../../LANDSCAPE-PLAN.md) into incremental deliveries that preserve existing simulation and visual contracts.

## Work and evidence

Inspected source at `7fe3d84`, with an initially clean working tree, against the user's request for arbitrary time selection and believable dawn, midday and darkness. Two Luna Max research/audit agents investigated primary sources and integration seams; the lead inspected rendering consumers and assembled the plan. Reports:

- [Primary sources](primary-sources.md): solar geometry, twilight definitions, lunar limitations, daytime sky-model domain, pinned Godot Compatibility behavior, source/license notes and unresolved experiments.
- [Integration audit](integration-audit.md): Home and direct routes, preference versions, physical atmosphere, clocks, trace/checkpoint contracts, tests and scenery.

This evidence supports implementation choices and identifies assumptions to test. It does not establish sky brightness, human night visibility, renderer performance or an accepted field location.

## Rendering findings

| Inspected source | Finding | Implementation consequence |
| --- | --- | --- |
| [Spec](../../../../app/spec.gd), [Atmosphere](../../../../app/render/atmosphere.gd) | Sun azimuth/elevation, sky/cloud/haze colour, energy and exposure are fixed; ambient/reflections come from the sky | Introduce one evaluated lighting snapshot while retaining the legacy fixture |
| [Sky shader](../../../../app/render/sky.gdshader) | Gradient fitted at a 45° Sun, Compatibility-specific colour encoding; the solar term is added after cloud mixing | Add bounded twilight/night inputs and cloud attenuation of the disc; preserve colour-space and horizon matching |
| [Ground shader](../../../../app/render/ground.gdshader), [grass shader](../../../../app/render/near_grass.gdshader) | Custom light functions apply the solar cloud transmission to every directional light | A later Moon needs its own lighting/projection treatment |
| [Atmosphere.update_clouds](../../../../app/render/atmosphere.gd) | CPU simulation time updates the sky offset once per simulation second; QUALITY radiance can be recomputed on each update | Measure invalidation cost before increasing update frequency; do not describe current radiance as permanently frozen |
| [NearGrass.build](../../../../app/render/near_grass.gd), [Ground](../../../../app/render/ground.gd) | Shader values are copied into grass and duplicated surface materials | Updating only the sky or the original ground material can leave stale daylight consumers |
| [Shadow.footprint / alpha](../../../../app/render/shadow.gd) | Sun Y is clamped to 0.05; opacity is positive and depends only on aircraft altitude | Add a direct-light/shadow-availability contract and bounded horizon behavior |
| [Main capture path](../../../../app/main.gd) | Shadow-position metadata divides by `sd.y` | An exact horizon selection requires explicit no-projection handling, even if the image itself renders |
| [Scenery.build](../../../../app/scenery/scenery.gd), [GroundFeatures.contact_shadow](../../../../app/scenery/ground_features.gd) | Sun is read once when merged shadow geometry is built; projection clamps Y to 0.2 | Resolve static light before construction; later edits/progression need an explicit shadow update strategy |
| [Cue grounding](../../../../app/render/flight_cue_shadows.gd) | Unshaded darkening footprints are explicitly artistic contact grounding | Keep them distinct from directional solar shadows and prevent lightening artifacts |
| [HomeScene](../../../../app/ui/home_scene.gd) | Independent environment, still composition and fixed cloud time; uses the same builders | Reuse lighting evaluation with scene-local resources; avoid leaking global uniforms between previews and flight |
| [Frames](../../../../app/render/frames.gd) | Render X east, Y up, −Z north | Test solar east/west and zenith independently before tuning appearance |

The generic day/night skill example was inspected but not adopted: its frame-delta clock, fixed-hour sunrise and simple rotation do not meet this repository's deterministic timing or geographic solar contract. The existing app remains the implementation foundation.

## Reproduce the inspection

From the repository root:

```sh
git rev-parse HEAD
git status --short
rg -n 'ATMOSPHERE|sun_|exposure|cloud_update_s' app/spec.gd
rg -n 'sun_direction|PROCESS_MODE|update_clouds|_set_haze_uniforms' app/render/atmosphere.gd
rg -n 'sd.y|visual_clock_s|capture_evidence|_trace_meta' app/main.gd
rg -n 'sun|shadow|shader_parameter' app/render/shadow.gd app/render/near_grass.gd app/scenery/ground_features.gd app/scenery/scenery.gd
```

These commands reproduce the source search, not a graphics experiment. TOD-01 must supply the first rendered and timing evidence. No application scripts, assets, dependencies or generated physics data were changed for TOD-00. No app tests were run because this change only adds and connects documentation. Document checks cover local link targets, registered step names and whitespace.

Documentation verification: 93 relative links in new documents and added/changed index lines resolve to non-ignored paths; 17 step rows have unique TOD IDs. `git diff --check` and new-file `git diff --no-index --check /dev/null <file>` report no whitespace errors. The patch contains four new Markdown documents and five small existing-document updates.

Suggested commit: `docs(TOD-00): plan selectable time of day (proof: 93 local links and step registry checked)`.

## Plan review

A separate Luna Max source review found four gaps, corrected before delivery:

- A clock/date-only CLI could not reproduce Home's location/offset selection. The proposed complete lighting-config input now covers that route without reading preferences.
- Solar accuracy was incorrectly assigned to the renderer probe. TOD-02b owns the independent astronomy comparison.
- Saved lighting context was being conflated with a rendered replay/seek feature. The plan now limits delivery to recording, known-tick lighting reconstruction and paired checkpoint restore; a visual player is deferred.
- No independent sky-luminance calibration set was identified. Curves are now explicitly estimated, with reference collection and pilot review planned; ordinary photographs are not photometric validation.

This review checks plan consistency with inspected code; it is not runtime verification.

## Retained uncertainties

The fictional field has no accepted geographic location. Its reference location/date/offset must be labelled and pinned before the astronomical mode ships. Visual intensities/curves remain estimates until independent references and pilot evidence exist. The lunar model, artificial light equipment, glare, time-varying weather and more sophisticated sky models have separate later scope. Research source/asset licenses are recorded in the primary-source report; no third-party assets were imported.

Existing [rendering lessons](../../../learnings/models-and-rendering.md) and [shared lessons](../../../../LEARNINGS.md) already cover source-vs-runtime evidence, local visual metrics, float64 boundaries and target-hardware acceptance. This audit proposes follow-up probes; it does not add an unmeasured result as a new lesson.
