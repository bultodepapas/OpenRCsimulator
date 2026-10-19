# EX-06/EX-08 Extra installation and flight probes

2026-10-11 research tools; the original installation/envelope results are dated evidence. Current scope and verification gaps live in the aircraft guide; physical qualification remains open. Owner: [realism plan](../../../docs/EXTRA-300-PLAN.md).

The current aircraft data encodes manual high rates as mechanical maxima and the low/high ratios below as `controls.rates.normal`. Normal keyboard/gamepad travel uses that profile; a radio supplies its own rates. Full-profile/scripted inputs use the maxima. Use the [current control guide](../../../docs/FIRST-LAUNCH.md), verify endpoints and avoid applying a reduction twice. These derived angles do not identify installed servo behavior.

| Surface | Manual high/low linear travel, each direction | Derived high/low angle | Low/high angular ratio |
| --- | --- | --- | --- |
| Aileron | ⅝ / ¼ in | 17.601° / 6.947° | 0.394705 |
| Elevator | 1¼ / ¾ in | 23.922° / 14.081° | 0.588627 |
| Rudder | 2½ / 1½ in | 30.026° / 17.472° | 0.581888 |

Angles use `asin(linear_travel / local_control_chord)` from the measured hinge geometry. Thus reducing angular travel by exactly 40%/60%/60% does not reproduce the manual's linear low-rate travel. No expo is prescribed by this audit. The source manual recommends low rates for takeoff and normal flight; high elevator can intentionally stall/snap the model. These are simulator setup instructions, not a real-aircraft setup recommendation.

Geometry/physics generation and routine checks have one home in the [asset guide](../../../assets/aircraft/extra-300s-60/README.md#pipeline-and-routine-verification).

The current test runner discovers the Extra installation/handling scripts; historical results below do not establish a passing current suite. The research probes exercise the actual flight session with explicit scripted controls and write metrics rather than asserting unmeasured aircraft performance. Run each probe against a separately imported app snapshot to compare physical changes. All reported rates are body angular rates unless explicitly stated otherwise; integrating body pitch rate is not, by itself, proof of a planar loop.

Sources, before/after results and limits: [EX realism evidence](../../../docs/research/extra-300-realism/README.md).

Run each imported snapshot with the pinned Godot 4.7.2. Example from PowerShell (replace the app and output paths to compare snapshots):

```powershell
python research/extra-300/ex06/run_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --probe envelope --hz 240 --output extra-envelope-240.json
python research/extra-300/ex06/run_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --probe ground --hz 240 --output extra-ground-240.json
```

Repeat with `--hz 480` for refinement. The runner rejects engine errors, setup failures, nonfinite state and incomplete airborne traces; a finite ground outcome still requires review of crash, contact and event fields. Each run saves a log and probe/aircraft/wheel-profile hashes. `envelope_probe.gd` uses explicit pilot commands, including bounded research-only feedback in the guided turns and a solved inverted reference. `ground_probe.gd` uses the actual session wheel/terrain/crash path. Neither script changes production model coefficients.

Reduce saved reports named `envelope-after-240.json`, `envelope-after-480.json`, `ground-after-240.json` and `ground-after-480.json` with:

```sh
python research/extra-300/ex06/compare_results.py --baseline-app BASELINE/app --after-app AFTER/app --evidence EVIDENCE_DIR
```

For whole-app checks, use `bash app/test.sh` in a clean Linux checkout with these changes applied and text checked out as LF. Run the Extra-specific benchmark with `--script res://tests/bench_physics.gd -- --aircraft=gp-extra-300s-60`; its best-of-three batches are local timing observations, not hardware acceptance. The evidence report records any baseline suite failures and the downstream checks run after them.
