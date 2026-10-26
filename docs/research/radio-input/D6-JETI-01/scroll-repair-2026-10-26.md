# UI-15-JETI-04 — preserve the mapping being edited

Date: 2026-10-26. Source: [Jakub's latest feedback](../D6-JETI-00/feedback-2026-10-26.md). Ownership and remaining package/hardware gates live in the [JETI plan](../../../plans/jeti-support.md#feedback-update--2026-10-26).

## Cause and repair

Both action and AUX capture called `select_section()` even when their section was already selected. That method deliberately resets scroll and focuses the section tab. The debug bridge reproduced a lower action's offset changing from 3825 to 0 at capture start and remaining there after assignment. This initial headless session was later found to have a 64×64 window despite the launch resolution flag; it establishes the reset path, not 1080p qualification.

Capture now navigates only when it needs another section. It retains existing rows, selected-device filtering, validation, release consumption and Save/Cancel semantics. Real tab changes still reset and cancel capture as before.

Status text and mapping labels can also change geometry without changing focus. Layout notifications are coalesced into the next process frame, after containers have sorted, then the currently focused mapping is kept visible with the existing scroll container. The code does not retain a stale capture control, steal focus from another section, or run follow logic for ordinary scrolling. Wheel, pan, touch and scrollbar input cancel pending follow; same-frame layout notifications respect that explicit input. Small visibility adjustments during reflow are allowed; an exact pixel offset is not promised when the available viewport changes.

Compact height now accounts for text scale. At large text sizes, navigation moves into the scrolling area and the status preview uses one line, with its full text retained in the tooltip. This prevents status/navigation chrome from consuming the entire editor viewport.

The existing JETI malformed-profile test also exposed invalid mixed-type comparisons in `ControllerActions._aux_invalid_paths()`. The diagnostic now compares only integer pairs; `SmokeAux.valid_binding()` validates every member before comparing pairs. Tests include invalid members in either position, booleans, strings, floats, null and dictionaries. Valid switch semantics are unchanged.

## Verification

Engine: pinned Windows `4.8.beta1.official.4d10419ca`. Baseline: `557cc11d4`; broad checks use an isolated sparse worktree under local `tmp/jeti-capture-scroll/suite/`. Concurrent commits advanced the shared checkout during verification; no unrelated changes were reverted.

| Check | Result / scope |
| --- | --- |
| Identical initial capture regression on baseline/candidate | 1,296 checks: 544 failed before; 0 failed after. Baseline ran from the isolated checkout. |
| Final capture regression | 1,328 checks, 0 failed, including actual wheel input while a layout follow is pending. Fixtures use 1920×1080 first, then 2560×1440 and 3840×2160, then 1280×720; EN/ES and text scales 1.0/2.0. Larger displays use the existing logical UI scaling. |
| Existing setup regressions | `test_controller_setup`, `test_controller_setup_safety`, `test_controller_aux_setup`, `test_controller_responsive`, `test_jeti_setup` and `test_jeti_identity` passed. |
| Input/profile regressions | `test_controller_actions`, `test_controller_profile`, `test_controller_store`, `test_smoke_aux` passed. Expanded `test_jeti_runtime`: 105 checks, 0 failures and no engine errors. The checked runner caught the original errors despite that test's zero exit status. |
| Native Windows desktop scenario | The keyboard Remap/assign/Escape/Cancel path passed at 1920×1080 through the debug bridge. No physical transmitter was connected. |

The headless smoke launcher initially produced a 64×64 window on this host. The new scenario explicitly sets a 1920×1080 window for its checks and restores the previous size afterward. This avoids mistaking an impossible viewport for a controller regression.

Tests: [capture regression](../../../../app/tests/test_controller_capture_scroll.gd), [runtime malformed profiles](../../../../app/tests/test_jeti_runtime.gd), [debug scenario](../../../../tools/debug/scenarios/controller_capture_scroll.txt). Use the [checked runner](../../../tools/shared.md#one-godot-script) and [debug smoke](../../../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8). Local logs are under ignored `tmp/jeti-capture-scroll/`; no screenshots were added to Git.

## Hardware handoff

On the next authorized retest, record build/OS, DC-16II firmware and stick mode; assign five consecutive lower-list actions, reject a duplicate, cancel another capture, map AUX positions, Save/restart, and check sticks/buttons in flight plus focus/reconnect recovery. The exported package and real-radio result remain open. Software regression coverage does not establish physical mapping, latency or flight realism.
