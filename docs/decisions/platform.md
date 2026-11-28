# Platform selection and acceptance

Scope: the decisions, alternatives and evidence behind platform selection and acceptance. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Native desktop Godot, with an explicit engine pin

**Gate 1 / GDU-03.** Godot in `app/` replaced the browser prototype because the owner prioritized native desktop delivery, real-radio input and the editor over the bake-off's higher three.js score. The prototype remains frozen. Official Godot 4.8-beta1 replaced the earlier 4.7.x pin after owner-authorized local verification; this did not requalify every platform or historical benchmark. The owner requested official 4.8-beta2 on 2026-11-01; [GDU-12](../research/engine-upgrade/GDU-12/README.md) records the follow-up without replacing historical numerical baselines. The exact pin lives in [get-godot.sh](../../app/get-godot.sh), with rationale in the [bake-off](../../prototypes/stage0/COMPARISON.md) and [GDU-03 adoption](../research/engine-upgrade/GDU-03/README.md). Reconsider the platform only against demonstrated product or implementation limits.

## Aircraft first; broader vehicles share the foundation

**SF-01 / HELI / RCV / DR.** Vehicle breadth uses the common simulation contracts, with each family retaining its own data, session and qualification. Named helicopter and ground-vehicle consumers justified replacing H10's earlier decision to defer interface extraction. Physics groundwork or a playable research surrogate does not establish a qualified new aircraft or racing activity. Current family status belongs in [STACK](../STACK.md#supported-vehicle-paths) and the owning guides; [SF-01](../research/simulation-foundation/SF-01/README.md) records the extraction rationale.

## Separate software preservation from product acceptance

**Gate 2 / Gate P / VAL.** Goldens, exact replay and analytic checks protect implementation; independent applicable measurements qualify physical behavior, and pilot, radio and target-hardware gates remain separate. This prevents a model's own coefficients or a development-VM speedup from certifying realism or release performance. The physics budget remains a gate, not a guaranteed runtime bound. Use the [ROADMAP gates](../../ROADMAP.md#execution-order-and-release-gates), [VAL-3](../research/validation/VAL-3/README.md) and the existing [resolution policy](../../AGENTS.md#display-resolution-priorities), rather than copying acceptance numbers into this record.
