# AI filmmaking skills research — GitHub and Reddit (2026-11-21)

**Scope:** investigate actual agent SKILL.md resources, film directing/video-editing practices, practical Reddit experiences and relevant AI capabilities; selectively adopt safe text-only skills for OPEN RC SIMULATOR Trailer 2.0. No external executables, packages, APIs or video generators were installed or run.

## 1. Adopted: five verbatim MIT film-production skills

**Upstream:** [Benitoow/cinema-skills](https://github.com/Benitoow/cinema-skills)\
**Exact source revision:** [b3d96caaf90729f086ce8bfa96654f40fd98e4e5](https://github.com/Benitoow/cinema-skills/tree/b3d96caaf90729f086ce8bfa96654f40fd98e4e5)\
**Original author:** Benjamin Leleu, 2026. **License:** MIT, accompanying original LICENSE included next to *each* copied SKILL.md. Copied **unaltered**, not a dependency installed by a package manager.

| Name | Location in the production folder | Why it helps this trailer |
|---|---|---|
| shot-list | tools/trailer/skills/shot-list/SKILL.md | Turn V2 screenplay into motivated lens/framing/camera/action/duration coverage. |
| scene-breakdown | tools/trailer/skills/scene-breakdown/SKILL.md | Separate lake / FPV field / Workshop / dirt course / blue hour and preflight risks. |
| color-script | tools/trailer/skills/color-script/SKILL.md | Maintain a coherent day → twilight → night → Corsair warm-lake palette without muddy night plates. |
| cut-list | tools/trailer/skills/cut-list/SKILL.md | Map real clips/in-out points to 90 s, 30 s and 6 s edits, after footage/timecodes exist. |
| export-checklist | tools/trailer/skills/export-checklist/SKILL.md | Later validate 1080p60, audio levels, captions/phone safe area, licenses and final codec. |

The repo's existing [camera-cinematography](../../../.agents/skills/camera-cinematography/SKILL.md), [compositing](../../../.agents/skills/compositing/SKILL.md), [lighting](../../../.agents/skills/lighting/SKILL.md), [openrc-tools](../../../.agents/skills/openrc-tools/SKILL.md) and [openrc-debug](../../../.agents/skills/openrc-debug/SKILL.md) already cover Blender/Godot-native camera/quality/diagnostics; do not overwrite or duplicate them.

## 2. New original OpenRC-specific Agent Skills

Unlike the vendor package, these four are **original project instructions**, originally mirrored into .agents/skills and .claude/skills on the preproduction branch. The consolidated [skills directory](../skills/) holds each guide once. Their triggers are narrowly scoped to the game's trailer.

| Skill | File in tools/trailer/skills/ | Reason |
|---|---|---|
| openrc-trailer-director | openrc-trailer-director/SKILL.md | A game-first camera director: jet inverted, FPV race, helicopter/blimp, smoke, night, Corsair orbit + lake, 13-fleet reel. |
| openrc-trailer-continuity | openrc-trailer-continuity/SKILL.md | Identity/perspective and claim ledger: livery vs reflection, three-size presentation vs gameplay, OSD gate truth, actual impacts. |
| openrc-trailer-ai-previs | openrc-trailer-ai-previs/SKILL.md | Concept/storyboard prompts with one action, one camera move, stable start/end frame, clearly marked AI reference status. |
| openrc-trailer-edit-review | openrc-trailer-edit-review/SKILL.md | Review 90 s cut, 30 s/6 s derivatives, source image/audio, supported feature claims, frame/timecodes and color/rights. |

All nine agent skills are **text instructions**, not automatic tools. Having them in this branch does not mean this session has installed a Remotion project, invoked an AI video model or rendered a frame. Open the bundled guides directly from the production folder.

## 3. Reviewed GitHub skills and toolkits — NOT automatically imported

| Source | What it contributes | Decision for OpenRC | Reason for not vendoring today |
|---|---|---|---|
| [AustinZ21/cinematic-skills](https://github.com/AustinZ21/cinematic-skills) | Shot-director vocabulary, 22 camera moves, start/end framing, screen direction, still-to-film methods. MIT. | **Use as director reference** and cite. | Skill references multiple supporting documents; copying one file creates broken relative guidance; repo already has cinematography. |
| [g0dam/video-studio-skills](https://github.com/g0dam/video-studio-skills) | Six modules: visual taste profiling, story planning, asset bible, shotboard, render prompts, release QA. MIT. | **Use workflow structure**; especially a visual canon and shotboard. | Full suite more generic/AI-character-oriented than this real-game trailer. |
| [remotion-dev/skills](https://github.com/remotion-dev/skills) | Official Remotion skill ecosystem: compositing, kinetic text, captions, audio, motion animation, render preview. | **Candidate post-production option**, not installed. | OpenRC already has a Python/FFmpeg edit toolchain; introducing React/Remotion requires separate dependency/licensing/renderer decision. |
| [iamaanahmad/agents-video-editing-skills](https://github.com/iamaanahmad/agents-video-editing-skills) | FFmpeg, audio, subtitles, vertical reframe, export, QA playbooks. MIT. | **Reference for future export/cutdowns.** | Installer would execute external tooling; choose a small set of safe methods only when video work is approved. |
| [karekin/video-shotcraft](https://github.com/karekin/video-shotcraft) | Product-video shot recipe gallery, sound hits, beat-synchronized cuts, motion design. | **Creative reference**, not a replacement for native game capture. | Many examples target product/promo composites and require Remotion workflows. |
| [Benitoow/cinema-skills](https://github.com/Benitoow/cinema-skills) | Five dependency-free filmmaker documents. MIT. | **Imported five skills**, exact pinned snapshot. | Small, auditable, no scripts. |
| [replicate/skills — prompt-videos](https://github.com/replicate/skills/blob/main/skills/prompt-videos/SKILL.md) | Camera/motion/composition/atmosphere prompt vocabulary for video models. | **Reference for non-gameplay previs**. | Provider execution/generative assets are not needed to prove game capabilities. |
| [scenario-labs/skills](https://github.com/scenario-labs/skills) | Model-assisted video, motion storyboard, grading, edits, audio and provider orchestration. | **Research only.** | Model credits/provider connection/cost/rights require explicit future approval. |
| [cajias/agentic-video-skills](https://github.com/cajias/agentic-video-skills) | Curated prompt, director and storyboard plug-ins. | **Research only.** | Aggregate includes an upstream storyboard skill identified without a license; do not blindly copy unlicensed content. |
| [ella-wang-opus/awesome-video-skills](https://github.com/ella-wang-opus/awesome-video-skills) | Directory of installable visual/video-first skills. | **Discovery index only**. | Catalogue is not a vetted security/license audit of each package. |

### Security / rights assessment

- Only the five selected MIT Markdown skills were vendored. Confirmed their original content and MIT license from the pinned GitHub revision; each location retains its own LICENSE file.
- We did **not** run npx skills add, Node/npm/Python installers, shell scripts, video APIs, browser automation, or paid generative models. No secrets, credentials, images, fonts, binaries or music were added.
- Third-party skill text is untrusted project input; check tool requests and commands before any future execution. Agent instructions cannot override user scope, repository safety, licensing or current product truths.
- Link-only candidates are **not installed** and no external capability should be claimed active simply because a name appears here.

## 4. Reddit workflow research — reports, not verified benchmarks

Reddit is valuable for production pain points and creative process, but posts are individual experiences (sometimes promotional); none is evidence of OpenRC feature support or of a specific AI model's reliability.

| Discussion | Main reported lesson | Application to OPEN RC SIMULATOR |
|---|---|---|
| [r/aifilmmaking — One year of production lessons](https://www.reddit.com/r/aifilmmaking/comments/1v7hm7e/) | Coherent long films depend on a stable **visual canon**: shot direction, props and scene states recorded before rendering. | Track Corsair body/skin/reflection, same lake sky and camera pose; match all three Stik sizes; keep each drone gate/OSD state honest. |
| [r/aifilmmaking — Overplanned AI short failed](https://www.reddit.com/r/aifilmmaking/comments/1xtvofy/) | A huge all-in-one prompt produced stiff video; a short single camera-movement study felt more cinematic. | Test one 3–6 s lake orbit or gate POV at a time in concept/previs. Keep storyboards modular; don't write one monster prompt for 90 s. |
| [r/aivideomaking — AI for creative edits?](https://www.reddit.com/r/aivideomaking/comments/1wvcsi6/) | Community replies favor AI for selecting takes, rough cuts, motion ideas, masks and technical tasks; human judgment remains central for continuity, color and sound. | Use skills to propose multiple cuts and evaluate, not to automatically ship a generated movie. |
| [r/aifilmmaking — My film process](https://www.reddit.com/r/aifilmmaking/comments/1sgs2z9/) | Start from narrative/emotion, build keyframes and visual references, iterate, then sound and edit make shots coherent. | Build mood/color boards for the Corsair lake and night RGB, retain real game audio as the identity, iterate on story impact. |
| [r/aifilmmaking — Storyboarding for animation keyframes](https://www.reddit.com/r/aifilmmaking/comments/1vqejuy/) | People want storyboard images to be reusable as production keyframes, with continuity between views. | If visual concepts are later generated, record start/end frame and camera settings; do not mistake the board for actual gameplay. |
| [r/aifilmmaking — Reactions to AI video production pain points](https://www.reddit.com/r/aifilmmaking/comments/1xhza02/) | Multi-shot consistency, sound, editing and model variation remain recurring burdens. | Build a continuity register and human review gate before automated assembly. |

## 5. Recommended workflow once the director approves actual video work

1. **Script**: use openrc-trailer-director and scene-breakdown to lock story beats and visual purpose; preserve user-chosen Corsair orbit, lake and skins.
2. **Visual canon / color**: use color-script and openrc-trailer-continuity to lock vehicle/skin, time-of-day, geometry, gate and reflection expectations.
3. **Shotboard**: use shot-list and optional openrc-trailer-ai-previs to compare camera ideas. Synthetic boards remain labeled *concept* and are never evidence of gameplay.
4. **Film from game**: under separately authorized production, reuse existing Godot/Windows 3090 capture tooling and validate every planned move, feature and generated frame.
5. **Offline edit**: use cut-list and openrc-trailer-edit-review for scene rhythm, sound cues, versioning and visible gameplay evidence.
6. **Final QC**: use export-checklist to check true resolution, 60fps frame count, audio clipping, rights, captions, menus, language and platform specifications.
7. **Only if needed**: consider Remotion for motion titles or provider-generated concept cutaways after scope/rights agreement; never automatically substitute synthetic aircraft, physics or reflections for actual game footage.

The most valuable AI addition for this project is **visual decision support**: camera language, reference lock, edit alternatives and repeatable QC. Its strongest unique footage remains the game itself.
