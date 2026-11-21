# Game controls qualification matrix — 21 November 2026

This is the follow-through matrix for the [audit](AUDIT.md), pinned to source
commit `57abea025f62b20233ca281d58d2acbee4ab8b8e`. It is a qualification plan,
not a record of new physical tests. The five GCA findings and four GCA-G gaps
retain the scope and distinctions in that report. The existing
[controller-support plan](../../plans/controller-support.md) owns the hardware
procedure, release gates and track IDs; this matrix makes the affected activity
and recovery boundaries explicit.

## Evidence status

| Evidence | Status and meaning |
| --- | --- |
| Source review | The audit describes inspected paths at the pinned commit. This does not establish behavior on a device or a later build. |
| Synthetic and headless software | Consult [VERIFICATION](VERIFICATION.md) and [verification.json](verification.json) for the actual completed checks, diagnostics, markers, engine errors and source identities. A diagnostic that observes an adverse baseline is not a passing repair regression. |
| Physical controllers and keyboard on every OS/transport below | **UNTESTED** for this audit. Each exact device, mode, firmware, OS and transport combination needs its own result. |
| Rendered native interaction, target graphics and accessibility | **UNTESTED** for this audit, including visible focus, screen-reader output and controller-only journeys. Headless InputMap matching is not a rendered HUD activation. |
| Exported packages, actual OS sleep/resume, physical RF loss and pilot acceptance | **UNTESTED** for this audit. Source and synthetic results do not qualify these boundaries. |
| Complete required CI at an eventual repair commit | **UNTESTED** for this audit. Follow the repository's required checks; focused results do not replace them. |

Every physical status in the tables below starts **UNTESTED**. A future result
applies only to the named build and exact row exercised. If a device or transport
is unavailable, keep its row open; do not infer it from a related row. A device
without a stated transport capability is not assumed to support that transport.

## Physical device and platform matrix

For every applicable cell, test both the native development build and the
exported package as separate subrows. Record the exact OS build and native
architecture. An exported package, a wrapper, and a different transport do not
inherit a source-build or another transport's result.

| Input or isolation case | Windows | Linux | macOS |
| --- | --- | --- | --- |
| Physical keyboard and mouse | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| Xbox Wireless Controller, identified generation, USB | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| The same Xbox model, Bluetooth where supported | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| DualSense, identified revision, USB | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| The same DualSense revision, Bluetooth where supported | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| EdgeTX/OpenTX transmitter, identified model and USB joystick mode | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| JETI transmitter, identified model and USB joystick mode | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| Other configured raw joystick or third-party controller, each reported mode | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| Two recognized gamepads, including same-family or duplicate descriptors | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| Controller and radio connected together, separate flight and menu roles | **UNTESTED** | **UNTESTED** | **UNTESTED** |
| Steam-emulated controller or another already available wrapper, by version and mode | **UNTESTED** | **UNTESTED** | **UNTESTED** |

