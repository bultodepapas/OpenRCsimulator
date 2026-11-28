# Application lifecycle and preparation

Scope: the decisions, alternatives and evidence behind application lifecycle and preparation. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Accepted transition identity owns companion restart

**AFC-01-R2 / AFC-03-R2 (2026-11-09).** Session publishes operational kind/generation
receipts without changing physical checkpoint schemas. Only the latest accepted
start may rebuild a roster; restore and pending configuration cannot authorize
resume. The paired Main facade refuses an active fleet before player-only restore;
an accepted direct Session/debug restore retires it before clocks can diverge.
Logical removal is synchronous, with disposal deferred when an agent callback is
active. [Contract and evidence](../research/ai-companions/AFC-03-R2/README.md).

## Native controls own interaction; styling follows a shared shell

**UI-21/22.** Keep native focus/input and named session pause holds while laying out the shell from a bounded 1080p reference with compact reflow and localization. Theme and finite motion stay beneath controls, with reduced-motion support and explicit preference rollback. Successive color/glass experiments are consolidated in the current visual system instead of remaining competing directives. [Shell contract](../MENU-PLAN.md), [color and surfaces](../plans/menu-redesign.md#color-and-surfaces).

## Preserve exact weather values across settings saves

**UI-21/22 / v0.2.2.** Use a bounded, validated binary weather witness when the pinned engine's numeric text cannot preserve the canonical float64 values. Keep legacy schemas for weather that survives text exactly. Schema 7 requires the witness and protects damaged files; its calm text fallback lets older builds read other preferences without overwriting the file. This preserves physical inputs instead of quantizing them to a serializer fixed point. Reconsider the extra representation after an engine upgrade qualifies exact numeric round trips. [Persistence contract](../TOOLS.md#preference-file-recovery), [regression checks](../../app/tests/test_ui_atmosphere.gd).

## Prepare selected work privately and drain cancellation

**UI-05-R3 / UI-34c / DT-11a.** Bounded selected scene and numeric preparation may run after Home's first draw and stable intent; Fly can adopt matching work. Keep outputs private until validation, live-tree construction on main, and cancellation under an owner that drains outstanding jobs. This replaces stale no-prefetch wording without authorizing unbounded speculative work. The dedicated resource-load workaround came from a Godot 4.7.2 fixture, not a demonstrated universal engine defect. [Current preparation policy](../plans/menu-redesign.md#selected-preparation-while-home-is-visible), [loader evidence](../research/menu-investigations/UI-34c-R5/README.md).

## Loading bars count completed stages; motion only shows activity

**UI-28-R5 (2026-11-12).** The startup intro and the flight loading surface share one bar. Its fill is the position of the current top-level stage in the known stage order. Sub-stages (field and scenery chunks) only advance it within that stage, and it never moves back. A sweep and a pulsing head show that work continues, including during a long threaded load. No percentage, time estimate or minimum display time: the §12 rule against fabricated overall progress stands. The first Home is built in the flight's staged world builder under the intro, so the intro keeps drawing. UI-28-R5b builds Home the same way under a non-cancellable "Preparing home…" surface. The surface is opaque after an activity ends. After a landscape change it is see-through, so the previous view stays visible and dimmed, and requests made meanwhile wait for the build. The surface shows the stable stage with the sub-stage beneath it. Headless routes stay synchronous. Rejected: time-driven fills, which move without work and stall when work does; building the new landscape behind a live menu, which would race aircraft, lighting and Fly changes against the replacement world. [Evidence](../research/menu-investigations/UI-28-R5/README.md), [bar](../../app/ui/loading_bar.gd).
