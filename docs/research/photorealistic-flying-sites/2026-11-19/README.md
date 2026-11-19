# Photorealistic flying sites: strengthened plan and hybrid scenery

2026-11-19. Follow-up to the [2026-11-18 research pack](../2026-11-18/README.md),
reviewing planning commit `0dac71fc8a829a8a9ea33fd62c4e45703f4021ca` against
main `1188f1d4a1e31fd8263336b645db86535bca062f`.

**Recommendation:** keep the fixed-pilot Godot approach, but require independent
image/depth/color proof, a photo-specific shadow and damage policy, recoverable
loading, and measured package/hardware admission before calling the site usable.
The review found 18 actionable gaps in the previous requirements and integrated
their corrections into the same SC-PHOTO plan.

The [canonical implementation plan](../../../plans/photorealistic-flying-sites.md)
still owns all 18 step IDs and their status. This pack adds design requirements,
not completed runtime work or another status ledger.

## Hybrid follow-up: photographs plus existing 3D assets

The next study reviews planning commit
`f5dbf743f3e5229687688149fcda3215b8228a70` and the relevant paths on main
`99e5a5ac024935c32028e5332d31a3e09da4dc42`. It adds **12 hybrid technique
investigations, 12 precedent dossiers, 47 retained search strings, 30 grouped
source records and six proposed comparison cases**.

The revised recommendation compares a fixed-eye hybrid during SC-PHOTO-02:
photographic distance plus a few existing real trees, props and local ground.
Photo-baked objects, 3D additions and cleaned 3D replacements have separate
appearance/shadow roles while keeping stable physical identity. Supported real
trees may use accepted-time wind; photographed trees stay static. Moving views
still require real geometry and their own camera-volume/parallax proof.

The asset audit finds 30 current vegetation assets/13 tree forms and reuses the
existing Blender/generator, tree-card, ground and wind workflows. Source checks
also resolve two misleading examples: the Godot forest demo really composes
photographic sky with procedural terrain and real trees, while the separate
Navier8 panorama demo hides its matching glTF. Neither supplies OpenRC runtime
qualification or blanket rights to its assets.

## Read in this order

| Document | Purpose |
| --- | --- |
| [Adversarial review](adversarial-review.md) | Eighteen findings, severity, original omission, source evidence, correction and counterevidence |
| [Implementation contracts](implementation-contracts.md) | Coordinate/projection convention, calibration envelope, color/shadows, physical policy, bounded loading, cold recovery and delivery identity |
| [Qualification protocol](qualification-protocol.md) | Twelve concrete case groups with independent oracles, proposed limits, failure paths, hardware scope and existing tools |
| [Research log](research-log.md) | Twenty-five retained queries, 25 primary-source records, repository/main comparison and retrieval limits |
| [Optics analysis](../../../../research/photorealistic-flying-sites/optics_review.py) and [receipt](../../../../research/photorealistic-flying-sites/optics_review_receipt.json) | Reproducible dependency-free geometry/memory calculations; no Godot runtime claim |
| [Hybrid design](hybrid-scenery.md) | Twelve techniques, appearance ownership, renderer limits, local/photo ground and shadow/reflection interfaces |
| [Hybrid precedents](hybrid-precedents.md) | Named RC simulators, creators, production accounts and source-inspected Godot examples, with evidence boundaries |
| [Existing-asset reuse audit](hybrid-reuse-audit.md) | Current source formats, trees/cards, wind/filtering, ground/props, stale documentation and missing integration |
| [Hybrid experiments](hybrid-experiments.md) | Six concrete comparisons mapped to existing steps and Q groups, including independent controls and failure decisions |
| [Hybrid search/source record](hybrid-search-log.md) | Forty-seven retained queries, 30 grouped source records, pinned external code and retrieval corrections |
| [Hybrid parallax analysis](../../../../research/photorealistic-flying-sites/hybrid_parallax_review.py) and [receipt](../../../../research/photorealistic-flying-sites/hybrid_parallax_receipt.json) | Reproducible centered-point calculation explaining why a foreground mesh does not admit a moving panorama |

The new contracts and protocol take precedence over the corresponding initial
design/acceptance choices. The older techniques, free resources, citations,
historical measurements and search logs remain useful and are preserved.
The hybrid follow-up refines those same contracts; it introduces no duplicate
implementation-status table.

## What changed the decision

The most consequential result is quantitative: the old four-pixel allowance at
90° horizontal FOV becomes **257.824 output pixels** at the existing 1° vertical
zoom on a 1080-pixel-high output. An eight-pixel allowance becomes 515.649.
The same 16K panorama supplies only 45.511 vertical source texels in that view.
The revised gate distinguishes soft background detail from wrongly occluding
the aircraft and uses measured per-view errors for critical features.

Other source-backed hazards are equally practical: an obstacle can lose its
collider while staying in the photograph; an Auto shadow can fade toward a
native receiver that does not exist; a corrupt saved site has no old Home to
restore; and a generic runway capability also enables a scenario generator
restricted to the stock field. These are integration hazards to prevent, not
failures observed in an implemented photo site.

