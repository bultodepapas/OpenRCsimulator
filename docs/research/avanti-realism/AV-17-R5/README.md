# AV-17-R5: flap compensation ownership

2026-11-10 · Implements review package R4 from the [retained review](../review-2026-11-10.md).
Baseline HEAD: `18000e97e586c1a8b0c401dc21ba657750176159`. Aircraft data, aerodynamic
coefficients, actuator law, failure law and kernel input layouts are unchanged.
Implementation commit: `a9daae7b809bbdf5351a8790a46ed9ee7c119de7`.
The [identity manifest](manifest.json) pins source, compressed evidence and checked
receipts, including the separately classified inherited companion-gate failure.

## Behavior

Controller schema v2 gains optional `flap_elevator_mix_owner`. Missing fields resolve
to `simulator`, and in-memory migration makes that default explicit. Existing saved
profiles remain readable without a bulk rewrite. New profiles default to simulator
ownership. Only radio/joystick profiles may choose `transmitter`; invalid values and
gamepad transmitter ownership are rejected. Calibration and profile saves preserve
the selection. The [player guide](../../../FIRST-LAUNCH.md) describes the Settings control.

FlightSession samples ownership with live commands. Simulator compensation retains
the authored gain and follows actual flap slew before failures, saturation and servo
travel. Transmitter ownership skips only that addition. Keyboard, gamepad, external
drivers and scripted maneuvers keep simulator ownership. A failed tick restores the
owner of the last accepted inputs before pause/fault observers run. Reset/restore
transactions include ownership, and restore publishes the new owner with the
committed frame while keeping the previous flight in its closing context.

Transmitter checkpoints bind the optional contract into their configuration hash.
Historical simulator-owned checkpoints keep their existing configuration bytes.
The [flight-log extension](../../../FLIGHT-LOGGING.md#quick-start) records ownership
per interval, profile identity changes and endpoint surface diagnostics. Replay uses
the recorded owner, independent of connected devices. Unknown, stripped or malformed
extensions are rejected; current replay tools explicitly refuse this extension when
paired with a historical solver that cannot implement it.

## Evidence

- The pre-edit [flap tape](baseline.orfl.gz) contains 5,520 ticks / 23 seconds of
  extension, deployed flight and retraction. Its [baseline exact replay](baseline-exact.json)
  is complete with `solver_changed: false`.
- Replaying that same tape on the candidate is deliberately [candidate mode](baseline-candidate-final.json)
  with `solver_changed: true`. The baseline and candidate CSV bytes are identical:
  SHA-256 `e6acf016c315330bf0a4dc573e16ef386c1dbd2895696c7c491a6cd3b50f06bc`.
  The compressed [baseline CSV](baseline-exact.csv.gz) and [candidate CSV](baseline-candidate-final.csv.gz)
  preserve the original bytes. This establishes unchanged behavior on this tape,
  not exact source equivalence or physical identification.
- [Ownership tape](ownership.orfl), [exact replay report](ownership-exact-final.json)
  and [surface-chain CSV](ownership-exact-final.csv): 192 accepted ticks traverse simulator-owned
  radio input, transmitter-owned radio input and keyboard fallback through the
  session's normal input sampler with synthetic axis events. All 193 numeric
  samples replay exactly, including owner, mix target and actual elevator travel.
  It identifies profile changes and does not require a physical radio.
- The new session regression checks legacy compensation, premixed radio/joystick
  channels, gamepad/keyboard/external/scripted behavior, saturation, unchanged flap
  travel, checkpoint discrimination, rejected-tick rollback, restore publication,
  per-interval replay and malformed declarations: **51 checks, zero failures**.
- Profile migration, validation, persistence, calibration, Settings save/cancel
  and diagnostics: **63 checks, zero failures**. Existing profile (74), conditioning
  (57), diagnostics (49), integration (27), calibration (111), setup/AUX and
  responsive layout (18,259) checks also pass.
- Existing focused suites pass: flaps session 36, controller rates 67, log input
  roles 284, flight logs 4,391, reset publication 215, restore publication 137,
  external-driver rejection 63 and failure integration 117. Full-suite CI remains
  separate. Checked process receipts and raw engine logs are retained in `checks/`.
- The actual Controls → Extra channels screen was rendered and visually reviewed
  at **1920×1080**, Compatibility/OpenGL on NVIDIA RTX 3090. The new choice, help,
  Save and Cancel fit without overlap. The screenshot remains under ignored `tmp/`;
  its checked capture receipt is retained. This is readability evidence, not a
  performance measurement or hardware-radio qualification.

The baseline recording starts at a research altitude of 500 m; reset-time launch
metadata still names its original launch. Its accepted command tape bypasses device
shaping. The separate ownership fixture exercises device sampling. Neither is a
pilot evaluation or a matched flight of the physical A200.

## Reproduction and remaining gates

### Native/reference boundary

The [native result](native/result.json) passes 19 aggregate checks for a 192-tick
paired Avanti trajectory under Linux x86_64 / WSL, followed by exact continuation
of 96 intervals from a transmitter-owned checkpoint. The production NativeStage
adapter retains ownership at every tick; original-flight counter deltas are 768
native stage calls / 192 contexts, and replay deltas are 384 / 96. State, previous
state, AUX, continuous state, inputs, loads, modes and events match byte for byte.
Nonzero flap travel and pitch traverse simulator → transmitter → simulator ownership.

The [harness](../../../../research/avanti-s/av17-r5/native_mix.gd) loads the verified
temporary research library; it does not install it into the app. Its
[before](native/before.json) and [after](native/after.json) identities match.
The retained [interval tape](native/interval-tape.bin), checked process receipt and
[build receipt](native/build-receipt.json) bind the observation to the actual
library and source. This is a bounded native/reference comparison, not Windows
native support, a native package requalification, performance evidence or physical
validation. The ordinary package pipeline must still prepare its own updated receipt.

### Companion and release boundaries

The required [companion solver rebind](../../ai-companions/AFC-02/rebinds/2026-11-10-a4ee8de9-to-e9ea5138.json)
compared all nine retained tapes, each 2,881 rows, on the accepted and current
solver copies. All CSVs are identical; the profile and qualification record now
pin normalized solver identity `e9ea5138`. This is tape preservation, not a new
companion behavior qualification.

`test_companions_profiles.gd` confirms the new solver pin, but **still fails** its
separate behavior-manifest gate at `app/app_root.gd`. The [identity comparison](companion-behavior-gate.json)
proves that file already had the same mismatching bytes at baseline `18000e97`;
this change does not edit it. The other fifteen behavior-source entries match.
The fail-closed admission and existing manifest remain intact. Full companion
admission must not be reported as passing until its owner renews that separate
qualification.

Use the [checked runner](../../../../tools/godot/README.md) for
`res://tests/test_flap_mix_ownership.gd` and
`res://tests/test_controller_flap_mix_profile.gd`. The first accepts `--out=<new directory>`
and writes its ownership tape. Use the existing flight-log CLI for exact replay of
the resulting tape on the same source/engine. Decompress `.gz` artifacts before
using them with that CLI. Historical baseline exact replay requires its retained
baseline source; current source must use explicit candidate mode.

Physical-radio setup, installed surface travel, pilot acceptance and release-package
qualification remain open. R3 ground correction still requires an identified target;
R5/R6 aerodynamic investigations are independent. The [plan](../../../AVANTI-S-PLAN.md)
owns the remaining review sequence.
