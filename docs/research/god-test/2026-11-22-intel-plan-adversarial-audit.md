# Adversarial audit of the Intel performance plan

Date: 22 November 2026. Owner: VQ-07h-A2-R1 / PT1h-R15 / VQ-06 / DT-11a.
Audited `main`: `85a2475f60029a4b6b09f23f643119bceea84a45`.
Investigation branch before this revision:
`48395fac4e9ca28111dcc920494000c12142d0af`.

**Decision:** replace the earlier mechanism-first implementation ranking with
the [corrected low-end plan](../../plans/low-end-gpu-performance.md): existing
pixel controls and ground-heavy Home attribution first, a bounded Simple ground
candidate only if current attribution supports it, loading as a separate
parallel track, and remaining render
mechanisms only when active and material to the affected view. Automatic
adaptation follows trustworthy measurement and application, rather than being
a prerequisite for a manual optimization.

The lead and two source-read-only specialists examined code, the retained
measurements and the previous proposals. An independent reviewer challenged
the integrated draft and found no remaining substantive blocker after the
corrections recorded below. The lead verifies the final ledger and documentation
mechanically; that final ledger was outside the reviewer's completed scope.
This is a planning/source audit; no new performance run, host
change or runtime implementation is claimed. The
[audit ledger](2026-11-22-intel-plan-adversarial-audit.json) retains exact source
identities, issue dispositions and verification.

## 1. What changed on main

GitHub's commit comparison puts audited main 14 commits after the old runtime
source `91d7d6ddcb2182422a496036825e9113f82d2433`. The investigation's two
intervening commits were documentation-only. Thirty-eight paths changed on
main, predominantly telemetry and ground-vehicle/circuit work. Of the earlier
render-internals paths, AppRoot changes concern telemetry; the overlay manager
now uses the composed terrain where available. The ground, treeline, projected
shadow, sky, cloud-cache, reconstruction, Home-budget and calibration mechanisms
discussed here remain present.

The audit used Git objects from the exact main commit, including paths absent
from the sparse working tree. It did not infer current behavior from missing
files or from a dated plan. This documentation revision preserves unrelated
main development; it does not claim to merge or benchmark those 14 commits.

## 2. Findings that change the plan

