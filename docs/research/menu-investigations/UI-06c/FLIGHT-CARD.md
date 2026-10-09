# UI-06c — manual runway flight card

**Status: ready for the owner; no physical pilot trial is recorded here.** The exported smoke is a software check. Complete one card per pilot session and keep unsuccessful attempts.

## Build and setup

| Item | Record |
| --- | --- |
| Date and pilot | |
| Export build / tag | |
| Export executable SHA-256 | |
| Git commit and dirty flag in the export | |
| Stik aircraft input SHA-256 | |
| Field input SHA-256 | |
| Radio, firmware and USB joystick mode (or keyboard) | |
| Radio model/profile name and profile/input-file SHA-256 | |
| OS, display/GPU, screen resolution and scale | |
| Camera mode, auto-zoom and shadow mode | |
| Trace, screen recording, radio video and frame-time file paths | |

Copy hashes from the exported smoke report only when the pilot flies that exact executable and aircraft file. Otherwise hash the binary and aircraft file actually flown; do not carry hashes over from a different build. Record the actual controller/profile used by the pilot even if the smoke harness used keyboard events.

## Run and observations

Select the Ugly Stik, default field and **Start: runway (experimental)**. Begin with hands off at idle. Use the radio that will be evaluated; leave scenery and camera settings recorded as found. Save the trace and any screen/radio video for every attempt, including resets and unsuccessful landings.

After Fly starts the flight, press **T once** to start a trace. Fly or taxi, then press **T again** to stop and save it under `user://traces/trace-*.csv`. Record the saved file path with the attempt. Keep one trace per attempt where possible; each file carries the launch selection and recording-start snapshot. Do not use a trace from an earlier flight to describe a later build.

| Phase | Attempt / trace path | What happened |
| --- | --- | --- |
| Idle hold | | Does the airplane remain settled at idle? |
| Straight taxi | | Does throttle and steering response feel understandable? |
| Takeoff | | Where did it lift off? Any yaw, bounce or loss of control? |
| Circuit | | Was bank, pitch and height easy to judge? |
| Approach | | Could you control sink and alignment? |
| Wheel landing and rollout | | Which wheels touched first? Was rollout stable? |
| Restart after a problem | | Did R and Pause → Restart return to the selected runway start? |

Compare control response with a real Stik and rate each axis from **−2 (sluggish)** through **0 (comparable)** to **+2 (twitchy)**. If no real-aircraft comparison is available, write “not rated” and describe the observed response.

| Control axis | Rating −2…+2 / notes |
| --- | --- |
| Roll / aileron | |
| Pitch / elevator | |
| Yaw / rudder, including taxi steering | |
| Throttle | |

Rate readability from **1 (hard to judge)** to **5 (clear)**, or leave a descriptive note. Record setup clarity and measured frame time as notes rather than handling ratings.

| Observation | Readability 1–5 / notes |
| --- | --- |
| Airplane attitude | |
| Height and distance | |
| Screen resolution, scale and camera mode | |
| Radio setup and throttle arming | |
| Frame time on the target machine (include the measurement file) | |

Describe the largest blocker with the maneuver, speed if known, control input, and resulting response. Do not change physics coefficients during this session; preserve the trace and compare evidence before choosing a repair.

## Evidence follow-up

- Attach the [pilot feedback form](../../../../.github/ISSUE_TEMPLATE/pilot_feedback.md) or copy its handling, visibility and controller notes into the session report.
- Find software and evidence entry points in [docs/TOOLS.md — flight and physics experiments](../../../TOOLS.md#flight-and-physics-experiments). Run the exact G1b1 [offline range-audit CLI workflow](../../../../research/propulsion/range-audit/README.md) on the flown trace, the exact Stik aircraft file, the number of physics steps excluding the initial row, and `--assume-still-air`; retain its JSON report beside the trace. State the previous-state reconstruction limit: the audit uses previous-row velocity with current-row RPM and does not reveal internal RK-stage queries or validate propeller data.
- Compare circuit presentation with the [E3c2b review kit](../../ground-contact/E3c2b/index.html). It is a recorded-state render reference, not a replay or physical acceptance.
- Record the largest reproducible pilot blocker and keep Gate 2, landing realism and PT2 conclusions separate from the exported software smoke.
