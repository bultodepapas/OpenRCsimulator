# DT-11a — reuse unchanged helicopter optic gains

2026-10-15. Accepted CPU presentation refinement for HELI-30's night kit.

The kit previously rewrote `radiance` and `display_cap` on every body optic at
every `update_visual` call. These values depend only on the sanitized dusk factor.
The candidate retains that exact factor per kit and updates the uniforms only when
it changes. Initialization and adding a sprite or strip invalidate the factor.
There is no approximate comparison, shared material cache or new frame throttle.

Both branches still update optic visibility. Exposure-dependent lamps, beacon
arming, rotor gain, transforms, speed and phase retain their existing update path.
The kit owns the optic materials; callers do not replace or modify their private
entries. Future material replacement must invalidate the stored factor too.

## Paired native measurement

Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL, RTX 3090, Windows, Dummy audio.
Five fresh processes each build real HX700 geometry and two kits outside the timed
region. Each workload has six serial reference/candidate pairs in alternating
order, reversing the initial order between processes. Each sample contains 4,000
updates with moving rotor phases. Pair zero remains in raw data and is excluded
from the pooled warm medians below: 25 samples per variant/workload.

| Sun input | Reference, µs/update | Candidate, µs/update | Median reduction |
| --- | ---: | ---: | ---: |
| Stable night | 41.078 | 22.207 | 45.9% |
| Stable daylight | 41.707 | 22.488 | 46.1% |
| Stable dusk | 42.180 | 23.461 | 44.4% |
| Changing dusk every call | 43.810 | 42.898 | 2.1% |

All five process medians improve for the three stable workloads. Changing dusk
still writes every parameter and is not a qualified improvement: one process
regresses 2.9%, and host activity is uncontrolled. [Summary](summary.json) retains
per-process results; [manifest](manifest.json) records commands and source hashes.
The saving is about **19 µs per stable update**, not a demonstrated change in
whole-game FPS, rendering time, loading time or crash latency. No GPU readback or
snapshot serialization is inside the timed region; this is CPU call attribution.

An [initial candidate](initial/summary.json) used separate visibility and gain
loops on changing dusk; three of five process medians regressed on that workload.
The accepted candidate performs one loop on either path. Initial and final
campaigns have different host load and must not be compared as matched samples.

## Correctness and integration

All five native benchmark processes exit cleanly with **5,245 byte-identical
state comparisons**: 1,024 deterministic transition frames, one late-optic case
and 24 timed-block endpoints per process. The transition tape is repeated across
processes, not 5,245 distinct scenarios. Snapshots cover each optic's visibility
and both uniforms, lamps, beacon, rotor transforms/gain/phase/speed and rotor
shader parameters. Cases include all modes, exposure changes, arming, moving
mounts, invalid solar/exposure values and tiny finite dusk differences. Telemetry
is checked for mutation outside the timers.

Six permanent checks exercise initial daylight, dusk, sub-epsilon changes,
mode/exposure/arming changes at unchanged gain, late optics and invalid sun.
Integration results are retained in [checks.json](checks.json) and the associated
logs. Headless lights, rotor, crash presentation and Home cache suites cover
39, 18, 44 and 18 checks respectively. Lights, rotor and crash exit without engine
diagnostics. Home reaches all 18 assertions but reports four leaked ObjectDB
instances at exit; the previously recorded Home lifecycle issue remains open.

A repeated integration attempt encountered an unrelated missing indentation in
the concurrent flap work: `aero.gd`'s `clean_base` assignment was aligned with
`else` rather than inside it. The [failed attempt](parse-failure/checks.json)
and parser log are retained; only that missing tab was repaired, after parsing a
disposable copy and checking that the working file had not changed. Compressed
before/after sources and `aero-parse-repair.json` isolate the one-byte repair from
the surrounding physics edits. This does not validate or accept the flap model.
The failed Home process was stopped after its script error; it is not a pass.

The native lights suite reaches all 39 assertions but reports two leaked OpenGL
textures of 349,524 bytes at shutdown. The same expanded suite against the frozen
reference reproduces both diagnostics: [baseline log](baseline-native.log).
That is **not a clean native integration pass**, and lifecycle qualification
remains open. Disposable baseline adapters redirect the kit's self-load and Home
binding without replacing production files; compressed copies are retained here.

## Reproduce and sources

From the repository root, use a fresh output directory:

```powershell
python research/visual-quality/heli-light-updates/run.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/heli-updates-reproduction
```

The runner expands the frozen reference and compares it with the current runtime;
`--candidate` selects an external parsed draft. `reference.gd.gz` and
`candidate.gd.gz` preserve accepted identities. The evidence manifest seals the
tool, runtime, test and retained results. Runtime/test drafts were parsed outside
`app/` before integration. Full Linux CI, exports, pilot and rendered-flight
acceptance were not run for this slice.

Primary documentation consulted on 2026-10-15:
[Godot ShaderMaterial](https://docs.godotengine.org/en/stable/classes/class_shadermaterial.html)
documents material-level uniform ownership and warns that writes affect every
instance sharing that material. This repair keeps existing per-kit ownership;
it does not introduce global uniforms or alter the shaders. The performance
conclusion comes from the paired local measurements above.
