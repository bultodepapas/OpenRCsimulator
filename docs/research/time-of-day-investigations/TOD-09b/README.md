# TOD-09b — In-place scene lighting

2026-10-10 · Status: implemented and software-verified; full regression, exported interactions and 22/22 independent-process pixel pairs pass. Continuous solar progression remains disabled.

[Plan](../../../TIME-OF-DAY-PLAN.md) · [Prior consumer audit](../TOD-09a/render-update-audit.md)

## Change and ownership

Paused Apply and paired checkpoint restoration now update the existing field, Sun, Environment and Sky. They retain ground textures, surface geometry, near-grass MultiMeshes, treelines, scenery objects, animation and audio nodes. Physics, visual timeline v1 and checkpoint schemas keep their existing contracts.

[Atmosphere](../../../../app/render/atmosphere.gd) shares lighting setters between construction and updates. Sky changes preserve cloud phase; both directions of astronomical/legacy selection explicitly set the disc-occlusion flag. The field retains a scene-local list of its ground material, each fallback mown/runway copy and the near-grass material. [Field.prepare_lighting](../../../../app/render/field.gd) prepares the scenery shadow replacements; `commit_lighting` publishes the material parameters and contact-cue tint. Contact cues use black in astronomical mode and their original white material multiplier in legacy mode (their grey comes from vertex colors).

[Main](../../../../app/main.gd) keeps preparation before the physical checkpoint commit. Preparation does not mutate live materials, clouds or nodes. No frame/await separates the visual commit's consumers. Applying a new selection still requires Pause and records the existing ordered visual event. Aircraft shadow updates still use that same committed snapshot.

## Scenery shadow policy

[Scenery](../../../../app/scenery/scenery.gd) retains filtered nearby source placements and stable per-cell shadow nodes/material. A changed projection rebuilds only those shadow meshes. Alpha-only changes retain geometry. At zero strength it clears shadow geometry once, ignores subsequent invisible direction changes, and regenerates from retained placements when daylight returns. The existing distance/quality filters and bounded low-angle projection are preserved; this is still the existing estimated planar shadow, not a new physical shadow model.

Preparation allocates detached replacement meshes and validates ownership at commit. Static opaque scenery, moving parts, ambient audio and birds are not rebuilt. Scenery off is a no-op. This is an on-demand update seam; TOD-09c must schedule it from resolved solar seconds, alongside versioned progression records and lifecycle integration. No per-frame or accelerated update budget is claimed.

## Verification

`app/test.sh` completed with exit 0: 156 GDScript test programs plus the model contracts, CLI/trace checks, golden flights, complete-state 30/60/144 FPS checks and ground-contact regressions. Focused coverage includes 94 render-update checks (also run with scenery enabled), 25 scenery-shadow checks, 57 production paused-edit checks and 44 production checkpoint checks.

[Check summary and source hashes](check-summary.json), [evidence checksums](SHA256SUMS), [full test log](full.log.gz), [lint](lint.json.gz) and [scene smoke](smoke.json.gz) retain the results. The native Linux export passed the real keyboard route Home → Fly → record → Pause → Time of day → Night → Apply → Continue → stop recording with scenery [off](export-off/report.json) and [on](export-on/report.json). Both runs identify the exported binary by SHA-256.

The production paused-Apply captures pass with scenery [off](apply-off/report.json) and [on](apply-on/report.json): unchanged physical state, exact day/night/day round trip, exact repeated-night pixels, and settled first frames. The independent fresh-build matrix covers legacy, noon, night, dawn and samples immediately around sunrise/sunset. All 11 scenery-[off](render-off/report.json) pairs are exact. Scenery-[on](render-on/report.json) passes only the night pair; the other 10 pairs differ at two or three static-cell pixels, with a maximum channel delta of 4/255. All pairs retain the same aircraft transform and converge between consecutive frames.

