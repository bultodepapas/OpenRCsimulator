# LU-00: landscape audit

Status: inspected before implementation, 2026-10-11. Owning plan: [LANDSCAPE_UPGRADE_PLAN](../../../../LANDSCAPE_UPGRADE_PLAN.md).

Inspected the existing L/VQ/SC/FW/TOD/CR and GP plans, source provenance, world/field/atmosphere/sky/treeline builders, scenery batching/prefabs/placement, aircraft catalog, capture workflows and actual native engine. Baseline native captures use `scenery/capture_views.gd` at 1280×720 on NVIDIA RTX 3090 / OpenGL 3.3 driver 610.88. Four catalog aircraft already have fleet snapshots. Scenery currently refuses collision flags and is not connected to float64 flight contact detection.

The first baseline suite invocation under WSL failed immediately because checked-out shell files have CRLF. No test verdict is inferred. Use an isolated LF checkout or native equivalent for validation. An initial capture command used an invalid postcard name and was stopped; the corrected production captures completed without engine errors.

- [Asset/resource audit](resources.md)
- [Scenery audit](scenery-audit.md)
- [Collision audit](collision-audit.md)

Concurrent default-setting edits appeared after the first status check. The user confirmed continuing carefully. Preserve them; ownership and exact delivery phases are recorded in the plan.
