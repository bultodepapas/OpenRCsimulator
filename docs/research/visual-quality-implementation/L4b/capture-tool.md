# L4b capture tool

Date: 2026-10-07. **Status: guarded capture evidence passed; owner-GPU visual review remains open.** This note documents the L4b capture/check entry point.

## Capture contract

The harness builds `FieldLoader.DEFAULT_PATH` through `FieldBuilder.build`, uses `Atmosphere.environment()` and `Atmosphere.create_sun()`, and advances both `ShaderClock` and `Atmosphere.update_clouds()` at t=0, 10 and 120 s. The production sun remains at 225° azimuth and 45° elevation. Scenery is disabled so the evidence isolates the production field, sky and ground.

Each mode captures four pilot-height views toward and away from the sun at camera pitches 10° and 45° up, plus a 140 m view pitched 15° down toward the sun. The legacy mode zeros the new cluster, cirrus, silver-lining and cloud-shadow strengths while retaining the existing base cloud deck. Enhanced mode reads the configured production values. The optional `--shadow-strength 0.6` override is diagnostic; default acceptance uses the value from `Spec.ATMOSPHERE`.

Two fresh processes render the complete set. The checker requires the PNGs and manifests to match byte for byte, checks all capture IDs and camera metadata, records image deltas for each legacy/enhanced pair, and measures t=10/t=120 drift against t=0. At each requested time it verifies the sky offset against `Atmosphere.cloud_offset` and the `ShaderClock` time. The high-ground lower-70% t=120 drift check confirms that the ground view changes. A separate shadow-off control renders the same enhanced sky and ground parameters at high-ground t=0 and t=120 with only `cloud_shadow_strength` set to zero; changed pixels in the lower 70% crop prove the ground-shadow contribution independently of sky or ambient changes.

`--grading` adds a third mode with estimated Environment adjustments (brightness 1.0, contrast 1.04, saturation 1.02). It compares the graded captures with normal enhanced output and leaves adjustment disabled in the production defaults.

## Reproduce

From the repository root, use the pinned Godot and visual Python environment:

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l4b-atmosphere
```

For the optional grading experiment, add `--grading`. To expose cloud-shadow projection in a diagnostic run, use `--shadow-strength 0.6`; production runs use the configured value. The summary records SHA-256 hashes for runtime app sources/assets and the two capture producers before and after rendering, and the checker fails if any change during the run.

To compare against the frozen pre-Phase-6 build, pass its Godot project directory:

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py \
  --app app --godot "$(app/get-godot.sh)" \
  --baseline-app /tmp/openrc-l4b-baseline/app --out /tmp/l4b-atmosphere
```

The baseline route uses `--legacy-only` internally, so it does not require Phase 6 uniforms. Exact baseline parity checks whether the candidate ground shader with cloud-shadow strength zero preserves the previous field render. The command writes captures and `capture-summary.json` under `/tmp`; the output directory must be fresh and nonempty output paths are rejected. The summary is written only after all checks pass.

This is deterministic software-renderer verification. It does not establish visual preference, quality on the owner's GPU, or frame time there.

## Initial baseline smoke and fix

The first candidate smoke, captured before the ground BRDF correction, matched the frozen baseline in 6/15 views. The other nine differed only in the ground region; for example, `sun-up10-t000` changed 254,981 pixels (27.67%; mean absolute RGB delta 0.645; p99 max-channel delta 9), and `antisun-up10-t000` changed 296,103 (32.13%; mean delta 8.219; p99 47). Inspection found the custom ground shader omitted an explicit diffuse mode and therefore used Godot's Lambert fallback while the previous `StandardMaterial3D` rendered Burley. The candidate's ground shader was corrected to Lambert, and the follow-up pair matched all 15 frozen-baseline legacy captures byte for byte. The initial mismatch was a useful parity failure; shadow appearance is measured separately by the enhanced-vs-shadow-off crop gate.

## Guarded evidence run

The final run used Godot 4.7.2 Compatibility on Mesa llvmpipe. It rendered 94 candidate images across two repeats (legacy 15, enhanced 15, shadow-off 2, graded 15 per repeat) and 30 frozen-baseline images. Every candidate mode and the baseline was byte-identical across repeats; all 15 zero-strength candidate legacy images matched the frozen baseline byte for byte. The enhanced lower-70% ground crop changed 517,329 pixels from t=0 to t=120. Against the shadow-off control, the same crop changed 229,058 pixels at t=0 and 317,629 at t=120. The grading A/B changed all 15 cases.

The run output is `/tmp/l4b-atmosphere-final-20261007a/capture-summary.json`. Its source guard passed before and after all captures: candidate runtime file-map SHA-256 `d335a606d25e4444da2525e636c1cc3c033ff29072b6545ea1ed2bcc42453fa8` (253 files), frozen baseline `0a6fca680c51b8c420d6885731e77b35d1708d6ecdc1bc67ac18873bf01f1093` (252 files), and capture-producer map `b46c0cbf933de1de2d91621b62d93668bdd611d1e4527ff7e0fc398032ae9050`. The exact input was the frozen `/tmp/openrc-l4b-candidate/app`; it predates the later global-registration-order fix made in the shared and export trees. These hashes pin the sources used for this evidence run.

The run is deterministic software-renderer verification. It does not establish visual preference, quality on the owner's GPU, or frame time there.