| ID / severity | Adversarial finding and code/evidence | Correction |
| --- | --- | --- |
| A01 — high | The prior report ranked windsock scheduling, tree culling and particular shader expressions first without an affected-workload measurement. Source mechanisms establish possible cost, not its magnitude. | Move R01/R03/R04/R06 behind the current pixel/material attribution. Keep them as conditional experiments, not committed speedups. |
| A02 — high | The [retained comparison](2026-11-22-linux-uhd630-comparison.md) contains stronger screen-fill evidence: large ground-heavy Home ablations and scale sensitivity, but only 1.8–3.7 ms for a one-texture ground in the flight screen. Raw runs and GPU-poll freshness cannot be rechecked. | Reuse the evidence as a lead, preserve its limits, and separate Home from flight. Never add overlapping ablation estimates or transfer an old Forward+ cost into current Compatibility. |
| A03 — high | [Automatic policy](../../../app/render/auto_graphics_policy.gd), [display preferences](../../../app/app_state/display_preferences.gd) and [reconstruction](../../../app/render/reconstruction.gd) already implement scale choices and the recognized weak-GPU 75%/MSAA-off bundle. | Start from GFX-IGPU-01. Do not list those delivered controls as missing work or count historical gains again. |
| A04 — high | [Home budget](../../../app/render/home_render_budget.gd) is an existing independent temporary scale owner, with frame-count settling and two slow windows. Nominal 75% can become 52.5% at its floor. | Record actual state/time-to-adjust; hold it constant for material A/B and verify production adaptation separately. No second scaler. |
| A05 — high | The prior protocol's nine-case native graphical prerequisite conflicts with its own missing enrolled Linux adapter and Intel-utilization validator. No live route is configured in this workspace. | Use the smallest actually admitted existing-Intel comparison when available. Source work continues; formal hardware/presentation qualification stays open rather than being bypassed. |
| A06 — high | New automatic quality fields would exceed [calibration](../../../app/render/auto_calibration.gd)'s current identity/application scope. It samples root timing, can only shift scene level, and Low→lower clamps at Low. Unknown workload fields can match; root timing does not include every secondary pass. | Manual controls first. Extend A5-R2/R3 identity, safe apply/retest and rollback before automatic promotion. A completed verdict is not proof a changed tier works. |
| A07 — high | [Display ownership](../../../app/app_state/display_preferences.gd) infers managed values by type/value equality for strings as well as numbers. A user choosing the same value as Auto cannot record distinct manual intent under that heuristic. | New controls and every deliberately set manual-bundle field need explicit intent before shipping. Include equal numeric/string selection, atomic ownership/value persistence, restore/cancel, restart and GPU change. |
| A08 — medium | Photo grass is enabled for the default field by [field setup](../../../app/render/field.gd) → [grass binder](../../../app/render/grass_ground_material.gd), independently of the enhanced research mode. The [fragment path](../../../app/render/ground.gdshader) still fades by distance/footprint. | Reject both extremes: it is neither research-only nor six unconditional samples for every flight pixel. A simple whole material must be attributed before texture repacking. |
| A09 — medium | `scene_detail.gd`'s collision comment is stale. [Collision setup](../../../app/scenery/collision_setup.gd) passes full layout, [collision world](../../../app/scenery/collision_world.gd) builds its inventory and [scenery selection](../../../app/scenery/scenery.gd) retains collidable placements. | Preserve/test the implemented physical contract. Do not create a needless collision-decoupling rewrite from the comment. RC track is a genuine scenario setting and stays outside graphics downgrade/reset. |
| A10 — medium | Existing Off choices have different lifetimes: built meadow is hidden; an aircraft projector can retain its target; ground cloud-shadow Off leaves legitimate sky cache consumers; lighting VFX still has update work. | Define before-build, live-off, shared-owner, retention, reactivation and cancellation behavior per control. Do not assume Off means zero memory, or that retaining a bounded cache is necessarily a bug. |
| A11 — medium | Stock [lake water](../../../app/render/lake/water.gdshader) uses screen/depth refraction and a [probe](../../../app/render/lake/lake_terrain.gd). [Planar reflection](../../../app/render/lake/lake_planar_reflection.gd) is a High-only technical opt-in. | Test Simple water and actual probe cost in lake-visible views; do not count disabling already-off planar reflection as a win or remove physical water. |
| A12 — medium | General smoke quality is not player-facing; [main](../../../app/main.gd) has a technical `--smoke=off` path that avoids visual nodes/subscriptions. `_supports_show_smoke()` also derives input availability from those nodes. Lens, birds, flags, overlays and lighting already have controls. | Add smoke quality only for an attributed active workload. First separate retained equipment capability from render allocation so visual Off preserves AUX assignment, keyboard/radio/controller routing and fuel/sound semantics. |
| A13 — medium | The sixteen mechanisms mix first-use, steady rendering, optional features and small CPU work. A lower-fidelity material can improve runtime yet create more cold compilation; a cache can trade time for memory. | Separate loading and flight acceptance, keep variant/caching budgets bounded and reject moving a stall to first visible use. |
| A14 — high | “Works on low-end GPUs” had no distinct milestone, and the physics catch-up floor could be confused with a satisfactory experience. | Propose per-run 30-FPS median, p95 ≤40 ms, p99 ≤50 ms, pace and readability targets for the owner to freeze. Reproduced >50-ms gameplay stalls still fail even when explained. Retain distinct existing 60-Hz/product/presentation gates; unavailable presentation evidence stays open. |

## 3. Accepted, adapted and rejected recommendations

**Accepted:** first use the available pixel controls; give a genuinely cheaper
ground material independent quality ownership; separate loading attribution;
preserve essential cues and physical identity; account for auxiliary settings;
make Off/live transitions measurable; expose only useful finished options.

**Adapted:** the shader specialist's six-to-four texture-packing candidate stays
in the research queue, but actual pixel coverage and a simple-material result
come first. The controls specialist's tree batching proposal remains plausible,
but its contribution is unmeasured and more batches can regress CPU cost.
Projected-shadow quality should first extend the existing shadow-quality
resolver; a new independent aircraft override needs a demonstrated product need.
Water, clouds, grass and smoke are staged additions rather than a large first UI
delivery. Source-only identification never makes a feature the current bottleneck.

**Rejected after inspecting counterevidence:** an early claim that Scene Detail
currently removes collidable props relied on a stale comment; current code
preserves them. Another early claim that default-field photo grass only runs
under the enhanced research mode missed the unconditional default-field binder.
Both were corrected before integration. The final plan preserves both the
actual binding and the fragment's distance/footprint guard.

