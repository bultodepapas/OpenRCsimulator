# Open-source license, source and user evidence ledger

**Checked:** 11 November 2026. **OpenRC baseline:** [`7bff78490f9af5c1664f47c8ba865a92b3430920`](https://github.com/bultodepapas/OpenRCsimulator/tree/7bff78490f9af5c1664f47c8ba865a92b3430920). **Companions:** [13 approaches](13_OPEN_SOURCE_FPV_AND_DRONE_APPROACHES.md), [14 decisions and experiments](14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md). This file owns the evidence for this open-source follow-up; 06, 09 and 12 retain the earlier OpenRC, firmware-settings and broader product evidence.

## 1. Method and limits

The investigation inspected exact repository revisions, literal license/notice files and selected implementation paths. Bare/sparse Git objects or retrieved primary source files supplied the evidence; no third-party build scripts were executed. The audit checks code presence and implementation structure, not a running binary, accuracy, performance, complete dependency closure or every asset's provenance. Source pin/path checks and document checks are distinct from simulation tests.

**Admission rule:** count a separately identified project with inspectable source, a recognizable open-source grant for the scoped project code, and a concrete implemented capability or machine-readable protocol definition relevant to FPV/drone development. Do not count every fork, edition, README feature or reused physics law as an independent project/validation. The set contains 25 admitted project investigations, plus eight excluded or qualified examples. A source-available repository without an established grant, or one with use restrictions, is not admitted just because its README calls it open source. The [Open Source Definition](https://opensource.org/osd) distinguishes source availability from distribution/modification rights and unrestricted fields of endeavor.

Licenses below describe inspected evidence and scope, not a certification of every file or a particular future distribution. A root license does not automatically cover dependencies, firmware blobs, fonts, audio, trademarks, scanned scenes, datasets or trained weights. Where a GPL license text alone does not settle “only” versus “or later,” that uncertainty is retained. Historical pins are not claims of abandonment; development HEADs are not promises of stable release compatibility.

OpenRC's own [pinned LICENSE](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/LICENSE) is MIT. Its assets have separate provenance. Copying/porting/linking a component needs a component-specific decision; a process boundary alone does not settle combination/redistribution questions. The [GNU GPL FAQ on aggregation](https://www.gnu.org/licenses/gpl-faq.html#MereAggregation) is a primary explanation of why architecture and license scope must both be examined.

## 2. Source records for the 25 counted approaches

### OSS-01

**KwadSim — A Godot-native racing/practice shell.** [Repository](https://github.com/timower/KwadSim) · [inspected tree](https://github.com/timower/KwadSim/tree/fb5c8b252cb438296100452c609eb84b6dc638fa).

**Exact commit:** `fb5c8b252cb438296100452c609eb84b6dc638fa`. **Snapshot context:** 2020-02-18T21:05:40+01:00.

**License scope:** Actual root LICENSE contains GPL version 3 text. No project-wide explicit only-or-later qualification was established in inspected files. Check each asset and addon; root license does not verify every external asset.

License/notice evidence: [LICENSE](https://github.com/timower/KwadSim/blob/fb5c8b252cb438296100452c609eb84b6dc638fa/LICENSE); [addons/gut/LICENSE.md](https://github.com/timower/KwadSim/blob/fb5c8b252cb438296100452c609eb84b6dc638fa/addons/gut/LICENSE.md).

Inspected implementation:

- [Script/Kwad/Kwad.gd](https://github.com/timower/KwadSim/blob/fb5c8b252cb438296100452c609eb84b6dc638fa/Script/Kwad/Kwad.gd#L153): get_input, calc_pid, calc_mixer and calc_motor implement a local rate/PID/mixer/prop model; _physics_process invokes these plus drag and ground effect.
- [Script/LapTimes.gd](https://github.com/timower/KwadSim/blob/fb5c8b252cb438296100452c609eb84b6dc638fa/Script/LapTimes.gd#L57): gate_entered provides a racing/lap mechanism.
- [Script/Kwad/Packets.gd](https://github.com/timower/KwadSim/blob/fb5c8b252cb438296100452c609eb84b6dc638fa/Script/Kwad/Packets.gd#L35): InitPacket and StatePacket define data structures used at a simulator boundary.

**Evidence limits:** Pinned HEAD is from 2020; this does not prove the whole project was abandoned. Uses Godot 3.2 and its own physics path; do not assume the inspected Kwad.gd path uses Betaflight firmware or has modern Godot 4 compatibility.

### OSS-02

**FlowState — Checkpoint metadata and editable-track goals.** [Repository](https://github.com/brucesdad13/FlowState) · [inspected tree](https://github.com/brucesdad13/FlowState/tree/75403a07730f621b7d1413da21e7c22102757135).

**Exact commit:** `75403a07730f621b7d1413da21e7c22102757135`. **Snapshot context:** 2018-12-08T12:40:37-07:00.

**License scope:** Actual root LICENSE contains GPLv3 text. Inspected text does not establish an explicit version election for all content or verify individual assets, sounds, logos and third-party engine terms.

License/notice evidence: [LICENSE](https://github.com/brucesdad13/FlowState/blob/75403a07730f621b7d1413da21e7c22102757135/LICENSE).

Inspected implementation:

- [scripts/gameUtils.py](https://github.com/brucesdad13/FlowState/blob/75403a07730f621b7d1413da21e7c22102757135/scripts/gameUtils.py#L52): The readable Python utility assigns checkpoint metadata and IDs.
- [scripts/gameUtils.py](https://github.com/brucesdad13/FlowState/blob/75403a07730f621b7d1413da21e7c22102757135/scripts/gameUtils.py#L87): setDefaults stores camera tilt, rates, radio channels/calibration and track/lap state.
- [README.md](https://github.com/brucesdad13/FlowState/blob/75403a07730f621b7d1413da21e7c22102757135/README.md): The project philosophy prioritizes low-latency FPV perception, editable tracks, lap practice and offline use; these are goals, not measured outcomes.

**Evidence limits:** Inspected brucesdad13 repository HEAD is 2018; README points to skyfpv/FlowState, which could not be cloned during this audit. The relationship and current upstream status are unverified. Most game material is in game.blend; flight physics internals and imported asset licenses were not inspected.

### OSS-03

**WebFPVSimulator — Real flight firmware compiled to WebAssembly.** [Repository](https://github.com/Mathew-Harvey/WebFPVSimulator) · [inspected tree](https://github.com/Mathew-Harvey/WebFPVSimulator/tree/3dcb9b31ce1383b4143295ce0bcf5312db2090c8).

**Exact commit:** `3dcb9b31ce1383b4143295ce0bcf5312db2090c8`. **Snapshot context:** 2026-11-11T12:56:12Z.

**License scope:** Actual LICENSE contains GPLv3 text and NOTICE says the combined work is GPLv3-or-later. NOTICE separately excludes specific third-party trademarks, recordings, logos and unresolved-origin items; check the exact files before any reuse. Vendored MIT components retain notices.

License/notice evidence: [LICENSE](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/LICENSE); [NOTICE](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/NOTICE); [src/maps/city/vendored/LICENSE](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/src/maps/city/vendored/LICENSE).

Inspected implementation:

- [src/native/sim.c](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/src/native/sim.c#L1726): sim_step consumes time-stamped inputs at 1 kHz, calls bridge_run and plant_step, then advances world state.
- [src/native/plant.c](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/src/native/plant.c#L1040): plant_step_body computes the simulated plant; bf/bf_glue.c bridge_run couples it to the firmware.
- [tests/verify.js](https://github.com/Mathew-Harvey/WebFPVSimulator/blob/3dcb9b31ce1383b4143295ce0bcf5312db2090c8/tests/verify.js): The repository provides a verification harness; README describes cross-runtime determinism checks, which were not run in this audit.

**Evidence limits:** Recent source snapshot and changing code; no real-world fidelity, WebAssembly build or reported test result was independently verified. NOTICE expressly excludes or flags multiple assets; no blanket claim that every repository asset is open-licensed.

### OSS-04

**ShramkoGSFPV — Scanned scenes with explicit collision and configurable scale.** [Repository](https://github.com/AndriiShramko/ShramkoGSFPV) · [inspected tree](https://github.com/AndriiShramko/ShramkoGSFPV/tree/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced).

**Exact commit:** `31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced`. **Snapshot context:** audited 2026-11-11; alpha development snapshot.

**License scope:** Root MIT grant verified. The separate NOTICE expressly requires preserving both NOTICE and LICENSE on redistribution. NOTICE separately scopes third-party MIT components, fdlibm/musl notices, externally loaded scenes and excluded supporter names/photos/reviews. The author describes independently implemented Betaflight formulas; this audit did not certify derivation or distribution compatibility.

License/notice evidence: [LICENSE](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/LICENSE); [NOTICE](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/NOTICE); [docs/PROVENANCE.md](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/docs/PROVENANCE.md).

Inspected implementation:

- [packages/collision/src/world.ts](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/packages/collision/src/world.ts#L66): VoxelContactWorld.sweepOne and bisect search swept sphere motion against a voxel occupancy grid, using inflated covers and a fixed spatial leaf tolerance.
- [packages/collision/src/transform.ts](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/packages/collision/src/transform.ts#L23): Explicit uniform scale and translation with positive finite scale; handles file-space XY flip, rebuilding metadata over existing voxel arrays.
- [packages/sim-core/src/sim.ts](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/packages/sim-core/src/sim.ts#L1): Float64Array state, 1 ms step, PlayCanvas Y-up world and right/up/back body; translational integration is semi-implicit Euler. Distinct from OpenRC NED/FRD 240 Hz RK4.
- [packages/sim-core/src/runner.ts](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/packages/sim-core/src/runner.ts#L720): Runner advances fixed ticks, consumes queued timestamped samples, limits catch-up work and records hitch counters; replay paths reference log and scene identities.
- [packages/input/src/calib.ts](https://github.com/AndriiShramko/ShramkoGSFPV/blob/31b1453ad9ea34bf84d823e0c1f9ba7c10a4bced/packages/input/src/calib.ts#L33): CalibrationWizard defines connect/stir/centre/axis/arm/check stages and records axis limits, centre, reversal and deadband.

**Evidence limits:** No build, flight, hardware input or collision accuracy test executed in this audit. A scanned visual scene is not automatically metric, watertight or redistributable. README labels hardware-radio evidence simulated; source claims and upstream test reports are not our independent qualification. The sweep contract is bounded by voxel occupancy, spatial leaf tolerance and supplied sphere/path padding, not a general proof for OpenRC rotating props.

### OSS-05

**SimITL — A complete firmware-plus-plant backend.** [Repository](https://github.com/AJ92/SimITL) · [inspected tree](https://github.com/AJ92/SimITL/tree/c881d55080ca852c8f0b5b219182b87c116526ed).

**Exact commit:** `c881d55080ca852c8f0b5b219182b87c116526ed`. **Snapshot context:** 2026-09-07T01:05:34+02:00.

**License scope:** Actual LICENSE contains GPL version 3 text; README calls it GPL v3. Exact only-or-later scope for this wrapper requires checking individual rights statements. Betaflight and other submodules have their own notices.

License/notice evidence: [LICENSE](https://github.com/AJ92/SimITL/blob/c881d55080ca852c8f0b5b219182b87c116526ed/LICENSE).

Inspected implementation:

- [src/sim/sim.cpp](https://github.com/AJ92/SimITL/blob/c881d55080ca852c8f0b5b219182b87c116526ed/src/sim/sim.cpp#L9): An 8 kHz fixed substep runs updateGyro, then either open-loop motor PWM or BF::update, then updatePhysics.
- [src/sim/physics.cpp](https://github.com/AJ92/SimITL/blob/c881d55080ca852c8f0b5b219182b87c116526ed/src/sim/physics.cpp#L500): Physics::calculateMotors and calculatePhysics model battery, motors, thrust, gravity and rotor effects; it is a physics backend as well as a firmware wrapper.
- [src/sim/bf.cpp](https://github.com/AJ92/SimITL/blob/c881d55080ca852c8f0b5b219182b87c116526ed/src/sim/bf.cpp#L134): BF::update advances firmware time and runs Betaflight integration.

**Evidence limits:** The inspected backend uses float-based internals and a different step rate/conventions; its output cannot be substituted silently for OpenRC state. Physical accuracy, performance, replay repeatability and the submodule build were not independently measured.

### OSS-06

**libfpv — An engine-facing C API with explicit timing modes.** [Repository](https://github.com/hammerill/libfpv) · [inspected tree](https://github.com/hammerill/libfpv/tree/82c3ad0b11d888ff13041f33223fbc819a43ecd7).

**Exact commit:** `82c3ad0b11d888ff13041f33223fbc819a43ecd7`. **Snapshot context:** 2026-11-10T08:48:23+01:00.

**License scope:** Actual root LICENSE contains GPLv3 text and README explicitly states GPL-3.0-or-later, with GPL compatibility implications for linked programs. Bundled submodules, patches, fonts and assets require their own notices and permissions.

License/notice evidence: [LICENSE](https://github.com/hammerill/libfpv/blob/82c3ad0b11d888ff13041f33223fbc819a43ecd7/LICENSE); [README.md](https://github.com/hammerill/libfpv/blob/82c3ad0b11d888ff13041f33223fbc819a43ecd7/README.md).

Inspected implementation:

- [include/libfpv.h](https://github.com/hammerill/libfpv/blob/82c3ad0b11d888ff13041f33223fbc819a43ecd7/include/libfpv.h#L168): fpv_timing_mode supports a real-time threaded path and FPV_TIMING_MANUAL host-driven fpv_step(); the default outer rate is 1 kHz.
- [include/libfpv.h](https://github.com/hammerill/libfpv/blob/82c3ad0b11d888ff13041f33223fbc819a43ecd7/include/libfpv.h#L292): fpv_static_surfaces_load takes host-provided collision meshes; fpv_drone_tick returns frame-facing pose/camera data.
- [src/sim/runner.cpp](https://github.com/hammerill/libfpv/blob/82c3ad0b11d888ff13041f33223fbc819a43ecd7/src/sim/runner.cpp#L94): A native simulation thread is started for the threaded path.

**Evidence limits:** GPL compatibility needs review before linking or distributing; dependencies and patches are part of the integration. This project owns a separate simulated aircraft and collision path; it is not just an input/controller library or a drop-in equivalent to OpenRC RK4.

### OSS-07

**OpenFPVSim — A headless experiment server with a Godot client.** [Repository](https://github.com/hugowis/open-fpv-sim) · [inspected tree](https://github.com/hugowis/open-fpv-sim/tree/d653d67a6e79ffcc662653a93af05dda0000a196).

**Exact commit:** `d653d67a6e79ffcc662653a93af05dda0000a196`. **Snapshot context:** 2026-11-01T21:09:33+01:00.

**License scope:** Actual root LICENSE is GPLv3 text; README identifies project GPL-3.0-or-later, one OSD font GPL-3.0-only, combined distribution GPL-3.0, and library/ part data CC-BY-SA-4.0. Treat third-party engine/assets separately.

License/notice evidence: [LICENSE](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/LICENSE); [README.md](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/README.md); [godot/ui/OSD_FONT_LICENSE.md](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/godot/ui/OSD_FONT_LICENSE.md).

Inspected implementation:

- [crates/ofs-core/src/scheduler.rs](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/crates/ofs-core/src/scheduler.rs#L55): A fixed-order, multi-rate scheduler steps typed models.
- [crates/ofs-physics/src/rigid_body.rs](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/crates/ofs-physics/src/rigid_body.rs#L257): FRD/NED float64 rigid-body step uses semi-implicit Euler for translation and midpoint RK2 for rotation, rather than OpenRC 240 Hz RK4.
- [crates/ofs-fc/src/sitl/bridge.rs](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/crates/ofs-fc/src/sitl/bridge.rs#L220): The UDP SITL bridge warns an initial resend can introduce an extra firmware tick, limiting deterministic claims.
- [docs/validation.md](https://github.com/hugowis/open-fpv-sim/blob/d653d67a6e79ffcc662653a93af05dda0000a196/docs/validation.md#L93): The included thrust-stand worked example is explicitly synthetic; blackbox step comparator is not yet implemented for real data.

**Evidence limits:** Most parameters are estimated per validation.md; examples cannot establish physical fidelity. An 8 kHz base rate, different integrators, a separate process and gRPC introduce a different architecture and additional integration overhead. No build or benchmarks were run.

### OSS-08

**Betaflight — The racing flight-controller behavior reference.** [Repository](https://github.com/betaflight/betaflight) · [inspected tree](https://github.com/betaflight/betaflight/tree/f97bdbcf57316d86519cf981d17590bcdbe303d6).

**Exact commit:** `f97bdbcf57316d86519cf981d17590bcdbe303d6`. **Snapshot context:** 2026-11-11T14:36:27+11:00.

**License scope:** Actual LICENSE is GPLv3 text. DEFAULT_LICENSE.md states version 3 or any later for Betaflight; individual files, bundled libraries and assets may carry different notices.

License/notice evidence: [LICENSE](https://github.com/betaflight/betaflight/blob/f97bdbcf57316d86519cf981d17590bcdbe303d6/LICENSE); [DEFAULT_LICENSE.md](https://github.com/betaflight/betaflight/blob/f97bdbcf57316d86519cf981d17590bcdbe303d6/DEFAULT_LICENSE.md).

Inspected implementation:

- [src/main/flight/pid.c](https://github.com/betaflight/betaflight/blob/f97bdbcf57316d86519cf981d17590bcdbe303d6/src/main/flight/pid.c#L1141): pidController implements a flight-control loop; mixer.c converts control output to motor outputs.
- [src/platform/SIMULATOR/sitl.c](https://github.com/betaflight/betaflight/blob/f97bdbcf57316d86519cf981d17590bcdbe303d6/src/platform/SIMULATOR/sitl.c#L305): SITL maps simulated IMU rates to gyro axes and its platform motor code publishes motor data.
- [src/main/fc/rc.c](https://github.com/betaflight/betaflight/blob/f97bdbcf57316d86519cf981d17590bcdbe303d6/src/main/fc/rc.c): The flight controller processes radio input and rate behavior separately from any environment model.

**Evidence limits:** Firmware is not a rigid-body plant, world, renderer or complete human-facing simulator. A continuously changing firmware HEAD is not the version bundled with every simulator; pin version and settings for valid comparisons.

### OSS-09

**INAV — Mode and simulated-receiver semantics for broader RC use.** [Repository](https://github.com/iNavFlight/inav) · [inspected tree](https://github.com/iNavFlight/inav/tree/fca135ce57c28393b20b1e5c9af6b27bff0479da).

**Exact commit:** `fca135ce57c28393b20b1e5c9af6b27bff0479da`. **Snapshot context:** 2026-11-11T00:11:03-06:00.

**License scope:** Actual root LICENSE contains GPLv3. The inspected src/main/flight/pid.c header explicitly allows version 3 or later; check other files and bundled libraries individually.

License/notice evidence: [LICENSE](https://github.com/iNavFlight/inav/blob/fca135ce57c28393b20b1e5c9af6b27bff0479da/LICENSE); [src/main/flight/pid.c](https://github.com/iNavFlight/inav/blob/fca135ce57c28393b20b1e5c9af6b27bff0479da/src/main/flight/pid.c).

Inspected implementation:

- [src/main/flight/pid.c](https://github.com/iNavFlight/inav/blob/fca135ce57c28393b20b1e5c9af6b27bff0479da/src/main/flight/pid.c#L2091): pidController and rate-controller functions implement flight-controller behavior.
- [src/main/rx/sim.c](https://github.com/iNavFlight/inav/blob/fca135ce57c28393b20b1e5c9af6b27bff0479da/src/main/rx/sim.c#L42): rxSimSetChannelValue and rxSimFrameStatus provide simulated receiver channels/status.
- [src/main/flight/mixer.c](https://github.com/iNavFlight/inav/blob/fca135ce57c28393b20b1e5c9af6b27bff0479da/src/main/flight/mixer.c): The firmware includes actuator mixing, separate from an external physics model.

**Evidence limits:** INAV is flight firmware, not a ready-made OpenRC flight model or renderer. HEAD is active at the observed timestamp but this is not a compatibility or long-term maintenance guarantee; no SITL was run.

### OSS-10

**RotorPy — Interpretable aerodynamic wrenches and wind experiments.** [Repository](https://github.com/spencerfolk/rotorpy) · [inspected tree](https://github.com/spencerfolk/rotorpy/tree/40b09697a6a1596d404a67f459941d46a39eedd3).

**Exact commit:** `40b09697a6a1596d404a67f459941d46a39eedd3`. **Snapshot context:** 2026-09-07.

**License scope:** Root LICENSE.md contains canonical MIT text for repository software; inspect separate dependency and asset terms.

License/notice evidence: [License / source notice](https://github.com/spencerfolk/rotorpy/blob/40b09697a6a1596d404a67f459941d46a39eedd3/LICENSE.md).

Inspected implementation:

- [rotorpy/vehicles/multirotor.py](https://github.com/spencerfolk/rotorpy/blob/40b09697a6a1596d404a67f459941d46a39eedd3/rotorpy/vehicles/multirotor.py#L226): Inspected: Multirotor.step, _s_dot_fn, compute_body_wrench, _handle_vehicle_on_ground
- [rotorpy/simulate.py](https://github.com/spencerfolk/rotorpy/blob/40b09697a6a1596d404a67f459941d46a39eedd3/rotorpy/simulate.py#L30): Inspected: simulate

**Evidence limits:** Different integrators and coefficients can cause trajectory differences; no physical-accuracy claim. SciPy, Python, torch, world/assets and data have separate terms.

### OSS-11

**gym-pybullet-drones — Explicit control rates, physics modes and research actions.** [Repository](https://github.com/learnsyslab/gym-pybullet-drones) · [inspected tree](https://github.com/learnsyslab/gym-pybullet-drones/tree/348b5c18a4bb770a48928b9d044decf77ca33302).

**Exact commit:** `348b5c18a4bb770a48928b9d044decf77ca33302`. **Snapshot context:** 2026-11-05.

**License scope:** Root LICENSE is canonical MIT for repository software; separately check PyBullet, models and assets.

License/notice evidence: [License / source notice](https://github.com/learnsyslab/gym-pybullet-drones/blob/348b5c18a4bb770a48928b9d044decf77ca33302/LICENSE).

Inspected implementation:

- [gym_pybullet_drones/envs/BaseAviary.py](https://github.com/learnsyslab/gym-pybullet-drones/blob/348b5c18a4bb770a48928b9d044decf77ca33302/gym_pybullet_drones/envs/BaseAviary.py#L258): Inspected: BaseAviary.step, _physics, _groundEffect, _drag, _dynamics

**Evidence limits:** Physics mode, URDF, rotor numbering and frame alter outcomes; not a drop-in Godot physics replacement. PyBullet/Bullet, Gymnasium, model/URDF assets require separate license review.

### OSS-12

**Flightmare flightlib — Independent physics and rendering with a transport boundary.** [Repository](https://github.com/uzh-rpg/flightmare) · [inspected tree](https://github.com/uzh-rpg/flightmare/tree/d4218aedac18cbe9364a0a0df10ab992c4b65e4f).

**Exact commit:** `d4218aedac18cbe9364a0a0df10ab992c4b65e4f`. **Snapshot context:** 2023-05-15.

**License scope:** Root LICENSE is canonical MIT for repository code, including inspected flightlib files; it does not grant rights to Unity engine or separately obtained binaries/scenes/assets.

License/notice evidence: [License / source notice](https://github.com/uzh-rpg/flightmare/blob/d4218aedac18cbe9364a0a0df10ab992c4b65e4f/LICENSE).

Inspected implementation:

- [flightlib/src/objects/quadrotor.cpp](https://github.com/uzh-rpg/flightmare/blob/d4218aedac18cbe9364a0a0df10ab992c4b65e4f/flightlib/src/objects/quadrotor.cpp#L27): Inspected: Quadrotor::run, runFlightCtl, runMotors, constrainInWorldBox, updateDynamics
- [flightlib/src/dynamics/quadrotor_dynamics.cpp](https://github.com/uzh-rpg/flightmare/blob/d4218aedac18cbe9364a0a0df10ab992c4b65e4f/flightlib/src/dynamics/quadrotor_dynamics.cpp#L26): Inspected: QuadrotorDynamics::dState, motorOmegaToThrust, getAllocationMatrix

**Evidence limits:** Snapshot from 2023; renderer binary provenance, version and redistribution permission not verified. Matching first-order motor updates does not validate drag, contacts or whole vehicle. Unity engine, separately downloaded executables, scenes, trained weights and assets are outside root code license grant.

### OSS-13

**multicopterDynamicsSim — Standalone rotor mechanics and angular-momentum checks.** [Repository](https://github.com/mit-fast/multicopterDynamicsSim) · [inspected tree](https://github.com/mit-fast/multicopterDynamicsSim/tree/7e799751f83c72977a42d269da45a84264d6f1a5).

**Exact commit:** `7e799751f83c72977a42d269da45a84264d6f1a5`. **Snapshot context:** 2021-05-29.

**License scope:** Canonical MIT root LICENSE for this separate repository; do not conflate with FlightGoggles parent license.

License/notice evidence: [License / source notice](https://github.com/mit-fast/multicopterDynamicsSim/blob/7e799751f83c72977a42d269da45a84264d6f1a5/LICENSE).

Inspected implementation:

- [multicopterDynamicsSim.cpp](https://github.com/mit-fast/multicopterDynamicsSim/blob/7e799751f83c72977a42d269da45a84264d6f1a5/multicopterDynamicsSim.cpp#L358): Inspected: getThrust, getControlMoment, getDragForce, proceedState_RK4, getMotorSpeedDerivative, getAngularVelocityDerivative

**Evidence limits:** 2021 snapshot; reconcile integrator stages, rotor inertia convention, gravity, and aerodynamic effects. No battery/contact validation. Eigen and included IMU-related code have their own licenses and versions.

### OSS-14

**Gazebo Sim (gz-sim) — Plugin lifecycle, simulation clocks and selectable contact engines.** [Repository](https://github.com/gazebosim/gz-sim) · [inspected tree](https://github.com/gazebosim/gz-sim/tree/de7dd3c71e4f7abfbd68e58d8f4970b5763625fa).

**Exact commit:** `de7dd3c71e4f7abfbd68e58d8f4970b5763625fa`. **Snapshot context:** 2026-11-10.

**License scope:** Root Apache-2.0 license applies to inspected project source; plugins, gz-physics engines and assets may have distinct licenses.

License/notice evidence: [License / source notice](https://github.com/gazebosim/gz-sim/blob/de7dd3c71e4f7abfbd68e58d8f4970b5763625fa/LICENSE).

Inspected implementation:

- [src/SimulationRunner.cc](https://github.com/gazebosim/gz-sim/blob/de7dd3c71e4f7abfbd68e58d8f4970b5763625fa/src/SimulationRunner.cc#L394): Inspected: SimulationRunner::UpdateCurrentInfo, UpdateSystems
- [src/systems/physics/Physics.cc](https://github.com/gazebosim/gz-sim/blob/de7dd3c71e4f7abfbd68e58d8f4970b5763625fa/src/systems/physics/Physics.cc#L1195): Inspected: Physics::Update
- [src/systems/multicopter_motor_model/MulticopterMotorModel.cc](https://github.com/gazebosim/gz-sim/blob/de7dd3c71e4f7abfbd68e58d8f4970b5763625fa/src/systems/multicopter_motor_model/MulticopterMotorModel.cc#L393): Inspected: MulticopterMotorModel::PreUpdate, UpdateForcesAndMoments

**Evidence limits:** Development branch snapshot, not necessarily stable release; does not justify replacing OpenRC core. Selected gz-physics engine, transport, sensors, plugins, world assets and dependencies are separate.

### OSS-15

**Webots — Propellers with axial-flow terms inside a contact simulator.** [Repository](https://github.com/cyberbotics/webots) · [inspected tree](https://github.com/cyberbotics/webots/tree/f6e94fe50753b92bd3fb470316b9fca362fa3aaf).

**Exact commit:** `f6e94fe50753b92bd3fb470316b9fca362fa3aaf`. **Snapshot context:** 2026-11-11.

**License scope:** Root Apache-2.0 and Apache header on inspected WbPropeller code; bundled ODE and third-party libraries have separate terms.

License/notice evidence: [License / source notice](https://github.com/cyberbotics/webots/blob/f6e94fe50753b92bd3fb470316b9fca362fa3aaf/LICENSE).

Inspected implementation:

- [src/webots/nodes/WbPropeller.cpp](https://github.com/cyberbotics/webots/blob/f6e94fe50753b92bd3fb470316b9fca362fa3aaf/src/webots/nodes/WbPropeller.cpp#L200): Inspected: WbPropeller::prePhysicsStep
- [src/webots/nodes/WbSolid.cpp](https://github.com/cyberbotics/webots/blob/f6e94fe50753b92bd3fb470316b9fca362fa3aaf/src/webots/nodes/WbSolid.cpp#L2081): Inspected: WbSolid force/torque interface
- [src/ode/COPYING](https://github.com/cyberbotics/webots/blob/f6e94fe50753b92bd3fb470316b9fca362fa3aaf/src/ode/COPYING#L1): Inspected: ODE license statement

**Evidence limits:** ODE COPYING reports LGPL-2.1-or-later or modified BSD choices and third-party terms; it references LICENSE-BSD.TXT absent at the stated path in this snapshot. Resolve before code reuse. This is a development snapshot. ODE, ODE subcomponents, external models, resources and assets require independent license review.

### OSS-16

**Data-Driven MPC for Quadrotors — Learn residual aerodynamics around an explicit nominal model.** [Repository](https://github.com/uzh-rpg/data_driven_mpc) · [inspected tree](https://github.com/uzh-rpg/data_driven_mpc/tree/a6be5d301e66d91a823ef68a29c79ccc5829f1b9).

**Exact commit:** `a6be5d301e66d91a823ef68a29c79ccc5829f1b9`. **Snapshot context:** 2021-03-14.

**License scope:** Root file contains GPL version 3 text; inspected quad_3d.py and quad_3d_optimizer.py headers explicitly say version 3 or later. Do not infer every file variant solely from the root text. Reuse/distribution has copyleft implications.

License/notice evidence: [License / source notice](https://github.com/uzh-rpg/data_driven_mpc/blob/a6be5d301e66d91a823ef68a29c79ccc5829f1b9/LICENSE).

Inspected implementation:

- [ros_gp_mpc/src/quad_mpc/quad_3d.py](https://github.com/uzh-rpg/data_driven_mpc/blob/a6be5d301e66d91a823ef68a29c79ccc5829f1b9/ros_gp_mpc/src/quad_mpc/quad_3d.py#L175): Inspected: Quadrotor3D.update, f_vel
- [ros_gp_mpc/src/quad_mpc/quad_3d_optimizer.py](https://github.com/uzh-rpg/data_driven_mpc/blob/a6be5d301e66d91a823ef68a29c79ccc5829f1b9/ros_gp_mpc/src/quad_mpc/quad_3d_optimizer.py#L341): Inspected: quad_dynamics, v_dynamics
- [ros_gp_mpc/src/quad_mpc/quad_3d.py](https://github.com/uzh-rpg/data_driven_mpc/blob/a6be5d301e66d91a823ef68a29c79ccc5829f1b9/ros_gp_mpc/src/quad_mpc/quad_3d.py#L1): Inspected: file GPL-3.0-or-later notice

**Evidence limits:** GPL review required before incorporation/distribution; older ROS, acados and Python stack. Model weights/data terms and transferability are separate. ROS, acados, CasADi, learned models and data need separate provenance/license checks.

### OSS-17

**RPG Quadrotor Control — An autonomous trajectory controller as a reproducible test pilot.** [Repository](https://github.com/uzh-rpg/rpg_quadrotor_control) · [inspected tree](https://github.com/uzh-rpg/rpg_quadrotor_control/tree/22b55b085546a3322c302a68c2b67108a092a298).

**Exact commit:** `22b55b085546a3322c302a68c2b67108a092a298`. **Snapshot context:** 2021-02-25.

**License scope:** Canonical MIT root license for inspected controller code; dependencies are separate.

License/notice evidence: [License / source notice](https://github.com/uzh-rpg/rpg_quadrotor_control/blob/22b55b085546a3322c302a68c2b67108a092a298/LICENSE).

Inspected implementation:

- [control/position_controller/src/position_controller.cpp](https://github.com/uzh-rpg/rpg_quadrotor_control/blob/22b55b085546a3322c302a68c2b67108a092a298/control/position_controller/src/position_controller.cpp#L19): Inspected: PositionController::run, computeNominalReferenceInputs, computeAeroCompensatedReferenceInputs
- [simulation/rpg_rotors_interface/src/rpg_rotors_interface.cpp](https://github.com/uzh-rpg/rpg_quadrotor_control/blob/22b55b085546a3322c302a68c2b67108a092a298/simulation/rpg_rotors_interface/src/rpg_rotors_interface.cpp#L1): Inspected: RotorS interface

**Evidence limits:** Older ROS/common dependencies; not a physics engine or independent source of selected-build validation. ROS, RotorS and rpg_quadrotor_common have separate version/license scope.

### OSS-18

**PX4-Autopilot — An explicit simulated-sensor and actuator bridge.** [Repository](https://github.com/PX4/PX4-Autopilot) · [inspected tree](https://github.com/PX4/PX4-Autopilot/tree/3695a9e9fb4463555d9635fe71b3cb2b7ae03426).

**Exact commit:** `3695a9e9fb4463555d9635fe71b3cb2b7ae03426`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Root LICENSE is BSD 3-Clause; the inspected SimulatorMavlink.cpp has a three-clause copyright notice. docs/LICENSE is CC BY 4.0. Check individual third-party assets and dependencies.

License/notice evidence: [LICENSE](https://github.com/PX4/PX4-Autopilot/blob/3695a9e9fb4463555d9635fe71b3cb2b7ae03426/LICENSE); [docs/LICENSE](https://github.com/PX4/PX4-Autopilot/blob/3695a9e9fb4463555d9635fe71b3cb2b7ae03426/docs/LICENSE).

Inspected implementation:

- [src/modules/simulation/simulator_mavlink/SimulatorMavlink.cpp](https://github.com/PX4/PX4-Autopilot/blob/3695a9e9fb4463555d9635fe71b3cb2b7ae03426/src/modules/simulation/simulator_mavlink/SimulatorMavlink.cpp#L121): actuator_controls_from_outputs serializes armed actuator outputs; send_controls sends HIL_ACTUATOR_CONTROLS.
- [src/modules/simulation/simulator_mavlink/SimulatorMavlink.cpp](https://github.com/PX4/PX4-Autopilot/blob/3695a9e9fb4463555d9635fe71b3cb2b7ae03426/src/modules/simulation/simulator_mavlink/SimulatorMavlink.cpp#L475): handle_message_hil_sensor decodes sensor messages, updates sensors and advances lockstep handling; scheduling behavior is build/configuration dependent.
- [src/modules/mc_rate_control/MulticopterRateControl.cpp](https://github.com/PX4/PX4-Autopilot/blob/3695a9e9fb4463555d9635fe71b3cb2b7ae03426/src/modules/mc_rate_control/MulticopterRateControl.cpp#L159): Acro manual inputs are shaped into rate setpoints, and the rate controller generates torque setpoints.

**Evidence limits:** Controller and protocol bridge, not Betaflight behavior. Source has conditional lockstep and placeholder ESC telemetry calculations; simulation presence alone proves neither physics accuracy nor deterministic end-to-end timing. HIL time handling, message flags, units, actuator order, arming, thread scheduling, and float64-to-float32 conversion need explicit adapters and tests; the PX4 stack adds substantial runtime complexity.

### OSS-19

**ArduPilot — External flight dynamics through a deliberately asymmetric protocol.** [Repository](https://github.com/ArduPilot/ardupilot) · [inspected tree](https://github.com/ArduPilot/ardupilot/tree/aea9a1b5d4d89c8aa7425d9375354355dd92189c).

**Exact commit:** `aea9a1b5d4d89c8aa7425d9375354355dd92189c`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** GPL-3.0-or-later for the project per README and explicitly for the inspected SIM_JSON.cpp and SIM_Multicopter.cpp; root COPYING.txt contains GPL v3. Check individual bundled components.

License/notice evidence: [COPYING.txt](https://github.com/ArduPilot/ardupilot/blob/aea9a1b5d4d89c8aa7425d9375354355dd92189c/COPYING.txt); [README.md](https://github.com/ArduPilot/ardupilot/blob/aea9a1b5d4d89c8aa7425d9375354355dd92189c/README.md).

Inspected implementation:

- [libraries/SITL/SIM_JSON.cpp](https://github.com/ArduPilot/ardupilot/blob/aea9a1b5d4d89c8aa7425d9375354355dd92189c/libraries/SITL/SIM_JSON.cpp#L105): JSON::output_servos sends frame rate, frame count and 16/32 PWM outputs over UDP.
- [libraries/SITL/SIM_JSON.cpp](https://github.com/ArduPilot/ardupilot/blob/aea9a1b5d4d89c8aa7425d9375354355dd92189c/libraries/SITL/SIM_JSON.cpp#L303): JSON::recv_fdm parses sensor records, validates mandatory fields, supports no-lockstep behavior, and resends servo output on receive timeouts.
- [libraries/SITL/SIM_Multicopter.cpp](https://github.com/ArduPilot/ardupilot/blob/aea9a1b5d4d89c8aa7425d9375354355dd92189c/libraries/SITL/SIM_Multicopter.cpp#L48): MultiCopter::update calculates frame forces, updates dynamics and position, and advances simulation time.

**Evidence limits:** Autonomous-vehicle SITL, not proof of racing-quad handling. UDP adapter and built-in model are separate possible paths; output format here is binary PWM while sensor side is JSON. Strong copyleft may affect code reuse/distribution; process architecture alone is not a license conclusion. Binary servo packet format, JSON fields, ordering, time and coordinate conversion must be verified against the specific adapter version.

### OSS-20

**MAVLink — Versioned wire messages with explicit units and field presence.** [Repository](https://github.com/mavlink/mavlink) · [inspected tree](https://github.com/mavlink/mavlink/tree/504e7a9b28657e5e59c18fb63ec0b866d290f6c7).

**Exact commit:** `504e7a9b28657e5e59c18fb63ec0b866d290f6c7`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Pinned COPYING states generator is “(L)GPL v3” and includes a generated-output MIT exception. The project’s separately pinned developer guide says its message-definition XML and generated C headers are MIT, and the generator toolchain is LGPLv3; inspect dialects and generated artifacts individually.

License/notice evidence: [COPYING](https://github.com/mavlink/mavlink/blob/504e7a9b28657e5e59c18fb63ec0b866d290f6c7/COPYING).

Inspected message definitions:

- [message_definitions/v1.0/common.xml](https://github.com/mavlink/mavlink/blob/504e7a9b28657e5e59c18fb63ec0b866d290f6c7/message_definitions/v1.0/common.xml#L5991): HIL_ACTUATOR_CONTROLS defines a timestamp, sixteen normalized controls, mode and flags.
- [message_definitions/v1.0/common.xml](https://github.com/mavlink/mavlink/blob/504e7a9b28657e5e59c18fb63ec0b866d290f6c7/message_definitions/v1.0/common.xml#L6095): HIL_SENSOR defines timestamped IMU, magnetic, pressure, temperature and update-mask fields, with units for several fields.
- [message_definitions/v1.0/common.xml](https://github.com/mavlink/mavlink/blob/504e7a9b28657e5e59c18fb63ec0b866d290f6c7/message_definitions/v1.0/common.xml#L5702): MANUAL_CONTROL defines a standard control message; message availability and semantics depend on peers and dialect.
- Separate license-scope statement: [MAVLink developer guide at b67f34d179ed7d03d6125465717a67696e68923b](https://github.com/mavlink/mavlink-devguide/blob/b67f34d179ed7d03d6125465717a67696e68923b/en/index.md#license), distinguishing XML/generated C from the generator.

**Evidence limits:** Message schemas specify formats, not controller behavior, data availability, timing guarantees, RF properties, or a physics model. The definition calls HIL_SENSOR a NED body frame; confirm axes, accelerometer specific-force semantics and conversions with each peer. Dialect/version, vehicle IDs, orientation conventions, sensor truth vs specific force, float quantization, freshness, timebase and command acknowledgements must be handled explicitly.

### OSS-21

**MAVSDK — Typed asynchronous automation outside the simulation transaction.** [Repository](https://github.com/mavlink/MAVSDK) · [inspected tree](https://github.com/mavlink/MAVSDK/tree/3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28).

**Exact commit:** `3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Root LICENSE.md contains the BSD 3-Clause license. Dependencies and generated bindings have their own notices.

License/notice evidence: [LICENSE.md](https://github.com/mavlink/MAVSDK/blob/3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28/LICENSE.md).

Inspected implementation:

- [cpp/src/mavsdk/core/mavsdk_impl.cpp](https://github.com/mavlink/MAVSDK/blob/3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28/cpp/src/mavsdk/core/mavsdk_impl.cpp#L1246): MavsdkImpl::add_any_connection constructs connection paths and dispatches received messages.
- [cpp/src/mavsdk/plugins/telemetry/telemetry_impl.cpp](https://github.com/mavlink/MAVSDK/blob/3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28/cpp/src/mavsdk/plugins/telemetry/telemetry_impl.cpp#L78): Telemetry registers handlers for attitude messages.
- [cpp/src/mavsdk/plugins/offboard/offboard_impl.cpp](https://github.com/mavlink/MAVSDK/blob/3eea18ca99edc7a0087e0e5e4b2bffbcfb376b28/cpp/src/mavsdk/plugins/offboard/offboard_impl.cpp#L176): set_velocity_ned schedules repeated setpoint sends and immediately sends an updated setpoint; start() rejects the absence of a setpoint.

**Evidence limits:** The API does not guarantee that every autopilot emits every subscribed message or supports every offboard command; asynchronous delivery does not guarantee deterministic timing. External API, dependencies, message rates, threading and autopilot-specific feature support; do not put asynchronous network callbacks inside the transactional physics step.

### OSS-22

**QGroundControl — Joystick calibration data and separate guided sensor workflows.** [Repository](https://github.com/mavlink/qgroundcontrol) · [inspected tree](https://github.com/mavlink/qgroundcontrol/tree/13faea0245c22a1d763b96721fe5c1711edc52e2).

**Exact commit:** `13faea0245c22a1d763b96721fe5c1711edc52e2`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Pinned .github/COPYING.md says dual-licensed Apache-2.0 OR GPL v3, with Apache use requiring a commercial Qt license according to that notice. Root LICENSE-APACHE and LICENSE-GPL contain both texts; check bundled assets and dependencies.

License/notice evidence: [.github/COPYING.md](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/.github/COPYING.md); [LICENSE-APACHE](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/LICENSE-APACHE); [LICENSE-GPL](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/LICENSE-GPL).

Inspected implementation:

- [src/Joystick/Joystick.cc](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/src/Joystick/Joystick.cc#L310): Joystick calibration settings include axis configuration and deadband.
- [src/Joystick/Joystick.cc](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/src/Joystick/Joystick.cc#L875): Joystick::_adjustRange transforms raw axis input using calibration and optional deadbands.
- [src/AutoPilotPlugins/APM/APMSensorsComponentController.cc](https://github.com/mavlink/qgroundcontrol/blob/13faea0245c22a1d763b96721fe5c1711edc52e2/src/AutoPilotPlugins/APM/APMSensorsComponentController.cc#L70): Sensor calibration controller initializes visual calibration and progress state.

**Evidence limits:** A ground-control calibration workflow is not proof that any particular USB transmitter enumerates correctly or that OpenRC has a MAVLink vehicle. Controller identification and axis mapping differ by OS and device; do not infer that QGC license choice automatically licenses Qt or all included assets.

### OSS-23

**EdgeTX — Transmitter shaping and USB channel assignment as upstream input state.** [Repository](https://github.com/EdgeTX/edgetx) · [inspected tree](https://github.com/EdgeTX/edgetx/tree/c8196280d58f77308276b0d43814324535e937e7).

**Exact commit:** `c8196280d58f77308276b0d43814324535e937e7`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Root LICENSE contains GPL v2; inspected radio/src/mixer.cpp explicitly says GPL version 2. radio/src/fonts/Noto/LICENSE_OFL.txt is a separate SIL Open Font License notice; inspect other assets and components.

License/notice evidence: [LICENSE](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/LICENSE); [radio/src/mixer.cpp](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/radio/src/mixer.cpp); [radio/src/fonts/Noto/LICENSE_OFL.txt](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/radio/src/fonts/Noto/LICENSE_OFL.txt).

Inspected implementation:

- [radio/src/gui/common/stdlcd/calibration.cpp](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/radio/src/gui/common/stdlcd/calibration.cpp#L72): The calibration UI captures a midpoint, then stick min/max, then stores calibration.
- [radio/src/mixer.cpp](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/radio/src/mixer.cpp#L180): expo and applyExpos implement transmitter-side input shaping.
- [radio/src/usb_joystick.cpp](https://github.com/EdgeTX/edgetx/blob/c8196280d58f77308276b0d43814324535e937e7/radio/src/usb_joystick.cpp#L39): USB joystick code stores axis and button channel assignments and declares a HID report.

**Evidence limits:** EdgeTX may shape channels before USB; applying a second curve in OpenRC can change feel. USB input does not by itself reproduce EdgeTX processing or ExpressLRS behavior. Mappings, device descriptors, USB modes, axis ranges, trims, expo, throttle direction and host OS can differ; GPLv2 applies to inspected mixer source, and bundled font assets differ.

### OSS-24

**ExpressLRS — Separate input delivery quality from radio propagation.** [Repository](https://github.com/ExpressLRS/ExpressLRS) · [inspected tree](https://github.com/ExpressLRS/ExpressLRS/tree/f8700cab6f7bfd50fe076194abdcf0e26d787e82).

**Exact commit:** `f8700cab6f7bfd50fe076194abdcf0e26d787e82`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Root LICENSE contains GNU GPL version 3; README points to it. The exact “only” versus “or later” designation for every inspected file was not established; inspect file-specific and third-party notices.

License/notice evidence: [LICENSE](https://github.com/ExpressLRS/ExpressLRS/blob/f8700cab6f7bfd50fe076194abdcf0e26d787e82/LICENSE); [README.md](https://github.com/ExpressLRS/ExpressLRS/blob/f8700cab6f7bfd50fe076194abdcf0e26d787e82/README.md).

Inspected implementation:

- [src/lib/FHSS/FHSS.cpp](https://github.com/ExpressLRS/ExpressLRS/blob/f8700cab6f7bfd50fe076194abdcf0e26d787e82/src/lib/FHSS/FHSS.cpp#L97): FHSSrandomiseFHSSsequence creates domain-dependent seeded hop sequences.
- [src/lib/LQCALC/LQCALC.h](https://github.com/ExpressLRS/ExpressLRS/blob/f8700cab6f7bfd50fe076194abdcf0e26d787e82/src/lib/LQCALC/LQCALC.h#L14): LQCALC tracks received periods in a bounded rolling window and reports a percentage.
- [src/lib/OTA/OTA.cpp](https://github.com/ExpressLRS/ExpressLRS/blob/f8700cab6f7bfd50fe076194abdcf0e26d787e82/src/lib/OTA/OTA.cpp#L23): OTA code packs radio data and handles CRC generation and validation.

**Evidence limits:** Packet scheduling and rolling LQ are not an RF propagation model; a packet rate is not an observed end-to-end control-latency measurement. OpenRC has no validated ELRS emulation. Strong copyleft and hardware/RF dependencies. Realistic latency/loss requires measured distributions, firmware configuration, receiver behavior and hardware validation.

### OSS-25

**Betaflight Blackbox Explorer — Readable tuning evidence with aligned signals and honest graph scales.** [Repository](https://github.com/betaflight/blackbox-log-viewer) · [inspected tree](https://github.com/betaflight/blackbox-log-viewer/tree/e179902df4e38f24d4b61f114bf856a196c995be).

**Exact commit:** `e179902df4e38f24d4b61f114bf856a196c995be`. **Snapshot context:** audited 2026-11-11; development snapshot.

**License scope:** Root LICENSE is GNU GPL v3; pinned README describes the project as GPLv3. “Or later” was not established for the whole repository; check any dependencies, log samples and media separately.

License/notice evidence: [LICENSE](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/LICENSE); [README.md](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/README.md).

Inspected implementation:

- [src/flightlog_parser.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/flightlog_parser.js#L1029): parseFrame decodes field encodings and prediction based on frame definitions.
- [src/flightlog.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/flightlog.js#L44): The flight-log layer aligns and merges multiple frame types into a time series.
- [src/graph_spectrum_calc.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/graph_spectrum_calc.js#L102): A selected range can be windowed and transformed to frequency data using an FFT.
- Maintenance statement: [pinned README](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/README.md) says the standalone project is feature-frozen, work moved to the Betaflight App, and announces 1 December 2026 for archiving. This was a future date at this audit; no completed archive is asserted.

**Evidence limits:** A logged flight is evidence of measured behavior only to the extent sensors, timestamps, calibration and available metadata are trustworthy. Its parser is a Betaflight-log parser, not an OpenRC replay implementation. README at this pin says standalone repo is feature-frozen and work moved into the Betaflight App; announced archive date was 2026-12-01. GPLv3 distribution issues for copying code; format versioning, axis units, sample rates, timestamp alignment and aliasing can mislead comparison.

## 3. Excluded or scoped examples — not in the 25

| Example | Inspected evidence | Why it is not counted / permitted inference |
| --- | --- | --- |
| KwadSimSITL | [Primary evidence](https://github.com/timower/KwadSimSITL/tree/e61735c96c5feb0c824355c83a3ceed1c6c79883) | No LICENSE/COPYING in the pinned tracked tree and no grant in inspected wrapper source. Betaflight submodule licensing does not license this host. Architecture reference only; no code adoption. |
| Betaloop | [Primary evidence](https://github.com/Aeroloop/betaloop/tree/dbe50cdaf63c00a159477ee0f904ea5e5a445941) | No established grant for the inspected launcher. Its motor-order discrepancy is a useful documented integration warning, not permission to copy its wrapper. |
| RotorS motor plugin | [Primary evidence](https://github.com/ethz-asl/rotors_simulator/blob/cd813b7a8c375d677352aa20ad20047feb661126/rotors_gazebo_plugins/src/gazebo_motor_model.cpp) | Inspected motor source has an Apache-2.0 notice and package.xml declares ASL 2.0, but no root license was found at this pin. Eligible file-scoped study; no blanket repository/asset claim and not needed for the 25-project count. Gazebo Sim motor code shares this lineage. |
| FlightGoggles | [Primary evidence](https://github.com/mit-aera/FlightGoggles/blob/684207863fe2344788a629634ec5d62ee5a0cfb9/LICENSE) | The literal MIT-like grant adds mandatory citation for academic use. It is not canonical MIT; approval/compatibility of that exact variant was not established here. Excluded conservatively from this verified set. Its separately MIT-licensed dynamics submodule is OSS-13, counted once. |
| Agilicious | [Primary evidence](https://github.com/uzh-rpg/agilicious/blob/50bba456156f6f438bea212c643b02e162442fa7/docs/license.rst) | Published agreement limits access/use to authorized academic/noncommercial researchers and restricts reuse/distribution. Do not equate the README description or a published paper with open-source code/data rights; no restricted source was obtained. |
| RotorHazard current revision | [Primary evidence](https://github.com/RotorHazard/RotorHazard/blob/6c3520ff3cdfb33588b5f72686822d1378bcf0f3/LICENSE) | Literal grant is MIT NON-AI with a machine-learning-use restriction and separate brand terms. Excluded from unrestricted open-source code count; descriptive race-timing and user-need research only. A 2024 historical license lacked that new clause but does not license subsequent changes. |
| CurryKitten-Sim | [Primary evidence](https://github.com/CurryKitten/CurryKitten-Sim) | Its README explicitly says the simulator is not open source; public issues/downloads are not a source grant. Retained only as a correction to loose free/open terminology. |
| pr0p Unity frontend | [Primary evidence](https://pr0p.dev/) | SimITL is separately open-source; no independently verified open-source license for this frontend was established. Do not transfer backend licensing to the complete frontend/product. |

The historical RotorHazard check is pinned at [`671c3a8aeb032902ac565a88bb70690a74d0f8b3`](https://github.com/RotorHazard/RotorHazard/blob/671c3a8aeb032902ac565a88bb70690a74d0f8b3/LICENSE), dated 3 September 2024. It is not counted again and no conclusion about later code follows. Flightmare's MIT code is separately evaluated from its Unity engine/binaries/assets. Webots' project code is separately evaluated from ODE and robot models. NeuroBEM papers or downloadable datasets are not counted as separately licensed code/weights without that audit.

## 4. Dated user and developer discussions

**Sampling:** deliberate issue-level selection for relevance to input, simulator boundaries, geometry, diagnostics and practice. This is not a survey, benchmark, defect census or ranking. The ledger has **19 records**: 17 selected user/contributor/member issue reports or questions, one individual commenter anecdote, and one additional maintainer-origin observation. Reporter association describes the retrieved context; the Blackbox request is from a project member and UR-03 is from a contributor. Neither association makes the individual report representative. Dates are issue creation dates unless noted. Reports may be historical, resolved or inapplicable to current versions.

Every interpretation below is our inference. Requests support a need to test or expose a behavior; they do not prove it is already implemented or preferred by most pilots.

### UR-01

**2025-12-05 — User issue.** [Primary discussion](https://github.com/uzh-rpg/flightmare/issues/223).

**Reported:** A vision/RL user reported an intermittent block while receiving Unity camera frames.

**OpenRC implication:** Bound renderer transport and show which stage is waiting; this report does not prove a universal or current defect.

### UR-02

**2025-05-17 — User issue; later reply.** [Primary discussion](https://github.com/uzh-rpg/flightmare/issues/217).

**Reported:** A user asked for drone and gate dimensions; a later reply described resetting while attempting to pass a gate.

**OpenRC implication:** Expose metric geometry/collision envelopes; no root cause is established by the thread.

### UR-03

**2024-10-01 — User/contributor issue.** [Primary discussion](https://github.com/learnsyslab/gym-pybullet-drones/issues/241).

**Reported:** A user reported zero motor outputs and confusion over which Betaflight process/build should run, with conflicting ports and setup steps.

**OpenRC implication:** Distinguish process startup, packet receipt, firmware/config identity, arming and valid motor output.

### UR-04

**2024-05-24 — User question.** [Primary discussion](https://github.com/learnsyslab/gym-pybullet-drones/issues/218).

**Reported:** A researcher asked how an RL policy connects to Betaflight and transfers to a real platform.

**OpenRC implication:** Specify action space, controller ownership and sensor/plant boundary; do not claim sim-to-real transfer from an interface alone.

### UR-05

**2025-11-17 — User question; maintainer response.** [Primary discussion](https://github.com/learnsyslab/gym-pybullet-drones/issues/291).

**Reported:** A researcher requested a direct collective-thrust/body-rate controller for RL instead of an unclear full-SITL path.

**OpenRC implication:** Choose the smallest controller boundary appropriate to the experiment; full firmware is not always the required tool.

### UR-06

**2019-06-19 — Historical user issue.** [Primary discussion](https://github.com/timower/KwadSim/issues/23).

**Reported:** A user reported no drone or track options when launching the simulator.

**OpenRC implication:** Validate content discovery and exported routes, not only physics functions.

### UR-07

**2024-10-17 — User request.** [Primary discussion](https://github.com/spencerfolk/rotorpy/issues/9).

**Reported:** A user praised the repository and requested simultaneous vehicles for swarm and RL work.

**OpenRC implication:** Researchers value extensibility and batch/multi-vehicle experiments; this does not make swarms a manual FPV requirement.

### UR-08

**2023-01; thread-level date — Individual Reddit commenter anecdote.** [Primary discussion](https://www.reddit.com/r/fpv/comments/103mgzk/any_good_free_drone_sims/).

**Reported:** One commenter calls FlowState on Steam realistic and describes it as more racing-oriented with a minimalist UI; no preference for the focus or UI is established.

**OpenRC implication:** Treat this as one subjective impression and product description; the commenter’s pilot status, a match to the 2018 code snapshot and measured realism are unverified.

### UE-01

**2024-11-28 — User report/request.** [Primary discussion](https://github.com/ArduPilot/ardupilot/issues/28769).

**Reported:** One operator using a custom JSON FDM reported changing local coordinates but no map movement, and separately reported intermittent JSBSim link-down behavior.

**OpenRC implication:** A bridge needs distinct diagnostics for connection, sensor receipt, estimator health, and displayed position; the report does not establish one cause.

### UE-02

**2026-05-10 — User report/request.** [Primary discussion](https://github.com/ArduPilot/ardupilot/issues/33017).

**Reported:** A SITL user reported that changing SIM_RC_FAIL during a session did not produce the expected virtual RC failsafe for their tested setup.

**OpenRC implication:** Test failure injection at the chosen input boundary; avoid treating one toggled parameter as proof that a full failsafe scenario ran.

### UE-03

**2023-12-06 — User report/request.** [Primary discussion](https://github.com/mavlink/MAVSDK/issues/2190).

**Reported:** A user trying to synchronize an external application reported that unix_epoch_time telemetry callbacks did not arrive in either C++ or Python.

**OpenRC implication:** Show whether a connection exists separately from whether a specific message is being received and whether its time source is valid.

### UE-04

**2024-02-03 — User report/request.** [Primary discussion](https://github.com/mavlink/qgroundcontrol/issues/11017).

**Reported:** A Radiomaster Zorro user reported that QGroundControl 4.3.0 only saw half the throttle axis and could not complete joystick calibration in their Ubuntu/SITL setup.

**OpenRC implication:** Show raw and normalized axis values, full travel, direction, and mapping while calibrating; this is an individual historical report.

### UE-05

**2022-12-22 — User report/request.** [Primary discussion](https://github.com/EdgeTX/edgetx/issues/2924).

**Reported:** A Companion 2.8 user reported mismatch between transmitter output channels and the joystick calibration dialog when using a FrSky simulator dongle.

**OpenRC implication:** Expose physical HID axes and assigned game functions together so mis-mapping is diagnosable.

### UE-06

**2024-01-28 — User report/request.** [Primary discussion](https://github.com/EdgeTX/edgetx/issues/4580).

**Reported:** A RadioMaster Boxer user reported that DCL on PS4 Pro recognized the transmitter on EdgeTX 2.8.5 but not 2.9.0–2.9.3 in the described setup.

**OpenRC implication:** Test actual device enumeration and versions; avoid declaring all transmitters compatible from one device or one platform.

### UE-07

**2022-03-09 — User report/request.** [Primary discussion](https://github.com/ExpressLRS/ExpressLRS/issues/1475).

**Reported:** A user with ExpressLRS 2.3 reported a receiver connecting at 250 Hz and below but failing to connect at 500 Hz on their listed TX/RX hardware.

**OpenRC implication:** A configurable packet rate is not itself a measured latency or interoperability guarantee.

### UE-08

**2025-03-13 — User report/request.** [Primary discussion](https://github.com/ExpressLRS/ExpressLRS/issues/3157).

**Reported:** A user reported intermittent reconnection and telemetry problems after failsafe with a stated 100 Hz, 1:8 telemetry and eight-channel setup.

**OpenRC implication:** If a future simulated link is introduced, test reconnect and freshness transitions explicitly; do not imply OpenRC already emulates this link.

### UE-09

**2026-03-15 — User report/request.** [Primary discussion](https://github.com/RotorHazard/RotorHazard/issues/1125).

**Reported:** A race operator requested indicators that distinguish peaks used for lap calculation from discarded peaks while marshalling difficult races.

**OpenRC implication:** Show committed crossing/adjudication evidence and reasons where the authoritative policy records them. Do not infer or invent rejected crossings from visual geometry, and do not import RF-specific heuristics.

### UE-10

**2019-11-19 — Project-member request.** [Primary discussion](https://github.com/betaflight/blackbox-log-viewer/issues/413).

**Reported:** A project member requested a fixed graph scale, explaining that auto-scaling can make a low-noise trace look worse than a higher-noise trace when comparing logs.

**OpenRC implication:** Offer identical units and locked axes for comparisons, and label any automatic scaling.

### UM-01

**2020-01-08 — Maintainer-origin historical observation.** [Primary discussion](https://github.com/RotorHazard/RotorHazard/issues/199).

**Reported:** A development-version report describes differences between live lap detection and laps reconstructed from stored history.

**OpenRC implication:** Compare committed decisions and reconstruction, but do not import RF-peak timing into geometric gate scoring or assert a current defect.

## 5. Evidence-to-plan traceability

| Finding | Implementation consequence | Plan owner / proposed checks |
| --- | --- | --- |
| SimITL/libfpv own complete simulated aircraft; Open FPV Sim has a different integrator/scheduler | One plant authority; distinct solver identity for foreign experiments | P25/P26; OSS-REF/BRIDGE |
| Several projects reuse firmware or rotor-law lineage | Do not call agreement independent validation without a dependency map | P25 source manifest |
| Manual stepping does not establish hidden-state restore | Full state inventory, idempotence and candidate rejection handling before production use | P26; OSS-BRIDGE-02…07 |
| Input shape/mapping can originate in transmitter firmware | Raw and normalized diagnostics; one declared curve chain | P10/P18/P22; OSS-UX-01 |
| User reports confuse transport availability with meaningful data | Distinct process, packet, sample, clock and actuator health | P26; OSS-BRIDGE-01/03 |
| Geometry scale and timing reconstruction cause practical confusion | Qualified metric scene/course identities and accepted decision evidence | P14/P15/P24; OSS-WORLD-01/02 |
| Graph auto-ranging can mislead comparison | Shared axes, units, sample/processing labels and read-only views | P23; OSS-UX-02/03 |
| Actual firmware and richer equations do not identify a selected physical build | Matched-subset software comparisons and separate physical campaign | P16/P25; OSS-DATA-01 plus PHYS cases |
| Licenses differ across code, generator output, fonts, assets and data | Component-specific reuse record; uncertain/restricted parts excluded | P01/P25; OSS-REF-01 |

## 6. Executed versus proposed

**Executed in this follow-up:** source and license inspection; frozen commit/source-path checks; qualitative discussion coding; cross-project synthesis; independent critical review; Markdown/count/link/archive validation. No downloaded external build or test was run.

**Proposed:** P25 matched-model comparisons, P26 firmware bridge experiments, the 21 cases in 14, physical validation, hardware latency/calibration, runtime source ports and any foreign-controller transaction support. Upstream reported tests, synthetic examples and benchmark claims were not promoted to our own results.

The earlier executed OpenRC probes remain exactly as documented in 06 and 09. This follow-up adds no new claim of playable FPV, a qualified exported drone route, passing full CI, native 1080p performance, or measured physical accuracy. Before implementation, rebase the plan against the then-current OpenRC branch and preserve the existing DR ownership and milestones.
