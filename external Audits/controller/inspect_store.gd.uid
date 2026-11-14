# Controller profile, identity, and setup audit

## Identity and scope

Source snapshot: clean `f41d0fd2eb5483c609bcd858bcf22776eb311e14`, `/workspace/scratch/a1128d42a6f8/openrc-audit`. Read-only production review; no production files changed. The disposable project in `evidence/profiles/repro/` copies `app/input`, `app/ui`, and `app/app_state/build_info.gd`; all 209 tracked files in these copy scopes were SHA-256 checked byte-for-byte against the target snapshot, with zero missing or changed. Four generic prompt SVGs were materialized from the target Git objects; their Godot import products were created only in the disposable project. The fixture has a minimal `project.godot`, isolated `user://`, and the named probes below. It does not mount the full application, use SDL enumeration, or test physical devices.

Engine: Linux x86-64 Godot `4.8.beta2.official.cafc17a19`, SHA-512 `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9`. Used `tools/godot/run_checked.py`; final import and all final probes returned `ok: true`, child exit 0 and required completion markers. The probe checks deliberately assert that the adverse behavior was observed; they are not passing regression tests for intended behavior. Early probe logs failed the checked runner because initial fixture assets/dependency were missing; they were not used as evidence, and the final runs below use the complete fixture.

Focused source hashes: `controller_profile.gd` `9a302494e1449224195f2f7f57db85ac7806be23f3e675b56a428984684a16bb`; `controller_profile_store.gd` `c407b17f0fe67af364a58cb1c228c95ca42cb4070c55e9c2db927e4cea425016`; `controller_registry.gd` `2e5ff50676de07e9ce31b30c8acebb64f387359b60042ecd797ec508d585811b`; `controller_service.gd` `876273106015c77dac637ba4f4a99a9ec85df58be7b92336165c06cef7d6f353`; `controller_setup.gd` `d4ee36346edf9a07b663abf8b0a84d081c28eeeecdbab1ab9583bd6b735e6227`.

Reproduce from the source root after importing the disposable project:

```sh
export XDG_DATA_HOME=/workspace/scratch/a1128d42a6f8/evidence/profiles/userdata
export XDG_CONFIG_HOME=/workspace/scratch/a1128d42a6f8/evidence/profiles/config
engine=/workspace/scratch/912e78c5574d/repo_current/.tools/Godot_v4.8-beta2_linux.x86_64
project=/workspace/scratch/a1128d42a6f8/evidence/profiles/repro
out=/workspace/scratch/a1128d42a6f8/evidence/profiles/checks
python3 tools/godot/run_checked.py --label profile-audit-import --out-dir "$out" --timeout 60 -- "$engine" --headless --path "$project" --audio-driver Dummy --import
python3 tools/godot/run_checked.py --label profile-audit-probe --out-dir "$out" --timeout 60 --require-text 'AUDIT_PROBE_COMPLETE failures=0' -- "$engine" --headless --path "$project" --audio-driver Dummy --script res://probe.gd
python3 tools/godot/run_checked.py --label capture-audit-probe --out-dir "$out" --timeout 60 --require-text 'CAPTURE_PROBE_COMPLETE failures=0' -- "$engine" --headless --path "$project" --audio-driver Dummy --script res://capture_probe.gd
python3 /workspace/scratch/a1128d42a6f8/evidence/profiles/run_concurrent.py
```

The profile probe makes 12 observation checks; the capture probe makes 6. Results: `checks/profile-audit-probe-clean-95t_jjdb/{engine.log,report.json}` and `checks/capture-audit-probe-_6ptodtq/{engine.log,report.json}`. The concurrent test has separate checked logs for both writers and final read: `checks/race-writer-A-voljxvdk/`, `checks/race-writer-B-5x8nh0xi/`, and `checks/race-final-store-2eo9smvp/`. Exact logs and report verdicts are retained there.

## Confirmed findings

### P1 — A recycled connection ID can silently transfer and overwrite a saved profile

**Confidence:** high for synthetic registry observations and the Home/save path; physical device ID reuse and resulting flight control are not tested. The P1 classification reflects wrong-device mapping and loss of a saved association, not proof of automatic thrust or a crash.

**Causal chain:** `controller_setup.gd:308–320` stores the selected flight handle but no lease for the draft's connection generation. `:2181–2193` refreshes device descriptions on changes but keeps the draft and selected integer. `:3869–3883` constructs the profile association from whatever device currently has that integer. `:3894–3907` verifies generation only if a new in-screen calibration or menu verification has an origin; previously saved radio mappings are accepted by UUID and mapping at `:635–647`. The real app wires this screen to `ControllerService.save_settings_from_setup` at `app_root.gd:2054–2060`, and suppresses Home auto-selection while Controls is open at `:392–394`. The service checks that an ID is connected but not that it is the generation chosen when the draft began (`controller_service.gd:413–429`), then stores by existing profile UUID (`controller_profile_store.gd:64–75`).

