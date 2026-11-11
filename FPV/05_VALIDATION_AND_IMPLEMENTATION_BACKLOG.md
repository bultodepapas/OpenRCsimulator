# FPV implementation backlog and validation gates

**Baseline:** `7bff78490f9af5c1664f47c8ba865a92b3430920`, 11 November 2026. **Status:** proposed work and pass/fail contracts, except the explicitly executed evidence in §1. **Normative proposed design:** [02](02_ENGINEERING_CONTRACTS.md). **Source/test map:** [06](06_SOURCE_AUDIT_AND_EVIDENCE.md).

## 1. Evidence already obtained

| ID | Executed work | Result | What it establishes |
| --- | --- | --- | --- |
| E-01 | Unmodified `test_dr_multirotor_kernel.gd` on a 73-source byte-identical dependency copy; minimal headless project, pinned Godot `4.8.beta2.official.cafc17a19` | 15 checks, 0 failed; checked runner `ok=true`, `complete=true` | Existing laboratory hover/sign/drag/wind/twin-run/checkpoint assertions under that isolated configuration |
| E-02 | Isolated changed-duty/malformed-k2 probe followed by two reset preparations | Kernel arrays rolled back; private duties did not; stale yaw reset load 0.787007672634271 N·m versus 0 after priming | A reproducible transactional cache gap in the frozen source; successful probe exit means the defect was reproduced |
| E-03 | Standard-library reference calculations, repeated with byte-identical report | 20/20 cases passed | Arithmetic/convention checks for rates, mixing, angular momentum/work, shared bus, units, clearance, FOV and sampling |
| E-04 | Current code and primary-source review | Immutable source links and specific proposed interfaces | Current implementation knowledge and research basis, without empirical flight validation |
| E-05 | Settings follow-up: pinned BF 2026.6.2/INAV 9.1.0 source review and reference audit | 34 investigations; 177 valid current source links across 50 distinct primary files | Version-specific semantics, defaults/units/scopes and proposed dispositions; no firmware/controller equivalence |
| E-06 | Extracted BF throttle functions and initializer compiled on the documented host | 14 evaluations repeated with identical output; 30/70/0 at input 0.30 gives 1663 PWM under stated assumptions | Scoped current source-path observations; not 14 acceptance passes, a full firmware build, OpenRC behavior or hardware evidence |
| E-07 | Simulator/product/user desk research and independent design review | 28 approaches; 22 consumer-facing products/editions; 23 coded community threads; dated primary sources in 12 | Research-supported design hypotheses and bounded future experiments, not hands-on comparisons, a representative survey or physical validation |
| E-08 | Open-source code/license inspection, discussion coding and critical integration review | 25 admitted project approaches; exact source/license pins; 19 discussion records; eight excluded/scoped examples in 13–15 | Scoped code presence, reuse constraints and proposed experiments; no external build, simulator benchmark, firmware equivalence or physical measurement |

These results do not establish a working controller, product data, accepted new ABI, native rendering, device latency, exported drone route, physical aircraft fidelity or a passing full repository suite. The original 15-check test does not cover failed-tick cache restoration, disarm, a pack, controller state or continued closed-loop replay. Preserve this distinction in PR descriptions.

## 2. Reviewable work packages

New paths below are proposals. Existing DR IDs retain their ownership; suffixes divide work without redefining historical completion. Each PR contains one independently reviewable behavior and its focused evidence. The exact path names are frozen with the owning reviewer before implementation.

