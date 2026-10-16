# RC Ground Closeup Harness

This harness captures the production Bisonte and Monster Car 2 activities on the production airfield course. It toggles only the agreed ground-surface shader controls: baseline disables the RC surface effect and restores the legacy gravel track shader; candidate enables the RC dirt and track shaders.

The native Godot renderer runs with its window positioned offscreen. Capture-only runs warm the renderer and save images without collecting timing samples. Every case records the camera, complete simulation state and identities, source hashes, mesh and material signatures, texture dimensions and source hashes, plus draw-call and frame timing arrays when timing is enabled. Session state must remain paused and unchanged across the render window. This is render-only evidence, not physical validation.

Example baseline and candidate captures:

    python research/rc-monster-truck/ground-closeup/run.py --variant baseline --output-dir docs/research/rc-ground-implementation-2026-10-15/verification/baseline --vehicle all --spawn start --spawn track_start --spawn track_rollers --camera chase --camera low-orbit --capture-only --warmup-frames 30
    python research/rc-monster-truck/ground-closeup/run.py --variant candidate --output-dir docs/research/rc-ground-implementation-2026-10-15/verification/candidate --vehicle all --spawn start --spawn track_start --spawn track_rollers --camera chase --camera low-orbit --capture-only --warmup-frames 30 --compare-dir docs/research/rc-ground-implementation-2026-10-15/verification/baseline

For render timing, omit capture-only and set bounded --frames and --warmup-frames. Samples are wall-clock time between rendered frame boundaries, with physics callbacks disabled and the session paused; they do not measure vehicle simulation cost. Use --ticks 240 to run the same ordinary throttle input sequence before capture: one neutral arm tick, resume, then 240 ticks at throttle 0.25, followed by a pause hold. No physical state is injected.

Outputs must use a new directory under docs/research/rc-ground-implementation-2026-10-15/verification/. Each directory contains the plan, manifest, per-case PNG and JSON receipt, summary, texture-source hashes, and Godot log. Candidate runs can compare exact simulation state, model and identity, solver identity, and mesh geometry against a matching baseline directory.
