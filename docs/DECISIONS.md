# Decisions

Curated architecture and product choices, with the reasons worth preserving. Reviewed 2026-10-28. Read the relevant section before reopening a design; an approved direction is not proof of implementation, physical validity or performance qualification.

[STACK](STACK.md) owns current architecture, the [ownership registry](README.md#tracks-plans-and-step-ids) routes active work, and [LEARNINGS](LEARNINGS.md) records failure patterns. Linked guides and evidence retain detailed contracts, parameters, alternatives and dated results. Repository rules and display priorities remain in [AGENTS](../AGENTS.md).

| Decision area | Read |
| --- | --- |
| Platform and qualification | [Product and platform](#product-and-platform) |
| Solver, events, native code and replay | [Simulation authority](#simulation-authority) |
| Aerodynamics, propulsion, environment and contact | [Physical models](#physical-models) |
| Aircraft formats, imported models and Workshop | [Authoring and identity](#authoring-and-identity) |
| Launches, controls, failures, logs and companions | [Flight sessions and observation](#flight-sessions-and-observation) |
| Renderers, scenery, cameras, effects and audio | [Presentation](#presentation) |
| Menus, loading, debugging and releases | [Runtime and delivery](#runtime-and-delivery) |

## Product and platform

### Native desktop Godot, with an explicit engine pin

**Gate 1 / GDU-03.** Godot in `app/` replaced the browser prototype because the owner prioritized native desktop delivery, real-radio input and the editor over the bake-off's higher three.js score. The prototype remains frozen. Official Godot 4.8-beta1 replaced the earlier 4.7.x pin after owner-authorized local verification; this did not requalify every platform or historical benchmark. The exact pin lives in [get-godot.sh](../app/get-godot.sh), with rationale in the [bake-off](../prototypes/stage0/COMPARISON.md) and [GDU-03 adoption](research/engine-upgrade/GDU-03/README.md). Reconsider the platform only against demonstrated product or implementation limits.

### Aircraft first; broader vehicles share the foundation

**SF-01 / HELI / RCV / DR.** Vehicle breadth uses the common simulation contracts, with each family retaining its own data, session and qualification. Named helicopter and ground-vehicle consumers justified replacing H10's earlier decision to defer interface extraction. Physics groundwork or a playable research surrogate does not establish a qualified new aircraft or racing activity. Current family status belongs in [STACK](STACK.md#supported-vehicle-paths) and the owning guides; [SF-01](research/simulation-foundation/SF-01/README.md) records the extraction rationale.

### Separate software preservation from product acceptance

**Gate 2 / Gate P / VAL.** Goldens, exact replay and analytic checks protect implementation; independent applicable measurements qualify physical behavior, and pilot, radio and target-hardware gates remain separate. This prevents a model's own coefficients or a development-VM speedup from certifying realism or release performance. The physics budget remains a gate, not a guaranteed runtime bound. Use the [ROADMAP gates](../ROADMAP.md#execution-order-and-release-gates), [VAL-3](research/validation/VAL-3/README.md) and the existing [resolution policy](../AGENTS.md#display-resolution-priorities), rather than copying acceptance numbers into this record.

## Simulation authority

### One float64 kernel, vehicle-owned laws

**SF-01…03.** A session installs one `VehicleModel`; the kernel owns integration, event handling, accepted state and rollback, while models/adapters own vehicle laws and layout. Scalar and packed float64 state preserves small dynamics that Godot rendering types can lose. Rendering converts at the boundary. This eliminates competing tick/checkpoint implementations without adding vehicle branches to the kernel. The [kernel contract](STACK.md#boundaries-and-data-flow) owns coordinates, state layout, timing and callback rules.

### Native acceleration replaces a stage, not the transaction

**SF-08 / NK-3.** Keep the GDScript reference selectable and replace only an identified evaluation boundary. Receipts and replay bind the actual backend; unsupported configurations or unverified artifacts retain the reference. Owner-directed NK-3 promotion supersedes the blanket fixed-wing deferral: ordinary application flights request native by default, but admission is limited to verified Linux x86_64 **stock legacy prescribed-RPM Ugly Stik in supported calm configurations**. Low-level sessions remain reference by default; broader coverage is work in progress. This is not evidence of coupled electric/battery coverage, Windows/macOS admission or completed target-host Gate P.

The [NK-3 promotion](research/native-kernel/NK-3/README.md#promotion-to-the-default-backend) records that limited adoption. The original [SF-08 policy](research/simulation-foundation/README.md#6-backend-policy-sf-08) remains the broader qualification reference; its target-host evidence must not be presented as satisfied by the local promotion. Admission and packaging details live in the [native guide](../research/native-kernel/README.md#optional-normal-flight-backend).

### Preserve each event law's valid continuation

**SF-04 / SF-04b / SF-05.** Share the declared-event protocol where its trial continuation is valid, and retain the rotorcraft domain-guarded locator where negative trial speed would invalidate the law. A whole-tick policy cannot also request kernel contact substeps. Full-load substeps preserve their tested integration semantics; forcing every route through one locator or splitting only selected forces would change them. [SF-04b](research/simulation-foundation/SF-04b/README.md) supersedes the earlier single-locator direction; [SF-05](research/simulation-foundation/SF-05/README.md) owns substep evidence.

### Publish session changes only after physical acceptance

**H8 / GP-14.** Prepare and validate starts, reloads and restores before replacing the accepted flight. Rejection preserves the prior model, state and recording; accepted changes publish explicit old-flight context and commit receipts. An observer fault after physical commit pauses the accepted flight instead of claiming rollback. This prevents recorders, statistics and UI from observing a reset that never happened. Keep the [common start/reload](research/ground-physics/GP-14/README.md#common-start-and-reload-transactions-gp-14e) and [restore](research/ground-physics/GP-14/README.md#accepted-restore-publication-gp-14f) contracts together with the kernel boundary.

### Replay binds complete state and execution identity

**H8 / H9 / H6–7 / FL.** Checkpoints and logs include the continuous, sampled and discrete state needed for continuation, plus source/configuration, timestep and backend identity. Exact replay and a changed-solver candidate are different operations; tolerance qualification is explicit and platform-scoped. Transcendentals retain the `math3d` routing policy, with the adopted built-in `sqrt` exception; this does not promise universal cross-platform byte equality. [Flight-log contract](FLIGHT-LOGGING.md#recorded-data-and-timing), [H8](research/simulation-state/H8/README.md), [H9](research/simulation-state/H9/README.md), [NK-1](../research/native-math-spike/README.md).

## Physical models

### Extend aerodynamic regimes without hiding missing physics

**D9 / D11 / E0a2c / EX-14.** Retain the attached-flow oracle where applicable and use local force/moment laws outside it, with shared physical definitions and consistency checks at regime joins. Aircraft-specific opt-in terms preserve unrelated configurations while new laws qualify. A static fit cannot replace downwash dynamics or establish spin behavior: the Stik's retained post-stall blend and the Extra's fitted polar are separate decisions. The withdrawn P51-22 wing-in-jet repair hypothesis is not an outstanding requirement; its corrected pilot diagnosis remains in evidence. [E0a2c](research/aero-consistency/E0a2c/README.md), [D8b-R2d](research/flight-robustness/D8b-R2/analog/README.md), [EX-14h](research/extra-300-realism/EX-14/README.md#ex-14h--post-stall-wing-polar), [P51-22 correction](research/p51-realism/P51-22/README.md#resolution--2026-10-16).

### Share mechanics while keeping propulsion sources distinct

**G2 / NITRO / AV.** Electrical, turbine, two-stroke and true four-stroke sources retain their own power and lifecycle laws; supported coupled routes solve shaft/body reactions at the same integration stages. Installed profiles bind source data and calibration instead of borrowing a rating as installed performance. This permits shared mechanics without pretending all legacy routes use the newest shaft model. [Propulsion contract](PROPULSION-CORE-PLAN.md), [glow guide](GLOW-ENGINES.md), [turbine coupling](research/turbine-realism/AV-20/README.md).

### Keep finite resources and mass properties physically coherent

**FUEL-00-R1 / FUEL-12 / BAT-13.** The fixed solver datum is the authored reference-inventory CG, not `plan_cg` or the current fill-dependent CG. Fuel changes mass, CG, inertia, contact response and source state through the accepted transaction. Eligible catalog aircraft with `battery_data` use finite packs by default, superseding the earlier ideal-default recommendation; declared ideal/fixed-voltage routes remain explicit exceptions. Pickup geometry and chemistry are not inferred from a generic fuel label. The [fuel standard](FUEL-SYSTEM.md) and [battery specification](research/battery/BAT-04/specification.md) own exact semantics; [Workshop](AIRCRAFT-WORKSHOP.md) owns its source exceptions.

### Version physical weather separately from visual atmosphere

**M5 / VAL-AUD-R09.** The common environment supplies density and wind to each physical consumer at its declared stage and position, while preserving ground velocity. Telemetry retains its declared sample timing, including the distinction between stage loads and accepted endpoint state. Spatial weather uses an explicit versioned, hashed experimental configuration and matched surface-load differences; visual clouds, sky and lighting do not create a second force system. This preserves reference scenarios and makes unsupported domains rejectable. [Wind guide](WIND-PLAN.md), [spatial weather scope](research/wind-implementation/M5-W05d-R1/README.md), [bounded ISA integration](research/physics-audit-2026-10-14/remediation/R09/integration.md).

### Ground support follows authored geometry and actual surfaces

**GP-06/07 / E3.** Gear and hull contacts use explicit datums and are checked against the built model; GP-07 derives the Stik hull from that model. Aircraft tyre coefficients receive field scaling, while airframe sliding friction is specified separately per surface. This replaces hand-placed contacts that drifted from the drawing and avoids treating every ground touch as a crash. Contact constants remain sourced values or labeled estimates, not validated material properties. [GP-06](research/ground-physics/GP-06/README.md), [GP-07](research/ground-physics/GP-07/README.md), [ground surface contract](research/ground-surfaces-e3a.md).

### Advanced contact and structural failure remain gated foundations

**GP-09/11/12/16/17/20.** The newer foundation couples body, wheels and shaft under one authority; it does not silently layer a new response over legacy contact. Damage state and event evidence commit only on accepted paths, never from rejected integrator trials, and absent strength data remains unknown. A parsed resource or numerical bench does not admit stock-aircraft collapse, moving-hub handling or calibrated fracture. [Ground-physics masterplan](advanced-ground-flight-physics-masterplan.md), [coupled foundation](research/ground-physics/GP-11/README.md), [accepted damage contract](research/ground-physics/GP-16/README.md).

## Authoring and identity

### Strict aircraft data and reusable capability admission

**AS-06…14.** `openrc-aircraft v2` quantities carry units and provenance, with explicit capabilities and module combinations. New sources declare physical IDs; historical ID-less v2 data retain compatibility identities. Shared admission classifies the same model for flight and Workshop, while numerical feasibility still requires validation. New topologies such as elevons, tailless airframes and pushers extend the contract instead of masquerading as conventional tails or creating aircraft-ID branches. V1 remains an explicit historical reader. [Aircraft contract](AIRCRAFT_CONTRACT.md), [shared admission](research/aircraft-standardization/AS-06-14/README.md#shared-flight-admission-as-0714-r1-2026-10-26), [X8 topology](research/skywalker-x8/X8-04/README.md).

### Declarative imported models retain authored identity

**AS-09/10 / CR-09c / F4U.** Generated manifests bind source bytes, pivots, hinges, crash sections and supported articulations so shared consumers need no per-aircraft assembly logic. Geometry and animation share their authored kinematics with physical contacts where applicable. Whole-airframe livery GLBs are an accepted F4U delivery tradeoff, not a universal requirement; capacity, paint lists and export poses belong in the aircraft's contract. [Imported construction](research/aircraft-standardization/AS-09-10-import/README.md), [F4U livery rationale](research/f4u-corsair/F4U-16/README.md), [delivery guide](BLENDER-AIRCRAFT-DELIVERY.md).

### One Workshop pipeline; separate physical and appearance builds

**AE-12/13/24 / AS.** Compose capability-based transforms and generated descriptors across the fleet instead of copying formulas or editor screens for each aircraft. Physical builds pin their base, dependencies and compiler; presentation revisions remain independently immutable. Old builds are readable without silent rebasing, and fixed-station mass editing does not authorize arbitrary component relocation. This makes ordinary aircraft additions data/asset work while preserving replay identity. [Workshop contract](AIRCRAFT-WORKSHOP.md), [mass-editing decision](research/aircraft-editor/AE-12-13/README.md).

### Reuse source assets without erasing their terms

Suitable supplied or freely obtainable assets take precedence over recreating equivalents. Their source identity, conversion and redistribution terms remain distinct from the project's MIT code license. An owner's aircraft-specific name or clearance decision does not clear every downloaded model. The [aircraft licensing record](AIRCRAFT-LICENSING.md) owns those cases, and the [source-delivery index](../assets/source-deliveries/README.md) owns the asset references. Revisit a source when its suitability, provenance or distributable form changes.

## Flight sessions and observation

### Launch from a supported physical initial condition

**UI-06d-R3 / D6e-R4 / X8-07.** Interactive geared aircraft prefer a qualified runway start; supported gearless aircraft use hand launch, with airborne selection still available. Valid, supported saved choices take precedence, and a refused selected start does not silently become another start. The interactive level-flight trim is an operating-point choice separate from the low-level reference trim. Release position, throw speed and trim parameters belong in the implementation/evidence, not a second defaults table. [Runway decision](research/menu-investigations/UI-06b/README.md#2026-10-16--fleet-runway-default-ui-06d-r3), [hand launch](research/skywalker-x8/X8-07/README.md), [interactive trim](research/flight-dynamics/power-climb-2026-10-19/README.md#d6e-r4-every-launch-trimmed-for-50--throttle).

### Distinguish device ownership, input shaping and aircraft mechanics

**D6 / F3 / UI-GP.** Radio and gamepad calibration/readiness are separate from menu navigation and physical servo travel. Device detection does not silently transfer an active flight. Radios retain fresh low-throttle arming and disconnect protection; standard gamepads use verified live-poll readiness rather than the superseded centered-dwell gesture. Device-specific shaping must not become an aircraft force correction. [Controller contract and gates](plans/controller-support.md), [F3-GP-02-R2](research/controller-support-2026-10-14/README.md#gamepad-readiness-2026-10-15-f3-gp-02-r2).

### Rigging offsets and loaded servos are different models

**D6-TRIM-01 / D6-SRV-00.** Optional trim practice adds equivalent rigging angles at actual servo deflection, leaving input commands and the start trim solver distinct; the selected first-flight mode preserves its airframe and pilot trims. Loaded torque, heat and causal servo failure are a separate approved design that remains planned, with aircraft-by-aircraft admission and sourced limits. They must not be inferred from random-failure probability or presented as already installed. [Trim-practice decision](research/radio-input/D6-TRIM-01/README.md), [servo plan](plans/servo-dynamics.md).

### Resolve random scenarios and failures before advancing physics

**NR / EM.** Version and freeze the selected episode, seed, onset and severity so restart/replay preserves the same scenario. Stage physical effects through supported actuator/source capabilities, commit only after an accepted tick, and keep notices outside physical identity. New mechanisms do not redraw old versioned lists. Wing separation remains gated because an intact oracle can mask removed strips; hiding geometry cannot implement structural loss. [Failure contract](plans/failure-mode.md#implementation-checkpoint--current-scope), [EM-29](research/failure-mode/EM-29/README.md), [EM-31](research/failure-mode/EM-31/README.md).

### Reuse flight logs for factual analysis

**FL-01…05 / UI-FS.** Bounded recording observes accepted state without driving physics. Offline replay, CSV and existing plotting tools support analysis; marker debriefs reuse those artifacts instead of introducing another campaign runner or unvalidated coaching score. UI statistics and retained flight history have their own lifecycle, not checkpoint authority. [Flight logging](FLIGHT-LOGGING.md), [FL-05](research/flight-logging/FL-05/README.md), [flight statistics](FLIGHT-STATISTICS.md).

### Companions need their own admission, scheduling and replay proof

**AFC-01/02/03.** Preserve the player's tick driver and advance admitted independent companion sessions through a validated command seam after accepted player ticks. Qualify source/controller/field identity and actual corridor geometry rather than assuming every flyable aircraft is AI-ready. Diagnostic manifests can link existing aircraft logs without claiming fleet restore or shared-world replay. This bounds the first integration and keeps AI outside the single-model kernel. [Companion guide and limits](AI-FLIGHT-COMPANIONS.md), [AFC-02 evidence](research/ai-companions/AFC-02/README.md).

### Separate damage evidence, repair assessment and prices

**CR-28…39.** Accepted incidents supply observations; component resolution, repair/salvage estimates and dated commercial prices remain distinct. Unknown structural damage is not silently priced as zero or promoted to measured failure. Coverage groups avoid double-counting variants, and provisional bounds remain labeled. Godot wreck presentation does not feed unqualified state back into flight. [Crash contract](CRASH-DAMAGE-PLAN.md), [economics decisions and limits](plans/crash-damage-economics.md).

## Presentation

### Compatibility baseline and a Windows NVIDIA package

**VQ-07 / GDU-11.** The official-engine build retains Compatibility. Following the owner's 2026-10-28 request, the current-source Windows NVIDIA package defaults to Forward+ and exposes DLSS, DLAA and Reflex as regular saved settings. This supersedes their experimental UI status, not the remaining performance, motion-quality or cross-device gates. Full-resolution Native reconstruction remains the initial choice; Reflex requests On when supported. Matched binaries, runtime hashes and a separate import cache prevent mixing the NVIDIA fork with official-engine resources. Strict AI companion engine admission remains unchanged, and saved companion requests cannot block player-only flights on the fork. Keep the Standard launcher for recovery. [Native package guide](../tools/graphics/native/README.md), [advanced graphics plan](plans/advanced-graphics.md), [GDU-11 implementation](research/engine-upgrade/GDU-11/implementation.md).

### Apple features follow verified engine boundaries

**DT-MAC-00-R2.** Plan native Metal and MetalFX through the existing Godot renderer/reconstruction owners, with a recoverable Compatibility/Native baseline. The inspected 4.8-beta1 driver constructs MTL3 despite documentation describing automatic Metal 4 selection; OS capability labels cannot establish a different command backend. Metal 4 submission, newer neural inputs and frame interpolation are separate upstream-first workstreams, with their own synchronization, latency and release gates. This avoids a parallel renderer or chip-name feature policy and preserves the float64 simulation contract. [Source reconciliation](research/desktop-delivery-investigations/DT-MAC-00-R2/godot-compatibility.md) and the [execution plan](plans/apple-silicon-performance.md) own evidence, pending work and acceptance; this direction is not implementation or Mac qualification.

**DT-MAC-02/07 preparation.** The user requested implementation on Windows for later Mac testing. Keep MetalFX behind an explicit trial flag and validate engine/device capabilities. Record selected policy separately from unknown effective scaler execution: viewport properties alone cannot prove a GPU pass. An unacknowledged Temporal history reset falls back to Native and restores saved MSAA; method presence or submission is insufficient. This allows testing stock engine integration without promoting an unqualified renderer or changing the simulation. [Implementation and Windows checks](research/desktop-delivery-investigations/DT-MAC-02/README.md); native adoption gates remain in the plan.

### Scene detail and birds

**VQ-06b-R1 / SC-BIRD D2 / SC-09-R2.** Interactive scene-detail preferences default to an automatic GPU-name heuristic, with explicit saved selection taking precedence; this supersedes the former unconditional High preference. Technical routes without preferences retain High, and CLI/environment overrides take priority. It is a presentation choice, not hardware qualification, and does not change field-tree collision geometry. Birds have a separate saved live control. Parked-engine detail follows the scene tier without requiring a second baked fleet. The [scene-detail record](research/visual-quality-implementation/VQ-06b-scene-detail/README.md#vq-06b-r1-automatic-level), [bird plan](plans/birds-sky-life.md) and [parked-engine decision](research/scenery-implementation/SC-09-R1/README.md#revision-sc-09-r2-parked-engine-detail-follows-scene-detail) own settings and budgets.

### Share landscape identity and reuse static scenery

**L21…24 / SC-02a / SC-09.** Explicit catalog registration selects matching visual and collision adapters between sessions; it does not add landscape branches to the kernel. Normal interactive scenery is enabled, while reference captures select their intended state explicitly. Parked aircraft reuse material-preserving static bakes rather than spawning flight sessions. Drawn-cost budgets count actual instances, LODs, submissions and textures instead of one source-triangle total. [Landscape contract](LANDSCAPES.md), [scenery guide](SCENERY-PLAN.md), [LU-34](research/landscape-upgrade/LU-34/README.md).

### One read-only camera rig, with a ground-pilot reference

**CAM.** Cameras share the presented aircraft pose and query the existing collision world for clearance; they do not alter simulation or require a duplicate obstacle scene. Ground-pilot view remains the reference. Auto-zoom and FAR use one size target relative to 1080p, so higher-resolution displays preserve screen-relative readability. Optional aids and magnification retain their own pilot/performance gates. [Camera principles](plans/camera-views.md#3-principles), [clearance](research/camera-views/CAM-09/README.md), [reference-height correction](research/camera-views/CAM-23-27/README.md).

### Effects consume accepted observations and per-instance state

**FW / TOD / SM / FW-RGB.** Sky appearance and time, installed lights, smoke and show effects use explicit presentation state and accepted physical observations. They do not advance physics RNG, inject weather forces or silently alter other instances during preview. Authored anchors/outlets separate installation from emitter profiles, and saved appearance upgrades are explicit. This preserves reference flight and prevents preview work from mutating live global state. [Field-world guide](FIELD-WORLD-PLAN.md), [smoke contract](SMOKE.md), [lighting implementation](research/night-flight-lighting/implementation.md).

### Audio follows the installed source, with explicit fallbacks

**AUD-15.** Use licensed recordings where their source fit is identified, superseding the early generated-only choice; retain the phase-aware glow fallback and bounded playback. Accepted physical RPM, source state and contact observations drive sound rather than cosmetic animation or a separate simulated engine. Source fit, listening and target-driver latency remain separate acceptance questions. [Audio guide](AUDIO-PLAN.md), [recorded-source decisions](research/audio/AUD-15/sources.md).

## Runtime and delivery

### Native controls own interaction; styling follows a shared shell

**UI-21/22.** Keep native focus/input and named session pause holds while laying out the shell from a bounded 1080p reference with compact reflow and localization. Theme and finite motion stay beneath controls, with reduced-motion support and explicit preference rollback. Successive color/glass experiments are consolidated in the current visual system instead of remaining competing directives. [Shell contract](MENU-PLAN.md), [color and surfaces](MENU-REDESIGN-PLAN.md#color-and-surfaces).

### Prepare selected work privately and drain cancellation

**UI-05-R3 / UI-34c / DT-11a.** Bounded selected scene and numeric preparation may run after Home's first draw and stable intent; Fly can adopt matching work. Keep outputs private until validation, live-tree construction on main, and cancellation under an owner that drains outstanding jobs. This replaces stale no-prefetch wording without authorizing unbounded speculative work. The dedicated resource-load workaround came from a Godot 4.7.2 fixture, not a demonstrated universal engine defect. [Current preparation policy](MENU-REDESIGN-PLAN.md#selected-preparation-while-home-is-visible), [loader evidence](research/menu-investigations/UI-34c-R5/README.md).

### Use the debug bridge and engine diagnostics for agent work

**PT1h-R7/R8.** The opt-in debug-only loopback bridge provides stable state/input/UI operations, invalid-line rejection and main-thread scene mutation. The launcher issues a per-session token; a manually enabled bridge checks a token when configured. Engine profiling and compiler diagnostics avoid implementing another debugger protocol or depending on a stale language parser. The bridge is not exact replay authority; flight logs retain that role. [Design choice](../tools/debug/README.md#choice-of-design), [limits](../tools/debug/README.md#how-it-works-and-limits), [tool index](tools/README.md).

### Qualify exported artifacts separately from their source tree

**DT / PT1.** Desktop ZIP exports carry one build identity and their actual resources; package inspection, native launch, signing trust and sustained hardware performance are separate checks. Updating remains manual, and installer/web/mobile expansion is not implied by available export templates. Promote the verified artifact bytes rather than rebuilding an assumed equivalent after acceptance. [Delivery contract](DESKTOP-DELIVERY-PLAN.md#current-delivery), [DT-00-R2](research/desktop-delivery-investigations/DT-00-R2/README.md).

**DT-LNX-00 planning direction, implementation pending.** The [Linux plan](plans/linux-support-distribution.md) preserves one qualified payload per architecture/build environment across project package wrappers; byte-changing transformations precede receipt finalization and exact-artifact qualification. Source-built Flatpak output receives independent receipts and evidence. Managed channels own their updates; portable formats retain explicit replacement. This avoids invalidating native admission or mixing package-manager ownership. Broader distro/ARM64 and Flathub claims remain conditional on the [dated audit's gates](research/desktop-delivery-investigations/DT-LNX-00/README.md), not on format availability.

### Preserve Git history and limit future artifact growth

The adopted repository policy retains history rather than rewriting active clones or migrating existing evidence to LFS. Full history supports build identity; re-encoding tracked evidence would retain its old blobs and can destroy pixel-level proof. Bound new artifacts with the [large-file check](../tools/repo/check_large_files.py) and [evidence conventions](README.md#conventions-for-documents). Historical disk totals and provider quotas are not ongoing design assumptions. Reopen only with an explicit repository migration requirement and a coordinated plan.

## Maintaining this record

- Add an entry only for a consequential choice with a credible alternative or a non-obvious constraint. State the choice, reason, scope, owning step ID and canonical evidence. Include a concrete revisit condition when it is not already owned by the linked plan.
- Update the existing topic when a decision changes. Keep a short supersession note only when it prevents a likely mistake; dated reports and Git history retain the full reasoning. Do not append another chronological table or archive.
- Keep parameters, commands, feature inventories, benchmarks, pass counts and next actions in their authoritative homes. A local optimization or bug fix usually belongs in evidence or [LEARNINGS](LEARNINGS.md), not here.
- Label approved-but-unimplemented designs and experimental admissions explicitly. Check current contracts and consumers before turning an old status into a present-tense claim.
- Preserve valuable source/evidence records, verify links and heading targets, and update incoming links when consolidating an entry. New proposals and unresolved choices belong with their owner in the [track registry](README.md#tracks-plans-and-step-ids).
