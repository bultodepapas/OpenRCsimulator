# Development-practice selection — 19 November 2026

**DX-06 follow-up.** The owner requested at least twenty researched tips and explicit do/don't decisions, applied selectively to project documentation. This review evaluates **34 distinct practices: 14 applied or clarified, 16 retained, 3 rejected and 1 deferred**. It extends the [instruction-file audit](agent-orchestration-2026-11-15.md#instruction-file-audit--2026-11-19), without turning startup files into a general development manual.

## Scope and selection method

The candidate combines the earlier instruction branch at `718335245a1822611dbde6725fbf7c31dc59f369` with inspected current `main` at `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`. Main's newer event-ordering and display-measurement lessons were considered as existing work, not new findings from this review. The task changes documentation; it does not implement a new solver, runtime optimization or engine upgrade.

Sources were checked on **19 November 2026 (America/Bogota)**. Current official documentation, versioned API references and firsthand upstream issues are distinguished below. A retrieval date is not a publication date or an archived November snapshot. Godot references span **4.4–4.7**, while OpenRC pins **4.8-beta2**: they supply API guidance to verify against this project, not proof that an old engine bug persists. Older numerical references remain useful for stable principles; their dates are not presented as 2026 releases.

Three source-read-only investigations covered Godot/game development, simulation/numerics and agent instructions. The lead checked repository applicability and selected the edits; independent review challenges the integrated candidate. No third-party prompt pack, addon, skill or hook was installed.

Each item was evaluated for a credible primary basis and concrete OpenRC use. Applied items additionally need a gap or misleading statement in current guidance and a narrow document home. **Apply** means a documented conditional rule or precision correction, not that runtime code was changed. **Retain** means the existing implementation/guidance already covers the useful practice. **Reject** applies to the stated blanket approach; **defer** means no current need justifies a mandate.

## Godot and game development

