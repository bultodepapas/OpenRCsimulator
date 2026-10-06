# Physics and simulation audit

2026-10-06. Status: physics/simulation sub-audit complete. Scope: `app/physics/`, `app/sim/`, aircraft and ground physics data, physics tests/research, and the related ROADMAP sequence. Audit is against the working tree at commit `eaa8979c7aba2ad5c5eb46e045968c1f3f7cc676`; no implementation files changed.

## Current assessment

The numerical kernel and the process around it are unusually deliberate for this stage: float64 state, explicit NED/FRD conventions, a fixed 240 Hz step, RK4, pure load evaluation, finite-state guards, generated/provenanced aircraft numbers, exact-answer tests, golden replay, and a shared dynamics path for flight and analysis. That supports investigation without disguising guesses as measurements.

This is still an engineering candidate, not a physically validated simulator. The aerodynamic model combines borrowed global derivatives with estimated local surfaces and a regime blend; it has a pinned, measured-in-code inconsistency in the flight-relevant blend region. Most newly added aircraft have generated, estimated coefficients and are correctly labelled experimental. Ground tyre behavior is a useful pure approximation; real static friction and pilot testing remain ahead. Findings below separate current defects from explicit scope limits.

## Verified strengths

### S1 — State, units, axes, and integration have a clear contract

**Inspected:** [`rigid_body.gd`](../../../app/physics/rigid_body.gd), [`integrator.gd`](../../../app/physics/integrator.gd), [`simulation.gd`](../../../app/sim/simulation.gd), and the runtime state checks in the latter.

**Evidence:** `rigid_body.gd:1–8` defines the 13-value rigid-body state, world NED position, body FRD velocity/rates, body-to-NED quaternion, and the signed symmetric inertia layout. `integrator.gd:1–3,17–33` implements classical RK4 and renormalizes attitude after each step. `simulation.gd:57–89,115–182,214–254` validates initial/configuration/aux/load/RK-stage values, rejects degenerate quaternions and invalid inertia, and only publishes a valid integrated tick.

**Assessment / importance:** This is a strong foundation for a research simulator. The production kernel uses float64 arrays rather than Godot’s float32 transforms, making the precision boundary explicit. The integrator is simple enough to test against analytic answers and replay deterministically on one build/platform.

**Counterevidence / limit:** The integrator normalizes attitude only after a full RK step; intermediate stage quaternions are used directly in rotations. More significantly, this is a fourth-order integrator for a frozen-auxiliary rigid-body RHS, not proof that the complete coupled flight session is fourth-order; see T1. Current session propulsion/servo state is operator-split once per tick. Cross-platform bitwise identity is not established and should not be inferred from same-machine golden replays.

**Recommendation:** Keep this kernel. Continue exact-solution and step-halving tests as new stiffness/continuous-state systems arrive. Timing: preserve now; extend evidence with affected future physics.

### S2 — Flight and tools share a load/derivative path

**Inspected:** [`dynamics.gd`](../../../app/physics/dynamics.gd), [`flight_session.gd`](../../../app/sim/flight_session.gd), and the recorded repair report.

**Evidence:** `dynamics.gd:27–48,58–76` builds air data, aerodynamic loads, propulsion, optional slipstream, and rigid-body derivative through one evaluator. `flight_session.gd:523–534` adds ground loads to the same force path. Its `pre_step` is explicit at `flight_session.gd:555–575`. The repair report records the earlier divergence between trim/mode analysis and production flight and consolidates it through `Dynamics.evaluate` ([implementation report](../flight-repair-implementation.md)).

**Assessment / importance:** A shared evaluator substantially reduces “trim says one thing, flight uses another” risk. This is the right seam for deterministic verification and future component-load accounting.

**Counterevidence / limit:** Aircraft-specific values and conventions still sit in nested dictionaries and are converted repeatedly. The planned data pack is a measured optimization opportunity, not currently a correctness reason to flatten everything. More importantly, shared code only proves consistency; it does not prove that its force model describes a real aircraft.

**Recommendation:** Preserve the shared path. Validate against independent aircraft measurements before using internal modes or goldens as claims of realism. Timing: preserve now; independent validation is a precondition to calling the primary aircraft model validated.

