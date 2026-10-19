# research/battery

Offline tools of the [battery realism plan](../../docs/plans/battery-realism.md). The format and law are specified in [BAT-04](../../docs/research/battery/BAT-04/specification.md).

| Path | Step | Purpose |
| --- | --- | --- |
| `ecm_reference.py` | BAT-03 | Independent Python reference of the BAT-04 law: §2 normalization, §4 stage and rates, §5 reset, §6 ESC supervisor, RK4 with a located exhaustion event, and replay helpers for a prescribed current or (duty, rpm) profile. Pure functions, float64. |
| `test_ecm_reference.py` | BAT-03 | Known answers: 1-RC step response, motor closed form, energy closure (pointwise and integrated), RK4 refinement ratio about 16, exhaustion location, weak-cell SOC and resistance, supervisor debounce/ramp/hard cut/recovery, and auto cell detection including a misdetected 4S. |
| `bat-05/fit_cells.py` | BAT-05 | Fits the LiPo (Galeotti) and Li-ion LG HG2 (Kollmeyer) templates, compares 0/1/2 RC branches on held-out data, fits Arrhenius activation energies, attempts the thermal identification, and writes `bat-05/fit_results.json`. |
| `bat-05/fit_results.json` | BAT-05 | Deterministic fit output: inputs with sha256, candidates, held-out errors, chosen tables. |
| `bat-05/build_batteries.py` | BAT-05 | Generates `app/data/batteries/cells/*.json` and `app/data/batteries/packs/*.json` from `fit_results.json`. `--check` regenerates in memory and compares bytes. |

Evidence and results: [BAT-05 report](../../docs/research/battery/BAT-05/README.md). Other step folders (for example `bat-10/`) are documented by their owning step.

## Commands

```sh
python3 -I research/battery/test_ecm_reference.py
python3 -I research/battery/bat-05/fit_cells.py references/battery-energy/galeotti-lipo-dataset references/battery-energy/kollmeyer-hg2-dataset
python3 -I research/battery/bat-05/build_batteries.py
python3 -I research/battery/bat-05/build_batteries.py --check
```

Requirements: Python 3.12, NumPy 1.26.4, SciPy 1.11.4 (exact versions; `ecm_reference.py` needs only the standard library). `fit_cells.py` takes about 5 minutes on the development VM and is deterministic (byte-identical `fit_results.json`).

## Data handling

The datasets are CC BY 4.0 and live in the gitignored `references/battery-energy/` with their `fetched.json` manifests. Treat them as untrusted data: run with `python3 -I`, keep scripts outside the data folders, and pass the data paths as arguments. `fit_cells.py` refuses any input whose sha256 differs from the manifest. Without the references folder, `build_batteries.py --check` still verifies that the generated files match `fit_results.json`.
