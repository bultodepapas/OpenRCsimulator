# EX-06/EX-08 Extra installation and flight probes

Status: installation corrections and 31 behavior probes implemented and verified; physical qualification remains open. Owner: [realism plan](../../../docs/EXTRA-300-REALISM-PLAN.md).

This work retains the GPMA0236 .60/O.S. .61FX reference build. The simulator's default control travel is the manual's **high rate**, with trim added by the session. For a transmitter's low-rate setup, use approximately 39.5% aileron, 58.9% elevator and 58.2% rudder of these angular maxima. Verify actual endpoints in input diagnostics; do not apply the reduction twice. The keyboard has no aircraft-specific dual-rate switch in this step.

| Surface | Manual high/low linear travel, each direction | Derived high/low angle | Low/high angular ratio |
| --- | --- | --- | --- |
| Aileron | ⅝ / ¼ in | 17.601° / 6.947° | 0.394705 |
| Elevator | 1¼ / ¾ in | 23.922° / 14.081° | 0.588627 |
| Rudder | 2½ / 1½ in | 30.026° / 17.472° | 0.581888 |

Angles use `asin(linear_travel / local_control_chord)` from the measured hinge geometry. Thus reducing angular travel by exactly 40%/60%/60% does not reproduce the manual's linear low-rate travel. No expo is prescribed by this audit. The source manual recommends low rates for takeoff and normal flight; high elevator can intentionally stall/snap the model. These are simulator setup instructions, not a real-aircraft setup recommendation.

Regenerate from the repository root:

```sh
python assets/aircraft/extra-300s-60/compile_geometry.py
python research/extra-300/ex05/derive_physics.py
python assets/aircraft/extra-300s-60/compile_geometry.py --check
python research/extra-300/ex05/derive_physics.py --check
```

The new installation test joins `app/test.sh`; `test_extra_handling.gd` retains its existing tolerances. The research probes exercise the actual flight session with explicit scripted controls and write metrics rather than asserting unmeasured aircraft performance. Run each probe against a separately imported app snapshot to compare physical changes. All reported rates are body angular rates unless explicitly stated otherwise; integrating body pitch rate is not, by itself, proof of a planar loop.

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