### S3 — Aircraft quantities carry useful provenance and generated models are honestly labelled

**Inspected:** [`aircraft_data.gd`](../../../app/physics/aircraft_data.gd), all four files under `app/data/aircraft/`, plus the Stik, Extra, P-51 and Avanti derivation reports.

**Evidence:** `aircraft_data.gd:59–84` checks each scalar/vector quantity for unit, evidence kind, non-empty source, type, range, and finiteness; `:94–115,127–143,168–214` cross-checks planform, mass/inventory CG and derived inertia; `:347–384,565–586` validates coefficient tables. Aircraft data explicitly distinguishes measured/manual/borrowed/estimated/derived entries. For example, the Stik’s inherited aero is sourced to OpenFlightSim’s UltraStick25e data and labelled borrowed at `jensen_ugly_stik_60.json:759–815`; Extra, P-51 and Avanti declare estimated/generated aero and remain experimental in their track/catalog records.

**Assessment / importance:** This is the right way to manage an early parameterized flight model. Uncertainty is visible in the data and developers can ask which values to measure next instead of treating coefficients as authority.

**Counterevidence / limit:** Several nested sections have weaker validation than the common `_q`/`_xy_table` path; see finding B2. A provenance string can identify a source without the underlying source being independently checked, current, or suitable for scale transfer.

**Recommendation:** Keep the format and generator-first workflow. Close validation gaps before external aircraft data becomes user-authored/modifiable. Timing: schedule with the data-v2/pipeline phase; fix any gap that can admit malformed current production data sooner.

## Verified defects and risks

### B1 — Aerodynamic regime blend departs strongly from the attached-flow oracle across approach angles

**Importance:** Medium for current development; high before making approach-handling realism claims. **Status:** verified discrepancy against the code's chosen reference; its physical correctness remains unvalidated. It is not a literal discontinuity in loads.

**Inspected:** [`aero.gd`](../../../app/physics/aero.gd), [`test_damping_regimes.gd`](../../../app/tests/test_damping_regimes.gd), the D11 section of [`ROADMAP.md`](../../../ROADMAP.md), and the recorded flight-repair diagnostics.

**Evidence:** Global empirical derivatives are used at low angles, then complete local wing/tail loads blend in `aero.gd:228–270`. The test at `test_damping_regimes.gd:1–8,17–22,63–81` measures across 0–11° and pins worst ratios relative to its α=2° attached-flow oracle: Clp 1.73, Cmq 0.28, Cnr 0.72 and CLα 1.34. The test passes by checking those ratios remain near their documented values, not by showing the values match flight measurements. Loads blend smoothly; the derivatives can still vary with α. ROADMAP schedules wing-strip and tail/downwash work at D11d/E0a2 (`ROADMAP.md:159–160`; E0a2 also addresses the unused `CLadot`).

**Why it matters:** Approach α lies in the blend, so modeled control damping and lift slope change with α and can affect pilot feel. But a linear attached-flow oracle is not ground truth across a regime approaching stall; some α-dependence is physically expected. Internal self-consistency tests and goldens alone cannot tell whether the measured change is too large or realistic.

**Counterevidence:** The focused test transparently exposes the difference, and D11d/E0a2 add a more structured local model. However, “within ±15% of the α=2° oracle at every α” is an internal acceptance choice, not independently justified physical truth. No source reviewed here provides measured Stik derivatives through 0–11°.

**Recommended action:** Keep the pinned characterization test, but rename/report it as a reference discrepancy until its target is validated. Do not force constant derivatives merely to pass the oracle band; compare approach-angle response with measured aircraft data, a higher-confidence aerodynamic model, or a predeclared pilot-response band, and revise the acceptance bound if warranted. Gate approach-realism claims on that independent evidence. Timing: before validation claims that depend on the blend; no broad rewrite solely to meet an unverified threshold.

### B2 — Shaft power-curve validation is weaker than the general aircraft-data contract

**Importance:** Medium. **Status:** code defect in defensive validation; current generated P-51 data is valid.

**Inspected:** `AircraftData._shaft` at [`aircraft_data.gd:446–470`](../../../app/physics/aircraft_data.gd).

