# Afterburner development preparation

These are isolated experiments and proposed data, outside the production application. Start with the [proposed plan](../../docs/plans/jet-afterburner.md) and [dated research index](../../docs/research/afterburner/README.md). Research reviewed `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; the original standalone prototype/receipts belong to `f41d0fd2eb5483c609bcd858bcf22776eb311e14` and Godot `4.8.beta2.official.cafc17a19`.

## Contents

- [Original core guide](prototype/core/README.md) and [visual guide](prototype/visual/README.md): unchanged 16-file standalone Godot project. Its known geometry/material limitations remain open. The original MIT [license](LICENSE) and copyright notice apply to the supplied starter.
- [Visual-study fixtures](development/README.md): three proposed art profiles and 34 planned capture cases, all `not_run`; not accepted aircraft JSON or implemented editor resources.
- [Physics arithmetic](round2/physics_evidence/analytic_cases.py), [audio arithmetic](round2/audio_evidence/probe.py), [graphics inputs/results](round2/graphics_evidence/projected_size_phase.json), [shader/geometry arithmetic](shader_evidence/analytic_probe.py), and [image diagnostics](workflow_evidence/diagnostic_examples.py): synthetic examples and saved results, not flight or GPU measurements.
- [Texture costs](tools_evidence/texture_costs.json) and [exact-pin engine-source metadata](tools_evidence/pin_source_metadata.json): explicit assumptions and inspected code identities.

## Reproduce numerical examples

Run from the repository root:

```sh
python3 research/afterburner/round2/physics_evidence/analytic_cases.py
python3 research/afterburner/round2/audio_evidence/probe.py
python3 research/afterburner/shader_evidence/analytic_probe.py
python3 research/afterburner/workflow_evidence/diagnostic_examples.py
```

The first three use standard Python. The final program saves its numeric JSON and, when Matplotlib is available, an optional locally generated PNG; that illustrative plot is ignored and is not native visual evidence. Programs that regenerate companion outputs may change the working tree; compare numerical scope and dependency versions before treating a formatting change as a result.

## Original Godot fixture

Open `research/afterburner/prototype/project.godot` with the project's pinned engine. It is a separate fixture with its own clock/slider, not the production JET or accepted flight adapter. Historical commands in the original guides/receipts describe the original execution. Future headless runs follow the current [tool index](../../docs/tools/README.md) and [test-queue contract](../../tools/testqueue/README.md); graphical captures require a real renderer and the owning native workflow.

The [verification record](../../docs/research/afterburner/2026-11-15/verification.md) separates original 97-core/14-visual-state checks from unperformed rendered, audio, flight and hardware gates. No engine or simulation was run to import this material into GitHub.
