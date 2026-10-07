# Documentation map

Start here to find out what exists, where it lives and which document answers a given question. This map is the index of the project's documentation; it holds no status of its own beyond the registry table, which names the plan that does. Written 2026-10-06 after a review of every plan and research report ([audit](research/documentation-audit-2026-10-06.md)). Keep it current: a new track, plan or step-ID prefix is not real until it has a row here.

## What this project is

OpenRC Simulator is an open-source RC airplane simulator seen from the pilot's position on the field, built in Godot 4.7.2 (GDScript, Compatibility renderer). The owner is an RC pilot who flies a Das Ugly Stik 60 with EdgeTX radios; the project exists so that a radio in the hand and an airplane on the screen feel like the real thing.

The way we work is as much part of the project as the code. The principles below are defined in [ROADMAP.md](../ROADMAP.md#rules-for-every-step) and [DECISIONS.md](../DECISIONS.md); this is the short form.

1. **Be water, but on solid ground.** One step is one small change with one objective proof (test, capture, trace or measurement) that leaves the app working. "Looks fine" is not a proof.
2. **Known answers before unknown answers.** Math and integrators pass exact-solution tests before aerodynamics; new physics is read in trajectories before assertions are written.
3. **Every number carries its evidence.** Aircraft and field data are `{value, unit, kind, source}`; kinds are `manual`, `measured`, `borrowed`, `estimated`, `derived`. A guess is never presented as a measurement.
4. **Verification is not validation.** Checks against our own data prove the code; only independent data (flight-identified models, real airplanes, pilots) proves realism. Each physics milestone needs one of each.
5. **Gates are real stops** where the owner decides with the evidence collected, and the decision is recorded.
6. **Milestones end in a build the owner flies.** Feel and readability are judged on a real radio and a real screen, not in headless runs.
7. **Physics stays in 64-bit floats** and within a measured budget; realism and robustness come before features.
8. **Research is saved in `docs/`**, with sources, limits and a reproducible experiment when practical. Development is heavily AI-assisted, so evidence is written down instead of remembered.
9. **One team per commit**, with the proof in the message. Several developers and assistants work in the same tree at once.

## Start here, by role

| You are… | Read, in this order |
| --- | --- |
| A player or RC pilot testing a build | [README](../README.md) · [First launch](FIRST-LAUNCH.md) · [release notes](releases/) · how to report: [pilot feedback](../.github/ISSUE_TEMPLATE/pilot_feedback.md), [bug report](../.github/ISSUE_TEMPLATE/bug_report.md) |
| A developer or assistant starting work | [AGENTS.md](../AGENTS.md) (commands, rules, who owns what) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [ROADMAP: where we are](../ROADMAP.md#where-we-are) · the plan of your track (registry below) · its dated sections in [LEARNINGS.md](../LEARNINGS.md) · the [research index](research/README.md) |
| A reviewer of the project's direction | [DECISIONS.md](../DECISIONS.md) · the three plan reviews at the end of [ROADMAP.md](../ROADMAP.md) · [STACK.md](../STACK.md) · the [documentation audit](research/documentation-audit-2026-10-06.md) |

## One question, one document

Each question has one canonical document. Other documents may repeat the answer, but when they disagree the canonical one wins and the others are fixed.

| Question | Canonical document | Notes |
| --- | --- | --- |
| What is the project and how do I play it? | [README.md](../README.md), [FIRST-LAUNCH.md](FIRST-LAUNCH.md) | English, public |
| How do I run, test, capture and export? | [AGENTS.md](../AGENTS.md) | The command table and the rules every change follows |
| How do I contribute? | [CONTRIBUTING.md](../CONTRIBUTING.md) | |
| Where are we and what comes next? | [ROADMAP.md: where we are](../ROADMAP.md#where-we-are) | One line per track, each linking its plan |
| What are the steps of milestone M1…M5 and their proofs? | [ROADMAP.md](../ROADMAP.md) | Step IDs D, E, F, G, PT, Gate 1/2/F |
| What are the steps of a track (UI, visual, an aircraft…)? | The track's plan in `docs/` (registry below) | The plan is the source of truth for its own steps |
| What did we decide, why, and what would change it? | [DECISIONS.md](../DECISIONS.md) | Superseded rows are kept and marked |
| What stack do we use and why? | [STACK.md](../STACK.md) | Current stack at the top; the pre-Gate-1 survey below it is history |
| What did we learn by building? | [LEARNINGS.md](../LEARNINGS.md) | Cross-cutting sections by theme first, then dated entries per track in the order written |
| What did we read before Gate 1 and in plan review #3? | [RESEARCH.md](../RESEARCH.md) | A frozen notebook; new research goes to `docs/research/` |
| What must I know before starting a phase (theory, tools, data, tests, pitfalls)? | [Roadmap knowledge base](research/roadmap-investigations/README.md) | Ten documents from plan review #4, one per phase or cross-cutting area |
| Which research exists on a topic? | [docs/research/README.md](research/README.md) | Entry points per track |
| Which aircraft exist and what may the menu offer? | [`app/app_state/aircraft_catalog.gd`](../app/app_state/aircraft_catalog.gd) | IDs, names and the meaning of flyable / experimental / preview |
| Which numbers does an aircraft fly with, and where do they come from? | `app/data/aircraft/<id>.json` | Format `openrc-aircraft v1`; generated files name their generator |
| How were the README images made? | [docs/media/README.md](media/README.md) | |
| What shipped in a release? | `docs/releases/<tag>.md` | [rc2](releases/v0.1.0-rc2.md), [rc3](releases/v0.1.0-rc3.md), [rc4](releases/v0.1.0-rc4.md) |

## Tracks, plans and step IDs

State as recorded in each plan and in ROADMAP on 2026-10-06. "Owns" lists the paths a track changes; everything else is another team's and is touched only through its interface. Languages: en = English, es = Spanish (being translated; see convention 1).

| Track | Plan | Step IDs | State (2026-10-06) | Gate / depends on | Owns | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| **Physics and simulation** (main line) | [ROADMAP.md](../ROADMAP.md) (en, rev 5); repairs: [FLIGHT-MODEL-ROBUSTNESS-PLAN](FLIGHT-MODEL-ROBUSTNESS-PLAN.md), [RUDDER-REPAIR-PLAN](RUDDER-REPAIR-PLAN.md) | A–H, PT, EL, VAL-/DATA-/PERC-, M5 groups; `<step>-R<n>` repairs | M1 engineering baseline and Gate F done; Gate 2 open. E1–E3b3, H1–H11 implementation/evidence, D11a–b, D11d and E0a2a done; D11b is characterization. Gate P remains unmet. Bounded native slipstream verified on Linux; stall budget still fails. H12–H15 bring every fixture within 500 µs/tick at the median with exact trajectories (P-51 p95 still 519–536). Next: E0a2b/D11f and E1b before E3c, owner Gate P decision and [Stik circuit prerequisites](../ROADMAP.md#execution-order-and-release-gates) | Gate 2; target-machine Gate P; independent PT2 evidence | `app/physics/`, `app/sim/`, `app/data/aircraft/`, `app/data/ground/`, `app/tests/`, `app/main.gd` | [project audit](research/project-audit-2026-10-06/README.md), [flight-robustness/](research/flight-robustness/), [sensitivity](../research/sensitivity/results.md) |
| **Ugly Stik model** (model team) | [UGLY-STIK-PLAN](UGLY-STIK-PLAN.md) (es, rev 7) | US-01…08 | US-01–05 done (geometry v3). US-06 readability form, US-07 E1/E2 handoff and US-08 hardware cost wait for the owner | D1, D7, Gate 2, E1/E2 | `assets/aircraft/ugly-stik-60/`, `app/aircraft/ugly_stik_*`, `verify_model.gd`, `verify_controls.gd`, `inspect_model.gd`, `app/render/airplane.gd` | [ugly-stik-* reports](research/README.md#ugly-stik), [research/ugly-stik/](../research/ugly-stik/) |
| **Ugly Stik finish** (model team) | [UGLY-STIK-VISUAL-PLAN](UGLY-STIK-VISUAL-PLAN.md) (es, rev 5) | US-V01…08 | All eight done (finish v4, engine v5); human readability answers and GPU cost pending | D7, Gate 2 | `appearance.json` and `compile_appearance.py` next to the geometry | [model v4](research/ugly-stik-model-v4.md), [engine v5](research/ugly-stik-engine-v5.md), [research/ugly-stik/model-v4/](../research/ugly-stik/model-v4/README.md) |
| **Extra 300S .60** (second aircraft) | [EXTRA-300-PLAN](EXTRA-300-PLAN.md) (es, rev 5) | EX-00…13 | Flyable, **experimental**: EX-00–05, 07, 10a and 11 done; next EX-06 thrust axis, EX-08 envelope, EX-09 independent contrast | D5/D9c, D8–D10, UI-05, Gate 2, Gate F | `assets/aircraft/extra-300s-60/`, `app/aircraft/extra_300s_*`, `extra_clearance.gd`, `verify_extra.gd`, `inspect_extra.gd`; `app/data/aircraft/gp_extra_300s_60.json` is generated by `research/extra-300/ex05/derive_physics.py` | [extra-300-* reports](research/README.md#extra-300s), [research/extra-300/](../research/extra-300/) |
| **Avanti S** (jet, third aircraft) | [AVANTI-S-PLAN](AVANTI-S-PLAN.md) (rev 5) | AV-00…13 | **Experimental** in the catalog (AV-07): turbine branch (AV-05a), generated physics (AV-06), in-air start, flaps and gear up. AV-01 provisional, AV-02 contours being refined; next AV-09 flaps/gear, AV-10 fuel burn | Turbine propulsion kind in the loader (AV-05a), UI-05 | `assets/aircraft/avanti-s-a200/`, `app/aircraft/avanti_s_*`, `verify_avanti.gd`, `app/physics/turbine.gd`, `app/data/aircraft/sebart_avanti_s_a200.json` (generated), `test_turbine.gd`, `test_avanti_handling.gd` | [avanti-s-* reports](research/README.md#avanti-s), [research/avanti-s/](../research/avanti-s/) |
| **P-51D Mustang 1/4** (fourth aircraft) | [P51-PLAN](P51-PLAN.md) (rev 3); shapes and finish: [P51-VISUAL-PLAN](P51-VISUAL-PLAN.md) (es) | P51-00…14; V01…V11 are the sub-steps of P51-10 | Flyable, **experimental**: P51-00–09, 12 and 13 done (realism pass: NACA/RC cross-check, shaft engine, calibrated propeller, P-factor, slipstream, gear, spanwise stall, flown envelope); P51-14 pilot review pending; V09 scheme waits for the owner; P51-11 flaps and retracts blocked by E/G | UI-05, ROADMAP E and G | `assets/aircraft/p51d-mustang-120/`, `app/aircraft/p51d_*`, `verify_p51.gd`, `inspect_p51.gd`, `app/tests/test_p51_handling.gd`, `test_p51_envelope.gd`, `test_p51_ground.gd`, `p51_envelope_base.gd`; `app/data/aircraft/p51d_mustang_120.json` is generated by `research/p51/p51-05/derive_physics.py` | [p51-* reports](research/README.md#p-51d), [research/p51/](../research/p51/) |
| **Menus and product shell** (UI) | [MENU-PLAN](MENU-PLAN.md) (es, rev 3) | UI-00…15 (with a/b/c), delivery tiers UI-A/B/C | UI-00–05 done: Home, language, pause, end flight, build identity, Help, aircraft selector. Next UI-06 scenarios, UI-07 preferences, UI-08 HUD and volume | Gate 2; F3/F5 of M3 overlap UI-10/12 | `app/app_root.*`, `app/ui/`, `app/app_state/`, `app/addons/build_info/`, `app/i18n/`, `app/tests/ui_driver.gd`, `app/tests/test_ui_*.gd` | [menu-investigations/](research/menu-investigations/README.md) |
| **Visual quality** (execution of the field work) | [VISUAL-QUALITY-PLAN](VISUAL-QUALITY-PLAN.md) (es) | VQ-01…07; sequences the L steps from L5 on | VQ-01a/b, L5, L6a/b done; L6c numbers done, owner playtest pending; next L9a and VQ-02 | Gate 2, Gate L, UI-02/07 | `app/data/fields/`, `app/data/field_loader.gd`, `app/render/field.gd`, `app/assets/landscape/`, `assets/landscape/`, `tools/trees/`, capture checks in `app/tests/` | [visual-quality-implementation/<ID>/](research/visual-quality-implementation/) |
| **Landscape** (definition of the L steps) | [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md) (en) | L0…L20 (with letters), phases L-A…L-D, Gate L | L0–L4 done (shipped in rc2), L5–L6b done, L6c pending playtest; L7 onward planned; Gate L open | ROADMAP rule 7 budgets; M2 for terrain (L12), M5 for wind (L15) | `app/render/ground.gd`, `sky.gdshader`, `atmosphere.gd`, `treeline.*`, `tree_assets.gd`, `shader_clock.gd`; later `sim/terrain.gd` | [landscape-research](research/landscape-research.md), [landscape-investigations/](research/landscape-investigations/README.md), [tree-resource-review](research/tree-resource-review-2026-10-06/README.md) |
| **Crash and damage** | [CRASH-DAMAGE-PLAN](CRASH-DAMAGE-PLAN.md) (en, rev 2) | CR-00…27, Gate CR | CR-00 research slice done; CR-01 typed impact snapshot/readable cause next; report 03 thresholds pending under CR-07 | Gate 2 prioritizes presentation; E3d contacts; H8 before persistent damage; G4b before part-loss mass updates | `docs/CRASH-DAMAGE-PLAN.md`, `docs/research/crash-damage-investigations/`, `research/crash-damage/`; future `app/render/crash/`, `app/assets/audio/crash/`, `app/tests/test_crash_*.gd`; shared sim/UI through their owners | [crash investigations](research/crash-damage-investigations/README.md) |
| **Smoke** (exhaust and pump) | [SMOKE-PLAN](SMOKE-PLAN.md) (es, rev 2) | SM-00…09 | Proposal: no smoke code exists; one isolated Godot experiment | Model team's exhaust anchor, UI-10 radio wizard, wind W07 | Proposed: `app/render/aircraft_smoke.gd`, `app/sim/smoke_system.gd`, `app/input/aux_channel.gd` | [rc-exhaust-smoke](research/rc-exhaust-smoke.md), [smoke-investigations/](research/smoke-investigations/README.md) |
| **Scenery and field life** (separate parallel team) | [SCENERY-PLAN](SCENERY-PLAN.md) (en, rev 3) | SC-00…24, Gate SC | Proposal (2026-10-07): SC-00 done; SC-01 desk research done (4 reports), bake-off render and technique probe pending. Layout follows the owner's reference photo. Scenery is visual only and off by default until Gate SC | Visual/landscape track (one-line hook in `field.gd`, sub-budget, L10/L11b split, asphalt look O-6), physics line (asphalt friction O-6, camera near O-8), L14 for any collision, UI-06/07/08, VQ-06 | Proposed: `app/scenery/`, `app/data/scenery/`, `app/assets/scenery/`, `assets/scenery/`, `tools/scenery/`, `app/tests/test_scenery_*.gd`, `research/scenery/` | [scenery-investigations/](research/scenery-investigations/01-prop-asset-sources.md) (01 assets, 02 flora and sound, 03 layout, 04 techniques) |
| **Wind** (M5) | [WIND-PLAN](WIND-PLAN.md) (es) | M5-W00…W08, Gates W-A and W-B | Proposal: only W00 (the plan itself) exists. Its code audit predates the D9-R2 repair and must be re-read before W01 | M5; UI-07 settings; L15 windsock | Proposed: `app/physics/wind_*.gd`, `app/data/weather/` | [wind-physics-primary-sources](research/wind-physics-primary-sources.md), [wind-godot-integration](research/wind-godot-integration.md), [wind-investigations/](research/wind-investigations/README.md) |
| **Player guide** | [FIRST-LAUNCH.md](FIRST-LAUNCH.md) (en) | none | Current for the v0.1 alpha; also the fallback release notes in CI | PT1g, Gate 2 | — | — |
| **Releases** | [releases/](releases/) | tags `v*` | rc1 (notes in FIRST-LAUNCH), [rc2](releases/v0.1.0-rc2.md), [rc3](releases/v0.1.0-rc3.md), [rc4](releases/v0.1.0-rc4.md) | PT1f | — | — |
| **Tooling record** | [GODOT-SKILLS.md](GODOT-SKILLS.md) (es) + [installation manifest](godot-skills-installation.json) | none | Six third-party Godot agent skills installed outside the repo (`~/.codex/skills/`); not a game dependency | — | — | — |
| **Archive** | [archive/](archive/README.md) (historical plan revisions); [bake-off spec](../prototypes/stage0/SPEC.md) and [comparison](../prototypes/stage0/COMPARISON.md); [RESEARCH.md](../RESEARCH.md) | — | Frozen; kept for context. Historical plans carry a banner pointing to the current one | — | — | — |

Two rules keep this table honest:
- **A plan owns the status of its steps.** ROADMAP's [where we are](../ROADMAP.md#where-we-are) carries one line per track and links the plan; it does not repeat the step list. LEARNINGS records lessons, not status.
- **Status is written in one place per step.** When a step appears in two plans (the L steps appear in LANDSCAPE and VISUAL-QUALITY), the defining plan holds the status and the other links to it.

## Step-ID namespaces

| Prefix | Meaning | Defined in |
| --- | --- | --- |
| A, B, C | Foundation phases (done) | ROADMAP |
| D, E, F, G | Steps of milestones M1 (flight), M2 (takeoff and landing), M3 (radio), M4 (nitro); D11 is the M1 consistency follow-up (plan review #4) | ROADMAP |
| H, Gate P | Phase H: headroom, determinism and the extensible state; Gate P decides on GDExtension (plan review #4) | ROADMAP |
| EL | M4b electric propulsion (proposed, plan review #4) | ROADMAP |
| M5-ATM, M5-GE, M5-STALL, M5-SPIN, M5-PROP, M5-AIDS, M5-W-T | M5 sub-steps proposed by plan review #4 (the M5-W wind steps stay in WIND-PLAN) | ROADMAP |
| VAL-, DATA-, PERC- | Independent validation, aircraft-input pipeline and conditional schema evolution, pilot perception | ROADMAP |
| PT | Playtest and release steps (PT1a–g, PT2, PT4) | ROADMAP |
| Gate 1, Gate 2, Gate F | Platform (done), first owner flight (open), flight-model architecture (decided 2026-10-06) | ROADMAP, DECISIONS |
| `<step>-R<n>` | Repair sub-steps: C7-R1/R2, D1-R2/R3, D6b-R1 in ROADMAP; earlier D9-R1/R2, D4-R1, D1-R1, D8a-R1 and D10-R in repair plans | ROADMAP, FLIGHT-MODEL-ROBUSTNESS-PLAN, RUDDER-REPAIR-PLAN |
| M5-W | Wind steps of M5, with Gates W-A and W-B | WIND-PLAN |
| UI- | Menus and product shell; tiers UI-A/B/C | MENU-PLAN |
| VQ- | Visual quality deliveries | VISUAL-QUALITY-PLAN |
| L, Gate L | Landscape steps and their human gate | LANDSCAPE-PLAN |
| SM- | Smoke | SMOKE-PLAN |
| SC-, Gate SC | Scenery and field life (props, clubhouse, cars, flora, landmarks) | SCENERY-PLAN |
| CR-, Gate CR | Crash snapshot, presentation and later structural damage; Gate CR has structural and damaged-flight checkpoints | CRASH-DAMAGE-PLAN |
| US-, US-V | Ugly Stik model and finish | UGLY-STIK-PLAN, UGLY-STIK-VISUAL-PLAN |
| EX- | Extra 300S | EXTRA-300-PLAN |
| AV- | Avanti S | AVANTI-S-PLAN |
| P51-, V | P-51D; V01–V11 are the sub-steps of P51-10 | P51-PLAN, P51-VISUAL-PLAN |

Rules for IDs:
- A new track registers its prefix here before its first step; two tracks never share a prefix.
- Sub-steps keep their prefix. Write `P51-V01` and `US-V01` in prose when the bare `V01` could be read as the other aircraft's step.
- `M1…M5` are the ROADMAP milestones only. A plan's internal milestones use another word ("Hito A/B/C" or "tier").
- A gate is a question the owner answers; new gates (Gate L, Gate W-A/B) are listed here and, when answered, recorded in DECISIONS.

## Gates

| Gate | Question | State on 2026-10-06 | Recorded in |
| --- | --- | --- | --- |
| Gate 1 | three.js or Godot? | Done: Godot (owner, 2026-10-05) | DECISIONS |
| Gate 2 | Is v0.1 flyable, readable and fun with a radio? | Open; waits for the owner's session (ratings per axis, readability at 100 m, setup time, frame times) | ROADMAP M1 |
| Gate P | Does a measured physics bottleneck require GDExtension? | Open; all active aircraft/regimes on the owner’s slowest supported machine after justified optimizations; 500 µs/tick budget, reserve documented | ROADMAP Phase H, DECISIONS |
| Gate F | Keep the whole-aircraft derivative model or grow a component buildup? | Decided 2026-10-06 by the flight repair ([report](research/flight-repair-implementation.md)): a component buildup grown from the linear oracle, as proposed. Open: E0b propwash, G2 shaft balance | DECISIONS, ROADMAP |
| Gate L | Does the field read well to a pilot (horizon, trees, airplane)? | Open; L6c numbers recorded, human reading pending | LANDSCAPE-PLAN |
| Gate CR | Are structural outcomes and damaged flight plausible? | Open; later CR-B/CR-C checkpoints, after threshold research and contact/state prerequisites; distinct from Gate 2 priority | CRASH-DAMAGE-PLAN |
| Gate W-A, W-B | Wind feel and configuration | Proposed; nothing implemented | WIND-PLAN |
| Gate SC | Is the field more beautiful and alive while flying stays as readable and fast? Turns scenery on by default | Proposed; nothing implemented | SCENERY-PLAN |

## Where things live

| Path | What goes there | Rules |
| --- | --- | --- |
| Repository root | The eight canonical documents (README, AGENTS, CONTRIBUTING, ROADMAP, DECISIONS, STACK, LEARNINGS, RESEARCH) | English. New top-level documents need a row in this map |
| `docs/` | Plans (`<TRACK>-PLAN.md`), the player guide, this map | One plan per track |
| `docs/archive/` | Historical plan revisions | Banner on line 1 pointing to the current plan; never updated |
| `docs/releases/` | Release notes per tag | `<tag>.md`; fixed once the tag is published |
| `docs/media/` | Images used by the README, with provenance | Regenerated by `tools/readme/` |
| `docs/research/` | Research reports and the evidence that proves a step (JSON, logs, PNG, probes) | Indexed in [research/README.md](research/README.md); evidence folders named after the step they prove (`visual-quality-implementation/L6b/`) |
| `research/` | Scripts and data of reproducible experiments and of the aircraft measurement pipelines | Per track and step (`research/extra-300/ex05/`); some scripts generate repository files and say so in their header |
| `tools/` | Asset-processing tools (`trees/`, `readme/`) | Each tool folder has a README |
| `assets/` | Aircraft source data and generators, landscape sources with `PROVENANCE.json` | Generated outputs are regenerated, never hand-edited |
| `app/` | The simulator | See AGENTS.md; `app/test.sh` parses every script |
| `prototypes/stage0/` | The archived bake-off | Frozen |
| `references/` (gitignored, local only) | Third-party plans, scans and photos with unknown licenses | Never committed. Documents mention it in plain text ("local only: `references/…`"), never as a link that pretends to be in the repository |
| `app/captures/` (gitignored) | Generated captures | CI artifacts; not linked from documents |

## Conventions for documents

1. **English, short, concise, precise** (AGENTS.md rule 8), one language per file. Plans are in English; research reports written before 2026-10-06 may still be in Spanish and are translated when next revised.
2. **A plan starts with its identity:** title, date, revision, a one-line status in bold, its step-ID prefix, the paths it owns and links to its research. The status line is updated in the same change that completes a step.
3. **Steps are rows:** `ID | step | proof | status (date)`, and a dependency column when steps depend on other tracks. Done rows keep their proof.
4. **Dates are ISO** (`2026-10-06`). Revisions are integers.
5. **Research reports** say what was done, with what, what came out and what it does not prove; sources and licenses are listed; the reproducible command is included when it exists. Evidence lives next to the report or in the step's evidence folder.
6. **Lessons go to LEARNINGS.md:** cross-cutting ones in the thematic sections at the top, the rest appended at the end under `## YYYY-MM-DD · <step IDs> — title`, with the proof linked. Facts that change state go to the plan; decisions go to DECISIONS as table rows.
7. **Links** are relative and resolve from a fresh `git clone`. No links into `references/`, `app/captures/` or other ignored paths. Links to files not yet committed are committed together with the document.
8. **Status is not duplicated.** One line per track in ROADMAP, the full list in the plan.
9. **Historical versions** move to `docs/archive/`, keep a banner on line 1 pointing to the current document, and are never updated.
10. **Generated documents** (geometry tables, physics data, media) name their generator and are regenerated, not edited.

## Maintaining this map

- Adding a track: add its row to the registry, its prefix to the namespaces table, its gate if any, and a line to [AGENTS.md](../AGENTS.md) (parallel work) with the paths it owns.
- Closing or archiving a plan: `git mv` it to `docs/archive/`, add one `../` to its relative links, keep the banner and move its row to "Archive".
- Known gaps and stale statements found on 2026-10-06, with the line numbers to fix, are in the [documentation audit](research/documentation-audit-2026-10-06.md).
