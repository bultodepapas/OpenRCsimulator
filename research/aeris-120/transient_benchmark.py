#!/usr/bin/env python3
"""Select identified external thrust/RPM samples; offline, no aircraft-data writes."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "transient-source.json"
OUTPUT = ROOT / "transient-benchmark.json"
TARGET_RPM = 4000.0


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inspect(source_dir):
    # Read and hash the source bytes before importing optional HDF5 dependencies.
    manifest_raw = MANIFEST.read_bytes()
    source = json.loads(manifest_raw)
    require(source["format"] == "aeris120-transient-source v1", "unsupported source manifest")
    require(set(source["files"]) == {"README.md", "data_thrust.h5"}, "unexpected source files")
    originals = {}
    for name, expected in source["files"].items():
        path = source_dir / name
        require(path.stat().st_size == expected["bytes"], f"{name}: wrong byte count")
        raw = path.read_bytes()
        require(len(raw) == expected["bytes"], f"{name}: changed during read")
        require(hashlib.md5(raw).hexdigest() == expected["published_md5"], f"{name}: published MD5 mismatch")
        require(hashlib.sha256(raw).hexdigest() == expected["intake_sha256"], f"{name}: intake SHA-256 mismatch")
        originals[name] = raw
    try:
        import h5py
        import numpy as np
    except ImportError as exc:
        raise ValueError("install optional transient-requirements.txt in an isolated environment") from exc
    rows = []
    with h5py.File(io.BytesIO(originals["data_thrust.h5"]), "r") as h:
        require(set(h) == {"00", "05", "10"}, "unexpected pitch groups")
        radius, rho = float(h.attrs["R"]), float(h.attrs["rho"])
        require(radius == 0.15525 and rho == 1.2, "source geometry/normalization changed")
        for pitch in ("00", "05", "10"):
            steady = h[pitch]["St"]
            coeffs, steady_n = steady["T_fit_coeffs"][()], steady["n"][()]
            require(coeffs.shape == (3,) and steady_n.shape == (11,), "unexpected steady arrays")
            require(np.all(np.isfinite(coeffs)) and np.all(np.isfinite(steady_n)), "nonfinite steady data")
            for step, size in (("Up", 3000), ("Do", 4000)):
                group = h[pitch][step]
                t, n, thrust, delta, uncertainty, ct = [group[key][()] for key in
                    ("t", "n", "T", "Delta_CT", "Unc_Delta_CT", "CT")]
                require(all(x.shape == (size,) for x in (t, n, thrust, delta, uncertainty, ct)), "unexpected transient arrays")
                require(all(np.all(np.isfinite(x)) for x in (t, n, thrust, delta, ct)), "nonfinite core observations")
                require(np.all(n > 0) and np.all(np.diff(t) > 0), "invalid speed or time order")
                require(np.allclose(np.diff(t), 1e-4, rtol=1e-9, atol=1e-12), "unexpected time spacing")
                fit = np.polyval(coeffs, n)
                require(np.all(fit > 0), "nonpositive steady fit")
                require(np.allclose((thrust-fit)/fit, delta, rtol=1e-9, atol=1e-12), "Delta_CT definition mismatch")
                require(np.allclose(thrust/(rho*np.pi*radius**4*(2*np.pi*n/60)**2), ct,
                                    rtol=1e-9, atol=1e-12), "source CT normalization mismatch")
                index = int(np.argmin(np.abs(n-TARGET_RPM)))
                require(abs(float(n[index])-TARGET_RPM) < 1.0, "no sample within 1 RPM of target")
                require(float(steady_n.min()) <= float(n[index]) <= float(steady_n.max()), "selected fit point would extrapolate")
                require(np.isfinite(uncertainty[index]) and uncertainty[index] >= 0, "selected uncertainty unavailable")
                rows.append({"pitch_key": pitch, "step_key": step, "source_path": f"/{pitch}/{step}",
                             "index_zero_based": index, "time_s": float(t[index]), "processed_mean_rpm": float(n[index]),
                             "thrust_n": float(thrust[index]), "author_steady_fit_n": float(fit[index]),
                             "deviation_percent": float(100*delta[index]),
                             "author_expanded_u95_percentage_points": float(100*uncertainty[index])})
    return {"format": "aeris120-external-transient-result v1", "physical_acceptance": False,
            "aircraft_data_export": False, "evidence": "derived_selection_from_external_processed_measurements",
            "source": source, "target_rpm": TARGET_RPM, "rows": rows,
            "normalization": {"radius_m": radius, "density_kg_m3": rho,
                              "source_ct": "T/(rho*pi*R^4*Omega^2), Omega=2*pi*RPM/60",
                              "conventional_ct": "T/(rho*(RPM/60)^2*(2R)^4)",
                              "source_to_conventional_ct_factor": float(np.pi**3/4)},
            "limits": ["Filtered ensemble means of 500 repetitions; individual trials unavailable in this file.",
                       "Authors cubic-spline interpolated RPM onto the thrust time base; selector performs no additional interpolation.",
                       "30 Hz forward/backward filtering is noncausal; 10 kHz stored arrays are not independent observations.",
                       "First 5 ms absent; selected timestamps identify rows, not physical command-to-thrust onset latency.",
                       "U95 belongs to each deviation from the author's fitted baseline; paired covariance/uncertainty is not supplied.",
                       "Static fit and transients come from the same study; no new fit or held-out validation performed.",
                       "This apparatus cannot identify AERIS engine lag, installed 28-inch wake or a unique memory mechanism."],
            "identity": {"manifest_sha256": hashlib.sha256(manifest_raw).hexdigest(),
                         "selector_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                         "numpy": np.__version__, "h5py": h5py.__version__}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path, help="external directory containing the two identified originals")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        report = inspect(args.source_dir)
        raw = (json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False)+"\n").encode()
        if args.check:
            require(OUTPUT.exists() and OUTPUT.read_bytes() == raw, "external benchmark is missing or stale")
            print("External source identities, six selected rows and full-trace definitions match; no aircraft validation.")
        elif args.write:
            protected = [MANIFEST, Path(__file__), args.source_dir / "README.md", args.source_dir / "data_thrust.h5"]
            require(not OUTPUT.is_symlink(), "refusing output symlink")
            require(not OUTPUT.exists() or all(not os.path.samefile(OUTPUT, p) for p in protected), "refusing output alias")
            with tempfile.NamedTemporaryFile(dir=ROOT, prefix=".transient-", delete=False) as stream:
                temporary = Path(stream.name)
                try:
                    stream.write(raw)
                    stream.close()
                    temporary.replace(OUTPUT)
                finally:
                    temporary.unlink(missing_ok=True)
            print("Wrote transient-benchmark.json (external processed observations, not AERIS calibration).")
        else:
            sys.stdout.buffer.write(raw)
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
