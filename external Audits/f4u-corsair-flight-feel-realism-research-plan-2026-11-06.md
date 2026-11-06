## The target should be a precise, powerful giant RC Corsair with demanding approach management

The research points toward a Corsair that **tracks smoothly in ordinary flight, responds clearly to its controls, requires deliberate rudder coordination, and makes the pilot manage energy carefully during approach and landing**. That is the handling character I would pursue for your simulator.

I completed a detailed, approximately **7,100-word Markdown plan for the senior developer**:

**[F4U-CORSAIR-FLIGHT-FEEL-REALISM-PLAN-2026-11-06.md](https://chatgpt.com/library?file_id=libfile_8e293aef58a48191b42e1741a9b0da90&account_id=personal)**

It includes the research evidence, mathematical analysis, current implementation, code owners, development priorities, a 15-case handling test matrix, acceptance criteria and reproducible calculations. I cross-checked it against the consolidated audits and treated previously reported issues as prerequisites.

## 1. What the pilots and specialist sources actually tell us

The most useful accessible material was the CARF Corsair build discussion on **RC Universe**, supported by **RC-Network**, original **CARF and Moki documentation**, and specialist flight reviews.

**FlyingGiants was included in the search, but its posts could not be retrieved through the available service.** The relevant RC Groups thread was also inaccessible. The report identifies those limitations explicitly; the conclusions below come from sources whose content could be read.

### A Corsair can be comfortable in the air and demanding near the ground

One CARF owner described satisfactory control during his maiden, followed by a slow approach, substantial sink and a bouncing arrival. On a subsequent flight, he reported a more successful main-wheel landing with the tail held up. Those accounts concern the same aircraft and pilot, so they are especially useful for understanding how technique and flight condition changed the outcome. [RCU Forums](https://www.rcuniverse.com/forum/rc-warbirds-warplanes-200/10576473-carf-f4u-1-corsair-build-thread-3.html?utm_source=chatgpt.com)

The implication for the simulator is significant: **ordinary-flight stability and landing difficulty should be evaluated separately**. A model can track well at cruise and still become demanding when the pilot combines low energy, substantial flap, insufficient elevator reserve and an unfavorable touchdown attitude.

Another CARF pilot reported a wing drop during an approach in a **63 lb aircraft**, followed by recovery with power. That establishes a reported upset, but the post does not identify the aerodynamic cause or provide enough state information to reconstruct it. [RCU Forums](https://www.rcuniverse.com/forum/rc-warbirds-warplanes-200/10576473-carf-f4u-1-corsair-build-thread-27.html?utm_source=chatgpt.com)

### The manufacturer’s approach advice is particularly useful

CARF recommends a tail-high, main-wheel landing and limits its recommended approach flap setting to **30°** because of elevator response. That gives us a concrete relationship to investigate: **flap setting, trim demand and remaining elevator authority**. [carf-models.com](https://carf-models.com/files/product/34/ed/06/corsair_manual.pdf?utm_source=chatgpt.com)

This should become one of the central Corsair validation cases. We need to establish what happens to the tail and the available pitching moment as the aircraft slows with flaps deployed.

### Reports from other Corsairs must stay identifiable

A Black Horse 2.3 m owner described undemanding handling, while a FlightLine 1.6 m electric review described gentle ordinary stalls and a departure when the aircraft was deliberately held in a hard stall. Both are useful evidence that RC Corsairs vary considerably, but neither model supplies numerical calibration for your giant CARF-class aircraft. [RC-Network.de](https://www.rc-network.de/threads/blackhorse-corsair-2-3m-bh64.11949709/?utm_source=chatgpt.com)

The reference aircraft must remain explicit: kit or geometry, mass, balance, propeller, engine, control throws, flap angle and operating conditions.

## 2. The biggest research trap is mixing different aircraft weights

Your authored reference is a **2.778 m, Moki S250-powered virtual Corsair with a 30×18 three-blade propeller**. Its nominal **21.5 kg** mass corresponds to the half-tank inventory. The aircraft definition itself describes its physics as provisional. [Aircraft definition](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/data/aircraft/f4u_corsair_250.json)

Several of the demanding CARF accounts concern aircraft reported at **62–63 lb**, approximately **28.1–28.6 kg**. [RCU Forums](https://www.rcuniverse.com/forum/rc-warbirds-warplanes-200/10576473-carf-f4u-1-corsair-build-thread-3.html?utm_source=chatgpt.com)

That difference matters mathematically. For the same wing area, density and effective maximum lift coefficient,

\[
V_s=\sqrt{\frac{2mg}{\rho S C_{L,\max}}}.
\]

Consequently,

\[
\frac{V_{s,2}}{V_{s,1}}
=
\sqrt{\frac{m_2}{m_1}}.
\]

| Aircraft mass | Ideal mass-only speed factor relative to 21.5 kg |
|---|---:|
| 21.5 kg | 1.000 |
| 62 lb / 28.12 kg | 1.144 |
| 63 lb / 28.58 kg | 1.153 |

**Mass alone implies approximately 14–15% more lift-limited speed in the heavier examples**, under those assumptions. This is a sensitivity calculation, not a prediction of either pilot’s actual approach speed.

If we tune the default aircraft until it resembles a particularly heavy forum build, we could make the reference model excessively fast on approach or give it an exaggerated sink rate.

A heavy-build variant could be useful later, but it needs a plausible component distribution, CG and inertia. Simply increasing mass while retaining the lighter aircraft’s rotational properties would be incomplete.

### Fuel also changes the comparison within your simulator

The current inventory produces these approximate states:

| Condition | Mass | CG as percentage of MAC |
|---|---:|---:|
| Full-tank default start | 21.874 kg | 23.970% |
| Half-tank reference | 21.500 kg | 24.816% |
| Near exhaustion, retained residue | 21.134 kg | 25.675% |

These are derived model values, using the authored inventory and rounded geometric MAC. Full tank to the residue state moves the modeled CG aft by approximately **9.18 mm**. [Inventory and fuel implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/sim/liquid_fuel_flight.gd)

Therefore, handling comparisons should record **accepted mass and CG at the maneuver**, rather than identifying every flight simply as “the 21.5 kg Corsair.”

## 3. What the aircraft should feel like in each phase

The following is my proposed development target, inferred from the evidence and the mechanics. It is a set of behaviors to validate, rather than a claim that all real Corsairs behave identically.

| Flight phase | Desired experience | What should produce it |
|---|---|---|
| Taxi and takeoff | Deliberate directional control; a believable transition as the tail unloads | Wheel loads, steering, friction, thrust alignment, propeller moments and tail flow |
| Cruise and fast passes | Smooth tracking with useful, precise control authority | Correct trim, stability, damping, control mapping and installation |
| Rolls and turns | Finite acceleration, clear authority and intelligible yaw coupling | Inertia, control moments, damping, differential and sideslip |
| Slow turns | Increasing demand as the pilot asks for more lift | Angle of attack, load factor, local separation and energy |
| Flap deployment | A noticeable configuration change with a consistent trim consequence | Lift, drag, pitching moment, downwash and actual flap motion |
| Final approach | Speed and descent respond meaningfully to power and attitude | Aircraft drag, propeller behavior, available lift and elevator reserve |
| Touchdown and rollout | Main-wheel contact responds to attitude and sink; the tail lowers consistently | Remaining aerodynamic loads, contact order, strut damping and ground friction |
| Go-around | Power restores energy while producing the appropriate transient moments | Actual shaft response, thrust, slipstream and aircraft state |

The strongest improvement would be consistency across these phases. A pilot should be able to understand why an approach succeeded, why a turn consumed margin, or why an arrival bounced.

## 4. The most important mathematical relationships to preserve

### A. Slow-turn difficulty should emerge from load

For a steady, coordinated, level turn, neglecting significant vertical thrust,

\[
n=\frac{1}{\cos\phi},
\qquad
V_{s,\phi}=V_{s,0}\sqrt{n}.
\]

| Bank angle | Required lift factor | Ideal stall-speed increase |
|---|---:|---:|
| 30° | 1.155 | 7.5% |
| 45° | 1.414 | 18.9% |
| 60° | 2.000 | 41.4% |

A **45° level turn requires approximately 19% more ideal lift-limited speed** than wings-level flight at the same configuration.

That relationship gives us an excellent simulation test. The pilot’s additional pull should increase lift demand and angle of attack. Any subsequent departure should follow the modeled local conditions.

The formula has important limits: an unloaded descending turn, a skid or a transient pull is a different situation. The test therefore needs angle of attack, sideslip, load and control history alongside airspeed.

### B. Approach handling is an energy problem

A useful diagnostic is energy height:

\[
H_e=h+\frac{V_a^2}{2g}.
\]

For still air, approximately constant mass and a point-mass treatment,

\[
\dot H_e
=
\dot h+\frac{V_a\dot V_a}{g}
=
\frac{V_a(T_\parallel-D)}{mg}.
\]

This shows how climb and acceleration share the available propulsive power.

For the Corsair, I would compare clean, gear-down and flapped configurations at matched starting conditions, while recording actual RPM. That separates several questions:

- How much energy does the airframe lose?
- How does flap deployment change the loss?
- What does the propeller do at the actual operating point?
- How much additional power is available during a go-around?
- How does the required trim change?

A single level-flight condition mostly identifies the difference between thrust and drag. It cannot uniquely identify both curves. That is why increasing drag until an approach “looks right” is a weak calibration method.

### C. Rotational weight and steady control authority are different

A simplified roll equation is

\[
I_{xx}\dot p
\approx
\bar q S b
\left(
C_{\ell\delta_a}\delta_a+
C_{\ell p}\frac{pb}{2V}
\right).
\]

In the decoupled, constant-speed approximation, inertia controls the acceleration and response time. The eventual roll rate follows the balance between the control moment and aerodynamic damping.

This gives the developer a practical diagnostic:

- **Initial response too abrupt:** inspect inertia, actual surface motion and control moment.
- **Steady roll rate too high:** inspect control effectiveness and roll damping.
- **Unexpected yaw during the roll:** inspect differential, sideslip coupling and propulsion effects.

Changing one “heaviness” parameter to correct all three would obscure the problem. The report includes the coupled roll/yaw equations using the model’s nonzero \(J_{xz}\).

## 5. My highest-priority investigation: flap deployment and elevator reserve

This is where I would concentrate the next physics development cycle.

The key question is:

> **At a given speed, power, flap position and CG, how much additional nose-up pitching moment remains available?**

There are several plausible explanations for weak response:

| Possible cause | What to measure |
|---|---|
| Flap pitching moment consumes the available trim | Trim elevator and remaining nose-up travel |
| Downwash changes tail incidence or separation | Local tail angle, force and moment |
| Tail flow has insufficient effective pressure | Tail-plane speed, slipstream and RPM |
| Servo or linkage limits actual movement | Commanded versus actual deflection |
| CG changes the required tail load | Accepted CG and trim across fuel conditions |

Unused elevator travel does not necessarily mean useful authority remains. If the tail has saturated, further movement may produce little additional moment.

The current implementation already has local surface flow, tail contributions and slipstream effects. Its horizontal-tail surface law uses the **x–z plane speed** when calculating local pressure, so diagnostics must follow that convention rather than silently substitute full three-dimensional speed. [Aerodynamic implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/aero.gd)

The proposed comparison is **0°, 15° and 30° flap**, repeated across speed, actual RPM and CG. Record the initial pitch acceleration separately from the final trim.

The previously reported **CF-06 flap moment-transfer issue** belongs ahead of this calibration. Otherwise, a coefficient adjustment could compensate for a known mathematical inconsistency.

## 6. Several improvements are already supported by the code

### Control configuration comes first

The live scene starts in **Sport**, whereas technical flight sessions and scripted cards default to **Full**. Sport retains full roll travel but uses normal-profile pitch/yaw travel. Calibrated radios retain their transmitter shaping. These distinctions can materially change a pilot’s impression. [FlightSession profile behavior](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/sim/flight_session.gd)

The aircraft also has an estimated **0.18-second neutral-to-full actuator rate limit**. That is a travel-rate limit, not a first-order time constant. [Actuator implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/control_actuators.gd)

Every handling recording should therefore include the input source, profile, trim, commanded input and actual surface position.

A useful early data candidate is **measured aileron differential**. The current generator produces symmetric travel, while the shared contract already supports a separate downward aileron limit. Once the intended linkage and measurement geometry are established, this can be addressed through aircraft data. [Control-surface implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/control_surfaces.gd)

### Propeller effects already exist

The simulator already represents shaft torque balance, propeller reaction, gyroscopic effects, P-factor/normal force and tail slipstream with swirl. Those systems need identification and calibration before additional effects are introduced. [Propulsion](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/propulsion.gd) · [Slipstream](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/slipstream.gd)

The Moki manual provides a useful **30×18 three-blade / 4,400 rpm operating example**, but does not specify its test conditions or provide a complete propeller map. The project treats those operating examples as static anchors. [heilemann-sternmotoren.de](https://www.heilemann-sternmotoren.de/images/pdf-dokumente/MOKI_250_S_Radial_Operating_Instructions.pdf?utm_source=chatgpt.com)

Matching an RPM anchor cannot independently establish thrust, engine-off drag or throttle transients. The plan therefore separates RPM response, thrust/drag behavior and the resulting aircraft motion.

### Additional low-speed complexity needs a specific justification

The Corsair already uses local wing stations and separation blending. Its generator incorporates Reynolds-dependent source information, but the shipped aircraft does not perform a runtime Reynolds-indexed polar lookup. [Physics generator](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/research/f4u-corsair/F4U-07/derive_physics.py)

A measured polar could eventually improve the model, but there is an integration constraint: the loader currently rejects a tabulated wing polar combined with the F4U’s flap stall-shift parameter. That requires an explicit design decision and validation. [Aircraft admission rules](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/aircraft_data.gd)

I would first establish whether the remaining error comes from installation, controls, existing coefficients or a genuine limitation of the aerodynamic law.

## 7. Sound is a concrete opportunity to strengthen the Corsair’s identity

The F4U currently uses the **generic gasoline recorded bank**. The source explicitly notes that there is no radial recording yet. [Powertrain audio mapping](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/audio/powertrain_audio.gd)

A suitable Moki recording could improve the experience substantially while leaving the physical trajectory unchanged.

There are two different characteristic event rates:

\[
f_{\text{firing}}=\frac{5\,RPM}{120},
\qquad
f_{\text{blade}}=\frac{3\,RPM}{60}.
\]

At 4,274 rpm, the ideal rates are approximately:

- **178.1 Hz** for five-cylinder four-stroke firing events.
- **213.7 Hz** for three-blade passage.

Those values are analytical checks, not a complete sound recipe. Exhaust, load, recording position, firing sequence and harmonics determine the result.

The proposed audio work uses identified recordings, RPM/load-dependent behavior and controlled listener geometry. It must also preserve the existing suppression of duplicate powered propeller sound when the recording already includes it.

One implementation detail matters: the existing numerical `.orfl` replay does **not** replay audio or camera presentation. An identical-trajectory audio comparison needs a separate observer harness or an explicitly developed presentation-replay capability. [Flight-logging workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/FLIGHT-LOGGING.md)

## 8. Recommended implementation sequence

| Priority | Work package | Concrete result |
|---|---|---|
| 1 | Establish the reference installation and input setup | A reproducible baseline with source, fuel, CG, controls and observer settings |
| 2 | Resolve relevant known consistency defects | A baseline suitable for physical calibration |
| 3 | Identify ordinary-flight response and energy | Separate evidence for trim, damping, control authority, drag and propulsion |
| 4 | Investigate flap/elevator behavior | A measured explanation for changes in approach and flare authority |
| 5 | Calibrate takeoff and landing contact | Wheel loads, tail rise, heading and bounce consistent with the intended setup |
| 6 | Evaluate additional aerodynamic complexity | A documented improvement on cases that simpler calibration cannot explain |
| 7 | Develop and evaluate Moki audio | A recognizable radial identity using the same accepted physical trajectory |
| 8 | Conduct experienced-pilot comparisons | Per-phase judgments supported by telemetry and held-out cases |

The report turns this into **15 specific comparison cases**, covering controls, fuel/CG, trim, pitch and roll response, rudder coupling, glides, power changes, flaps, stalls, loaded turns, takeoff, landing, crosswind and pilot evaluation.

For model complexity, the plan includes a convergence comparison—such as 6, 10 and 14 total wing strips—before accepting additional computational cost. The relevant question is whether forces, moments and maneuver behavior improve enough to justify that cost.

### What is complete, and what remains to be established

The completed work provides a researched handling target and an implementation plan grounded in the current code. The mathematics and numerical examples were independently checked, and the report clearly separates historical simulator results from physical evidence.

**The remaining requirement for an accuracy claim is matched real-aircraft evidence.** Forum accounts are excellent for identifying what to investigate; they cannot determine a unique drag coefficient, damping derivative or stall law.

My recommendation is to begin with **one carefully identified baseline and the flap/approach/elevator comparison**. That is the strongest next step toward making this Corsair’s behavior coherent and recognizable throughout an entire flight.