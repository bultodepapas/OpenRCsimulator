# MP-00 verification and evidence limits

## Source and method

- Audited `bultodepapas/OpenRCsimulator` at `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`; isolated documentation branch based on that commit.
- Read repository guidance and track ownership; inspected production configuration, simulation/session publication, frame conversion, companion presentation, shell lifecycle, content identities, race code and export targets. Used targeted text/source inspection; no graph tool was available.
- Compared primary vendor/maintainer documentation with native Godot applicability and the owner's **no new spending** constraint. The [source register](sources.md) retains 46 external source URLs; the [audit](repository-audit.md) retains pinned project references.
- Independent research covered architecture and service economics. A separate source reviewer challenged the integrated plan. The lead checked material claims against original code/docs and reconciled the alternatives; agent agreement is not runtime evidence.

## Documentation verification

The scope is eight documentation files: a plan, four dated research/evidence files, and three navigation/decision updates. No runtime, engine pin, generated aircraft data, dependency, CI policy or deployment configuration is changed.

| Check | Result and scope |
| --- | --- |
| Whitespace/patch integrity | `git diff --cached --check` passed |
| New local links and anchors | **56 passed** against the complete candidate Git tree, using the existing `tools/ci/check_docs.py` link parser, `GitObjects` and `check_target`; inherited unrelated link debt was excluded |
| Immutable source references | **25 passed** for paths/line anchors against the audited commit |
| Named existing regression entry points | **22 test paths exist** in the audited tree; this is a path check, not test execution |
| Arithmetic | 128-byte field sum; 2/4/8-pilot host and relay payload formulas; 57,600-request directory example; 15–25/27–47 developer-day sums checked |
| Independent candidate review | Five concrete findings resolved: route-specific service gates, finite-extreme/render bounds, paused-state freshness versus liveness, forwarded ownership, and bounded private-invite claims. Shared lighting semantics clarified; focused re-review found no remaining blocker |

Link verification compares new destinations in the staged tree (`git write-tree`) with the pinned base, checking every new research/plan link as well as added index links. This reuses the repository validator beyond its CI CLI's limited guide allowlist; it does not forge a CI selection receipt. Public source pages were reviewed through research, not by this local-link checker. Arithmetic was independently recomputed in Python; no simulator test was needed for the documentation-only scope.

The current CI workflow triggers on `main` pushes, version tags, pull requests or manual dispatch. A feature-branch publication alone does not establish a hosted CI result. No pull request, merge, release or manual runtime job is part of this research delivery; required CI remains a gate for future implementation/integration.

## Not established by this work

No multiplayer prototype, provider account, relay, room service, port mapping or cloud deployment was created. No payment method, paid plan or resource was selected. No simulator, runtime regression suite, target-OS export, real network test or performance benchmark was run for this documentation task.

The 20 Hz/128-byte packet, 2/4/8-pilot caps, interpolation parameters, CPU/motion targets, quota usage and effort estimates are **proposals or calculations**. They are not measured outcomes. Existing test names identify future regression coverage; they do not constitute executed evidence.

EOSG compatibility with the pinned beta, provider account-specific eligibility/enforcement, actual packet overhead, real connectivity success rate and target-hardware cost remain open implementation gates. GD-Sync's conflicting advertised transfer allowance and Photon's precise Free/Godot traffic-spend enforcement are explicitly unresolved.

Research uses current public primary documentation. Official stable Godot pages may move beyond the repository engine, and free offers may change. Recheck before selecting dependencies or deploying. This branch records a defensible route to small zero-spend sessions; it does not certify an unlimited hosted service.


## MP-00-R2 continuation — 2026-11-16

The previous sections record the original delivery and its exact checks. This continuation starts at `81af96688e8111173f15b66e54fdd9dba19d1e02`; GitHub `main` remains `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`. It adds a [protocol contract](../../plans/multiplayer-protocol.md), [source/service findings](round-2.md), [EOS trial](eos-trial.md), and a standard-library [analytical model](../../../research/multiplayer/capacity_model.py) with [generated results](../../../research/multiplayer/capacity-results.json), and updates the current plan/navigation/decision record.

Two bounded research helpers examined independent network/lifecycle and EOS integration questions. The lead independently fetched the consequential pinned engine/wrapper code, inspected project integration points, checked official service sources, and integrated/adapted the results. Epic CreateDeviceId/DeleteDeviceId text was verified in the official HTML payload when web-rendered text was empty. No evidence was inferred from an inaccessible page alone.

| Follow-up check | Result / limit |
| --- | --- |
| Scope and patch integrity | Twelve intended files: ten Markdown documents plus one analytical Python script and its generated JSON; `git diff --cached --check` passed; no production source/config changes |
| New local references | **45 local links/anchors passed** against the staged Git tree using the existing documentation validator; unrelated inherited guide debt excluded |
| New pinned external source references | **17 line ranges across seven retrieved Godot/EOSG source files checked**; source semantics independently inspected, not inferred from an anchor alone |
| Model regeneration | Fresh standard-library execution exactly reproduced the JSON; all six directory scenarios independently recomputed |
| Layout and arithmetic | Contiguous bytes 0–127, 48-byte header/80-byte body, signed room-time field, three host bandwidth cases, 190 ms conditional bracket bound and duration allowance checked; no codec runtime test claimed |
| Independent review / resolution | Corrected pause-versus-late-pose handling, signed time origin, acceptance-time tracker prerequisites, contiguous directed controls, channel-0 auth completion order, clock uncertainty wording and routed-directory fail-closed behavior. Focused review confirmed the layout/model and exposed the final paused-timestamp edge cases; the lead integrated explicit age exceptions and a fresh-start requirement when acceptance time is unknown; a final focused recheck confirmed both remaining findings closed within document scope |

The lead accepted the reviewed source findings, adapted the room nonce without enlarging the payload, and retained unresolved engine/provider/network qualification as gates. The static review does not establish exploitability, platform compatibility or a measured capacity. Source/index checks and arithmetic are proportionate to this research scope; no fabricated CI selection or runtime receipt is used.

The executable model is planning arithmetic only. It does not implement a socket, service, codec decoder, simulation or provider meter. Godot execution, SDK loading, actual packet traffic, operating-system exports, physical-machine tests, adversarial runtime tests and all MP-01…07 gates remain unexecuted. No account, deployment, payment method, port mapping, upstream message or runtime source was changed. A branch update alone does not run the required hosted CI workflow.