**Evidence:** Unlike `_table` and `_xy_table`, `_shaft` validates each power row by coercing it with `float(row[0])`/`float(row[1])` and checking order/positive power (`:451–460`), but does not explicitly require numeric JSON types, a `kind`, or a non-empty `source` for the table. It checks the unit, while the error text itself says kind/source are expected. A temporary probe changed the first checked-in P-51 RPM row to string `"1000"` and removed table `kind`/`source`; `validate_and_derive` returned `ok=true` with no errors ([probe](evidence/physics-validator-probe.gd), [output](evidence/physics-validator-probe.txt)). This weakens the “every value is typed/provenanced and invalid data is refused” guarantee specifically for the P-51 shaft branch.

**Why it matters:** String-valued table entries can be coerced instead of refused, and the provenance rule can be bypassed for a propulsion quantity. Current checked-in P-51 curve is valid and carries metadata at `p51d_mustang_120.json:1355–1450`.

**Counterevidence:** The current generated file provides numeric, increasing RPM/power rows with unit, kind and source; this is not evidence that today’s P-51 file is corrupt. The row order/positive-power checks reject a tested "nan" string, and `_q` validates the other shaft scalars. The demonstrated defect is coercion and missing provenance enforcement, not a proven route for non-finite curve values to reach flight.

**Recommended action:** Bring `_shaft` up to `_xy_table`’s explicit type/finiteness/provenance checks and add malformed-row loader cases before extending the shaft model to other aircraft. Timing: fix before additional shaft-powered aircraft/data producers rely on it; low-risk validator change.

### B3 — Ground setup accepts a CG inside the gear bounding box even when it is outside the support polygon

**Importance:** Medium. **Status:** verified loader defect for supported generic gear layouts; the current Stik and P-51 examples pass the support-polygon check.

**Inspected:** `AircraftData._landing_gear` at [`aircraft_data.gd:217–292`](../../../app/physics/aircraft_data.gd).

**Evidence:** Lines `273–276` accept support if the CG’s longitudinal and lateral coordinates each lie strictly between the min/max of contact coordinates. This is a rectangle/bounding-box test. For three non-collinear contacts, a CG can lie within both coordinate ranges but outside the triangular convex hull and the model still loads, although gravity would tip the aircraft about the support polygon. A temporary probe set the Stik contacts to (0, −.18), (1, .18), (1, 0) in x-aft/y-right, leaving CG (.1209, 0) inside both bounds but outside the support triangle; the loader accepted it ([probe](evidence/physics-validator-probe.gd), [output](evidence/physics-validator-probe.txt)).

**Why it matters:** The contact force model can provide restoring force only at active points; a geometry accepted as able to “stand on its wheels” may actually be statically unstable. It affects ground starts/taxi for future unusual layouts and is especially relevant to taildraggers/experimental aircraft.

**Counterevidence:** Independent polygon checks put the current Stik CG (.1209, 0) and P-51 CG (.177763, 0) inside their documented contact footprints. The probe demonstrates a validator gap, not that current aircraft are statically unsupported. The check is metadata plausibility, not a flaw in the point-force equation.

**Recommended action:** Replace the bounding-box check with support-polygon containment (with a small tolerance) and exercise triangle/quadrilateral layouts. Timing: fix before any aircraft relies on this loader gate for ground start acceptance; not an obstacle to current airborne flights.

### B4 — True ground stiction is not implemented, so stationary idle aircraft creep

**Importance:** Medium for E3b runway starts; acceptable limitation before that phase. **Status:** known and independently supported by the force law.

**Inspected:** [`ground_contact.gd`](../../../app/physics/ground_contact.gd) and the E1/E2/E3a evidence.

**Evidence:** The E2 law is memoryless. Its own comment at `ground_contact.gd:21–28` says a steady force below rolling resistance produces creep because `ROLL_CREEP` is a velocity scale; true stiction needs a per-wheel anchor state. Rolling force is proportional to wheel speed below the creep threshold (`:94`), so it is zero at exact rest. E3a’s evidence measured about 0.9 cm/s creep against a steady push and E3b1 plans anchor states (`ROADMAP.md` M2 section).

