# Effects research round 3 — planned questions and completed research

**Date:** 15 November 2026 (America/Bogota). **Source:** OpenRC `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; current head independently rechecked before research. **Engine pin:** `4.8.beta2.official.cafc17a19`.

This round answers the user's effects-specific follow-up. The earlier 28 investigations remain the baseline. The following 24 questions were allocated before detailed execution; each must add a concrete visual technique, comparison, counterexample, tool decision or discriminating check. Research completion is separate from native rendering qualification.

| ID | Planned question | Planned method | Owning report |
|---|---|---|---|
| FX01 | Which visible cues distinguish dry exhaust, true augmentation, LED lighting and smoke? | Manufacturer/reference-image classification | flame_reference |
| FX02 | How should flame gas, soot and hot metal receive credible colors? | Primary emission studies and reference conditions | flame_reference |
| FX03 | How should shock cells appear without a universal diamond-spacing claim? | Nozzle/shock references and view analysis | flame_reference |
| FX04 | How can a core, mixing layer and fading tail approximate the visible plume? | Mixing evidence and bounded profile design | flame_reference |
| FX05 | How should wind, coflow and turns affect the near and far plume? | Transport reasoning and reference comparison | flame_reference |
| FX06 | How should flame and hot nozzle respond during ignition and shutdown? | Turbine/nozzle evidence and visual sequencing | flame_reference |
| FX07 | Which mesh, card, slice or proxy representation works from all needed views? | Representation comparison and geometry counterexamples | shader_techniques |
| FX08 | How do additive, alpha and premultiplied layers change apparent brightness? | Godot blend contracts and optical/compositing arithmetic | shader_techniques |
| FX09 | Are parameterization, winding, normals and nozzle transforms coherent? | Starter mesh/Jacobian and source inspection | shader_techniques |
| FX10 | How can the shader actually filter unresolved cells and animated detail? | Derivative-filtering formulas and sampling checks | shader_techniques |
| FX11 | How can flame intersections and close-camera views remain clean? | Depth-fade/reconstruction and clipping analysis | shader_techniques |
| FX12 | How should color, fog, exposure, glow and local illumination interact? | Renderer/material/environment contracts | shader_techniques |
| FX13 | Which procedural noise resources and imports are practical? | Godot noise APIs, lifecycle and memory arithmetic | tools_assets |
| FX14 | When is a flipbook useful, and how should its atlas be prepared? | Official authoring/import workflow and memory/angle tradeoffs | tools_assets |
| FX15 | Can flow maps and curl-style motion improve texture advection? | Primary techniques and bounded temporal alternatives | tools_assets |
| FX16 | How should a reusable particle detail profile schedule births and randomness? | Current smoke scheduler versus stock Godot features | tools_assets |
| FX17 | When would a baked volume or ray-marched proxy justify its cost? | Texture3D/VDB pipeline and workload estimates | tools_assets |
| FX18 | Which free tools and reusable examples should actually be adopted? | Official projects, capabilities, maintenance and licenses | tools_assets |
| FX19 | What authoring profile makes effects reusable and hard to misconfigure? | Godot Resource/Inspector contracts and current attachment ownership | effects_workflow |
| FX20 | Which distinct visual concepts best serve RC readability and larger jets? | Reference-led art directions and capability mapping | effects_workflow |
| FX21 | What controllable VFX laboratory will shorten iteration in Godot? | Existing debug/capture tools and designed case matrix | effects_workflow |
| FX22 | How should the effect behave in lake reflections and secondary views? | Current lake/render-camera source trace | effects_workflow |
| FX23 | How can shader variants and first-use compilation avoid surprise hitches? | Official pipeline-cache/precompilation guidance and project loading policy | effects_workflow |
| FX24 | Which image diagnostics and fallbacks reveal an unconvincing effect? | Discriminating capture metrics, failure cases and degradation ladder | effects_workflow |

**Completion:** all 24 records are complete, including inspected sources, version/coverage, finding, implementation choice, proposed check and remaining limits. Native acceptance remains pending. Production, the earlier prototype and its old test receipts remain unchanged. New original arithmetic and proposed authoring/capture data may be prepared outside the repository. Primary sources are required for technical claims; images and assets are not physical calibration.
