# FPV settings implementation, import and qualification contract

**Revision:** 11 November 2026. **Status:** proposed design; no settings importer or new flight controller was implemented in this research. **Evidence:** [34 investigations](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) and [source/probe dossier](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md). **Parent contracts:** [02](02_ENGINEERING_CONTRACTS.md), [03](03_FLIGHT_DYNAMICS_AND_RESEARCH.md), and [05](05_VALIDATION_AND_IMPLEMENTATION_BACKLOG.md). Existing DR IDs and the DR-16a dependency remain authoritative.

## 1. Product decision

Provide a familiar racing-drone settings workflow with truthful simulator behavior. The first product uses the qualified OpenRC controller/plant and supports an explicitly enumerated subset of pilot-control mathematics. A control that is present in Betaflight or INAV becomes active in OpenRC only when its algorithm, sampling, state, dependencies and acceptance evidence exist.

Separate three concepts in the UI and data: **the imported firmware document**, **the normalized OpenRC candidate**, and **the active accepted configuration**. Displaying a recognized source value does not activate it. A source reset value is not a recommended tune for the selected quad, and a software-compatible curve does not establish firmware or physical-aircraft equivalence.

Keep BF 4.5.2 Actual-rate math as the initial compatibility target. The newly inspected BF 2026.6.2 and INAV 9.1.0 pins are comparison baselines, not implicit support upgrades. Qualify other families and versions independently, even when one equation is unchanged. Current source findings and exact keys/defaults are in SET-01…34; do not duplicate their numeric registry in a second authoritative table.

## 2. Support states and admission

Every recognized source item receives one of the following dispositions. These are proposed importer states, not labels for features currently implemented.

| State | Runtime meaning | User-visible result |
| --- | --- | --- |
| supported_math | A specific pure transform, units, domains and ordering have independent reference evidence. Firmware quantization may be excluded only when the support label says so. | Name the family, source pin and mathematical scope. |
| supported_simulator | An implemented OpenRC law provides the named behavior with its own parameters, state and validation. It is not an exact firmware controller. | Show the simulator law and its effective values. |
| retained_metadata | Source value is preserved with provenance but has no active simulated effect. | Show why it is inactive and any future dependency. |
| unsupported_active_request | Requested behavior is outside the admitted controller/plant/sensor/route. | Block applying that requested scope; offer an explicit narrower import. |
| invalid_or_unresolved | Unknown source, units, value, defaults, scope, mapping or contradictory syntax prevents interpretation. | Report source line, reason and required evidence; no guessed replacement. |

“Recognized,” “parsed,” “source-valid,” “runtime-admissible” and “qualified” are separate internal properties. A parser can recognize a 250 Hz filter while refusing to activate it on a 240 Hz sample stream. A source-valid zero can be a disable sentinel, an unlimited timer or a meaningful physical value depending on the field.

A partial pilot-controls import is allowed when every value needed for that declared scope is explicit or has a verified default, and all retained fields are reported. It must be named **Pilot controls only**, not “Betaflight setup imported” or “INAV tune applied.” An unknown PID field does not block a deliberately scoped rates import, but it prevents a complete-controller compatibility claim.

## 3. Configuration domains and ownership

| Domain | Contains | Identity and runtime authority |
| --- | --- | --- |
| Input device | USB axis mapping, measured calibration, inversion, deadzone, absolute/rate throttle interpretation, source generation | Existing input owner; pins the logical-tape interpretation. A firmware PWM range is not automatically a USB calibration. |
| Pilot response | Rates family, per-axis parameters/caps, throttle curve, selected rate/control profile and admitted input filtering | Sampled pilot adapter; pure transforms plus explicitly stored histories. |
| Flight controller | OpenRC SI gains, derivative/filter law, integrator and allocator policy, admitted gain modifiers and modes | Sampled controller; configuration identifies every active law and its sample clock. |
| Sensors and schedule | Ideal or modeled sensor, orientation, bandwidth, noise, sample clocks, filters, telemetry availability and delay | Sensor/controller owner under the generic transaction; deterministic histories/RNG/counters are checkpointed. |
| Physical build | Mass/inertia, geometry, spin signs, ESC/shaft/prop and shared pack laws, contact envelope | Strict vehicle data and plant owner. A settings import cannot casually replace sourced physical parameters. |
| Lifecycle and rules | Arm/prearm, admitted recovery/failsafe exercise, race start/terminal policy | Model/session transaction, with explicit precedence and recorded events. |
| Presentation | HUD units/layout, crosshair/horizon, camera preferences, optional VTX metadata | Read-only presentation. Changes leave physical evolution unchanged for the same accepted tape. |
| Recording/provenance | Source document/hash, adapter version, support report, effective identities, diagnostic field selection and decimation | Bounded recorder/import metadata. Complete replay tape remains independent of diagnostic downsampling. |

