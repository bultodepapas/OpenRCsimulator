# AV-14…17 Avanti realism checks

2026-10-12 · Software verification of the experimental original SebArt A200 / 2017 P100-RX. These tools do not establish agreement with a measured aircraft.

From the repository root, use the pinned Godot 4.7.2 executable. Preserve the pre-change app separately; never run a baseline label against current files. Each probe refuses an existing output path and records source hashes, engine errors and execution identity.

```sh
python3 research/avanti-s/av14/test_geometry_inventory.py
python3 research/avanti-s/av14/test_sensitivity.py
python3 research/avanti-s/av06/derive_physics.py --check
python3 research/avanti-s/av06/sensitivity.py
python3 research/avanti-s/av14/run_probe.py --godot "$GODOT" --app "$BASELINE_APP" --probe envelope --hz 240 --output baseline-240.json
python3 research/avanti-s/av14/run_probe.py --godot "$GODOT" --app app --probe envelope --hz 240 --output candidate-240.json
python3 research/avanti-s/av14/run_probe.py --godot "$GODOT" --app app --probe lifecycle --hz 240 --output lifecycle-240.json
```

Repeat the envelope and lifecycle commands at 480 Hz. Use the same probe scripts for both app versions. The envelope reuses the P-51 full-session/reducer pattern and Extra's trim/trace helpers, with Avanti-specific identity and scenarios. World-flight-path metrics are independent of the body-pitch integral. Turbulent cases are descriptive; changing timestep may change the sampled stochastic realization.

Lifecycle replay uses native Variant bytes, as required by the production checkpoint contract; JSON is diagnostic output. Use the evidence files ending in `-native.json` for the final lifecycle result. `pitch_sweep` is an additional runner probe choice for the eight signed elevator inputs. Recreate the saved trajectory figure with `python3 research/avanti-s/av14/plot_pitch_sweep.py` (Matplotlib 3.11.1).

Run `run_benchmarks.py --godot "$GODOT" --baseline "$BASELINE_APP" --candidate app --out timing` only with other simulation jobs stopped. It alternates baseline/candidate/candidate/baseline trim and stalled costs. The recorded host observation is not a low-end hardware guarantee.

Full checks: `app/test.sh` in an isolated LF checkout. The existing `research/p51/p51-15/run_suite.py` can preserve a failing full-suite log and continue the remaining checks for diagnosis; its continued result is still a failing suite. Use independent user-data directories and record unrelated baseline failures explicitly.

Evidence and limitations: [AV-14…17 report](../../../docs/research/avanti-realism/README.md). Work ordering and acceptance: [Avanti plan](../../../docs/AVANTI-S-PLAN.md#3-steps).
