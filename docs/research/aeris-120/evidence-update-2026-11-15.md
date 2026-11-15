# AERIS-120: deeper handling and physics evidence

**2026-11-15 · A120-00 continuation.** This extends the research at `f08d4a7398629e46fa1bb2b1921f4f438aaadd94`. The runtime baseline remains `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; no simulator law or aircraft data changes here. [Plan/status](../../plans/aeris-120-3d-gas.md) · [Source register](sources.md) · [Developer briefs](development-briefs.md) · [Reproducible study and acquisition kit](../../../research/aeris-120/README.md).

## 1. Findings that change the investigation

### Similar-sized flight tests support the measurement method, not a donor tune

Dantsker and Selig's 2.6 m Sukhoi carried a 100 Hz logger, RPM sensing and actual surface potentiometers. It weighed 16.37 kg and used electric propulsion. Its illustrated stalls and descending harriers were motor-off; reconstructed coefficients depend on motion, inertia and propeller-force assumptions. That makes it useful instrumentation precedent, not a powered AERIS harrier map. Its listed ±300°/s gyro range also shows why a logger's sample rate alone cannot establish suitability for aggressive rotations. [S20, §§II–IV]

The retained Extra 260 stall/spin study is also close in span. Its air-data limitations matter: the pitot was specified only to 20° incidence, and the authors caution that some reconstructed angle-of-attack/Reynolds histories include wind effects. Logged surface positions do not by themselves establish independently sensed mechanical deflection. Use its maneuver/configuration matrix as a reference, while keeping air-relative velocity and sensor validity explicit. [S19, §§II–IV]

For A120, record actual surfaces, motion and RPM on a known clock. Record sensor range, saturation and filtering. GPS ground velocity is insufficient to identify high-alpha aerodynamics without wind; a conventional pitot cannot supply full-angle flow direction. Published curves reconstructed from those channels are not independent measurements of every component force.

### Harrier wing rock is a phenomenon to identify

Johnson and Lind measured upright/inverted harriers on a much smaller electric aerobat. Upright wing rock was concentrated around **4 rad/s, approximately 0.64 Hz**, with changing frequency; it was substantially reduced inverted across the tested fin sizes. They logged commands and inertial motion but could not establish the local aerodynamic cause. This is evidence for paired signed tests, not a universal inverted-flight rule or an AERIS oscillation frequency. [S21, §§II–IV]

Post-stall control measurements on several unpowered wing planforms also show that asymmetric separation and retained aileron authority depend on geometry. Their tested Reynolds numbers and deflections provide useful experimental ranges, not coefficients for the existing AERIS asset. [S32, ch. 4]

**Investigation consequence:** compare upright/inverted and left/right cases with actual controls, RPM, path, local-flow validity and entry history. Separate pilot corrections from uncommanded motion. A sinusoidal wing-rock helper, compulsory aileron reversal, fixed wing-drop direction or artificially symmetric harrier would bypass the question being investigated.

### Wing-inclusive propwash needs spatial evidence

An installed wing can alter a propeller wake: a small hover rig measured downstream deformation that changed with flap angle. A separate rapidly pitching small wing with contra-rotating propellers showed changes in separation and effective incidence with blowing. These are mechanism references with different geometry/Reynolds regimes, not an AERIS wake map. [S33, §§2–4; S34, static/dynamic results]

The Glasgow oblique-inflow experiment offers a reusable independent benchmark: blade Reynolds number about 111,000, advance ratio 0.36–1.54 and yaw 0–20°. It measured a plane **upstream** of the propeller. It can challenge uniform-inflow assumptions within that envelope; it cannot qualify downstream tail wash, near-hover conditions, transport delay or reverse flow. Its `J=V_inf/(nD)` uses total freestream speed; under its yaw geometry the axial value is `J*cos(yaw)`. Preserve each case's blade pitch and normalization before comparing with OpenRC's axial local-flow convention. [S24]

Use the actual wing, cowl, prop and tail geometry when testing overlap. Survey identified positions and velocity components; a scalar thrust/RPM trace does not determine local wing or rudder flow. A steady sequential traverse cannot establish a transient field. For transient work use synchronized fixed probes or demonstrably repeatable, phase-aligned trials.

### Related DA120 data exist, but configuration identity matters

HFE's 2025 DA120 **EFI**, stock-muffler sheet publishes part-throttle dyno curves and gravimetric fuel results, using 30-second steady points and a stated ±10% allowance. It is a useful comparator and method reference. Its table lists peak power at 8,500 RPM outside the stated 2,000–8,000 RPM range; do not extrapolate through that inconsistency. It does not establish the carbureted AERIS map or transient response. [S22, pp. 1–4]

Nominal prop size is also insufficient identity. HFE's estimated 28×10 operating point does not override the separate limit of the exact Mejzlik PN 228108 reference. Retain engine, fuel system, muffler, prop part/revision and test conditions together. [S06, S22]

One propeller at steady state samples a restricted equilibrium curve. Without measured shaft torque, thrust and RPM cannot determine brake power. Even with torque, those points do not identify the full two-dimensional engine torque map against RPM and actual butterfly angle. Additional independently characterized loads or dynamometer points are required.

### Separate actuator, shaft and observation dynamics

A glow-engine experiment measured throttle-servo position separately because servo motion affected identification. Its remaining lever-to-RPM response still describes a prop-loaded static installation; its fitted time constants do not transfer to a gasoline DA120. [S31, §§2–7]

Steffensen and colleagues identified ground and flight actuator/surface response from measured deflections and frequency excitation, finding substantial differences between servo systems. This supports measuring the installed linkage and actual surface, rather than deriving loaded behavior from catalog transit speed. [S23, §3]

For A120, a measured RPM step is a combined response until command, butterfly angle, RPM, load and instrumentation delays are separated. The existing shaft balance already creates acceleration lag. Add a combustion/induction state only for repeatable residuals after those quantities are accounted for. D6-SRV remains the shared actuator owner.

### Keep mean rotor dynamics distinct from vibration

The familiar gyroscopic term is a time-mean description for a two-blade propeller; the instantaneous moments also contain twice-per-revolution components. [S29] At the illustrative 5,000 RPM point, twice per revolution is about 167 Hz. A 100 Hz recorder cannot resolve that component, and a 240 Hz fixed-step solver does not establish blade-resolved vibration accuracy. Mean flight dynamics and separately rendered/audio cues have different bandwidth requirements.

Retain the coupled relative-shaft/body angular-momentum convention in [physics and propulsion](physics-and-propulsion.md). Do not add a second torque reaction or a cosmetic “gyro strength.” The estimated prop inertia is not the total installed rotor inertia, and effective reciprocating-engine acceleration inertia need not equal a rigid gyroscopic momentum coefficient.

## 2. Reproducible scale checks

The [offline study](../../../research/aeris-120/README.md) makes the following **illustrative arithmetic** reproducible. Inputs identify prior design dimensions, borrowed manufacturer simulations and chosen scenarios; none is a new AERIS measurement.

| Calculation | Result under shipped inputs | Engineering use / limit |
| --- | --- | --- |
| `S/b`, aspect ratio | 0.470 m; 5.617 | Reference chord is not measured MAC |
| Reference Reynolds number at 5 / 10 / 20 m/s | 161k / 322k / 644k, with `nu=1.46e-5 m²/s` | A local-speed scale check; section chord, weather and wash vary |
| Reference dynamic pressure at 5 / 20 m/s | 15.3 / 245 Pa | A fourfold speed change gives sixteenfold pressure, before changes in coefficients or direction |
| `p b/(2V)` at 360°/s and 10 m/s | 0.829 | Large rotational/local-flow contribution; no universal derivative-validity cutoff is inferred |
| S06 static reference at 5,000 RPM | 177.6 N thrust; 3.405 kW shaft power; 6.504 N·m torque | Converted from simulated coefficients, not an installed engine test |
| Ideal static disk / far-wake speed | 13.51 / 27.02 m/s | Distinct ideal locations, excluding swirl/installation; neither is a tail-speed prediction |
| Prop-only angular momentum | 4.016 N·m·s | About 12.62 N·m mean gyro coupling at a chosen **perpendicular** 180°/s; not net aircraft moment |
| Constant-Ct `T=mg`, assumed 12.6 kg | About 4,171 RPM | Algebra outside the supplied RPM point; no engine equilibrium, hover authority or validated margin |
| Pure 50 ms delay at 2 Hz | −36° phase | An isolated-delay calculation, not measured full-loop phase or a latency budget |

The stored report retains full calculation precision for reproduction, not as claimed physical accuracy. Reduced rates and chord-advection time are **null at zero reference speed**. The study never inserts a fictitious minimum aerodynamic speed.

## 3. Identifiability: which observation distinguishes which cause?

An apparently accurate response can hide wrong parameters. For a local one-axis roll approximation,

\[
I_x\dot p=L_\delta\delta_a+L_p p.
\]

The measured response identifies ratios `L_delta/Ix` and `Lp/Ix`. Multiplying all three dimensional parameters by the same factor leaves that response unchanged. A steady roll, rise and release alone therefore cannot determine inertia, aileron authority and damping independently. Measure mass properties and actual deflection first; then fit only the identifiable aerodynamic quantities over a declared attached-flow regime. This is an algebraic example, not a new global roll law.

| Observation | What remains confounded | Discriminating additional evidence |
| --- | --- | --- |
| RPM follows throttle slowly | Throttle actuator, combustion/induction, shaft inertia, prop load, sensor filtering | Actual butterfly angle and characterized prop load/inertia; repeated up/down histories |
| Hover correction needs excessive rudder | Local wake, rudder force law, torque/thrust offsets, CG and actual throw | Measured surface angles plus local vector flow and signed force/moment map |
| Slow roll stop | Surface return, input shaping, inertia, aerodynamic damping | Surface return history, independent inertia and matched-speed roll release |
| Pitch/roll loop in high-alpha response | Local-flow history, surface delay, separation memory and wind | Match instantaneous measured local flow and actual deflection across different histories |
| Taxi yaw after throttle blip | Rudder/wake, steering, tire/contact, wind, restraint and torque | Airborne or isolated force/flow observations; ground measurements remain a separate coupled case |
| Better pilot score | Aircraft mechanics, camera, device latency, familiarization and expectation | Fixed presentation/input setup, repeated counterbalanced tasks, separate tracking error and compensation |

For short constant-mass/inertia windows, a calibrated IMU can support a **net** external wrench estimate. Correct the sensor offset from live CG: acceleration at a rigid offset includes `omega_dot × r + omega × (omega × r)`. Confirm whether the sensor reports specific force before adding/subtracting gravity. Use the full inertia/cross-axis/rotor terms for moments, and separate known propulsion/contact/restraint loads. This cannot uniquely allocate the remaining wrench among wing, tail and fuselage.

When fitting multiple parameters, inspect the output-sensitivity matrix and its rank/conditioning at the actual test points. Use dimensionless parameter/output scales and the declared error covariance; arbitrary units can create misleading conditioning. Near-dependent columns call for another independent observation or fewer free parameters. A low fit residual does not remove this ambiguity. Freeze the fit and test independent, previously unused trials. The existing reducers' uncertainty conventions remain authoritative. [S17, S18, S27]

## 4. Handling evaluation is a defined pilot task

Cooper and Harper treat handling qualities as task-dependent and include the control/display interface and environment. That supports recording desired/adequate task performance and pilot compensation separately. It does not supply a ready-made RC acceptance score. [S25] Delay studies likewise show that the consequence of delay depends on the controlled system and task; transport-aircraft delay limits cannot become AERIS limits. [S26]

Use the [blank pilot record](../../../research/aeris-120/pilot-evaluation.template.md) with the existing A120-C cards. Compare a frozen baseline and one candidate, counterbalance A/B order, provide equal familiarization and preserve unsuccessful attempts. Start with precise roll stops/lines, then hover recovery, both knife edges and paired harriers. Separate entry, sustained portion and exit/recovery; a stable hold can conceal a poor transition.

Record task error, corrections, saturation, recovery and the pilot's explanation of the limiting phase. A preference for easier handling is different from similarity to the identified real installation. Record the pilot's relevant experience and whether it is the exact aircraft or only the size/class. Do not average qualitative labels into a single “realism percentage.”

Freeze ground-pilot position, FOV/zoom, screen dimensions/view distance, display/achieved frame pacing, radio setup, wind and fuel. Assess audio and camera changes in their own comparisons. ExpressLRS distinguishes packet rate from per-channel update rate; neither provides this simulator's USB-to-display latency. [S30] Use the existing filmed-latency protocol for the actual route, then separately observe command-to-surface and aircraft response. A replay bypassing input conditioning cannot qualify a changed expo or device path.

## 5. Data reuse and remaining evidence

The [Glasgow collection](https://researchdata.gla.ac.uk/969/) lists a public 1 GB archive and a 15 KB README under **CC BY 4.0**; the accepted paper has different terms. The lightweight README was inspected: it describes MATLAB structures and CSV blocks, normalized/interpolated `AVU/AVV/AVW`, non-interpolated `MeaningfulMeanU/V/W`, and traverse/azimuth/radius coordinates. Filenames encode freestream, blade pitch, RPM and yaw; CSV block positions can vary. An importer should preserve named fields, masks, frames and normalization. The full archive was not downloaded or inspected. [S24]

README identity: [ReadMe_969.docx](https://researchdata.gla.ac.uk/969/1/ReadMe_969.docx), 15,201 bytes, SHA-256 `67cc683e4421b242ddb39506d1bff2485f5402efa0477f8fc4fd8a1ba12924f6`. Store original archives outside Git; any selected derived benchmark needs attribution, exact file hashes and a separate ingestion check. The existing UIUC importer accepts another format and should not be presented as a Glasgow importer.

### Small-propeller transient benchmark

The S35 preprint has an associated **CC BY 4.0** dataset. We acquired only its README and 1.76 MB thrust/RPM file, verified the published checksums, and added an [offline selector and derived result](../../../research/aeris-120/README.md#external-transient-benchmark). It describes a 0.3105 m electric propeller installation with fixed additional blade-pitch keys `00`, `05` and `10`. The stored transients are filtered ensemble means over 500 repeats, not individual trials. [S36]

For each pitch/direction trace, select the existing sample nearest 4,000 RPM, within 1 RPM, and compare with the author's stored steady fit at that stored mean RPM. The source RPM was already cubic-spline interpolated onto the thrust time base and 30 Hz filtered. The selector performs no **additional** interpolation, fit or extrapolation:

| Pitch key | Step | Stored mean RPM | Mean thrust, N | Deviation from author steady fit | Author expanded U95 of deviation |
| --- | --- | ---: | ---: | ---: | ---: |
| `00` | Up | 3999.425 | 4.5460 | −0.8872% | 0.1487 percentage points |
| `00` | Down | 4000.599 | 4.6410 | +1.1215% | 0.1365 percentage points |
| `05` | Up | 3999.199 | 5.2517 | −6.1385% | 0.2005 percentage points |
| `05` | Down | 3999.550 | 5.8459 | +4.4632% | 0.3320 percentage points |
| `10` | Up | 4000.064 | 6.1141 | −2.8034% | 0.1402 percentage points |
| `10` | Down | 4000.621 | 6.4364 | +2.2913% | 0.1773 percentage points |

These descriptive rows challenge a memoryless steady-thrust approximation **for this apparatus**. They do not identify one causal mechanism, qualify a new simulator law, or provide AERIS tuning coefficients. The source's noncausal 30 Hz filtering, absent initial 5 ms and shared fitted baseline prevent interpreting the timestamps as physical onset latency or combining the two U95 values into an independently justified paired uncertainty. [S36]

Another concrete ingestion issue is coefficient normalization: the dataset uses `CT=T/(rho*pi*R^4*Omega²)`, while conventional prop tables use `Ct=T/(rho*n²*D⁴)`. With `Omega=2*pi*n` and `D=2R`, **`Ct=(pi³/4)*CT`**, a factor of about 7.75157. The relative deviation in the table is unchanged. The selector verifies the definitions against all six full transient arrays; it does not copy the source CT into aircraft data. Source versions, license, exact hashes, dependencies and reproduction commands are retained with the kit.

No matching AERIS measurements were found for installed flow maps, gasoline torque/transients, loaded surfaces, 3D control response or pilot transfer. The original unknowns remain open. The follow-up advances source discrimination, executable reference calculations and implementation preparation; it closes no L0–L3 aircraft gate.
