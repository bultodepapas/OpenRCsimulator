# P51-06: propeller and engine of the P-51D 1/4

2026-10-06. Report: [docs/research/p51-flight-realism.md](../../../docs/research/p51-flight-realism.md).

| File | What |
| --- | --- |
| `bem.py` | Blade-element/momentum propeller model (Prandtl tip loss, geometric twist, generic section), with two calibration factors: effective pitch and chord scale. Shared by `derive_physics.py` and the fit. |
| `mejzlik_26x12.json` | Mejzlik's 26x12 2-blade and 3-blade gas tables (Ct, Cp at 12 advance ratios; manufacturer-simulated at 5400 rpm, Rev. 3.0) transcribed from the datasheets, with URLs and SHA-256 of the PDFs (kept in the gitignored `references/p51-mustang/propellers/`); and the 28x10 static Cp with the measured static rpm on a DA-120 that anchors the engine. |
| `fit_mejzlik.py` | Fits pitch and chord factors to both 26x12 tables together (J ≤ 0.76, errors relative to the static values) and predicts the 4-blade. Writes `calibration.json`. |
| `calibration.json` | Pitch × 1.441, chord × 0.581, rms 6.5 %; per-row comparison; 4-blade static Ct 0.148, Cp 0.063. |

Result. The calibrated 4-blade 26x12 absorbs about 5.5 kW at 4950 rpm static (where the installed torque curve meets it) and pushes 24 kgf. A DA-120's installed power is anchored by a 28x10 turning 6550 rpm static (Falcon spec, Mejzlik and DLE reports agree): 6.9 kW, 24 % below the 11.7 hp rating. The previous model (5751 rpm, 32.6 kgf) needed about 8.5 kW.

Limits. Mejzlik's tables are simulated, not measured. No 4-blade gas datasheet exists, so the 4-blade is a prediction of the calibrated model. Beyond zero thrust the model's Cp turns negative faster than Mejzlik's (the windmilling branch is uncalibrated). The engine's torque shape is generic (no DA-120 dyno curve is published).

Reproduce: `cd research/p51/p51-06 && python3 fit_mejzlik.py` (~20 s), then `python3 research/p51/p51-05/derive_physics.py`.
