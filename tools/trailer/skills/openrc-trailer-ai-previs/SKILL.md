---
name: openrc-trailer-ai-previs
description: Plan ethical AI-assisted previsualization, image-to-video reference explorations, camera prompts and storyboards for OPEN RC SIMULATOR while preserving truthful in-game marketing footage. Use when generating shot ideas, AI prompt packs, image boards, alternate camera plans and motion studies.
license: MIT
metadata:
  author: OpenRC Simulator trailer preproduction
  version: "0.1.0"
  domain: filmmaking
  related-skills: openrc-trailer-director, openrc-trailer-continuity, shot-list, color-script
---

# OPEN RC SIMULATOR — AI previs and concept explorations

## Principle: AI augments the director, not the product

The final public gameplay trailer should be filmed in the actual game. Use generative video or image tools to test **creative ideas and composition** (where the camera goes, how fast a skin reveal should feel, which sunlight works at the lake), not to invent a working feature or replace actual physics with synthetic motion while presenting the result as gameplay.

Never pass a synthetic plate off as a real OpenRC screenshot. Tag all studies **AI CONCEPT / NOT GAMEPLAY** in filenames/metadata and during review. Do not include those plates in a final marketing master unless the owner explicitly authorizes a clearly disclosed non-gameplay insert and all rights permit it. No external paid service, API call, asset download, executable installation or media-generation attempt is authorized by merely reading this skill.

## Previs worksheet

For each proposed scene make a structured director sheet:
1. **Purpose** — what can the player actually do?
2. **Canonical vehicle** — real catalog name, silhouette/skin and relevant colors; use no invented unlicensed model.
3. **Background anchor** — Club lake, Green paradise, RC dirt course, FPV gate course; single place per shot.
4. **Motion** — one primary subject action (e.g., level Corsair lake pass), one camera move (low-side tracking), one environmental motion (water ripples/trees).
5. **Start frame** — where camera/subject/horizon/reflection begin and their size in frame.
6. **End frame** — exact screen direction, camera stopping point and subject pose.
7. **Lighting** — actual day/night preset candidate and exposure intent; not automatically available graphics features.
8. **Continuity locks** — same skin body/reflection, wingfold state, wheel position, drone gate order, original/giant/mini depth.
9. **Acceptance** — compare a concept board to a real in-game capture later; concept must never become the evidence.
10. **Cost** — if any external model is considered, identify provider and current per-generation price separately before seeking permission.

## Recommended short prompt structure

Subject and provenance; one action; camera height/lens/track; start and end frame; light/weather; what stays constant; duration; 16:9; exclude added models/text/logos and unrealistic physics. A complex 90-second film should be separated into short shots and approved keyframes, not a single huge video-model prompt. Use reference images only when the user actually supplies or authorizes them.

Examples of **prompt concepts only**:
- Corsair orbit: the original F4U fills a stable frame while the camera circles; changing skins is **editorial**, not a metamorphosis of geometry.
- Lake: low shoreline tracking with aircraft above a believable moving mirror; label this previs, then test the game's planar implementation instead of borrowing synthetic reflection.
- FPV: camera fixed to the quad as it aims at a numbered gate; no arbitrary drone collision pass or invented race UI.
- Mini/giant: use a known runway landmark and all three plane sizes at one true depth; label simultaneous trio as cinematic staging.
- Jet: external low camera looking at real inverted canopy orientation; do not rotate the world.

## Useful AI roles with no promise of automatic execution

- Script-to-shots, shot ranking, emotionally motivated camera options, clip continuity checklists, first/last frame specifications.
- Moodboard, color script, storyboard alternatives, narration draft (optional), animated logo sketch and typography experiments.
- Text-free storyboard frames and motion references **for planning**; separate from filmed product.
- Suggested FFmpeg/Remotion post-production structures for subtitles, 2D animated titles and cuts; actual use requires separate decision and tool verification.
- Shot sound-cue planning, stem layout, rights matrix, automatic technical QC design.

## Validation and human control

Research communities repeatedly emphasize reference continuity, short shot units, sound design and actual editorial judgment. Write independent alternatives then select with the user; do not make arbitrary aesthetic decisions irreversible. Do not assume any AI tool preserves multi-shot consistency without tests.

Sources for further reading (not vendored or invoked): https://github.com/AustinZ21/cinematic-skills ; https://github.com/replicate/skills/blob/main/skills/prompt-videos/SKILL.md ; https://github.com/g0dam/video-studio-skills ; https://www.reddit.com/r/aifilmmaking/comments/1v7hm7e/ .
