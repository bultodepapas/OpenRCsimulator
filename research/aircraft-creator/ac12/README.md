# AC-12 research scripts: handling probe and numerical campaign

Research drivers and audit contract checks for step AC-12 of the [Aircraft Creator plan](../../../docs/plans/aircraft-creator.md), outside `app/`. Historical drivers retain their original definitions and law; separately versioned studies explicitly select and identify their candidate compiler/session contracts. Results and limits are recorded in [the campaign record](../../../docs/research/aircraft-creator/AC-12-numerical-campaign.md), [the package derivation](../../../docs/research/aircraft-creator/estimated-trainer-package.md) and the [versioned servo-arrival record](../../../docs/research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md). Software evidence about an estimated package; no physical validation.

| File | Role |
| --- | --- |
| `variants.gd` | Builds in-domain definitions from the template: scaled span, aspect ratio, taper, balance by battery position and ballast, added mass |
| `handling.gd` | Modes at trim (4×4 projections and the full Jacobian), hand launch at full throttle and a one-second full-aft pull, each as flown and with the propeller's reaction torque and gyroscopic momentum cancelled inside the probe |
| `eigenvalues.py` | Coupled eigenvalues of the full Jacobians with NumPy |
| `campaign.gd` | Preregistered step-refinement campaign: 17 cases × 4 input tapes × 240/480/960 Hz |
| `refinement_audit.gd` | Separate current-source diagnostic: strict sampling/clock checks, unchanged legacy verdict on cached runs, exact float64 artifacts, pinned reference backend and exact `.orfl` baseline replay |
| `test_refinement_audit.gd` | Known-answer shape, finite-value, metric, binary-encoding, cell-selection, full-replay and output-path boundaries; no flights |
| `servo_arrival_campaign.gd`, `servo_arrival_campaign_all.gd` | Separately identified normalized-slew campaign and exclusive 68-cell driver; complete measurements do not imply a numerical pass |
| `verify_servo_arrivals.py` | Source-pinned independent Windows retention, binary metrics and full exact-replay verification; a partial collection never closes the gate |

Run from the repository root with the pinned engine (`app/get-godot.sh`; on Windows `.tools/Godot_v4.8-beta2_win64_console.exe`), scripts by absolute path:

```sh
GD="$(app/get-godot.sh)"
HERE="$PWD/research/aircraft-creator/ac12"
OUT=<a directory outside the repository>

# Handling probe (about 6 minutes), then the coupled eigenvalues
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/handling.gd" -- --out="$OUT"
python "$HERE/eigenvalues.py" "$OUT/jacobians.json"

# Campaign: list the cases without flying, then fly all or some (about 25 s per case and tape)
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/campaign.gd" -- --list
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/campaign.gd" -- --out="$OUT"
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/campaign.gd" -- --out="$OUT" --only=C14,C15
```

`handling.gd --only=<text>` limits the probe to cases whose name contains the text. The campaign writes `campaign-<cases>.json` with every difference, ratio, order and verdict. Outputs are not committed.

The probe's torque and gyroscopic cancellation wraps the session's stage evaluator inside the script. The runtime has no such switch and must not gain one.

## Current-source audit (AC-12 / AC-CV-06)

The [2026-11-16 preregistration](../../../docs/research/aircraft-creator/AC-12-audit-2026-11-16.md)
owns the five fixed cells and their interpretation. The historical campaign and thresholds
remain unchanged. The audit never qualifies flight or derives a replacement noise floor.

```sh
# Contract checks first; then one registered cell in a new/empty absolute output directory.
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/test_refinement_audit.gd"
"$GD" --headless --path app --audio-driver Dummy --script "$HERE/refinement_audit.gd" -- \
  --case=C15 --tape=roll_doublet --calibrate --out="$OUT"
```

On enrolled shared hosts use the [checked queue](../../../tools/testqueue/README.md),
not a direct unadmitted launch. The native evidence uses immutable focused app inputs
with byte-identical research files under `app/tools/ac12/` and selecting tool entrypoints;
every report records its actual source closure and engine hash. A selecting subclass may
live outside the AC-12 directory; helper resolution remains anchored to the audit module.

Without `--calibrate`, only 240/480/960 Hz run as a protocol pilot. Calibration adds a second
960 Hz run, two 1920 Hz runs and one 3840 Hz run. Keep `audit.json`, the exact definition
and compiled aircraft JSON, all `.f64le` samples, and the `.orfl`/CSV/replay report. The
pinned engine must expose little-endian packed float64 data; an explicit probe refuses
other encodings. Sample files contain 1440 rows of 17 binary64 values, without a header:
13 rigid-body states, airspeed m/s, shaft rpm, battery current A and consumed charge C.

Outputs must resolve to an absolute path outside the application source. The checked pool
collects runner receipts, not these `user://` artifacts. Recover the printed audit directory,
verify its SHA-256 against the checked log and every artifact against the report, and retain
the complete directory outside Git before releasing a completed native job's writable files.
The 240 Hz replay must include ticks 0 through 1440 and exactly 1441 rows; a normally
completed, exactly replayed prefix is refused.

`complete=true` means the requested measurement and artifact protocol completed. It is
distinct from the labelled inherited-rule verdict and from `flight_qualified=false`.
Compare initial frames, environments and canonical command edges before interpreting a
pair as step refinement. Equal sampled repeats alone do not establish a roundoff floor,
complete trajectory equality, physical realism or G05.

## Known arrival boundaries

[The arrival-partition experiment](../../../docs/research/aircraft-creator/AC-12-servo-knots-2026-11-16.md)
owns the controlled split study. `app/physics/slew_interval.gd` prepares the existing normalized
slew endpoint and sorted unique interior arrival offsets. It commits no state.
`ElectricContactStep.advance_at_offsets` merges at most three extra cuts with the existing
contact partition, refreshes later-piece derivatives and preserves atomic event handling.
Empty/coincident cuts retain the legacy path. Unresolvable or excessively fine absolute
clock intervals are refused. These utilities do not install a new aircraft law or enable flight.

Explicit pieces retain their local widths. Their represented absolute endpoints may differ
from the next piece's start by at most the existing capped clock tolerance (1 ns maximum);
this is not a promise of bit-exact clock joins. Distinct cuts are never epsilon-merged.
Historical endpoint arithmetic can leave a tiny servo residual whose next arrival is below
clock resolution; composition refuses it. Callers must handle that refusal, not silently
drop the cut. The planner bounds 64 channels; this battery composition admits three cuts.

`VehicleModel` also exposes the opt-in `joint-interval-v1` stage/policy transport, documented
in that contract and checked by `test_sf_joint_interval.gd`. No production aircraft selects
it; the arrival study's private ramp law is still separate from the runtime adapter.