The current Windows primary gate calls for identified Xbox and DualSense USB
and applicable Bluetooth rows, two-device isolation, and the package procedure;
the [plan's hardware matrix and physical procedure](../../plans/controller-support.md#hardware-matrix)
also specify the RC transmitter and cross-platform work. A brand or an SDL
classification alone is not evidence of channel order, trigger independence,
firmware behavior or compatibility. An unenumerated physical control stays
unknown. Record exact controller revision, transmitter firmware, driver or
wrapper, available metadata and observed axes/buttons; keep serials redacted or
locally associated.

## Activity, role and route matrix

Use each applicable physical device/OS row above for the entries selected below.
The three input columns describe the **scenario to qualify**, not an assertion
that every action or menu is supported. Every cell is **UNTESTED** for physical,
rendered, native and exported qualification in this audit. The car has a
distinct fixed driving scheme; a raw radio is an isolation case, not an assumed
car driving source. Verified radio GUI navigation and radio Pause are separate
capabilities.

| Activity and route | Keyboard flight/drive and menu | Selected gamepad flight/drive and menu | Configured radio or raw joystick flight and menu |
| --- | --- | --- | --- |
| Fixed-wing: Home launch and direct/technical launch | **UNTESTED** — launch, Pause, resume and recovery | **UNTESTED** — mode/rate or trigger profile, separate menu ownership | **UNTESTED** — measured channels, LOW evidence, supported verified-radio menus and direct legacy route |
| Helicopter: Home launch and direct/technical launch | **UNTESTED** — collective, arm/hold and explicit Continue | **UNTESTED** — collective, arm/hold and menu role | **UNTESTED** — calibrated collective, LOW/arm evidence and supported menu role |
| Experimental FPV quad: Home and `--multirotor` | **UNTESTED** — arm, Pause and recovery | **UNTESTED** — flight source, remapped Pause and selected menu pad | **UNTESTED** — arm OFF/ON, Pause button/axis and supported menu route; GCA-01 and GCA-G2 apply |
| Experimental airship: Home and `--airship` | **UNTESTED** — virtual commands reset on hold and explicit resume | **UNTESTED** — managed profile, current menu owner and low/yaw resume gates; GCA-02/03 apply | **UNTESTED** — managed profile and radio Pause; record direct route's separate legacy behavior under GCA-G2 |
| Ground vehicle: Home and direct vehicle route | **UNTESTED** — driving, Garage and neutral recovery | **UNTESTED** — local selected pad, steering/triggers/reverse and neutral recovery | **UNTESTED** — verify that an unselected or raw radio does not acquire car driving or menu authority |

For the airship, a normal hold resets virtual keyboard and rate-throttle
commands, while physical absolute throttle must be LOW and yaw centered before
Resume. Helicopter collective and quad arm policy remain their own contracts.
For the car, release the driving keys or the selected pad's stick, triggers and
reverse control before a new drive command. Do not impose one vehicle's neutral
policy on all others. Direct airship entry currently differs from its managed
Home route; record what was actually resolved rather than claiming V2 or menu
parity without evidence. See the [airship plan](../../plans/rc-airship.md),
[quad plan](../../plans/drone-racing.md) and
[ground-vehicle plan](../../plans/rc-monster-truck.md).

## Recovery and regression matrix

The checks below are acceptance targets for a future candidate, not claims that
the baseline already meets them. Use isolated profiles, keep the source and
session identity fixed, and record each connection or profile change the case
requires. Repeat across applicable activity/role/route combinations; record
unsupported combinations explicitly.

| Case and owning work | Trigger and required observation |
| --- | --- |
| **Pause and action dispatch — GCA-01; DR-14/DR-16, UI-15-GP-01** | Save a valid radio Pause button, then a learned unused-axis Pause; establish OFF followed by ON during quad flight. The offered binding must produce the documented hold, or setup must clearly refuse the unsupported form. Check another device, held input across menus, AUX conflicts, P/Escape and explicit Continue. Exercise the full learned-axis edge sequence, not validation alone. |
| **Menu ownership and reused ID — GCA-02; BL-10/BL-12, UI-12-GP-01, F3-GP-02** | In managed airship, select menu pad A, disconnect it, and reuse its numeric ID for a different device. Assert that A's native menu mappings are removed and the replacement cannot activate a focused HUD control without the UI role. Select pad B and verify only its eligible mapping; test changed bindings, keyboard recovery and return Home. Check actual rendered press/release separately from synthetic InputMap matching. |
| **Busy profile store and retry — GCA-03; BL-10, F3-GP-02, D6-GP-02** | Use a fresh selected connection with no cached profile. Hold the isolated V2 store lease from another instance, attempt airship resolution and confirm the source remains unready and held. Release the lease; the same current generation should be re-resolved at an explicit recovery action, without guessing a profile or resuming automatically. Repeat with the lock still held and with an identity change; report the actual refusal. For the baseline, the player can return Home, open Controls and relaunch; a direct method-level reapply is only a diagnostic control. |
| **Legacy persistence — GCA-04; D6-GP-02 and direct fixed-wing/helicopter owners** | In an isolated legacy file, coordinate two processes writing different device sections and a calibration-versus-smoke pair. A success must preserve both acknowledged changes or clearly report contention. Exercise failed save, read error, cancellation and an interrupted replacement separately. V2-to-V2 locking is a different boundary; do not infer power-loss durability from an interleaving test. |
| **Profile endpoint semantics — GCA-05; D6-GP-02/03** | Using isolated externally authored profiles, test spans below, at and above the eventual documented minimum, both inversion states, and off-center signed channels. Check validation, storage/reload, activation and actual reader output. Rejection must leave the prior working profile repairable; valid declared LOW/FULL endpoints must match the agreed normalization contract. Also record real device endpoints; do not treat an extreme synthetic span as a physical-device incident. |
| **Focus, disconnect and same-ID replacement — F3-GP-02/03, F4-GP-01** | At idle and with active controls, lose focus or disconnect the selected source; include an event while a modal or capture owns input. Check the activity's held state, invalidated evidence, current role/generation, no unauthorized command and explicit recovery. Reconnect the same hardware and replace it with a different device on the same handle; a numeric ID alone is not continuity proof. Repeat the primary physical fault cycles required by the controller-support plan. |
| **Long processing gap without another event — GCA-G1; F3-GP-02 and each activity owner** | In a deterministic software fixture, advance a controllable clock past the existing watchdog interval without sending focus or disconnect notifications. Observe the first post-gap physics tick and whether a hold precedes it for each applicable activity, including fixed-wing/helicopter ordering. Then test actual OS sleep/resume separately and record which focus, connection and clock events the platform delivered. Do not infer the native result from the synthetic gap or attach incompatible sessions to the service. |
| **Capture and draft ownership — CTRL-02/06/07 regression boundary; UI-15-GP-01, D6-GP-02** | Start remap, Learn axis, AUX or calibration capture with a held control; send a foreign event, disconnect or replace the selected connection, and cancel. Verify lease/generation checks, release consumption, retained draft and last valid stored profile. Retry with the intended control and verify no captured press leaks into a menu or flight action. These cases preserve prior repairs rather than reopening the historical IDs. |
| **LOW throttle and arm continuity — CTRL-01 regression boundary; F3-GP-02, DR-14, BL-10, helicopter and fixed-wing owners** | For a configured raw radio, require fresh LOW evidence after selection, focus loss or reconnect; a contradictory HIGH reading must not carry an old LOW through readiness. Check the quad's fresh arm OFF-to-ON at LOW and the airship's LOW/yaw Resume gate. For a recognized gamepad, use its actual verified readiness and activity-specific virtual/absolute throttle policy; do not invent a general gamepad neutral dwell. Verify rate throttle, AUX and recovery on the first accepted tick. |
| **Fallback policy — GCA-G3; DR-14 and general controller documentation** | Disconnect the quad flight source with another connected eligible device present. Record the selected fallback, source generation, menu text, held session and arm-continuity invalidation. The accepted quad policy permits an automatic choice of another controller, including a radio or unconfigured/unknown device; it does not auto-resume. An armed stored paused frame can remain armed until the first resumed simulation tick disarms it. Reconcile broader no-takeover wording; do not report the accepted choice itself as a new defect. |
| **Radio menu proof and activity boundaries — GCA-G2/G4; UI-12-GP-02** | Verify calibrated roll/pitch, distinct Accept/Back/Pause and the same connection's fresh center/OFF evidence. Test supported Home and fixed-wing journeys, popups, focus and reconnect; record whether quad, airship or car offer that particular menu route. Keyboard, mouse or a separate eligible gamepad remains available for initial verification, text and native dialogs. A passed fixed-wing journey does not qualify other activities. |

USB unplug, Bluetooth loss and transmitter-off RF loss are distinct events. A
receiver can remain enumerated while its transmitter is off; unchanged samples
alone do not establish either a healthy or failed RF link. Record the receiver's
observed failsafe and mark RF loss unobservable if the route exposes no
discriminator. No new RF-loss detector is presumed by this audit.

## Evidence to retain for each attempted row

1. Identify the exact source commit and dirty state, application/package hash,
   engine version **and executable hash**, native OS build/architecture,
   renderer, and actual selected simulation backend. Record whether the run is
   a source build, exported package, headless synthetic test or rendered native
   session; a requested native backend is not proof of the backend used.
2. Record the device model/revision, firmware, transport, driver or wrapper and
   its version, observed connection metadata, profile revision and relevant
   mappings. Preserve private identity evidence locally or redact it while
   retaining a way to distinguish the tested connections and generations.
3. Capture the selected flight and menu roles, start mode, activity, launch
   route, readiness, throttle/arm state and relevant mapping before and after
   each trigger. Include event order, timestamps, accepted tick boundary,
   visible hold/recovery message and the explicit Continue or other recovery
   action. For same-ID replacement, retain proof that the device identity or
   connection generation changed, not just that the number matched.
4. Retain the checked command or package launch, exit/completion marker and
   diagnostics. Inspect engine/script errors and warnings as well as exit
   status; list skipped or incomplete cases. Link concise receipts and hashes
   rather than implying that a partial capture was a completed run.
5. For rendered cases, record output, logical/viewport and actual drawable
   dimensions and the focus/interaction observed; follow the repository's
   display priorities and Apple Retina rules. Record accessibility observations
   separately from visual focus. For F6 timing work, use the existing
   [controller plan](../../plans/controller-support.md#physical-acceptance-procedure),
   its device and measurement protocol and the actual uncertainty; callback
   counts are not USB poll rate, latency or application FPS. This matrix adds no
   new performance threshold.
6. Mark each exact row **PASS**, **LIMITED**, **FAIL** or **UNTESTED**, with a
   reason and artifact reference. A missing device, platform, result, event
   trace, native package or completed diagnostic remains **UNTESTED**. Record
   a failed or refused case as observed; do not count it as a passing repair.

Input conditioning, device evidence and pilot adaptation need their own live
input/flight boundary checks: a replay of already conditioned commands cannot
retest them. Preserve prior tapes and follow the
[flight logging guide](../../FLIGHT-LOGGING.md); do not re-record golden flights
to conceal an input regression. Finish with the affected consumer checks and
required CI at the actual integrated repair commit, then qualify each claimed
native package and physical configuration independently.
