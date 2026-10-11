# Aircraft standardization plan

**Status: AS-00–03 complete; AS-04/05 verification and delivery in progress, 2026-10-11.** Revision 2. The complete initial plan preceded code changes. Owner: aircraft standardization lead, physics line. Prefix: AS-. This root location is requested by the project owner.

## Objective and scope

Standardize the four catalog aircraft and the existing electric test configurations before adding aircraft features. Deliver a versioned, fail-closed aircraft contract, matching Godot validation and offline schema, migrated source pipelines, an authoring template, an audit comparison, and repeatable in-engine proof. Keep valid aircraft differences and established numerical behavior. Software verification does not certify physical accuracy: independent mass, inertia, propeller, ground and flight measurements remain separate gates.

Audit every boundary: catalog and data identity; generated geometry and datum transforms; mass inventory, CG and inertia; reference quantities and aerodynamic derivatives; local wing/tail and stall models; controls and servo limits; propulsion and energy; ground contacts and field surfaces; crash hull and damage presentation; trim/start, pause, reset, reload, checkpoints; model animation, camera, HUD, audio and traces. Authored inputs, load-time derivations and evolving state must have distinct ownership.

## AS-00 findings and technical basis

The installed engine reports `4.7.2.stable.official.ed1daf0bf`. Production uses GDScript scalar doubles and packed float64 arrays, a 13-value rigid-body state and 240 Hz integration. Godot rigid-body nodes are not the flight solver. Existing `physics/aircraft_data.gd` already validates quantities and many coupled physical relationships; `data/schema/openrc-aircraft-v1.schema.json` is an extensive offline structural schema. Reuse these foundations.

The knowledge graph identified the catalog, loader, session and their consumers. Its stored snippet line ranges can lag the working tree; inspect the current files before integration. Bounded Luna/max audits cover configuration, lifecycle and physics/generators; their reports live in [AS-00 evidence](docs/research/aircraft-standardization/AS-00/).

| Finding | Required resolution |
| --- | --- |
| Legacy v1 permits ignored/unknown fields and uneven null/empty semantics | Strict new version; retain explicitly named v1 compatibility for historical research, never silently downgrade a new file |
| Stik inherits 15 m/s start and combustion solver selection; v1 permits an implicit rectangular planform; inventory point masses and zero steering are implicit | Make configuration intent explicit; distinguish exact zero from omitted required input and inactive systems |
| P-51 gasoline runs through historical `glow_prop` code; turbine and electric already have independent dispatch | Describe solver family versus fuel/hardware accurately; use existing equations, no speculative new engine law |
| Frame/convention prose is not executable validation | Require a machine-readable convention identifier with one documented transform; do not infer signs from model names |
| Some quantities are validation/reference evidence, not force inputs (e.g. firewall and engine brochure power); `CLadot` has no aerodynamic consumer | Identify their roles; move or constrain unsupported inputs rather than advertising an effect; retain provenance |
| Global derivatives and local surfaces are related but not interchangeable | Preserve the attached-flow oracle and loader consistency checks; document derived residuals and strip calibration, avoiding double counting |
| All aircraft use a virtual balanced reference inventory; several values are borrowed/estimated | Preserve evidence labels, balancing mass and warnings; no invented physical validation or unmeasured retuning |
| P-51 modeled gear is down; Avanti gear is up with no contacts; flaps are not simulated | Explicit simulated capabilities, separate hardware descriptions; absent systems stay inactive and contradictory declarations fail |
| Extra/P-51/Avanti have upstream derivation scripts; Stik and electric specimens are authored JSON | Migrate generated aircraft through their generators, authored files through an ID-gated migration; verify reproducibility and preserve every numerical input |
| Ground, crash and audio tracks are actively editing this tree | Isolate new modules/tests; minimize shared hunks, preserve their changes and record exact tested snapshot |

