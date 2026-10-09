# Graveacre AI-assisted asset workflow

2026-10-09 · **Status: public-source research; vendor services were not called.** Standalone note; no implementation step ID.

## Findings

The Graveacre author describes a development-time art pipeline for a browser idle game. The author says an agent calls PixelLab and Retro Diffusion through MCP, while a script normalizes the outputs and a review page lets a person mark assets for rework. A held tool changed shape across generated animation frames, so the author reports animating the body separately, drawing the tool once, placing it with explicit depth and angle per frame, and redrawing the hands over its handle. The author says an edited first frame works for objects with little rotation. They also report using human screenshot review to catch mismatched viewpoints and contrast, and separate Git worktrees with a shared assignment file for parallel sessions. These are author reports, not independently measured results. The author says the live game makes no AI calls. [Reddit post](https://www.reddit.com/r/aigamedev/comments/1x15pre/making_a_pixelart_zombie_idle_game_with_claude/)

Vendor documentation confirms that both products expose remote MCP workflows and image-generation features. PixelLab documents a remote HTTP MCP endpoint, text and skeleton animation, reference images, and inpainting; its animation guidance recommends human frame selection and rough manual corrections between generations. [Ways to use PixelLab](https://www.pixellab.ai/docs/ways-to-use-pixellab), [animation with text](https://www.pixellab.ai/docs/tools/animation), [animation with skeleton](https://www.pixellab.ai/docs/tools/animate-with-skeleton). Retro Diffusion's vendor-maintained MCP/API documentation describes a hosted MCP endpoint, animation outputs as GIFs or sprite sheets, image-to-image input, reference images for supported styles, and image-editing tools. [Retro Diffusion MCP](https://github.com/Retro-Diffusion/retro-diffusion-mcp), [Retro Diffusion API examples and field reference](https://github.com/Retro-Diffusion/api-examples).

The docs establish interface capabilities; they do not establish output quality or a vendor feature that keeps a hand-held object geometrically fixed through animation. The separate-object composition described in the post is the author's own workaround.

## Transferable lessons

- Keep generated appearance separate from functional geometry and transforms. For an aircraft, retain model dimensions, hinges, propeller placement, and control-surface motion as explicit project data.
- Give moving objects a stable source and deterministic pose/depth rules instead of regenerating them independently in every frame.
- Preserve prompts, job IDs, source images, and cleanup settings; review the result in representative in-app captures, where scale, viewpoint, silhouette, and contrast can be judged in context.

These are workflow lessons for visual assets; they provide no evidence about flight physics or aircraft-model accuracy.

## Comparison with OpenRC Simulator

Repository inspection at `5ae8798` with concurrent working-tree changes; no flight or rendering experiment was run for this note. The following applications are our engineering recommendations, not claims made by the Graveacre author.

| Lesson | Existing foundation | Practical application |
| --- | --- | --- |
| Preserve moving parts rather than regenerating them | [Aircraft adapter](../../app/render/airplane.gd) builds stable meshes and drives hinges and wheels explicitly | Keep control surfaces, propellers and landing gear driven by simulation state. Generated imagery can supply appearance references; it cannot establish dimensions, hinge placement or aerodynamics. |
| Normalize before importing | [Tree pipeline](../../tools/trees/README.md) checks hashes, scale, visible trunk position, alpha, mipmaps and source/derived captures | Reuse these checks for future generated decoration. Normalize visible ground contact, not just image or mesh bounds. Pixel-art hard alpha is not a universal rule: our distant tree cards need coverage-aware mipmaps. |
| Reuse appearance under different lighting | The tree bake preserves albedo without baking the diagnostic sun into the atlas | Prefer neutral appearance assets and runtime lighting. Check the airplane against sky, grass and treeline from the actual pilot camera before accepting decorative detail. |
| Turn human review into targeted rework | [Scenery scenario/history](../../tools/scenery/README.md), [rendered circuit kit](ground-contact/E3c2b/README.md) and [L6c human readability kit](visual-quality-implementation/L6c/README.md) already exist | Attach each observed defect to a build, view/tick, screenshot, severity and expected correction. Compare the same case after the fix. Repeatable pixels alone do not establish readable orientation. |
| Isolate parallel sessions | [Track registry](../README.md#tracks-plans-and-step-ids) assigns paths; the circuit renderer already recommends a frozen checkout | Trial separate worktrees for simultaneous code changes, retaining ownership and integration checks. Use separate capture output, import caches and user settings. Worktrees separate checkouts but share repository data; they do not remove merge conflicts. [Git documentation](https://git-scm.com/docs/git-worktree) |
| Use player feedback to choose the next change | [PT2 trial preparation](ground-contact/PT2/README.md) and [pilot feedback template](../../.github/ISSUE_TEMPLATE/pilot_feedback.md) already request reproducible evidence | Collect the manual Stik circuit and repair its largest reproducible blocker before expanding presentation scope. Preserve real-aircraft comparisons separately from automated verification. |

## Recommended next action

Use the existing PT2 flight card and review kits for one identified build. Record a short defect list alongside the pilot evidence:

`build / aircraft / controller / display / camera / zoom / trace tick or video time / observation / expected behavior / severity / owner / disposition / before-and-after evidence`

Choose one blocker, make one bounded correction, repeat its capture or maneuver and run the relevant checks. Reuse the current HTML kits and issue template; build a new review interface only if this trial demonstrates a missing capability. The [current execution order](../../ROADMAP.md#execution-order-and-release-gates) already prioritizes this outcome. This research does not close a gate or create a new implementation track.

If a later task requires generated assets, extend that asset's existing provenance record with provider/model version when exposed, prompt, job ID, seed when exposed, reference/output hashes and cleanup command/version. Job IDs document origin; they do not guarantee reproducible generation. Keep the original output and accepted derivative distinguishable.

PixelLab and Retro Diffusion are candidates for a future pixel-art task. Their documented sprite workflows do not justify adopting them for our current 3D aircraft. No tool purchase or runtime AI dependency is recommended by this investigation.

## Access and scope

The [Graveacre home page](https://graveacre.com/) returned a public HTML shell with bilingual game metadata, but its client-rendered game was not exercised. The supplied [Discord invite](https://discord.gg/rfXhhbHYFE) redirected to Discord; no server was joined and no channel content was read. PixelLab's public documentation was readable. Retro Diffusion's site/API reference was client-rendered in this research environment, so the readable capability details above come from its vendor-maintained public GitHub documentation. No accounts were created, services installed, paid generations submitted, or generated outputs tested. The Reddit post and all project-specific workflow details remain the author's claims.

No third-party images, code, or generated outputs are included here. Licensing and terms for vendor services and generated assets were not evaluated; this note does not establish reuse rights.

The [linked GIF](https://i.redd.it/1xtsn5xipbuh1.gif) was downloaded temporarily and decoded with Pillow: 1742 × 569 pixels, eight frames. Inspected frames 0 and 4 show four survivors in different directions; those frames do not demonstrate held-tool compositing. The media was not added to the repository. Reddit's automatically suggested related posts were outside this review's scope.
