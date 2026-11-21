# OPEN RC SIMULATOR — game controls audit

**Date:** 21 November 2026. **Source:** `bultodepapas/OpenRCsimulator`, current
`main` fetched at the beginning of the review, commit
`57abea025f62b20233ca281d58d2acbee4ab8b8e`.
**Branch:** `audit/game-controls-2026-11-21`.
**Engine:** official `4.8.beta2.official.cafc17a19`, Linux x86-64 executable verified
against the repository's SHA-512 pin.

## 1. Engineering assessment

The shared controls implementation has substantial protection already in place:
connection generations, explicit ownership, checked V2 profiles, transactional
V2 persistence, calibration stability checks, radio throttle evidence, separate
gamepad readiness, and preserved setup drafts. The remaining defects found here
are concentrated in **activity integration and legacy persistence**, plus a
narrow validation/normalization inconsistency.

Five bounded defects are documented below. Four merit P2 correction; the
externally authored tiny-range case is P3 hardening because ordinary calibration
rejects that range. The audit found no reproduced P0 or P1 defect. This is a
statement about this bounded review, not certification of the complete controls
system. Evidence levels and actual checked results are retained in
[VERIFICATION](VERIFICATION.md) and [verification.json](verification.json).

All five witnesses reproduced within their stated limits. Of 27 existing
regression programs attempted serially, **22 passed the checked runner and five
remain unqualified**: their runs reported missing scene/vehicle assets, with
three timeouts. Those failed or incomplete invocations are retained separately;
they are neither passing regression evidence nor additional controls defects.

