# D6b-R2 — Fresh throttle evidence after calibration

2026-10-09 · **Status: implemented and software verified; physical-radio acceptance remains open.** Owning step: [ROADMAP D6b-R2](../../../../ROADMAP.md). Scope: radio arming; physics, aircraft data, saved-profile format and menus are unchanged.

## Defect and change

`RcInput.use_profile()` previously disarmed the radio but preserved `_seen`, its connection-wide raw-axis history. The next poll could immediately arm using a pre-calibration event and a low cached value. A unipolar throttle is especially clear: raw zero maps to idle, so polling an unreported/reset zero could reuse old evidence. The original E2E test also expected calibration to arm after only an aileron event.

The reader now keeps separate `_throttle_low_seen` evidence. Connection, profile replacement and disconnect clear it. While unarmed, a finite event on the active throttle axis sets it only when the value normalizes to at most 5%; a later high/invalid event clears it. Radio polling requires both this evidence and a currently low reading. Once armed, throttle still follows the stick normally. The built-in gamepad rate throttle keeps its existing idle-start behavior.

Raw axes and `has_axis_sample()` still retain connection-wide history across calibration, preserving the F6a latency marker. Clearing all diagnostic history would fix one symptom while changing that separate contract. The [player guide](../../../FIRST-LAUNCH.md) now tells the pilot to move throttle away from low and back after finishing calibration.

## Proof

- [New regression](../../../../app/tests/test_rc_rearm.gd): **365 checks pass**, using valid profiles on axes 0/2/9, bipolar/unipolar/asymmetric endpoints and both directions. Covers stale history, fresh high events, mismatched event/poll values, nonfinite events, current-low gating, repeated calibration, reconnect/direct replacement, reassignment, diagnostic history and gamepad control. These are authored software stimuli, not hardware measurements. [Focused debugger](focused-diagnostics.json): zero errors or warnings.
- [Private-project reproduction](baseline.log): **181 failures / 365 checks** against the original reader; the positive controls still load and arm. [Verification](verification.json): the current control passes; seven isolated defects fail the intended assertion, with no engine errors. Defects restore cached-history arming, omit profile/connection reset, accept nonfinite evidence, latch old low evidence, ignore the current poll or clear raw history.
- [Focused integration](focused-results.json): input math 41, axis history **9,252** over all 1,024 axis sets, wizard 19, persisted profiles 720, real-scene radio 38, F6a marker 533 and UI isolation 17 checks pass. The [radio log](test_e2e_radio.log) verifies SAFE after calibration and after a fresh high event, then ARMED after a fresh low event.
- [Full app suite](suite.log): `app/test.sh` exits 0 with **127 GDScript test programs**; existing goldens, four trimmed aircraft, frame-rate equality, contact and UI checks pass. The immediately preceding [D1-R5 suite](../../aircraft-validation/D1-R5/integration/app.log) supplies the 126-program baseline. Its frozen physics/simulation/data identity was checked before this step; the saved [reader/test hashes](before-source.json) identify the unchanged radio baseline.
- Static lint retains the same 12 existing warnings and zero errors. The real-scene radio fixture still emits its existing ObjectDB shutdown warning. This is not a warning-free whole-project run. [Manifest](manifest.json) binds source and evidence.

## Cost and limits

The [paired cost probe](cost/README.md) ran three alternating invocations per reader in ARMED and sustained SAFE regimes, each with the existing seven-round F3b benchmark. At 4,000 synthetic events/s, handler medians changed from 0.829 → 0.858 µs/event armed and 0.804 → 1.219 µs/event SAFE: estimated +0.002 and +0.028 ms per 60 Hz frame. Full dispatch medians changed from 4.486 → 4.794 and 4.734 → 5.120 µs/event. All twelve runs verify delivery. Event construction, physics and rendering are excluded; SAFE never polls. Concurrent suite load makes these observations, not performance acceptance or USB/stick-to-photon latency measurements.

Physical USB behavior, focus/replug qualification and Gate 2/F6 remain open. This repair changes calibration arming only; it does not add frozen-device detection or close the broader F3 work.

## Reproduce

With Python 3 and the pinned Godot, from the repository root:

```sh
app/test.sh
python3 research/input/d6b-r2/verify.py --out /tmp/d6b-r2-proof
patch --reverse --output /tmp/d6b-r2-original.gd app/input/rc_input.gd \
  < docs/research/radio-input/D6b-R2/change.patch
python3 research/input/d6b-r2/verify.py \
  --baseline /tmp/d6b-r2-original.gd --out /tmp/d6b-r2-baseline-proof
```

Output folders must be new. The verifier writes only its evidence folder and disposable projects. The patch identifies this reader revision; later changes need a matching baseline. Sources: repository reader, calibration, session, F6a marker and the existing F3b benchmark. No new external assumptions or dependencies.

Ready-to-paste commit message:

```text
fix(input): require fresh low throttle after calibration (D6b-R2)

Proof: 365 checks; seven rejected isolated defects; 9,252 axis-history checks;
real-scene calibration/rearm; full app suite (127 programs); paired event-cost probe.
```