| Package / IDs | Deliverable and likely files | Depends on | Completion evidence |
| --- | --- | --- | --- |
| P01 — DR-01/02/03 | Dated audit; build/data/asset ledger; reference-oracle harness under `research/drone-racing/`; source pins and missing measurements | Current baseline | References resolve; calculations reproduce; asset/data status truthful; no fixture masquerades as product |
| P02 — DR-16a.1 | Generic explicit callback protocol, full accepted-frame sample and sampled stage context; `vehicle_model.gd`, `simulation.gd` | P01, SF review | TX-01…05; all joint-stage predicates/dispatches covered; legacy behavior preserved |
| P03 — DR-16a.2 | Opt-in full-frame reset preparation/commit and restore-context proof, registered state guards | P02 | TX-06…10; owner seals and observer faults; no old-flight mutation on refusal |
| P04 — DR-10/11/13 | Strict sibling schema/loader, immutable preparation, versioned research generator; proposed `multirotor_data.gd` and schema/generator files | P01/P02 layout | DATA-01…08; generator `--check`; independently checked balance/geometry |
| P05 — DR-06/07 | Separate controlled laboratory law, PID/Angle/allocator, explicit SI gains and state, independent controller reference | P02–P04 | CTRL-01…06, PHY-01…04; no hidden state; conservation approximation declared |
| P06 — DR-08/09a/15 | Versioned Actual and admitted rate curves; scoped profile parser; fixed-sample refinement/cost harness | P05/P17; conditional P19a if 240 Hz fails NUM-02 | CTRL-07…09 and NUM-01/02; malformed/unsupported fields reported; no waiting for P11 to repair failed sample-rate qualification |
| P07 — DR-16b/17 | Dedicated headless session, accepted tape, full checkpoint/record/replay adapter | P03–P06 | REPLAY-01…06; complete exact replay; M1 exit |
| P08 — DR-05/12 | Sourced product generator, four-load one-pack stage, motor/prop/pack identities and accounting | P01/P04/P07, EL/BAT review | PHY-05…09; static-data fit/residuals and explicit estimates; no unsupported braking |
| P09 — DR-09b/18/19/20 | Qualified hybrid contact/stop/depletion policy, event-local drive cut, flat-pad support, crash/reset | P03/P08, GP/CR + SF | EVENT-01…08; CONTACT-01…05; bounded work and domain/refinement proof |
| P10 — DR-14/15 | Pre-expo calibrated pilot adapter, actions, arm/hold/recovery, throttle policies, global input-buffer ownership | P07/P09, UI/input | INPUT-01…10; old vehicle profiles and real-device evidence preserved |
| P11 — DR-21/22 | Product controller requalification, endurance and whole-step cost campaign | P08–P10 | CTRL/NUM/PERF gates on final physical data; no lab-gain carryover assumption |
| P12 — DR-29/30/31/35/37 | Licensed visual adapter, four rotor views, FPV, honest OSD/basic licensed sound, restart UX | P01/P07; final data before release | VIS-01…08; native 1080p interaction and asset/axis/clip checks |
| P13 — DR-36a | Explicit catalog/Home/CLI/capability routing, preview cancellation, fresh export | P09–P12 | ROUTE-01…07 and relevant fleet/CI gates establish an implemented route candidate; final M2 admission follows relevant P21 and P22 qualification |
| P14 — DR-23/24/32 | Strict track/rule loader, one upright-gate course, matching solids/scoring/visuals, world identity | P09/P13, SC/LU | RACE-01/02/03; geometry/admission/native readability |
| P15 — DR-25/26/36b | Accepted-path policy receipt, pure composite endpoint race director, canonical events, checkpointed three-lap state, terminal result projection | P09/P14 | RACE-04…15 plus replay and PERF on race workload; M3 exit |
| P16 — DR-04/38/39/40 | Advanced-law comparison, pilot campaign and selected-build measurement | Stable identified product/reference | DATA-09; PHYS-01…06; M4 claims scoped to observed envelope |
| P17 — DR-10/15 | Versioned settings schema/adapter registry, typed units/defaults/profiles, bounded import and support report | P01/P04 | SET-01/23/24/28/29/33 and IMP-01…10; no stale defaults, unknown effects or unsupported active controls |
| P18 — DR-14/15/29 | Qualified pilot subset, profile preview/apply, explicit armed-hold reset action and settings UX | P02/P03/P06/P10/P17 | Rate/throttle/input cases; CFG-01/02/08; native 1080p workflow and fresh arm evidence |
| P19a / P19b — DR-09a + SF; then DR-21/22 | Conditional generic faster sampled-event protocol; later sensor/filter/noise/telemetry harness | P19a: P02/P03/P05, before P06 closes if NUM-02 fails; P19b: qualified P11 | Fresh-feedback/phase/rollback proof, SET-04/13…17 and NUM gates; advanced filters do not block the early scheduling repair |
| P20 — DR-07/12/21 | Optional independently identified FF/relaxation/TPA/anti-gravity/launch/dynamic-idle/voltage modules | Qualified base controller, plant and required sensor/scheduler capabilities | SET-06…09/11/12/19/20/22; bounded state, dependency and replay tests; inactive until separately admitted |
| P21 — DR-17/30/36 | Settings identity/support report, recording fields/decimation and route/export integration | P07/P17/P18 and implemented P13 route candidate, not already-admitted M2 | SET-29…33; CFG-03…08; full replay remains independent of diagnostic downsampling |
| P22 — DR-14/15/29/36a | Practice usability qualification through existing input/settings/Home/FPV/reset paths; normative journey and cases in 11 | P10/P12/P18/P21 and P13 route candidate | M2 portions of UX-01…04/07 and EXP-01…04/12; existing native/input/lifecycle gates. No course/race or physical-flight dependency; then final M2 admission |
| P23 — DR-27/28/30/36b | Local compatible ghost, read-only replay inspection and optional short drills, as separately reviewed increments | P07/P15/P21; M3 timing qualified | PRACTICE-01…03 and relevant UX-05/06/EXP-05…07 in 11; no physical side effects or invented race authority |
| P24 — DR-23/24/32 + SC/LU | Validated local course authoring/import/export on P14 data; approved existing assets | M3 course/geometry stability | AUTHOR-01…03/EXP-08 in 11; semantic round-trip, geometry agreement and actual flown/replayed result; optional after M3 |
| P25 — DR-04 + SF/flight dynamics | Optional source-pinned matched-subset comparison harness; manifests, transforms, native/normalized traces and discrepancy report in 14 | Source preparation alongside P01; plant cases on identified candidate; closed-loop cases after P07/M1 | OSS-REF-01…08; source/parameter/clock/lineage identities and declared convergence evidence; not physical validation or an additional M1/M2 release gate |
| P26 — DR-09a/15/17 research + SF | Optional separate firmware-bridge feasibility: RC/sensor boundary, causal samples, exact clock, sequence/epoch, idempotence and state inventory in 14 | Concrete sampled-control/replay contracts; production bridge proposal only after M2; broader robotics interoperability after M3 | OSS-BRIDGE-01…07; complete lifecycle proof or explicit research-only disposition; no hidden firmware state or second plant authority |

