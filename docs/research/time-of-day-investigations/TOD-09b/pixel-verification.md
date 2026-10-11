# TOD-09b — Independent-process pixel verification

2026-10-10 · Status: software pixel gate closed; 22/22 exact pairs and negative-control rejection verified.

[Implementation report](README.md) · [Renderer-context controls](static-cell-diagnostic/README.md) · [Runner](../../../../research/time-of-day/tod-09b/process_oracle.py)

## Oracle

For each scenery mode, one Main instance captures its initial legacy daylight, then applies the remaining ten configurations through the production paused-edit method. A separate engine process starts a fresh Main with each matching configuration supplied before it enters the scene tree, as Home does. No reference scene is constructed beside a running scene.

Every process disables physical ticks and pins the authoritative tick-zero pose before its first await. Captures retain the production 0.1 m near plane, 21,000 m far plane, materials, geometry and lighting curves. Shader/cloud time stays at zero; only audio is disabled. Each capture must converge across consecutive completed frames. The gate compares raw image bytes exactly and checks configuration, lighting context, physical state, airplane transform, camera and scenery options; renderer identity is recorded. PNGs retain the visual evidence; the runner removes matching raw buffers after comparison.

A negative control deliberately restores the legacy Environment after the real noon Apply while retaining the new field and Sun. Its physical and recorded-context invariants still pass, but the normal pixel gate must reject it. Production code is never mutated.

## Results

[Final matrix](process-parity/report.json): 22/22 pairs match exactly, all invariants pass, and the deliberately stale Environment fails the strict pixel comparison. All 46 saved PNGs decode to the raw pixel hashes recorded by Godot. The matrix logs contain no engine errors or ObjectDB exit warnings; Xvfb reports its unsupported V-Sync capability, and the existing aircraft-data inertia advisory remains visible. The previous full `app/test.sh` run covered 156 programs and integration checks; the hashed TOD runtime inputs remain unchanged. Repeated [focused checks](check-summary.json) pass: 94 render-update, 25 scenery-shadow, 57 paused-edit, 44 Main checkpoint and 40 visual-checkpoint checks.

## Why the oracle changed

The archived same-process matrix remains reproducibly non-exact at two or three static-cell pixels, including its initial no-op. CPU geometry matches byte for byte, but new mesh allocation reverses the renderer's order for overlapping cells. Shared-mesh and near-plane diagnostic controls remove the discrepancy; sharing only materials does not. The independent-process oracle matches startup allocation context while retaining the production camera and exact assertion. This is a correction to the comparison fixture, not a scenery or camera workaround.

The same-process reconstruction result remains a documented rendering limitation, separate from correct in-place lighting. Target-GPU performance and pilot/display acceptance are also separate; no continuous solar progression is enabled here.

## Reproduction

```bash
bash research/time-of-day/tod-09b/capture_probe.sh /tmp/tod09b-process-parity
```

This runs both scenery modes and the stale-Environment negative control. A mismatched normal pair, invalid invariant, missing report, timeout or engine error returns nonzero. The retained `render_probe.gd` is the historical same-process diagnostic and exploratory cost probe; its known scenery-on mismatch is not hidden by this wrapper.