| # | Practice and what not to do | Decision | OpenRC fit and document home | Sources |
| --- | --- | --- | --- | --- |
| 1 | Keep a fixed simulation timestep and bounded catch-up. **Don't** vary solver time with render FPS or promise real-time progress under overload. | Retain | [Project settings](../../app/project.godot) use 240 Hz and a 12-step cap; [STACK](../STACK.md#limits-and-upgrades) already describes slowdown. | [T01], [T02] |
| 2 | Use one interpolation owner. **Don't** globally enable Godot interpolation as a generic smoothing fix for this custom solver. | Reject blanket change | [Simulation](../../app/sim/simulation.gd), [Main](../../app/main.gd) and `physics_jitter_fix=0` already implement the presentation boundary. Preserve [rendering rules](../../app/render/AGENTS.md). This is not a rejection of interpolation itself. | [T03], [T04] |
| 3 | Reset presentation history at discontinuities. **Don't** assume an engine-node interpolation reset also resets custom state arrays. | Retain | `Simulation.reset` synchronizes accepted history; Main passes fraction 1.0 to `Simulation.interpolated()` while paused. Existing source owns this mechanism. Applying the engine tutorial's discontinuity principle to custom arrays is an inference. | [T05] |
| 4 | Keep active scene-tree changes on the main thread, mutable resources single-owner and shared plain data synchronized. **Don't** assume a mutex makes arbitrary engine/resource operations thread-safe. | Apply | Add the general ownership boundary to [STACK](../STACK.md#godot-runtime-boundaries), using the [flight loader](../../app/ui/flight_scene_load.gd) as an existing project example. No new thread pool is introduced. | [T06] |
| 5 | Retain a job owner through completion and discard abandoned results. **Don't** equate closing its UI with cancellation of engine work or free a live worker. | Retain | [Flight loader](../../app/ui/flight_scene_load.gd), [Home preparation](../../app/ui/home_flight_preparation.gd) and the [menu plan](../plans/menu-redesign.md#selected-preparation-while-home-is-visible) already own lifecycle and retirement. Preserve the dedicated-load workaround's original version scope. | [T07], [T25] |
| 6 | Poll an asynchronous load and collect its terminal result. **Don't** call `load_threaded_get()` immediately in a frame-sensitive path and assume it cannot block. | Retain | [Preview resources](../../app/ui/home_preview_resources.gd) already poll and collect; shutdown draining is a distinct intentional operation. Keep procedure details in the menu owner. | [T08] |
| 7 | Share immutable resources and isolate the subresources actually edited. **Don't** assume a second load or shallow duplicate creates independent mutable state, or deep-copy every asset. | Apply | Add resource ownership to [STACK](../STACK.md#godot-runtime-boundaries), grounded in [vehicle paint](../../app/render/vehicle_paint.gd), [lighting skins](../../app/render/lighting/lighting_skins.gd) and existing aliasing lessons. | [T08], [T09] |
| 8 | Attribute script, physics, rendering CPU and GPU cost separately. **Don't** read the Visual Profiler's CPU column as total application CPU or infer another platform's repeatability from one capture. | Apply | Clarify [graphics diagnosis](../tools/debugging-graphics.md#observe) and scope its repeated-capture claim. Existing target-hardware and paired-measurement gates remain authoritative. | [T10], [T11] |
| 9 | Type stable interfaces where useful and check failed casts. **Don't** mandate a repository-wide typing rewrite or claim a measured OpenRC speedup from typing alone. | Defer mandate | Existing typed interfaces include [ScreenStack](../../app/ui/screen_stack.gd). No demonstrated defect or benchmark justifies mass churn; use the local style when touching an affected interface. | [T12] |
| 10 | Give reused nodes explicit suspend/resume and disposal. **Don't** expect reattachment to rerun `_ready()` or `remove_child()` to free the node. | Apply | Add the lifecycle boundary to [STACK](../STACK.md#godot-runtime-boundaries), tied to [ScreenStack.pop](../../app/ui/screen_stack.gd) and its existing reusable-Home route. | [T13] |
| 11 | Distinguish event propagation from global input state. **Don't** assume GUI acceptance clears global polling or require `_unhandled_input` for every control path. | Retain | [Input/menu lessons](../learnings/runtime-and-delivery.md#radio-input-and-menus) already separate focus, held-key masking and flight axes; [ScreenStack](../../app/ui/screen_stack.gd) owns menu holds. | [T14] |
| 12 | Track source import metadata and required UID sidecars; rebuild generated caches. **Don't** commit `.godot/` or discard identity files as disposable cache. | Retain | [Setup](../TOOLS.md#developer-setup), [release checks](../../tools/release/README.md), `.gitignore` and `.gitattributes` own these contracts. The `.uid` completeness requirement is project-specific; the import tutorial chiefly explains `.import` metadata. | [T15] |
| 13 | Verify runtime data in the exported artifact. **Don't** infer its presence from an editor run or add include filters without checking export behavior. | Retain | [Release tooling](../../tools/release/README.md), [export plugin](../../app/addons/build_info/export_plugin.gd) and [delivery lessons](../learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence) already inspect packaged resources. | [T08], [T16] |
| 14 | Warm only demonstrated first-use rendering paths when justified. **Don't** preload/render the whole world or assume a hidden node compiles every needed variant on every renderer. | Reject blanket warmup | The [menu plan](../plans/menu-redesign.md) and [lens stack](../../app/render/lens/lens_stack.gd) already own targeted preparation. More startup work and memory are not a proven improvement; retain renderer-specific measurement. | [T17] |

## Simulation and numerical development

