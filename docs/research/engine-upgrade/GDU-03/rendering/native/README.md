# GDU-05/07: native production captures and renderer restart

2026-10-25, official Godot 4.8-beta1, Windows RTX 3090. The existing
`capture_landscape_upgrade.gd` produced fourteen 1920×1080 Compatibility images:
eight daylight field/lake/vegetation/aircraft views, three sunset views and three
night-lighting views. All three checked invocations completed without engine
errors or warnings. Dimensions were verified from every PNG and report.

Representative field, lake, sunset-aircraft and night-runway views were inspected.
This is functional capture evidence, not a paired full-image equivalence result.
The existing [capture tool](../../../../../../tools/landscape/README.md) retains
the camera, lighting and scene-building contracts.

The existing production restart probe also passed Standard → High → Standard
through three real editor processes. Every stage reached Home, reported the
intended renderer, and left preferences unchanged. The Forward+ stage used
Vulkan on the RTX 3090; both child logs contained no warnings or errors.
This checks editor relaunch, not packaged relaunch or other operating systems.

[Verification](verification.json) retains engine reports, invocation verdicts,
restart-stage records and capture hashes. Raw images remain outside Git under
`D:/OpenRCsimulator-experiments/gdu03-suite/tmp/gdu03-render/`. The three copied
reports preserve raw frame timings, but concurrent headless tests exclude
performance qualification. The separate stock ReflectionProbe lifetime issue
must not be inferred fixed from a clean restart.