Primary references: [Godot 4.7 scalar precision](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html), [JSBSim frames](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/), [mass/inertia convention](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGMassBalance.html), [forces and moments](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/forces-and-moments/), [UIUC low-Reynolds-number airfoil/propeller data](https://m-selig.ae.illinois.edu/pd.html), [UIUC propeller definitions/data](https://m-selig.ae.illinois.edu/props/propDB.html), and the manufacturer/plan evidence already attached to each quantity. Use these to justify conventions and measurement requirements, not to transplant full-scale coefficients into RC models. Retain additional audit sources and limits under AS-00.

## Architecture decisions

1. Introduce `openrc-aircraft v2` with explicit configuration capabilities and fixed conventions. Keep SI quantities with `{value, unit, kind, source}`. The contract defines every implemented field's meaning, bound, dependency, consumer and effect; reference-only fields are clearly identified. Unsupported extensions are documented and rejected at the runtime boundary.
2. Add strict structural/module preflight ahead of the existing physical derivation. Use a small reviewed structural contract and shared generation/checking where practical; do not implement a general JSON Schema engine in GDScript. Existing numeric and coupled checks remain authoritative. The offline schema must match structural acceptance; coupled-physics counterexamples intentionally remain runtime-only.
3. Preserve one normalized runtime model and one set of force equations. Adapt validated v2 into the established derivation, with no per-tick configuration parsing. V1 remains an explicitly tested compatibility path for old experiments. Catalog files and their generators use v2. File identity includes actual source format and bytes; model/checkpoint identity changes when the authored contract changes.
4. Capabilities describe the simulated configuration: conventional controls, deployed fixed contacts or gear-up hull-only contact, single tractor combustion/electric prop or single turbine, prescribed fuel versus modeled battery, terminal hull damage. Physical retract hardware does not claim retract dynamics. No default EDF, pusher, multiengine, flaps, fuel depletion/CG migration, thermal battery, structural break-up or active stability assistance.
5. Retain legitimate aircraft-specific geometry, throws, servo rates, stall envelopes, thrust axes, shaft/wake options, turbine spool/ram terms and gear behavior. Numerical resolution, gravity, integrator safeguards and input-device curves remain system settings. Authored aircraft parameters must not duplicate these constants.
6. No intentional flight-equation or calibration change is planned. Removing inert fields, making defaults explicit and tightening validation are contract changes. Any discovered correction that changes forces must receive its own before/after evidence and explicit plan revision; do not re-record golden flights merely to pass migration.
7. Keep visual builders, node/hinge names and geometry generators stable. Add cross-layer checks for IDs, datum, span, control direction and inactive hardware. Shared runtime capability consumers should read normalized model data rather than introduce another ID table.

## Ownership and coordination

| Area | Owner / boundary |
| --- | --- |
| Plan, final contract, integration and review | Lead; root plan/contract, AS evidence/research, loader dispatch and source migration |
| Configuration/schema audit and bounded implementation | Luna/max; new contract/schema modules and dedicated tests only when assigned after this plan |
| Lifecycle audit and verification | Luna/max; new AS verification driver/tests; no session/main/crash/audio edits without lead coordination |
| Physics/generator audit and authoring material | Luna/max; assigned generator/template changes only; no visual geometry or physical retuning |
| External ground team | Owns `GROUND_PHYSICS_PLAN.md`, terrain, wheel profiles/spin/brakes and session state; AS must not duplicate or overwrite these |
| External crash/audio/UI/model teams | Existing registry remains authoritative; preserve dirty `main.gd`, `flight_session.gd`, crash/render/audio files and docs |

At audit start these external paths were already dirty. A local baseline copy preserves the starting app for comparison. No live communication endpoint to those separate sessions is available; the plan/registry records an ownership reservation, not an acknowledgement from them. Re-read shared files and `git status` before each integration; use narrow patches and review incoming changes. If ground introduces a new profile contract during this work, document/bind that existing interface without editing its solver. Subagent contributions require lead diff review and verification. No dependency upgrades, moving owned files, or commits containing another track's work.

## Phases and proof

| ID | Deliverable | Proof | Status |
| --- | --- | --- | --- |
| AS-00 | End-to-end audit, primary references, boundaries and this complete plan | Current code inspection, engine version, ownership snapshot, [configuration](docs/research/aircraft-standardization/AS-00/config-audit.md), [lifecycle](docs/research/aircraft-standardization/AS-00/lifecycle-audit.md) and [physics](docs/research/aircraft-standardization/AS-00/physics-audit.md) audits | Complete before implementation, 2026-10-11; lead review corrections retained |
| AS-01 | `AIRCRAFT_CONTRACT.md`, field/consumer inventory, capability matrix and v2 schema/runtime preflight | All supported modules represented; unknown/null/type/unit/branch contradictions rejected; v1 compatibility explicit | Complete; closed v2 preflight/schema, 148-path register and conditional-module semantics |
| AS-02 | Four aircraft and electric fixture migration through source pipelines | Reproducible outputs; value/evidence comparison; no undocumented numerical delta | Complete; 8 files, 2,815 original numeric leaves preserved, zero differences; three generator pipelines reproducible |
| AS-03 | Lifecycle/consumer alignment and reusable authoring template | IDs, controls, animation, inactive systems, trim/reset/reload/checkpoint and source identity tests | Complete; catalog identity/version guard, template, exact 8-aircraft lifecycle comparison and 170 hinge checks |
| AS-04 | In-engine flight/propulsion/ground/damage/regression/performance matrix | Retained Godot logs, comparison records and source hashes; no golden rerecording | Pending |
| AS-05 | Reviewed delivery, audit comparison, concise add/tune guide, gaps and results | Fresh-copy integrity where paths/generated outputs change; final diff/ownership review; documentation indexed | Pending |

## Measurable acceptance

- Every catalog aircraft and all existing electric variants load under the pinned engine with no script errors. Invalid files fail with actionable paths and no flyable model. Test missing fields, explicit null, zero, unknown fields, nonfinite values, wrong dimensions/units, contradictory modules and unsupported future layouts.
- Every configurable numerical field has a declared role and consumer; values used only for evidence or plausibility cannot masquerade as active forces. Unknown coefficients fail in v2. Required inactive modules are absent; there is no invisible propeller, battery, gear, flap, brake or fuel-burn behavior.
- Match independently recorded baseline mass, CG, inertia, reference geometry, control outputs, trim and force samples for each existing aircraft. Compare deterministic same-platform airborne state/propulsion trajectories exactly where only metadata changes; report any numerical exception and investigate it. No acceptance by replacing baselines.
- Verify control direction and throws; combustion RPM/shaft behavior, turbine spool/ram behavior and electric battery behavior; zero commands and zero-load cases. Existing meaningful physics tests remain the numerical/analytic oracles.
- Verify three deployed-contact aircraft static balance, steering and existing ground scenarios; Avanti remains explicitly in-air only. Ground changes from another track are separately identified in results rather than attributed to AS.
- Exercise restart, pause/resume, aircraft switches, malformed reload rollback and checkpoint replay. A checkpoint from changed data must not silently restore into a different model. Crash/reset returns to the selected aircraft's initial configuration and energy state.
- Run the full supported app suite (or its equivalent native Windows commands if the shell cannot run Linux Godot), all four model contracts, existing schema tests and new v2 tests. Treat engine errors as failures even with exit code zero. Record unrelated concurrent failures precisely; repair AS defects and rerun affected checks.
- Measure load validation and steady-state tick cost on the same machine, alternating baseline/candidate where practical. Target no new per-tick work and no statistically credible >5% tick regression; report timing variability and p50/p95 rather than claiming a hard realtime budget from a shared host.
- Validate generated output freshness and packaged schema/resource availability from an isolated fresh copy. Keep proof and source URLs in `docs/research/aircraft-standardization/`; no documentation links to ignored artifacts.

## Risks and remaining physical gates

Strictness may uncover research fixtures intentionally mutating optional systems: convert those fixtures explicitly to legacy v1 or update their capability declaration; do not weaken v2. Source identities/checkpoints will change even when trajectories do not. Generator prerequisites may include local plan assets; report reproducibility limits. Concurrent ground/crash/audio changes can invalidate a baseline, requiring an isolated overlay comparison. Tables and coefficients retain their stated evidence quality; low-Reynolds-number flight, control effectiveness, inertias, tire/grass properties and engine transients still need measurements. The standard makes these gaps visible and prevents unsupported configurations; it does not manufacture missing physical evidence.
