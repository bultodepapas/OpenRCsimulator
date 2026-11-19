# Photorealistic flying sites: strengthened plan and adversarial review

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

## Read in this order

| Document | Purpose |
| --- | --- |
| [Adversarial review](adversarial-review.md) | Eighteen findings, severity, original omission, source evidence, correction and counterevidence |
| [Implementation contracts](implementation-contracts.md) | Coordinate/projection convention, calibration envelope, color/shadows, physical policy, bounded loading, cold recovery and delivery identity |
| [Qualification protocol](qualification-protocol.md) | Twelve concrete case groups with independent oracles, proposed limits, failure paths, hardware scope and existing tools |
| [Research log](research-log.md) | Twenty-five retained queries, 25 primary-source records, repository/main comparison and retrieval limits |
| [Optics analysis](../../../../research/photorealistic-flying-sites/optics_review.py) and [receipt](../../../../research/photorealistic-flying-sites/optics_review_receipt.json) | Reproducible dependency-free geometry/memory calculations; no Godot runtime claim |

The new contracts and protocol take precedence over the corresponding initial
design/acceptance choices. The older techniques, free resources, citations,
historical measurements and search logs remain useful and are preserved.

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

Only the analytical script ran. Its maximum direction round-trip error for
the ten rotated cases was approximately 6.26e-16 using Python float arithmetic.
That verifies the proposed convention and reproduces the calculations; it does
not verify Godot shader compilation, imported images, live flight or GPU memory.
All new performance, size and visual thresholds are explicit proposals.

## Verification record

The integrated candidate was checked on 2026-11-19:

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
