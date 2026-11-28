# Decisions

Find the reason behind a consequential choice, then read its linked contract and evidence. Each subject has one decision record. Decisions retain their stated scope and date; they do not certify current implementation, physical validity or performance. Start at the [master documentation index](README.md) for other tasks, [architecture](STACK.md) for current boundaries, and the [roadmap](../ROADMAP.md) for priorities.

## Product and platform

<a id="native-desktop-godot-with-an-explicit-engine-pin"></a>

- [Native desktop Godot, with an explicit engine pin](decisions/platform.md#native-desktop-godot-with-an-explicit-engine-pin).

<a id="aircraft-first-broader-vehicles-share-the-foundation"></a>

- [Aircraft first; broader vehicles share the foundation](decisions/platform.md#aircraft-first-broader-vehicles-share-the-foundation).

<a id="separate-software-preservation-from-product-acceptance"></a>

- [Separate software preservation from product acceptance](decisions/platform.md#separate-software-preservation-from-product-acceptance).

## Simulation authority

<a id="one-float64-kernel-vehicle-owned-laws"></a>

- [One float64 kernel, vehicle-owned laws](decisions/simulation-transactions.md#one-float64-kernel-vehicle-owned-laws).

<a id="native-acceleration-keeps-the-reference-as-its-specification"></a>

- [Native acceleration keeps the reference as its specification](decisions/native-execution.md#native-acceleration-keeps-the-reference-as-its-specification).

<a id="preserve-each-event-laws-valid-continuation"></a>

- [Preserve each event law's valid continuation](decisions/simulation-transactions.md#preserve-each-event-laws-valid-continuation).

<a id="closed-loop-control-samples-the-accepted-frame-through-an-opt-in-protocol"></a>

- [Closed-loop control samples the accepted frame through an opt-in protocol](decisions/simulation-transactions.md#closed-loop-control-samples-the-accepted-frame-through-an-opt-in-protocol).

<a id="publish-session-changes-only-after-physical-acceptance"></a>

- [Publish session changes only after physical acceptance](decisions/simulation-transactions.md#publish-session-changes-only-after-physical-acceptance).

<a id="replay-binds-complete-state-and-execution-identity"></a>

- [Replay binds complete state and execution identity](decisions/simulation-transactions.md#replay-binds-complete-state-and-execution-identity).

## Physical models

<a id="extend-aerodynamic-regimes-without-hiding-missing-physics"></a>

- [Extend aerodynamic regimes without hiding missing physics](decisions/physical-models.md#extend-aerodynamic-regimes-without-hiding-missing-physics).

<a id="share-mechanics-while-keeping-propulsion-sources-distinct"></a>

- [Share mechanics while keeping propulsion sources distinct](decisions/physical-models.md#share-mechanics-while-keeping-propulsion-sources-distinct).

<a id="keep-finite-resources-and-mass-properties-physically-coherent"></a>

- [Keep finite resources and mass properties physically coherent](decisions/physical-models.md#keep-finite-resources-and-mass-properties-physically-coherent).

<a id="version-physical-weather-separately-from-visual-atmosphere"></a>

- [Version physical weather separately from visual atmosphere](decisions/physical-models.md#version-physical-weather-separately-from-visual-atmosphere).

<a id="ground-support-follows-authored-geometry-and-actual-surfaces"></a>

- [Ground support follows authored geometry and actual surfaces](decisions/physical-models.md#ground-support-follows-authored-geometry-and-actual-surfaces).

<a id="helicopter-terrain-follows-the-accepted-scene-context"></a>

- [Helicopter terrain follows the accepted scene context](decisions/physical-models.md#helicopter-terrain-follows-the-accepted-scene-context).

<a id="the-rc-circuit-is-terrain-under-aircraft-never-decoration"></a>

- [The RC circuit is terrain under aircraft, never decoration](decisions/physical-models.md#the-rc-circuit-is-terrain-under-aircraft-never-decoration).

<a id="the-workshop-admits-the-blimp-as-a-second-family-through-format-dispatch"></a>

- [The Workshop admits the blimp as a second family through format dispatch](decisions/aircraft-authoring.md#the-workshop-admits-the-blimp-as-a-second-family-through-format-dispatch).

<a id="the-rc-blimp-owns-a-coupled-added-mass-law-with-a-declared-afterbody-loss"></a>

- [The RC blimp owns a coupled added-mass law with a declared afterbody loss](decisions/airship-dynamics.md#the-rc-blimp-owns-a-coupled-added-mass-law-with-a-declared-afterbody-loss).

<a id="the-first-quad-law-is-transparent-and-its-continuations-are-declared"></a>

- [The first quad law is transparent, and its continuations are declared](decisions/quad-dynamics.md#the-first-quad-law-is-transparent-and-its-continuations-are-declared).

<a id="advanced-contact-and-structural-failure-remain-gated-foundations"></a>

- [Advanced contact and structural failure remain gated foundations](decisions/physical-models.md#advanced-contact-and-structural-failure-remain-gated-foundations).

## Authoring and identity

<a id="strict-aircraft-data-and-reusable-capability-admission"></a>

- [Strict aircraft data and reusable capability admission](decisions/aircraft-authoring.md#strict-aircraft-data-and-reusable-capability-admission).

<a id="stock-selection-does-not-redefine-technical-aircraft-identity"></a>

- [Stock selection does not redefine technical aircraft identity](decisions/aircraft-authoring.md#stock-selection-does-not-redefine-technical-aircraft-identity).

<a id="home-lists-every-vehicle-the-aircraft-catalog-stays-aircraft-only"></a>

- [Home lists every vehicle; the aircraft catalog stays aircraft-only](decisions/aircraft-authoring.md#home-lists-every-vehicle-the-aircraft-catalog-stays-aircraft-only).

<a id="declarative-imported-models-retain-authored-identity"></a>

- [Declarative imported models retain authored identity](decisions/aircraft-authoring.md#declarative-imported-models-retain-authored-identity).

<a id="one-workshop-pipeline-separate-physical-and-appearance-builds"></a>

- [One Workshop pipeline; separate physical and appearance builds](decisions/aircraft-authoring.md#one-workshop-pipeline-separate-physical-and-appearance-builds).

<a id="aircraft-creator-imports-a-model-but-never-its-physics"></a>

- [Aircraft Creator imports a model but never its physics](decisions/aircraft-imports.md#aircraft-creator-imports-a-model-but-never-its-physics).

<a id="flight-simulator-import-performs-conversion-inside-the-application"></a>

- [Flight Simulator import performs conversion inside the application](decisions/aircraft-imports.md#flight-simulator-import-performs-conversion-inside-the-application).

<a id="reuse-source-assets-without-erasing-their-terms"></a>

- [Reuse source assets without erasing their terms](decisions/aircraft-authoring.md#reuse-source-assets-without-erasing-their-terms).

## Flight sessions and observation

<a id="launch-from-a-supported-physical-initial-condition"></a>

- [Launch from a supported physical initial condition](decisions/flight-sessions.md#launch-from-a-supported-physical-initial-condition).

<a id="distinguish-device-ownership-input-shaping-and-aircraft-mechanics"></a>

- [Distinguish device ownership, input shaping and aircraft mechanics](decisions/flight-sessions.md#distinguish-device-ownership-input-shaping-and-aircraft-mechanics).

<a id="rigging-offsets-and-loaded-servos-are-different-models"></a>

- [Rigging offsets and loaded servos are different models](decisions/flight-sessions.md#rigging-offsets-and-loaded-servos-are-different-models).

<a id="resolve-random-scenarios-and-failures-before-advancing-physics"></a>

- [Resolve random scenarios and failures before advancing physics](decisions/flight-sessions.md#resolve-random-scenarios-and-failures-before-advancing-physics).

<a id="race-state-commits-with-the-physics-tick"></a>

- [Race state commits with the physics tick](decisions/fpv-racing.md#race-state-commits-with-the-physics-tick).

<a id="race-gates-are-drawn-as-their-collision-panels"></a>

- [Race gates are drawn as their collision panels](decisions/fpv-racing.md#race-gates-are-drawn-as-their-collision-panels).

<a id="race-records-are-local-per-course-identity-with-geometry-derived-medals"></a>

- [Race records are local, per course identity, with geometry-derived medals](decisions/fpv-racing.md#race-records-are-local-per-course-identity-with-geometry-derived-medals).

<a id="fpv-audit-repairs-fix-the-quads-control-energy-scoring-and-result-contracts"></a>

- [FPV audit repairs fix the quad's control, energy, scoring and result contracts](decisions/fpv-racing.md#fpv-audit-repairs-fix-the-quads-control-energy-scoring-and-result-contracts).

<a id="quad-crashes-are-graded-and-controllers-arrive-preconfigured"></a>

- [Quad crashes are graded and controllers arrive preconfigured](decisions/fpv-racing.md#quad-crashes-are-graded-and-controllers-arrive-preconfigured).

<a id="reuse-flight-logs-for-factual-analysis"></a>

- [Reuse flight logs for factual analysis](decisions/flight-sessions.md#reuse-flight-logs-for-factual-analysis).

<a id="companions-need-their-own-admission-scheduling-and-replay-proof"></a>

- [Companions need their own admission, scheduling and replay proof](decisions/flight-sessions.md#companions-need-their-own-admission-scheduling-and-replay-proof).

<a id="separate-damage-evidence-repair-assessment-and-prices"></a>

- [Separate damage evidence, repair assessment and prices](decisions/flight-sessions.md#separate-damage-evidence-repair-assessment-and-prices).

## Presentation

<a id="graphics-calibration-is-evidence-restore-is-a-transaction"></a>

- [Graphics calibration is evidence; Restore is a transaction](decisions/presentation.md#graphics-calibration-is-evidence-restore-is-a-transaction).

<a id="compatibility-baseline-and-a-windows-nvidia-package"></a>

- [Compatibility baseline and a Windows NVIDIA package](decisions/presentation.md#compatibility-baseline-and-a-windows-nvidia-package).

<a id="compatibility-is-a-frozen-legacy-renderer"></a>

- [Compatibility is a frozen legacy renderer](decisions/presentation.md#compatibility-is-a-frozen-legacy-renderer).

<a id="apple-features-follow-verified-engine-boundaries"></a>

- [Apple features follow verified engine boundaries](decisions/presentation.md#apple-features-follow-verified-engine-boundaries).

<a id="scene-detail-and-birds"></a>

- [Scene detail and birds](decisions/presentation.md#scene-detail-and-birds).

<a id="share-landscape-identity-and-reuse-static-scenery"></a>

- [Share landscape identity and reuse static scenery](decisions/presentation.md#share-landscape-identity-and-reuse-static-scenery).

<a id="one-read-only-camera-rig-with-a-ground-pilot-reference"></a>

- [One read-only camera rig, with a ground-pilot reference](decisions/presentation.md#one-read-only-camera-rig-with-a-ground-pilot-reference).

<a id="effects-consume-accepted-observations-and-per-instance-state"></a>

- [Effects consume accepted observations and per-instance state](decisions/presentation.md#effects-consume-accepted-observations-and-per-instance-state).

<a id="audio-follows-the-installed-source-with-explicit-fallbacks"></a>

- [Audio follows the installed source, with explicit fallbacks](decisions/presentation.md#audio-follows-the-installed-source-with-explicit-fallbacks).

## Runtime and delivery

<a id="accepted-transition-identity-owns-companion-restart"></a>

- [Accepted transition identity owns companion restart](decisions/application-lifecycle.md#accepted-transition-identity-owns-companion-restart).

<a id="native-controls-own-interaction-styling-follows-a-shared-shell"></a>

- [Native controls own interaction; styling follows a shared shell](decisions/application-lifecycle.md#native-controls-own-interaction-styling-follows-a-shared-shell).

<a id="preserve-exact-weather-values-across-settings-saves"></a>

- [Preserve exact weather values across settings saves](decisions/application-lifecycle.md#preserve-exact-weather-values-across-settings-saves).

<a id="prepare-selected-work-privately-and-drain-cancellation"></a>

- [Prepare selected work privately and drain cancellation](decisions/application-lifecycle.md#prepare-selected-work-privately-and-drain-cancellation).

<a id="loading-bars-count-completed-stages-motion-only-shows-activity"></a>

- [Loading bars count completed stages; motion only shows activity](decisions/application-lifecycle.md#loading-bars-count-completed-stages-motion-only-shows-activity).

<a id="use-the-debug-bridge-and-engine-diagnostics-for-agent-work"></a>

- [Use the debug bridge and engine diagnostics for agent work](decisions/developer-workflow.md#use-the-debug-bridge-and-engine-diagnostics-for-agent-work).

<a id="preserve-stutter-evidence-before-extending-attribution"></a>

- [Preserve stutter evidence before extending attribution](decisions/stutter-diagnostics.md#preserve-stutter-evidence-before-extending-attribution).

<a id="qualify-exported-artifacts-separately-from-their-source-tree"></a>

- [Qualify exported artifacts separately from their source tree](decisions/release-qualification.md#qualify-exported-artifacts-separately-from-their-source-tree).

<a id="preserve-git-history-and-limit-future-artifact-growth"></a>

- [Preserve Git history and limit future artifact growth](decisions/developer-workflow.md#preserve-git-history-and-limit-future-artifact-growth).

<a id="keep-landscape-fabric-in-the-presentation-layer"></a>

- [Keep landscape fabric in the presentation layer](decisions/presentation.md#keep-landscape-fabric-in-the-presentation-layer).

<a id="keep-host-admission-outside-worktrees-and-retain-uncertain-claims"></a>

- [Keep host admission outside worktrees and retain uncertain claims](decisions/host-admission.md#keep-host-admission-outside-worktrees-and-retain-uncertain-claims).

<a id="keep-a-senior-lead-with-bounded-evidence-producing-helpers"></a>

- [Keep a senior lead with bounded, evidence-producing helpers](decisions/developer-workflow.md#keep-a-senior-lead-with-bounded-evidence-producing-helpers).

<a id="one-shared-agent-rule-source-with-task-specific-detail"></a>

- [One shared agent rule source, with task-specific detail](decisions/developer-workflow.md#one-shared-agent-rule-source-with-task-specific-detail).

<a id="adapt-clearview-visuals-upstream-of-creator-admission"></a>

- [Adapt ClearView visuals upstream of Creator admission](decisions/aircraft-imports.md#adapt-clearview-visuals-upstream-of-creator-admission).

<a id="ac-cv-v1-parity"></a>

- [AC-CV v1 parity](decisions/aircraft-imports.md#ac-cv-v1-parity).

<a id="phoenix-aeroplanes-join-the-declared-estimated-configuration-route"></a>

- [Phoenix aeroplanes join the declared estimated-configuration route](decisions/aircraft-imports.md#phoenix-aeroplanes-join-the-declared-estimated-configuration-route).

<a id="phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data"></a>

- [Phoenix aeroplanes fly on packages derived from their own data](decisions/aircraft-imports.md#phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data).

<a id="creator-fixed-landing-gear"></a>

- [Creator fixed landing gear](decisions/aircraft-authoring.md#creator-fixed-landing-gear).

<a id="creator-directional-terms-follow-the-stik-study"></a>

- [Creator directional terms follow the Stik study](decisions/aircraft-authoring.md#creator-directional-terms-follow-the-stik-study).

<a id="one-owner-and-one-strength-for-direct-shadows"></a>

- [One owner and one strength for direct shadows](decisions/presentation.md#one-owner-and-one-strength-for-direct-shadows).

## Maintaining this record

- Add an entry only for a consequential choice with a credible alternative or a non-obvious constraint. State the choice, reason, scope, owning step ID and canonical evidence. Include a concrete revisit condition when it is not already owned by the linked plan.
- Update the existing topic when a decision changes. Keep a short supersession note only when it prevents a likely mistake; dated reports and Git history retain the full reasoning. Do not append another chronological table or archive.
- Keep parameters, commands, feature inventories, benchmarks, pass counts and next actions in their authoritative homes. A local optimization or bug fix usually belongs in evidence or [LEARNINGS](LEARNINGS.md), not here.
- Label approved-but-unimplemented designs and experimental admissions explicitly. Check current contracts and consumers before turning an old status into a present-tense claim.
- Preserve valuable source/evidence records, verify links and heading targets, and update incoming links when consolidating an entry. New proposals and unresolved choices belong with their owner in the [track registry](TRACKS.md).

## Further decisions

<a id="default-to-native-physics-on-supported-apple-silicon-flights"></a>

- [Default to native physics on supported Apple Silicon flights](decisions/native-execution.md#default-to-native-physics-on-supported-apple-silicon-flights).

<a id="transparent-telemetry-as-a-separate-product-data-boundary"></a>

- [Transparent telemetry as a separate product data boundary](decisions/telemetry.md#transparent-telemetry-as-a-separate-product-data-boundary).

<a id="telemetry-schema-v2-reports-the-physics-backend"></a>

- [Telemetry schema v2 reports the physics backend](decisions/telemetry.md#telemetry-schema-v2-reports-the-physics-backend).

<a id="start-graphics-from-the-active-gpu-and-keep-manual-choices"></a>

- [Start graphics from the active GPU and keep manual choices](decisions/presentation.md#start-graphics-from-the-active-gpu-and-keep-manual-choices).

<a id="v2--bind-the-shooting-package-to-one-explicit-revision"></a>

- [V2 — Bind the shooting package to one explicit revision](decisions/trailer-production.md#v2--bind-the-shooting-package-to-one-explicit-revision).

<a id="the-accident-ledger-samples-gear-support-once-per-frame"></a>

- [The accident ledger samples gear support once per frame](decisions/flight-sessions.md#the-accident-ledger-samples-gear-support-once-per-frame).

<a id="a-native-flight-freezes-its-guarded-configuration"></a>

- [A native flight freezes its guarded configuration](decisions/native-execution.md#a-native-flight-freezes-its-guarded-configuration).
