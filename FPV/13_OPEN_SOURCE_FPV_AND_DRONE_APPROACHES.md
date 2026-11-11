# 25 open-source FPV and drone approaches

**Research date:** 11 November 2026. **Purpose:** strengthen the OpenRC FPV racer plan with actual open-source code, implementation evidence and user/developer needs. **Status:** source and literature investigation; no external flight simulator was built, flown or benchmarked here.

This follow-up investigates **25 distinct open-source projects and their engineering approaches**. It includes human-facing FPV simulators, flight controllers, dynamics libraries, robotics platforms, transmitter/link firmware, telemetry tools and flight-log analysis. They are not 25 interchangeable consumer racing games. Each numbered investigation has a pinned repository revision, inspected license evidence and concrete source paths in [15](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md). Eight additional excluded or scoped examples are documented there without inflating the count.

## Main finding

The strongest opportunity is to combine a reliable OpenRC-owned flight/practice loop with existing open tools for numerical comparison, calibration and analysis. Preserve the float64 NED/FRD kernel and implement its proposed complete transaction first. Use a licensed reference model to challenge the implementation, not to certify physical realism through agreement. Treat firmware, plant, world/collision, input hardware and presentation as separate fidelity claims.

The research supports immediate attention to visible radio setup, explicit rates/configuration identity, complete reset/replay and readable diagnostics. Large autonomy stacks, scanned worlds, RF modeling and learned aerodynamics are valuable optional research directions; they are not additional prerequisites for an experimental M2 flight or the first local M3 race. The concrete integration decisions and 21 proposed checks are in [14](14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md).

## How to read the evidence

- **Observed in code:** an implementation path was inspected at the linked commit. This is narrower than proving that every advertised feature works in a built product.
- **Reported by a user/member:** a specific dated discussion expresses a need, preference or failure in its stated context. Reports may be historical or fixed; the sample is not representative.
- **Inferred user value:** our proposed reason a capability could help a pilot or developer. It still needs a product experiment.
- **Recommended for OpenRC:** a design decision or bounded future experiment, not a completed integration or a promised physical result.

The 19 discussion records in [15](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md) comprise 17 selected user/contributor/member issue reports or questions, one individual commenter anecdote and one separate maintainer-origin observation. They include developer/research needs as well as pilot needs. Stars, forks, README adjectives and issue counts are not used as a popularity or accuracy ranking.

## Approach map

