# Atmosphere evidence tools

## Directional cloud relief (L4c)

`l4c_verify.py` runs native Compatibility captures with exact zero-strength,
repeat, clear-sky and ground parity, plus an aircraft-interior guard allowing one
8-bit level for mixed MSAA coverage. `--profile` instead runs
three alternating pairs of ten-second warmups and sixty-second samples at 720p
and 1080p; only 720p has the predeclared incremental GPU budget. The always-updating
off-screen viewport renders the production field, sky and aircraft through the
real GPU. It isolates static rendering, not whole-flight performance.

`l4c_integration.py` exercises the actual app entry, 721-sample flight traces,
both time-of-day routes and an exported Windows pack. Both tools require a fresh
`--out`, `--godot`, `--baseline` app directory and `--app` candidate directory.
Use the isolated evidence dependencies in `l4c_requirements.txt`; do not upgrade
the project's existing visual environment. Full commands, sources, budgets and
limits: [L4c report](../../docs/research/visual-quality-implementation/L4c/README.md).

## Existing sky and shadow checks

`check_phase6.py` captures and checks the L4b sky and cloud-shadow A/B using the production field, `Atmosphere`, and `ShaderClock` paths. `capture_phase6.gd` is its Godot render script.

Run from the repository root with a fresh output directory:

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l4b-atmosphere
```

The default set compares production strengths with a legacy view that zeros the cluster, cirrus, silver-lining, directional cloud-relief, and ground-shadow terms. Both retain the existing fair-weather cloud deck. It renders 15 views per mode at t=0, 10, and 120 s, plus a two-time high-ground shadow-off control. Each mode runs twice in a fresh process. The checker requires byte-identical repeats, validates camera and knob metadata, measures same-camera A/B deltas and cloud drift, and confirms that the enhanced ground crop changes against an otherwise identical zero-shadow control. `--baseline-app /path/to/frozen/app` additionally captures the pre-Phase-6 code in legacy-only mode and requires its PNGs to match the candidate's zero-strength legacy images. `--legacy-only` runs just that compatibility capture against an old project with no Phase 6 uniforms.

Use `--shadow-strength 0.6` only for a diagnostic enhanced-mode capture; the default reads the value from production `Spec.ATMOSPHERE`. The built-in shadow-off control always sets that one ground uniform to zero while retaining the enhanced sky and all other production parameters.

`--grading` adds a third 15-view mode with Environment adjustment enabled at brightness 1.0, contrast 1.04 and saturation 1.02. It compares those estimated values with the normal enhanced mode. Adjustment stays disabled by default. The summary includes per-file SHA-256 hashes for runtime app sources/assets and both capture producers, and the run fails if any of those files change while captures are being produced.

`check_cloud_probe.py` renders the shared density include into a twelve-panel GPU atlas twice. It checks finite bounded density, 64-cell periodicity, ground/sky projection, the drift wrap and a wrong-sign control. This mathematical probe complements the production shadow-off captures; it does not establish hardware performance. Its output directory can be reused safely.

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_cloud_probe.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15d-cloud-probe
```