Distinguish source battery alarms/capacity descriptions from the selected physical pack. A newly imported capacity is an unresolved build change until the product data pipeline accepts it. An alarm that later commands disarm or navigation ceases to be presentation-only and needs a lifecycle/controller capability.

## 4. Typed schema and profile model

Create a sibling schema such as **openrc-fpv-settings-v1**. Keep it distinct from the aircraft physical schema and the kernel checkpoint. Its exact filename is a DR-10/15 implementation decision.

The envelope contains:

- Source firmware family/version/commit, target/board revision, available build-feature evidence, configurator/export provenance, export kind, raw source hash and a verified default-manifest identity when available.
- Import grammar/adapter version; source command order; declared import scope; the per-item support report; unresolved and retained metadata.
- Separate source PID/rate/battery or control/mixer/battery profile collections, with original indices and the separately resolved active selection for each collection. Preserve profile links rather than flattening all collections into one tune.
- Fully resolved effective OpenRC input, pilot, controller, sensor, plant-reference, lifecycle/rule and presentation configurations with explicit law/version identities.
- A canonical serialization version and complete runtime-configuration hash. Serialization rejects nonfinite values and ambiguous integer encodings; use the repository's binary-preserving checkpoint contract for runtime state.

Each parameter record needs: canonical key, typed value and unit, source key/raw value/unit, source scope and line, provenance state (explicit/default/derived/unknown), support status, effective law, dependency checks, and an optional reason. Exact upstream ranges live in the versioned adapter registry; OpenRC runtime domains can be stricter but must report that distinction.

This **illustrative parameter row** is a synthetic 4.5.2 Actual-rate example, not a default tune or a complete file:

~~~json
{
  "canonical_key": "pilot.rates.roll.center_rad_s",
  "value": 3.490658503988659,
  "unit": "rad/s",
  "source": {
    "firmware": "betaflight",
    "version": "4.5.2",
    "scope": {"kind": "rateprofile", "index": 0},
    "key": "roll_rc_rate",
    "raw_value": 20,
    "raw_unit": "10 deg/s under ACTUAL",
    "line": 12,
    "origin": "explicit"
  },
  "law": "openrc-actual-bf452-math-v1",
  "support": "supported_math",
  "status": "candidate"
}
~~~

The adapter resolves the enclosing ACTUAL family and complete axis requirements before this row can be active. The UI may show 200 deg/s while the controller receives rad/s. A different rate family must not reuse this unit conversion just because the raw key name matches.

### Noninterchangeable values found in this research

| Source distinction | Required representation |
| --- | --- |
| BF alignment in degrees versus INAV alignment in deci-degrees | Explicit source unit and one conversion into the declared sensor transform; never change camera tilt or plant orientation implicitly. |
| BF landing timeout in seconds versus INAV off delay in deciseconds, with zero sentinel | Typed duration plus separate disabled/unlimited semantics; avoid a generic numeric timeout field that loses the distinction. |
| BF profile indices starting at 0 versus INAV profile indices starting at 1 | Preserve source index and collection; canonical internal IDs are independent of display numbering. |
| BF battery profiles and INAV control/mixer/battery scopes | Per-family collections, field scope and final active selections. |
| INAV capacity expressed as mAh or mWh | Charge or energy quantity; no nominal-voltage guess to convert one into the other. |
| RPM, electrical RPM, electrical RPM packet scaling and pole count | Distinct units and transport identity; poles must be a physically admitted even count before deriving pole pairs. |
| VTX power index | Device/table-qualified metadata, not a fixed mW conversion. |
| Curve family versus full firmware signal path | Independent compatibility identities for rate math, throttle lookup, RC conditioning, quantization and scheduler. |

