# VQ-04b-S06: bounded Native shelter shadows

2026-10-31. This is a partial structure-coverage step in the [shadow plan](../../../../plans/shadows.md),
following the [settings and ownership slice](../S01-S03-2026-10-31/README.md).
Native remains opt-in. No default, physics, asset geometry, dependency or C++ backend changes.

## Implementation and scope

`shadow_field_policy.gd` admits at most two visible, opaque `Scenery/PitShelter_*` meshes using the
existing shelter shader. It checks the entire transformed horizontal AABB against the existing
100 m pilot range, orders eligible shelters by distance with a name tie-break, and excludes
overlays, next passes, foreign shaders and multi-surface meshes. Discovery runs at attachment or
manager replacement, not each frame. Auto, Projected and Off restore the exact previous casting
flags. A shelter-only field also retains its policy without a projected-shadow manager.

The production fixture selects ten source meshes, including two shelters, across three scenery
cells, with no population batches. Existing downloaded shelter geometry/materials are reused.
People, foliage, distant structures and other excluded sources still do not gain Native coverage.

The implementation is in `d27406a8f76f6ffb0a24dd6a963863b1bf9b7249`. Native capture inputs use that
snapshot. The later suite snapshot also includes the current missing-field-metadata guard,
Graphics action-row layout, and expanded cue-lifecycle tests. The compact source receipts distinguish
these inputs; concurrent CI/release changes are outside this campaign.

## Native 1080p observations

Forty images cover matched before/after Native views and current Auto controls. All outputs are
1920×1080, 4× MSAA, scale 1.0, on Windows with official Godot 4.8-beta1 (`4d10419ca`), RTX 3090,
driver 617.42. Standard uses Compatibility/OpenGL 3.3; High uses Forward+/Vulkan 1.4.351.
Only the field policy is replaced by its `28d6a4b77` version for the before controls. Each comparison
keeps the engine, assets, lighting and camera fixed. One rendered application runs at a time.

Six views cover flightline, windsock, aircraft near the ground, pilot, pavilion and lake. Separate
pavilion pairs use astronomical 08:00 lighting. Inspected pavilion pairs show the shelter roofs
shading their slabs, nearby ground and objects below; the former sunlit pit area is now grounded
by its roof and post shadows. This is static rendered evidence, not a motion or performance gate.

| Comparison | Standard | High |
| --- | --- | --- |
| Native pavilion, before → after | 27,571 changed pixels | 25,967 changed pixels |
| Native morning pavilion, before → after | 13,525 changed pixels | 14,535 changed pixels |
| Native pilot, before → after | Exact | Exact |
| Auto versus original pre-settings baseline | Four views exact; flightline 26 pixels, maximum 4/255; lake 658 pixels, maximum 1/255 | All six images byte-identical |

These whole-image counts include any producer variation; they are not a shadow-quality score.
Native lake differs by 920 one-step pixels in Standard and is exact in High. No tolerance is widened.
The existing High `Texture` RID shutdown warning and `OpVectorExtractDynamic` messages also appear
in the control campaign; this work does not claim to repair those renderer diagnostics.

## Lifecycle and software checks

Six focused checked-runner invocations pass **276 assertions**, with zero engine errors or warnings:
ownership 49, cue controls 49, projected geometry 43, windsock 22, field projections 59 and settings 54.
The new standalone-projector checks cover global position/basis after detached construction,
hidden ancestors, whole-subtree detach/reattach with changed transforms, and a source first entering
an already-live projector. They deliberately avoid a carrier or field owner repairing the fixture.

The small Standard flightline difference remains unresolved. The following discarded-variant results
are exploratory observations: complete run-time variant source receipts were not retained. The
[comparison receipt](exploratory-controls.json) verifies the retained images, not reproducible source
attribution or candidate qualification. Removing the source-entry connection
in a disposable control leaves only one one-step pixel versus the original baseline. Keeping the
connection while suppressing its initial refresh still leaves the larger difference, so a premature
refresh alone is not an established cause. A generic readiness guard without a ready-time replay
fails three new assertions: initial global position, basis and ancestor visibility. Adding the replay
passes all 49 checks but does not eliminate the image difference. These speculative runtime changes
were rejected; production entry/reattachment behavior remains unchanged.

The first isolated import failed with a missing cached extension reference, three `get_multiple_md5`
errors and a nonzero process exit. The retry completed with three MD5 errors and was correctly rejected
despite exit 0. The subsequent import passed with zero errors/warnings. Failed reports are retained
separately from successful focused checks; the cause of the import MD5 errors is not established.

Full application and visual suites are being checked against isolated snapshots. Their final status
belongs here once the invocations finish; the focused checks above are not a full-suite pass.

## Evidence and reproduction

Raw images, producer reports, rejected controls and checked logs are outside Git in
`D:/OpenRC-shadow-followup-20261031/tmp/shadow-followup/`. The original before-settings images were
copied into `original-baselines/`. `run_captures.ps1` records the exact paired capture commands, and
`compare_captures.py` records full-image differences without exclusions. The
[graphics tool guide](../../../../../tools/graphics/README.md) owns the producer's supported options.
No screenshots are committed.

Compact receipts retain the [40 image identities and comparisons](captures.json),
[checked invocations](checks.json), [capture source](capture-source.json),
[Windows suite overlay](suite-source.json) and [Linux suite overlay](linux-source.json).
The invocation collection labels failed imports and deliberate mutation controls separately.
All 40 image hashes and 44 local documentation file targets were verified; `git diff --check` passed.

The earlier `D:/OpenRC-shadow-verification2-20261031` temporary snapshot was no longer present at
resumption. Its unfinished readiness experiment was not treated as evidence. This campaign uses a
new worktree and fresh outputs. The previous Linux partial captures were preserved at
`/home/bulto/OpenRC-shadow-visual-20261031/tmp/shadow-followup-previous-captures` before the new suite.

Remaining S06 work includes animated and alpha-tested sources, LOD/range transitions and owner-specific
coverage. S11 still requires moving-flight, camera, resource and uncontended performance evidence
before preset/default promotion. No speedup or new C++ efficiency claim is made.