P01 assets/data research can proceed alongside P02/P03. P12 presentation can prototype on an explicitly marked fixture. Shared kernel/input/catalog work has one writer per path. Do not parallelize native performance campaigns on the same host or mutate a source snapshot during a run.

P13 implementation/route qualification → relevant P21 integration → P22 M2-only campaign → final M2 admission is the intended order. P14/P15 course/race checks, P23/P24 and PHYS-05/06 are not prerequisites for that campaign. Shared experiment IDs in 11 explicitly separate their M2 free-flight, M3 course/race and M4 physical arms.

The 21 proposed open-source follow-up cases live in [14](14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md): eight reference, seven bridge, three diagnostic/input, two world and one data case. They strengthen P25/P26 and existing P22/P23/P24/P16 work; they are not executed results or blanket release gates. Scanned worlds, external robotics stacks, synthetic radio impairment and learned residuals remain optional capabilities with their stated milestone boundaries.

## 3. Transaction and lifecycle checks

The test IDs below are a proposed acceptance ledger. They are not existing test filenames or passing implementation claims. The lead should add appropriately scoped `test_mr_*`/`test_race_*` files following the repository's existing SceneTree test pattern and checked runner.

| ID | Discriminating case | Required result |
| --- | --- | --- |
| TX-01 | Sample the same accepted frame/input twice | Identical candidate bytes; previous frame/configuration unchanged; one accepted sample per tick |
| TX-02 | Inject malformed k1, k2, k4 after a new command/filter update | Body, rotors, pack, controller, modes, action cursor, race and registered environment state restore; sticky fault/pause expected; no accepted recorder row/event |
| TX-03 | Stage mutates passed sample arrays, captured registered config or callbacks; callback reentry | Refusal with guarded state restored; tests explicitly state finite guard scope and do not claim global sandboxing |
| TX-04 | Plant substeps and policy trial stages | Same held controller command throughout; no extra PID/filter/virtual-throttle updates |
| TX-05 | New-protocol joint-stage detection and each dispatch route | Correct stage family at reset/k1/k2–k4/policy/substeps; no silent legacy split/default-load path |
| TX-06 | Prepare reset with new aux/rotor/mode/input values while old flight/recorder is active | Detached candidate evaluation; rejected candidate changes nothing; accepted full frame publishes together |
| TX-07 | Commit a reset candidate on another owner or after identity/config changes | Refused; owner seal and prior flight intact |
| TX-08 | Restore old checkpoint after later commands/filters/crash state | Next accepted command, loads, state and events equal a fresh control from that checkpoint |
| TX-09 | Observer throws/faults after an accepted tick/reset | Correctly classified committed observer fault; accepted state not relabeled rejected/rolled back; recording completeness handled |
| TX-10 | Observer captures checkpoint directly inside kernel signals | Cursor, source, controller and race correspond to the same accepted physics tick; storage reclamation timing irrelevant |