| ID | Priority | Finding | Principal boundary |
| --- | --- | --- | --- |
| [GCA-01](#gca-01--quad-accepts-pause-assignments-that-flight-does-not-dispatch) | P2 | Quad accepts radio Pause assignments that flight does not dispatch | Controls → multirotor activity |
| [GCA-02](#gca-02--airship-keeps-native-menu-mappings-after-ui-ownership-changes) | P2 | Airship keeps the former native menu controller after role loss/change | Registry → AppRoot → activity → InputMap |
| [GCA-03](#gca-03--airship-does-not-retry-a-temporarily-refused-profile-on-continue) | P2 | Airship Continue does not retry an uncached profile after a temporary refusal | Profile resolver → connection → resume |
| [GCA-04](#gca-04--legacy-calibration-writers-can-acknowledge-a-lost-update) | P2 | Two legacy calibration writers can both succeed while losing one update | Direct/legacy persistence |
| [GCA-05](#gca-05--accepted-tiny-ranges-do-not-reach-their-declared-endpoints) | P3 | Accepted tiny channel ranges do not normalize to their declared endpoints | Validation → persistence → runtime conditioning |

P2 denotes a material, bounded workflow, ownership or data-integrity defect.
P3 denotes an unusual accepted-input boundary or lower-priority robustness issue.
These are engineering priorities, not physical aircraft safety ratings. The
experimental status of the quad and airship remains relevant to release wording.

The repair order is GCA-01/GCA-02, then GCA-03/GCA-04, then GCA-05. First align
offered actions and device authority with the active vehicle; then close recovery
and persistence gaps. Preserve each activity's distinct throttle, arming and
resume rules. [REMEDIATION](REMEDIATION.md) specifies the acceptance boundaries.

## 2. Scope and method

The review traced keyboard, gamepad, raw joystick and RC-radio input through
registry selection, V2 and legacy profiles, calibration, action capture, native
GUI mapping, pause/focus/reconnect handling, and fixed-wing, helicopter, quad,
airship and car consumers. JETI and EdgeTX/OpenTX behavior was considered through
the existing profile and controller contracts; brand recognition does not prove
channel order, transport reliability or hardware compatibility.

The root and scoped repository instructions, controller and Controls UX plans,
flight-log guide, consolidated audit queue and historical controller correction
record were read before assigning current findings. Two bounded source reviews
covered profiles/persistence and routing/lifecycle. An independent Good Enemy
review challenged scope, priorities and counterexamples. The lead checked the
material source paths and integrated only findings with a causal explanation.

Existing tests establish regression context. New diagnostics use unchanged
production classes and synthetic input; the legacy race uses a disposable source
copy with an explicitly recorded scheduling barrier. The probes deliberately
assert the adverse baseline and include positive controls. They are not proposed
permanent regression expectations. A future fix must replace the adverse
expectation with the intended invariant.

The initial checkout was sparse. Missing tracked resources caused preparation
errors; those attempts are excluded from passing evidence. Required static
dependencies were materialized from the pinned tree, and generated import
metadata was restored and its referenced caches regenerated after inspection.
Larger scene assets needed by five integration programs remain unavailable in
this bounded checkout. No production script, aircraft data, physics law, input preset
or golden flight was changed. The final source manifest and checked results
record what was actually available to each accepted run.

### Implemented boundaries

| Layer | Current responsibility | Audit concern |
| --- | --- | --- |
| Controller registry/service | Observed identity, connection generation, flight/UI role, profile resolution and managed activation | Every activity must honor cleared roles and resolver refusal/recovery |
| V2 profile/store | Schema, channel/action meaning, association, storage lease and rollback | Accepted values must satisfy downstream normalization assumptions |
| RcInput | Calibration normalization, readiness, radio LOW evidence, gamepad polling and virtual throttle | Preserve existing activity-specific readiness; do not conflate polling with fresh radio evidence |
| Controls setup | Drafts, capture, calibration handoff, validation and explicit Save/Cancel | An offered action must have an actual consumer in that activity |
| AppRoot and UiInput | Selected-device menu mappings and semantic action routing | Delegated activities must clear/rebuild global GUI mappings |
| Vehicle activities | Input adapter, Pause/Continue, arm/disarm and session tick ownership | Recovery must remain explicit and use current source/profile identity |

These boundaries explain why a passing profile validator or store test alone
cannot qualify a complete player action. The owning source is listed in the
[source manifest](source-manifest.json); exact defect locations follow below.

## 3. Confirmed defects

### GCA-01 — Quad accepts Pause assignments that flight does not dispatch

**Priority:** P2. **Owners:** DR-14/DR-16 with UI-15-GP-01 and shared action owners.
**Scope:** the experimental multirotor activity, specifically non-gamepad-button
Pause bindings. This does not reopen the prior quad arming defect CTRL-01.

`pause` is declared as an action available in both menu and flight contexts. Its
applicability does not exclude multirotors. Controls exposes Remap and the
radio/joystick Learn axis operation; the profile and action validators accept a
radio button or learned unused-axis binding. However, AppRoot returns early from
its generic controller-event router while an activity occupies `ground_vehicle`.
The multirotor adapter
installs Pause only after the source passes `radio.is_gamepad()`, and then only
for a button binding. The activity handles that button plus hardcoded P/Escape.
An accepted radio Pause assignment therefore has no flight consumer. A custom
Pause key other than P/Escape has the same source-level dispatch gap.
[Action declaration][actions] · [applicability][action-applicability] · [adapter][quad-input] · [activity dispatch][quad-dispatch] · [shell delegation][shell-delegation]

**Reproduction:** select a synthetic radio with a valid V2 profile and assign
Pause to button 20. Supply the actual LOW-throttle event, explicitly Continue,
then deliver OFF followed by ON for that button through the activity's input
callbacks. The session stays running. Deliver Escape to the same activity: it
pauses. The diagnostic also validates a learned-axis Pause profile, but does not
claim that its full runtime edge sequence was separately exercised.

The consequence is an apparently successful configuration that does not provide
the requested pause control. Keyboard recovery remains available. Existing
`test_mr_controller_authority.gd` checks default Start and a remapped gamepad
button; neither establishes radio Pause dispatch. The reproduction uses the real
activity/session with a synthetic radio, not a physical transmitter or native
SDL event stream. [Diagnostic](../../../research/game-controls-audit-2026-11-21/probe_quad_pause.gd)

**Recommended repair:** dispatch the admitted Pause binding through the shared
edge/hysteresis contract at the quad's own activity boundary, retaining selected
device/generation ownership and OFF-before-ON for raw controls. Alternatively,
explicitly reject and explain unsupported binding forms in that activity's
Controls UI. Merely saving a valid generic action is insufficient. Verify radio
buttons, learned axes, custom keys, foreign devices, held switches, AUX conflicts
and explicit resume, with P/Escape preserved.

### GCA-02 — Airship keeps native menu mappings after UI ownership changes

**Priority:** P2. **Owners:** BL-10/BL-12 with UI-12-GP-01 and F3-GP-02.
**Scope:** native gamepad menu mapping while the managed airship is active.
Flight-axis ownership is a separate path and is not shown to transfer here.

Home installs native `ui_*` events for the selected gamepad's numeric device ID.
The registry correctly clears a lost UI role and the service forwards the
selection change. AppRoot clears its radio router, then delegates to
`ground_vehicle._refresh_controller_ui()` and returns. The airship implementation
only refreshes Pause bindings. Consequently the old `UiInput` selection and
InputMap events remain installed, unlike the quad's explicit menu-map refresh.
[Registry loss][registry-loss] · [service forwarding][service-selection] · [shell callback][shell-ui] · [airship refresh][airship-ui] · [native mapping owner][ui-input]

**Reproduction:** select pad 7 for menus, install its native map, activate the
airship routing callback, and disconnect pad 7 through the real registry. The
registry UI role becomes `-1`, but `UiInput.selected_gamepad_id()` stays `7` and a
pad-7 Accept event still matches `ui_accept`. Re-enumerate a different device on
ID 7: it still matches the stale map without holding the UI role. Then select pad
8 for menus: the registry changes to 8 while the native map remains on 7.

The retained probe exercises actual registry/service/AppRoot/airship callbacks
and native InputMap matching. It does not claim that a physical reused device
clicked the rendered HUD. The airship HUD uses ordinary focusable buttons, so
actual rendered activation is an explicit follow-up acceptance check, not an
invented observation. [Diagnostic](../../../research/game-controls-audit-2026-11-21/probe_airship.gd)

**Recommended repair:** make the activity's UI refresh clear native mappings
first, then install only the currently authorized menu source. Preserve keyboard
recovery and the activity's separate radio-menu support limitations. Test loss,
same-handle replacement, second-device selection, changed profile bindings and
exit back to Home. Clearing the service registry alone cannot remove already
installed global InputMap events.

### GCA-03 — Airship does not retry a temporarily refused profile on Continue

**Priority:** P2. **Owners:** BL-10 and F3-GP-02/D6-GP-02.
**Precondition:** a selected connection has no cached successful profile when a
lookup is refused, for example while another store instance owns the V2 lease.
This does not affect every launch: a cached profile can bypass the read.

The resolver correctly returns an empty profile when it cannot acquire the store
lease. The airship correctly suppresses a guessed gamepad default and connects
the source as unconfigured. It also records that connection generation. Later,
`_sync_selected_controller()` returns immediately for the same ID/generation,
and Continue only samples the unresolved reader. It never requests the now
healthy profile. The quad explicitly has a retry path for this condition.
[Resolver][service-resolver] · [airship connection and sync][airship-connect] · [Continue][airship-resume] · [quad retry helper][quad-retry] · [quad Continue call][quad-retry-call]

**Reproduction:** hold a real V2 store lease with a second Store instance; connect
a fresh selected pad through the managed airship resolver. Confirm it stays
unarmed. Release the lease, verify that the same resolver now returns a valid
gamepad profile, then synchronize and press Continue. The session remains paused
with the generic lower-throttle/check-controller message. Explicitly reapplying
the same recovered profile allows the same source to resume.

This is a recoverability defect after a temporary error, not a request to fly
during failed validation. The existing airship audit test checks the fail-closed
half but does not check recovery. Returning Home, reviewing/reselecting or saving
in Controls, and launching again provides a player recovery route. The probe's
direct `apply_controller_selection()` call is a method-level positive control,
not evidence of a Controls entry within the airship's private pause HUD. No
permanent data loss is alleged.
[Diagnostic](../../../research/game-controls-audit-2026-11-21/probe_airship.gd)

**Recommended repair:** retry only unresolved/refused profile state at an explicit
recovery boundary, with current connection identity and selected role rechecked.
Continue must still remain an explicit action, and a repeated refusal must keep
the activity held. Preserve calibrated radio LOW evidence and verified gamepad
semantics instead of substituting a default profile. Provide a storage/profile
error when that is the actual cause.

### GCA-04 — Legacy calibration writers can acknowledge a lost update

**Priority:** P2. **Owners:** D6-GP-02, direct fixed-wing/helicopter calibration
and AUX persistence. **Scope:** `rc_calibration.cfg` legacy writes, not the
repaired V2-to-V2 transaction path from CTRL-14.

`RcCalibration.save_profile()` loads the entire ConfigFile, changes one device
section, then directly saves the whole file. `save_smoke_binding()` has the same
read/modify/write shape. Neither participates in a shared cross-process lease or
staged replacement. Direct/technical fixed-wing and helicopter calibration still
reach this writer when managed persistence callbacks are absent.
[Legacy writer][legacy-save] · [fixed-wing caller][legacy-fw] · [helicopter caller][legacy-heli]

**Instrumented reproduction:** start from a legacy file containing a seed device.
Two independent Godot processes load that same file and prepare different device
sections. A barrier inserted into a disposable copy immediately before the
original save schedules A to save, then B to save its earlier snapshot. Both
actual `ConfigFile.save()` calls return `OK`. Reading with the unmodified
production loader finds the seed and writer B, but not writer A. This establishes
the lost-update interleaving; it is not a claim that a random concurrent launch
always produces it. The barrier, generated diff, source hash and outcomes are
recorded. [Reproducer](../../../research/game-controls-audit-2026-11-21/run_legacy_race.py)

Direct save also lacks a rollback publication stage, but no power-loss or disk
failure experiment was performed. That is a design concern to test separately,
not an additional reproduced defect.

**Recommended repair:** serialize all writers of the legacy file under one
file-specific lease covering load/merge/save, and publish a validated staged
file with a defined failure/rollback policy. Include calibration and smoke
updates under the same authority. Preserve the legacy format and migration
readers; do not silently replace their semantics with V2. Test simultaneous
different-device writes, same-device updates, calibration-versus-smoke, read
failure, contention and interrupted publication. A successful response must mean
the acknowledged update survived or that the caller was told to retry.

### GCA-05 — Accepted tiny ranges do not reach their declared endpoints

**Priority:** P3. **Owners:** D6-GP-02/D6-GP-03.
**Scope:** externally authored, imported or manually damaged profiles admitted by
the current validators. The wizard's minimum total sweep is `0.5`, so it does
not normally generate the `0.0000005` range used here.

The validator requires finite ordered endpoints but accepts any positive span.
The normalization code divides by `max(span, 0.000001)`. Those contracts disagree
below that denominator floor. A valid absolute channel with `min=0`, `center=0`
and `max=0.0000005` produces `0.5` at its declared full endpoint. With inversion,
the physical LOW endpoint is raw maximum and also produces `0.5`, rather than
zero. Signed per-side normalization has the same lower-bound design issue.
[Validation][profile-validation] · [normalization][profile-normalization] · [wizard minimum][wizard-sweep] · [wizard rejection][wizard-rejection]

**Reproduction:** validate the narrow trigger profile, save/reload it through the
real V2 store, and pass it to the actual RcInput reader with synthetic verified
gamepad polling. The reader is ready and returns 50% throttle at the declared
inverted idle. With a radio profile using the same inverted range, its LOW gate
cannot arm. Ordinary trigger endpoints remain zero and one in a positive
control. The diagnostic establishes profile arithmetic and reader behavior, not
a device incident or physical probability.
[Diagnostic](../../../research/game-controls-audit-2026-11-21/probe_profile_ranges.gd)

**Recommended repair:** define and enforce an explicit minimum span compatible
with normalization at both validation and activation, or change normalization
with a reviewed numerical contract. Keep existing files repairable and reject
activation with an actionable field error. Test values just below/at/above the
chosen bound, both signs, off-center signed channels, both inversion states,
persistence and the live reader. Avoid silently accepting a profile whose named
endpoints cannot be reached.

## 4. Gaps and support boundaries

### GCA-G1 — Long-gap continuity is not shared by every activity

The service's `>5000 ms` suspension check depends on an attached `session` with a
connected radio. AppRoot attaches fixed-wing/helicopter sessions, while car,
quad and airship live behind separate activity adapters. Their normal focus and
disconnect handlers exist; the missing case is a long processing gap **without**
either event. Source inspection did not find an equivalent gap check in those
activity tick paths. This is an unverified recovery coverage gap, not a claim
that a particular OS sleep reproduces it. [Watchdog][watchdog] · [flight attachment][session-attach]

Use a synthetic clock and real activity tick boundary to establish whether any
post-gap tick is accepted before a hold. Then qualify native suspend/resume and
focus-event delivery per platform. Even the aircraft watchdog runs in `_process`;
its existence alone does not prove it precedes every first post-gap physics tick.
Do not attach incompatible vehicle sessions blindly to the service API.

### GCA-G2 — Direct routes and verified radio menus need an explicit activity matrix

The direct airship launch returns before ordinary AppRoot service initialization
and uses the first-device/legacy-profile route. The quad has a separate managed
direct-route service. Technical launch flags are documented as distinct from
Home preferences; this review therefore classifies the difference as a support
contract to document/qualify, not automatically a general launch defect.
[Direct route][direct-airship] · [legacy first device][airship-legacy]

Likewise, AppRoot disables its verified semantic radio GUI router for activity
nodes. Radio Pause handling and complete radio GUI navigation are different
capabilities. The player guide already limits activity-wide radio-menu claims;
make per-activity support explicit rather than treating one successful fixed-wing
journey as universal evidence. Keyboard remapping remains a known planned
D6-UX-02 feature, not a newly discovered implementation regression.
[Radio activity gate][radio-menu-gate] · [Controls UX plan](../../plans/controls-setup-ux.md)

### GCA-G3 — General no-takeover wording conflicts with the accepted quad fallback

The quad deliberately picks another connected controller after losing its source,
holds the session and invalidates arm continuity. An already armed simulated
motor disarms on the first resumed tick; the paused stored frame can retain its
former mode. Its owning plan and test explicitly require that fallback. General
controller prose says active selection waits for explicit
ownership. Reconcile the wording and display the new source before Continue;
do not label the intentionally tested fallback itself as a new bug or an
automatic resumption of flight. [Owning policy][quad-policy] · [fallback test][quad-fallback-test] · [general contract](../../plans/controller-support.md)

### GCA-G4 — Hardware, accessibility and package qualification remain open

This audit exercised synthetic input and source behavior on Linux headless with
Dummy audio. It did not qualify Xbox, DualSense, JETI, EdgeTX or other physical
controllers, USB-versus-Bluetooth differences, transmitter-off RF failsafe,
controller sleep, OS suspend, Steam wrappers, handheld controls, exported
packages, controller-only text entry, screen readers, or pilot feel. Carry these
as independent rows with model/firmware/OS/provider/transport and actual build
identities. An enumerated receiver and unchanged axes do not prove an RF link is
healthy or failed. See [QUALIFICATION](QUALIFICATION.md).

## 5. Optimization and maintainability opportunities

### GCA-O1 — Measure and consolidate repeated input sampling

On a connected, configured, valid poll that reaches its sampling loops, the
production reader scans ten axes and 128 buttons when the corresponding reader
callables are supplied. Other paths can return early. The deterministic probe counted **2,400
axis callback invocations and 30,720 button callback invocations for 240 polls**
on a default gamepad without extra AUX bindings. These are application callback
counts, not physical USB polls or measured frame cost. A polled AUX binding can
add reads. [Reader loop][reader-loop] · [count probe](../../../research/game-controls-audit-2026-11-21/probe_poll_budget.gd)

Benchmark a coherent per-device, per-tick snapshot reused by readiness, primary
channels and AUX consumers, with preallocated storage where it simplifies
ownership. Preserve observation freshness, unbound held-button policies, invalid
sample rejection, and event-versus-poll distinctions. Do not reduce sampling to
currently mapped buttons without proving the existing gates are equivalent.
Acceptance requires unchanged outputs/edges at identical input tapes plus
native CPU/allocation and input-to-display measurements; no speedup is claimed
here. The previous per-event profile/binding cache and 2 Hz store-lease correction
already exist and must not be reissued as new findings.

### GCA-O2 — Give setup draft and capture state smaller owners

At the pinned tree, `controller_setup.gd` has 6,074 lines, alongside 6,204 lines
in twelve `ui/controls` scripts; AppRoot has 5,337 lines. Size alone is not a bug,
but the defect pattern makes explicit ownership valuable. The existing Controls
UX plan already proposes draft, capture and view seams. Continue that bounded
decomposition around immutable connection leases, profile candidates and capture
completion; preserve the public facade and current behavior while migrating
tests. Avoid a wholesale UI rewrite or several competing profile authorities.
[Controls UX ownership and steps](../../plans/controls-setup-ux.md)

### GCA-O3 — Test one admitted action across every relevant consumer

The current suite has strong component tests, yet GCA-01 survives because generic
validation and the quad's narrower action dispatch are tested separately. Define
small reusable contract cases for an admitted binding: validate → activate →
OFF/press/release → activity response → hold/focus/reconnect → recovery. Run the
applicable case for fixed-wing, helicopter, quad, airship and ground activities,
with explicit unsupported rows. This improves regression detection and reduces
duplicated policy assumptions; it does not require forcing every vehicle to
implement identical actions. Reuse existing fixtures and checked tooling.

## 6. Reconciliation with earlier work

The [14 November correction table](../controller-support-2026-10-14/README.md#external-controls-audit-corrections-2026-11-14)
records CTRL-01–15 as corrected within their stated scope. Current source and
selected tests support retaining that status. This audit does not claim every
historical issue was independently requalified on every platform.

| Earlier area | Current treatment |
| --- | --- |
| CTRL-01 quad readiness | Existing correction retained; GCA-01 concerns Pause dispatch, not raw throttle bypass |
| CTRL-02/06 draft and capture connection leases | Retained; no current blanket identity-takeover allegation |
| CTRL-03 dirty contexts | Retained; existing setup tests exercise save/discard behavior |
| CTRL-04/05 managed airship input | Retained; GCA-02 tests native menu mapping and GCA-03 tests retry after refusal |
| CTRL-07–13 capture/calibration semantics | Retained; GCA-05 concerns external tiny spans below the wizard's admissible sweep |
| CTRL-14 V2 concurrency | Retained; GCA-04 concerns separate legacy writers |
| CTRL-15 event allocation/copying | Existing event-scope cache retained; O1 concerns poll callbacks, not the repaired event path |
| F3-GP-02-R3 periodic store lease | Existing optimization retained; no new target performance claim |

The audit's local IDs are intentionally distinct from historical CTRL IDs.
The machine-readable register and repair plan link each item to its existing
implementation owners. Proposed optimizations and qualification gaps are not
included in the confirmed defect count.

## 7. Evidence limits and release implications

The checked diagnostics and selected regression suites support the specific
software conclusions in [VERIFICATION](VERIFICATION.md). They do not constitute
the complete app suite, final required CI, a package release gate, a rendered
flight, or physical qualification. Raw diagnostic completion must be read with
its expected baseline behavior: a reproduced undesirable result is not a fix.

No fixed-wing or vehicle physics changes are proposed on this branch, and no
golden replay was regenerated. When fixes alter input conditioning, matching
post-conditioning replay alone cannot re-test that processing or pilot
adaptation. Follow the [flight logging guide](../../FLIGHT-LOGGING.md) and add
actual input/live-flight boundary checks appropriate to the owning vehicle.

The practical release concern is truthful controls support: an advertised
assignment should work for the selected activity; cleared ownership should also
clear native GUI authority; temporary refusal should have a recoverable path;
and successful persistence should retain the acknowledged settings. Hardware
support wording must continue to name only the routes independently qualified.

## 8. Primary references

Repository source at the pinned commit and executed diagnostics are the authority
for the findings. Official engine documentation supplies background only:

- [Godot Input API](https://docs.godotengine.org/en/stable/classes/class_input.html): global polling state and SceneTree event consumption are separate; clearing/consuming one route is not proof the other is isolated. Accessed 21 November 2026.
- [Godot controller guide](https://docs.godotengine.org/en/latest/tutorials/inputs/controllers_gamepads_joysticks.html): desktop controller support uses SDL 3, while device mapping, drift, focus and platform behavior still need qualification. This is the moving `latest` manual, not proof of the pinned beta's behavior. Accessed 21 November 2026.

[actions]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_actions.gd#L44-L52
[action-applicability]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_actions.gd#L424-L436
[quad-input]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/multirotor_input.gd#L229-L251
[quad-dispatch]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/multirotor/multirotor_scene.gd#L736-L778
[shell-delegation]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L2768-L2782
[registry-loss]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_registry.gd#L93-L111
[service-selection]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_service.gd#L421-L439
[shell-ui]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L2412-L2440
[airship-ui]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/airship/airship_scene.gd#L922-L923
[ui-input]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/ui/ui_input.gd#L11-L62
[service-resolver]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_service.gd#L309-L330
[airship-connect]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/airship/airship_scene.gd#L384-L447
[airship-resume]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/airship/airship_scene.gd#L598-L611
[quad-retry]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/multirotor/multirotor_scene.gd#L621-L628
[quad-retry-call]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/vehicles/multirotor/multirotor_scene.gd#L858-L864
[legacy-save]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/rc_calibration.gd#L327-L374
[legacy-fw]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/flight_session.gd#L1901-L1922
[legacy-heli]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/helicopter_flight_session.gd#L1013-L1028
[profile-validation]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_profile.gd#L523-L545
[profile-normalization]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_profile.gd#L626-L691
[wizard-sweep]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/rc_calibration.gd#L31-L44
[wizard-rejection]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/rc_calibration.gd#L220-L229
[watchdog]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/controller_service.gd#L50-L59
[session-attach]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L1728-L1729
[direct-airship]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L349-L375
[airship-legacy]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/airship_input.gd#L26-L42
[radio-menu-gate]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L2465-L2479
[quad-policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/docs/plans/drone-racing.md#L639
[quad-fallback-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/tests/test_mr_activity.gd#L532-L547
[reader-loop]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/input/rc_input.gd#L297-L377
