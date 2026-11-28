# EDF-00-R2: Twenty investigations for a native EDF experiment

**Date:** 2026-11-21. **Inspected source:**
`9d17c29ed2463cdb3a67d3bd573c0137587edb9d`.
**Branch:** `research/edf-propulsion-2026-11-21`; [PR #18](https://github.com/bultodepapas/OpenRCsimulator/pull/18).

The owner requested twenty distinct investigations into physics, games, tools,
guides, skills, GitHub and Reddit, with useful learning integrated into the plan
and a strong native-code requirement. Three source-read-only specialists covered
R2-01…06, R2-07…13 and R2-14…19; the lead investigated R2-20, checked decisive
source/math claims and integrated the candidate. A fresh Good Enemy reviewed
the native boundary and combined changes. Requested helper routing was Terra/max;
effective model/effort metadata was not independently verified.

This is a research/design delivery, not twenty executed simulation experiments.
Each investigation below has a question, inspected evidence, disposition,
implementation consequence and falsifiable future experiment. Primary literature,
upstream documentation/code, repository source and community anecdotes remain
distinct. The [plan](../../plans/edf-propulsion.md) owns implementation order;
the [native runtime design](native-runtime-design.md) owns the proposed execution
and product contract. All new implementation and physical gates remain pending.

## Investigation map

| ID | Question | Disposition / integration |
| --- | --- | --- |
| R2-01 | How small can an identifiable installed fan model be? | Accept compact prepared maps and output-specific identification; EDF-02b/03/09. |
| R2-02 | What really transfers between fan sizes? | Accept a similarity audit; defer measured coefficient transfer; EDF-02b/11. |
| R2-03 | How should inlet/nozzle and incidence enter the law? | Accept prepared geometry-specific surrogates; CFD offline only; EDF-02b/03/07/09. |
| R2-04 | Which dynamics are physical and which belong to the controller? | Start with torque/inertia; defer unidentifiable extra lag states; EDF-01/04/05/09. |
| R2-05 | How can current limits and source-off modes be consistent and fast? | Accept averaged first slice and a bounded synthetic limiter candidate; defer switching/regen; EDF-04/05. |
| R2-06 | What pack measurements constrain voltage and temperature separately? | Accept mission-relevant pulse/rest and thermal cards; EDF-02b/04/09. |
| R2-07 | What does a complete native EDF path require? | Accept a generic native numerical-tick capability and EDF launch refusal without it; EDF-01/05/06. |
| R2-08 | Where should data, scratch and boundary copies live? | Accept immutable prepared inputs and measured bounded allocation; EDF-02/03/06/12. |
| R2-09 | Which interpolation properties actually preserve energy behavior? | Accept joint cell/interior checks; defer unqualified cubic smoothing; EDF-03/06. |
| R2-10 | Which compiler/SIMD changes preserve the numerical contract? | Retain strict scalar FP; defer separately qualified optimization; EDF-06/12. |
| R2-11 | How can native events, damage and rollback remain one transaction? | Port complete admitted policies and qualify commit ordering; EDF-01/05/06. |
| R2-12 | Should one coupled tick be parallelized? | Start with one simulation owner; parallelize independent offline cases first; EDF-05/08/12. |
| R2-13 | Which native tests provide evidence beyond parity? | Add bounded fuzz/property/sanitizer controls to owning tools; EDF-03/05/06/12. |
| R2-14 | What does efficient mean for the actual flight callback? | Measure law, bridge, numerical tick and full callback separately; EDF-12. |
| R2-15 | What can other open-source simulators/tools contribute? | Borrow ideas; optional offline checks; reject a replacement flight engine; EDF-01/02/07. |
| R2-16 | How should an EDF sound without aliasing or physics feedback? | Native accepted-state observer and band-limited surrogate; EDF-08. |
| R2-17 | What will the user see and do? | Native Godot stand → installation preview → flight → debrief; EDF-07/08/10. |
| R2-18 | Which small virtual campaign exposes useful interactions? | Eight corners plus a center with complete case receipts; EDF-10/11. |
| R2-19 | Which skills and workflows are actually relevant? | Reuse OpenRC tools/debug/audio/native guides; no speculative plugin install; EDF-01/12. |
| R2-20 | How can native-only behavior survive actual distribution? | Per-target ABI/package/loader/lifecycle admission; EDF-06/12. |

## Physics and identification

### R2-01 — Compact installed maps and identifiability

**Evidence:** NASA's EDF characterization [N01], response-surface propeller work
[N02] and SmartFan testbed [N03]. These distinguish multiple operating inputs,
measurement channels and validation observations. Propeller methodology and a
small research rig are not coefficients for the A200 installation.

**Decision:** fit a small map or local polynomial offline, with the actual
regressor matrix, rank/conditioning, output-specific support and tare model
retained. A static thrust/DC-power fit cannot identify unobserved shaft torque,
inertia or installed moments. Investigate measurement choices that break the
correlation rather than adding unconstrained coefficients. Assess whether support
drag and fan/fixture interaction can be separated in the measurement boundary.

Regional models may use the same convex weight for the complete force/moment/
shaft-load tuple at the same physical input. The existing scoped passivity
expression is affine in that tuple, so blending pointwise passive candidates
this way preserves it. R2-09 explains why ordinary table interpolation has a
different guarantee. This is our mathematical deduction, not measured fan data.

**Integrate:** EDF-02b/03/06/09; T02/T05/T06/T32. Prepare coefficients once and
evaluate bounded scalar arithmetic; a transition region may evaluate two models.
**Experiment:** fit two admissible models to the same static observations, then
discriminate them with independently acquired wind-on and transient observations.
If their unobserved outputs remain different, retain the identification gap.

### R2-02 — Scaling, Reynolds number, Mach and clearance

**Evidence:** [N01], a small axial-compressor Reynolds study [N04], and measured
ducted-fan geometry/clearance in [N05]. The compressor is a different machine and
working-fluid experiment; its trends do not supply an EDF correction factor.

**Decision:** add a per-size similarity audit: actual rotor-tip diameter, chord,
hub ratio, blade/stator geometry, dimensional and normalized clearance including
circumferential variation, density, viscosity, sound speed and local helical tip
Mach. Catalog casing sizes are not sufficient. Defer cross-size measured-map
transfer; keep each 128/152/195 mm candidate's own evidence and identity.

For hypothetical geometrically similar ROTORS at fixed tip speed, RPM scales
as `1/D` and chord Reynolds number approximately as `D`; at fixed RPM, tip speed
scales as `D` and chord Reynolds number approximately as `D^2`, holding other
assumptions fixed. These deductions do not characterize the catalog products.

**Integrate:** EDF-02b/11 and its feasibility manifest. Compute similarity during
preparation; add runtime axes only when identified. **Experiment:** compare a
matched fan/duct before and after a measured clearance change at the same RPM
and inflow, with thrust, torque or labeled electrical proxy and uncertainty.
Do not generalize one response into a universal gap law.

### R2-03 — Duct/nozzle geometry and offline CFD

**Evidence:** wind-tunnel/CFD ducted-fan work [N06], a high-incidence inlet study
[N07] and the variable-nozzle SmartFan rig [N03]. They motivate coupled geometry,
flow and load observations; their scales and configurations differ from this EDF.

**Decision:** accept CFD/reduced-flow analysis for offline screening and estimated
surrogates, with matched boundary conditions, grid sensitivity, tare and separate
measurement comparisons. A CFD output alone does not qualify a physical flight
map. Do not impose a universal incidence threshold or assume separation changes
every output abruptly. Keep signed inflow and distinct pitch/yaw support for an
asymmetric installation. A thrust-only multiplier cannot generally describe
simultaneous moment and shaft-load changes.

**Integrate:** EDF-02b/03/07/09. Fixed inlet/nozzle geometry selects an immutable
prepared map; existing WindFlow supplies local flow once. Keep one owner for
installed inlet/duct/nozzle forces. **Experiment:** compare two nozzle areas at
matched RPM/inflow using synchronized wrench, DC input, optional shaft torque
and pressure measurements on separate fit/validation runs. Runtime cost is a
small lookup/polynomial, with no live CFD solver.

### R2-04 — Spool, control dynamics and model order

**Evidence:** [N01] reports setup-dependent command-to-speed response; [N03]
uses a torque/inertia mechanical model; rotorcraft dynamic-inflow work [N08]
illustrates identification limits but is not a fixed-wing EDF law.

**Decision:** retain the coupled shaft inertia as the first physical dynamic
state. Record effective command, controller ramp settings and sensor bandwidth.
An empirical extra lag can duplicate dynamics already represented by the shaft
and controller. Defer aerodynamic memory until repeatable residuals distinguish
it from electrical, controller, sensor and structural effects. Any later inflow
state needs a storage/work boundary; the present quasi-steady passivity check
cannot be applied unchanged.

**Integrate:** EDF-01/02b/04/05/09. A later state adds native derivatives,
checkpoint fields and coupled accuracy/event checks. **Experiment:** compare
up/down transients at the same instantaneous RPM and inflow but different
acceleration history, across controller ramp settings. Retain time alignment,
measurement delay and independent runs. A persistent residual motivates model
development; it does not uniquely identify a new aerodynamic state.

### R2-05 — Current limits, winding dynamics and source-off meaning

**Evidence:** TI's BLDC current discussion [N09] and H-bridge decay paths [N10]
show why bus current, winding current and conducting freewheel paths differ.
The illustrated circuits are not evidence for the selected EDF ESC firmware.

**Decision:** start with a declared one-quadrant averaged drive and an ideal
isolated source-off mode. Aerodynamic windmilling does not imply a particular
electrical coast/brake/rectification path. Regeneration and switching-level
protection remain separate identified modes. Compare current only at matched
measurement/filter bandwidth.

A useful synthetic native limiter can solve its active branch directly. With
`E0 = E_pol - R_pack I_aux`, back-EMF `Eb`, motor resistance `Rm` and motor-current
limit `I*`, ideal duty `d` satisfies

$$
R_{pack} I_* d^2-E_0 d+(E_b+R_m I_*)=0,
\qquad
d=\frac{2(E_b+R_m I_*)}{E_0+\sqrt{E_0^2-4R_{pack}I_*(E_b+R_mI_*)}}.
$$

This is the lower admissible root of the stated ideal circuit, not an ESC model.
Specify zero/degenerate branches, positive bus, real discriminant, continuity
from the unlimited branch and `d <= requested duty`; otherwise refuse. Recompute
current, voltage and torque together. With 48 V polarized source, 0.2-ohm pack,
zero auxiliary load, 12 V back-EMF, 0.1-ohm motor and 40 A limit, `d=0.354248689`,
bus voltage `45.16601049 V` and pack current `14.16994756 A`; ideal bus power is
640 W. Motor current is not pack current.

Adding a synthetic `L/R=1 ms` state to one unsplit 240 Hz RK4 step gives error
amplification `6.016235854`, versus exact frozen-coefficient decay `0.015503854`.
Defer that model until coupled numerical admission, magnetic storage and current
decay paths are qualified. An isolated exact electrical update is not a proof
for changing speed, bus voltage and duty.

**Integrate:** EDF-04/05/06, T08/T10/T11/T33. **Experiment:** sweep the limiting
transition and independently check both circuit equations, torque, rejected
roots, source modes and native parity. The direct branch uses bounded scalar
arithmetic and one square root; actual cost remains unmeasured.

### R2-06 — Pack identification and thermal claims

**Evidence:** pulse/relaxation selection study [N11] and independent entropy/
electrothermal experiments [N12]. Their cells, cooling and current histories are
not a calibration for the proposed pack. In the repository, `pack_ecm.gd`
uses ohmic plus RC-resistor dissipation and one lumped temperature.

**Decision:** retain a low-order average/weak-cell model as an estimated first
slice, with the prior thermal-stiffness finding still requiring resolution.
Choose identification pulses/rest periods around the EDF mission before adding
RC branches. Label reversible heat, spatial temperature gradients and hotspots
unmodeled. Good terminal-voltage agreement does not establish thermal accuracy.
Do not substitute `I(OCV - V)` for instantaneous heat: RC storage contributes
to that difference during transients.

**Integrate:** EDF-02b/04/09 and V05. Independently identify heating/cooling;
record measurement locations, cell/pack voltage, current, SOC, airflow and
temperature. **Experiment:** fit on one pulse/rest sequence, validate on a
separate takeoff/climb/cruise-like load train across declared initial conditions,
and score voltage, weak-cell minimum and temperature separately. Further states
consume native stage work only when independent evidence warrants them.

## Native architecture and numerical execution

### R2-07 — Close the entire native numerical path

**Evidence:** current `native_stage.gd`, `Simulation.step`, `FlightSession` and
the native guide. JSBSim's run-loop structure [N43] is an architectural contrast,
not a replacement transaction. Its mutating propulsion/fuel operations must not
be copied into repeatedly evaluated RK stages.

**Decision:** the owner requires more than today's native stage evaluator.
Propose one generic native numerical-tick capability through the shared kernel,
with no EDF-only loop. Include native stateful input conditioning/arming/rates,
sampled controls, turbulence/RNG, full stage laws, integration/events, contact,
terminal decisions, endpoint policies and validation. Existing raw-device
capture and Godot shell dispatch can remain outside numerical evaluation.

Native-only EDF launch admission must cover every required policy and world;
missing or refused capability disables that experiment. Reference execution is
an explicit verification tool, not a playable fallback. Existing non-EDF policy
remains unchanged. The [native design](native-runtime-design.md) records this
proposed shared-kernel change and the actual source gap.

**Integrate:** EDF-01/05/06, T30/T31/T34. **Experiment:** trap every reference
state-affecting callback while running a native mutant/control from a pinned
checkpoint, including live input and runway/contact. Native-stage counts alone
cannot pass. This adds substantial port/qualification work; no speedup is assumed.

### R2-08 — Prepared data, scratch and bridge cost

**Evidence:** `nk_kernel.cpp::stage`, `nk_stage.hpp::StageResult`, prepared native
scratch and Godot's packed-array/Variant documentation [N13]. The current stage
builds dictionaries/output arrays and uses vector storage; it is not proven
allocation-free.

**Decision:** prepare immutable validated map/geometry/electrical data and use
private pre-sized double arrays for the whole tick, k1–k4 and bounded event
trials. Prefer one detached complete result at the Godot boundary over per-stage
marshaling. Keep ownership explicit; packed-array handoff does not guarantee
zero-copy behavior. Source/identity guards remain effective.

A last-cell index is only a checked lookup hint. Speculative queries may arrive
out of order; a rejected trial cannot make a later answer depend on cache history.
**Integrate:** EDF-02/03/06/12, T32/T36. **Experiment:** count allocations/bytes
after prepare in ordinary, event-heavy and refusal paths; compare cache-on/off
and adversarial query order byte-for-byte. Memory bounds and boundary copies
are reported explicitly rather than hidden by a stage microbenchmark.

### R2-09 — Interpolation and interior energy behavior

**Evidence:** bounded linear interpolation mathematics and the scoped power
contract; SciPy's one-dimensional PCHIP definition [N14]. PCHIP preserves
monotone data and first-derivative continuity, not arbitrary multidimensional
physical constraints. No SciPy runtime dependency is proposed.

**Decision:** start with explicit supported cells/holes, ordered axes,
deterministic knot ownership and finite refusal. Vertex bounds and scalar
monotonicity do not prove a coupled power inequality inside a cell. In a
normalized example `Omega=x`, `Q=x`, `F=x`, `V=1`, the passivity residual
`F V - Q Omega = x-x^2` is zero at both endpoints but +0.25 at `x=0.5`.

By contrast, R2-01's common convex blend of complete candidate outputs evaluated
at the SAME input preserves a pointwise affine inequality. At `V=20, Omega=100`,
tuples `(F,Q)=(5,1)` and `(0,0)` each yield zero power residual; using the first
force and second load creates +100 W. These are analytic negative controls.

**Integrate:** EDF-03/06, T05/T32. **Experiment:** independently bound admitted
cells/interiors, knots and branch transitions; reject cells whose required
constraint cannot be established. Defer cubic smoothing until its fidelity,
accuracy and coefficient/evaluation cost justify another qualified law identity.

### R2-10 — Strict floating point and SIMD

**Evidence:** `nk_math.hpp`, effective build flags and compiler guidance [N15]/[N16].
The existing kernel deliberately controls operation order, selected special-value
behavior and math shims. Clang contraction is a separate policy from fast-math;
MSVC guidance does not qualify the project's current MinGW Windows toolchain.

**Decision:** preserve qualified scalar double arithmetic, effective
`-fno-fast-math` and `-ffp-contract=off`, FP environment and math-library receipts.
Do not change the single-precision Godot binding ABI to obtain double simulation
values. Matching-host byte parity remains distinct from cross-platform identity.
Defer SIMD, reassociation, mixed precision and new transcendental approximations.

**Integrate:** EDF-06/12 and T16/T30. **Experiment:** evaluate any proposed
optimization on the pinned host with special values, signed zero/subnormals,
map knots, full event trajectories and checkpoint continuation. A prohibited
byte mismatch fails it. Independent-scenario SIMD is a possible later target;
reordering one coupled trajectory is not a free optimization.

### R2-11 — Events, mutable world state and atomic publication

**Evidence:** `event_step.gd`, the composed electric step and session commit
paths; CVODE's documented sign-change root limitations [N17]. That numerical
reference is a warning about a class of methods, not a proposal to install CVODE.

**Decision:** port the complete admitted event/contact policy natively, including
moving-side probes, stage minima, tolerances, tie order, projection and bounded
work. Define supported crossings/grazing; do not promise universal event finding.
Keep only accepted-path diagnostic receipts.

Immutable collision geometry is not the whole world state. Broken scenery IDs,
failure/contact/crash modes and pending incidents affect later physics. They
must participate in candidate/commit/rollback and checkpointing. Native pre-step
terminal decisions are part of closure. Current ordinary steps emit events
before the session's stepped damage commit; the existing publication guard is
for prepared reset/restore, not all ticks. Propose an EDF-native complete commit
before event/step publication, with a separately qualified guard for detectable
mutation, forbidden synchronous transition reentry and explicit observer failure.
Precommit refusal retains the prior frame; detected postcommit violations retain
the new frame and pause/fault. Define notification/recording outcomes and keep
legacy non-EDF observer semantics. This is not universal engine-error recovery.

**Integrate:** EDF-01/05/06 and T11/T13/T31. **Experiment:** stop/cutoff/contact
ties, grazing, rejected subdivisions and failures at each phase; then a scenery
hit, second pass, restores from both pre-break and post-break checkpoints, and
a rejected hit. Each restore recovers its recorded intact/broken world version.
Check physical state, damage, RNG,
events and clock. Refinement adds bounded worst-case work measured separately.

### R2-12 — Threads, simulation ownership and render interpolation

**Evidence:** Godot thread-safety/interpolation guides [N18]/[N19] and Fiedler's
fixed-timestep discussion [N20]. Active scene-tree operations are not a general
worker-thread API; interpolation also has a visual latency tradeoff.

**Decision:** keep one numerical owner initially. The motor/pack/rotor/body/
contact stages are coupled, so worker subdivision creates synchronization and
ordering costs before a benefit is demonstrated. Publish detached previous/
current frames; rendering interpolates only its view. If workers are introduced,
define buffer lifetime and ownership, not merely an atomic pointer swap.

**Integrate:** EDF-05/08/12, T34/T36. **Experiment:** the same command fixture at
different render rates, including zero/one/multiple ticks per rendered frame,
must preserve accepted states and event order. A later worker-count experiment
needs deterministic ordering and race-detection coverage. Parallel independent
offline campaigns first; never infer that this makes one live flight faster.

### R2-13 — Native fuzzing, sanitizers and independent properties

**Evidence:** LLVM sanitizer/fuzzer contracts [N21]/[N22]/[N23] and existing native
qualification tools. UBSan's `undefined` group excludes floating divide-by-zero;
TSan's useful coverage depends on the instrumented code and relevant libraries.

**Decision:** use bounded pure-C++ targets for map/layout decoding, finite-domain
queries and checkpoint validation, with resettable state, corpus/seed identity
and minimized reproductions. Add analytic conservation/symmetry/interior-power
properties and differential full-tick checks. Keep diagnostic and performance
builds separate. Sanitizers and parity do not establish physical accuracy.

**Integrate:** EDF-03/05/06/12, T30/T31/T32. **Experiment:** deliberately seed
bounds errors, undefined integer operations, relevant floating divide-by-zero,
malformed maps and known physical counterexamples. A pipeline missing its
positive control is inconclusive. Instrumentation, corpus maintenance and
additional CI time are explicit costs; do not add a broad testing framework
where a focused existing native tool suffices.

## Game experience and engineering tools

### R2-14 — Measure the actual flight, not just the evaluator

**Evidence:** Godot CPU/debugger/Tracy guides [N24]/[N25]/[N26], Instruments [N27],
ETW [N28], and the repository's Apple performance plan. Community report C02
motivates editor-versus-export comparison but supplies no EDF benchmark.

**Decision:** distinguish pure-law cost, bridge/marshaling, complete numerical
tick, and full callback with observers. Current `step_usec` is smoothed and ends
before final observers. Record raw distributions, actual native path, warm-up,
sample counts, source/binary, target hardware, display/renderer and workload.
Profiling can perturb cost; use it for attribution and remeasure release output.

**Integrate:** EDF-12, T27/T36. Keep the owning 500-microsecond gate's exact
regime/statistic semantics; also report p50/p95/p99 and defined event tails.
**Experiment:** alternate matched native flights with observers on/off, including
throttle/current-limit and stop/contact workloads, on a quiet admitted host.
Use existing debug/GOD TEST and native platform tools before adding Tracy hooks.
Do not compare an instrumented candidate to an uninstrumented baseline as a
speedup measurement.

### R2-15 — Learn from open-source flight tools without importing their assumptions

**Evidence:** JSBSim's actual electric class/run-loop code [N29]/[N43], OpenVSP mass
properties [N30], AeroSandbox [N31] and their upstream licensing statements [N42].
The inspected `FGElectric` maps throttle to nominal power before its thruster;
that class is not this finite-pack, current-limited, coupled EDF model.

**Decision:** accept interface and independent limiting-case ideas; defer optional
offline geometry/sensitivity cross-checks; reject wholesale replacement of the
OpenRC transaction or adding another flight engine to the runtime. OpenVSP can
check modeled component properties, not actual physical fit. License labels
(JSBSim LGPL 2.1, OpenVSP NOSA 1.3, AeroSandbox MIT) require component/data review
before code, datasets or assets are copied or redistributed.

**Integrate:** EDF-01/02/07, T18. **Experiment:** independently define point masses
and simple shapes, move the pack and compare signed CG/full inertia against hand
calculation, optionally a pinned external model. Preserve discrepancies and
units. Community authoring question C03 informs clarity of the data workflow,
not solver accuracy. External tools remain optional offline dependencies.

### R2-16 — EDF audio as a native accepted-state observer

**Evidence:** NASA fan-acoustics material [N32], Godot audio generator [N33] and
existing audio tool contracts. Community C04 suggests testing layered sounds;
it does not supply a measured EDF spectrum.

**Decision:** a native recorded/procedural surrogate consumes final accepted
RPM/load, source/pause state and epoch/tick, with bounded queues and stale-epoch
discard. Blade-pass frequency is an anchor, not a loudness/spectrum model.
Native synthesis and Godot's mixer remain outside physics. Smooth presentation
only; preserve complete physics checkpoints with audio on/off.

**Integrate:** EDF-08, T22/T23/T35. **Experiment:** at 14 blades and 45,000 RPM,
test the 10.5 kHz anchor and its harmonics at an actual 48 kHz sample rate;
the third is 31.5 kHz, above Nyquist. Fade/omit or band-limit unsupported bands,
capture real-driver PCM and check aliasing, clipping and pause/reset. Dummy
covers routing/lifecycle only. Budget synthesis, buffering and mix overhead
separately from numerical physics.

### R2-17 — A small native Godot experiment flow

**Evidence:** existing Home/session/HUD contracts and Godot Control/focus guidance
[N34]. Community C05 supplies a keyboard-activation case to test, not a claim
that OpenRC has that issue.

**Decision:** add a compact stand → installation preview → flight → debrief
flow inside the existing application. The [native design](native-runtime-design.md#5-what-the-experiment-should-look-like)
defines each view and its boundary. Show thrust, actual RPM, voltage, pack/motor
current, source/limit reason and evidence quality from detached accepted state.
Unknown temperature is unavailable, not zero. Use text/symbols as well as color;
keep solver/ABI details in developer views.

**Integrate:** EDF-07/08/10, T18/T21–T23/T35. **Experiment:** at 1080p, complete
Home → stand → preview → flight → pause/reset → Home using keyboard/controller;
inject a limit and an out-of-domain fault, verify labels against accepted frames,
and review the separate Retina target. Geometry, force arrows, cutaway/blur and
flow illustrations are presentation only. Reuse themes and native controls;
do not add a separate web app or per-render-frame simulation.

### R2-18 — A small reproducible virtual design campaign

**Evidence:** NIST's factorial/interactions example [N35], existing flight-test
and recording tools, and Godot threading guidance [N18]. Community test-stand
project C06 is a channel-selection idea, not an acquired calibration dataset.

**Decision:** predeclare eight low/high combinations of pack resistance, mount
mass and a physically coherent installation-loss assumption, plus a center case.
Regenerate mass/CG/inertia and joint map outputs consistently; an independent
thrust multiplier must not create energy. Report invalid/out-of-domain cases.
This tests interactions among assumptions, not measured confidence intervals.

**Integrate:** EDF-10/11, T24/T36. **Experiment:** retain a manifest with generator,
map/source/backend/card identities, factors/units, initial conditions, seeds,
case completion and output hashes; compare stand and separately trimmed flight
cards. Reuse/version the owning flight-test card. Exact replay stays within one
matching identity; candidate replay is open-loop, requires compatible layouts
and cannot retrim a turbine tape into an EDF. Parallelize independent offline
jobs only through admitted tools, and serialize performance comparisons.

### R2-19 — Select skills by their actual procedure

**Evidence:** repository `openrc-tools`, `openrc-debug`, `physics-sim`, tool/audio
guides; GitHub workflow/artifact guidance [N36]/[N37]. Community C07 motivates
inspection of external plugins, without establishing any specific security claim.

**Decision:** reuse the existing native qualification, checked runner/test pool,
flight-test, debug, capture and audio workflows. `physics-sim` is a Blender
rigid/soft-body bake skill, not the RC float64 solver. Do not install it for
EDF equations or create a generic new skill simply to wrap known commands.
No additional plugin or skill was installed in this research.

**Integrate:** EDF-01/12 evidence instructions and the [tool index](../../tools/README.md).
For a justified new tool, retain exact source/revision, license, acquisition
identity, dependencies and reproduction route. Existing CI pins/gates remain.
**Experiment:** map each proposed measurement to an existing owning tool, then
verify its receipt identifies actual native execution, scope and completeness
when implementation exists. Extend a tool only for a concrete uncovered boundary;
artifact retention alone is not proof that a run passed.

### R2-20 — Native-only packaging, ABI and lifecycle

**Evidence:** Godot's compatibility/descriptor guides [N38]/[N39], godot-cpp's
upstream API/versioning guidance [N40], current OpenRC build/loader guards and
upstream hot-reload issue reports [N41]. Reddit export reports C08/C09 are
reproduction leads; primary loader rules and actual packages decide correctness.

**Decision:** retain the pinned engine/bindings/API/precision/compiler path.
Current native physics doubles coexist with single-precision Godot `real_t`
bindings; changing binding precision alone breaks the intended ABI. Upstream
`latest` docs and godot-cpp master are discovery material, not permission to
upgrade the project's lock. Keep qualified libraries non-reloadable and restart
the process after replacement.

Issue #2059 was closed on 2026-11-06; #2084 was open when inspected on 2026-11-21.
They concern reported hot-reload lifetimes on named upstream configurations,
not a reproduced defect in OpenRC. They motivate retaining explicit lifecycle
tests, not adopting their suggested workarounds.

**Integrate:** EDF-06/12, T17/T26/T30. Each advertised OS/architecture requires
its own actual exported native tick. Unsupported packages show EDF unavailable
without crashing the app or substituting reference physics. **Experiment:**
launch an extracted package, remove or mismatch the library/receipt in a disposable
copy, exercise Home/direct/restart/restore and normal shutdown, and verify native
coverage or the declared refusal. Source-editor success does not qualify release.

## Sources and limits

Sources were inspected on 2026-11-21. Versioned documentation is preferred where
available; `stable`, `latest`, master and issue status can change. Before adopting
code or a dependency, bind its exact revision and confirm behavior on the pinned
OpenRC engine/toolchain. These links are retained evidence, not instructions to
download, install, alter permissions or execute third-party code.

| Ref | Primary source / scope |
| --- | --- |
| [N01] | NASA, experimental EDF characterization for SUSAN, SciTech 2024; setup-specific models and independent validation. |
| [N02] | NASA, variable-pitch propeller response-surface modeling, 2022; method transfer only. |
| [N03] | NASA/HX5, SmartFan model matching/control, Turbo Expo 2025; separately instrumented small testbed. |
| [N04] | NASA, Reynolds effects on a small axial compressor, 1972; different machine/fluid. |
| [N05] | NASA, ducted-fan performance experiment, 2002; 38-inch fan and measured geometry. |
| [N06] | NASA, ducted-fan experiment and CFD, 2002; measured and predicted conditions require matching. |
| [N07] | NASA, high-incidence inlet experiment, 1977; installation-specific distortion/separation. |
| [N08] | NASA, rotorcraft dynamic-inflow correlation, 1986; identification cautions, not EDF coefficients. |
| [N09] | TI, BLDC current protection; winding versus bus current and inductive behavior. |
| [N10] | TI, Current Recirculation and Decay Modes, Rev. A; illustrative H-bridge paths. |
| [N11] | Grebtsov et al., ECM excitation pulse/relaxation study, 2026; controlled cell domain. |
| [N12] | LeBel et al., entropy/electrothermal modeling experiment, 2025; thermal mechanisms and validation. |
| [N13] | Godot 4.7 C++ core types; packed-array access and copying. |
| [N14] | SciPy 1.15.3 PCHIP contract; one-dimensional interpolation properties. |
| [N15] | Clang compiler FP options; effective contraction and optimization controls. |
| [N16] | Microsoft MSVC 170 FP options; separately qualified toolchain guidance. |
| [N17] | SUNDIALS CVODE 7.2.1 mathematical/rootfinding limitations. |
| [N18] | Godot 4.7 thread-safe APIs; active scene tree and server boundaries. |
| [N19] | Godot 4.7 interpolation guide; render/simulation timing and latency. |
| [N20] | Glenn Fiedler, Fix Your Timestep; game-loop design rationale. |
| [N21] | LLVM UndefinedBehaviorSanitizer; supported and excluded checks. |
| [N22] | LLVM ThreadSanitizer C++ manual; instrumentation scope. |
| [N23] | LLVM 19.1 libFuzzer; deterministic in-process fuzz-target requirements. |
| [N24] | Godot CPU optimization guide; measurement and attribution. |
| [N25] | Godot debugger/profiler guide; scope of profiler output. |
| [N26] | Godot latest Tracy guide; optional instrumented engine workflow. |
| [N27] | Apple WWDC2026 Instruments session; target-native profiling guidance. |
| [N28] | Microsoft ETW tools; target-native tracing. |
| [N29] | JSBSim original FGElectric implementation; inspect its actual simplified source assumptions. |
| [N30] | OpenVSP mass-property API; modeled-geometry cross-checks. |
| [N31] | AeroSandbox upstream repository; optional offline sensitivity/optimization. |
| [N32] | NASA fan-noise report; tonal/broadband mechanisms, not an RC sound recording. |
| [N33] | Godot AudioStreamGenerator; procedural audio and compiled-language guidance. |
| [N34] | Godot UI keyboard/controller focus guide; verify pinned-engine behavior. |
| [N35] | NIST full-factorial example; interactions and center points. |
| [N36] | GitHub secure workflow guidance; pinned third-party actions. |
| [N37] | GitHub upload-artifact original README; retention and artifact handling. |
| [N38] | Godot godot-cpp compatibility guide; engine/API/precision matching. |
| [N39] | Godot GDExtension descriptor; target tags, library paths and dependencies. |
| [N40] | godot-cpp upstream README; independent versioning/API target selection. |
| [N41] | Upstream godot-cpp issue #2084; reported reload/shutdown lifetime failure. Related [#2059](https://github.com/godotengine/godot-cpp/issues/2059) was already closed when inspected. |
| [N42] | OpenVSP original license; also inspect [JSBSim](https://github.com/JSBSim-Team/jsbsim) and [AeroSandbox](https://github.com/peterdsharpe/AeroSandbox) licensing before reuse. |
| [N43] | JSBSim original FGPropulsion run loop; mutating engine/fuel operations are not pure RK stage callbacks. |

### Reddit discovery ledger

Community text supplies use cases and failure hypotheses only. Technical
decisions above rely on primary material, current source and future discriminating
checks. Search-returned text was read; some direct page opens were blocked, as
noted. No community benchmark is transferred to EDF performance.

| ID / date | Inspected discussion | Useful lead / access limit |
| --- | --- | --- |
| C01 / 2026-02-16 | [Using C++ GDExtension to optimize a game](https://www.reddit.com/r/godot/comments/1r6039x/using_c_gdextension_to_optimize_my_game/) | Retrieved post/comments; benchmark the actual bottleneck, do not import its speed claim. |
| C02 / 2026-11-17 | [Measuring outside the editor](https://www.reddit.com/r/godot/comments/1xykjbp/you_might_consider_measuring_performance_outside/) | Retrieved post/comments; compare release and editor deliberately. |
| C03 / 2022-08-24 | [FlightGear aircraft XML authoring](https://www.reddit.com/r/flightgear/comments/wwxj1b) | Search-returned post/replies; direct fetch blocked. Authoring clarity only. |
| C04 / 2025-05-07 | [Looping vehicle sounds](https://www.reddit.com/r/godot/comments/1kh97r3) | Search-returned post/replies; direct fetch blocked. Test layered audio. |
| C05 / 2026-06-15 | [Keyboard TextureButton feedback](https://www.reddit.com/r/godot/comments/1u6jldo/texturebutton_pressed_texture_does_not_show_when/) | Indexed post; direct fetch blocked. Test keyboard/controller activation. |
| C06 / 2025-08-23 | [Thrust test stand project](https://www.reddit.com/r/arduino/comments/1mycjxh/my_thrust_test_stand_project/) | Retrieved post/comments; channel synchronization idea, no adopted dataset. |
| C07 / 2026-05-29 | [Asset-library plugin checks](https://www.reddit.com/r/godot/comments/1tr9xid/are_plugins_in_the_asset_library_checked/) | Retrieved post/comments; inspect actual code and dependencies. |
| C08 / 2023-11-30 | [Loading a GDExtension from a package](https://www.reddit.com/r/godot/comments/187qiov) | Search-returned post; direct fetch blocked. Actual exported loader test. |
| C09 / 2026-07-11 | [Exported library placement](https://www.reddit.com/r/godot/comments/1uto6rj/gdextension_libraries_arent_placed_correctly/) | Retrieved post/comments; OS-specific packaging negative control. |

## Integrated outcome and verification boundary

Accepted ideas have explicit EDF steps and T/V discriminators above. Deferred
work is conditional on identified evidence or a measured bottleneck: extra inflow
or inductance states, regen/braking, cubic map laws, SIMD/GPU/live threading,
external geometry/optimization dependencies and matched sound. Rejected shortcuts
include silent reference EDF flight, stage-only native claims, live CFD, an
imported replacement FDM, unsupported physical scaling and copied forum speedups.

The lead independently recomputed the limiter, inductive-RK4, passivity-blend/
cell-interior, audio-frequency and tick-budget examples. These are synthetic
arithmetic, not executions of an EDF implementation. The
[research index](README.md#verification-and-delivery) records document checks;
the PR records CI against the published revision. Source-only reviewers did not
launch the app, benchmarks, hardware tests or audio captures.

[N01]: https://ntrs.nasa.gov/citations/20230017299
[N02]: https://ntrs.nasa.gov/api/citations/20220005627/downloads/Simmons_eVTOL_Prop_Modeling_Aviation22_v04232022.pdf
[N03]: https://ntrs.nasa.gov/api/citations/20250002566/downloads/JJSW_TurboExpo_2025_SmartFan_vfinal.pdf
[N04]: https://ntrs.nasa.gov/api/citations/19720008295/downloads/19720008295.pdf
[N05]: https://ntrs.nasa.gov/api/citations/20020052231/downloads/20020052231.pdf
[N06]: https://ntrs.nasa.gov/api/citations/20020052417/downloads/20020052417.pdf
[N07]: https://ntrs.nasa.gov/api/citations/19770024152/downloads/19770024152.pdf
[N08]: https://ntrs.nasa.gov/citations/19860005823
[N09]: https://www.ti.com/lit/ta/ssztbp2/ssztbp2.pdf
[N10]: https://www.ti.com/lit/an/slva321a/slva321a.pdf
[N11]: https://www.mdpi.com/2032-6653/17/1/38
[N12]: https://www.mdpi.com/2313-0105/11/3/84
[N13]: https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/core_types.html
[N14]: https://docs.scipy.org/doc/scipy-1.15.3/reference/generated/scipy.interpolate.PchipInterpolator.html
[N15]: https://clang.llvm.org/docs/UsersManual.html#cmdoption-ffp-contract
[N16]: https://learn.microsoft.com/en-us/cpp/build/reference/fp-specify-floating-point-behavior?view=msvc-170
[N17]: https://sundials.readthedocs.io/en/v7.2.1/cvode/Mathematics_link.html
[N18]: https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html
[N19]: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html
[N20]: https://gafferongames.com/post/fix_your_timestep/
[N21]: https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
[N22]: https://github.com/google/sanitizers/wiki/ThreadSanitizerCppManual
[N23]: https://releases.llvm.org/19.1.0/docs/LibFuzzer.html
[N24]: https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html
[N25]: https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html
[N26]: https://docs.godotengine.org/en/latest/engine_details/development/profiling/tracy.html
[N27]: https://developer.apple.com/videos/play/wwdc2026/268/
[N28]: https://learn.microsoft.com/en-us/windows/win32/etw/event-tracing-tools
[N29]: https://github.com/JSBSim-Team/jsbsim/blob/master/src/models/propulsion/FGElectric.cpp
[N30]: https://openvsp.org/api_docs/latest/group___computations.html
[N31]: https://github.com/peterdsharpe/AeroSandbox
[N32]: https://ntrs.nasa.gov/citations/19770026169
[N33]: https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
[N34]: https://docs.godotengine.org/en/4.4/tutorials/ui/gui_navigation.html
[N35]: https://www.itl.nist.gov/div898/handbook/pri/section3/pri3332.htm
[N36]: https://docs.github.com/en/actions/reference/security/secure-use
[N37]: https://github.com/actions/upload-artifact/blob/main/README.md
[N38]: https://docs.godotengine.org/en/latest/tutorials/scripting/cpp/about_godot_cpp.html
[N39]: https://docs.godotengine.org/en/latest/engine_details/engine_api/gdextension/gdextension_file.html
[N40]: https://github.com/godotengine/godot-cpp/blob/master/README.md
[N41]: https://github.com/godotengine/godot-cpp/issues/2084
[N42]: https://github.com/OpenVSP/OpenVSP/blob/main/LICENSE
[N43]: https://github.com/JSBSim-Team/jsbsim/blob/master/src/models/FGPropulsion.cpp