| # | Practice and what not to do | Decision | OpenRC fit and document home | Sources |
| --- | --- | --- | --- | --- |
| 15 | Establish supported event-surface behavior and test relevant fast, multiple and grazing crossings. **Don't** infer that matching sampled signs exclude an intervening event. | Apply | [Resource-event tests](../../app/tests/test_resource_event_step.gd) explicitly retain a multiple-root sampling limit after current-main's repair. Add a conditional [numerical check](../tools/physics.md#numerical-change-checks); this is not evidence of a stock-flight defect. | [T18], [T19] |
| 16 | For parallel physics, specify reduction/event order independently of worker completion. **Don't** confuse race prevention with deterministic arithmetic or event ordering. | Apply | [Simulation](../../app/sim/simulation.gd) and [event tests](../../app/tests/test_sf_event_protocol.gd) own accepted state/events. Require relevant worker-count comparisons when parallelization is proposed, in [numerical checks](../tools/physics.md#numerical-change-checks). Box2D's implementation is an example, not a replacement kernel. | [T20] |
| 17 | Preserve physical RNG state, algorithm/runtime identity and draw schedule. **Don't** treat a seed as a mid-sequence checkpoint or a cross-version promise. | Apply | [Wind turbulence](../../app/physics/wind_turbulence.gd), [spatial configuration](../../app/physics/wind_spatial_config.gd) and the [wind reference](../WIND-ATMOSPHERE-REFERENCE.md) already provide examples. Generalize the future-law check in [numerical checks](../tools/physics.md#numerical-change-checks), without duplicating wind's formats. | [T21] |
| 18 | Associate effective inputs/interventions with accepted ticks and a defined order. **Don't** treat a frame-dispatched debug command as an exact replay tape or consult live devices during replay. | Apply | [FlightSession](../../app/sim/flight_session.gd) and [flight logging](../FLIGHT-LOGGING.md) already define the routes. Add conditional zero/one/multiple-ticks-per-frame checks for changed input boundaries. Those test cases are an OpenRC inference from its scheduling model. | [T22] |
| 19 | Compare numerically sensitive changes through a controlled refinement series at common simulated times. **Don't** infer fourth-order behavior for an entire hybrid/contact split from its RK4 component. | Apply | Existing [integrator tests](../../app/tests/test_integrator.gd), [event refinement](../../app/tests/test_sf_event_refinement.gd) and [GP-11 evidence](ground-physics/GP-11/README.md) justify a concise selection rule in [numerical checks](../tools/physics.md#numerical-change-checks). Production 240 Hz is not changed. | [T23], [T36] |
| 20 | Use independent analytic, conservation or symmetry expectations where applicable. **Don't** reproduce the implementation as its own oracle or demand conservation despite external work/dissipation. | Apply | [Integrator](../../app/tests/test_integrator.gd) and [law-property tests](../../app/tests/test_sf_law_properties.gd) are existing examples. Add the assumptions and oracle-selection criterion to [numerical checks](../tools/physics.md#numerical-change-checks). | [T24] |
| 21 | Scope exact equivalence to identified state, inputs, engine, backend and configuration. **Don't** treat fixed frequency alone as proof of determinism or say every intentional physics change must fail a golden. | Apply | Correct [debugging](../tools/debugging.md#1-reproduce) and [physics diagnosis](../tools/debugging-physics.md): the synchronous golden test does not exercise render cadence or isolate the cause of a mismatch. [Flight logging](../FLIGHT-LOGGING.md) already owns the exact replay contract. | [T20], [T22] |
| 22 | State frames, origins, units and signs at physical boundaries. **Don't** import another simulator's values just because axis names look similar. | Retain | [Aircraft conventions](../AIRCRAFT_CONTRACT.md), [render conversion](../../app/render/frames.gd) and [math tests](../../app/tests/test_math3d.gd) already own OpenRC's structural/FRD/NED boundaries. JSBSim illustrates the distinction, not OpenRC's datum. | [T26] |
| 23 | Separate cold behavior from steady state and use repeated controlled comparisons. **Don't** call best-of-three or percentiles of batch means whole-frame tail latency. | Retain | [Performance protocol](../../research/performance/README.md), [probe limitations](../tools/physics.md#benches-and-probes) and [GOD TEST](../plans/god-test.md) already distinguish these measurements. LLVM's machine-tuning suggestions are not adopted wholesale. | [T27] |
| 24 | Keep observers bounded and evaluate their cost with matched controls. **Don't** let recording alter physics or subtract noisy overhead from individual samples as exact truth. | Retain | [Flight logging](../FLIGHT-LOGGING.md) and the [performance protocol](../../research/performance/README.md) own observational state, buffering and paired measurement. LLVM supports caution about bias; the project's protocol is the direct procedural authority. | [T27] |
| 25 | Separate software verification, physical validation, pilot acceptance and hardware qualification. **Don't** equate stable or exact output with realistic flight. | Retain | Root [AGENTS](../../AGENTS.md#simulation-and-verification), [LEARNINGS](../LEARNINGS.md#prove-what-the-airplane-actually-does) and owning acceptance gates already make the distinction. No extra startup rule is needed. | [T28] |

## Agent instruction files and workflow

| # | Practice and what not to do | Decision | OpenRC fit and document home | Sources |
| --- | --- | --- | --- | --- |
| 26 | Inspect startup Claude instruction files separately from on-demand scoped rules. **Don't** present `/memory` as a complete effective-context or compliance check. | Apply | Correct [CLAUDE](../../CLAUDE.md) and [SUBAGENTS](../SUBAGENTS.md#claude-code): `/context all` for launch memory files, explicit nested-rule reads, and the version-dependent documented `/memory` check for directly loaded AGENTS. No live-client verification is claimed. | [T29], [T33] |
| 27 | When discovery is uncertain, inspect root, overrides, configured budget and client records. **Don't** diagnose missing instructions solely from the model's recollection. | Apply | Add a conditional diagnostic sentence to [instruction maintenance](../README.md#agent-instruction-files). Upstream reports distinguish a wrong effective root from instructions present but not followed; neither establishes current prevalence here. | [T30], [T34], [T37] |
| 28 | Treat Codex's default 32 KiB as a combined project-chain budget. **Don't** treat it as a per-file allowance or enlarge it without a need. | Retain | The [earlier audit](agent-orchestration-2026-11-15.md#instruction-file-audit--2026-11-19) already records the configurable limit. This review does not claim to measure every instruction loaded in the user's clients. | [T30], [T35] |
| 29 | Keep one shared rule source and a real `@AGENTS.md` import. **Don't** replace it with a Markdown link or assume new native support makes the adapter redundant. | Retain | [CLAUDE](../../CLAUDE.md) remains a short adapter; project CLAUDE files can change native AGENTS defaults. This also avoids Windows symlink portability concerns. | [T29], [T33] |
| 30 | Route domain details by task and scope. **Don't** import every guide, role catalog or historical result into startup context. | Retain | [AGENTS](../../AGENTS.md#start-here), scoped rules and the [document responsibility map](../README.md#agent-instruction-files) already provide progressive reading. New technical details stay in their owning guides. | [T29], [T31] |
| 31 | Admit instructions for a concrete gap; state trigger, action and check. **Don't** add vague “be thorough” language, duplicate rules or universalize a version-specific workaround. | Apply | Add the selection criterion to [instruction maintenance](../README.md#agent-instruction-files). The detailed rationale remains in this dated review. | [T29], [T31] |
| 32 | Use actual permissions, checks and CI for enforceable boundaries. **Don't** describe prompt wording, a role title or an omitted tool as whole-process isolation. | Retain | [SUBAGENTS](../SUBAGENTS.md#lead-agent-and-delegation-rules) already separates guidance from permissions and warns about hooks outside tool allowlists. Existing controls are retained; none are added or weakened. | [T32] |
| 33 | Require evidence from the integrated candidate and independently review material claims. **Don't** accept an unscoped “tests passed” or a helper's self-description as runtime proof. | Retain | [Handoff templates](../SUBAGENTS.md#dispatch-and-return-templates) and [verification scope](../tools/shared.md#verification-scope) already specify identities, commands, results and pending evidence. | [T32] |
| 34 | Add workflow machinery only for an unmet need. **Don't** import giant community templates, require a new hook/skill framework or mandate full-repository reading for every task. | Reject blanket package | Existing [instruction conventions](../README.md#agent-instruction-files) and the four OpenRC tool wrappers already have owners. This review found no reason to install or bulk-copy another system. | [T29], [T31] |

## What changed and what stayed conditional

The root `AGENTS.md` gains a task-routing row and preserves main's requirement for verification evidence in commit messages. `CLAUDE.md` keeps its shared import and short adapter structure. The new Godot ownership/lifecycle guidance lives in `STACK`; numerical checks live in the existing physics-tool guide, with pointers from the physics and simulation scoped instructions. Graphics and physics playbooks receive bounded wording corrections. Instruction maintenance and Claude discovery diagnostics stay with their existing owners.

The numerical checklist applies when its corresponding behavior changes. It does not mandate extra tests for every edit, change the production tick, relax replay identity, introduce a solver, or turn an old issue report into a current defect. The native backend, render/display targets, shared-host admission, generated-source and required CI contracts remain in place.

Additional rejected applications are recorded within the rows' don'ts: replacing the float64 kernel with Godot rigid-body nodes; changing tick rate to make performance numbers look better; treating all engine APIs as thread-safe; inferring physical fidelity from goldens; and enabling a separate render thread merely because someone else reported a speedup. Those require their own owner, source-specific evidence and acceptance work, not a documentation tip.

## Primary sources and limitations

| IDs | Primary material | What it contributes and what it does not prove |
| --- | --- | --- |
| T01–T05 | Godot 4.6–4.7 clock/interpolation references and discontinuity guidance; Glenn Fiedler's 2004 timestep article | Clock, catch-up and interpolation mechanisms. OpenRC's custom arrays and accepted-state boundary are checked in its source. |
| T06–T09 | Godot 4.7 thread/resource-loading and 4.5 resource references | API ownership, blocking and sharing semantics. They do not establish the pinned engine's performance or justify an untested workaround. |
| T10–T17 | Godot profiler, optimization, type, node, input, import/export and stutter references | Engine-boundary traps and diagnostic scope. Older versioned docs are not a certification of 4.8-beta2 behavior. |
| T18–T19 | SciPy 1.15.2 and SUNDIALS 6.6.1 numerical documentation | General limits of sampled/sign-change event detection. Neither implements OpenRC's event policy or proves a flight defect here. |
| T20–T22 | Erin Catto, Box2D determinism (27 August 2024); Godot RNG; Fiedler lockstep (29 November 2014) | Reproducible ordering, random state and frame-associated input. No Box2D or networking architecture is adopted. |
| T23–T24, T36 | NASA temporal-convergence and verification tutorials; a 2016 NASA numerical integration paper, §2.19 | Controlled refinement, RK discontinuity considerations and independent expectations. Existing OpenRC hybrid tests/evidence define the local application. |
| T25 | [Godot #120661][T25] and [linked fix discussion](https://github.com/godotengine/godot/pull/121025) | Firsthand loader reports include an October 2026 report on 4.7.2 and differing reports on other versions. They do not establish that 4.8-beta2 has the same defect. |
| T26–T28 | JSBSim's reference manual, LLVM 19.1 benchmark guidance and NASA modeling/simulation guidance | Frame distinctions, measurement bias and verification/validation. Local formats and hardware protocols remain authoritative. |
| T29–T32 | Current official Anthropic/OpenAI documentation; OpenAI's 11 September 2026 instruction review | Supported discovery/configuration and disciplined instruction selection. No live-client loading or productivity benchmark was performed here. |
| T33–T35, T37 | Claude [#108279][T33] (8 November 2026); Codex [root/discovery][T34] and [compliance][T37] reports; Codex [#36371][T35] (31 July 2026) | Firsthand compatibility and documentation problems to corroborate. Issue closure, votes and model recollection do not prove a fix or compliance. |

## Verification and remaining limits

Completed checks covered **1,590 local links/anchors across 25 Markdown files**, including every changed document and all seven scoped instruction files. The explicit `@AGENTS.md` import resolves. No live inbound reference targets the six headings removed by the earlier audit. All 26 specialist definitions and seven helper/configuration files remain byte-identical. The selection table contains exactly 34 consecutive items with the stated 14/16/3/1 disposition and 37 defined primary-source references.

Source review and independent candidate review resolved the incorrect interpolation function/caller attribution, overbroad golden-test and fixed-clock claims, missing source references and an accidental weakening of where golden explanations must be recorded. Main's commit-message evidence requirement is preserved. `git diff --check` passed; the branch's delta from the inspected main contains only Markdown and the earlier `.gitignore` change. These are documentation checks, not runtime acceptance.

No engine process, physics/performance campaign or live Claude/Codex instruction-discovery session was run for this prose change. Existing required CI and physical/native acceptance gates remain unchanged and unclaimed here.

[T01]: https://gafferongames.com/post/fix_your_timestep/
[T02]: https://docs.godotengine.org/en/4.7/classes/class_engine.html
[T03]: https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html
[T04]: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/advanced_physics_interpolation.html
[T05]: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/using_physics_interpolation.html
[T06]: https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html
[T07]: https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html
[T08]: https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html
[T09]: https://docs.godotengine.org/en/4.5/classes/class_resource.html
[T10]: https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html
[T11]: https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html
[T12]: https://docs.godotengine.org/en/4.5/tutorials/scripting/gdscript/static_typing.html
[T13]: https://docs.godotengine.org/en/4.4/classes/class_node.html
[T14]: https://docs.godotengine.org/en/4.5/classes/class_input.html
[T15]: https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html
[T16]: https://docs.godotengine.org/en/4.6/classes/class_fileaccess.html
[T17]: https://docs.godotengine.org/en/4.5/tutorials/rendering/jitter_stutter.html
[T18]: https://docs.scipy.org/doc/scipy-1.15.2/reference/generated/scipy.integrate.solve_ivp.html
[T19]: https://sundials.readthedocs.io/en/v6.6.1/arkode/Mathematics_link.html
[T20]: https://box2d.org/posts/2024/08/determinism/
[T21]: https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html
[T22]: https://gafferongames.com/post/deterministic_lockstep/
[T23]: https://www.grc.nasa.gov/WWW/wind/valid/tutorial/tempconv.html
[T24]: https://www.grc.nasa.gov/www/wind/valid/tutorial/verassess.html
[T25]: https://github.com/godotengine/godot/issues/120661
[T26]: https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/
[T27]: https://releases.llvm.org/19.1.0/docs/Benchmarking.html
[T28]: https://public.ksc.nasa.gov/mns/faq/
[T29]: https://code.claude.com/docs/en/memory
[T30]: https://learn.chatgpt.com/docs/agent-configuration/agents-md
[T31]: https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra
[T32]: https://code.claude.com/docs/en/best-practices
[T33]: https://github.com/anthropics/claude-code/issues/108279
[T34]: https://github.com/openai/codex/issues/25651
[T35]: https://github.com/openai/codex/issues/36371
[T36]: https://ntrs.nasa.gov/api/citations/20160005923/downloads/20160005923.pdf
[T37]: https://github.com/openai/codex/issues/34189