The evidence for these rows is in SET-17, 23…26, 28…29, 31 and 33. A registry must preserve the physical unit, conditional enable rule and scope, not just a string name, minimum and maximum.

## 5. Import is a bounded data transaction

### Parse and resolve

1. Read bytes into an isolated candidate. Proposed starting resource limits are 1 MiB per document, 20,000 lines and 4,096 bytes per line, with bounded profile/setting/command counts from the supported adapter. These are reviewable product limits; reject overflow before changing any active state.
2. Identify a supported grammar and source version. A pasted version line is source metadata, not proof of a particular hardware build. Conflicting headers fail resolution; missing information permits only a scope that does not depend on it.
3. Parse allowed statements into an ordered intermediate representation. Support comments, profile selectors and known value/feature/mode records explicitly. Never execute, eval, source, shell, transmit or flash the text.
4. Interpret recognized defaults/batch/save markers as inert document semantics. A reset marker resets the staged source model to its exact verified baseline when known. If the baseline is unknown, invalidate every affected earlier parameter, profile selector and link to UNKNOWN, or block that scope; never let pre-reset assignments survive as defaults. Later explicit assignments/selectors can resolve a complete chosen subset. The marker never resets the user's active flight. A save marker is not permission to write firmware or start a drone.
5. Resolve global and profile-local assignments in their declared scope. Ordered reassignment inside a supported grammar may be valid: retain assignment history, use the specified last assignment, and show material overrides. Conflicting source identities are blocking. An unknown or unclassified command blocks even a partial import unless the versioned grammar proves it affects only an excluded scope; lack of knowledge is not evidence of independence.
6. Resolve separately emitted active-profile selections. Distinguish the export's section traversal from its final restoration selectors. If active selection is absent or ambiguous, leave it unresolved; a UI may let the user select a profile explicitly for a partial import.
7. Reconstruct omitted values only with an exact applicable default manifest, including relevant target/build features and preset effects. A version name or a compatible diff alone is insufficient. Preserve unknowns.
8. Convert dimensions and validate source domains, cross-field dependencies, selected vehicle capabilities, sample-rate limits, channel/motor mappings and mode precedence.
9. Produce a complete preview: active effects, normalized values, original units, selected profiles, changes, inert metadata, blockers, unsupported modes and any mathematical/firmware compatibility limit.

Hardware resource/serial/VTX/passthrough commands may be retained as bounded provenance when explicitly outside the selected scope. They never acquire execution authority. An unknown/unclassified statement cannot be silently discarded from any selected import scope. Only statements positively classified by the versioned grammar as outside that scope can remain inert metadata. Round-tripping source metadata is not the same as generating an executable firmware configuration.

### Apply and reset

For the first product, applying any input, rate, controller, sensor, physical or lifecycle configuration uses **an explicit held reset/replacement transaction from 02 whose candidate starts disarmed**. Profile selection follows this policy. No in-flight live tune or hot profile switch is admitted initially.

Opening settings during flight freezes the accepted motor state; moving the ARM switch OFF during that hold is readiness evidence, not an accepted disarm. For an already disarmed session, Apply uses the prepared reset path. If the accepted session is still armed, require the distinctly labeled **Reset to pad and apply** action, with its reset/attempt-abort consequence visible before activation. That action stages the complete new disarmed configuration and commits it atomically; it does not advance the old flight or execute a hidden disarm tick. The existing separate pad reset is also valid before Apply. Cancel preserves the old held session and pending candidate without consuming arm evidence. Never silently reset because the ordinary Apply button was attempted.

Stage the new effective configuration, compiled immutable evaluators, state layout, initialized filter/controller state, input ownership and result-outbox capacity before committing. If the current race attempt is replaced, retain its terminal abort record under the existing atomic outbox rule. Require fresh current-source arm evidence after the accepted reset. Do not consume input edges, alter the accepted cursor, or clear a crash latch while merely previewing settings.

A failed validation/preparation leaves the complete old session, recorder, race, profile selections and UI active indicator intact. On success, publish the new configuration identity and reset state together; start a new recording identity/segment according to DR-17. A recorder/UI observer failure after that commit cannot restore the old configuration: retain the new accepted state/identity, pause its session under the observer-fault contract, mark an affected recording incomplete and expose the committed identity. Test failures on both sides of publication. A later hot-switch capability must define its sample boundary, gain/filter/integrator handoff and tape event explicitly before activation.