Fault tests include event, endpoint, projection, final-validator, reset and restore refusal points, not just a successful RK path. Keep intentionally malformed runs isolated and recognize expected faults explicitly so error suppression cannot make a test pass accidentally.

## 4. Data, physics and event checks

| IDs | Required cases and independent evidence |
| --- | --- |
| DATA-01…04 | Unknown/missing keys; wrong unit/type; NaN/Inf; duplicate/missing motor; malformed axis/spin; bad source or configuration hash; incompatible law/state layout. Each rejects before accepted-session replacement. |
| DATA-05…08 | Mass/CG/full-inertia inventory independently recalculated; locked/effective inertia positive definite; actual prop/frame/prop clearances; impossible hover and pack voltage refusal; generator bytes reproducible. Test 5.0 versus 5.1 inches explicitly. |
| DATA-09 | Separate whole-flight/maneuver fit and held-out sets; no adjacent-sample leakage; documented frames/filtering/timing alignment, omissions and per-regime residuals. |
| PHY-01 | Per-motor and all admitted spin-layout signs in FRD; arbitrary attitude/frame rotation checks; static synthetic wrench `[4, .08, .04, .008]` maps to `[.5, 1.1, 1.3, 1.1]` N under the stated fixture. |
| PHY-02 | Free angular momentum conservation with one/asymmetric/four rotors and nonzero body rates; independent 100 W motor-work oracle including kinetic cross term. |
| PHY-03 | Hover with unequal hubs/CG/loads; minimum and full admissible pack state; residual force/moment thresholds scaled to declared quantities. |
| PHY-04 | Drag passivity in appropriate air-relative coordinates, wind/frame covariance and no double-counted rotor/body drag. Wind may do work in the world frame; do not misuse a still-air energy assertion. |
| PHY-05 | One shared bus with four equal motors, mixed active/coast motors, disabled motor, unequal resistance/back-EMF, zero pack resistance and near active-set equality. Check same bus on every load. |
| PHY-06 | Stage power identities and integrated charge/chemical/terminal/loss accounting. Separate copper, pack, ESC and mechanical losses and state each model simplification. |
| PHY-07 | `Q→0`, stopped rotor, overrun/coast, zero drive and armed idle; reject invalid stages or use only a qualified locator continuation. |
| PHY-08 | No unsupported signed current/regeneration; no artificial speed lag stacked on an already identified electromechanical response; empirical map carries its own energy limitations. |
| PHY-09 | Manufacturer-row conversion/fit against RPM and voltage, withheld-row residuals, displayed torque precision, static-domain bounds and explicit missing transient/forward-flow evidence. |
| EVENT-01…03 | One and four simultaneous stops; stop + depletion; root exactly on interval endpoint; finite bounded work; accepted state remains in domain. |
| EVENT-04 | Interior crash/strike at half a tick. Later subintervals use terminal cut latch; compare to independent piecewise zero-drive reference. Preserve/log the nonzero sampled commands and separate cut time/effective zero drive; terminal restore still cuts drive. Test roots before/after RK stage times and do not reuse pre-event k1. |
| EVENT-05…08 | Crash + depletion/stop ties; cut-latch domain/monotonicity/reset/restore; invalid receipt/work cap; rejected post-event stage. All changes rollback together; no late drive or false event publication. |
| CONTACT-01…05 | Flat-pad solved support, static friction/tip-over, armed idle without spontaneous flight, touchdown, swept prop/hull versus terrain/post/edge, high-speed tunneling and stationary-blade hull. Qualified geometry and independent analytical/contact fixtures; no claims for untested slope or rotated proxies. |

### Tolerances

Freeze each quantity's absolute plus relative tolerance before viewing candidate results. The included Python oracles use `abs_tol=rel_tol=1e-10` for their well-scaled synthetic double-precision arithmetic. That is not a universal trajectory, sensor or manufacturer-data tolerance. For imported firmware curves, compare against both independent double-precision vectors and the pinned firmware's single-precision evaluation using an explicitly justified output tolerance; bitwise equality across precisions is not required.

For energy/momentum trajectories, report residual versus integration step, physical scale and integration duration; identify external work and the reference invariant. For discontinuities, compare event time/state/work with a refined or analytic solution, rather than demanding smooth fourth-order convergence across an event. A residual small only because both sides reuse the same faulty helper is not an independent oracle.

## 5. Controller and numerical qualification

### Required controller cases

