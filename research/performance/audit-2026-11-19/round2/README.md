# Round-two correctness and optimization probes

These probes reproduce the baseline observations in the [round-two audit](../../../../docs/research/performance-audit-2026-11-19/round-2.md). They add controller, terrain, replay, settings, input-count and lake-math evidence to the [first reproduction package](../README.md).

**A successful run means the documented baseline counterexamples recur. It does not mean they are repaired or that performance improved.** No production source, graphics preference or aircraft data is changed by the runner.

## Run

From the repository root, with the official Linux x86_64 Godot binary pinned by `app/get-godot.sh`:

```bash
python3 research/performance/audit-2026-11-19/round2/run.py \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64 \
  --out /tmp/openrc-audit-round2-new
```

Use a **new output directory**. The runner refuses an existing directory, a different engine, a changed source manifest, altered fixture stubs, or a lake-layout extraction that differs from the original functions. Python 3.10+ and the pinned official Godot 4.8 beta 2 binary are required. No binary assets or native extension are needed. On an enrolled shared host, obtain the required test-queue admission before running; this collection used an unenrolled local environment with no configured test pool.

The runner makes two temporary projects, each with isolated XDG data/config/cache directories and a 240 Hz physics setting. It executes **12 sequential checked launches** through `tools/godot/run_checked.py`: two imports and ten probe launches. Checked receipts retain complete commands, exit/completion status, error/warning counts and log SHA-256 hashes. `audit_results.json` records raw observations, expected-baseline predicates, source/engine hashes and reproduction asset hashes. The runner refuses a missing or ambiguous receipt, a failed check or a changed log hash. Output persists for review; remove it manually when no longer needed.

| Probe | Finding | Evidence boundary |
| --- | --- | --- |
| `settings_probe.gd` | F36 | Actual Settings methods, saved display profile and calibration-file lifecycle; synthetic recommendations and calibration, fallback fonts. Method-driven Revert, Keep, expiry and close/reopen, not timed UI interaction. |
| `angle_probe.gd` | F37 | Actual float64 Angle controller, filtering and allocator; separate synthetic attitudes with zero history/rates and a laboratory static actuator-map fixture. No motor-lag dynamics or flown transition. |
| `angle_half_turn_probe.gd` | F37 subcase | Exact equivalent quaternion encodings and a nearby control at the production controller method. No ordinary-flight incidence established. |
| `replay_probe.gd` | F38–F39 | Valid airship recording through public verify in two fresh processes; separate parsed-record metadata cases call the replay component. No malformed on-disk recording is generated. |
| `input_probe.gd` | F41 | Actual input polling with counted synthetic readers, an injected verifier that confirms a synthetic gamepad, and unbound AUX. No physical device or menu interaction. Callback counts, not hardware traffic, latency or CPU duration. |
| `lake_wave_probe.gd` | F42 | Exact generated placement functions, analytic wave equation and rendering Transform3D math at local origins. No shader or GLB vertex execution. |
| `terrain_component_probe.gd` | F43 | Actual contact/crash/graded-ground methods and contact-point/disc witnesses at 0.59 m and 0.70 m CG clearance. |
| `terrain_session_probe.gd` | F43 | Actual strict and graded multirotor prepare/resume/accepted-tick paths, shipped quad/default field, valid custom ramp and intentionally overlapping research air start. |
| `custom_wave_probe.gd` | F44–F45 | Actual lake validation, physical sampler and shader-clock value; source-modeled clamp and shader equation. Chosen analytic time samples, not adjacent physics ticks or a rendered 17-minute flight. |

F40 is a conditional source finding about unavailable package identity. This package does **not** run a release executable or reproduce that failure.

## Exact sources and disclosed fixture substitutions

`fixture_sources.json` records the baseline `894357de83762ff6e0fdc47b0024e60f3d8286b7`, exact SHA-256 values for copied/reviewed production files and the checked runner, and the official engine SHA-512. The core project copies 119 production source/data files; Settings copies 32. The manifest also pins sources reviewed without executing them, including shaders and the original preferences constant. These counts do not imply every file was dynamically covered.

The original source is checked before and after collection. Substitutions are explicit:

- Two `scenery/` fixture files contain assertion-only methods. The terrain-only airship and drone cases install no scenery obstacle inventory; executing these methods fails the run. Actual ground terrain, RC-track geometry, plant, kernel, controller and data loaders remain unchanged. This does not qualify obstacle collision behavior.
- Settings receives only the exact production `Preferences.DEFAULT_PATH` constant from a small fixture. It uses fallback fonts so importing unrelated image/font assets is unnecessary. The display-preferences and calibration implementations are unchanged; the real player profile is isolated by XDG paths.
- `plant_layout_extracted.gd` contains unchanged `layout`, `_anchor` and `_too_close` functions plus their constants. The runner reconstructs it from production and compares exact text/hash. It does not instantiate aquatic meshes or run shaders.
- Between the two replay processes, the runner appends a comment to **the copied** `physics/math3d.gd`, then restores its original bytes in `finally`. The existing `.orfl` bytes are retained and compared by SHA-256. This changes the fixture source fingerprint without changing numerical implementation. That fingerprint describes only the copied dependency closure, not the shipped solver/package.

Keep fixture fingerprints distinct from release or full-checkout fingerprints. The evidence exercises the verifier's policy and selected source methods; it does not qualify every recorder, native backend, release package or platform.

## After a repair

This is a frozen baseline reproduction, not a candidate acceptance suite: intentional production edits cause its source guard to refuse execution, and corrected behavior should invalidate the affected baseline predicates. Add focused regressions in the owning production test suite and create a new manifest/evidence snapshot for a proposed repair. Preserve 240 Hz, float64 state, accepted-tick ordering, replay identities and the selected input policy.

Native execution, GPU/frame-time improvements, full-flight behavior, physical realism, 1080p presentation and native-panel Apple Silicon performance remain separate qualification tasks. Incidental checked-run elapsed times are not benchmark results.
