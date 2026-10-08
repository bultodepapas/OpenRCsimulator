# E3c2b — rendered circuit review kit

**Status:** complete — offline rendered verification; owner readability and physical acceptance remain open. **Date:** 2026-10-08. **Owner:** Codex circuit-capture agent.

Open the [review kit](index.html): twelve stages of the verified E3c2a circuit, each shown from the production pilot camera and aircraft inspection camera. This supplies reproducible rendered evidence for the experimental circuit. E3c2 continuous presentation/owner review, physical validation, propwash acceptance and PT2 remain open.

## Scope

The [offline tool](../../../../research/landing/e3c2b/) renders selected recorded states through the production `main.tscn`, `_pose_of()` and `_render_pose()` functions. It changes no runtime file, force, controller, camera policy, aircraft data or replay policy. The initialized session remains at tick zero with processing disabled; only the renderer receives the recorded poses. This is recorded-state visualization, not a dynamics replay, another flight or a continuous video.

Inputs are the accepted [E3c2a CSV](../E3c2a/circuit.csv.gz) and [full verification report](../E3c2a/report.json). The existing trace reader verifies every row, timing and exact aircraft-file identity. Phase records must appear in order and agree with recorded position, altitude and speed. Selection uses those matched phase boundaries and the final trace sample; it does not trust separate liftoff, touchdown or stopping timestamps to label pictures. **Rollout entry means the controller phase**, not a newly estimated physical impact instant.

The twelve stages are parked, takeoff roll, climb, crosswind, downwind, base, final join, approach, flare, rollout entry, rollout and stopped. Each pose uses the CSV's recorded quaternion and actual servo positions. Shaft phase is not recorded: the displayed propeller angle is explicitly a visual-only trapezoidal integral of RPM starting at zero.

The kit uses the identified field and model renderer, rather than claiming to reconstruct historical pixels from the original flight. The baseline checkout was `959eb8a`; [source hashes](source-identity.json) identify the actual capture dependencies and tool code. Scenery is off. Shader and cloud clocks are fixed to each source timestamp.

## Acceptance and results

All **24 stage/view pairs** pass, with **48 PNGs per run** including airplane-only ablations. Two independent Xvfb/llvmpipe processes produce byte-identical images and capture manifests. This is software-renderer repeatability, not a target-GPU performance or human readability result.

The independent Python checker verifies:

- The source manifest hash, unique frame/view coverage, recorded ticks, timestamps and complete source state.
- Rendered CG placement within 0.03 mm, independently mapped quaternion basis within 1e-6, actual hinge rotations from recorded servos and aircraft throws, and applied propeller phase modulo a revolution.
- The fixed pilot eye, current auto-zoom formula, inspection offset, FOV and CG-centered aim; shader time and unchanged tick zero.
- Shadow visibility in both members of each pair. Only the airplane mesh is hidden, so the shadow cannot count as airplane pixels.
- Nonblank 960×540 images, visible airplane pixels, and exact repeated image bytes.

The [proof](proof.json) records 79–122 changed pixels in pilot views and 20,406–20,724 in inspection views. These are content-presence observations, **not readability thresholds**. The distant pilot views remain small and require owner review. Sampled stills cannot establish visibility, obstacle clearance or absence of visual defects between samples.

[Unit regressions](unit.log): **12 tests pass**, including wrong phase data, non-unit attitude, servo range, missing/duplicate views, pose/hinge/clock/camera/tick corruption, nonfinite metadata, path escape, absent-airplane images, changed repeat images and blank captures. [Eight corruptions of the real rendered artifacts](mutations.json) are rejected after a valid positive control. [CLI refusals](refusals.json) reject headless rendering and nonempty output directories; an existing sentinel file survives unchanged.

[Relevant app regressions](focused.log): frame conversion, shader clock and visual-evidence scripts pass **122 checks**. Godot parsing and [targeted static lint](lint.json) pass with zero errors or warnings. The full physics suite was not repeated for this offline renderer-only addition.

[First-run](first.log) and [second-run](second.log) logs record Godot 4.7.2, Compatibility/OpenGL and llvmpipe. Xvfb emits an unsupported-VSync warning; neither successful run emits engine/script errors. The first run's complete PNG pairs and manifest are preserved in [first/](first/); duplicate second-run images are omitted because their bytes are identical, with hashes retained in the proof.

## Concurrent field integration

After the full kit was captured, the visual track added a flightline barrier and cue shadows. A separate [identified snapshot](integration/source-delta.json) of those five field files was copied into the isolated checkout. Parked and rollout-entry stages in both cameras pass the same pose/image checks and repeat exactly: [four-pair proof](integration/proof.json), [capture manifest and images](integration/first/), [log](integration/first.log). The full twelve-stage kit retains its original source identity; it is not relabeled as the later field version. The barrier track subsequently revised its mesh again; these captures remain evidence for their recorded hashes. Regenerate the kit for any owner review of a newer build. Shared-checkout [unit tests](shared-unit.log) and [targeted lint](shared-lint.json) also pass.

## Reproduce

Use the repository's pinned visual environment, and a new output directory:

```sh
app/tests/visual-env.sh
.tools/visual-venv/bin/python -m unittest discover -s research/landing/e3c2b -p test_kit.py -v
.tools/visual-venv/bin/python research/landing/e3c2b/kit.py --out /tmp/e3c2b-review
.tools/visual-venv/bin/python research/landing/e3c2b/mutations.py /tmp/e3c2b-review
```

Open the generated `index.html`. The wrapper imports assets before rendering, isolates user settings, sets software rendering and one llvmpipe thread, refuses process/engine errors, and rejects source changes during capture. For concurrent development, run it from a frozen checkout. Existing outputs are never overwritten.

Fresh-checkout inspection initially exposed missing imported atlas textures. The final wrapper performs Godot's import pass before parsing/rendering; partial outputs from a failed run never become an accepted kit.

## Commit message

```text
Add E3c2b recorded-circuit render review kit

Proof: 24 stage/view pairs and 48 PNGs repeat exactly; 12 unit tests,
8 real-artifact corruptions, 2 refusal probes and 122 app checks pass.
No runtime edits; physical and owner readability acceptance stay open.
```
