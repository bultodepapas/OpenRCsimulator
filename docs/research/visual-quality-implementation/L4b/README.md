# L4b · Sky and light

Date: 2026-10-07. **Status: implementation complete; final validation in progress.** Canonical step status: [LANDSCAPE-PLAN](../../../LANDSCAPE-PLAN.md). This implements Phase 6 of the [landscape improvement proposal](../../landscape-improvement-2026-10-07/README.md).

## Scope and review

Phase 5 / L7 already supplied distant forest, hills and visibility presets. Phase 6 extends the sky and adds ground cloud shadows. It keeps the existing sun, haze, exposure, terrain, field data and aircraft physics. Gate L remains a human readability and target-hardware decision.

- **Grouped cumulus:** a coarse coverage octave creates broader gaps in the existing five-octave cloud field. Both sky and ground use the same periodic integer-hash include.
- **Cirrus:** a second angular layer stretches the noise 17:1. It fades into the horizon and blends lightly over the sky.
- **Silver lining:** bounded forward scatter brightens partly transparent cloud edges near the sun.
- **Cloud shadows:** the ground projects toward an estimated 1,500 m deck and reduces direct sunlight by at most 22%. The global displacement reaches rough, mown and runway surfaces and follows the same quantized simulation time as the sky. Ambient light and haze are preserved. [L15d implementation and limitations](../L15d/README.md).
- **Grading:** an optional capture-only comparison uses brightness 1.0, contrast 1.04 and saturation 1.02. Production adjustment remains disabled; this experiment is not L6c acceptance of a global grade.

Production strengths are estimates in `Spec.ATMOSPHERE`: cluster 0.35, cirrus 0.12 and silver 0.18. The shader defaults are zero for controlled legacy comparisons. No external plugin, texture or dependency is added. [Sky details](sky.md).

## Evidence

Validation uses a frozen L7 baseline and a candidate containing only this visual change. Concurrent physics, radio and desktop-delivery work is excluded from that comparison; no reset, stash or commit is performed in the shared working tree.

Final results are recorded here after the guarded runs finish. The retained tools are [documented in the repository](../../../../tools/atmosphere/README.md). Production captures are wired into `app/capture.sh`; their summaries and hashes are part of the complete-run manifest.

## Reproduce

```sh
app/test.sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l4b-atmosphere --grading
"$(app/tests/visual-env.sh)" tools/atmosphere/check_cloud_probe.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15d-cloud-probe
"$(app/tests/visual-env.sh)" app/tests/treeline_readability.py capture \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l4b-readability
```

`check_phase6.py --baseline-app /path/to/frozen/app` also compares the zero-strength candidate against the earlier implementation. That check caught an unwanted ground lighting change during development; restoring the original Lambert fallback fixed the cause. A shader's default path must be checked against the pinned renderer, not inferred from `StandardMaterial3D` defaults.

Full dynamic wind integration remains M5-W04b work. The sky is still an angular layer without chase-camera parallax; this step does not add volumetric clouds or measured weather. Software-renderer captures establish correctness and repeatability, not target-GPU frame times or human acceptance.
