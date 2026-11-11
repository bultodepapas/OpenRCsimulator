# AC-12 research scripts: handling probe and numerical campaign

Research drivers for step AC-12 of the [Aircraft Creator plan](../../../docs/plans/aircraft-creator.md). They are not tests and not part of `app/`: they compile in-domain definitions with the unchanged compiler and fly them in the unchanged `FlightSession`. Results and their limits are recorded in [the campaign record](../../../docs/research/aircraft-creator/AC-12-numerical-campaign.md) and [the package derivation](../../../docs/research/aircraft-creator/estimated-trainer-package.md). Software evidence about an estimated package; no physical validation.

| File | Role |
| --- | --- |
| `variants.gd` | Builds in-domain definitions from the template: scaled span, aspect ratio, taper, balance by battery position and ballast, added mass |
| `handling.gd` | Modes at trim (4×4 projections and the full Jacobian), hand launch at full throttle and a one-second full-aft pull, each as flown and with the propeller's reaction torque and gyroscopic momentum cancelled inside the probe |
| `eigenvalues.py` | Coupled eigenvalues of the full Jacobians with NumPy |
| `campaign.gd` | Preregistered step-refinement campaign: 17 cases × 4 input tapes × 240/480/960 Hz |

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
