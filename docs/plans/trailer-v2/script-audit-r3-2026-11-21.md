# Trailer 2.0 — screenplay audit and R3 decisions

**Historical audit.** The [R5 audit](script-audit-r5-2026-11-21.md) records current integration and timing; this document preserves the R3 findings.

**Date:** 21 November 2026. **Owner / track:** trailer director-editor / V2.
**Input:** trailer branch at 046839601c76f6416ca7315eeeb635706a884dee; R2 and all supporting documents; nine selected filmmaking skills; historical v9.13 report; current game source at 57abea025f62b20233ca281d58d2acbee4ab8b8e.
**Output:** [R3 screenplay](cinematic-script-r3.md), [timed storyboard](storyboard-90s.md), [mechanical sequences](mechanical-sequences.md), revised treatment/bible/gates and current index.

## Audit conclusion

R2 has the right ingredients, but its internal shot demands are denser than its ninety-second blocks suggest. The strongest revision gives the important actions time to register, restores the user's original Corsair orbit, and uses mechanism movement as a short story about control. It retains all 13 configurations across the film, rather than introducing and then reintroducing the heroes.

This is a **script-level and source-level audit**. No new MP4, rendered frames, animatic, music audition, phone playback, game launch or hardware capture was reviewed. Descriptions of readability are proposed acceptance criteria, not observed audience results.

## Findings and decisions

| Finding | Consequence | R3 decision |
| --- | --- | --- |
| R2's Corsair chapter replaced the original smooth skin-changing orbit with repeated lake angles. | The user's favourite shot was lost despite retaining the same aircraft and paint theme. | Restore a seven-second continuous orbital move and the full current 13-stock-scheme cycle; follow with a six-second lake pass holding the final skin. Preserve the full eased orbit/skin coverage first when retiming. |
| Thirteen roughly one-second introductions also asked for actions, names and distinct sounds. Many heroes returned later. | Recognition competes with reading; complete rolls/jumps are unlikely to fit those descriptions. | Distribute all 13 in a coverage ledger. Use longer action/identity shots and no extra roster parade. |
| The new request needs collective movement, not just a spinning rotor. The old documented inspector shot used cyclic. | Reusing a generic rotor or cyclic shot could misrepresent the requested mechanism. | A new stopped-rotor collective study in the articulated HX-700 inspector, labelled throughout; separate actual X-Cell flight immediately follows. |
| The playable helicopter's legacy visual has no blade-feather hinge. | An unlabelled macro could imply the articulated rotor is in the flight model. | Explicitly identify the inspector and keep its studio context. Do not advertise it as a flight mode or exact flight dynamics. |
| Full Corsair wing travel is about eight seconds; canopy/flaps about 2.5 seconds. | A quick montage could accidentally imply unrealistically fast full cycles. | Native-speed excerpts with fixed references and visible end poses. The separate 32-second vignette allows fuller movements. |
| R2 had no clear distinction between a desired cockpit detail and supported cockpit animation. | The film could promise moving stick/pedals or a fixed-wing interior camera. | Show the actual sliding canopy; retain genuine instrument widgets. No unsupported interior control animation. |
| Gear retraction is blocked on loaded wheels; current authored retraction is four seconds. | A ground retract shot is not a supported player action; a four-second companion shot cannot also contain a separate held payoff. | Retracts occur airborne in the companion idea, with a six-second slot for travel and framing/hold. |
| P-51 and baseline/Extra propulsion were described inconsistently in older notes. | Wrong sound identity weakens the aircraft's character and factual accuracy. | Baseline Stick is a .61 glow reference; Extra .61 glow; Mustang 120 cc gasoline; Corsair Moki radial. Use actual game audio. |
| A baseline glow Stick and Electric 6S can look similar. | The ledger may count two configurations that a silent viewer cannot distinguish. | Explicit Electric 6S identity early; .61 GLOW identity held across size-control/trial footage. |
| The prior 'ANY SIZE' line was broader than the supported model/range. | It implies universal scaling. | Specific baseline Stick 10%–500% copy and a separate labelled cinematic size trio. |
| Multiple Creator setup steps and two captions competed with seven seconds. | The process and experimental qualification could both become unreadable. | One accepted model, one setup adjustment, one eligible trial; one persistent line: IMPORT · EXPERIMENTAL TEST FLIGHT. |
| An impact immediately after Creator could imply the imported model crashed. | It undermines the promised successful experiment. | Move the brief effect to a separate FPV attempt at 22–23.5 s. Creator now ends in successful flight, followed by the Bisonte. |
| Three-second end card carried too many messages. | The download invitation is easy to miss. | Five seconds; logo, PLAY FREE, real URL and actual product status. Surrounding campaign copy can carry the tagline. |
| The previous 80–85% gameplay target did not account for the inspector, staged trio, livery treatment, UI and card. | Attractive presentation could be counted as interactive gameplay. | Conservative explicit budget: 65.5 s G + 5.5 s U + 14 s P + 5 s E = 90 s. |
| Capture, audition and even blood/formation tests were listed before resolving the current story. | The plan could launch tool work unrelated to the user's present priority. | Script first; tools next; actual proof takes later. Remove blood/formation as master prerequisites while preserving them as optional ideas. |

