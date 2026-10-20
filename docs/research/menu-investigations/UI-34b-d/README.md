# UI-34b–d — aircraft flow

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings AS-2, AS-5, AS-6, AS-8, AS-9, AS-11, HN-7, SP-7 and the desktop part of SP-1. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs). [UI-34a](../UI-34a/README.md) delivered Change aircraft separately.

## Behaviour

| Finding | Change |
| --- | --- |
| AS-9, SP-7 | Catalog entries own a one-line `short_name`, read by `Catalog.short_name()`. The Home card and the catalog list use it, which replaces Home's per-ID compact overrides. The full name stays in tooltips and in the details card. With the helicopter selected, the default Flight page no longer scrolls at 1080p. |
| AS-2, SP-1 (desktop) | On logical canvases of at least 1500×850, the Aircraft page shows an **AircraftDetails** card beside the rail. It holds the full name, capability, summary and limitations of the selected (or just requested) aircraft, so keyboard and gamepad users can read them without tooltips. Compact layouts keep the rail list. The catalog intro no longer claims that limitations appear on each entry. |
| AS-5 | The Aircraft page shows the same "Loading…" or "could not be loaded" state as the Flight card. |
| AS-11 | The Natural Random briefing requests a preview of the airplane it draws; Back restores Home's selection. |
| AS-6 | With the helicopter selected, Workshop stays available and opens on the default airplane, and Natural Random stays available. Failure practice remains airplane-only. |
| AS-8 | `Catalog.runway_supported()` and `Catalog.has_finite_fuel()` read each stock data file once per run, instead of on every selection. |
| HN-7 | Fly shows "Preparing flight…" and waits one frame before the synchronous flight build, so the press is visibly acknowledged. A rejected start restores FLY. |

A language switch now re-renders the start label without recording it as the remembered start. This regression came from UI-32 and was found while wiring the card; a check in `test_ui_preserved_choices.gd` now covers it.

**Not in this step:**
- Favourite saved builds in the catalog and a reason line under a blocked FLY (AS-10, latent) remain in UI-34d.
- The large-text scene card (SP-8) and the object-labelled FLY (HN-3) remain in UI-34b.
- Keeping the preview broker across Home rebuilds (AS-8b) remains in UI-34c.

## Proof

[`test_ui_aircraft_flow.gd`](../../../../app/tests/test_ui_aircraft_flow.gd) is new.
- Before the change it could not parse, because the catalog API did not exist.
- After the change all 19 checks pass. The test sets a real 1920×1080 canvas after startup; a headless SceneTree otherwise stays at 64×64. It covers:
  - short names and cached capabilities;
  - the helicopter page fitting once its preview has loaded;
  - Workshop and Natural Random reachable from the helicopter;
  - the briefing preview and its restore;
  - the details card's content and placement, plus its absence in compact layouts;
  - the loading state;
  - the preparing state.

One [`test_ui_home.gd`](../../../../app/tests/test_ui_home.gd) assertion encoded the AS-6 dead end. It now asserts that Workshop and Natural Random stay available while failure practice stays airplane-only.

Regression runs: RESULTS-PENDING
