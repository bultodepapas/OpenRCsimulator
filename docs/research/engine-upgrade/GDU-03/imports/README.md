# GDU-03: import and numerical-input provenance follow-up

2026-10-25, audit at 15:26:57 UTC. Current root and the frozen full-suite tree
retain the numerical inputs used by the [GDU-04 comparison](../numerical/README.md).
No trajectories were rerun and no simulation source or aircraft physical data
was changed by this audit.

| Tested input scope | Files | Exact tested bytes, root / frozen | Equal after CRLF → LF, root / frozen |
| --- | ---: | ---: | ---: |
| Simulation, physics, failures and input GDScript | 99 | 70 / 70 | 99 / 99 |
| Aircraft physical JSON | 18 | 17 / 17 | 18 / 18 |

Root and `D:/OpenRCsimulator-experiments/gdu03-suite/app` match each other in
exact bytes for all 117 files. The 29 script differences against the tested
snapshot are line endings only. The one physical JSON with different line
endings is the unexercised HX700 experimental helicopter; the nine fixed-wing
aircraft's physical JSON inputs still match the tested bytes exactly.
All tested raw hashes were checked against the original numerical manifest
before comparison. Normalization is an analysis operation; `.orfl` exact replay
continues to require the original raw solver and engine identity.

## Import and measurement receipts

The lead's root `--headless --path app --audio-driver Dummy --import` check uses
official `4.8.beta1.official.4d10419ca`, completes in 15.625 seconds and reports
zero engine errors or warnings. This is the retained root import invocation;
it does not by itself qualify fresh-clone import or exported packages.

An independent recursive JSON comparison confirms that the regenerated Timber
mesh measurements differ from the pre-migration worktree only at `/godot`:
`4.7.2-stable (official)` → `4.8-beta1 (official)`. The measured 21 meshes,
49 surfaces, 42,519 triangles and every numeric measurement are unchanged.
Both the temporary measurement and the accepted measurement regeneration have
checked receipts with zero engine errors or warnings. The read-only existing
`python research/timber/tt07/derive_physics.py --check` also passes on current
root: `TT-07 Timber physics current`. This verifies both generated ideal and
finite-pack physical JSON outputs against the existing generator.

The regenerated power-insulator JSON differs from the tested numerical
snapshot only at `/reduction/godot_version`, with the same version-string change.
All geometry and reduction values remain equal. The lead's original recursive
delta receipts agree with both independently recomputed differences. This
follow-up does not qualify other regenerated presentation identities or pending
export gates.

[Verification](verification.json) retains source groups, line-ending-only paths,
old/new measurement hashes and exact deltas, the three checked Godot receipts
and the TT-07 command/log identity. All 117 per-file raw and normalized hashes
remain outside Git at
`D:/OpenRCsimulator-experiments/gdu03-provenance-audit/numeric-source-hashes.json`,
whose hash is retained in verification. No images or numerical arrays were added.