Source details for mechanisms are consolidated in the [mechanical evidence matrix](mechanical-sequences.md#what-the-current-source-actually-supports). The [claim matrix](verification-gates.md#source-to-screen-claim-matrix) owns the broader feature boundaries. Historical film observations remain in the [v9.13 record](../../research/cinematic-trailer/revision-9-2026-10-29.md).

## Application of all nine skills

Each of these files was read for this revision. Their contribution is procedural; none proves that footage, software integration or a final film exists. Upstream provenance/licences remain in the [existing manifest](vendor-skills-manifest.json).

| Skill | What was applied | Concrete result |
| --- | --- | --- |
| [shot-list](../../../.agents/skills/shot-list/SKILL.md) | One beat/purpose per shot, practical size/angle/movement, meaningful completed action and cheaper fallback. | Hero cards and the six-part ground sequence; no one-second complete aerobatic roll. |
| [scene-breakdown](../../../.agents/skills/scene-breakdown/SKILL.md) | Separate scenes, complexity and unknowns; group by location/light rather than story order. | Shot-bible grouping table; inspector, ground controls, lake and Creator have different risks and honest alternatives. |
| [color-script](../../../.agents/skills/color-script/SKILL.md) | Emotion-to-colour progression, motif, continuity and legibility. | Treatment palette: neutral precision, warm identity, readable blue night and a softer lake payoff; no invented LUT or recoloured skin. |
| [cut-list](../../../.agents/skills/cut-list/SKILL.md) | Add actual planned durations, choose transitions by purpose, alternate intensity/holds. | Exact paper cut and category budget; source in/out and score beats remain unassigned. |
| [export-checklist](../../../.agents/skills/export-checklist/SKILL.md) | Design readable text and an invitation now; distinguish future media/delivery checks. | Five-second card, shared text budget and pending full-decode/audio/display checks. No codec/platform claim from an absent export. |
| [openrc-trailer-director](../../../.agents/skills/openrc-trailer-director/SKILL.md) | Preserve the requested visual signatures; specify action, camera endpoints, stable references and fallbacks. | Original orbit into lake; fixed-reference mechanism details; genuine gate and truck outcomes. |
| [openrc-trailer-continuity](../../../.agents/skills/openrc-trailer-continuity/SKILL.md) | Track model/skin/state/source class and avoid false feature inferences. | Skin ledger, same reflected livery, inspector/X-Cell separation, labelled trio and correct engine identities. |
| [openrc-trailer-ai-previs](../../../.agents/skills/openrc-trailer-ai-previs/SKILL.md) | One action/one principal move; clear first/end frames; concepts are not gameplay evidence. | Concrete written shot cards without needing generative plates or selecting a video model. |
| [openrc-trailer-edit-review](../../../.agents/skills/openrc-trailer-edit-review/SKILL.md) | Silent story, cadence, audio identity and finish are distinct review passes. | Explicit pending mute/phone/full-motion review, native sound arc and a successful-play ending. |

The four original project skills still contain fixed R2 references. The updated README explicitly makes R3 authoritative and treats R2 as historical input. This task does not rewrite the imported skill files or select their suggested tools; the user's screenplay-first instruction governs the present work.

## Independent challenge and integration

Two source-read-only reviews were used: mechanical implementation and editorial structure/continuity. Their useful findings were checked against the owning source or the integrated draft. Accepted corrections include inspector/playable separation, native mechanism times, the manual-sourced 30-degree flap limit versus estimated actuator time, four-second current gear retraction, full-orbit priority, explicit glow identity, one Creator caption and moving impact away from the Creator payoff.

The edit has **one shared two-second reserve**, the final flourish. It cannot simultaneously solve three different timing problems. Any future reallocation must update the storyboard and source-class totals; if it is insufficient, make a specific further trim or present a longer alternate. The current 90-second paper edit has not already spent this reserve. It is also the conditional night-light fallback: removing it requires explicit replacement or recorded reduced night coverage. Removing text alone does not create more screen time.

One optional suggestion was not adopted: adding a second skin-switch montage on another model. The user's request is satisfied by deliberately distributing actual supported skins through existing takes; another rapid transformation would compete with camera/HUD readability. Non-Corsair skin choices and the Corsair sequence/final hero choice remain to be logged before filming. The 13 Corsair stock IDs were verified in its manifest; their rendered appearances were not reviewed. A first R3 draft proposed only three Corsair skins; the lead restored the full cycle to preserve the user's stated preference. The rapid same-airframe paint rhythm remains a visual-proof risk, not a completed readability test.

## Verification record

The final branch update must pass the focused documentation checks below. This section records paper/source scope only; it does not turn a planned shot into validated footage.

| Check | Scope / result |
| --- | --- |
| Nine skills read | All five imported and four original selected files read; source/licence files unchanged. |
| Source inspection | Corsair bindings/interlocks/travel, inspector controls and playable rotor limits read; quad lens/contact integration and vehicle propulsion identities checked. |
| Independent editorial review | Found a contiguous 34-row, 90-second first R3 table; subsequent accepted changes moved the contact beat and preserved the same category totals. Final root recheck passed the figures recorded below. A final independent closeout also caught and resolved stale scene-group IDs, catalogue wording and the orbit-reserve wording after retiming. |
| Documents and arithmetic | Root check: 34 contiguous cut rows and 13 contiguous screenplay chapters, exactly 90.0 s / 5,400 intended frames; whole-frame boundaries; G 65.5 / U 5.5 / P 14 / E 5; 13 fleet entries; companion 32 s. All 146 relative links and 13 explicit heading anchors resolved against the candidate/tree. Markdown trailing spaces found on the first pass were removed; git diff --cached --check passed for the final staged candidate. |
| Media, audio, runtime and hardware | **Not performed.** No new video, image, animatic, game launch, listening test, FPS measurement or target-GPU proof. |
| Changes | Screenplay/supporting Markdown in this trailer directory only; no game, tools, skills, dependencies or assets changed. |

## What should be checked next

First evaluate the actual story visually: especially the one-second elevator/rudder inserts, real widget readability, mini-plane scale, disclosure reading and unhurried full orbit. Then decide the capture and editing routes needed for the accepted shots. Qualify the collective, Corsair mirror, native mechanism travel, Creator eligibility and night body visibility on the chosen build.

The [working script](cinematic-script-r3.md) is ready for creative feedback. The film, tools, actual skin selections, music grid and picture lock remain later work; this audit makes no claim to have completed them.
