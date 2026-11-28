# Product vision and conditional proposals

Scope: long-term product choices and the evidence that would justify them. These are **proposals**, not a delivery schedule or a list of shipped features. The [current roadmap](ROADMAP.md) owns priority and status; [architecture](docs/STACK.md) owns implemented boundaries. The original [28 October assessment](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/MOONSHOT.md) preserves its dated baseline, provisional numerical scorecard and twelve-month scenario in Git history.

## The destination

Help a pilot bring their transmitter, aircraft setup and local field into a repeatable practice loop: fly, inspect a particular moment, understand the evidence and try again. Connect measured aircraft, inspectable flight records, useful instruction and an open creator community. More aircraft or a different renderer alone would not deliver that experience.

Keep free flight immediately available. Pursue credible behavior and a useful short session together. Independent measurements, learner studies, rights clearance and native-platform testing remain real dependencies even when development resources increase. Claims about realism, teaching, performance and accessibility require separate evidence.

## Eight proposals and their decision gates

### T1 — Calibrated aircraft configurations

Fit one identified installation from measured mass/CG/inertia, actuator timing, installed thrust/RPM and aligned flight observations. Use the existing reducers and generated v2 contract; retain interpretable physics, parameter uncertainty and the supported operating envelope. Reserve complete sorties before fitting so calibration cannot consume its validation data.

The research proposed starting in attached flow, comparing simpler fits, then expanding to three configurations. Its candidate metric was the equally weighted mean of per-sortie normalized RMSE for body rates and true airspeed, with a normalization floor of three times sensor uncertainty. Alignment, windows, filtering and nuisance parameters must be frozen before held-out evaluation. The suggested 30% aggregate improvement and at most 10% channel regression require independently chosen absolute tolerances; do not claim a percentage win below the measurement floor. Keep failed sorties and pilot preference separate from predictive accuracy. Sparse video cannot uniquely identify wind, delay, servo and aero errors. Learned residuals remain bounded offline research, refused outside measured support.

### T2 — Replay-backed instruction

Build from exact replay and factual marker windows, then instructor annotations, isolated checkpoint branches and qualified assistance. Every reported number must resolve to source identity, tick and units. An unchanged branch must reproduce its reference before a control intervention is allowed; changed branches are explicitly identified model predictions. They cannot prove a real accident's cause or the response a real aircraft would have made.

The first useful comparison is a conventional controller and expert reference. A learned policy needs held-out configurations/seeds, refusal cases and an inference budget before assistance is considered. Teaching claims need a preregistered study with an active control, blinded assessment and delayed retention. The original example was a 20% reduction in next-day approach-path error, with completion/abort guards; instructors must select a meaningful outcome, estimate variance/sample size and report uncertainty and attrition before recruiting. Simulator improvement alone does not establish transfer to real RC flight. An LLM may explain validated facts; it must not enter RK stages.

### T3 — Responsive execution

Preserve the shared simulation transaction and invest in attributed complete-session costs, bounded preparation and accepted observations. Existing qualified native execution is part of that architecture. Additional worker threads, standalone simulation services and cadence changes require explicit state ownership, bounded queues, cancellation/reset/restore checks and physical control-latency measurements. Synchronization, retained memory and stale input can erase a local speedup.

Use the [current performance acceptance contract](docs/plans/global-performance-visual-quality.md) and [native qualification](docs/plans/native-kernel-roadmap.md). Do not use the old vision's provisional frame/loading targets as a second release gate. Engine alternatives require the live comparison below.

### T4 — Coherent field weather

Extend the existing position/time wind queries only with bounded, source-grounded models. Offline flow studies can inform reduced fields; interpolation, gradients, seed/state identity and validity limits remain explicit. Smoke, flags, trees and sound should read coherent conditions without allowing appearance to alter aerodynamic truth.

Before a field-flow claim, measure mean, variance, spectra and spatial correlation at surveyed locations/heights, with uncertainty, across two different terrain/obstacle settings. Check continuity/replay and complete-callback costs. A live weather feed is not a measurement of instantaneous club-field turbulence; interactive full CFD and invented obstacle effects remain outside the release path. [Wind reference](docs/WIND-ATMOSPHERE-REFERENCE.md)

### T5 — Asynchronous challenges and small clubs

Try versioned challenge packs and compatible replay ghosts before maintaining public live services. Share the resolved scenario/content digest, not a seed alone. A casual room may exchange bounded tick-stamped remote presentation while keeping the local pilot authoritative; full local dynamics for every remote aircraft and cross-machine deterministic lockstep are not assumed.

The original room proposal was eight pilots plus spectators under 150 ms RTT, 30 ms jitter and 2% loss, with late joins, hostile packets, disconnects and bounded memory/CPU. Those are a future experiment specification, not a supported capability. Initially exclude inter-aircraft contact. Ranked results need server-owned scenarios and pinned verification or an explicit unverified label. Input sharing is opt-in. Public services need an operating owner, cost limits, abuse handling, mute/block and content withdrawal; weak social demand favors asynchronous activities.

### T6 — Verifiable creator packs