**Reproduction:** With saved A (tested once as a known gamepad and once as a saved calibrated-style radio), open Controls and edit its name. Disconnect A, then connect different known gamepad B with the same synthetic handle 5; registry generation changes 1→2. Save without explicitly choosing B. In both cases `save_settings_from_setup` returned success, selected B for flight, and overwrote A's UUID with B's serial/GUID/VID/PID association. The radio variant retained A's saved radio mapping. Expected: the screen must detect that the connection behind its draft changed, preserve the A draft and A stored association, and require an explicit fresh selection/review for B. Existing calibration-origin and menu-verification leases only narrow the issue for newly produced evidence; they do not cover ordinary edits to an already saved mapping.

**Fix and cases:** Bind both flight and menu draft selections to connection-generation tokens. On a mismatch, fail Save before association/write/application; preserve the draft and offer explicit re-selection. Recheck the tokens at the service commit boundary as well. Cover disconnect/reconnect with the same and different identity, an atomic replacement snapshot, saved gamepad and radio profiles, menu-only replacement, same physical device reconnect, and a Pause session rejecting activation. Assert original file bytes/association remain intact and no role is silently transferred. Verify actual backend event timing and physical device behavior separately.

### P2 — Hidden profile drafts are discarded without the documented close prompt

**Confidence:** high; reproduced through the production screen's public close path. `controller_setup.gd:2357–2373` stores a separate remembered draft and clean snapshot per profile context, but `:366–373` checks only the current context; `:340–343` closes immediately when that returns false. The owner pops the screen on `close_requested` (`app_root.gd:2070–2071`). The guide promises dirty draft indication and a Save/Discard/Keep editing question (`docs/FIRST-LAUNCH.md:117`).

**Reproduction:** Load saved profile A, edit its name, then select clean saved B. The fixture observed A's edit still in `_drafts_by_context`, `has_unsaved_changes() == false` on B, and `request_close()` emitted `close_requested` immediately. Thus the remembered A edit disappears when the screen is popped. Expected: any unsaved profile or device draft keeps the dirty indicator and prompts before leaving; the user should be told exactly which changes Save will commit. A successful Save of the current profile can likewise close while other remembered drafts exist, so a fix must address Save semantics as well as Back.

**Fix and cases:** Track dirty state across every retained context, including pending names and calibration evidence; define whether Save commits all changed drafts or keeps the screen open and identifies remaining drafts. Test A dirty→B clean→Back, several edited profiles/devices, current save with another dirty context, pending calibration, Discard, Keep editing, and clean-all exit.

### P2 — Concurrent instances can acknowledge saves that erase each other

**Confidence:** high for the explicitly scheduled two-process interleaving; it requires two application instances sharing the same profile path. `controller_profile_store.gd:57–75` performs an unlocked read/modify/write, using fixed `.tmp` and `.rollback` paths at `:326–364`. A whole-file rename cannot preserve updates read by another process before the first commit. Contrast the explicit cross-process lock in `app/app_state/preferences_file.gd:87–105`.

**Reproduction:** The deterministic fixture subclasses only the transaction entry to pause each real `save_profile` immediately after its real load/merge, until both writers have read the same empty store. It then releases writer A to complete, followed by writer B. Both independent checked Godot processes report `ok=true`; final `load_all` contains only `Writer B`, so A's acknowledged save was lost. No simultaneous rename is needed. The scheduler is a test seam, not an unmodified production binary; the production read/merge and `_write_transaction` code are otherwise unchanged. Fixed shared temporary/backup names admit additional simultaneous-write contention, which this particular observation does not characterize.

**Fix and cases:** Use one cross-process lock spanning load, validation, merge, write, activation rollback, and recovery, or a versioned compare-and-swap with reliable retry; do not lock only the rename. Cover two new distinct profiles, edits to distinct profiles, UI-preference updates, simultaneous temporary-file contention, and one process failing or crashing while owning the lock. State and test recovery of stale locks explicitly.

### P2 — Maintained-switch capture lacks the connection-generation lease

**Confidence:** high for the synthetic atomic replacement snapshot; real backend delivery of such a snapshot is not established. `_start_capture` captures a generation (`controller_setup.gd:3438–3453`), but `_start_aux_capture` only captures the numeric ID (`:3463–3483`). `_on_registry_devices_changed` cancels on generation mismatch only when `_capturing_generation > 0` (`:2181–2190`), and the AUX input path accepts a same-ID button (`:2090–2105`, `:3534–3551`). Registry advances generations and clears selections on identity change even if it observes replacement directly (`controller_registry.gd:50–76`).

