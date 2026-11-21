# EDF verification and physical-validation matrix

**EDF-00 · 2026-11-21 · All future implementation/flight cases below are pending.**
This document specifies acceptance; it does not report executed EDF tests.
Actual checks on the research deliverable live in [README](README.md#verification-and-delivery).
The [plan](../../plans/edf-propulsion.md) owns step status and the
[audit](repository-audit.md) distinguishes defects from extension risks.

## 1. Verification layers

1. **Data and software:** the right input reaches the right law, with explicit
   refusal, lifecycle and identity behavior.
2. **Numerical:** the discrete implementation solves the stated equations with
   acceptable error, stability, event timing and conservation properties.
3. **Physical:** identified parameters and predictions agree with independent,
   matched observations within a declared domain and uncertainty budget.
4. **Product and target hardware:** the delivered variant works through real
   navigation, radio, audio, rendering, package and target-machine paths.

A passing lower layer does not imply the next one. Keep actual tested source,
generated-data hashes, map/installation, engine, toolchain, binary, platform,
backend, selected versus actual route, initial conditions and complete outcomes.
CI may test a merge tree instead of the branch head; record both identities.

## 2. Software and numerical cases

The existing tests listed here are precedents/regressions, not proof they already
exercise an EDF. New `test_edf_*` filenames are proposed. Preserve old assertions
and goldens; add a case only when it discriminates a real requirement.
EDF-00-R2 adds T30–T36 and strengthens native admission. A reference route below
is an explicitly selected verification oracle, never an automatic EDF product
flight fallback. Existing non-EDF fallback policy is unchanged. The
[native design](native-runtime-design.md) defines the proposed complete boundary.

| ID / owner | Stimulus | Independent expected result or gate | Existing entry point / proposed scope |
| --- | --- | --- | --- |
| T01 / AS | Valid EDF fixture; unknown kind, missing map, mixed turbine/fan fields, wrong energy kind, invalid units/axis/FSA/inertia/NaN; map bytes disagree with declared integrity identity | Runtime and offline schema agree; invalid model/data rejected under both backends, preserving accepted state | `test_aircraft_modules.gd`, `test_aircraft_contract.gd`, `test_electric_data.gd`; proposed `test_edf_data.gd` |
| T02 / EDF | Dimensional and nondimensional fan fixture, RPM↔rad/s, kgf↔N, cm²↔m², paired map points | Hand-calculated conversions and source-point interpolation; DC input never silently equated to measured shaft power; loss-based estimates retain separate provenance and propagated uncertainty | Proposed `test_edf_map.gd` |
| T03 / EDF/M5 | Uniform and gradient wind, moved datum/CG, nonzero body rate, stale stage receipt; locked rotor/body-roll counterexample | Existing WindFlow local velocity consumed once; correct moment transfer and invariant wrench power under uniform-flow datum change; finite-disc rate effects explicitly bounded/estimated or supported, not silently inferred from center flow | `test_spatial_powered_stage.gd`, `test_spatial_propulsion_flow.gd`; proposed `test_edf_installation.gd` |
| T04 / physics | Ideal stator with zero inlet/outlet axial angular-momentum flux; spool step; tilted axis; nonzero axial body rate; mirrored hardware fixture | Whole-installation moment and shaft load remain separate; full locked-inertia energy including cross term; correct polar/axial reflection, reaction and gyro once | `test_rotor_coupling.gd`; proposed `test_edf_coupling.gd` |
| T05 / EDF | RPM→0, stopped flow-on, forward/static/reverse breakaway, source-off rundown, high advance ratio; signed windmill map creating +80 W | Finite physical continuation; scoped joint aerodynamic passivity at nodes/interiors; invalid windmill pair fails despite correct individual signs; no invented regeneration or hold reaction | `test_electric_stop.gd`; EDF-specific low-speed/passivity tests |
| T06 / EDF/SF | Joint support hull/cell holes and edges; k2-only excursion; entirely synthetic map; rejected subdivisions; locator-only probes; in-flight physical-domain violation | Output-specific evidence; estimated physical and numerical-probe domains stay distinct; qualified transport or disclosed endpoint-only scope; one recoverable fault outcome for true invalid states, no silent extrapolation | Proposed map/domain/transport tests and T21 product recovery |
| T07 / EL/BAT | Partial duty, pack sag, no-load/startup/auxiliary current; fixed one-RC pulse/rest and varying-parameter qualification | Exact equivalent-port circuit; motor versus bus current; 0.60 W OCV/terminal difference = 0.35 W dissipation + 0.25 W polarization storage in the fixed fixture; variable-C residual not hidden | `test_electric_motor.gd`, `test_electric_motor_compact.gd`, `test_electric_supply.gd`, `test_battery_pack_ecm.gd` |
| T08 / EL | Current-limited startup, upward/downward command steps, saturation and recovery | Effective duty, source torque and bus meet same limit solution; stateful controller samples exactly as specified | `test_battery_esc_supervisor.gd`; proposed bounded-drive tests |
| T09 / BAT | EDF-A01 cooling-only example; fastest RC/filter/controller modes; speed/temperature-dependent bounds | Analytic exponential or refused unsafe configuration; no clamp-induced apparent success | `test_battery_session.gd`; new thermal admission/refinement cases |
| T10 / physics | Smooth/eventful cases with 240/480/960 Hz integration resolution, fixed input/controller sampling schedule and independent oracle; stable-but-inaccurate decay fixture | Production 240 Hz errors meet frozen per-observable/time-horizon budgets; refinement alone cannot pass; event-time/work bounds separate from smooth order | Existing electric refinement patterns; proposed EDF refinement harness |
| T11 / session | Analytic rotor stop within one tick with negative locator probes; near-simultaneous exhaustion/LVC/contact; static hold/forward/reverse breakaway; invalid map probe | Qualified moving-side extension retains zero-speed fan load; accurate stop time and momentum-preserving projection; accepted states nonnegative; malformed input still rolls back | `test_electric_event_localization.gd`, `test_electric_battery_step.gd`, `test_electric_contact_step.gd` |
| T12 / session | Pause, reset, relaunch, invalid reload and failed trim at low SOC | All EDF/pack/controller states reset or remain accepted as specified; no stale mode or partial state publish | `test_electric_battery_session.gd`, `test_electric_equilibrium_preparation.gd` |
| T13 / session | Stage NaN, invalid map/context/event overflow; ordinary native event/step observer, protected-state mutation, forbidden synchronous transition reentry and explicit failure report | Precommit refusal keeps prior frame. Proposed native publication guard keeps new commit and pauses/faults on detected violations; test each signal's visibility, notification continuation and recording completeness. Allowed read/pause works; no universal engine-error recovery claim | Existing reset/restore guards are precedents, not ordinary-tick coverage; extend native capability tests while preserving legacy listener behavior |
| T14 / FL | Complete EDF flight, checkpoint, restore, exact replay, wrong map/controller/layout/backend | Matching replay follows existing exact contract; mismatches refuse, old turbine recordings stay matched to old laws | `test_flight_log.gd`, `test_flight_log_empty_continuous.gd`; EDF identity fixtures |
| T15 / trim | Rested versus conditioned pack snapshot; powered trim; zero-duty/disconnected stable windmill root, held stop/no root; source-off launch and first tick | Body/shaft/bus residuals and expected resource/controller drift match the declared initialization; no hard-coded glide zero falsely called equilibrium; precise refusal where no admissible root | `test_electric_propulsion.gd`, `test_electric_trim_reuse.gd`, `test_electric_runway.gd` |
| T16 / NK | At least 10,000 prepared/stage states including zeros, knots, event neighborhoods and malformed input, plus full eventful native ticks and restored continuation | Required matching-host byte parity, exact trajectories and actual native-call coverage; stage parity alone does not qualify native input/events/world/session closure | `test_native_stage.gd` and extended `research/native-kernel/` qualification tools |
| T17 / NK | Stale native map/geometry/layout receipt versus invalid model data; unauthorized state-slot mutation, mismatched binary/engine, unsupported capability and live mutation | Missing/refused native EDF capability disables launch; no automatic reference EDF flight. Integrity-invalid data refuse both native and explicit test oracle; live guard refuses before evaluation; valid evolving state remains supported; no mid-flight switch | Native admission/negative controls and immutable source receipts; preserve non-EDF policy |
| T18 / AV/AS | Regenerate both siblings; load fresh EDF output, pack mount and model descriptor | Sources generate exact outputs; distinct IDs; correctly recomputed mass/CG/inertia, no fuel burn in EDF | AV-06 and battery generator checks; proposed EDF sibling generator `--check` |
| T19 / GP | New mass/load distribution, downlocked gear and flight attitude envelope | Positive static support, reserve-energy/travel and valid carrier tensor; no inherited turbine-only mass range | `test_gear_visual_contacts.gd`, `test_gear_reserve_energy.gd`, relevant ground checks |
| T20 / GP/CR | Internal fan geometry near ground/water; corresponding exposed-prop regression | No phantom internal-fan blade strike; existing prop disc strikes remain; hull contact still operates | Hull/contact tests and proposed EDF internal-fan case |
| T21 / UI/input | Home/stand/preview/direct/restart ideal/pack mapping; arming/gear/flaps; missing native capability and in-flight out-of-domain failure, reset/Home recovery | Loaded source law matches label; native admission enforced on every route; one visible paused/fault state, accepted frame retained, no retry loop/false clock or complete-recording claim; no hidden law/backend switch | Catalog/UI/arming tests plus rendered/manual flow and T34 raw-input coverage |
| T22 / AUD/SM | Both siblings under default/legacy audio and requested Avanti show smoke; start/load/cutoff/pause/reset/stale epoch/listener changes | EDF-safe handling or explicit unsupported option; native EDF observer, no combustion-field access, invalid smoke binding or phantom effect; complete physics checkpoint identity with audio on/off | Existing audio/smoke tools plus real-driver PCM/listening; Dummy driver proves routing/lifecycle only; T35 spectral case |
| T23 / HUD/trace | Compare displayed/recorded RPM, current, volts, power and source/domain flags against accepted frame | Correct current convention/units, no per-frame state advancement, no invented temperatures | Overlay/trace tests; `test_overlay_battery_flight.gd` patterns |
| T24 / flight | Discriminating native EDF flight card below, complete recorder; isolated finer-step comparisons retain the same 240 Hz input/controller schedule | Complete repeatable software maneuver and declared domain coverage; numerical refinement does not alter the production flight clock; sibling comparisons initialize/trim separately; physical performance remains separate | Flight-test tools and matching `.orfl` recordings; raw-conditioning evidence belongs to T34 |
| T25 / regression | Existing electric/glow/turbine siblings, related contact and recorder consumers | Preserved intended behavior and existing goldens; any intentional law change explained independently | Focused family tests first, required CI on stable integrated candidate |
| T26 / DT | Each advertised Windows/Linux/macOS package/architecture: cold launch, native prepare, reset/replay/restore, shutdown and missing/mismatched library | Actual complete native EDF route, matching data/engine/API/ABI/bindings/library/dependencies; missing support disables EDF. Keep descriptor reload policy and non-EDF behavior; source/editor success is insufficient | Current desktop/native package gates extended with EDF capability and lifecycle receipts |
| T27 / PT | Matched native production flight and event-heavy workload on target hardware, observers on/off and uninstrumented release control | Separate law/bridge/full numerical tick/full callback distributions; existing 500 µs gate keeps its owning statistic/workload; p50/p95/p99, observed tails/max, frame pacing, counts and exact identities; smoothed `step_usec` is not full callback | Existing GOD TEST/performance tools; serialize competing benchmarks; T36 detailed receipts |
| T28 / AE/EM/NR/AC | Optional editing/failures/scenarios/imports or deliberate exclusion | Supported routes pass own gates; unsupported routes reject explicitly; old scenario seeds/import meaning preserved | Owning Workshop, failure, scenario and Creator tests |
| T29 / AV | EDF-A02 exact threshold, zero-flow root neighborhood, source-on/off and idle/full conditions | Finite defined turbine law or explicit refusal, native parity and unchanged supported endpoints | `test_turbine.gd`, `test_turbine_continuous.gd`; separate AV repair |
| T30 / SF/NK | Native capability inventory; trap each GDScript numerical callback; deliberately mutate native law result; missing stage/tick/control/weather/contact capability | Complete native path exercised, traps/mutant detected; no new EDF solver/clock/accepted-state owner; incomplete capability refuses flight, including direct/restart/restore routes | Proposed generic native-tick harness and admission receipts; independent oracle plus T16, not a loaded-library assertion |
| T31 / SF/GP/FL | Save pre-break checkpoint → accept break → save post-break checkpoint → second pass; restore each checkpoint and repeat; rejected hit; terminal/restart effects; T13 observer cases | Restore each checkpoint's exact intact/broken proxy, damage and RNG state; effects commit/checkpoint together; rejected trials publish nothing. Proposed native event/step observers see the complete commit; detected violations retain it; tie/grazing scope declared | Extend owning contact/session/checkpoint tests with native tick and independent event expectations; preserve non-EDF ordering/reentry |
| T32 / EDF/NK | Passivity-valid vertices with invalid interior; independent versus common tuple blending; knots/holes; reversed query order and lookup hint on/off; oversized map | Actual scoped interior energy condition fails known counterexample; fixed-input common-weight complete tuple preserves the affine condition; deterministic outputs/refusals and bounded prepared memory | Native pure-map property/fuzz targets, independent cell analysis and qualification oracle |
| T33 / EL/BAT | Ideal active limiter with 48 V, 0.2 Ω pack, no auxiliary load, 12 V back-EMF, 0.1 Ω motor, 40 A motor limit; saturated/degenerate roots; source off; 1 ms winding mode | R2-05 independent circuit gives duty 0.354248689, bus 45.16601049 V, pack 14.16994756 A and 640 W; source-off circuit explicit; an unsplit 240 Hz RK4 winding mode with amplification 6.016235854 is rejected, not clamped | Proposed native operating-point tests; compare bandwidth/topology consistently; no hardware ESC equivalence claim |
| T34 / input/M5/SF | Identical timestamped raw-event/tick-assignment tape through native arming/rates/expo/yaw/keyboard conditioning; turbulence RNG; rejection/pause/rearm/reset/restore; varying render cadence | Frozen sample schedule and checkpointed conditioner/RNG produce expected commands/states; rejected trials consume no hidden state. Identical accepted tick-samples give identical simulation outcomes across render cadences; live device delivery/arming latency is measured separately | Proposed raw-input harness with independent expected sequence plus live-input latency checks; `.orfl` starts after conditioning and cannot substitute |
| T35 / UI/AUD | Native Godot Home → stand → preview → flight → debrief; keyboard/controller focus; unknown thermal/ideal charge labels; accepted 14-blade 45,000 RPM at 48 kHz output | Labels match force boundary/evidence/accepted result; no UI physics mutation; 10.5 kHz fundamental, 31.5 kHz third harmonic must be filtered/omitted before output; no stale-epoch sound | Actual rendered review plus native-driver PCM/spectrum/listening and checkpoint parity; no generated concept art claimed as gameplay |
| T36 / NK/PT/EDF | Warmed normal/event/refused native ticks including bridge allocation/copies; predeclared eight-corner-plus-center virtual campaign | Record scoped allocation/latency raw samples and identities; no allocation-free/speed claim without measurement. Every campaign case retains source/map/generator/card/seed/outcome, consistent mass/wrench and refusal status | Existing native/debug/flight tools with focused extensions, separate diagnostic/release runs; synthetic campaign is not physical validation |

### Numerical acceptance policy

Use analytic expectations for independent electrical circuits, cooling,
steady stator cancellation, angular momentum, full coupled energy and fixed-RC
storage. The [calculator report](calculations.json) contains small synthetic
oracles and deliberately invalid examples, not implementation tests. Use measured data only for
physical parameter/prediction comparisons. Do not generate all expected results
from the same implementation under test.

EDF-01 must freeze a budget before accepting implementation results: each
observable's units, norm, absolute floor, relative scale, duration and applicable
regime, plus independent oracle precision and event-time/work budgets. Cover
rotor speed, bus current/voltage, body position/attitude/rates, charge and modeled
temperatures. Use orientation error rather than raw quaternion-sign differences.
A declared form such as `error_j <= atol_j + rtol_j * scale_j` needs actual
justified values in the fixture manifest before it can pass; missing budgets are
an incomplete gate. Do not choose limits after viewing candidate errors.

Tolerances need a written basis: rounding, interpolation, solver truncation or
measurement uncertainty. Exact native/replay policies remain exact where required;
do not weaken them to hide a new backend discrepancy. For smooth trajectories,
compare 240/480/960 Hz and a separate high-accuracy reference, then justify the
observed convergence **and** satisfy the production 240 Hz error budget. For
`y'=-480 y`, a 240 Hz RK4 step has stable amplification `1/3` but the exact
factor is `exp(-2)`: about 146% relative error in the remaining state. Its finer
solutions converge, which cannot make the original step accurate.
Hold the physical input history and sampled controller schedule fixed during
integration refinement; doubling controller updates changes the modeled system.
Refine complete coupled stages, not just one stiff subsystem without justification.
At stop, cutoff and interpolation boundaries, inspect event
time, state jump/projection, bounded event counts and total work/energy separately.
Include long-duration and repeated reset cases for charge/temperature drift.

The report must distinguish a requested backend from the one actually used.
Native/reference agreement can preserve the same wrong physical model; it is not
an independent calibration oracle.

## 3. Physical validation cards

The initial thrust/current/endurance targets reuse the existing
[EL physical-promotion policy](../../ELECTRIC-PROPULSION-PLAN.md#physical-reference-and-promotion):
±10% thrust/current and ±15% endurance, with the project's uncertainty rule.
Choose reference magnitudes and absolute tolerances **before** collecting final
validation data; relative percentages are ill-conditioned near zero thrust,
zero current and zero residual torque. Dynamic timing, residual moments and
temperature need their own predefined limits, not an invented universal EDF spec.

| Card | Controlled factors and measurements | Discriminating result |
| --- | --- | --- |
| V01 — static fan and source | Exact hardware/firmware/installation, independent acquisition/run IDs, multiple conditions, thrust/terminal volts/current/RPM and independent torque where available | Matched fit plus independently acquired validation; withholding points on one digitized curve is only interpolation evidence. DC, shaft and balance quantities stay separate. |
| V02 — dynamic drive | Step direction/size/history, controller settings, SOC/T; synchronized filtered RPM, bus current, thrust and voltage; declared sensor/filter bandwidth | Response and equally filtered bus-current peak errors on independent steps. Phase/switching peaks are outside an averaged model's claim; no universal spool time constant. |
| V03 — installed airflow | Identical powertrain with actual ducts; airspeed, incidence and sideslip; net six-component load, tare and pressure/flow when available | Installation loss and moment identified without counting inlet/duct loads twice; domain of valid continuation stated. |
| V04 — power-off | Stopped/freewheel/source loss, wind-on speed and restart; RPM, drag and electrical state | Correct aerodynamic restart/drag and no false regeneration; undefined brake mode is excluded. |
| V05 — energy/thermal | Real pack identity, pulse/rest capacity/impedance/weak cell, cooling, sensor locations and independent measured mission current/temperature history | Score voltage, cutoff and temperature separately; entropy heat/spatial hot spots remain unmodeled unless identified; lumped temperature does not qualify hottest-cell safety or motor/ESC temperature. |
| V06 — aircraft | Actual mass/CG/inertia, installed system, radio conditioning and pilot; flight card with atmospheric and surface conditions | Measured aircraft outcomes and pilot evaluation distinct from simulated consistency. |

After identifying the hardware/instruments and before acquiring or inspecting
final held-out observations, freeze the applicable physical-card protocol.
Exploratory/fit observations may inform it but cannot also serve as validation.
This physical-track milestone is not a prerequisite to synthetic runtime coding.
Before a physical card can pass, its acquisition protocol must specify the
measurand/error definition and normalization, absolute scales near zero,
sensor calibration/bandwidth/tare, independent run unit, repeat plan and fit versus
validation allocation. Define `Ue` as either an explicit bound or a computed
expanded uncertainty with its coverage factor and supported interpretation;
retain component uncertainties and covariance/common systematic effects. Do not
call one standard uncertainty a 95% bound by default. NIST's combined, expanded
and reporting guidance is recorded as S28–S30 in the [source study](physics-and-sources.md).

Predeclare the campaign decision: which points/regimes must each pass, any
permitted aggregate metric and its coverage, and how failed/inconclusive points
restrict the claimed domain. Dense samples from one smoothed curve are not
independent repetitions. Missing protocol/data makes the physical card
inconclusive; it does not block a labeled EDF-02a/10a software experiment.

For a consistently defined error `e`, uncertainty `Ue` and limit `L`, pass only when
`abs(e)+Ue <= L`; fail when `max(0,abs(e)-Ue)>L`; otherwise report **inconclusive**.
This is the project decision rule, not a manufacturer requirement. Keep calibration
and validation runs independent; a separate plot of the same fitted points is
not a held-out dataset. Measurements require synchronized channels, calibrated
instruments, retained raw data, units and declared filtering/tare.

## 4. Same-jet comparison card

The purpose is to compare propulsion changes on the A200 while revealing mass,
balance and throttle-response consequences. Record both siblings' own trim and
source identities. Equal transmitter commands do not imply equal power or thrust.

| Maneuver | Outputs | What it resolves |
| --- | --- | --- |
| Runway start and takeoff | Rotor speed, current peaks, thrust, battery voltage, wheel loads and takeoff distance | Spin-up, current limiting, mass/ground changes and low-speed integration. |
| Level trim at several speeds | Throttle, RPM, current/power, drag, elevator and domain flags | Forward-speed fan map and sustainable operating points. |
| Hands-off power steps | Attitude/rates, acceleration, rotor speed, residual torque and source power | Offset moments, stator versus rotor reaction and transient coupling. |
| Climb and go-around | Airspeed, climb rate, thrust/power, SOC and temperature | Useful power, load and energy consequences. |
| Throttle-off glide and restart | Drag/sink, fan speed, source state and restart current | Windmilling and bounded stopped continuation. |
| Flap approach and landing | Trim/pitch, airspeed, current reserve and ground/contact events | Shared airframe controls with the new mass and power response. |
| Low-SOC / hot-high repeat | Cell voltage, cutoff timing, temperatures, takeoff/climb margin | Pack/atmosphere interaction and limits. |

Use the existing [flight logging workflow](../../FLIGHT-LOGGING.md). Preserve
each baseline recording before changing parameters. Exact replay stays within
the matching model/solver/backend; candidate replay requires explicit
compatibility and consumes recorded post-conditioning commands. It cannot
retest radio conditioning, retrim an aircraft, or model pilot adaptation.
T34 therefore owns a separate raw-input fixture. Record sampled input, RNG and
world-state continuation in the native identity/transaction, not in an observer.
For a different sibling, use a separately initialized controlled card unless the
existing tools explicitly support the compatible comparison. Retain complete
recordings, CSV, markers and reports; recovered prefixes are not complete flights.

EDF-11's virtual campaign uses a predeclared 2×2×2 design plus a center case for
pack resistance, mount mass and a coherent installation-loss assumption. Generate
the complete affected mass/CG/map data, retain every refused/out-of-domain case,
and use separately initialized cards. The interaction patterns describe the
assumed models; they are not measurement uncertainty or physical confidence.

## 5. Efficient execution and evidence

Use the repository's [tool index](../../tools/README.md),
[verification scope](../../tools/shared.md#verification-scope), checked runner
and [test queue](../../../tools/testqueue/README.md). Headless compatible work
uses the configured pool or permitted checked local path, with source-frozen
receipts. Do not bypass an unavailable enrolled-host authority. Serialize
interactive/rendered/performance resources and retain ownership through teardown.

During implementation, run the smallest relevant new/existing checks, then the
affected boundary checks on a stable candidate, followed by required CI. Do not
run every benchmark after a documentation edit. Preserve the current full CI
policy; this plan does not add skips, relax assertions or rerun unchanged failures
until they happen to pass. Investigate failures and record inherited versus new
behavior. Publish no release or merge on the strength of a pending CI run.

Store compact evidence with the owning step: source and data identities,
command/entry point, test matrix, actual route, verdict, measured error/uncertainty
and unresolved limits. Keep raw bulky logs/captures in the established retained
artifact workflow. The EDF-00 calculation report is reproducible planning
arithmetic only; it is not any of T01–T29 or V01–V06 passing.
