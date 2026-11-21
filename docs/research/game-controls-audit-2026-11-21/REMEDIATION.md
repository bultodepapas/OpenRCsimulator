# Game controls audit — remediation plan

**Source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
These are proposed, independently reviewable changes; this document does not
authorize or claim an implementation. The [audit](AUDIT.md) owns the finding
scope and earlier-ID reconciliation. Use [verification](VERIFICATION.md) for
the audit evidence and [qualification](QUALIFICATION.md) for the remaining
device, platform and package gates.

Use the existing track IDs below when scheduling the work; GCA identifiers
refer to this audit, not new repository-wide track prefixes. Coordinate shared
input, shell and UI changes with their owners. Preserve fixed-wing, helicopter,
quad, airship and ground activity contracts independently.

## Repair order and acceptance

### 1. Dispatch the quad's admitted Pause bindings — GCA-01, P2

**Owners:** DR-14/DR-16, UI-15-GP-01 and shared controller-action owners.
**Boundary:** Controls action admission through the multirotor activity; this
does not reopen CTRL-01's raw-throttle readiness correction.

Route the admitted Pause action at the activity boundary using the existing
binding and edge semantics. Support the accepted radio button, learned axis and
custom key forms, or explicitly refuse a form in the applicable Controls flow
with an actionable explanation. Keep P/Escape and the established gamepad
button route. Do not assume that a valid saved binding is already dispatched.

Acceptance on synthetic input and actual activity/session boundaries:

- Validate and save an admitted radio button, learned axis and custom key;
  each supported form pauses a running quad through the real event route.
  Unsupported forms are refused before a misleading successful Save.
- Raw switches require the applicable OFF-before-ON evidence; held inputs,
  repeat events, rebinds, focus changes and reconnects do not create a new
  press. Axis thresholds and hysteresis match the shared action contract.
- Only the selected source and current connection generation have authority;
  foreign devices and conflicting AUX assignments do not trigger Pause.
  Continue remains explicit and respects the activity's disarm and throttle
  policy. P/Escape and existing gamepad mappings still work.

### 2. Clear and rebuild airship native menu ownership — GCA-02, P2

**Owners:** BL-10/BL-12, UI-12-GP-01 and F3-GP-02.
**Boundary:** registry/UI-role notification through AppRoot and the airship's
global native `InputMap`; flight-axis selection is separate.

Make the activity refresh the native GUI mapping from the currently authorized
menu role and profile, clearing old events whenever that role is absent or
ineligible. Retain keyboard recovery and the separately documented scope of
radio menu navigation.

Acceptance:

- Lose a selected menu pad, reuse its numeric handle for another device, and
  select a different pad. The previous ID's Accept, Back and navigation events
  no longer match the active native map; only the current eligible role does.
- Exercise changed bindings and profile eligibility, keyboard-only selection,
  focus and activity exit back to Home. The correct map is restored without
  changing the flight role or granting the replacement device menu authority.
- Check the real callback chain and native `InputMap` as well as focusable
  rendered HUD controls. Keep synthetic event checks separate from physical
  controller and platform qualification.

### 3. Retry an unresolved airship profile on Continue — GCA-03, P2

**Owners:** BL-10, F3-GP-02 and D6-GP-02.
**Boundary:** an uncached profile lookup refused temporarily, such as store
lease contention, followed by explicit recovery on the same selected connection.
Already cached successful profiles are not this failure case.

At an explicit recovery boundary, resolve an unresolved profile again and
recheck the selected role, connection generation and profile validity before
activation. Preserve the fail-closed state on repeated refusal; never infer a
gamepad default from an empty result. Surface a useful storage or profile error
when available, without adding a store read to every input event or tick.

Acceptance:

- Hold the V2 lease with a separate store instance, connect a fresh uncached
  selected source, and verify that it remains unconfigured and unarmed. Release
  the lease and press Continue: the same connection can recover its resolved
  profile and proceed only through its own readiness gates and explicit Continue.
  Releasing the lease alone never resumes the session. Until repaired, the player
  workaround is to return Home, review/reselect and save in Controls, then launch
  again; the airship HUD does not itself provide a Controls entry.
- A still-busy, corrupt, ambiguous or genuinely unconfigured source stays held;
  the message identifies the available recovery action. A changed selection,
  disconnected device or reused generation cannot apply a stale result.
- Check verified gamepad readiness and calibrated radio LOW evidence separately;
  retain the successful cached-profile path and existing calibration behavior.

### 4. Protect legacy calibration read/modify/write — GCA-04, P2

**Owners:** D6-GP-02 with direct fixed-wing/helicopter calibration and AUX
persistence owners. **Boundary:** legacy `rc_calibration.cfg` writers and readers;
the repaired V2-to-V2 CTRL-14 transaction remains separate.

Coordinate calibration and smoke-binding updates under the same file-specific
cross-process authority over the full read/merge/publication boundary. Define a
validated staged publication and failure/rollback policy that preserves the
legacy format, unrelated device sections, existing identity checks and migration
readers. A successful response must retain the acknowledged update; contention
or a failed publication must be reported. Do not infer power-loss durability
from a successful rename.

Acceptance:

- Reproduce the lost-update schedule using two processes and a barrier inserted
  only into a disposable source copy; identify the copy and its scheduling diff.
  On the repaired candidate, distinct-device updates either both survive or an
  explicit contention/retry result is returned. Also cover competing same-device
  edits and calibration-versus-smoke updates, including an existing seed entry.
- Exercise readers during publication, invalid/unreadable input, failed write,
  rollback and interrupted-lock recovery. Retain the last usable data and report
  failures accurately; never overwrite an unreadable source as if it were empty.
  Test crash and power-loss behavior separately before making durability claims.
- Cover both direct fixed-wing and helicopter callers and managed legacy import;
  keep the V2 transaction and its existing concurrency regressions intact.

### 5. Align accepted ranges and normalization — GCA-05, P3

**Owners:** D6-GP-02/D6-GP-03. **Boundary:** externally authored, imported or
damaged profiles with spans below the normalization denominator floor. The
ordinary wizard requires at least `0.5` total sweep and is not shown to create
the tiny witness.

Choose an explicit, justified minimum span with actionable activation errors,
or revise normalization under a documented numerical contract. Apply the rule
consistently to absolute and each signed side. Preserve existing files and keep
affected profiles available for review and repair without silently activating
incorrect mappings or making unrelated profiles inaccessible.

Acceptance:

- Test below, at and above the chosen boundary for absolute throttle and
  off-center signed channels, normal and inverted. Declared endpoints either
  produce the documented full/idle commands or activation is refused with a
  field-specific explanation. Include V2 save/reload and legacy import.
- Through the real reader, test verified gamepad and radio LOW/arming behavior;
  a bad mapping must not become ready with a misleading idle. Preserve normal
  calibrated ranges, existing transmitter shaping and previously saved data.

## Separate support and qualification work

These items are not added to the five-defect count. Their owners should first
establish the applicable contract and evidence rather than assuming that a
software fixture represents a physical device.

| ID | Owner and next step | Closure boundary |
| --- | --- | --- |
| GCA-G1 | F3-GP-02 with DR, BL and RCV: investigate long processing gaps without focus/disconnect events using a synthetic clock at each real activity tick boundary. | Demonstrate the ordering of gap detection and the first post-gap tick; choose a hold/recovery policy per activity, then qualify native suspend/resume separately. Do not attach incompatible sessions to the service merely to reuse its watchdog. |
| GCA-G2 | UI-12/15-GP and DR/BL/RCV: document a per-activity matrix for Home versus direct launch, profile resolution, radio Pause, verified radio menus and keyboard recovery. | Check each supported route and mark unsupported combinations explicitly; one fixed-wing radio-menu journey does not establish activity-wide navigation. |
| GCA-G3 | DR-14/DR-16 with controller and UI owners: reconcile general no-takeover wording with the existing quad fallback. | Preserve deliberate selection of another connected controller, including a radio or unknown device, while the session is held and arm continuity is invalidated. Identify the new source before explicit Continue. An already-armed simulated motor disarms on the first resumed tick; the paused stored frame can still report `MOTOR_ARMED`. Do not describe the fallback as automatic flight resumption or a new defect. |
| GCA-G4 | F1/F4/F6-GP, UI and DT/PT: carry physical-device, accessibility, native-platform and export work into the [qualification matrix](QUALIFICATION.md). | Record actual build, engine, OS, device model/firmware, transport, profile and outcome. USB disconnect and transmitter-off RF behavior are separate; unchanged receiver axes do not prove RF status. |

## Opportunities after correctness

| ID | Owner and bounded candidate | Evidence required before adoption |
| --- | --- | --- |
| GCA-O1 | D6-GP-02/F3-GP-02 with activity owners: evaluate reuse of a coherent per-device tick snapshot across readiness, primary axes and AUX. | The audit's axis/button callback counts are not a CPU, physical-polling or latency measurement. First profile the complete native route; then compare identical input tapes, freshness, held-button and OFF/release behavior, invalid samples, allocations and input-to-display latency. Preserve the existing per-event cache and store-refresh optimization. |
| GCA-O2 | UI-15-UX/D6-UX with D6-GP owners: extract one draft, capture or connection-lease responsibility at a time behind the existing Controls facade. | Preserve Save/Cancel, dirty drafts, validation, connection generation, capture cancellation, accessibility and existing callers; do not use file size alone to justify a rewrite. |
| GCA-O3 | Shared action owners with DR/BL/HELI/RCV: reuse small cross-consumer cases for admitted action → activation → OFF/press/release → activity response → recovery. | Test each applicable activity and explicitly label unsupported bindings; retain each vehicle's distinct arming, held-input and resume policy. |

## Verification and release boundary

Each repair needs focused checks and affected consumer tests on a stable
candidate, followed by the repository's applicable integration and required-CI
gates. Verify actual engine diagnostics as well as process status. Native device,
rendered UI, accessibility and exported-package evidence remain distinct from
synthetic tests; see [qualification](QUALIFICATION.md). For changes to device
conditioning or mappings, check the input and live-flight boundaries:
post-conditioning replay alone cannot retest those stages or pilot adaptation.
Record any unrun gates rather than treating this plan or an audit probe as a
passing fix.