| ID | Project and distinct approach | License scope at inspected revision | OpenRC use |
| --- | --- | --- | --- |
| [OSS-01](#oss-01) | **KwadSim** — A Godot-native racing/practice shell | GPLv3 text; assets separate | FPV frontends |
| [OSS-02](#oss-02) | **FlowState** — Checkpoint metadata and editable-track goals | GPLv3 text; historical snapshot | FPV frontends |
| [OSS-03](#oss-03) | **WebFPVSimulator** — Real flight firmware compiled to WebAssembly | GPLv3-or-later code; NOTICE exclusions | FPV frontends |
| [OSS-04](#oss-04) | **ShramkoGSFPV** — Scanned scenes with explicit collision and configurable scale | MIT code; NOTICE/content exceptions | FPV frontends |
| [OSS-05](#oss-05) | **SimITL** — A complete firmware-plus-plant backend | GPLv3 text; submodules separate | Firmware and backend boundaries |
| [OSS-06](#oss-06) | **libfpv** — An engine-facing C API with explicit timing modes | GPL-3.0-or-later; dependency audit needed | Firmware and backend boundaries |
| [OSS-07](#oss-07) | **OpenFPVSim** — A headless experiment server with a Godot client | GPL code; font and part-data terms separate | Firmware and backend boundaries |
| [OSS-08](#oss-08) | **Betaflight** — The racing flight-controller behavior reference | GPL-3.0-or-later default; per-file scope | Firmware and backend boundaries |
| [OSS-09](#oss-09) | **INAV** — Mode and simulated-receiver semantics for broader RC use | GPLv3 root; inspected PID allows later | Firmware and backend boundaries |
| [OSS-10](#oss-10) | **RotorPy** — Interpretable aerodynamic wrenches and wind experiments | MIT | Dynamics and research |
| [OSS-11](#oss-11) | **gym-pybullet-drones** — Explicit control rates, physics modes and research actions | MIT project code | Dynamics and research |
| [OSS-12](#oss-12) | **Flightmare flightlib** — Independent physics and rendering with a transport boundary | MIT repository code; Unity separate | Dynamics and research |
| [OSS-13](#oss-13) | **multicopterDynamicsSim** — Standalone rotor mechanics and angular-momentum checks | MIT | Dynamics and research |
| [OSS-14](#oss-14) | **Gazebo Sim (gz-sim)** — Plugin lifecycle, simulation clocks and selectable contact engines | Apache-2.0 project code | Dynamics and research |
| [OSS-15](#oss-15) | **Webots** — Propellers with axial-flow terms inside a contact simulator | Apache-2.0 source; ODE terms separate | Dynamics and research |
| [OSS-16](#oss-16) | **Data-Driven MPC for Quadrotors** — Learn residual aerodynamics around an explicit nominal model | GPL-3.0-or-later in inspected source | Dynamics and research |
| [OSS-17](#oss-17) | **RPG Quadrotor Control** — An autonomous trajectory controller as a reproducible test pilot | MIT | Dynamics and research |
| [OSS-18](#oss-18) | **PX4-Autopilot** — An explicit simulated-sensor and actuator bridge | BSD-3-Clause code; docs CC BY 4.0 | Control and interoperability |
| [OSS-19](#oss-19) | **ArduPilot** — External flight dynamics through a deliberately asymmetric protocol | GPL-3.0-or-later inspected SITL | Control and interoperability |
| [OSS-20](#oss-20) | **MAVLink** — Versioned wire messages with explicit units and field presence | MIT XML/generated C; generator/other outputs separate | Control and interoperability |
| [OSS-21](#oss-21) | **MAVSDK** — Typed asynchronous automation outside the simulation transaction | BSD-3-Clause | Control and interoperability |
| [OSS-22](#oss-22) | **QGroundControl** — Joystick calibration data and separate guided sensor workflows | Apache-2.0 OR GPLv3; Qt notice applies | Pilot input and diagnostics |
| [OSS-23](#oss-23) | **EdgeTX** — Transmitter shaping and USB channel assignment as upstream input state | GPLv2 inspected mixer; fonts separate | Pilot input and diagnostics |
| [OSS-24](#oss-24) | **ExpressLRS** — Separate input delivery quality from radio propagation | GPLv3 text; variant/file audit needed | Pilot input and diagnostics |
| [OSS-25](#oss-25) | **Betaflight Blackbox Explorer** — Readable tuning evidence with aligned signals and honest graph scales | GPLv3 text; formats/media separate | Pilot input and diagnostics |

Project count is not independent-physics count. libfpv uses SimITL/Betaflight; several frontends and bridges reuse Betaflight; Gazebo's motor implementation credits RotorS; RPG Quadrotor Control integrates with RotorS; FlightGoggles uses the separately licensed multicopterDynamicsSim. These relationships are material when interpreting apparently corroborating results.

## Detailed investigations

### OSS-01

**KwadSim — A Godot-native racing/practice shell.** [GPLv3 text; assets separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-01).

**Core and features observed.** The inspected Godot 3.2 code has local input, PID, mixer, motor and drag paths, plus lap/checkpoint handling and simulator packet structures. It is useful evidence that a compact Godot FPV game can separate its flight, race and presentation responsibilities. The local Kwad.gd path must not be described as automatically running Betaflight.

**User value.** Repeated lap practice and a discoverable vehicle/course selection are plausible pilot benefits. A historical user reported having no drone or track choices; see UR-06.

**OpenRC decision.** Study scene/gameplay organization and the route from selection to flight. Implement through OpenRC’s current Godot version and accepted-state race contract; do not port a Godot 3 project wholesale.

**Proposed verification.** P13 route discovery and P15 checkpoint/reset checks; confirm a clean export reaches the selected quad and course. These checks have not been executed in this investigation.

### OSS-02

**FlowState — Checkpoint metadata and editable-track goals.** [GPLv3 text; historical snapshot; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-02).

**Core and features observed.** Readable Python utilities in the inspected UPBGE repository assign checkpoint identifiers and initialize camera tilt, rate, radio-calibration and track/lap settings. Much of the game lives in a Blender file; its full flight implementation was not audited. This is a 2018 public snapshot whose relationship to the currently distributed product is unverified.

**User value.** One Reddit commenter gives a subjective realism opinion and describes FlowState’s racing focus and minimal UI; UR-08. The comment does not establish a preference for those features, pilot experience, physical accuracy or a test of this exact source snapshot.

**OpenRC decision.** Take the focused offline practice and editable checkpoint concepts into P23/P24 after M3. Keep course authority, asset provenance and compatible ghosts explicit.

**Proposed verification.** AUTHOR-01…03 plus OSS-WORLD-01; editing a course changes its identity and cannot preserve an old comparable result. These checks have not been executed in this investigation.

### OSS-03

**WebFPVSimulator — Real flight firmware compiled to WebAssembly.** [GPLv3-or-later code; NOTICE exclusions; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-03).

**Core and features observed.** The C simulation path consumes timestamped input, runs a firmware bridge and advances a plant at a 1 ms schedule; the project targets Betaflight 4.5.1 compiled to WASM. The repository also supplies a verification harness. Its reported test outcomes and physical-fidelity ambition were not independently reproduced here.

**User value.** Browser access can reduce setup friction, while stored radio mapping and familiar rates can shorten the route into practice. This is an inferred benefit, not measured learning transfer.

**OpenRC decision.** Use timestamped input/replay and bounded browser packaging as references. Preserve native 1080p-first OpenRC delivery. NOTICE excludes or flags particular media, logos and recordings, so copying the repository as an asset pack is inappropriate.

**Proposed verification.** M1 replay under different render batching; separately inspect generated WASM/dependency identities before any optional browser experiment. These checks have not been executed in this investigation.

### OSS-04

**ShramkoGSFPV — Scanned scenes with explicit collision and configurable scale.** [MIT code; NOTICE/content exceptions; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-04).

**Core and features observed.** The TypeScript source separates a fixed 1 ms model, a timestamped runner, calibration stages and voxel collision queries. VoxelContactWorld searches swept spheres; transformCollision applies a uniform scale/translation with explicit file-space conventions. The flight model uses a Y-up rendering frame and semi-implicit translation, unlike OpenRC’s NED/FRD RK4 core.

**User value.** A scanned familiar place could make exploration and shot planning attractive. Treat this as a product hypothesis: the README’s radio evidence is simulated, and neither real-radio behavior nor scan collision fidelity was tested here.

**OpenRC decision.** An optional post-M3 scenery/authoring experiment. Require separate scan rights, metric scale evidence, collision generation/hash and an immutable course/world identity.

**Proposed verification.** OSS-WORLD-01/02: known dimensions, thin walls, rotating clearance and scale changes; no scoring from splat appearance alone. These checks have not been executed in this investigation.

### OSS-05

**SimITL — A complete firmware-plus-plant backend.** [GPLv3 text; submodules separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-05).

**Core and features observed.** The audited loop runs gyro updates, Betaflight or open-loop motor commands, and its own physical update at an 8 kHz substep. Its motor/physics source includes a battery, motors, thrust, gravity and rotor effects. The output boundary therefore belongs to a complete simulated aircraft, not just a flight-controller algorithm.

**User value.** Running actual firmware can make rates, modes and tuning familiar to pilots. It does not establish that the chosen motor/propeller/pack model matches their real drone.

**OpenRC decision.** A separate optional comparison backend. Do not combine its returned aircraft motion with a second OpenRC plant or silently replace the accepted-state solver.

**Proposed verification.** P25 mapped no-contact traces; P26 ownership/clock inspection. Declare the bundled firmware version and all plant parameters before interpreting differences. These checks have not been executed in this investigation.

### OSS-06

**libfpv — An engine-facing C API with explicit timing modes.** [GPL-3.0-or-later; dependency audit needed; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-06).

**Core and features observed.** The public header exposes a default threaded timing mode, manual fpv_step(), host-provided static collision surfaces and render-facing drone/camera data. Its runner starts a native simulation thread. It packages SimITL/Betaflight for host integration, so it shares that backend lineage rather than supplying an independent aerodynamic validation.

**User value.** A narrow API and reusable input/camera/OSD facilities can reduce integration effort for developers; the corresponding low-latency pilot benefit remains to be measured.

**OpenRC decision.** Evaluate manual mode in a separate comparison executable only if its contribution is needed and distribution terms are settled. Manual stepping is not evidence of arbitrary firmware checkpoint/restore.

**Proposed verification.** OSS-BRIDGE-04/06 and explicit clock/hidden-state inventory before considering any production integration. These checks have not been executed in this investigation.

### OSS-07

**OpenFPVSim — A headless experiment server with a Godot client.** [GPL code; font and part-data terms separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-07).

**Core and features observed.** Rust source defines a multi-rate scheduler, float64 FRD/NED physics, a separate Betaflight SITL bridge and a Godot-facing session architecture. Translation uses semi-implicit Euler and rotation midpoint RK2. The bridge warns that resending the initial UDP packet can add a firmware tick; its validation guide labels the thrust-stand example synthetic.

**User value.** Scripted input, identified parts and repeatable headless sessions could serve developers and pilots seeking reproducible tuning experiments. These are useful capabilities without a demonstrated physical-fidelity result.

**OpenRC decision.** A strong independent comparison candidate after aligning parameters, timing and disabled effects. Preserve the differences in integrator, firmware state, estimated parameters and license scope.

**Proposed verification.** OSS-REF-01…06 and OSS-BRIDGE-02/06: log actual consumed ticks and initial-resend events rather than relying on a general determinism claim. These checks have not been executed in this investigation.

### OSS-08

**Betaflight — The racing flight-controller behavior reference.** [GPL-3.0-or-later default; per-file scope; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-08).

**Core and features observed.** The inspected PID, RC and SITL platform code separates radio/rate processing, control/mixing and simulated IMU/motor boundaries. This is flight-controller firmware, not a rigid-body world or racing game. Its current development snapshot is distinct from the 2026.6.2 settings target already pinned in documents 07–09.

**User value.** Familiar rates and mode semantics can make practice transferable at the control-interface level. No inference of whole-drone accuracy follows merely from selecting the same firmware family.

**OpenRC decision.** Continue version-specific settings/reference-vector work. Consider a controller-only SITL research adapter after core transaction/replay work; do not silently upgrade existing defaults.

**Proposed verification.** Existing rate/import cases plus OSS-BRIDGE-01…06; match sensor units, motor order, firmware image and sample schedules. These checks have not been executed in this investigation.

### OSS-09

**INAV — Mode and simulated-receiver semantics for broader RC use.** [GPLv3 root; inspected PID allows later; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-09).

**Core and features observed.** The audited receiver simulation exposes channel values and frame status; PID and mixer sources supply a second concrete controller implementation. Navigation-oriented product scope does not mean those modes are already implemented in OpenRC, and a simulated receiver path alone is not a complete supported simulator bridge.

**User value.** Pilots who use more than one firmware family may value explicit differences in profiles, modes and failure status instead of deceptively interchangeable setting names.

**OpenRC decision.** Use as a separate settings/behavior reference. Preserve the 9.1.0 settings pin in 09; navigation/GPS capabilities and any production bridge remain separately admitted future work.

**Proposed verification.** Version/profile imports, receiver freshness and failure status, mode transitions and motor signs; refuse unsupported modes visibly. These checks have not been executed in this investigation.

### OSS-10

**RotorPy — Interpretable aerodynamic wrenches and wind experiments.** [MIT; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-10).

**Core and features observed.** The inspected scalar model uses first-order motor dynamics and an RK45 integration path. Body airspeed derives from velocity relative to wind; local rotor flow includes the hub’s rotational velocity. The code includes parasitic drag, rotor hub drag and optional flapping/lift effects. Its ground handling is a clamp/leveling policy, not a general contact solver.

**User value.** Readable equations and a lightweight Python interface help users understand why a maneuver changes. A user requested multiple vehicles for swarm/RL experiments; UR-07, not evidence of an FPV racing requirement.

**OpenRC decision.** First-choice offline aerodynamic reference for P25, starting with a matched subset and ground disabled. Richer terms are P16/M4 hypotheses; existing OpenRC rotor/body drag must not be counted twice.

**Proposed verification.** OSS-REF-02…08, including local airflow, wind-relative passivity and separate motor/plant step refinement. These checks have not been executed in this investigation.

### OSS-11

**gym-pybullet-drones — Explicit control rates, physics modes and research actions.** [MIT project code; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-11).

**Core and features observed.** BaseAviary requires an integer ratio between physics and control rates, holds controls through substeps and supports distinct dynamics/physics modes. Per-motor thrust uses RPM-squared coefficients; optional paths add ground effect, drag or downwash. Its direct dynamics path and PyBullet contact path are different experiments.

**User value.** Researchers ask for understandable action/controller boundaries and reproducible SITL setup. UR-03–05 document zero-motor-output confusion, sim-to-real integration questions and a request for direct collective-thrust/body-rate control.

**OpenRC decision.** Use clock/motor/frame modes as comparison fixtures. Do not equate its RPM command model, URDF data or optional downwash with an identified OpenRC racer.

**Proposed verification.** OSS-REF-03/05/06/08 and bridge setup diagnostics that distinguish a running process, valid packets and actual nonzero actuator output. These checks have not been executed in this investigation.

### OSS-12

**Flightmare flightlib — Independent physics and rendering with a transport boundary.** [MIT repository code; Unity separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-12).

**Core and features observed.** The source separates quadrotor dynamics, control, exponential motor response, RK4 integration and a rendering bridge. The world-box constraint resets selected state rather than supplying general collision response. Its code license does not license the Unity engine or automatically license separately downloaded scenes and renderer binaries.

**User value.** Separate physics and visuals can support headless experiments and richer cameras. Users reported a blocked render receive and uncertainty about drone/gate dimensions; UR-01/02.

**OpenRC decision.** Reference the existing OpenRC render boundary and use isolated motor-law comparisons. Bound any future renderer transport and keep visual delivery outside accepted physics authority.

**Proposed verification.** OSS-REF-04/08; renderer stall must not silently change accepted ticks, and displayed gate size must match qualified geometry. These checks have not been executed in this investigation.

### OSS-13

**multicopterDynamicsSim — Standalone rotor mechanics and angular-momentum checks.** [MIT; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-13).

**Core and features observed.** The independently licensed FlightGoggles dynamics submodule implements configurable motor transforms, thrust/torque, rotor acceleration reaction, rotor angular momentum, drag, RK4/Euler stepping and seedable process noise. This is a useful mechanics reference with its own exact license, distinct from FlightGoggles’ modified root grant.

**User value.** Developers can inspect motor/body coupling directly without adopting a complete graphics or robotics stack. That transparency is an inferred engineering benefit, not a claim of measured racer feel.

**OpenRC decision.** Second primary P25 reference. Reconcile spin, body frame, inertia definition and reaction torque; disable unmatched drag/noise before comparison.

**Proposed verification.** OSS-REF-02/03 and existing PHY-02 angular momentum/work cases, including asymmetric rotor acceleration and zero external torque. These checks have not been executed in this investigation.

### OSS-14

**Gazebo Sim (gz-sim) — Plugin lifecycle, simulation clocks and selectable contact engines.** [Apache-2.0 project code; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-14).

**Core and features observed.** The runner distinguishes simulation/wall time and phases systems through PreUpdate/Update/PostUpdate. The physics system delegates to a selected physics engine. Its multicopter motor plugin includes filtered command, thrust, drag and reaction torque, and explicitly credits RotorS lineage.

**User value.** Modular sensors/worlds and explicit simulation services can make robotics integrations reusable. This is a platform capability, not evidence that a selected default quad flies like a racer.

**OpenRC decision.** Reference lifecycle, clock and engine-identity discipline. Use selected contact experiments externally if needed; do not install Gazebo as a second runtime physics owner.

**Proposed verification.** OSS-REF-05/08 and existing transactional observer cases; identify engine, version, materials, shapes and plugin configuration for each comparison. These checks have not been executed in this investigation.

### OSS-15

**Webots — Propellers with axial-flow terms inside a contact simulator.** [Apache-2.0 source; ODE terms separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-15).

**Core and features observed.** WbPropeller applies force at a thrust center and torque through ODE. Its model includes speed-squared and axial point-velocity terms, offering a concrete alternative to a speed-only propeller law. This is not evidence that the supplied coefficients describe the selected OpenRC propeller.

**User value.** Integrated worlds, sensors and contacts can help users test whole robot scenarios. That convenience has different goals from low-latency manual FPV practice.

**OpenRC decision.** Study an isolated axial-velocity/thrust/torque sweep as an M4 candidate. Inspect ODE and model/asset notices separately; the root Apache grant does not cover every bundled component.

**Proposed verification.** P16 held-out propeller data plus OSS-REF-02/08; distinguish a richer equation from a validated coefficient fit. These checks have not been executed in this investigation.

### OSS-16

**Data-Driven MPC for Quadrotors — Learn residual aerodynamics around an explicit nominal model.** [GPL-3.0-or-later in inspected source; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-16).

**Core and features observed.** The source clips direct thrust commands, advances a lightweight RK4 model and supports body-frame drag and GP augmentation in the optimization path. It studies corrections to a nominal model rather than supplying an electrical motor/pack simulation or a ready-made human FPV product.

**User value.** A reproducible nominal-versus-residual comparison can help researchers explain systematic model error. It does not prove that adding machine learning improves OpenRC’s unmeasured racer.

**OpenRC decision.** P16/M4 only, after selected-build data and timing/frame checks. Verify dataset, learned-weight and dependency rights separately from GPL code.

**Proposed verification.** OSS-DATA-01: whole-flight/build hold-outs, explicit out-of-domain behavior, time-offset negative control and per-regime residuals. These checks have not been executed in this investigation.

### OSS-17

**RPG Quadrotor Control — An autonomous trajectory controller as a reproducible test pilot.** [MIT; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-17).

**Core and features observed.** The inspected position controller computes acceleration, attitude/collective and rate or attitude references, with an optional drag-compensated path. Its RotorS interface is an integration layer. This is a controller family, not another independent flight-physics solver or Betaflight implementation.

**User value.** A scripted pilot can repeat maneuvers while a developer changes one plant parameter. This supports experiments; it does not replace manual Acro or establish human skill transfer.

**OpenRC decision.** Optional later trajectory/excitation reference, with an explicit controller/input identity. No autonomy requirement is added to M1–M3.

**Proposed verification.** Preserve normal arm/hold/reset and accepted input tapes; repeat the same trajectory request with complete identified controller state. These checks have not been executed in this investigation.

### OSS-18

**PX4-Autopilot — An explicit simulated-sensor and actuator bridge.** [BSD-3-Clause code; docs CC BY 4.0; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-18).

**Core and features observed.** SimulatorMavlink serializes armed actuator output and handles HIL sensor messages with conditional lockstep behavior. The rate controller maps manual inputs into rate/torque setpoints. Build flags, time handling and thread scheduling matter; the existence of lockstep code is not a general determinism guarantee.

**User value.** A supported sensor/actuator seam can let a real controller run against an external plant. This is a useful engineering boundary, not Betaflight-equivalent behavior.

**OpenRC decision.** Borrow the boundary specification discipline now. Any PX4 product integration is optional after the local M3 route, with source/docs/dependency terms kept distinct.

**Proposed verification.** OSS-BRIDGE-01…06; verify message update masks, time, float conversion, arm status and motor ordering. These checks have not been executed in this investigation.

### OSS-19

**ArduPilot — External flight dynamics through a deliberately asymmetric protocol.** [GPL-3.0-or-later inspected SITL; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-19).

**Core and features observed.** The external JSON FDM path sends binary servo/PWM packets containing a frame count and rate, then receives JSON sensor records. It validates mandatory fields, has timeout/re-send behavior and supports a no-lockstep option. A separate built-in multicopter model also exists; these are distinct authority choices.

**User value.** Users can substitute their own plant, but reported connection/display and failsafe-injection confusion shows why every boundary needs observable state; UE-01/02.

**OpenRC decision.** Reference bridge diagnostics and mandatory-field handling. Do not assume the interface is JSON in both directions or that a retry is an idempotent controller step. Defer a product bridge until after M3.

**Proposed verification.** OSS-BRIDGE-01…05 plus separate injected failures at RC delivery, sensor transport and actuator output. These checks have not been executed in this investigation.

### OSS-20

**MAVLink — Versioned wire messages with explicit units and field presence.** [MIT XML/generated C; generator/other outputs separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-20).

**Core and features observed.** Common message definitions specify manual control, HIL actuator output and HIL sensors, including timestamps, flags and units. The generator, message definitions and generated headers have distinct grants. A message schema specifies an interchange format; it does not provide an estimator, clock guarantee, plant or RF model.

**User value.** Named fields and established peers can reduce integration ambiguity. Missing messages or unsupported fields must remain visible instead of being filled with invented values.

**OpenRC decision.** Optional narrow telemetry/experiment adapter after M3. Preserve OpenRC’s typed internal state; map only an admitted dialect/message subset.

**Proposed verification.** Version/dialect, field/update-mask, units, timebase, peer identity and freshness conformance; inspect specific-force conventions rather than trusting a frame label alone. These checks have not been executed in this investigation.

### OSS-21

**MAVSDK — Typed asynchronous automation outside the simulation transaction.** [BSD-3-Clause; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-21).

**Core and features observed.** The SDK supplies connection paths, telemetry handlers and offboard setpoint scheduling. The inspected offboard path requires a setpoint before starting and repeatedly sends configured commands. It is a client of a compatible vehicle, not a flight controller or simulation core.

**User value.** An external developer can automate experiments with less packet-level code. UE-03 shows that a connection does not guarantee a requested timestamp callback will be delivered.

**OpenRC decision.** Optional post-M3 tooling or separate research automation. Keep network callbacks outside the physics transaction and identify supported messages/capabilities.

**Proposed verification.** Observe connection, message availability, source timestamp and command acceptance separately; bound callback queues and stale-command handling. These checks have not been executed in this investigation.

### OSS-22

**QGroundControl — Joystick calibration data and separate guided sensor workflows.** [Apache-2.0 OR GPLv3; Qt notice applies; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-22).

**Core and features observed.** The joystick code stores calibration/deadband settings and adjusts raw axis ranges; separate sensor-calibration code drives visible progress/state. The project documents a license choice and Qt conditions, so copying the desktop application brings more obligations than borrowing its UX requirements.

**User value.** A historical user could not complete calibration because the throttle appeared to cover only half its range; UE-04. Visible raw extrema, center and normalized output directly help diagnose such cases.

**OpenRC decision.** Strengthen P10/P18/P22 with independent Godot-native diagnostics. Do not add a ground-control application or MAVLink requirement to ordinary USB-radio setup.

**Proposed verification.** OSS-UX-01 plus INPUT/CFG cases for asymmetric throttle, axis reversal, reconnect and persisted per-device mapping. These checks have not been executed in this investigation.

### OSS-23

**EdgeTX — Transmitter shaping and USB channel assignment as upstream input state.** [GPLv2 inspected mixer; fonts separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-23).

**Core and features observed.** Transmitter-side source captures calibration midpoints/extrema, applies input expo and declares USB joystick axis/button assignments. Consequently the game may receive already-shaped and remapped channels. A USB connection alone does not reproduce radio-link behavior.

**User value.** Users want their real transmitter to be recognized with correct channels. UE-05/06 document a mapping mismatch and a version/platform-specific recognition report, without establishing universal incompatibility.

**OpenRC decision.** Use generic calibrated input and an inspectable mapping, not embedded transmitter firmware. Show the possibility of transmitter-side shaping and avoid accidental duplicate expo.

**Proposed verification.** OSS-UX-01; run actual supported OS/device/version combinations and preserve fresh low-throttle/arm requirements after reconnect. These checks have not been executed in this investigation.

### OSS-24

**ExpressLRS — Separate input delivery quality from radio propagation.** [GPLv3 text; variant/file audit needed; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-24).

**Core and features observed.** The inspected code implements seeded frequency-hop sequences, a rolling received-period link-quality statistic, and OTA packet packing/CRC. These mechanisms describe protocol behavior; they are not a geometry-aware RF propagation model or an end-to-end latency measurement.

**User value.** Users care whether a chosen rate connects and whether a link recovers after failure; UE-07/08. Nominal packet frequency alone does not answer those questions.

**OpenRC decision.** Keep normal M2/M3 input pristine. If impairment research is useful, introduce an explicitly synthetic seeded delay/drop/reconnect model with a separate identity; make no ELRS-emulation claim.

**Proposed verification.** Recorded delivery times, repeatable seed, explicit stale/lost/reconnected transitions and failsafe policy; measure real hardware before claiming representative latency. These checks have not been executed in this investigation.

### OSS-25

**Betaflight Blackbox Explorer — Readable tuning evidence with aligned signals and honest graph scales.** [GPLv3 text; formats/media separate; exact pin and source evidence](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md#oss-25).

**Core and features observed.** The parser decodes frame encodings/predictors, the flight-log layer assembles time series and the spectrum path can apply a Hann window to selected data before an FFT when that option is enabled. This is an analysis tool, not an OpenRC replay engine. Its pinned README announces a feature freeze/move into the Betaflight App and a future archive date, so do not assume long-term standalone development.

**User value.** A project member requested locked graph scales because auto-ranging can visually invert a noise comparison; UE-10. This directly supports units, fixed shared scales and clearly labeled processing.

**OpenRC decision.** Use existing free tools and read-only exports first. Preserve actual firmware Blackbox files for firmware runs; keep OpenRC `.orfl` authoritative and expose its completeness separately.

**Proposed verification.** OSS-UX-02/03 plus sampling/Nyquist and timestamp checks; a diagnostic plot cannot repair an incomplete recorder or rewrite a valid finish. These checks have not been executed in this investigation.

## What the user evidence changes

| Observed need | Supporting records in 15 | Concrete consequence |
| --- | --- | --- |
| Understand why a radio will not calibrate or map correctly | UE-04/05/06 | Show raw axes, extrema, center, reversal, mapping, device identity and normalized output in P22 |
| Tell whether a bridge is connected, producing valid data and using the expected clock | UR-01/03; UE-01/03 | Separate process, transport, message, sensor, controller and actuator diagnostics |
| Understand which controller/action boundary an experiment uses | UR-04/05 | Separate controller-only SITL, direct thrust/rate actions and a complete foreign plant |
| See gate scale and justify timing decisions | UR-02; UE-09; UM-01 | Metric collision views and retained committed decision evidence; UI does not infer authority |
| Compare tuning/noise without misleading graphs | UE-10 | Shared fixed axes, explicit units, time alignment and processing labels |
| Trust reconnect and failsafe experiments | UE-02/07/08 | Inject and record failure at the specific boundary; packet rate alone is not latency evidence |
| Reach a focused, repeatable practice session | UR-06/08 | Validate the exported route, restart/rearm, saved settings and local practice journey |
| Extend research without taking over the product | UR-07 | Optional headless experiment adapters; no swarm/autonomy dependency for racing |

Most rows are requests or friction reports rather than satisfaction measurements. The proper product conclusion is “make this observable and test it,” not “most pilots prefer this architecture.” Keep previously planned pilot studies and physical comparisons separately scoped.

## Recommended shortlist

**Use first for research:** RotorPy and multicopterDynamicsSim for independent mechanics comparisons; Flightmare for an isolated motor-law check; Betaflight/INAV for pinned settings semantics; EdgeTX/QGroundControl for input-boundary requirements; Blackbox Explorer and existing free plotting tools for read-only evidence.

**Evaluate as optional separate backends:** Open FPV Sim, SimITL and libfpv. Choose by a specific missing capability and state/clock contract, not by a “real firmware” label. Their use of shared firmware/backend code must remain visible in comparisons.

**Keep as later capabilities:** scanned worlds, MAVLink/PX4/ArduPilot integration, link impairment, autonomous test pilots and learned residual models. Reuse their useful design ideas while preserving M0 → M1 → M2 → M3 and separately measured M4 promotion. See [14](14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md) for package ownership, stop conditions and proposed acceptance cases.
