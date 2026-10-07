# D6b-R1 — Saved radio calibration validation

**Status:** implemented, 2026-10-07. Scope: calibration persistence; M2 physics and session code untouched.

## Contract

The loader accepts a complete wizard-produced `kind = "radio"` profile only:

- Four distinct integer axes in 0–9; boolean inversion per channel.
- Numeric, finite endpoints within the raw HID range −1…+1.
- `min < center < max` for roll, pitch and yaw.
- `min < max` and `min <= center <= max` for throttle. The wizard writes `center = min`, even for reversed throttle; throttle normalization ignores center.
- An exact string match with the requested nonempty device identity, in its MD5-keyed section.

Invalid data returns `{}` as a whole. Existing connection logic selects the complete default radio or built-in gamepad profile and resets arming. No malformed subset is merged into a valid profile. Saving invalid data returns `ERR_INVALID_DATA` before touching disk; failure to read an existing config returns that error instead of overwriting other devices.

Persisted gamepad-shaped profiles are intentionally refused: the calibration wizard always writes radio profiles, whereas the built-in gamepad profile uses a spring-centered throttle rate and extra shaping parameters. That runtime default remains unchanged. Missing kinds and floating-point axis IDs are rejected, not coerced. Direct `RcInput` callers remain responsible for passing validated profiles; this step changes the persistence boundary only.

## Evidence

- `test_rc_profile_validation.gd`: [720 checks](profiles.log), including malformed shapes/types, every primary channel, nonfinite endpoints, duplicate/fractional axes, asymmetric travel, reversed 0…1 throttle, identity mismatch, complete rejection and byte-preserving refused saves.
- `test_rc_calibration.gd`: 19 checks; the original wizard still generates usable profiles and round-trips them per device.
- `test_e2e_radio.gd`: [real main scene with fake device 15](radio.log); valid calibration/replug, malformed-profile fallback and idle throttle until a fresh low event. Three corrupt-file cases: duplicate axis, NaN endpoint and wrong device identity.
- Isolated mutations: original loader produces 174 failed assertions; removing uniqueness produces 28, removing finiteness produces 24. Removing the identity type guard triggers a Godot runtime error despite exit 0 and zero failed assertions. Always scan engine errors, as `app/test.sh` does. Results: [mutations.json](mutations.json).
- [Unreadable-config probe](probe_unreadable_config.gd): deliberately malformed ConfigFile is rejected on load and returns `ERR_PARSE_ERROR` (43) on save, [preserving its exact bytes](unreadable-config.log). Its expected engine parse errors are why this probe runs separately from the normal suite.
- Skill linter: zero errors before/after; the same 12 existing warnings.

Full `app/test.sh` passed: 85 GDScript test programs, model contracts, four aircraft's trimmed traces and identical state hashes at 30/60/144 FPS. [Full log](suite.log); isolated baseline identity and file hashes: [verification.json](verification.json). The shared working-tree baseline stopped before this change at tree-placement freshness (`Committed placement differs from offline recipe`); isolated verification excludes other tracks' uncommitted work.

Mutation reproduction: use a temporary Godot project containing `input/rc_input.gd`, `input/rc_calibration.gd` and `tests/test_rc_profile_validation.gd`. Independently replace the calibration script with the pre-change file, remove `or used_axes.has(axis)`, remove `not is_finite(float(value)) or`, or remove `typeof(identity) != TYPE_STRING or`. Run the new profile test after each change, checking both exit status and engine errors. Never mutate the shared working tree.

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_rc_profile_validation.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_rc_calibration.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_e2e_radio.gd
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/radio-input/D6b-R1/probe_unreadable_config.gd"
app/test.sh
```

These are software verification results. Physical-radio compatibility, pilot feel and Gate 2 acceptance remain open.

## Sources

[Audit SYS-06](../../project-audit-2026-10-06/systems.md#sys-06--saved-radio-profile-validation-is-structural-but-permissive); [radio knowledge base](../../roadmap-investigations/06-radio-input-servos-latency.md); [persistence and wizard](../../../../app/input/rc_calibration.gd); [normalization and arming](../../../../app/input/rc_input.gd). No new hardware assumptions or dependency changes.