| ID | Case | Required evidence |
| --- | --- | --- |
| CTRL-01 | Acro zero/positive/negative commands on each axis | Correct direction, zero-stick rate target without self-level; cross-axis behavior explained |
| CTRL-02 | Bounded allocation | Feasible motor commands; deterministic objective/ties; requested/allocated/produced wrench distinction |
| CTRL-03 | Low throttle / Airmode | Correction authority within admitted limits, collective shift documented, disarm always overrides idle/correction |
| CTRL-04 | Sustained saturation and release, each axis plus combined axes | Correct anti-windup direction, bounded integral, defined yaw/roll/pitch/collective priorities; stable recovery |
| CTRL-05 | Mode switches and Angle limits | No unintentional yaw target/derivative kick; explicit inverted/near-vertical admission or refusal |
| CTRL-06 | Low voltage, changing pack load and asymmetric available motors | Stable declared behavior; no nominal-voltage allocation assumption presented as achieved authority |
| CTRL-07 | Actual and each supported rate family | Full signed curves, center slope, endpoint and separate rate cap; no duplicate deadband/expo |
| CTRL-08 | Import dump/diff with multiple profiles and omitted defaults | Exact pinned profile semantics or explicit refusal; no cross-profile leakage; ignored-field report |
| CTRL-09 | Unknown firmware/rates/filter/PID/motor fields | Specific unsupported result; no claim of complete firmware migration |

### NUM-01 — plant refinement at fixed control times

Hold controller samples at `k/240` seconds and the same command tape/initial state. Refine the plant's accepted intervals at `h`, `h/2`, `h/4` (initially 1/240, 1/480, 1/960 s), with refinement beyond h/4 if the reference still moves materially. Use hover, throttle punch/chop, axis doublets, sustained high-rate rotation, descent, contact and stop/depletion. Keep control/filter scheduling constant. Report position, orientation angle, body rates, rotor speeds, charge/energy and event-time differences. Contact/event cases have their own convergence interpretation.

### NUM-02 — controller sample/phase qualification

Use a sufficiently refined plant and compare 240 versus 960 Hz closed loops, then 1920 Hz when needed to show reference convergence. Every controller sample must receive fresh plant feedback. Use a continuously timed pilot/setpoint tape and explicit sample-edge/phase offsets. Do not reinterpret four solver substeps as four feedback samples.

Proposed **engineering screen**, inherited and completed from the earlier plan: rise-time error ≤15%, settling-time error ≤20%, and overshoot difference ≤5 percentage points relative to the qualified high-rate reference. These thresholds are product-development choices and do not establish real-aircraft fidelity.

For the initial unsaturated rate-response fixture, define one-axis steps from 0 to +200 deg/s and 0 to −200 deg/s after 0.2 s at rest, hold each step for 1.0 s, then return to zero for 1.0 s. Fix the controller/pack condition, axis and input family in the report. Measure 10–90% rise time in the commanded direction; overshoot relative to the commanded step magnitude; settling time as the first entry into a ±5% band that remains satisfied through the rest of the hold, including at least 0.1 s dwell. Interpolate measurement crossings under the declared sampling convention. Non-settling, sign reversal, insufficient hold window or an unresolved reference is a failed/inconclusive screen, not a zero metric. Treat a near-zero reference time with a declared absolute resolution floor rather than dividing by zero.

Add high-rate/full-stick and saturation tests separately; a command exceeding physical authority does not have the same tracking target as an unsaturated fixture. Define the expected failure/limit response before the run. Include simultaneous throttle/yaw/roll, voltage sag and release. No growing sustained oscillation is admitted in the release envelope. Frequency/phase inspection in the chosen maneuver band complements step metrics. If 240 Hz fails, block M2 and qualify the generic faster sampled-event design; never fix it through render callbacks.

## 6. Input, replay and route checks

