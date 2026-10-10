# EL1e — Synthetic electric product path

2026-10-10 · **Status: synthetic product-path checks pass; physical validation remains open. Step prefix: EL.**

Both explicit demo routes load the synthetic Stik electric configuration through the real main scene. The test drives a fake radio at device 15 and checks SAFE zero current, fresh-low arming, full throttle, unplug pause and shaft freeze, keyboard resume/throttle, and `R` reset. Each configuration passes 16 input checks. The ordinary app suite's no-argument path also passes six checks across both data files: electric coupled-session selection, disabled-source zero current, and reset to powered trim.

The real app reaches 480 simulation ticks at 30, 60, and 144 rendering fps. Complete checkpoint SHA-256 is identical across all three rates for each configuration:

| Configuration | Exact input-file SHA-256 | 30/60/144 fps checkpoint SHA-256 |
| --- | --- | --- |
| Synthetic Stik 4S | `80ee03c81260f4933158a8d1f2c394745d030f1ed5130f1897b4bc9fac3f3460` | `e636411ca829ad349490339bb688ed225fd6c76600838275325aa433584858d7` |
| Synthetic Stik 6S | `ffe8c6667c582c4e12355c9cd8803f7ea09fc563d57aee08247fd72a48986e06` | `07f49cb96a851d9d07fe9027a6ad8498cc148753600ee159e25efd888098239d` |

The pinned Godot 4.7.2 Linux template was already installed. One release export, with the existing embedded PCK preset, ran from separate empty working directories for 4S and 6S. Each emitted `openrc-trace v7`, identified the corresponding exact input-file hash and `electric-fixed-bus-coupled-stop-v1` with `coupled-rk4`, and recorded 49 contiguous rows from tick 0 through 48 at 240 Hz. The exported binary SHA-256 is `48b1498572bba642af32e2ed54ad6f34f621befb0d0ec5da7771237cea57eb60`.

Reproduce the full input, frame-rate, export, and packaged-trace checks from the repository root:

```sh
python3 research/propulsion/el1/product_check.py
```

The runner writes commands, logs, traces, hashes, and a machine-readable result to `/tmp/openrc-el-product/`; its summary is `product-check.json`. The two synthetic files report their inherited-Stik inertia provenance warning. The manual export reports that `OPENRC_BUILD_*` was unset and labels the build `export-manual`; no engine errors occurred. These checks establish software integration and packaging only. They do not validate a physical electric conversion, Timber hardware, or aerodynamic/electrical accuracy.