Purely visual settings may apply without a physical reset. Their UI, identity and event storage remain separate; they cannot change simulation dt, gyro/PID sample clocks, arming, battery laws or gate results.

## 6. Signal order and state obligations

The initial simulator path is: calibrated device interpretation → one deadband/conditioning owner → logical pilot frame → admitted throttle/rate transform and caps → explicit smoothing/sample hold → controller → bounded allocation and admitted output limits → event-local drive authorization → joint physical stages. The exact position of any future gain modifier, source-equivalent filter or throttle limiter is versioned, not inferred from this conceptual list.

Source-specific compatibility must reproduce the actual source ordering. For example, the input to TPA, the position of a throttle limit, and gyro filtering before versus after differencing may change the result. Do not make an arbitrary common pipeline and label both firmware families equivalent.

The controller's allocated command and its effective post-cut drive remain separate. A crash tick retains sampled request/allocation diagnostics through publication, while the event latch cuts later subintervals. A settings/profile import cannot override that latch or cause a recorder to lose the pre-impact command.

The 31-value baseline controller block in 02 is only the proposed basic controller layout. It does not already hold every optional filter or modifier investigated here. Any added state changes the admitted layout/version: per-axis filter registers, preceding samples, integrator/relaxation state, feedforward/slew history, anti-gravity history, TPA/Airmode/launch latches, RPM validity/filter histories, FFT/window/peak state, scheduler counters, delayed data and sensor RNG state. Fixed-size bounds and rollback/restore obligations apply to all of it.

No stateful control algorithm runs from the render callback, a UI property setter, an RK derivative evaluation, or an uncheckpointed mutable closure. Coefficient changes and estimator updates occur at their declared accepted sample boundaries.

## 7. Sampling and filter qualification

Separate sensor acquisition, gyro filtering, PID feedback, actuator output and plant integration clocks. Initially there is a 240 Hz sampled controller hypothesis with explicit sensor assumptions. The 240 Hz feedback/filter stream has a 120 Hz Nyquist limit; a separately admitted faster sensor/filter/output stream has its own limit and requires an explicit anti-alias path before decimation. These are mathematical limits, not recommended cutoffs. A below-Nyquist filter can still have unacceptable phase, attenuation or numerical behavior.

SET-13…17 establish why accepting common firmware frequency values requires more than a slider. In the pinned BF source, dynamic notch disables below a 2 kHz update rate. INAV's dynamic notch, RPM telemetry path and filter ordering differ. Repeated evaluation of a held sensor sample or additional RK stages does not provide new information.

Before an advanced filter is active, require:

- A sensor sample law, analog/synthetic bandwidth, anti-alias path, sample phase and missing/stale telemetry behavior.
- Independent constant, impulse, step, broadband and moving narrow-band signals with known spectra and phase. Use realistic retained traces when available and keep calibration versus held-out data separate.
- Measured magnitude/phase/delay, startup/bypass transition behavior, harmonic/peak-tracking behavior, computational bounds and deterministic restoration.
- Coupled controller comparisons with identical identified plant and pilot tape, separating plant refinement from fresh-feedback frequency changes.

Run waveform generation and numerical references at sufficient rate to avoid hiding aliases in the oracle itself. A zero-noise gyro does not qualify noise rejection or peak tracking. Keep advanced filters inactive with a named reason until their dependency gate is met; do not silently change the imported cutoff or algorithm to make it run.

## 8. Settings workspace and initial choices

Use a familiar section layout, with the effective simulator model and current profile always visible:

| Section | Initial useful controls | Controls shown only with an admitted capability |
| --- | --- | --- |
| Receiver | Source, calibrated mapping, polarity, deadband, throttle interpretation, live normalized axes | Firmware transport timing/substitution exercise and exact source-specific receiver conditioning |
| Rates and throttle | Qualified rate family, per-axis response/caps, curve plot, explicitly named throttle law, profile selection | Additional firmware curves and exact quantization paths |
| Controller | OpenRC SI controller identity, qualified gains, requested/allocated/produced response diagnostics | Feedforward, TPA, anti-gravity, relaxation and firmware-equivalent modes after qualification |
| Filters and timing | Actual sample clocks, ideal/declared sensor, admitted simple gyro/D filter | Dynamic/RPM notches, advanced sensor paths and higher-rate sampled-event scheduler |
| Motors and power | Physical motor map/spin signs, validated idle/output bounds, selected shared pack and truthful telemetry | Dynamic idle, source-specific voltage compensation and reverse drive |
| Modes and lifecycle | Acro/Angle, admitted bindings, arm block reasons, host hold/recovery | Horizon, launch aid, RF-loss exercise, navigation and turtle |
| OSD and view | Units, crosshair/horizon, telemetry visibility, separate FPV camera controls | Exact packed firmware layouts or modeled RF/video impairment |
| Profiles and logs | Preview/apply, configuration identities, full replay capture, bounded diagnostic fields | Full Blackbox export after format/content qualification |

Begin with **an identified experimental build's simulator-qualified controller tune**, not source reset PIDs. Headless numerical/control and native pilot-facing qualification can support an explicitly experimental release; selected physical-quad measurement and fidelity claims remain the separate M4/DR-40 gate. The existing illustrative Actual curve remains a research vector, not a universal recommended racer preset. Default optional gain modifiers/navigation/launch/turtle/RF impairment to inactive until their capability is implemented. Use an ideal sensor with bypass or the declared qualified simple filter for the initial research baseline; the selected choice is visible and identified.

Do not make protocol metadata such as DShot600 imply a 600 Hz physics rate or a known ESC time constant. Motor idle requires the selected motor/prop/pack and arming/contact evidence. Battery alarms cannot fabricate telemetry for the ideal-energy fixture. Disabled controls should explain their missing model/sampling dependency in ordinary language.

The settings workspace follows the existing 1080p-first and English/Spanish readability gates. Save custom user profiles without overwriting source presets; show pending versus applied changes, allow cancellation, and preserve the prior valid selection on failed import. Camera FOV/tilt is separate from sensor-board alignment and an artificial-horizon compensation value.

## 9. Additional implementation packages

These packages extend the existing 16; they do not renumber DR tracks or create a second implementation-status owner.

| Package | DR ownership and deliverable | Dependencies and exit |
| --- | --- | --- |
| P17 | DR-10/15: versioned settings schema, adapter registry, typed defaults/provenance, bounded import IR and report | P01/P04; SET-01/23/24/28/29/33 plus IMP-01…10; no unsupported field silently active. |
| P18 | DR-14/15/29: qualified pilot-control subset and profile preview/apply UX | P02/P03/P06/P10/P17; source curve cases, input ownership, atomic reset and 1080p workflow. |
| P19a / P19b | DR-09a + SF, then DR-21/22: conditional generic faster sampled-event protocol; later sensor/filter harness | P19a depends on P02/P03 and the P05 control fixture and is an unblocked conditional prerequisite to closing P06/NUM-02 if 240 Hz fails. It defines a new opt-in sampling protocol rather than mutating 02's once-per-tick baseline. P19b follows qualified P11 for advanced filters/noise/telemetry. SET-04/13…17 and numerical/phase/cost evidence apply. |
| P20 | DR-07/12/21: optional controller/idle/voltage modifier modules, each independently versioned | Qualified base plant/controller/sensor path; SET-06…09/11/12/19/20/22; no universal firmware-gain conversion. |
| P21 | DR-17/30/36: accepted settings identity, recording fields, support report and export/route integration | P07/P13/P17/P18; replay/restore/diagnostic-decimation and settings UI gates; additional hardware/navigation capabilities remain separate scope. |

The faster-sampling escape path is explicit: if P06's NUM-02 screen fails at 240 Hz, implement/review P19a without waiting for P11, then rerun NUM-02 before proceeding. The alternate protocol must transact all internal sample events, clocks and candidate histories together with full outer-tick rollback; neither extra RK stages nor repeated held samples satisfy it. P19b's later advanced-filter work is not a dependency of that repair.

M0 adds adapter/schema/defaults decisions alongside the transaction proof. M1 requires only the chosen pilot subset and truthful unsupported-field reporting. M2 requires a working settings journey and qualified effective values. M3 keeps its existing race identity, attempt-abort and result rules. Advanced modifiers, noise models and source-equivalent filtering enter only through their own evidence gates; research breadth does not make every investigated feature a first-release dependency.