| IDs | Required cases |
| --- | --- |
| INPUT-01…03 | Calibrated endpoints/center/inversion; correct pitch/roll/yaw signs; absolute/rate throttle interpretation; radio and gamepad pre-expo outputs; selected source/profile persistence. |
| INPUT-04…06 | High arm switch at entry; high throttle; OFF→ON; switch bounce; disarm while Airmode active; mode transitions; source-generation change. |
| INPUT-07/08 | Pause/focus loss/unplug/replug; no integration during hold; absolute low-throttle recovery; centered rate-throttle >0 while held; explicit zero-throttle recovery proposal, cancellation and first-resumed-tick failure. |
| INPUT-09 | Enumerated USB receiver with transmitter off; ambiguous device IDs; reconnect mappings. Distinguish host connection evidence from tested RF failsafe behavior; no invented failure detection. |
| INPUT-10 | Direct launch versus Home versus airplane→drone switch. Explicit global input-buffer policy and identical intended conditioning; real radio latency qualified separately. |
| REPLAY-01/02 | Complete baseline; restore at hover/flip/stop/low-charge/gate; continue accepted ticks. Full state, events, cursor, FC and race match under the same build/platform. |
| REPLAY-03/04 | Corrupt/truncated log; data/rates/world/track/rule/solver mismatch. Refused exact claim; recovered prefixes explicitly incomplete. |
| REPLAY-05 | Candidate controller run. Candidate reruns feedback from the same pilot tape; baseline actuator tape never substitutes for this. |
| REPLAY-06 | Recorder queue/I/O and observer faults. Complete/partial status truthful; bounded behavior and no retroactive physical rollback. |
| ROUTE-01…04 | Home/direct route, all start options, unsupported CLI combination, no airplane trim/schema/failure/Workshop fallthrough. Explicit capability checks and useful refusal; valid previously selected activity preserved on candidate failure. |
| ROUTE-05…07 | Rapid vehicle/landscape switching, preview loading/cancel/cache, return-to-Home, new clean export. Correct resources/controller ownership; no cross-activity leaks; assets and schemas present. |

Existing source tests to preserve are listed in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md). The source's airship `.orfl` adapter is useful precedent, but `exact=true` alone is insufficient: exact drone acceptance additionally requires completeness, matching identity and `solver_changed=false`.

## 7. Race acceptance

| ID | Case | Expected result under `openrc-local-race-v1` |
| --- | --- | --- |
| RACE-01 | Invalid track axes/dimensions, duplicated IDs, unsupported tilt, field/proxy mismatch | Refused before starting activity |
| RACE-02 | Upright gate visual, solid frame and scoring aperture | Independent alignment/clearance proof; thin-frame high-speed collision test |
| RACE-03 | Track/world/rule edit after checkpoint | Identity mismatch refuses restore |
| RACE-04 | Straight 40 m/s numerical fixture in 04 | Crossing at 1.25 ms, not tick start or end; strict edge excluded |
| RACE-05 | Wrong way, coplanar start, on-plane reset, exact endpoint | No false/double scoring; checkpoint retains needed side state |
| RACE-06 | Near-tangent/zero-normal-speed/high-curvature crossing, cross-return within one tick, and root-position uncertainty overlapping an aperture edge | Qualified located/dense path with time and in-plane position bounds; whole crossing interval strictly inside to score; refine or unresolved when ambiguous/bound/cap fails |
| RACE-07 | Two successive gates in one accepted interval | Canonical event ordering; next-gate sequence advances correctly |
| RACE-08 | Crash before, after and within the declared tie window of crossing | Physical time applied correctly; tie adjudication deterministic; attempt abort metadata retained |
| RACE-09 | Physical endpoint correction with `body_filtered=false` | No scoring from an unrepresented path; validate against final endpoint |
| RACE-10 | Missing/invalid receipt, abandoned RK trial, capacity overflow | No score from incomplete evidence; documented fault/unresolved path |
| RACE-11 | GO at t720, fresh throttle high/low, source loss, failed GO tick | Correct pre-inhibit input; no drive before GO; refusal stays inhibited and clears authorization; no committed GO on rollback |
| RACE-12 | Missed gate, then correct return | Current lap continues; out-of-order crossings never skip required gate |
| RACE-13 | Crash/reset after one or two completed laps | Whole attempt aborts; prior completed slots and reason preserved; new attempt starts all three laps and countdown |
| RACE-14 | Pause/resume; terminal result write failure; outbox-full reset; checkpoint/restore with queued result | Race clock freezes; practice metadata; old terminal record and new attempt commit together; failed writes retain unsaved record, full outbox refuses replacement, successful retries are idempotent |
| RACE-15 | Restore immediately before/on/after gate and finish; identical tape at 30/60/144 render caps | Identical accepted lap list, event/adjudication order and terminal validity; presentation remains observational |

The earlier ≤0.1 ms timing screen applies only to its synthetic straight crossing. A curved-path time bound also needs position/state/root/clock error and a positive normal-speed bound. The `A h²/8` example in 04 demonstrates why near-grazing cases need refinement or an unresolved result. Declare a speed/acceleration/geometry envelope before claiming no missed gate at high speed. A very small tie window is a rules resolution, not proof that event timing has that physical accuracy.

## 8. Presentation, endurance and native qualification

