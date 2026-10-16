# AVL 3.52 wing reference and panel sensitivity (2026-10-16)

This folder retains the AVL inputs, command tapes, raw text outputs, scripts and summaries for a wing-only model comparison. It is software/model-form evidence, not physical qualification. The downloaded AVL guide and executable are not included. AVL 3.52 for Windows is available from the [official MIT AVL page](https://web.mit.edu/drela/Public/web/avl/); the exact executable used is identified by URL and SHA-256 in [`hash-receipt.json`](hash-receipt.json).

## Interpretation correction

The earlier interpretation that assigned `+0.0002584` to circulation/downwash was incorrect. In the zero-camber D11f reference at α=11°, the local [`check_reference_split.json`](check_reference_split.json) gives `circulatory_cnr = 2.7441579e-16` (numerically zero), `profile_cnr = -0.0138064046`, and the same total to rounding. The `+0.0002584` is the change in the analytic profile term between α=0 and α=11°: `-CD0/3 × (1 − 1/(4·3²)) × cos(α)`. The original D11f raw log is retained unchanged in the sibling [`d11g-repair`](../d11g-repair/) evidence.

## Matched panel-count sensitivity

`run_matched_wing.py` maps the six production strip-`CL0` inputs to a uniform fixed equivalent-incidence value of 1.3420266°. This is an approximate model match, not measured airfoil camber. The 6-panel α=0 AVL result is `CLtot = 0.09901`, while the input mean strip intercept is `CL0 = 0.09885846`; these are different aggregate measures and do not match exactly. The retained [`matched-summary.json`](matched-summary.json) reports these α=11° results:

| Panels | Profile `CD0` | `Cnr` | `CLtot` |
| ---: | ---: | ---: | ---: |
| 6 | 0.0434 | −0.013486 | 0.89501 |
| 20 | 0.0434 | −0.013971 | 0.83941 |
| 80 | 0.0434 | −0.014034 | 0.81921 |
| 6 | 0 | +0.000323 | 0.89501 |

With profile drag included, changing from 6 to 20 panels shifts `Cnr` by −0.000485; 20 to 80 shifts it by −0.000063. The 6-panel inviscid row also shows the profile-drag sensitivity for that discretization. These are model and discretization sensitivities; they do not identify a physically correct force law or establish aircraft-level validity.

## Retained files

`run_wing.py` records the zero-camber 6/20/80-panel AVL runs; `run_matched_wing.py` records the matched-incidence/profile variants. Their `.avl` inputs, command tapes, per-case body/force outputs and console logs are kept byte-for-byte. `check_reference_split.py` and its JSON output record the D11f analytic profile/circulation split. The matched-comparison JSON input is copied under [`inputs/`](inputs/) and its canonical source and hash are listed in the receipt. The scripts are preserved as run; `run_matched_wing.py` and `check_reference_split.py` contain the original checkout paths used during this capture.

`hash-receipt.json` lists SHA-256 and byte length for every retained file except itself, the AVL executable URL and hash, excluded downloads, and the hashes of the linked source inputs.

## Rerun in a fresh working directory

Run on Windows in a newly created, empty temporary directory; do not run into this retained evidence folder or a prior run directory. The matched script uses `mkdir` for its case folders and the flat-run script rewrites its outputs. Copy only `run_wing.py`, `run_matched_wing.py`, `check_reference_split.py`, and `inputs/yaw_r02_vs_kj_comparison-v4.json` into the fresh directory. Also copy the canonical [`research/aero/d11f/wing_yaw_damping.py`](../../../../../../../research/aero/d11f/wing_yaw_damping.py) to `inputs/wing_yaw_damping.py`; its SHA-256 is recorded in the receipt. Download `avl352.exe` from the official MIT page, place it beside the scripts, and verify the receipt hash.

The preserved scripts contain absolute paths from the original checkout. In **disposable copies only**, set `run_matched_wing.py`'s `comparison_path` to `base / 'inputs' / 'yaw_r02_vs_kj_comparison-v4.json'`, and set `check_reference_split.py`'s `source` to `Path(__file__).resolve().parent / 'inputs' / 'wing_yaw_damping.py'`. Leave the scripts in this evidence directory unchanged. Then run, in order:

```powershell
python run_wing.py
python run_matched_wing.py
python check_reference_split.py
```

The first script creates the 6/20/80-panel zero-camber inputs and raw runs, which the second script uses to build the matched cases. The final script writes a fresh split-check JSON beside its disposable copy. Use another empty directory for each rerun so no retained output is overwritten.