**Deferred:** broad Mobile/HDR or Mesa experiments, new upscalers, continuous
flight scaling, shader/terrain rewrites, global texture conversion, physical
scenario deletion, physics-rate changes and cross-machine qualification as an
Intel prerequisite. These do not resolve the strongest current uncertainty.

## 4. Why the new sequence is more useful

| Sequence | Player-facing purpose | Main uncertainty to resolve |
| --- | --- | --- |
| L0/L1 | Use the improved product baseline and existing scale/AA options correctly. | Is the remaining view pixel-sensitive, and what scale is actually rendered? |
| L2 | Qualify Simple ground and a small manual Very Low bundle if current attribution supports them. | Which decorative material work can be removed while preserving flight cues? Rerank if ground is not actionable. |
| L3, parallel after L0 | Shorten or split the actual blocking construction/compile/transfer interval. | Which cold/warm phase prevents usable Home or flight? |
| L4 | Reduce the next observed pass or inactive-effect cost; add only useful controls. | Is the path active, and does its whole-workload saving exceed its new overhead? |
| L5 | Make a qualified choice automatic without fighting the player. | Does the applied setting improve this valid workload and survive retest/rollback? |
| L6 | Deliver the accepted slice and retain its limits. | What has software, hardware, visual and presentation evidence actually established? |

There is no requirement to finish every research idea or global calibration
refactor before a manual Simple-ground candidate. Conversely, a passing source
review does not justify an automatic policy change. Each phase can reject its
candidate and return to the current baseline without expanding scope.

## 5. Independent integrated-plan review

The final reviewer found six implementation/acceptance gaps in the first draft.
The corrected plan resolves them as follows:

| Review ID | Challenge | Required correction in the plan |
| --- | --- | --- |
| GE01 | A manual Very Low bundle can set the same numeric/string values as Auto and silently keep automatic ownership. Settings currently detects dirty state from values or calibration reset, so an ownership-only change may not enable Keep. | §4.3/L2.4 treats ownership-only edits as dirty and atomically releases ownership of every deliberately set field, with restart/GPU-change and failure/Revert/Close/expiry tests. It does not wait for L5. |
| GE02 | A median-only target and “unexplained stalls” wording cannot decide whether low-end usability passed. | §3 states provisional per-run tails, repeatable-stall rejection and cue review; the owner must freeze the checkpoint before acceptance. Physical presentation and 60-Hz release qualification remain separate. |
| GE03 | A mandatory Simple-ground delivery could survive negative current attribution; one failed candidate could end the whole investigation. | L2.1 now stops that candidate and reranks if ground cost is inconclusive/negligible; L6.3 rejects individual candidates and preserves unmet release gates. |
| GE04 | An “accepted candidate” required the hardware test that was itself needed to accept it. | L6.2 now starts with a software-ready provisional candidate. Offline work can proceed, but performance promotion and qualification require admitted evidence. |
| GE05 | Copying technical smoke Off would suppress equipment input availability. | L4 requires capability state independent of visual nodes, with AUX, keyboard/radio/controller and reactivation checks before a smoke-quality option. |
| GE06 | Saving 75% while retaining a non-Native provider would not apply that scale. | The explicit bundle selects Native and lists that touched choice; preview/Keep/Revert covers provider settings and actual effective scale. |

The missing draft ledger link is resolved by the companion JSON file. These
are plan corrections, not claims that the corresponding runtime contracts have
already been implemented.

## 6. Research and verification scope

The lead checked current main, the retained Intel reports, existing settings and
the material/ownership boundaries. Fresh primary-source queries checked
[resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html),
[bounded shader variants](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/shader_preprocessor.html),
[bottleneck methodology](https://docs.godotengine.org/en/latest/tutorials/performance/general_optimization.html)
and [3D culling/LOD](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).
They motivate experiments; the pinned application/engine establishes what is
implemented. The previous ledger retains the deeper Intel/GL evidence.

Verification for this documentation-only revision covers source identities,
main-versus-research differences, independent review resolution, local links and
anchors, dependency/order consistency, arithmetic and whitespace. It does not
include Godot execution, new GPU measurements or full CI. The original raw
campaign remains unavailable here; current hardware configuration is not
inferred from the dated report. The audit makes no claim that the Intel card is
defective or that Proxmox/driver changes would recover a specific amount of time.