| IDs | Gate |
| --- | --- |
| VIS-01/02 | Rigid FPV origin/axes at zero and 40° tilt, upright/90° roll/inverted pose, nonzero camera offset; no hidden leveling or second interpolation. |
| VIS-03/04 | Actual 1920×1080 and actual 4:3 content projection; 120° horizontal equals 88.507155° or 104.821821° vertical respectively; resize and bars correct; near/far/prop/gate clipping reviewed. |
| VIS-05/06 | Four achieved-RPM/spin rotor visuals, stopped blade/hull; OSD values reflect selected law; no fabricated ideal-pack telemetry; licensed sound and correct listener policy. |
| VIS-07/08 | First frame, pause/resume, crash and teleport history reset; en/es and supported display readability; fresh-package assets and capabilities. 1080p first, then higher resolutions, then 720p fallback. |
| END-01 | Ten-minute declared free-flight and race tapes; charge/endurance outcome interpreted under law, not a guaranteed flight-duration target. |
| END-02 | Thirty arm/takeoff/land/disarm/reset cycles, plus selected hold/reconnect cases. No stale state, silent backlog, duplicate records, growing memory or unexplained energy creation; retain exact fixture scope. |

### PERF-01 — whole-step cost

On an idle, named target host and pinned native build, retain raw unsmoothed per-tick elapsed time around sampled input/FC + kernel + committed endpoint/race handling, plus a separate kernel-only measurement. Include normal flight, low voltage, contact, stop/depletion and gate-heavy cases. Report p50/p95/p99/max, deadline misses, work/substep/event counts, faults and simulated-time/wall-time ratio. Report instrumentation overhead. The existing smoothed `step_usec` overlay cannot supply these distributions.

Retain the proposed **≤500 µs p95 whole-step** target as a development budget, pending actual hardware qualification. It is approximately 12% of 1/240 s, not a worst-case guarantee. Report how it relates to main-line Gate P and any current native/reference backend coverage. Do not require a new native backend for initial admission; a native port needs its own repository-policy justification and reference parity.

### PERF-02 — frame pacing

Use a real native 1920×1080 drawable, FPV view, declared preset, track, radio/input tape, GPU/driver, refresh and vsync/VRR mode. Retain at least 60 s of warmed measured frames, separately reporting startup/loading. Record raw frame/presentation timestamps, sampling boundary, p50/p95/p99/max, long-frame counts and simulation/wall-time ratio. A headless or software-rendered VM does not qualify the GPU target.

The existing ≤16.67 ms p95 proposal alone is too weak to describe comfort: it omits tail size and latency. For a fixed-refresh screen use the measured refresh period and a predeclared pacing policy (the candidate 1.05× p95 / 1.10× p99 screen in 04 is a proposal, not a shipped target). Record actual missed intervals/hitches and judge changes against the paired baseline. Do not apply a fixed-vsync screen unchanged to uncapped or VRR modes.

### PERF-03 — input/display latency

Use the existing physical stick-to-marker workflow, and a separate prescribed stick-to-FPV-scene-response measurement. Record method resolution/exposure/scanout uncertainty, raw trials and exact radio/USB/OS/display configuration. At least the existing protocol's 30 transitions are needed for an initial distribution; stable p95 usually needs more. Choose an absolute product latency target only after the measurement boundary and hardware are defined. No unexplained extra display frame beyond uncertainty is a useful paired regression screen. Neither synthetic input injection nor a 4.167 ms tick interval establishes hardware latency.

## 9. Selected-build physical campaign — DR-39/40

This is a measurement plan, not work claimed complete. Use the actual assembly named in the product manifest, with suitable guarded test equipment and qualified operators; retain sensor calibration and uncertainty with the data.

| ID | Measurement | Parameter/claim it can support |
| --- | --- | --- |
| PHYS-01 | Complete component mass, battery placement, CG and independent inertia measurement | Mass inventory and locked/effective inertia; CAD appearance alone cannot establish them |
| PHYS-02 | Matched motor/prop/ESC static sweep with synchronized thrust, torque, RPM, bus voltage and pack current | Static maps and electrical losses over measured range; instrument saturation and displayed precision explicit |
| PHYS-03 | Spin-up/down and throttle steps at several voltages/loads; declared ESC settings | Actuator response and coast/brake behavior; distinguish command, relative RPM and timing |
| PHYS-04 | Pack OCV/charge/resistance under controlled conditions; dynamic/thermal tests only for a selected richer law | One-pack model parameters and uncertainty; series/capacity/cell condition explicit |
| PHYS-05 | Blackbox plus independent motion measurement for selected steps, rolls, punch/chop, descent and forward flight | Closed-loop/flight response within measured envelope; calibrate time/frame transforms and RPM telemetry |
| PHYS-06 | Experienced FPV pilot maneuver card and matched baseline/candidate review | Perceptual/control usability evidence with rates, radio, camera and display identified; supplements quantitative data |