**Reproduction:** Start capturing a saved radio A's Flaps switch position; capture generation is 0. Directly replace its registry observation with radio B using the same handle, generation 1→2, without an intermediate disconnected snapshot. Capture remains live and B's synthetic button 42 changes A's draft switch group from `[20, 21]` to `[42, 21]`. Expected: capture cancels when the owning connection generation changes, before any B event is considered. A normal explicit disconnect callback does cancel, so the narrower atomic-identity-change condition matters.

**Fix and cases:** Set the generation for AUX button capture exactly as for ordinary capture, and verify lease again on input. Test same-ID direct replacement, identity metadata change, separate disconnect, same-identity reconnect, held/released controls, and unchanged uninterrupted connection.

### P2 — A resting throttle event can prematurely end action remapping

**Confidence:** high for synthetic event routing; whether a specific physical radio emits this jitter is unmeasured. `controller_setup.gd:3438–3459` starts ordinary Remap without recording baseline axes. `:2129–2141` accepts any selected-device motion above 0.65; the movement-from-baseline filter applies only to Find. `controller_actions.gd:327–330` turns it into an axis binding, after which `:281–286` rejects a primary flight axis and `controller_setup.gd:3500–3530` ends capture.

**Reproduction:** On a saved radio, throttle axis 2 rests at −1. Start remapping `camera_cycle`; before pressing the intended button, send one axis-2 motion at −0.999. Capture immediately emits `ok=false` with “uses a flight stick axis”; the intended button is never captured. Expected: incidental movement around the resting endpoint does not terminate a request for another control. Repeated idle events can make the UI difficult to use; this is not a claim that every radio generates them.

**Fix and cases:** Snapshot finite per-axis baselines at capture start and require deliberate displacement before considering an axis; preserve button/key capture, explicit learned-axis flow, and conflict feedback. Test endpoint jitter, a real moved axis from endpoint, a centered axis, invalid samples, device loss, and subsequent intended button press.

## Conditional identity hardening concern

`controller_profile_store.gd:383–403` treats a matching nonempty serial as sufficient even when both stored and observed USB IDs are absent and their nonempty GUIDs conflict; `:205–219` only checks uniqueness among devices connected now. The clean synthetic probe saved radio profile A with `serial_number=shared`, `guid=guid-A`, zero VID/PID, and matched it to sole connected B with `serial_number=shared`, `guid=guid-B`, zero VID/PID. This proves the matcher behavior, not that a physical Xbox, PlayStation, RC radio, transport, or driver actually reports duplicate/placeholder serials. If such reports exist, a wrong saved mapping can be suggested automatically; serial qualification should account for conflicting evidence and backend-specific reliability while retaining deliberate USB/Bluetooth transitions. Add fixture tests for identical placeholder serials, conflicting GUIDs, absent VID/PID, true unique serials, two simultaneous duplicates, and verified cross-transport changes before adjusting policy.

## Balanced review and limits

- The registry deliberately marks duplicate descriptors, advances generations, and clears ownership for disconnect/identity change (`controller_registry.gd:37–76`, `:199–232`); the active capture and draft exceptions above are specific omissions, not a claim that generation tracking is absent everywhere.
- A corrupt/unsupported V2 primary and invalid rollback are rejected, not silently treated as a new installation (`controller_profile_store.gd:26–41`, `:240–269`; service `:255–262`). Nonfinite and unsupported nested values are checked recursively (`controller_profile.gd:299–308`, `:627–655`); existing `test_controller_profile.gd:79–104` covers several examples. No broad invalid-value bypass was established.
- A normal single-writer transaction writes and validates a temp file, stages a rollback copy, and restores it on a failed commit (`controller_profile_store.gd:314–380`); recovery reads a valid rollback when primary is missing/damaged. This review did not test power-loss durability, read-only filesystem permissions, or true concurrent crash recovery and does not certify those paths.
- Multiple saved profiles associated with the same device intentionally fail unique automatic matching (`controller_profile_store.gd:197–203`); the guide describes automatic priority as one matching saved profile (`docs/FIRST-LAUNCH.md:103`). Do not label that conservative policy itself as an unintended collision without a product decision.
- A new calibration has a connection-generation origin guard (`controller_setup.gd:512–527`, `:3894–3898`); a menu challenge has a similar generation lease (`:575–600`). The saved-profile reassociation finding specifically bypasses the existence of those new-evidence origins.
- The source has legacy radio import and diagnostics export, but this audit found no general controller-profile delete/export interface to exercise. Existing legacy `rc_calibration.cfg` is left unchanged by import; skipped/import failures were not runtime-tested. No broad suite, real hardware, native Windows/macOS, or rendered interaction was run.
