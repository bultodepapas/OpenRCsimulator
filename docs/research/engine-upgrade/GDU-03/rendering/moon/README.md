# GDU-05c: moon radiance invariant

2026-10-25, Windows x86-64, NVIDIA GeForce RTX 3090, native OpenGL Compatibility,
actual 1920×1080 fullscreen. The existing [FW-MOON-01 cost-amplifier
probe](../../../../field-world/FW-MOON-01/README.md) supports the radiance-unused
invariant on official Godot `4.8.beta1.official.4d10419ca`, with the same result
on `4.7.2.stable.official.ed1daf0bf`. No runtime source or accepted data changed.

The unchanged `bench.gd` inserts a configurable loop only inside
`AT_CUBEMAP_PASS`. Changing `moon_dir` every frame should repeatedly execute that
loop when ambient lighting uses SKY. With ambient COLOR and reflections
DISABLED, the field-world configuration behind `World.radiance_unused()`, it
should not. The SKY positive control distinguishes this from an ineffective
amplifier or a shader that did not compile.

| Existing case | Cubemap-only iterations | 4.8 GPU p50, ms | 4.7.2 GPU p50, ms |
| --- | ---: | ---: | ---: |
| COLOR, static | 20,000 | 0.433 | 0.3865 |
| COLOR, animated uniform | 0 | 0.381 | 0.3800 |
| COLOR, animated uniform | 20,000 | 0.385 | 0.3875 |
| SKY, static | 20,000 | 0.396 | 0.3880 |
| SKY, animated uniform | 0 | 1.086 | 1.1740 |
| SKY, animated uniform | 20,000 | 6.806 | 6.8880 |

Reflections are DISABLED in every case. The amplified animated SKY control
adds 5.720/5.714 ms against its zero-iteration control. The corresponding COLOR
differences are 0.004/0.0075 ms. This is evidence for the expected rendering
path, not a claim that those small differences measure an optimization.

## Inputs and execution

The existing [bench project](../../../../../../research/field-world/fw-moon-01/project/)
was copied to separate D-drive projects. Both contain identical, unchanged
`project.godot`, `bench.gd`, `bench.tscn` and `moon_disc.gdshader` from the research
fixture, plus the current app's `sky.gdshader` and its four include files. This
includes the newer `moon_disc.gdshaderinc`; it does not reuse the historical
wrapper's pinned 2026-10-19 shaders. The original fixture configuration and
`4.7` feature string were preserved. No engine identity was relabeled.
All nine copied files still match their root source hashes after both runs.

The Linux/Xvfb shell wrapper was bypassed; its existing GDScript probe ran
directly through `tools/godot/run_checked.py`, with warnings treated as errors.
Representative Godot arguments, after the checked runner's `--`, were:

```text
<engine> --path <isolated-project> --rendering-driver opengl3 --audio-driver Dummy
  --fullscreen --resolution 1920x1080 --disable-vsync -- --mode=bench
  --case=burn_sky_uniform --burn=20000 --warmup=30 --frames=120 --out=<result.json>
```

The other fullscreen cases use 60 warm-up and 180 measured frames. The fixture
retains QUALITY sky processing, radiance size 256 and MSAA 2×. Each case runs
once per engine, sequentially; each engine has a separate import cache. TEMP,
TMP, LOCALAPPDATA and APPDATA point to the owned D-drive profile directories.

All 28 checked invocations finish with zero engine errors or warnings: two
headless imports, an initial 14-case windowed pass and 12 fullscreen cases.
Windows constrained the initial windowed viewport to 1920×1061; those results
remain on D and are excluded from the table. No screenshots were requested.

Other headless suites were active, so these measurements do not establish
quiet-host performance or loaded-game frame cost. Scope is Compatibility's
COLOR/DISABLED invariant, not Forward+, High realtime sky, lake reflection
probes, moon photometry or visual parity.

[Verification](verification.json) retains result hashes, distributions, exact
commands, engine hashes and checked-log receipts. [Source manifest](source-manifest.json)
retains the nine frozen input identities. Raw arrays, logs, caches and the
small orchestration scripts remain at
`D:/OpenRCsimulator-experiments/gdu03-moon-20261025/`.
