# OpenRC Simulator — Controls, Input, Calibration and Profile Audit

**External engineering review for the OpenRC Simulator maintainers**  
**Audit date:** 14 November 2026  
**Repository:** [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator)  
**Audited main commit:** [f41d0fd2eb5483c609bcd858bcf22776eb311e14](https://github.com/bultodepapas/OpenRCsimulator/commit/f41d0fd2eb5483c609bcd858bcf22776eb311e14)  
**Application version in this snapshot:** 0.2.8  
**Execution engine:** Godot 4.8.beta2.official.cafc17a19, Linux x86-64  
**Deliverables:** this report and its accompanying reproduction/evidence archive  
**Change status:** production source was inspected read-only; no fixes, commits, pull requests or upstream issue submissions were made.

## Contents

1. [Executive assessment](#1-executive-assessment)
2. [Scope, method and limits](#2-scope-method-and-limits)
3. [How controls and calibration work](#3-how-controls-and-calibration-work)
4. [Detailed findings](#4-detailed-findings)
5. [Policy decisions and support gaps](#5-policy-decisions-and-support-gaps-kept-separate-from-defects)
6. [Compatibility assessment](#6-compatibility-assessment)
7. [Maintainability and optimization](#7-maintainability-and-optimization-opportunities)
8. [Validation results](#8-validation-results)
9. [Remediation sequence](#9-remediation-sequence-for-maintainers)
10. [What was not established as a defect](#10-what-was-examined-and-not-established-as-a-defect)

## 1. Executive assessment

The controls system has substantial defensive work already in place: versioned profiles, device identity and connection generations, explicit radio calibration, validated mappings, separate flight/menu ownership, neutral and fresh-input gates, and transactional single-writer persistence. The most consequential defects occur where an adapter or UI workflow uses only part of those contracts.

This audit identifies **15 actionable findings: two P1 and thirteen P2**, plus four separately identified policy/support decisions. The findings include deterministic synthetic reproductions, a controlled two-process persistence interleaving, direct source call-chain analysis, and a bounded event-routing microbenchmark. “Reproduced” in this report means the described software behavior occurred in the stated fixture; it does not mean a physical transmitter or native release package has been qualified.

The two highest-priority corrections are:

1. **Restore the raw-radio readiness contract in the FPV/quad route.** The multirotor adapter can advertise readiness and pass throttle while the shared RC reader remains unarmed for lack of fresh low-throttle evidence. An adapter-plus-flight-controller probe reached the motor-armed state and full collective under that condition.
2. **Bind controller setup drafts and saves to a connection generation.** If another device occupies the same numeric handle while Controls is open, Save can overwrite an existing profile's association with the replacement device and select that device, retaining the old mapping.

Other material problems include disappearing unsaved drafts, an airship pause/resume dead end, airship routes that ignore selected controllers and modern profiles, calibration changes that silently remove controls or discard completed measurements, misleading Mode 1 guidance, capture interrupted by resting throttle events, and lost saves across simultaneous application instances.

The event router also does avoidable work for each axis event. An isolated projection of the actual AppRoot methods performed seven binding resolutions and eight profile-copy requests per event, including events from an unselected controller. A cache-only experimental variant reduced median time from 1,217.25 to 292.05 microseconds/event in that fixture. This establishes an optimization opportunity; it is not an application-wide FPS or latency result.

The evidence supports focused corrections and shared contract tests. It does not support a blanket claim that JETI, EdgeTX, Xbox or PlayStation devices are broken, that every reported issue occurs on every device, or that the complete project test suite fails.

### Priority and evidence index

| ID | Priority | Finding | Strongest evidence |
|---|---|---|---|
| [CTRL-01](#ctrl-01) | P1 | Quad bypasses raw-radio readiness and forwards throttle | Actual adapter + flight controller + controlled plant; synthetic input |
| [CTRL-02](#ctrl-02) | P1 | Reused device handle can overwrite a saved profile's association | Actual setup/service/store with synthetic registry replacement |
| [CTRL-03](#ctrl-03) | P2 | A dirty profile draft disappears when closing on another clean profile | Actual setup close path |
| [CTRL-04](#ctrl-04) | P2 | Airship cannot ordinarily resume with retained virtual throttle/yaw | Actual input adapter and session resume gate; isolated session |
| [CTRL-05](#ctrl-05) | P2 | Airship controller ownership, profile resolution and startup diverge | Complete source paths; gamepad-readiness probe |
| [CTRL-06](#ctrl-06) | P2 | AUX switch capture has no connection-generation lease | Actual capture UI with atomic identity replacement |
| [CTRL-07](#ctrl-07) | P2 | Resting throttle motion terminates action remapping | Actual capture UI with synthetic endpoint jitter |
| [CTRL-08](#ctrl-08) | P2 | Radio Mode 1 selection opens Mode 2 calibration guidance | Actual assistant, bridge, wizard and view |
| [CTRL-09](#ctrl-09) | P2 | Recalibration removes AUX controls without a complete user warning | Calibration/merge probe plus Home and in-flight call chains |
| [CTRL-10](#ctrl-10) | P2 | Existing action-axis conflict discards completed calibration | Actual validation/merge probe and UI call chain |
| [CTRL-11](#ctrl-11) | P2 | Calibration accepts transient center/endpoint bias as valid idle | Actual calibration and RC reader; controlled samples |
| [CTRL-12](#ctrl-12) | P2 | Accepted absolute roll/pitch/yaw semantics survive recalibration | Actual profile validation/merge/normalization |
| [CTRL-13](#ctrl-13) | P2 | New generic joystick cannot complete the offered assistant flow | Executed refusal plus complete setup/save call chain |
| [CTRL-14](#ctrl-14) | P2 | Concurrent processes acknowledge saves that overwrite one another | Scheduled two-process real store transaction |
| [CTRL-15](#ctrl-15) | P2 | Event routing repeatedly reconstructs maps and copies profiles | Actual-method projection, counts and seven timing rounds |

**Priority definitions.** P1 means an important input guard is bypassed or an existing device/profile association can be silently replaced; these should block declaring the affected path ready for release. P2 means a substantial but bounded workflow, correctness, robustness or efficiency problem. Priority is an engineering recommendation, not a CVSS score or a claim about physical aircraft safety. Rare preconditions and experimental vehicle scope remain visible in each finding.

## 2. Scope, method and limits

### Source and runtime identity

The review is pinned to the commit above. The local production checkout was clean, and the remote main reference still matched the audited hash at the final source check. The engine was selected from the repository's own pin, rather than the system-installed Godot. Its version and executable SHA-512 were verified against the repository's expected Linux binary hash:

~~~
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
~~~

Source: [app/get-godot.sh:1–20](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/get-godot.sh#L1-L20). Application metadata: [app/project.godot:7–24](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/project.godot#L7-L24).

Review concentrated on the 20 GDScript modules under app/input, the Controls screen, the setup assistant and calibration presentation, AppRoot routing, profile persistence and migration, and the fixed-wing, helicopter, multirotor, airship and ground consumers. Existing tests and the repository's controller/JETI qualification plans were inspected to distinguish implemented behavior from documented limitations.

The task's “Jetty” was treated as **JETI**. The request's “HTX” does not identify a unique controller model or implementation. No separately named HTX implementation was found in the inspected control modules. This review covers the explicit JETI path, the EdgeTX/OpenTX-oriented radio path and generic joystick/HID behavior; it does not invent a model-specific HTX compatibility conclusion.

### Evidence discipline

- **Existing tests:** 14 focused repository scripts, with 845 checks in their final successful runs, executed in a minimal project with unchanged production scripts and the fixture configuration/generated-metadata exceptions disclosed in Section 8.3.
- **Targeted reproductions:** actual production classes copied into isolated projects, driven by deterministic samples, synthetic InputEvents and controlled registry observations.
- **Persistence race:** real load/merge/write code with a narrow scheduling seam that pauses each writer after its read/merge. Both writers then use the original transaction implementation.
- **Performance:** verbatim AppRoot method bodies in an inert application fixture, with the real profile/action/service code. Rendering, physics, SDL delivery and USB delivery are excluded.
- **Source review:** complete causal paths are cited when a rendered or device-dependent workflow was not executed.
- **Independent challenge:** another reviewer challenged severity, alternative interpretations and the boundaries of the highest-priority conclusions.

All final runtime results were checked with the repository's tools/godot/run_checked.py. Engine/script diagnostics, completion markers where used, and process completion were inspected; exit code alone was not treated as proof. Early fixture mistakes—missing assets, an omitted translation registration and a wrong requested completion marker—were corrected and are excluded from product-failure claims.

**Not performed:** the full project suite, a full rendered application session, Windows/macOS native packages, physical USB/Bluetooth qualification, RF-loss testing, suspension/reconnect testing on actual devices, power-loss durability testing, or an end-to-end input-latency measurement. The audit establishes software defects and test gaps at this snapshot; it is not an exhaustive proof that no other control defects exist.

## 3. How controls and calibration work

### 3.1 The intended shared path

| Layer | Responsibility | Key source |
|---|---|---|
| Godot input observation | Collect connected devices, reported metadata and known-gamepad status | [app/input/controller_service.gd:140–153](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L140-L153) |
| ControllerRegistry | Normalize identity, detect ambiguity, assign connection generations, track flight/UI selections | [app/input/controller_registry.gd:18–94](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_registry.gd#L18-L94) |
| ControllerProfileStore | Load and match V2 profiles; preserve a menu preference; transact writes and recover a rollback | [app/input/controller_profile_store.gd:8–75](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L8-L75); [app/input/controller_profile_store.gd:314–380](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L314-L380) |
| ControllerService | Resolve profiles, apply selected owners, bind trusted gamepad verification, persist setup/calibration | [app/input/controller_service.gd:175–210](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L175-L210); [app/input/controller_service.gd:239–279](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L239-L279) |
| RcInput | Read axes/buttons, normalize channels, enforce readiness, integrate virtual gamepad throttle | [app/input/rc_input.gd:222–370](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L222-L370) |
| ControllerActions / AppRoot | Resolve semantic bindings, distinguish menu/flight contexts and enforce action edges | [app/input/controller_actions.gd:161–226](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_actions.gd#L161-L226); [app/app_root.gd:2563–2666](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2563-L2666) |
| Vehicle adapter/session | Convert normalized commands into each activity's controls and pause/arming policy | [app/input/multirotor_input.gd:272–295](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/multirotor_input.gd#L272-L295); [app/input/airship_input.gd:25–85](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/airship_input.gd#L25-L85) |

The important distinction is between **configuration**, **connection identity**, **fresh input evidence**, and **motor/session authority**. A valid saved profile does not prove the current physical handle is the same device. A current axis poll does not necessarily prove a raw transmitter has delivered fresh low-throttle evidence. A menu choice does not automatically reach every vehicle adapter. CTRL-01, CTRL-02 and CTRL-05 are concrete breaks between these layers.

### 3.2 Gamepads versus RC radios and generic joysticks

Standard known gamepads receive presets based on normalized gamepad axes. Mode 2 uses right X/Y for roll/pitch and left X/Y for yaw/rate throttle; Mode 1 swaps the pitch/throttle vertical axes. A trigger-throttle preset uses an absolute trigger instead. The shared scalar gamepad conditioner defaults to deadzone 0.08 and expo 0.3; virtual throttle changes at a configured rate, initially 0.5 per second. Vehicle-specific shaping can differ: the FPV adapter takes the pre-expo value and uses its flight-controller rate model. [app/input/multirotor_input.gd:365–385](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/multirotor_input.gd#L365-L385) The profile carries its throttle interpretation explicitly. [app/input/controller_profile.gd:14–80](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L14-L80)

Radio profiles normally use absolute throttle and centered flight channels; the radio wizard measures their mappings and endpoints. Generic joystick mappings may retain assumed/default endpoint ranges after manual axis detection. The generic starter resembles AETR, but a new recognized radio must complete the wizard before Save; a family name is not calibration evidence. Unknown devices remain unconfigured until the user configures them. The shared reader's known-gamepad path can use a connected, focused, generation-verified polling callback. Raw radios retain an event-based low-throttle requirement. [app/input/rc_input.gd:76–119](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L76-L119); [app/input/controller_service.gd:175–191](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L175-L191); [app/ui/controller_setup.gd:635–647](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L635-L647); [docs/FIRST-LAUNCH.md:167–171](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L167-L171)

Radio profiles deliberately avoid the gamepad deadzone/expo stage. Generic joystick shaping can occur later in the aircraft control path; it should not be confused with the shared gamepad conditioner. This is why adding gamepad shaping indiscriminately is not the proposed repair for calibration bias. [app/input/controller_profile.gd:568–607](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L568-L607); [docs/FIRST-LAUNCH.md:80–82](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L80-L82)

### 3.3 JETI recognition and what it proves

The JETI helper requires the complete implemented USB pair, vendor 0x0483 and product 0xA07C, plus corroborating JETI identity text. It rejects ambiguous, contradictory or explicitly emulated identities. A JETI-looking name by itself therefore does not authorize generic gamepad defaults. The starter uses absolute throttle and clean radio action bindings. This is conservative software identification of the implemented family; it is not evidence that every JETI model, firmware or USB descriptor has been physically tested. [app/input/jeti_radio.gd:4–43](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/jeti_radio.gd#L4-L43); [app/input/jeti_radio.gd:70–106](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/jeti_radio.gd#L70-L106); [app/input/controller_registry.gd:153–172](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_registry.gd#L153-L172); [app/input/controller_profile.gd:44–80](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L44-L80)

The existing qualification plan already distinguishes software support and external basic-flight reports from outstanding Godot switch mapping and native-package qualification. That distinction is retained throughout this audit. [docs/plans/controller-support.md:41–52](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/controller-support.md#L41-L52); [docs/FIRST-LAUNCH.md:121](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L121)

### 3.4 Calibration sequence and arithmetic

The wizard is a measured-function state machine:

1. Capture rest: center roll/pitch/yaw and hold throttle low.
2. Sweep throttle fully and return low.
3. Hold roll right, confirm direction, sweep the opposite direction and return center.
4. Repeat for pitch back/forward and yaw right/left.
5. Review the resulting mapping. In Home, demonstrate normalized throttle FULL and then LOW before using the calibration.
6. Merge into the draft; Save commits settings. The shared reader requires fresh low-throttle evidence after saving a radio; CTRL-01 describes the quad adapter exception.

The calibration scans 10 raw axes. It requires a minimum sweep of 0.5 in the raw −1…+1 range, rejects substantial competing-axis motion, and verifies returns using different throttle/center tolerances. The Home final review accepts FULL at least 0.95 and LOW at most 0.05. The in-flight wizard intentionally has a different review flow, described in the guide. [app/input/rc_calibration.gd:11–40](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_calibration.gd#L11-L40); [app/input/rc_calibration.gd:145–210](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_calibration.gd#L145-L210); [app/ui/radio_calibration_setup.gd:123–166](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/radio_calibration_setup.gd#L123-L166); [docs/FIRST-LAUNCH.md:169–171](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L169-L171)

For a centered semantic axis with raw reading x, measured center c, minimum l and maximum h, the normalizer uses (x−c)/(h−c) above center and (x−c)/(c−l) below center, clamps to −1…+1, and applies inversion. Absolute throttle uses (x−l)/(h−l), clamped to 0…1, with inversion producing 1−value. Per-side normalization correctly accommodates asymmetric travel. These equations also explain why a biased saved center or endpoint produces a persistent output offset. [app/input/controller_profile.gd:553–608](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L553-L608)

## 4. Detailed findings

<a id="ctrl-01"></a>

### CTRL-01 — Quad treats a configured raw source as ready while RcInput still withholds throttle

**Priority:** P1  
**Confidence:** high for the reproduced software sequence  
**Affected route:** FPV/multirotor using a configured radio or generic joystick  
**Precondition:** no qualifying fresh low-throttle axis event has reached the common reader

**Observed behavior.** The quad adapter considers a configured non-gamepad source ready without consulting RcInput.armed, then decodes polled absolute throttle independently. A fresh keyboard E arm command at low throttle satisfies the quad controller's own arming sequence. Subsequent polled full throttle reaches full collective even though the common reader remains unarmed and would output zero throttle.

**Reproduction.**

1. Connect a valid synthetic radio profile to the actual MultirotorInput adapter.
2. Supply low throttle through the injected poll reader, but send no RC axis motion events.
3. Give the flight controller an OFF frame, then a fresh keyboard E ON command at low throttle.
4. Change only the polled throttle to full.

The actual adapter, flight controller and controlled plant produced:

~~~
OFF:  radio_armed=false  motor=0
ON:   radio_armed=false  motor=1  motor_armed_enum=1
FULL: radio_armed=false  motor=1  collective=1.0  command0=1.0
~~~

A companion probe observed source_ready=1 while radio.sticks().throttle remained zero.

**Root cause.** Non-gamepad readiness checks connection/profile configuration, while throttle is decoded directly from polled axes. That path bypasses the reader's fresh-event gate. The flight controller correctly enforces its own low-throttle/OFF→ON condition, but trusts the adapter's incorrect readiness signal. [app/input/multirotor_input.gd:272–295](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/multirotor_input.gd#L272-L295); [app/input/multirotor_input.gd:365–401](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/multirotor_input.gd#L365-L401); [app/input/rc_input.gd:222–249](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L222-L249); [app/input/rc_input.gd:357–370](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L357-L370); [app/physics/multirotor/flight_controller.gd:228–285](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/physics/multirotor/flight_controller.gd#L228-L285)

**Why current tests miss it.** The multirotor input test explicitly accepts immediate readiness from a poll without a radio motion event. This expectation encodes the divergent contract rather than checking the shared one. [app/tests/test_mr_input.gd:58–66](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_mr_input.gd#L58-L66)

**Recommended correction.** Require valid current-generation raw-source evidence before advertising readiness or forwarding authority. Keep the flight controller's independent low-throttle and OFF→ON arm gate. Preserve the verified polling path for recognized gamepads; raw transmitters and trusted standardized pads have different evidence rules. Invalidate the relevant evidence on source changes and focus recovery.

**Regression acceptance.** Adapter and flight controller together must remain unready/unarmed for no-event polls, high-before-low and stale prior-generation samples; a valid fresh low event must enable the intended sequence. Include disconnect/reconnect, focus/hold, both throttle directions, and verified gamepad polling. Explicitly test whether an OFF observation is accepted only after source readiness: the current controller can record OFF while unready, so simply zeroing throttle is not sufficient. [app/physics/multirotor/flight_controller.gd:252–285](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/physics/multirotor/flight_controller.gd#L252-L285)

**Evidence:** evidence/routing/probe/quad_fc.gd; evidence/routing/runs/routing-quad-fc-_56c9onu/{engine.log,report.json}; companion routing-probe-o8_odrzc.

**Boundary.** This proves a simulator input-guard bypass with synthetic data. It does not prove false physical readings, RF-loss behavior, an OS-suspension outcome, or control of a real aircraft.

<a id="ctrl-02"></a>

### CTRL-02 — A replacement device with the same handle can take over an existing saved profile

**Priority:** P1  
**Confidence:** high for the executed Home/setup/save path  
**Affected route:** editing an already saved gamepad or radio profile while connection identity changes

**Observed behavior.** Controls retains a draft keyed to an old numeric selection. Save associates that draft with whatever device currently occupies the number. The original profile UUID is retained, so the save overwrites the old association instead of creating an explicitly reviewed replacement.

**Reproduction.**

1. Save profile A and open Controls on device handle 5, generation 1.
2. Edit A's profile name.
3. Disconnect A, then update the registry with device B using handle 5, generation 2.
4. Save without explicitly choosing B.

The probe ran this once with saved gamepad A and once with saved radio A. Both saves succeeded, selected B for flight, and stored B's serial/GUID/VID/PID under A's existing UUID. The radio variant retained A's old radio mapping.

**Root cause.** Device refresh preserves the draft and integer selection. Candidate association is then rebuilt from current device metadata. Generation checks protect newly measured calibration/menu evidence, but ordinary edits to a previously saved mapping have no equivalent draft-origin lease. The service's commit boundary checks that the handle is connected, not that it is the connection the editor originally selected. [app/ui/controller_setup.gd:308–320](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L308-L320); [app/ui/controller_setup.gd:2181–2193](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2181-L2193); [app/ui/controller_setup.gd:3869–3915](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3869-L3915); [app/ui/controller_setup.gd:635–647](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L635-L647); [app/input/controller_service.gd:413–429](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L413-L429); [app/input/controller_profile_store.gd:57–75](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L57-L75)

**Recommended correction.** Bind every selected flight/menu draft to a connection token containing the handle, generation and relevant identity. Revalidate before building an association and again at the service commit boundary. If it changed, preserve A's draft and saved profile, and require explicit selection/review of B. A deliberate “use this mapping on another device” operation should be explicit and should make replacement versus copying clear.

**Regression acceptance.** Cover saved radio and gamepad mappings; direct replacement and separate disconnect/reconnect; same physical identity with a new generation; menu-only replacement; and activation rejection while paused. Assert disk bytes remain unchanged, and compare role selections with their state immediately before the rejected stale Save; disconnect has already cleared the old live selection.

**Evidence:** evidence/profiles/repro/probe.gd; evidence/profiles/checks/profile-audit-probe-clean-95t_jjdb/{engine.log,report.json}.

**Boundary.** The registry replacement is synthetic. The proof concerns Home Save, not an observed physical handle reuse or automatic in-flight transfer. Existing leases for new calibration and menu challenges should be retained; the defect is the uncovered saved-profile editing path.

<a id="ctrl-03"></a>

### CTRL-03 — Closing on a clean profile silently discards another profile's dirty draft

**Priority:** P2  
**Confidence:** high  
**Affected route:** switching between saved profiles while editing Controls

**Reproduction.** Edit saved profile A, switch to clean saved profile B on the same selected device, then request Close. The actual screen still contained A's edited draft in its per-context cache, but has_unsaved_changes() returned false and close_requested was emitted immediately. The owner then discards the screen, taking A's draft with it.

**Root cause.** Profile switching remembers multiple drafts and clean snapshots; the dirty check examines only the current context. The documented Save/Discard/Keep editing protection therefore does not cover all the state that the screen retains. [app/ui/controller_setup.gd:327–373](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L327-L373); [app/ui/controller_setup.gd:2357–2373](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2357-L2373); [app/app_root.gd:2070–2071](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2070-L2071); [docs/FIRST-LAUNCH.md:117](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L117)

**Recommended correction.** Track dirty state across all retained contexts, including pending calibration and names. Define a coherent Save policy: commit all reviewed dirty drafts, or save the current draft while clearly keeping other unsaved contexts open. Merely making has_unsaved_changes() inspect every draft is insufficient, because the current Save implementation commits only the current candidate and can still close over other changes. [app/ui/controller_setup.gd:3886–3917](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3886-L3917)

**Regression acceptance.** A dirty→B clean→Back; several dirty profiles/devices; Save B while A remains dirty; Discard all; Keep editing; calibration pending in an inactive context; clean-all exit. Assert the dialog describes what will actually be saved or discarded.

**Evidence:** profile-audit-probe-clean-95t_jjdb. Existing tests restore A when switching back but do not cover closing on B. [app/tests/test_controller_profile_creation.gd:85–102](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_controller_profile_creation.gd#L85-L102)

<a id="ctrl-04"></a>

### CTRL-04 — Airship pause freezes the very controls that Resume requires the user to correct

**Priority:** P2  
**Confidence:** high in the isolated input/session sequence  
**Affected route:** airship keyboard input and gamepad rate throttle

**Reproduction and observed values.**

| Before Pause | Attempt while paused | Retained value | Resume result |
|---|---|---|---|
| Keyboard throttle 0.5 | Hold S for five simulated seconds | Throttle 0.5 | “Lower the throttle to resume.” |
| Keyboard yaw 1.0 | Release yaw for five simulated seconds | Yaw 1.0 | “Centre the yaw stick to resume.” |
| Verified gamepad rate throttle 0.5 | Hold the throttle stick down for five simulated seconds | Throttle 0.5 | “Lower the throttle to resume.” |

**Root cause.** Ordinary Pause retains commands, then polls input with integrate=false. That freezes keyboard command integration and the gamepad's virtual throttle. Session.resume requires throttle ≤0.05 and centered yaw, leaving no ordinary menu/input path to satisfy the requirement. [app/vehicles/airship/airship_scene.gd:313–369](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/airship/airship_scene.gd#L313-L369); [app/vehicles/airship/airship_scene.gd:440–448](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/airship/airship_scene.gd#L440-L448); [app/input/airship_input.gd:57–85](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/airship_input.gd#L57-L85); [app/input/commands.gd:28–36](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/commands.gd#L28-L36); [app/input/rc_input.gd:349–356](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L349-L356); [app/sim/airship/session.gd:230–239](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/sim/airship/session.gd#L230-L239)

**Recommended correction.** Separate simulation integration from safe input recovery. Either expose an explicit reset of virtual throttle/yaw while held, or permit only reduction/centering in the paused control state without advancing simulation or allowing upward throttle. Communicate the chosen policy in the pause prompt.

**Regression acceptance.** Reach nonzero controls through normal input, pause normally, correct controls and resume without restarting. Cover keyboard yaw and throttle, both gamepad throttle presets, raw absolute radio throttle, repeated pauses and focus changes.

**Evidence:** evidence/routing/probe/airship_pause.gd; evidence/routing/runs/routing-airship-pause-isolated-htm18wz6/{engine.log,report.json}.

**Boundary.** The real adapter and resume method were executed with a prepared-session seam and an unrelated collision dependency stub. This is not a rendered world/physics test. Restart or an application-focus reset can clear the state, so the finding is an ordinary pause-flow dead end, not the absence of every possible workaround.

<a id="ctrl-05"></a>

### CTRL-05 — Airship bypasses shared controller ownership and modern profile resolution

**Priority:** P2  
**Confidence:** high in source paths; startup behavior additionally reproduced  
**Affected route:** airship controller launch, hotplug, Pause and gamepad recovery

This is one integration family with three distinct consequences.

**A. Selected device and V2 profile are ignored.** AppRoot creates the airship without injecting the common registry/profile resolver. The scene connects the first enumerated joystick, and its input adapter loads only the legacy rc_calibration.cfg. Its apply_controller_selection hook returns success without applying a change, while its refresh hook is empty. Selecting Keyboard or a particular device in shared Controls therefore does not govern this route as it does the managed flight paths. A valid V2 radio profile can appear unconfigured; a custom gamepad mapping can fall back to defaults; an extant legacy calibration can take precedence over current settings. [app/app_root.gd:895–905](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L895-L905); [app/vehicles/airship/airship_scene.gd:158–159](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/airship/airship_scene.gd#L158-L159); [app/vehicles/airship/airship_scene.gd:652–658](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/airship/airship_scene.gd#L652-L658); [app/input/airship_input.gd:16–47](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/airship_input.gd#L16-L47); [app/input/controller_profile_store.gd:8–46](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L8-L46)

**B. Foreign raw buttons and unrelated hotplug affect Pause.** The scene treats JOY_BUTTON_START from any device as Pause without checking the selected owner or recognized-gamepad status. A second controller, or a raw transmitter switch on the same numeric button index, can open Pause or attempt Resume. Any connection callback also opens/updates the menu even when the input adapter ignored the unrelated device. Resume still checks its own conditions; this is not evidence that a foreign controller can always resume or command throttle. [app/vehicles/airship/airship_scene.gd:301–340](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/airship/airship_scene.gd#L301-L340); [app/input/airship_input.gd:31–47](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/airship_input.gd#L31-L47)

**C. Neutral gamepad polling cannot establish readiness.** The airship never binds the trusted connected/focused gamepad-verification callback. A synthetic known pad remained unarmed after one second of neutral polling; after events on all four mapped axes and 0.25 seconds of neutral dwell, it armed. A real backend may deliver initial events, so physical frequency depends on device/backend behavior. The fallback requires fresh events for all four mapped axes and neutral dwell; users may need to move them if the backend does not emit initial events. The shared verified path can instead establish readiness from neutral polling. [app/input/airship_input.gd:31–79](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/airship_input.gd#L31-L79); [app/input/rc_input.gd:169–176](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L169-L176); [app/input/rc_input.gd:310–335](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L310-L335); [app/input/rc_input.gd:555–597](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L555-L597)

**Recommended correction.** Adopt ControllerService ownership and V2 resolution, with current-generation selection and explicit paused source transitions. Route semantic actions through the chosen role/profile; react only to meaningful owner changes. Bind trusted neutral-poll verification only for a selected, connected, focused standardized gamepad. Preserve raw-radio fresh-evidence requirements.

**Regression acceptance.** Selected Keyboard with a pad connected; selected second controller; current V2 radio and gamepad profiles; stale legacy file present; foreign Start and transmitter raw button 6; unrelated hotplug; initial neutral gamepad; focus recovery and verifier revocation. Ownership correction and CTRL-04 both need tests because fixing one does not repair the other.

**Evidence:** the source paths above; evidence/routing/probe/probe.gd and routing-probe-o8_odrzc. Launch and event routing follow the cited source call chain; no rendered launch/foreign-button sequence or real-device behavior was executed.

<a id="ctrl-06"></a>

### CTRL-06 — Maintained AUX switch capture omits the connection-generation lease

**Priority:** P2  
**Confidence:** high for an atomic registry identity replacement  
**Affected route:** capturing a maintained AUX switch position

**Reproduction.** Start capturing the Flaps switch on radio A at handle 5. The capture generation remains zero. Replace A's registry observation directly with B at the same handle, advancing generation 1→2 without an intermediate disconnected snapshot. Capture remains active; B's button 42 changes A's draft switch group from [20,21] to [42,21].

**Root cause.** Ordinary action capture records a connection generation; AUX capture records only the integer handle. The registry-change cancellation checks a generation mismatch only when the saved capture generation is greater than zero. The later AUX event path accepts the same handle. [app/ui/controller_setup.gd:3438–3483](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3438-L3483); [app/ui/controller_setup.gd:2181–2190](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2181-L2190); [app/ui/controller_setup.gd:2090–2105](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2090-L2105); [app/ui/controller_setup.gd:3534–3551](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3534-L3551)

**Recommended correction.** Give every capture mode the same lease object and check it both on registry changes and immediately before accepting an event. Consolidating that small ownership primitive would prevent another capture mode from omitting a field.

**Regression acceptance.** Atomic replacement, changed identity metadata, explicit disconnect/reconnect, same-identity new generation, held/released switches and an uninterrupted valid connection. The original draft must remain unchanged on cancellation.

**Evidence:** evidence/profiles/repro/capture_probe.gd; capture-audit-probe-_6ptodtq.

**Boundary.** An ordinary explicit disconnect already cancels capture. The reproduced omission is the direct identity-replacement observation; real backend delivery frequency was not measured.

<a id="ctrl-07"></a>

### CTRL-07 — Tiny motion at a resting throttle endpoint terminates action Remap

**Priority:** P2  
**Confidence:** high for event handling; physical jitter frequency unmeasured  
**Affected route:** ordinary action Remap on a configured radio

**Reproduction.** With primary throttle on axis 2 resting at −1, start Remap for camera_cycle. Before pressing the intended button, send one selected-device axis-2 event at −0.999. The event satisfies the absolute-magnitude threshold, becomes an axis binding, is rejected for using a flight axis, and ends capture. The intended button never gets a chance to complete the request.

**Root cause.** Remap does not snapshot axis baselines. The input handler accepts a motion whose absolute value is at least 0.65; only the separate Find flow checks movement relative to a baseline. Primary-axis conflict validation is correct, but its result closes the capture for an incidental event. [app/ui/controller_setup.gd:3438–3459](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3438-L3459); [app/ui/controller_setup.gd:2129–2141](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2129-L2141); [app/ui/controller_setup.gd:3500–3530](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3500-L3530); [app/input/controller_actions.gd:281–286](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_actions.gd#L281-L286); [app/input/controller_actions.gd:327–330](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_actions.gd#L327-L330)

**Recommended correction.** Record finite baselines at capture start and require deliberate displacement or an appropriate release/activation sequence before accepting an axis. Preserve button/key capture and the explicit Learn axis flow. An irrelevant or conflicting endpoint event should not consume the user's whole capture request.

**Regression acceptance.** Endpoint jitter; centered jitter; deliberate motion from an endpoint; a valid button after irrelevant motion; primary-axis conflict feedback; invalid samples and disconnect. Ensure relative-motion filtering does not make intentionally maintained switch axes impossible to assign.

**Evidence:** capture-audit-probe-_6ptodtq. This does not establish that every radio emits idle jitter; it proves the UI mishandles a plausible and legal input sequence.

<a id="ctrl-08"></a>

### CTRL-08 — A radio Mode 1 selection does not reach the calibration diagram

**Priority:** P2  
**Confidence:** high  
**Affected route:** setup assistant → radio calibration

**Reproduction.** Leave the HUD stick-mode preference at its default Mode 2, select radio Mode 1 in the assistant, and start calibration. The actual UI classes reported:

~~~
assistant=mode1
wizard_mode=2
left=[yaw,throttle]
right=[roll,pitch]
~~~

The assistant's Test and Summary use its local Mode 1 selection, but the wizard draws Mode 2.

**Root cause.** The bridge accepts Mode 1/2 for radios without transmitting the choice to the wizard. The calibration view separately loads a HUD presentation preference, defaulting to Mode 2. [app/ui/controls/setup_assistant.gd:372–395](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd#L372-L395); [app/ui/controls/setup_assistant.gd:784–795](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd#L784-L795); [app/ui/controls/setup_assistant_bridge.gd:74–79](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant_bridge.gd#L74-L79); [app/ui/radio_calibration_setup.gd:91–92](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/radio_calibration_setup.gd#L91-L92); [app/ui/controls/calibration_view.gd:217–236](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/calibration_view.gd#L217-L236); [app/ui/controls/calibration_view.gd:294–369](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/calibration_view.gd#L294-L369)

**Recommended correction.** Pass the selected mode explicitly as calibration presentation context. Decide separately whether the user's choice should update a persisted radio presentation preference; do not silently infer it from an unrelated HUD setting.

**Regression acceptance.** Mode 1 and Mode 2 against the opposite saved HUD preference; throttle and pitch targets; return-to-center diagrams; Test/Summary consistency; reopening.

**Evidence:** evidence/calibration/project/ui_probe.gd; calibration-ui-audit-s8fv9m38.

**Boundary.** This is confirmed contradictory guidance. It is not proof that Mode 1 always produces a wrong channel mapping: the wizard still names functions in text and learns the axis the person moves. Mapping damage depends on following the misleading visual.

<a id="ctrl-09"></a>

### CTRL-09 — Recalibration drops overlapping AUX bindings without telling the user about all removals

**Priority:** P2  
**Confidence:** high  
**Affected route:** Home and managed in-flight radio recalibration

**Reproduction.** Begin with flight axes 0/1/2/3, gear on axis 5 and smoke on axis 6. Recalibrate roll onto 5 and pitch onto 6. Both AUX bindings disappear after the executed merge, and the wizard returns only the final smoke warning. The source-traced Home path consequently displays only that warning. Successful fixed-wing/helicopter in-flight persistence paths discard even that warning from their result.

**Root cause.** Removing a primary/AUX conflict is correct, but each removal overwrites one aux_warning string. Home can display only the last value. The in-flight paths pass calibration.profile into persistence without carrying the warning. Engine log warnings exist; the defect is incomplete or absent user-facing disclosure of configuration changes. [app/input/rc_calibration.gd:337–353](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_calibration.gd#L337-L353); [app/input/controller_profile.gd:207–225](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L207-L225); [app/ui/radio_calibration_setup.gd:155–166](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/radio_calibration_setup.gd#L155-L166); [app/ui/controller_setup.gd:518–539](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L518-L539); [app/sim/flight_session.gd:1866–1871](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/sim/flight_session.gd#L1866-L1871); [app/sim/helicopter_flight_session.gd:984–989](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/sim/helicopter_flight_session.gd#L984-L989)

**Recommended correction.** Return a structured list of every removed binding, propagate it through all callers, and include it in the final calibration review/save result. Preserve safe conflict exclusion while making reassignment needs explicit. A single warning string is inadequate for a multi-change operation.

**Regression acceptance.** Two or more conflicts; smoke plus another AUX; surviving unrelated AUX; Home draft and both in-flight paths. Assert the stored mapping, review text and final result all agree. Existing tests verify one overlap is removed, without checking multiple removals or the final user message. [app/tests/test_controller_aux_runtime.gd:153–167](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_controller_aux_runtime.gd#L153-L167)

**Evidence:** evidence/calibration/project/audit_probe.gd; calibration-range-kind-oc1xiz39. Two expected overlap warnings are retained in the log.

<a id="ctrl-10"></a>

### CTRL-10 — A prior action binding can invalidate a completed calibration without an actionable explanation

**Priority:** P2  
**Confidence:** high  
**Affected route:** recalibration after transmitter channel reassignment

**Reproduction.** In a valid existing profile, assign camera_cycle to axis 5 and primary flight axes to 0/1/2/3. Supply a representative valid calibration mapping that puts roll on axis 5. That mapping validates, but the executed merge with the old actions returns an empty dictionary. Direct validation identifies the real cause: camera_cycle uses primary flight axis 5. The source-traced UI path then reports only “Invalid calibration. The draft is unchanged,” after popping the wizard; that complete UI sequence was not executed.

**Root cause.** The merge preserves prior actions, correctly rejects their new primary-axis overlap, and then throws away the measured result along with the detailed validation reason. Home and in-flight callers receive a generic failure. [app/input/controller_actions.gd:270–286](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_actions.gd#L270-L286); [app/input/controller_profile.gd:193–225](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L193-L225); [app/ui/controller_setup.gd:518–521](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L518-L521); [app/app_root.gd:2130–2134](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2130-L2134); [app/input/controller_service.gd:361–369](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L361-L369)

**Impact.** The prior saved profile remains intact, which is desirable. The user loses completed calibration work and has to discover the hidden conflict, clear/remap the old action and repeat the wizard.

**Recommended correction.** Keep measured calibration as a reviewable draft. Return structured conflicts with action IDs and axes, then let the user resolve or cancel before committing. Do not silently delete explicit user action bindings.

**Regression acceptance.** Existing flight and Pause axis bindings; several conflicts; resolution without repeating measurements; cancel preserving the old active profile; activation failure and storage rollback.

**Evidence:** calibration-range-kind-oc1xiz39. This is distinct from CTRL-09: AUX collisions currently remove bindings, whereas semantic action collisions reject the entire merge.

<a id="ctrl-11"></a>

### CTRL-11 — Instantaneous rest and extreme samples can produce an accepted biased calibration

**Priority:** P2, robustness  
**Confidence:** high for the demonstrated sample sequence; occurrence on physical devices unknown  
**Affected route:** raw radio calibration and final throttle verification

**Reproduction.**

1. Rest capture sees roll +0.05, although subsequent stable center is 0.0.
2. Throttle's actual idle/full readings are −0.8/+0.8.
3. Inject one valid in-range sample at −0.87 during its sweep.
4. Complete the remaining movements normally and return to actual idle/center.
5. Deliver a fresh low-throttle event and poll the resulting profile.

Calibration succeeds with throttle endpoints [−0.87,+0.8] and roll center +0.05. At actual stable idle/center the reader arms with:

~~~
throttle = 0.041916
roll     = -0.058824
~~~

The Home FULL/LOW thresholds would also accept full 1.0 and low 0.041916. That conclusion follows from the UI source; this bias probe did not execute the final Home verification UI.

**Root cause.** One rest sample becomes the center. Unfiltered absolute extrema become endpoints. Return validation permits the demonstrated disagreement: 5% of throttle span and 10% of the shorter centered-axis side. The final LOW threshold then accepts the nonzero normalized idle. [app/input/rc_calibration.gd:145–210](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_calibration.gd#L145-L210); [app/ui/radio_calibration_setup.gd:135–166](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/radio_calibration_setup.gd#L135-L166); [app/input/controller_profile.gd:553–607](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L553-L607); [app/input/rc_input.gd:240–249](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L240-L249); [app/input/rc_input.gd:357–370](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_input.gd#L357-L370)

**Recommended correction.** Measure a bounded stable neutral/idle window, compare the confirmed return against that estimate, and reject or clearly flag significant disagreement. Require robust/dwell evidence for endpoints so one isolated sample cannot dominate. Select tolerances from actual device sample distributions, reduced travel and asymmetric ranges. Avoid silently imposing gamepad expo or a blanket deadzone on radio profiles.

**Regression acceptance.** Both throttle directions, a stable small jitter band, an isolated in-range spike, a biased first sample followed by stable return, asymmetric endpoints, reduced travel, and final preview/armed output. The acceptance criterion should specify how closely confirmed stable idle must map to zero, rather than merely repeating the current thresholds.

**Evidence:** calibration-range-kind-oc1xiz39. The test establishes accepted output bias; it does not establish a specific transmitter's noise rate, a resulting physical motion, or an application-wide need for smoothing.

<a id="ctrl-12"></a>

### CTRL-12 — A valid V2 profile can retain absolute roll/pitch/yaw semantics after recalibration

**Priority:** P2  
**Confidence:** high  
**Precondition:** an accepted V2 profile supplied or altered outside a demonstrated normal UI producer, with a signed flight channel marked absolute

**Reproduction.** Start with a default radio profile and change only roll.range_kind to absolute. Profile validation accepts it. Merge a representative valid calibration dictionary with roll min −1, center 0, max +1. The merge is accepted and retains the absolute range kind. Normalization then yields +0.5 at stick center and 0 at full left, rather than 0 and −1. Pitch and yaw have the same schema exposure.

**Root cause.** The schema permits either range kind for each channel but constrains the throttle interpretation separately. Recalibration copies axis, inversion and endpoints but preserves the old range_kind. Absolute normalization ignores the measured center and outputs 0…1. [app/input/controller_profile.gd:427–491](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L427-L491); [app/input/controller_profile.gd:193–225](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L193-L225); [app/input/controller_profile.gd:553–608](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L553-L608)

**Recommended correction.** Enforce signed semantics for roll/pitch/yaw, or explicitly separate raw physical representation from signed command output. Recalibration must deliberately set the measured semantic range kind. **Ship a migration/repair strategy with the validation change:** the current loader rejects the whole collection if any stored profile fails validation, so tightening the validator alone can render otherwise healthy profiles unavailable. Preserve the original bytes and make repair/quarantine explicit. [app/input/controller_profile_store.gd:240–265](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L240-L265)

**Regression acceptance.** Each signed primary channel, inversion, V2 round trip, recalibration of a previously accepted absolute channel, a store containing both affected and healthy profiles, and unchanged supported throttle modes.

**Evidence:** calibration-range-kind-oc1xiz39. This is an accepted-schema and migration weakness with an uncommon prerequisite. The probe supplied an in-memory legacy-shaped calibration dictionary; it did not execute the wizard for this case. The existing legacy importer sets signed channels to centered semantics, so no claim is made that the standard wizard/importer produces this profile. [app/input/controller_profile.gd:155–167](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L155-L167)

<a id="ctrl-13"></a>

### CTRL-13 — The generic joystick assistant offers a calibration it cannot perform and cannot complete first setup

**Priority:** P2  
**Confidence:** high in the executed refusal and source chain  
**Affected route:** first-time generic joystick through “Set up this device…”

**Observed behavior.** The assistant describes joystick calibration like radio calibration and offers a Calibrate step. The executed bridge call refuses to start calibration for a joystick and tells the user to use Detect in Flight axes. The remaining first-time flow was traced in source: skipping does not configure or enable the mapping; the assistant has neither Detect nor the external “use this custom mapping for flight” control; Save delegates to the main screen, whose candidate remains unconfigured and is rejected.

**Root cause.** The assistant's advertised steps and bridge capabilities disagree. New joystick drafts begin configured=false; reselecting the same kind does not change that; skipping only advances the page; final candidate construction reads the still-unchecked external enable control. The guide says joysticks skip calibration and use Detect, which does not match the offered assistant sequence. [app/ui/controls/setup_assistant.gd:49–55](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd#L49-L55); [app/ui/controls/setup_assistant.gd:408–412](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd#L408-L412); [app/ui/controls/setup_assistant.gd:839–856](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd#L839-L856); [app/ui/controls/setup_assistant_bridge.gd:49–52](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant_bridge.gd#L49-L52); [app/ui/controls/setup_assistant_bridge.gd:92–101](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant_bridge.gd#L92-L101); [app/ui/controls/setup_assistant_bridge.gd:171–177](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant_bridge.gd#L171-L177); [app/ui/controller_setup.gd:2340–2349](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L2340-L2349); [app/ui/controller_setup.gd:3854–3860](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3854-L3860); [app/input/controller_profile.gd:332–335](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L332-L335); [docs/FIRST-LAUNCH.md:107](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/FIRST-LAUNCH.md#L107)

**Recommended correction.** Either implement actual joystick axis assignment and explicit enablement in the assistant, or replace the unsupported step with a clear transition to the main Flight axes workflow. Do not silently enable guessed axes simply to make Save succeed.

**Regression acceptance.** Drive a new generic joystick from discovery through the actual assistant bridge and owner to a valid saved mapping. Assert the user explicitly confirms the mapping; Cancel preserves the previous state; revisiting an already configured joystick remains usable.

**Evidence:** calibration-ui-audit-s8fv9m38 executes the calibration refusal. The subsequent first-time Save dead end is established from the source chain, not a full rendered UI session. Existing tests expect both the offered step and the refusal independently. [app/tests/test_setup_assistant.gd:288–290](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_setup_assistant.gd#L288-L290); [app/tests/test_setup_assistant_wiring.gd:197–208](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_setup_assistant_wiring.gd#L197-L208)

<a id="ctrl-14"></a>

### CTRL-14 — Concurrent application instances can successfully save and lose one another's changes

**Priority:** P2  
**Confidence:** high for the controlled interleaving  
**Precondition:** two processes share the same controller profile store

**Reproduction.** Two Godot processes each invoke the real profile save on the same initially empty store. A scheduling seam pauses each at transaction entry, after its real load/merge. Once both have read the old store, release A to finish, then B. Both report success. Final load contains only Writer B; Writer A's acknowledged profile has disappeared.

**Root cause.** The store's read/modify/write is not protected across processes. Atomic file replacement cannot reconcile two snapshots read before either write. Fixed .tmp and .rollback paths add a separate contention risk, but simultaneous rename contention was not needed for the demonstrated lost update. [app/input/controller_profile_store.gd:57–75](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L57-L75); [app/input/controller_profile_store.gd:326–364](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L326-L364)

The project already has an explicit cross-process lock in preferences persistence, providing a local design precedent. [app/app_state/preferences_file.gd:87–105](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_state/preferences_file.gd#L87-L105)

**Recommended correction.** Protect the whole read/validate/merge/commit and relevant rollback/recovery boundary, using a cross-process lock or versioned compare-and-swap with reliable retry. Unique temporary names alone will not fix stale-snapshot overwrites. Runtime activation failure must not roll back another process's later valid commit.

**Regression acceptance.** Simultaneous creation of distinct profiles; edits to distinct existing profiles; UI preference updates; commit/activation failure interleavings; crash/stale-lock recovery. Preserve both acknowledged successful updates or report/retry a conflict explicitly.

**Evidence:** evidence/profiles/repro/concurrent_writer.gd; evidence/profiles/run_concurrent.py; checks/race-writer-A-voljxvdk, race-writer-B-5x8nh0xi and race-final-store-2eo9smvp. The portable launcher preserves this scheduling protocol.

**Boundary.** This is a two-process failure, not a claim that ordinary single-instance saves routinely lose data. The transaction scheduler is a test seam; production load/merge and write implementation remain unchanged. No power-loss durability conclusion is drawn.

<a id="ctrl-15"></a>

### CTRL-15 — AppRoot repeatedly rebuilds bindings and copies profiles for each axis event

**Priority:** P2, optimization  
**Confidence:** high for operation counts and the isolated measurement; full-application impact unmeasured  
**Affected route:** AppRoot event dispatch with a selected controller

**Measured work.** A single axis event caused the following directly counted calls in the actual-method projection:

| Work per event | Selected controller | Unselected controller |
|---|---:|---:|
| Binding-map resolutions | 7 | 7 |
| Profile-resolution calls | 8 | 8 |

The fixture also held 30 generic action identities after each event. That is a map-size observation, not an instrumented allocation count. AppRoot's binding resolver obtains a profile and builds effective actions repeatedly across generic actions, rates, restart and dispatch. ControllerService's profile cache still returns a deep duplicate on cache hits. Main disables accumulated input, making per-event work especially important to measure. [app/app_root.gd:2193–2206](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2193-L2206); [app/app_root.gd:2411–2426](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2411-L2426); [app/app_root.gd:2563–2666](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2563-L2666); [app/app_root.gd:2694–2721](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2694-L2721); [app/input/controller_service.gd:239–279](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L239-L279); [app/input/controller_actions.gd:161–226](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_actions.gd#L161-L226); [app/main.gd:795–796](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/main.gd#L795-L796)

**Timing experiment.** Seven alternating rounds of 2,000 events, after warm-up, were run with other audit engine probes stopped. Environment: Linux container, AMD EPYC 9V74, pinned Godot. The experimental variant adds binding-map reuse; the production projection also includes lightweight binding-call counting instrumentation, while both variants use the counting service. The cache has no production invalidation contract.

| Variant | Median microseconds/event | Relative result in this fixture |
|---|---:|---:|
| Production method projection | 1,217.25 | Baseline |
| Experimental cached maps | 292.05 | 76.0% lower time; 4.17× throughput ratio |

This is an isolated router comparison with inert surrounding application objects. It excludes rendering, physics, event delivery and actual USB rates. It does not demonstrate a 4.17× faster simulator, and the prototype is not a shippable fix.

**Coverage gap.** The existing radio event benchmark instantiates Main directly and therefore omits AppRoot's dispatch path. Its synthetic event-rate model cannot certify the omitted code. [app/tests/bench_radio_events.gd:4–25](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/bench_radio_events.gd#L4-L25)

**Recommended correction.** Compile reusable effective binding tables when relevant state changes; avoid deep copying a full profile repeatedly within one event; index candidate bindings by source; reject irrelevant device events before expensive resolution where ownership permits. Define invalidation for profile revision/content, capabilities, selected roles, connection generation, activity/menu context, Save and rollback. Preserve OFF/release evidence, held actions and keyboard recovery during filtering.

**Regression and performance acceptance.** First assert semantic equivalence across roles, contexts, held switches, rebinds and profile rollback. Then measure the complete AppRoot→adapter→session route on representative native builds, recording input event rate, event age, frame-time percentiles and latency. Set a target only after that baseline; no speculative physical event rate is used to claim current FPS loss.

**Evidence:** evidence/parent/project/audit_hotpath.gd; project/shell_projection.gd; shell_projection_manifest.json; runs/hotpath-count-kyz0guyw and hotpath-timing-isolated-24rd1oly.

## 5. Policy decisions and support gaps kept separate from defects

These items deserve explicit decisions and tests, but the evidence does not justify presenting them as additional confirmed physical-device failures.

### DEC-01 — Serial-only matching can override conflicting incomplete identity

When both stored and observed USB IDs are absent/zero, a matching nonempty serial can match a profile even if nonempty GUIDs differ. The synthetic probe matched stored guid-A to sole connected guid-B using the same serial string. Current-device uniqueness does not prove serial reliability across devices or sessions. [app/input/controller_profile_store.gd:198–219](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L198-L219); [app/input/controller_profile_store.gd:383–403](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L383-L403)

**Decision needed:** how to handle placeholder/reused serials, conflicting GUIDs and deliberate USB/Bluetooth identity changes. Require actual backend observations before claiming a particular controller supplies unreliable serials. Add conflicting-identity fixtures and qualify legitimate cross-transport matches; do not simply reject every changed GUID or trust every serial.

### DEC-02 — Identical recalibration retains radio-menu proof despite broader documentation

The controller plan says recalibration invalidates radio-menu verification. The implementation invalidates it only when the mapping/action fingerprint changes. An exactly identical recalibration retains verified status; changing an endpoint correctly removes it. [docs/plans/controller-support.md:67](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/controller-support.md#L67); [app/input/controller_profile.gd:223–225](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L223-L225); [app/input/radio_menu.gd:14–75](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/radio_menu.gd#L14-L75)

**Decision needed:** require a new physical challenge after every recalibration, or document equality-based retention. The audit proves a contract ambiguity, not unsafe menu navigation. Test both equal and changed fingerprints under the chosen policy.

### DEC-03 — First rates/restart press may be intentionally consumed to establish OFF

Special rates/restart edge state starts by requiring an OFF observation. For a trusted standard pad already physically released, generic release polling does not clear that separate edge state, so the first press/release may serve only to establish OFF. Current tests explicitly expect initial suppression; others seed a release before the first press. [app/app_root.gd:2431–2513](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd#L2431-L2513); [app/tests/test_controller_routing_audit.gd:127–132](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_controller_routing_audit.gd#L127-L132); [app/tests/test_controller_rates.gd:138–145](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_controller_rates.gd#L138-L145)

**Decision needed:** whether a proven released poll from a selected, connected, focused standardized gamepad may satisfy this requirement. Keep explicit OFF evidence for raw switches and retain hold/rebind protection. Treat this as a usability/arming-policy consistency question, not an indisputable regression.

### DEC-04 — Ground vehicles and low-axis-count controllers have narrower support

The ground route explicitly accepts a connected recognized gamepad and reads fixed steering, trigger and button controls. It does not consume an arbitrary calibrated radio/pistol/joystick mapping. Shared flight profile validation also requires four distinct primary axes, so two-/three-axis devices need a product-level policy for missing channels. [app/vehicles/ground/ground_scene.gd:540–571](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/ground/ground_scene.gd#L540-L571); [app/vehicles/ground/ground_scene.gd:604–607](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/vehicles/ground/ground_scene.gd#L604-L607); [app/input/controller_profile.gd:419–444](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L419-L444)

**Decision needed:** define a vehicle capability/mapping contract before claiming pistol-transmitter or arbitrary joystick support. If support is expanded, represent steering/throttle/brake and absent channels explicitly; do not force them into aircraft roll/pitch/yaw/throttle defaults. Existing explicit rejection is preferable to a misleading “connected” success state.

## 6. Compatibility assessment

### 6.1 What the source supports versus what this audit qualifies

| Device family / mode | Implemented software path | Relevant findings / limits | Required next qualification |
|---|---|---|---|
| JETI DC/DS USB family recognized by the implemented identity rule | Conservative identity helper, clean radio starter, measured calibration, optional verified radio menu | CTRL-01/02 and common calibration/capture defects can affect this route; family detection alone does not establish model/firmware switch layout | Actual model, firmware, USB descriptors, all switch states, axis endpoints, both throttle directions, native export and reconnect/focus behavior |
| EdgeTX Classic | Generic radio/HID path and measured channels | Model configuration determines functions; do not infer verified AETR from the starter; common raw-radio findings apply | One recorded model with channels, switches and mixes documented; current Godot observations on each target OS |
| EdgeTX Advanced | Generic observation plus whatever descriptor/mapping is presented | Device type and channel modes can differ from Classic; reconnect/configure based on observed mapping | Joystick/Gamepad/MultiAxis variants, button versus axis switches, reduced/reversed ranges and descriptor changes |
| OpenTX / other recognized radio names | Radio-name hints plus explicit setup/calibration | Name recognition is not complete identity or channel qualification | Actual transmitter/firmware and USB mode evidence |
| Xbox family reported as a known gamepad | Standardized gamepad presets, shared conditioner, trusted connection verification where correctly wired | Profile/draft/performance defects apply; airship differs; first-action OFF policy may surprise | Separate USB/Bluetooth/wireless rows, live neutral startup, focus recovery, same-family dual devices, saved custom mappings |
| PlayStation family reported as a known gamepad | Same semantic gamepad path, presentation glyph options | Correct labels do not prove transport mapping or device qualification; same shared defects apply | DualShock/DualSense model and transport separately, trigger range, Share/Create/Options actions, focus and reconnect |
| Generic flight joystick | Explicit four-axis profile with absolute throttle; manual configuration | CTRL-13 assistant gap; four distinct primary axes required; no general proof for specialized controllers | Full manual setup/save/reload; actual axis count/ranges, hats and buttons, ownership recovery |
| Pistol transmitter / two- or three-axis device | No demonstrated general ground mapping contract | DEC-04; do not advertise arbitrary RC support from USB enumeration alone | Design and implement the vehicle mapping contract, then qualify actual hardware |
| “HTX” as named in the request | No separate implementation identified | Exact model/firmware/USB mode unspecified | Identify the device before making model-specific compatibility claims |

The Godot controller documentation describes SDL3-based desktop controller support and cautions that specialized devices have less coverage than ordinary gamepads. This supports treating standard gamepad mapping and raw/specialized HID qualification as separate tasks. It does not establish how every device behaves in the pinned beta. [Godot controller documentation](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).

The EdgeTX manual documents Classic as channels 1–8 on axes and 9–32 on buttons 1–24, while Advanced allows device-type and per-channel mapping choices. Consequently, a firmware label alone cannot establish channel order, button semantics or endpoint behavior. [EdgeTX USB joystick documentation](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick).

### 6.2 Qualification matrix to record

For each supported model/transport combination, retain a **build hash, engine version, OS build, controller model, firmware, transport, driver/wrapper mode, profile revision, observed metadata and redacted diagnostics**, then record the following outcomes:

| Scenario | Required evidence |
|---|---|
| Cold start at neutral/low | Correct selected owner; predictable ready/unready state; no guessed raw-radio authority |
| Start with high throttle / held switch | No unintended arm, restart or semantic action; clear recovery |
| Ten reconnect cycles | Correct generation, profile association and owner; no stale save/capture evidence |
| Focus loss and return | Pause/hold policy and fresh evidence respected in each vehicle |
| Suspend/resume | No stale device or freshness state accepted merely because a handle still exists |
| Two controllers, including same family | Unselected device cannot control flight/menu actions without its assigned role |
| USB versus Bluetooth/wireless | Identity matching and mappings recorded independently |
| Save, application restart and reload | Same calibration, inversion, actions, AUX and menu preference restored |
| Calibration with reduced/reversed travel | Preview, final profile and runtime commands agree |
| Corrupt/unwritable store and activation rejection | Honest error; old usable profile preserved; recovery path tested |
| Continuous input load | Complete-route event age and frame/latency measurements, with actual event rates |

The repository already calls for a similar native qualification record. This report extends that work with specific regression sequences; it does not imply those hardware gaps were previously hidden or that the maintainers had claimed complete qualification. [docs/plans/controller-support.md:52–100](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/controller-support.md#L52-L100)

## 7. Maintainability and optimization opportunities

### 7.1 Make device authority a shared, explicit value

The existing registry already provides the essential generation primitive. The omissions in saved drafts, AUX capture and airship routing suggest that authority is being reconstructed in several places as a loose combination of handle, profile and booleans.

Introduce a small shared connection/draft lease, with selected role, device handle, generation and profile revision, and require it at capture and commit boundaries. Separately model source readiness and activity authority. This keeps a valid profile from accidentally standing in for proof of a live source. It should be a targeted extraction following the P1 fixes, not a broad rewrite that delays them. Relevant existing seams: [app/input/controller_registry.gd:116–153](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_registry.gd#L116-L153); [app/input/controller_service.gd:175–210](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_service.gd#L175-L210); [app/ui/controller_setup.gd:3438–3483](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd#L3438-L3483).

### 7.2 Reduce responsibility concentration in Controls and AppRoot

At this snapshot, controller_setup.gd has 5,734 lines; setup_assistant.gd has 1,845; AppRoot has 4,636. Size alone is not a bug. The demonstrated failures identify useful separation boundaries: per-profile draft lifecycle, connection leases, capture state, calibration merge/conflict reporting, persistence/apply transaction, and presentation.

Extract those state machines behind existing behavioral seams, preserving the UI. Prefer immutable/reviewable draft values and structured results over shared fields and a single generic error string. CTRL-03, CTRL-06, CTRL-09, CTRL-10 and CTRL-13 give concrete acceptance criteria for the extraction. [Controls source](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controller_setup.gd); [assistant source](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/controls/setup_assistant.gd); [AppRoot source](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/app_root.gd).

### 7.3 Test contracts across consumers, not only each component's internal expectations

The current tests are useful and pass. Several blind spots are interactions between individually tested components:

- An adapter says ready while its underlying reader says unarmed.
- The assistant offers a step that its bridge rejects.
- Profile switching retains an edit, but closing from another context ignores it.
- A calibration validates alone, but its merge with prior actions fails.
- A store transaction is correct for one writer, but two writers lose updates.
- A benchmark covers Main while AppRoot owns costly routing.

Add a compact shared consumer contract suite for supported vehicles and input kinds. Test externally visible transitions and stored outcomes, rather than duplicating implementation branches or only asserting today's private fields. The existing assertions that encode the quad readiness and joystick-assistant mismatch should be revised deliberately when policy is corrected. [app/tests/test_mr_input.gd:58–66](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_mr_input.gd#L58-L66); [app/tests/test_setup_assistant_wiring.gd:197–208](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_setup_assistant_wiring.gd#L197-L208); [app/tests/test_controller_profile_creation.gd:85–102](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/test_controller_profile_creation.gd#L85-L102); [app/tests/bench_radio_events.gd:4–25](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/tests/bench_radio_events.gd#L4-L25)

### 7.4 Optimize only after retaining evidence and semantics

Use CTRL-15's counts as a clear first target: resolving immutable effective actions once per relevant state change should remove redundant work without changing command meaning. Measure allocations/copies explicitly if they become the claimed bottleneck; this audit directly counted calls and timed the route projection, not heap allocations.

Do not “optimize” by discarding release/OFF events, switching on accumulated input without validating semantics, removing profile validation, or trusting every poll as fresh raw-radio evidence. Those shortcuts could conceal the correctness failures this audit exposes. Instrument the full route and compare equivalent behavior before claiming a release performance gain.

## 8. Validation results

### 8.1 Existing repository tests

All entries below refer to final successful checked runs. Production test assertions were not changed.

| Test script | Checks | Result |
|---|---:|---|
| test_controller_conditioning.gd | 57 | Passed |
| test_controller_profile.gd | 74 | Passed |
| test_controller_actions.gd | 24 | Passed after correcting fixture translation registration |
| test_rc_input.gd | 41 | Passed |
| test_rc_calibration.gd | 39 | Passed |
| test_jeti_runtime.gd | 105 | Passed |
| test_jeti_identity.gd | 56 | Passed |
| test_controller_registry.gd | 27 | Passed |
| test_radio_menu.gd | 180 | Passed |
| test_controller_store.gd | 47 | Passed |
| test_controller_profile_hardening.gd | 94 | Passed |
| test_controller_diagnostics.gd | 49 | Passed |
| test_input_report_buttons.gd | 15 | Passed |
| test_controller_auto_defaults.gd | 37 | Passed |
| **Total: 14 scripts** | **845** | **All final runs passed** |

The controller-actions script reports a textual completion marker; its 24 checks were counted from the explicit successful check lines. These tests ran with unchanged production scripts in a minimal fixture, not the full application project; configuration and generated-metadata exceptions are disclosed below. Their success establishes the tested baseline and makes the missing interaction coverage more specific; it does not negate the new reproductions.

### 8.2 Targeted diagnostic probes

| Probe group | Executed evidence | Interpretation |
|---|---|---|
| Calibration core | 16 checks, zero failed | Demonstrates AUX loss/warnings, conflict merge behavior, sample bias, range-kind retention and verification policy |
| Calibration UI | 5 checks, zero failed | Demonstrates Mode 1 view mismatch and joystick calibration refusal |
| Profile/setup | 12 checks, zero failed | Demonstrates wrong association, hidden dirty draft and conditional matching behavior |
| Capture | 6 checks, zero failed | Demonstrates AUX lease omission and endpoint motion interruption |
| Concurrent store | Two writer processes and one final-reader process, all checked | Both writes succeed; one acknowledged profile is absent afterward |
| Routing | Three checked diagnostic scripts | Prints quad adapter/FC authority mismatch, airship pause rejection and gamepad readiness behavior |
| Event hot path | Checked operation-count run and isolated timing run | Counts calls, records generic identity map size and seven paired timing rounds |

A passing **diagnostic** probe means it observed the adverse behavior it was designed to expose. These are not passing regression tests for the intended fixed behavior. Convert the repros into product regressions that assert the corrected contract before merging repairs.

### 8.3 Integrity and fixture boundaries

An independent integrity review checked every original report/log pair against its recorded SHA-256 and byte length. The working evidence set contains 44 pairs: 35 passing runs and nine earlier failed attempts. The accompanying archive curates final evidence and documents which earlier attempts were excluded from conclusions; those early fixture failures are not counted as product bugs.

Copied production GDScript/shader bodies match the audited source except the disclosed routing collision-world stub. All 13 extracted AppRoot method bodies in the performance projection were independently verified verbatim. Minimal project configurations, generated script UIDs and import metadata differ, as expected for disposable projects. The evidence manifest distinguishes these from source changes.

No physical device, OS-specific export or rendered workflow is certified by these checks.

## 9. Remediation sequence for maintainers

These should be small, reviewable changes with focused regression coverage. The table groups related work; it is not a recommendation for one large combined pull request.

| Order | Change boundary | Findings | Completion criterion |
|---|---|---|---|
| 1 | Raw-source authority in quad | CTRL-01 | Reader, adapter and flight controller agree on readiness and fresh OFF→ON requirements |
| 1 | Draft/capture identity at commit | CTRL-02, CTRL-06 | Reused handles cannot rewrite associations or accept replacement-device input |
| 2 | Dirty draft lifecycle | CTRL-03 | Every retained edit is explicitly saved, retained or discarded |
| 2 | Airship input integration and pause recovery | CTRL-04, CTRL-05 | Selected owner/profile honored; safe ordinary pause/resume works |
| 2 | Calibration result and conflict model | CTRL-09, CTRL-10 | Every mapping change/conflict is visible and measured work remains reviewable |
| 2 | Profile semantic repair and migration | CTRL-12 | Signed commands repaired without making healthy stored profiles unavailable |
| 3 | Calibration sample quality | CTRL-11 | Stable rest/endpoints produce defined idle/center output under documented tolerances |
| 3 | Assistant and capture UX | CTRL-07, CTRL-08, CTRL-13 | Each offered path is executable and completes without misleading input guidance |
| 3 | Cross-process persistence | CTRL-14 | Both successful concurrent updates survive, or a conflict is explicitly retried/reported |
| 4 | Binding resolution cache and full-route benchmark | CTRL-15 | Equivalent semantics with measured reduction in complete-route cost |

**Release decisions.** Until CTRL-01 and CTRL-02 are corrected and their regressions pass, avoid treating the affected raw-radio quad and stale-setup-save paths as qualified. Experimental airship scope can affect scheduling, but should be stated explicitly in user-facing support information. Hardware qualification should follow the fixes on each intended target build rather than being inferred from these Linux synthetic results.

**Review cautions.** A validator tightening needs migration; a cache needs invalidation; a file lock needs transaction scope; a draft warning needs correct Save semantics; an input filter needs release/OFF preservation. These dependencies are part of the fixes, not optional later cleanup.

## 10. What was examined and not established as a defect

Several tempting broad claims were rejected:

- **“JETI detection is just a name match.”** False for the implemented strict family helper; identity corroboration and rejection paths exist.
- **“Reversed throttle calibration is broken.”** No such general failure was established. The direction/endpoints logic and existing orientation cases support both directions.
- **“Radio input needs the same expo/deadzone as gamepads.”** That is a product choice, and current radio shaping avoidance is intentional.
- **“Cancelling calibration saves partial values.”** No general cancellation defect was reproduced; Home calibration has focus/disconnect/generation guards.
- **“Any corrupt profile store silently becomes a new install.”** The loader reports invalid storage and validates rollback recovery. This audit did not establish that broad failure.
- **“All profile saves are nontransactional.”** Single-writer temporary validation, staged rollback and recovery exist. CTRL-14 is specifically the cross-process gap.
- **“All unknown joysticks should automatically fly.”** The unconfigured state is deliberate and preferable to trusting guessed mappings.
- **“Airship/ground findings prove the managed airplane and helicopter routes fail identically.”** The relevant adapters and ownership paths differ; conclusions remain route-specific.
- **“Every first ignored action is a bug.”** The initial OFF gate is explicitly tested and needs a policy decision for trusted gamepads.
- **“Passing unit tests certify physical Xbox, PlayStation, JETI or EdgeTX compatibility.”** They do not; the repository's own qualification plan makes this distinction.

Supporting code and policy: [app/input/jeti_radio.gd:15–19](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/jeti_radio.gd#L15-L19); [app/input/rc_calibration.gd:195–210](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/rc_calibration.gd#L195-L210); [app/input/controller_profile.gd:568–575](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile.gd#L568-L575); [app/ui/radio_calibration_setup.gd:73–109](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/ui/radio_calibration_setup.gd#L73-L109); [app/input/controller_profile_store.gd:26–41](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L26-L41); [app/input/controller_profile_store.gd:240–269](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L240-L269); [app/input/controller_profile_store.gd:314–380](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/input/controller_profile_store.gd#L314-L380); [docs/plans/controller-support.md:41–100](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/controller-support.md#L41-L100).

## Appendix A — Evidence archive map

All paths below are relative to the accompanying archive root. Original log/report contents are retained, including original host paths in command metadata; portable instructions do not depend on those paths.

| Path | Contents |
|---|---|
| README.md | Portable setup, isolation, commands and interpretation |
| run_probes.py | Portable launcher for selected final probes and optional baseline tests |
| evidence/VERIFICATION.md | Independent integrity review and fixture exceptions |
| evidence/verification_summary.json | Per-source and per-run verification details |
| evidence/calibration/project/ | Exact production dependency copies plus two targeted probes |
| evidence/calibration/runs/calibration-range-kind-oc1xiz39/ | Final 16-check calibration run |
| evidence/calibration/runs/calibration-ui-audit-s8fv9m38/ | Final 5-check UI run |
| evidence/profiles/repro/ | Production input/UI dependencies and profile/capture/race probes |
| evidence/profiles/PORTABLE_REPRO.md | Profile-specific commands and concurrency protocol |
| evidence/profiles/run_concurrent_portable.py | Portable two-writer scheduler |
| evidence/profiles/checks/ | Final profile/capture/race reports and logs |
| evidence/routing/probe/ | Adapter/controller/session probes and disclosed collision stub |
| evidence/routing/runs/ | Three final routing diagnostics |
| evidence/parent/project/ | 14 existing tests and actual-method performance projection |
| evidence/parent/shell_projection_manifest.json | Extracted AppRoot method identities and source lines |
| evidence/parent/runs/ | Final baseline tests, hot-path counts and isolated timing |
| SHA256SUMS.txt | Hashes of the delivered archive contents |
| LICENSE.OpenRC.txt | Source repository's MIT license for bundled project code |

The engine binary and the full repository/assets are not bundled. Use the audited repository checkout's checked runner and its pinned engine. Original author notes are retained as supporting analysis; this report is the consolidated priority and scope assessment.

## Appendix B — External primary references

- [Godot controllers, gamepads and joysticks](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html): desktop backend context and specialized-controller qualification limits. Retrieved 14 November 2026; documentation labels may advance independently of the pinned engine.
- [Godot Input API, latest documentation](https://docs.godotengine.org/en/latest/classes/class_input.html): metadata and known-mapping API context. This is explicitly unstable documentation, not proof of a particular physical device or every pinned-beta detail.
- [EdgeTX USB joystick documentation](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick): Classic channel layout and Advanced descriptor/channel options. Retrieved 14 November 2026.
- [OpenRC controller support plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/controller-support.md) and [JETI support plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/docs/plans/jeti-support.md): implemented versus pending qualification.
- Every inline source reference in this report points to the audited commit, so future main changes cannot silently change the cited evidence.