The new first implementation target is one synthetic fixed-eye scene that proves
projection, independent color, measured depth and aircraft grounding on the
pinned renderers. A simple surveyed turf field and its complete offline export
follow only after that method is demonstrated.

## Scope and practical limits

The engine remains `4.8.beta2.official.cafc17a19`. The numerical simulation,
native-backend domain gates, existing camera laws and renderer defaults remain
under their current owners. No runtime implementation or dependency change is
part of this revision.

The prior 20 technique dossiers, 24 free-resource dossiers, ordered first ten
plus second ten searches, 78 resource-search strings and 86 source records remain
present. This review's 25 source entries include revisited pages; the counts
are not a claim of 111 unique sources or adopted tools.

At the adversarial-review commit, only the optics analysis ran. Its maximum direction round-trip error for
the ten rotated cases was approximately 6.26e-16 using Python float arithmetic.
That verifies the proposed convention and reproduces the calculations; it does
not verify Godot shader compilation, imported images, live flight or GPU memory.
All new performance, size and visual thresholds are explicit proposals.

## Verification record — adversarial-review commit

The candidate published as `f5dbf743f3e5229687688149fcda3215b8228a70` was
checked on 2026-11-19. Counts below describe that earlier candidate:

- All **500 relative link occurrences and 248 linked heading anchors** resolved
  across 17 complete plan/research documents and the photographic-site links in
  three shared guides. The local check reused the repository's
  `tools/ci/check_docs.py` parser, resolving sparse targets from Git; this was
  not represented as a CI event receipt.
- The canonical ledger still has 18 unique SC-PHOTO steps. The new pack has
  18 findings, nine contracts, twelve qualification groups, 25 distinct retained
  query strings and 25 source entries. Every finding maps to a contract, case
  and existing step. No runtime step was marked complete.
- The original 20 technique dossiers, 24 resource dossiers, 86 source records
  and both original search logs were checked against the baseline and are
  unchanged. Earlier historical measurements retain their original scope.
- Python 3.12.14 reproduced the analytical receipt on the same runtime. Six
  cardinal expectations and ten rotated direction cases passed; the latter
  stay below the declared 2e-12 error bound. Cross-platform libm last-bit
  differences are not treated as byte-identity failures.
- Three independent read-only reviews covered architecture, visual method and
  resource delivery. Corrections included synthetic-versus-integrated gate
  sequencing, terminal-impact checks, coverage at actual runway poses, exact
  shader cardinal/polar cases and mip addressing, defined timing/noise and
  color-bias statistics, bounded requests inside a group, hash/provenance
  wording, allocator plateaus and final-archive versus host/target export proof.
  These corrections were integrated; the old effort estimates are explicitly
  low-confidence until re-estimated after the spike/site choice.
- The change is confined to 13 Markdown documents and two small analytical
  files under root `research/`. Whitespace and code-fence checks passed.
  No runtime source, engine pin, dependency or asset binary changed.

Runtime/import/export, simulator capture, pilot and hardware qualification
remain unexecuted and belong to SC-PHOTO-02…10. The analytical result and stronger
requirements do not close those gates.

## Verification record — hybrid follow-up

The integrated follow-up was checked on 2026-11-19:

- All **597 relative link occurrences and 286 linked heading anchors** resolved
  across 22 complete plan/research documents and the photographic-site links in
  three shared guides. This is a local scoped check using the existing document
  parser and Git-backed sparse targets, not a CI event receipt.
- The canonical ledger retains 18 unique SC-PHOTO steps. The follow-up contains
  12 HM technique dossiers, 12 HP precedent dossiers, six HX comparison cases,
  30 HS grouped source records and 47 distinct retained query strings. The prior
  20 techniques, 24 resource dossiers, 86 source entries and original search
  logs remain unchanged. The earlier review retains 18 findings, nine contracts,
  twelve Q groups, 25 queries and 25 source records.
- Both analytical receipts reproduce on the same Python 3.12.14 runtime. The
  hybrid calculation uses an ideal centered point, a hypothetical 25 cm transverse
  translation and an illustrative 2-pixel limit; at 1° vertical FOV/1080 px high,
  missing parallax for a point at 1 km is 15.469467767 pixels. It is not a new
  camera allowance, an independent renderer oracle or a hardware result.
- Three read-only reviews checked source evidence, repository reuse and the
  method/experiment design. Integrated corrections include a render-only direct
  factory fixture for close trees rejected by the existing treeline loader;
  explicit factory-versus-wrapper shadow policy; a specified distant reference
  and constant lighting/probe conditions in A/B; pre-reset damage checks;
  controlled representation overlap during dither; and precise source-license
  and resource-chain attribution.
- The follow-up is confined to 12 Markdown documents and two small analytical
  files. It changes no runtime source, engine pin, dependency or binary asset.
  Whitespace and balanced-code-fence checks passed. It does not mark an
  implementation or device gate complete.

The remaining work is to build and qualify the selected synthetic method, then
integrate one surveyed field under the canonical steps. No simulator, Blender
render, image/model import, exported application or GPU test ran in this follow-up.