Build data-only packs on the existing Workshop/compiler boundaries, with source identity, dependency hashes, deterministic recipes, declared capabilities, licenses and validation results. Ordinary packs must not execute imported code or load arbitrary paths/native libraries. Reuse licensed source assets and established Blender/glTF tools; free download is not permission to redistribute.

A useful gate is two outside creators producing compatible packs without core code changes, plus clean-checkout rebuilds and malformed/oversized/path-traversal refusal. An imported field needs surveyed scale/contact landmarks and target-host performance. Photogrammetry, generated images and neural backgrounds do not establish trustworthy collision geometry or aerodynamic data. Original source media can remain outside Git with acquisition instructions and hashes. [Aircraft authoring](docs/AIRCRAFT_CONTRACT.md) · [rights](docs/AIRCRAFT-LICENSING.md)

### T7 — A clear practice loop

Use versioned activities with eligible configurations, objectives, starts, events and completion. Keep free flight and aircraft access immediate; avoid grind, opaque difficulty adjustments and hidden changes to the flight model. Scenarios freeze their resolved inputs for sharing. Orientation, circuits, landings and emergency practice need expert interpretation and honest model limits.

The original usability proposal was at least 8/10 first-time users reaching controlled flight within ten minutes and 8/10 explaining a useful next action. Observe actual keyboard/controller and enlarged-text flows; obtain screen-reader evidence before claiming accessibility. Baseline repeat play and voluntary retries with consent before choosing retention targets. Localization, subtitles and cues that do not depend only on color remain product requirements.

### T8 — Readability before additional effects

Evaluate moving aircraft orientation at 50/100/200 m across matched sky/ground backgrounds, including temporal artifacts, camera/control latency and audible cues. Keep visual features scalable. A pleasing still image or a faster upscaler does not establish pilot readability.

Desktop acceptance precedes optional XR work. Named headsets need stereo/per-eye budgets, comfort tests, surveyed field scale and a way to use the physical transmitter. The original 90 Hz / 11.1 ms stereo target was a proposal, not a desktop extrapolation. Neural scenes and splats remain optional presentation research. [Display policy](AGENTS.md#display-resolution-priorities) · [visual qualification](docs/VISUAL-QUALITY-PLAN.md)

## Engine alternatives and stop rules

| Alternative | Rationale and cost | Evidence required before adoption |
| --- | --- | --- |
| Continue Godot with qualified native evaluators | Preserves the kernel, content, controls, tools and existing platform work; orchestration and renderer limits still need attribution. | Preferred production path under the [current architecture](docs/STACK.md). Reconsider only after bounded fixes fail a named complete-product gate. |
| Unreal presentation with OpenRC physics | Potential art/tooling benefits require a GDScript port, adapter/UI/input work, numerical verification, licensing and larger delivery cost. | A time-boxed matched field/tape playback first; then a live aircraft with real controls, accepted ticks, reset/restore and loading on the compared hosts. Playback alone cannot qualify migration or input latency. |
| Unity or a custom engine | Might offer a useful ecosystem or tighter control, while rebuilding working integrations and potentially an editor/content pipeline. | Research challenger only; no evidence currently justifies a parallel production port. |
| Engine-independent simulation service | Could serve real headless/controller/frontend consumers but adds ABI, lifetime, identity and duplicate-implementation costs. | Grow from accepted boundaries when actual consumers and measured benefit justify it. Do not replace the transaction by implication. |

Stop an engine challenger if it cannot demonstrate a decisive end-to-end advantage within its declared experiment budget. Keep serial ownership if threading fails latency/lifecycle checks. Keep factual debrief and classical models if learned controllers exploit model errors. Retain the simpler renderer if effects damage orientation or pacing. Request better measurements when identification is ill-conditioned. Defer open uploads/rankings when rights, moderation or operating cost cannot be supported. Cut speculative residual models, generated worlds and XR before radio usability, correctness or frame pacing.

## Replay-backed practice sequence

<a id="6-first-engineering-transformation-flight-intelligence-from-verified-flight-records"></a>

The original proposal selected T2 first because existing flight records could support a useful player experiment without an engine migration, trained model or new assets. [FL-05](docs/research/flight-logging/FL-05/README.md) delivered offline debrief infrastructure. Its [commands and marker semantics](docs/FLIGHT-LOGGING.md#debrief-marked-maneuvers) are authoritative; an offline report does not implement the player loop.

The remaining dependency sequence is factual debrief in the existing shell → understandable practice/retry → isolated compatible checkpoint branching → instructor-reviewed tasks → separately qualified shadow/active assistance. Required proofs include parser/identity/timeout handling, actual UI/accessibility and novice comprehension; unchanged-branch exactness, no statistics credit and fault/reset isolation; bounded task interpretations and held-out pilot cases. A training adapter is justified by real consumers, not by a speculative framework choice. Current scheduling belongs to [ROADMAP](ROADMAP.md).

## Research basis

The dated [engine/world](docs/research/moonshot/engine-world-2026-10-28.md), [physics/AI](docs/research/moonshot/physics-ai-2026-10-28.md) and [product/platform](docs/research/moonshot/product-platform-2026-10-28.md) investigations retain primary sources and alternatives. Their historic feature counts, version pins and market comparisons are not current implementation claims. Use existing verification, plotting, content and networking tools before creating another framework; pin versions and rights only when a dependency is adopted.