**Why it matters:** An aircraft cannot remain parked at engine idle under a static tyre force with this memoryless law. The roadmap’s E3b “parked at the threshold” behavior depends on adding state and a breakaway transition; tuning `C_rr` cannot create true stiction without creating incorrect low-speed damping.

**Counterevidence:** This limitation is explained in the implementation and explicitly scheduled for E3b. Current airborne dynamics add exactly no gear force above contact reach (`ground_contact.gd:41–50`), preserving air-flight traces.

**Recommended action:** Keep the present law for taxi experiments, but do not claim the runway-start gate until per-wheel anchors and static/dynamic transition are in. Timing: planned E3b; no need to add contact memory before the takeoff/runway milestone.

### B5 — The E1 report’s Stik axle conflict is a coordinate-datum misread, not a physics/render mismatch

**Importance:** Low documentation defect. **Status:** disproven suspected physics bug; stale prose should be corrected.

**Inspected:** Stik data frame and render transform in [`airplane.gd:47–63`](../../../app/render/airplane.gd), model geometry [`geometry.json:442–453`](../../../assets/aircraft/ugly-stik-60/geometry.json), render equipment construction [`ugly_stik_equipment.gd:730–766`](../../../app/aircraft/ugly_stik_equipment.gd), physics contacts in [`jensen_ugly_stik_60.json:588–664`](../../../app/data/aircraft/jensen_ugly_stik_60.json), and the claim in [`landing-gear-contact-e1.md:80–84`](../landing-gear-contact-e1.md).

**Evidence:** Render datum maps data x_aft=0 to model z=`wing.leading_z` = −0.115 m. Visual main axle at model z=+0.100 m therefore maps to x_aft=0.100−(−0.115)=0.215 m, exactly the contact x in physics. Visual wheel center y=−0.22 m with 0.0762 m diameter gives bottom z_up=−0.2581 m, also equal to the physics contact coordinate. Lateral track is ±0.18 m in both. The note at E1 report `:82–84` compares raw model Z to aircraft-frame x_aft and is wrong.

**Why it matters:** A false “wheel is 11.5 cm misplaced” report could trigger an unnecessary change to a correct gear location and break model/physics registration. More generally, these frame conversions are a safety-critical seam between model geometry and physical contact data.

**Counterevidence:** The E1 data values do agree with the model after applying the documented datum transform. The broader uncertainty is whether the source plan location is correct; current positions are estimated/manual-source geometry, and the E1 note says the plan should be re-read. That is a source-quality question, not the cited coordinate mismatch.

**Recommended action:** Correct the E1 note and the corresponding JSON source comment, and preserve a test that compares transformed model axle/wheel positions against physics contacts. Timing: fix documentation now; source-plan remeasurement can remain with the model’s gear handoff.

### B6 — Stik propeller coefficients are used well outside the measured RPM and diameter

**Importance:** High for powered-performance claims; acceptable, explicitly labelled uncertainty for early handling development. **Status:** verified data/model limitation, already scheduled as G1a.

**Inspected:** [`propulsion.gd`](../../../app/physics/propulsion.gd), the Stik propulsion data, ROADMAP M4/G1, and the primary UIUC propeller database.