Freeze fit versus validation maneuvers before tuning. Report regimes where measurements are absent, especially high speed, axial descent/propwash, rotor stop/restart and strong interactions. Validate advanced laws by held-out benefit relative to the transparent baseline, not by model complexity or borrowed published RMSE. Do not calibrate every effect against the same flight that is later called independent validation.

## 10. Required evidence record and merge discipline

Each package's record contains purpose/DR IDs; exact source and dirty-state identity; engine/backend/library hashes; configuration/input/track/rule hashes; source-data provenance; OS/host/renderer/resolution/refresh where relevant; exact command; requested and completed cases; tolerances; raw logs/tapes; verdict and limitations; and reproduction steps. Proposed thresholds and actual measurements are separate fields. A failure followed by success retains both reports and the intervening change.

Use current repository commands and `tools/godot/run_checked.py`; read its `ok`, `complete`, diagnostics and completion marker, not just process exit. Example for an **existing** test after the required project import:

```sh
python3 tools/godot/run_checked.py --timeout 90 \
  --label dr-existing-kernel --require-text '15 checks, 0 failed' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_dr_multirotor_kernel.gd
```

This command targets a full checkout; the actual run in this handoff used the documented minimal source closure. New `test_mr_*` names in the backlog must be implemented before they can be run. Select focused local checks while editing. Generic kernel/session changes require relevant session/fleet/golden checks on a stable candidate; required full suite/CI gates remain in force before feature merge. Never re-record a fleet golden solely for documentation, UI or routing changes. A hardware/pilot gate remains pending even when every automated check is green.

## 11. Settings investigation and integration gates

The [34 settings cards](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) add **81 proposed per-setting cases**, and [08](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md) adds **18 proposed import/configuration cases** (IMP-01…10 and CFG-01…08). Their normative descriptions remain in those documents. They are acceptance work, not tests run during this planning task. The [09 dossier](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md) records the source audit and 14 extracted-function evaluations separately.

M0 fixes the adapter/default/profile/schema decisions. M1 only requires the admitted pilot-control subset and truthful support reporting. M2 adds the usable settings journey and qualified effective product tune; physical-build measurement remains M4. Current-source reset PIDs/filters are not a product tune. Optional advanced settings do not become first-flight dependencies merely because their research card exists.

P19a is an explicit conditional early branch: a failed 240 Hz NUM-02 screen can trigger generic transactional faster sampling after P02/P03/P05 and before P06/P11 close. It needs a new opt-in protocol and all internal sample-event/candidate-state rollback evidence; do not put extra controller updates inside a derivative or hide a new scheduler in the plant. P19b can later qualify advanced filters and telemetry on the admitted rate path.

Settings fault injection must cover unknown-default reset invalidation, partial import with an unclassified command, armed midair entry into a non-integrating settings hold, explicit reset/apply, and both precommit preparation and postcommit observer/I/O failures. A successful replacement remains committed even if its UI/recorder observer fails.

## 12. Simulator approach research and practice qualification

[10](10_FPV_SIMULATOR_APPROACHES.md) investigates 28 approaches; [12](12_SIMULATOR_EVIDENCE_LEDGER.md) preserves product/source evidence and the 23-thread qualitative sample. [11](11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md) is the authoritative home for 12 proposed experiments, 13 proposed cases (UX-01…07, PRACTICE-01…03, AUTHOR-01…03), result-comparison policy and P22–P24 details. These are not executed tests or measured competitor results.

M2 qualification uses a flight field and complete software/observational evidence. The later course/race branches require P14/P15; the physical arm of EXP-04 requires P16/PHYS-05/06. Preserve hold/cancel state, reset only through accepted explicit preparation, and retain a committed finish if recording or persistence subsequently fails. Result compatibility must check course and collision-world identities as well as class/rules and permitted start conditions; camera/rates can vary only according to an explicit policy.

Counterbalanced handling feedback and a small formative cohort do not establish learning transfer. Learning comparisons need controlled exposure or matched novel tasks; a rest cannot erase learned course knowledge. Explain gate failures only when supported by bounded committed diagnostics; otherwise report no registered crossing or unresolved status. These refinements keep usability work consistent with the existing simulation and race contracts.