**The exact pixel gate is now closed by the independent-process fixture:** all 22 production Apply versus fresh Main pairs match, and a stale-Environment negative control is rejected. [Closure and reproduction](pixel-verification.md), [matrix report](process-parity/report.json). The archived same-process probe retains its failed comparisons; no pixel tolerance, mask or acceptance waiver was introduced. Target-GPU/display and pilot acceptance remain open.

## Exploratory update cost

Compatibility/OpenGL, llvmpipe, Xvfb, 960×540, one software-renderer worker. Twenty-four adjacent one-second solar updates were each followed by a rendered frame; this is a synthetic workload, not a production 1 Hz scheduler. Idle samples use the same astronomical noon configuration. Small samples on a shared CPU are diagnostic only.

| Scenery | Update CPU median / p95 / maximum (ms) | Idle frame median / p95 (ms) | Update frame median / p95 (ms) |
| --- | --- | --- | --- |
| Off | 0.545 / 0.753 / 1.652 | 406.185 / 419.650 | 441.689 / 460.459 |
| On | 4.989 / 5.957 / 9.293 | 424.728 / 448.961 | 477.540 / 508.203 |

These are absolute sampled frame intervals, not an isolated GPU-cost measurement. They do not establish the proposed 720p budget. Shadow-only mesh preparation still allocates; scheduling and target-hardware worst-update cost must be established before TOD-09c enables continuous progression. The archived capture process reports two ObjectDB instances at exit. The follow-up identifies them as WAV playback objects; the independent-process visual fixture disables audio and exits without that warning. Production audio teardown is outside this slice.

## Capture oracle diagnostic

The initial capture harness paused physical ticks but resampled the airplane's frame-interpolated pose between image pairs. Its legacy comparison differed at 47 aircraft pixels; the sky and field matched. [Initial images and pixel bounds](interpolation-diagnostic/report.json) preserve that failure. The corrected harness pins an explicit physical pose, asserts transform equality, and requires consecutive completed frames to converge. Production pose interpolation is unchanged. This avoids misclassifying geometry movement as a lighting error; it does not relax the image comparison.

The remaining three-pixel discrepancy already occurs in the initial legacy no-op. Two subsequent fresh builds match exactly. Hiding moving parts, flowers or shadow batches does not remove it; hiding only opaque `cell_*` geometry does. All 48 static cell meshes have byte-identical surface arrays (12,488,904 bytes) between the original and fresh scene. Raising cells equally does not reliably remove the difference, so ground Z-fighting is **not** established. [Diagnostic controls and reproduction](static-cell-diagnostic/README.md) preserve the observations. Follow-up mesh-resource and near-plane controls identify allocation-dependent draw ordering and depth sensitivity. The independent-process fixture preserves production startup allocation and closes the lighting parity gate with the original camera; it does not change static scenery geometry.

## Next action

Proceed to TOD-09c: versioned progressing events/checkpoints, solar scheduling, lifecycle behavior and UI controls. Establish scheduling and target-frame cost before enabling the user-facing 1× rate. Continuous time remains disabled in this change.

## Reproduction

```bash
app/test.sh
OPENRC_SCENERY=on "$(app/get-godot.sh)" --headless --path app \
  --script res://tests/test_time_of_day_render_update.gd
bash research/time-of-day/tod-09b/capture_probe.sh /tmp/tod09b-render
OPENRC_SCENERY=on OPENRC_SCENERY_AUDIO=off xvfb-run -a \
  "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-08b/capture_edit.gd" -- --probe-out=/tmp/tod09b-apply
"$(app/get-godot.sh)" --headless --path app --export-release Linux /tmp/openrc-tod09b-export/openrc-simulator.x86_64
OPENRC_SCENERY=on OPENRC_SCENERY_AUDIO=off xvfb-run -a -s '-screen 0 1280x720x24' \
  python3 research/time-of-day/tod-08b/export_edit_smoke.py \
  --binary /tmp/openrc-tod09b-export/openrc-simulator.x86_64 --out /tmp/tod09b-export-smoke
```

Repeat the rendered Apply/native-export commands with `OPENRC_SCENERY=off` for the default scene. The matrix wrapper runs both modes itself.
