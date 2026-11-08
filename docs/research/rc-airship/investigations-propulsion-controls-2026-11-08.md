# RC airship investigations I09–I16: propulsion and controls

**Research snapshot: 2026-11-08.** This report proposes changes to the [5 m blimp plan](../../plans/rc-airship.md); it does not implement or validate them. The user has specified only a generic 5 m length and will supply the model. Geometry, mass, hardware and operating environment remain unknown. The existing [physics investigation](physics-2026-11-08.md) provides the underlying motion and buoyancy context.

The source audit used current files at commit `4bda2e4540fc07ebe8eb63d35072fd5aead39cbe`. The tree was clean when this investigation began; the earlier plan records a different audit baseline. HEAD advanced to `2465abc4b2def4cc9d6e3a175f4196a2b755236c` during the work; a path-scoped comparison found no changes between those commits to the inspected plan, physics report or source files cited here. The shared plan also has concurrent working-tree edits, which this report does not audit. Graph searches were attempted first, then current GDScript was inspected directly. External pages and manuals were accessed on 2026-11-08. Examples below are explicitly assumed calculations, not specifications or measurements of the proposed blimp.

## I09 — Which propulsion layout can actually deliver the requested wrench?

**Method and finding.** Compare the alternative layouts in plan §3 against the actual [RC-Zeppelin operating instructions](https://www.rc-zeppelin.com/manuals.html), then resolve forces about one body datum. The manual describes two motors on a servo-controlled main axis and a rear reversing motor; it does not establish independent control, dimensions or limits for our unknown model. For illustration, put main hubs at `r_R,L = (0, ±b, z)` in body FRD, their common direction at `e = (cos θ, 0, -sin θ)`, and the signed lateral tail thrust `Tt` at `(-l, 0, zt)`. Define `S = TR + TL` and `D = TR - TL`. Ignoring shaft reaction, their total wrench is:

```text
F = (S cos θ, Tt, -S sin θ)
M = (-b D sin θ - zt Tt, z S cos θ, -b D cos θ - l Tt)
```

The servos and motors cannot independently demand all six components. A lateral tail force also translates the craft; differential main thrust couples yaw and, when tilted, roll; a single common motor command eliminates `D`. At `S = 0`, changing the common angle alone makes no immediate main-thruster force. A fixed forward pair plus a separate vertical motor offers different independent heave authority, at the cost of another installation and power channel; forward thrust plus fins has limited still-air authority unless local propwash actually reaches a surface.

**Plan delta.** Before BL-02/06 selects controls, publish a signed, per-actuator wrench matrix and bounded, rate-limited allocation for the chosen geometry. Compute requested and achieved wrench, including saturation and failures. In the convention above, for positive main thrust a rearward axial component from vectoring requires `cos θ < 0`: a ±90° travel ending vertical cannot do it. Reversal through a propeller/ESC is a separate capability. Resolve which directions, if any, the model and controls actually support.

**Acceptance.** Independently sum one-at-a-time `r × F` values and compare with mixer output at both vector stops, neutral, saturation and one-motor failure; check unreachable commands remain unachieved and no fin force appears at zero local flow. Check rank/local authority at zero and nonzero thrust, and test sign and rate changes.

**Limits.** This geometric model is illustrative; installation aerodynamics, motor reaction torques, asymmetry and the final hardware are unknown. Authority is not a stability or pilot-handling result.

## I10 — What do available propeller data say about reverse and zero RPM?

**Method and finding.** Inspect raw public data, not just plots, and compare with [Propulsion.thrust_torque and prop_torque](../../../app/physics/propulsion.gd). The [UIUC APC 10×4.7 slow-flyer static sweep](https://m-selig.web.engr.illinois.edu/props/volume-1/data/apcsf_10x4.7_static_kt0835.txt) and [4,997 RPM wind-tunnel run](https://m-selig.web.engr.illinois.edu/props/volume-1/data/apcsf_10x4.7_rd0838_4997.txt) contain measured coefficients for a particular isolated propeller. In the latter, positive-rotation `CT` is `0.0040` at `J=0.636` and `-0.0120` at `J=0.692`, while `CP` remains positive. Negative thrust therefore does not itself establish reverse rotation, regenerative braking or a freely windmilling shaft. UIUC describes its [test and corrections](https://m-selig.web.engr.illinois.edu/props/volume-1/propDB-volume-1.html); [APC's separate performance files](https://www.apcprop.com/technical-information/performance-data/) are computational predictions, not independent wind-tunnel measurements.

The repository's ordinary non-glow path clamps negative axial speed in `J`, returns zero below 1 RPM, and does not implement a signed-RPM four-quadrant map. At zero RPM in nonzero flow a stopped blade can still exert drag and torque; `J=V/(nD)` is singular there. The [TU Delft negative-thrust code](https://research.tudelft.nl/en/datasets/blade-element-momentum-theory-code-for-positive-and-negative-thru/) is a free Apache-2.0 uniform-inflow calculation requiring blade polars, not a measured reverse-rotation database or a no-input windmill guarantee.

**Plan delta.** BL-02/06 should name signs for shaft speed, inflow, thrust, shaft torque and electrical power; specify separately the forward, reverse, stopped, braking and unpowered/windmilling domains. Import matched free measured curves with operating ranges and provenance; mark unmeasured reverse and transition branches as estimates or refuse them. Verify redistribution terms before bundling.

**Acceptance.** Reproduce selected dimensional UIUC points and their sign at the listed RPM/flow, then test continuity and finite torque through zero speed, both rotation directions and inlet-flow signs. Check shaft/electrical power signs and energy balance through motor cut and reversal against an independent oracle.

**Limits.** These samples are not installed-blimp measurements and do not characterize reverse rotation or low-RPM stopped-blade loads. Neither a four-quadrant model nor regeneration is established by the existing curves.

## I11 — Are the vector servo and moving rotor dynamics adequate?

**Method and finding.** Compare [ControlActuators.prepare_prescribed_angle, prescribed_angle_response and fixed_axis_motion](../../../app/physics/control_actuators.gd) with [RotorSystem.evaluate_system](../../../app/physics/rotor_coupling.gd) and [RigidBody.derivative](../../../app/physics/rigid_body.gd). The prescribed actuator bounds angle and rate via an ideal, massless fixed-center carrier; it has no torque, thermal or servo electrical limit. The rotor-system code already includes prescribed moving-axis rates and acceleration, but its qualified fixed-center/carrier assumptions do not by themselves couple the airship's translational/rotational added-mass matrix or a finite-torque servo. RigidBody's sampled rotor momentum supplies a gyroscopic cross product; it is not a complete changing-axis and shaft-acceleration reaction law.

**Illustrative check.** The [Hitec HS-65MG table](https://hitecrcd.com/servo-specification-chart/) lists 2.2 kgf·cm stall torque (about 0.216 N·m) and 0.11 s per 60° no-load speed at 6 V, about 9.52 rad/s. They are different operating points, not simultaneous continuous ratings. Assume one rotor has axial inertia `0.0002 kg·m²`, spin `500 rad/s` and an orthogonal axis rotation of `2 rad/s`: the changing-spin-momentum term has magnitude `I Ω θdot = 0.20 N·m` before other hinge loads. This illustrates why the terms can matter; these assumed numbers do not describe the delivered vehicle or prove the servo is suitable.

**Plan delta.** BL-01/02 should collect moving masses, hinge geometry, rotor inertias, rotation senses, rate, torque, linkage and BEC limits. BL-06 must either couple rotor angular momentum, body and servo in one consistently partitioned solve or document and bound their omission. Do not add motor reaction, rotor momentum transport or inertia twice. Matched counter-rotating momenta may cancel; unequal loading need not.

**Acceptance.** Verify stationary versus spinning vector sweeps, opposite spin signs, equal/unequal counter-rotation, travel stops, and angular-momentum/energy balance against an independent formulation with no external wrench. Test finite torque, stalled and voltage-derated servo cases if claimed; compare measured loaded sweeps with held-out timings.

**Limits.** No servo, inertia or load curve was supplied; catalog stall and no-load points cannot identify a full torque–speed–temperature law.

## I12 — How do multiple motors share one battery?

**Method and finding.** Read [ElectricMotor](../../../app/physics/electric_motor.gd), [ElectricSupply](../../../app/physics/electric_supply.gd), [PackEcm.evaluate](../../../app/physics/battery/pack_ecm.gd) and [ESC supervisor](../../../app/physics/battery/esc_supervisor.gd). The current ECM is one-quadrant motoring and solves one motor, one duty and one pack together; it advances one pack's charge, polarization, energy and heat. Calling it separately for each motor with a full independent pack duplicates capacity, auxiliary demand and inconsistent bus voltages. `fixed_voltage` is a fixed-source approximation; it does not by itself establish finite endurance. The SOC/resistance and ECM paths have different state and cutoff contracts.

For the existing ideal one-quadrant current relation, a shared stage can solve `V = E - Rp (Iaux + Σ di Ii)` with `Ii = max((di V - Ei)/Rmi, 0)` over a checked active set, where `Ei` is each motor's back-EMF. **Illustrative check:** with `E=12.6 V`, `Rp=0.10 Ω`, `Iaux=0.20 A`, and two identical motors each at `d=0.5`, `E_i=4.0 V`, `Rm=0.50 Ω`, the simultaneous solution is `V≈12.164 V`, `Ii≈4.164 A` per motor and pack current `≈4.364 A`. One motor alone gives `V≈12.362 V` and `Ii≈4.362 A`. These numbers are algebraic test inputs, not the blimp's pack.

**Plan delta.** BL-06 should solve all installed loads against a single bus at each RK stage, sum auxiliary/servo demand once, and advance one authoritative charge/energy/thermal block. Define finite-energy simplified and dynamic ECM options separately, including their admissible ranges. Reversal, dissipative braking and possible regeneration require a new expressly qualified drive/pack law; reverse rotation alone is not charging.

**Acceptance.** Check the worked shared-bus case, one-motor reduction, load-order permutation, unequal motors, cutout and zero-charge event. Verify terminal/source/loss energy balance, simultaneous cutoff ordering, and exact mid-transient checkpoint/replay.

**Limits.** No battery, BEC, motor, wire resistance or reverse-ESC efficiency is known. Existing single-motor tests do not qualify the new network or operating envelope.

## I13 — Which reversible ESC state machine is supported by evidence?

**Method and finding.** Compare actual aircraft-controller manuals rather than importing a car's brake-to-reverse sequence. The [Hobbywing XRotor-Pro-3D manual, §§4–6](https://www.hobbywing.com/en/uploads/file/20221025/b35fb71a0b5ae429f79316d2130dfc42.pdf) specifies a fixed 1100–1940 µs range, 1520 µs center with ±20 µs deadband, forward and reverse regions, a three-second soft-start behavior, and output cut after more than 0.25 s without throttle signal. It describes output resumption on signal return. Its examples concern that controller and compatible flight controller, not the unidentified blimp. The [Spektrum Avian programming instructions](https://www.spektrumrc.com/on/demandware.static/-/Sites-horizon-master/default/dw8b38e716/Manuals/Spektrum-Avian-SmartLink-Update-Instructions.pdf) describe a distinct reverse-channel option, brake modes and selectable soft or hard low-voltage cutoff. The hardware choice changes both controls and transition timing.

**Plan delta.** BL-02/06/10 should identify the selected ESC and firmware, its channel topology, arming condition, neutral pulse, deadband, signal-loss behavior, brake/reverse transition, cutoff sensing, timers and recovery. Specify simulated states and ownership of each timer, with explicit priority for power-off, signal loss, low voltage and reversal. Use [esc_supervisor.gd](../../../app/physics/battery/esc_supervisor.gd) only where its sampled, next-tick soft/hard cutoff and low-throttle recovery match the chosen contract; its unipolar throttle reset does not automatically mean centered reversible neutral. Keep any generic simplified controller visibly identified as estimated.

**Acceptance.** Exercise both directions from neutral, live forward-to-reverse while spinning, neutral dwell, startup at nonneutral, loss/return of signal, cutoff and recovery, including simultaneous boundary events. Check motor speed and torque remain finite and checkpoint/restore reproduces timer and output transitions.

**Limits.** Neither manual selects the actual ESC. The XRotor manual sections examined do not establish this installation's battery cutoff, brake power path or mechanical stopping time; no assumed numbers may be promoted as measured hardware.

## I14 — Can existing RC input safely represent reversible neutral and reconnect?

**Method and finding.** Trace [RcInput.on_motion, poll, normalize_throttle and sticks](../../../app/input/rc_input.gd) and the helicopter session's selection/disconnect handling. Absolute radio throttle is normalized to `0…1`; the legacy radio arm evidence is **low** throttle, while keyboard `Commands.step_commands` integrates throttle within `0…1`. Standard live gamepad verification can arm from a confirmed poll. If a reversible control is naively mapped as `signed = 2 × throttle - 1`, low throttle becomes full reverse, and the current low-throttle arming rule is the wrong condition. Device sampling, neutral, throttle cut and ownership must therefore be separated from vehicle output arming.

The [FrSky ETHOS RF manual](https://ethos-doc.frsky-rc.com/model-setup/rf-system/) distinguishes receiver hold-last, per-channel custom and no-pulse failsafes. These modes are not equivalent to a USB/controller disconnection: an unchanged valid-looking USB axis may conceal RF loss. Do not claim that an input timeout detects an RF failure unless the connected device actually exposes that signal.

**Plan delta.** BL-02/10 should define named signed airship roles, axis calibration/inversion/deadband, mixer order, input units, controller capability profile and per-channel safe state. Add a vehicle-appropriate centered-neutral/explicit-arm gate at the ownership boundary; on disconnect, focus loss, profile change and reconnect, hold propulsion disabled until fresh valid samples and the declared rearm action. Account separately for motors, vector angle and retained buoyancy. Preserve input and safety-mode identity in logs.

**Acceptance.** Cover physical minimum/center/maximum, inverted and asymmetric calibrated endpoints, a centered reversible command, throttle cut, invalid data, disconnect, focus loss, active-axis reconnect and unchanged valid samples. Assert that no transition can turn a disarmed or disconnected default into reverse thrust and that no unavailable RF-loss signal is silently invented.

**Limits.** The mapping is a proposed simulator policy, not the FrSky receiver's or XRotor's asserted behavior; actual transmitter/receiver integration and hardware acceptance remain open.

## I15 — What do contact and an optional tether require?

**Method and finding.** Inspect [CollisionWorld.nearby](../../../app/scenery/collision_world.gd), [Environment.ground and sample_support](../../../app/sim/environment.gd), [HullCrossing.reconstruct](../../../app/physics/hull_crossing.gd) and [HullContact](../../../app/physics/hull_contact.gd). The world supplies static obstacle proxies and broadphase queries, and environment supplies ground geometry. HullCrossing explicitly reconstructs a point crossing under linear position and quaternion nlerp against a flat field; it says it is **not** continuous collision detection or RK dense output. HullContact's stiffness, damping and aircraft crash thresholds are estimated numerical choices, not envelope material or puncture evidence. Its point set and single prop-disc path do not prove clearance of a large rotating 5 m envelope.

The [experimental spherical-aerostat study](https://www.sciencedirect.com/science/article/pii/S0167610509000464) used a lumped-mass, stiffness and damping tether; [RC-Zeppelin's manual](https://www.rc-zeppelin.com/manuals.html) describes tethered handling as well as free flight. A tether changes the force and moment; an always-taut visual line is not equivalent.

**Plan delta.** BL-11 should first define separate envelope, gondola, fin and each propeller's collision proxies and a conservative, bounded swept-motion admission domain; terminal collision can initially be deterministic without implying deformation, puncture or safe landing. BL-15 may later add calibrated support response, accounting for the selected coupled effective mass. Keep tether excluded until requested; if added, specify attachment/anchor, unilateral slack/taut tension, off-center moment, length and any line mass, drag, elasticity or deployment assumptions. Include cable states/events in checkpoints.

**Acceptance.** Check envelope-first and gondola-first contact, grazing, thin obstacles, rapid rotation, both endpoints clear with an intervening intersection, terrain slopes, simultaneous contacts, rollback and restart. For a tether, independently check no compressive tension, slack-to-taut event ordering, attachment moment and bounded energy loss under a declared simple model.

**Limits.** No material pressure/indentation, restitution, line geometry or contact measurements exist for the supplied model. Proxy nonpenetration is software evidence, not physical deformation or crash validation.

## I16 — What is a defensible outdoor operating envelope?

**Method and finding.** Distinguish drifting safely, controlled return and holding a ground position. For steady uniform wind, station keeping requires simultaneous force **and moment** equilibrium, sufficient control margin, sustainable electrical power, and a stable/recoverable operating condition; a full-throttle force balance alone is only a necessary screen. Use measured or explicitly estimated directional `Cd A`, air density, installed thrust-versus-inflow, available battery power and actuator bounds. The [NASA drag equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/drag-equation/) makes reference area part of the coefficient definition. The [manufacturer's outdoor manual](https://www.rc-zeppelin.com/manuals.html) recommends sustained wind up to 10 km/h and gusts up to 15 km/h, while its [FAQ](https://www.rc-zeppelin.com/faq.html) gives a broader typical 15–20 km/h statement without enough matching configuration detail. These are conflicting, model-dependent operating advice, not a measured limit for this blimp.

**Illustrative check.** Let `ρ=1.225 kg/m³` and assumed headwind `Cd A=0.60 m²`; then `D=0.3675 U² N`. At `U=3 m/s`, drag is 3.31 N and useful air-relative power is 9.92 W; at `5 m/s`, they are 9.19 N and 45.94 W. At an assumed constant 50% propulsive efficiency plus 5 W auxiliary demand, a hypothetical 40 Wh usable terminal-energy budget lasts about 97 versus 25 minutes. This optimistic calculation excludes vertical-thrust induced power, servo load, maneuver reserve, transients, sag and wind-dependent efficiency. If a total 10 N thrust vector must also supply 3 N upward, at most `sqrt(10²−3²)=9.54 N` remains horizontal before torque balancing; 5 m/s already uses most of it. None of these inputs is a vehicle specification.

**Plan delta.** BL-06/13 should derive a directional feasibility and energy-reserve map across battery state, trim and wind, with separate drift, return and station-keeping labels. BL-14 remains the prerequisite for gust/shear claims; do not infer gust survival from a steady-wind result. Test power loss for light, neutral and heavy trim without invented position hold.

**Acceptance.** Check the dimensional examples, required force and moment at an admitted steady case, saturated no-equilibrium case, decreasing battery authority, and a safe-return margin on the same input tape. Later compare independent outdoor wind and flight measurements with uncertainty and a separately held-out maneuver.

**Limits.** No geometry, thrust maps, drag polar, measured battery, pilot or outdoor wind observation exists yet. A calculated threshold is not a demonstrated wind-survival or station-keeping rating.