## 10. Import and integration acceptance ledger

All tests below are **proposed**. The 34 cards contain further per-setting A/B/C/D cases. The only newly executed numerical source work is the scoped probe in 09; earlier executed kernel/math evidence remains in 06.

| ID | Discriminating case | Acceptance |
| --- | --- | --- |
| IMP-01 | Exact source version and target-default manifest; then unknown version/build | Supported scope resolves; unknown-dependent values remain unresolved and cannot be advertised as a complete tune. |
| IMP-02 | BF profile 0 versus INAV control_profile 1; mixed scopes and final restoration selectors | Correct independent collections, numbering and active selections; no profile field leakage. |
| IMP-03 | Known all-diff versus partial snippet without active selection | Complete reconstruction only with sufficient evidence; explicit profile choice/narrow scope otherwise. |
| IMP-04 | Omitted defaults across an INAV 9.0→9.1 migration | Resolve with the correct source baseline and show drift, or report unknown; compatible syntax never implies identical effective values. |
| IMP-05 | Same alignment name with raw 90; same timeout with zero sentinel | Correct dimensions and source-specific sentinels; no 10× transform or immediate-disarm substitution. |
| IMP-06 | Assignment and profile selection before defaults with unknown baseline, then an incomplete set of later assignments | All affected pre-reset values/selections/links become unknown or block the scope; later explicit fields resolve only themselves. A pre-reset roll value cannot survive because only pitch is set afterward. Current flight is unchanged. |
| IMP-07 | Unknown/oversized/truncated/malformed statements, command-like payloads | Bounded refusal with diagnostics; no execution/device access and no partial configuration mutation. |
| IMP-08 | Rates-only scope with known excluded PID/navigation/VTX fields, then an unknown profile/control statement | Known disjoint fields remain reported metadata; unclassified statement blocks the partial import. No full-firmware claim or silent unknown effects. |
| IMP-09 | Source-valid but above-band filter or absent RPM telemetry | Active request blocked or deliberately narrowed; source metadata retained without pretending effective support. |
| IMP-10 | Missing, duplicate or inconsistent channels/motors/profile link | Clear refusal; vehicle cannot launch with guessed mapping or incompatible spin/geometry. |
| CFG-01 | Preview/cancel; prepare failure; successful replacement; recorder/UI observer failure after commit | Old session survives precommit failure. Postcommit failure retains the new identity/state, pauses that session and marks affected recording incomplete; never rolls back an accepted replacement. |
| CFG-02 | Open settings midair while armed, move ARM OFF during hold, ordinary Apply, cancel, then explicit Reset to pad and apply | Hold does not fabricate disarm or advance a tick. Ordinary Apply cannot silently reset. Explicit combined reset publishes a disarmed candidate, retains the old attempt result and requires fresh post-reset arm evidence. |
| CFG-03 | Checkpoint during smoothing/relaxation/idle/launch/FFT state | Full declared state restores; next samples, events and commands match under the same runtime identities. |
| CFG-04 | Failed sampled tick after a profile-dependent controller update | No consumed input edge/cursor, partial state, extra recorded row or changed accepted profile. |
| CFG-05 | Changing only HUD units or inert VTX metadata | Same accepted pilot tape gives identical physics and race results; presentation/provenance changes are truthful. |
| CFG-06 | 1/2 diagnostic decimation with complete replay recording | Analysis phase survives restore while full replay requirements remain satisfied. |
| CFG-07 | Imported crash-recovery/turtle mode on first one-quadrant law | No negative-drive admission, terminal latch clearing or implicit race-validity restoration. |
| CFG-08 | Direct launch, Home selection, invalid preset and fresh export | Correct capability/data resources; no airplane-only settings, stale active config or missing adapter registry. |

Differential tests must state the comparison level: mathematical equation, extracted source path, complete firmware target, OpenRC implementation, same-build replay, native device timing, or physical flight. They are not interchangeable. For a pure float64 curve, predeclare the numerical tolerance and domain, include endpoints/caps/negative input, and report residuals. For a quantized source path, include exact integer lookup and rounding expectations under the specified build/toolchain. A new release or target is a new admission decision, even if the UI names look familiar.
