#!/usr/bin/env python3
"""Reproduce the SciPy-only exploratory calculations cited in 05-08-analysis-tools.md.

Tested with Python 3.12.3, NumPy 1.26.4, and SciPy 1.11.4.
Requires those already-installed packages; it does not touch the simulator.
"""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path

import numpy as np
import scipy
from scipy import linalg, signal


def welch_ou_experiment() -> dict[str, object]:
    fs_hz = 240.0
    tau_s = 2.0
    sigma_mps = 0.5
    duration_s = 900
    seed = 20261005
    sample_count = int(fs_hz * duration_s)
    a = float(np.exp(-1.0 / fs_hz / tau_s))
    innovation_sigma_mps = sigma_mps * float(np.sqrt(1.0 - a * a))

    rng = np.random.default_rng(seed)
    values = np.empty(sample_count, dtype=np.float64)
    values[0] = sigma_mps * rng.standard_normal()
    for index in range(1, sample_count):
        values[index] = (
            a * values[index - 1]
            + innovation_sigma_mps * rng.standard_normal()
        )

    rows: list[dict[str, float | int | str]] = []
    for nperseg in (4096, 8192, 16384):
        window = signal.windows.hann(nperseg, sym=False)
        for detrend in ("constant", False):
            frequencies_hz, psd = signal.welch(
                values,
                fs=fs_hz,
                window=window,
                nperseg=nperseg,
                noverlap=nperseg // 2,
                nfft=nperseg,
                detrend=detrend,
                return_onesided=True,
                scaling="density",
                average="mean",
            )
            rows.append(
                {
                    "nperseg_samples": nperseg,
                    "segment_duration_s": nperseg / fs_hz,
                    "frequency_bin_spacing_hz": float(
                        frequencies_hz[1] - frequencies_hz[0]
                    ),
                    "detrend": "constant" if detrend == "constant" else "false",
                    "integrated_psd_rms_mps": float(
                        np.sqrt(np.trapz(psd, frequencies_hz))
                    ),
                }
            )

    lag_samples = int(fs_hz)
    lag_one_second_correlation = float(
        np.corrcoef(values[:-lag_samples], values[lag_samples:])[0, 1]
    )
    return {
        "experiment": "stationary_scalar_ou_welch_window_and_detrend",
        "parameters": {
            "sample_rate_hz": fs_hz,
            "dt_s": 1.0 / fs_hz,
            "duration_s": duration_s,
            "sample_count": sample_count,
            "seed": seed,
            "tau_s": tau_s,
            "target_rms_mps": sigma_mps,
            "window": "periodic Hann (sym=False)",
            "overlap_fraction": 0.5,
            "scaling": "density",
            "nfft": "equal to nperseg",
        },
        "observed": {
            "sample_rms_mps": float(np.std(values)),
            "lag_1_s_correlation": lag_one_second_correlation,
            "expected_lag_1_s_correlation": float(np.exp(-1.0 / tau_s)),
            "welch_results": rows,
        },
    }


def state_space_noise_experiment() -> dict[str, object]:
    fs_hz = 240.0
    dt_s = 1.0 / fs_hz
    tau_s = 2.0
    sigma_mps = 0.5
    a_matrix = np.array([[-1.0 / tau_s]], dtype=np.float64)
    b_matrix = np.array([[1.0]], dtype=np.float64)
    c_matrix = np.eye(1, dtype=np.float64)
    d_matrix = np.zeros((1, 1), dtype=np.float64)

    ad, bd, _, _, _ = signal.cont2discrete(
        (a_matrix, b_matrix, c_matrix, d_matrix), dt_s, method="zoh"
    )
    qc = np.array([[2.0 * sigma_mps**2 / tau_s]], dtype=np.float64)
    van_loan_block = np.block(
        [[a_matrix, qc], [np.zeros_like(a_matrix), -a_matrix.T]]
    ) * dt_s
    exponential = linalg.expm(van_loan_block)
    qd = exponential[:1, 1:] @ ad.T
    expected_qd = sigma_mps**2 * (1.0 - np.exp(-2.0 * dt_s / tau_s))
    ad_from_expm = linalg.expm(a_matrix * dt_s)

    return {
        "experiment": "scalar_ou_zoh_vs_exact_process_noise_covariance",
        "parameters": {
            "sample_rate_hz": fs_hz,
            "dt_s": dt_s,
            "tau_s": tau_s,
            "stationary_rms_mps": sigma_mps,
            "continuous_A_per_s": float(a_matrix[0, 0]),
            "continuous_B": float(b_matrix[0, 0]),
            "continuous_noise_intensity_qc_mps2_per_s": float(qc[0, 0]),
            "discretization_method": "ZOH",
        },
        "observed": {
            "Ad_cont2discrete": float(ad[0, 0]),
            "Ad_expm": float(ad_from_expm[0, 0]),
            "Bd_zoh": float(bd[0, 0]),
            "Qd_van_loan_mps2": float(qd[0, 0]),
            "Qd_scalar_ou_reference_mps2": float(expected_qd),
            "Qd_absolute_difference_mps2": float(abs(qd[0, 0] - expected_qd)),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).with_name("scipy-wind-analysis-results.json"),
        help="JSON result path (defaults beside this script)",
    )
    arguments = parser.parse_args()
    result = {
        "environment": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "scipy": scipy.__version__,
        },
        "experiments": [welch_ou_experiment(), state_space_noise_experiment()],
        "scope": "Exploratory offline calculations; not an app test or RC atmospheric validation.",
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Wrote {arguments.output}")


if __name__ == "__main__":
    main()