**Evidence:** Runtime coefficient lookup is one-dimensional in advance ratio `J` (`propulsion.gd:23–37,149–159`); RPM changes only the dimensional scaling terms, not `Ct` or `Cp`. Stik data labels its table as borrowed APC Sport 11×6 measurements, applied to APC 12×6, with measurements up to 6,259 rpm, while the Stik max RPM is derived as 11,149 (`jensen_ugly_stik_60.json:1157–1219,1221–1254`, max RPM at `:1138–1143`). The official UIUC Vol. 4 page says its runs are per-specific RPM and include 12×6E, a *different thin-electric propeller* ([UIUC Vol. 4](https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html)). Its raw 12×6E tunnel files show `Ct=0.0440` at `J=.3516, 3040 rpm` ([3040 rpm data](https://m-selig.ae.illinois.edu/props/volume-4/data/apce_12x6_0630od_3040.txt)) and `Ct=0.0658` at `J=.3598, 6044 rpm` ([6044 rpm data](https://m-selig.ae.illinois.edu/props/volume-4/data/apce_12x6_0635od_6044.txt)), about a 50% increase over that RPM span. This demonstrates material Reynolds/RPM dependence in a nearby propeller, not the exact correction for the Stik's APC Sport.

**Why it matters:** Stik static thrust, throttle/shaft balance, climb, takeoff, and propwash magnitudes can all be internally consistent yet wrong at the derived operating RPM. The current `test_propulsion.gd:27–35` closes static thrust and power against values derived from the *same assumed* coefficient and engine power; it does not independently validate installed thrust or RPM. Avoid using those results as measured performance evidence.

**Counterevidence:** This extrapolation is declared in the JSON provenance and is already visible in G1a (`ROADMAP.md:257`). UIUC 12×6E is not geometrically/blade-profile-identical to 12×6 Sport, so its exact 50% trend must not be copied as the Sport correction. Flight handling tests can still exercise controls and qualitative response with an experimental power model.

**Recommended action:** Keep coefficients marked borrowed/estimated. Before validating Stik powered performance, add a same-prop static thrust and tachometer anchor and fit the operating band with evidence; that may be enough for this aircraft. Implement G1a's per-run `(J, rpm)` table with range reporting when supporting broad RPM/speed envelopes or additional propellers. Timing: measured Stik power anchor before powered-performance / propwash acceptance, not before basic airframe handling tests.

### B7 — Stopped propeller has no aerodynamic drag

**Importance:** Medium for dead-stick glide realism; known limitation already scheduled for G1d.

**Inspected:** [`propulsion.gd:149–180`](../../../app/physics/propulsion.gd), propulsion research and ROADMAP G1d.

**Evidence:** For non-turbine propellers, `thrust_torque` and `loads` return zero when RPM is below 1 (`propulsion.gd:150–152,165–169`). Thus a stopped propeller contributes no axial drag or torque at any airspeed. The unit test asserts this (`test_propulsion.gd:51–55`); it verifies current code, not physical correctness. ROADMAP G1d explicitly plans stopped-prop drag and calls out the present omission (`ROADMAP.md:260`).

**Why it matters:** Power-off glide performance and engine-off crash/recovery trajectories lack a real propeller's windmilling or stopped-blade drag. Existing idle-glide values should not be compared to a dead-stick aircraft unless the prop is still represented as windmilling.

**Counterevidence:** This is an explicit D5 scope limit, and the file labels windmill/stopped-prop behavior “not yet” (`propulsion.gd:1–8`). It is not a hidden regression or a reason to complicate the current 1-D model before the four-quadrant work.

**Recommended action:** Preserve the simple branch now. Implement and validate G1c/G1d before using engine-off glide as a realism claim. Timing: planned G1d.

### B8 — Propeller and turbine spool acceleration reaction is omitted

**Importance:** Medium for throttle-punch torque response; acceptable in the current experimental first slices. **Status:** verified known limitation, already scheduled as G2b.

**Inspected:** rigid_body.gd, dynamics.gd, propulsion.gd, turbine.gd, and ROADMAP G2b.

**Evidence:** The rigid-body rotational equation includes gyroscopic precession through omega cross (J omega + h) (rigid_body.gd:118–129), but there is no negative dh/dt reaction term. P-51 RPM changes in flight_session._pre_step (flight_session.gd:564–568), but only the resulting h(rpm) is passed into the derivative. Propeller loads include the steady reaction torque minus Q_prop (propulsion.gd:162–180); the first-order shaft balance also has transient Q_engine minus Q_prop (propulsion.gd:71–92). The session therefore has no term for the associated transient change in rotor angular momentum. The turbine branch likewise returns thrust and ram loads without reaction torque (turbine.gd:106–119) while its spool RPM changes (turbine.gd:57–72). ROADMAP G2b explicitly identifies the missing minus dh/dt torque and a throttle-punch check (ROADMAP.md:263).

**Why it matters:** Gyroscopic precession and acceleration reaction are different effects. Without the latter, torque roll or yaw during rapid spool-up is understated or mistimed, even if steady RPM and thrust are reasonable. A P-51 handling test can exercise powered flight without validating this transient.

**Counterevidence:** The P-51 implementation is explicitly a first shaft-model slice, uses an estimated rotor inertia, and remains experimental. Steady prop reaction is present and the gyroscopic term is not missing. Turbine internal torque bookkeeping should be derived carefully when spool dynamics become a validation target to avoid double-counting its compressor/load path.

**Recommended action:** Keep this in G2b after the H8 continuous-state design: integrate or otherwise measure rotor angular momentum, derive dh/dt consistently with each engine/propeller load branch, and verify sign and magnitude against the predicted throttle-punch moment. Timing: before torque-roll or rapid-throttle realism claims; no isolated patch needed before G2a/G2b.

### T1 — The full flight session is split-order; time-dependent RK-stage loads are not wired through

**Importance:** Medium now, high before coupled propulsion and M5 wind/turbulence validation. **Status:** verified architectural/model-order limit; current constant environment means no demonstrated flight bug from the timestamp alone.

**Inspected:** [`simulation.gd`](../../../app/sim/simulation.gd), [`integrator.gd`](../../../app/physics/integrator.gd), [`flight_session.gd`](../../../app/sim/flight_session.gd), and ROADMAP M5.

**Evidence:** `Simulation.step` captures tick-start `t`, calls `pre_step` once, replaces `aux` with its new value, captures rotor momentum once, then calls `loads(s, t)` for every RK derivative (`simulation.gd:119,131–167`). `integrator.rk4_step` accepts only `f(state)`, so it cannot supply `t`, `t+dt/2`, and `t+dt` at its four stages (`integrator.gd:17–25`). P-51 shaft `_pre_step` reads axial velocity from the old state and advances RPM once (`flight_session.gd:555–575`); the resulting new RPM and servo positions are then held across all state stages. Thus the RK4 label applies to the rigid-body state with frozen auxiliaries, not the coupled rigid-body/shaft/servo session. Meanwhile `_loads` ignores `_t`, fixes density at sea level, and passes zero wind (`flight_session.gd:523–534`), so repeating `t` has no current effect. ROADMAP explicitly requires wind/gust sampled per RK stage (`ROADMAP.md:312`), which the current Callable contract cannot express.

An isolated full-session P-51 probe applied a 0.2-to-1 throttle step for 0.5 s at 35 m/s and compared runs at 240, 480, 960, 1920 and 3840 Hz. End-RPM differences between adjacent resolutions were 1.516, 0.756, 0.378 and 0.189 rpm, respectively (approximately halving on each step); combined state/aux differences showed the same ratio ([probe](evidence/p51-step-halving.gd), [output](evidence/p51-step-halving.txt)). This confirms first-order convergence of the current shaft/session transient in this case, rather than the 16× error reduction expected from fourth-order convergence. It does not characterize every trajectory or establish the error magnitude at 240 Hz.

**Why it matters:** Future time-varying wind, gust filters, continuous shaft balance, or stage-varying atmosphere cannot be integrated at RK4 order with this interface. The once-per-tick split may be acceptable at 240 Hz for current demonstrator behavior, but session-level convergence cannot be inferred from the integrator's method name or frozen-state goldens.

**Counterevidence:** The current integrator is correct for autonomous loads with fixed aux. Present `_loads` is autonomous in state (constant calm wind and density); exact exponential first-order lag is used for baseline RPM, and current P-51/servo stepping is an explicitly opt-in first slice. No issue exists from the repeated timestamp until a time-dependent load is introduced.

**Recommended action:** Do not describe whole-flight integration as fourth-order. Before M5-W05c/d, change the stage evaluator to pass stage time; before G2a is considered complete for all aircraft, integrate RPM as part of the extended RK state or provide an independently validated coupled update, and include shaft RPM in convergence checks. Timing: schedule at H8/G2a/M5 dependency points already present in ROADMAP; no immediate refactor solely for constant-air tests.

### R2 — Propulsion research status is stale against the implementation and roadmap

**Importance:** Medium documentation/process risk. **Status:** verified research drift.

**Inspected:** investigation docs 03 and 05, current P-51 data, and current ROADMAP registry.

**Evidence:** Document 03 calls P51 shaft/slipstream code “uncommitted work in progress,” says no aircraft JSON declares the data, and labels P51-12 unregistered (`03-propeller-propwash.md:16,32–35`). Document 05 still labels shaft and turbine code uncommitted (`05-propulsion-engines-motors.md:21,37`). Current ROADMAP records P51-12/P51-13 and the optional shaft, thrust-axis, P-factor and slipstream physics as done, experimental (`ROADMAP.md:40`); the generated P-51 file contains `shaft` at `p51d_mustang_120.json:1355` and `slipstream` at `:1868`. The investigation documents also state an old `HEAD 69dc9bc` snapshot (`03:20`, `05:21`), not the current audited tree.

**Why it matters:** These knowledge-base documents are explicitly the pre-work reference for G1, E0b and M4. Stale status can lead a developer to re-derive completed work, miss current limitations, or sequence against an obsolete code shape. Their underlying physics analysis can still be useful when its date and scope remain clear.

**Counterevidence:** ROADMAP contains the newer status and documents contain valid analysis about G1's pending RPM-dependent data. This is not evidence that the current P-51 implementation is validated; only the status statements are stale.

**Recommended action:** Update the status/snapshot sections in 03 and 05 against current code, retaining historical notes as dated observations, and link current P-51 implementation evidence. Timing: before the next E0b/G1/G2 work is assigned.

## Roadmap and sequencing observations

### R1 — Physics feature order is mostly disciplined, with two gates that must stay real

**Inspected:** ROADMAP M1/M2/Phase H/M3–M5 and the flight-model, wind, aircraft-data and crash plans.

**Evidence:** Foundational state/integrator tests precede aero; M1 places goldens and predicted-handling checks before the high-angle model; Phase H explicitly buys measured headroom before propwash, shaft extension, turbulence and contacts; ground stiffness is checked against the fixed tick; the crash plan names extensible state before damage, though that dependency is only recommended; wind’s integration plan is staged behind explicit measurements/research. These are technically coherent dependencies for an early simulator.

**Assessment:** Do not infer that all published feature roadmaps are complete or validated because their steps exist. The highest-value path is still: finish the aero regime repair, measure/validate the first aircraft with a real pilot and independent flight evidence, then invest in takeoff/landing/wind/structural effects in that order. The open owner Gate 2 and D11 derivatives are material evidence gates, not paperwork.

**Counterevidence / risk:** Phase H mixes development-host measurements, a tighter optimization target, and the 500 µs budget for the owner’s slowest machine. The current roadmap records ≈380–400 µs after H2/H3 but also a 501 µs pre-refactor baseline, while the repair report records ≈487 µs in a shared-host run. These should be compared using one named, repeatable benchmark and target machine before authorizing GDExtension or declaring headroom. The current local model also grows beyond the Stik’s rectangular-wing case; the plan’s D11d cap of six strips is appropriately conservative but does not alone provide swept-wing/chordwise geometry.

**Recommended action:** Preserve the staged roadmap. Treat Gate 2 as pilot feel/readability and keep independent parameter identification as a separate validation gate. Re-measure the current per-aircraft tick budget with the same benchmark before the next architecture gate. Timing: do before Phase H Gate P / before heavier M2–M5 contributors are accepted.

## Verification performed

- Isolated Godot 4.7.2 probe verified both loader defects; evidence and script are in `evidence/physics-validator-probe.*`.
- Isolated P-51 throttle-step refinement probe showed ~2× error reduction per halving for the coupled shaft/session transient; see `evidence/p51-step-halving.*`. This is consistent with the current once-per-tick shaft update and is already addressed by G2a's RK-state step.
- Targeted `test_damping_regimes.gd` passed 17 checks. Its output remeasured worst ratios Clp ×1.726, Cmq ×0.278, Cnr ×0.724 and CLα ×1.341 ([captured output](evidence/damping-regimes.txt)). These green checks confirm the reference discrepancy remains; they do not validate its physical correctness.
- Inspected Stik gear/model datums and rejected the E1 “11.5 cm axle mismatch” claim after applying the leading-edge datum transform.
- Independently checked the UIUC Vol. 4 primary page and the raw 3040/6044 rpm 12×6E wind-tunnel rows. The measured RPM trend is relevant evidence but does not supply an exact APC Sport correction.
- Full app suite, benchmark, interactive run/capture, and broader repository checks are delegated to the lead audit to avoid duplicating shared run evidence.
