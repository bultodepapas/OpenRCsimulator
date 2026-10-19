# Landscape selection implementation plan

Owner: landscape track, coordinated with UI and session owners. Prefix: **L21–L24**.
Scope: `app/landscapes/`, small `main.gd`, Home and helicopter presentation hooks,
landscape tests and the [contributor guide](../LANDSCAPES.md). Existing physics,
club assets and default launch behavior remain authoritative.

| ID | Work | Acceptance / status |
| --- | --- | --- |
| L21 | Register bundled landscape scripts explicitly in one ordered catalog. Each supplies its name, field path, renderer and matching obstacle inventory. Keep Club field first/default; avoid directory scanning and asset moves. | Delivered: both IDs resolve; unknown direct IDs are refused; old preferences retain the default. |
| L22 | Import and validate the selected `openrc-field v1` before constructing Home or `main`. Delegate rendering and contacts through the selected adapter; preserve the existing Club field builders. Add Green paradise with one flat grass plane, no club objects or lake. | Delivered: both worlds load; Green has no hidden club contacts or night fixtures. Existing grass contact microrelief remains. |
| L23 | Add a remembered Home landscape selector. Replace the backdrop after validation; pass the same selection to flight and Workshop trials. Switch through End flight → Home; create a fresh session rather than teleporting a running vehicle. Support `--landscape=<id>` without reading preferences. | Delivered: round trip, saved relaunch, direct route and restart verified. Green uses airborne/hover starts; truck courses remain separate. Natural Random stays Club-only. |
| L24 | Verify loading, keyboard selection, independent resources, lighting and both flight routes; publish the short authoring contract with Green as the example. | Source, native captures and empty-host resource-pack checks passed. Full fleet regression is blocked by Timber's battery-template hash; rerun after its data is repaired. Full platform release exports and target-hardware acceptance remain open. |

No third-party map loader, mod browser, new terrain solver or dynamic discovery is
needed. Future bundled landscapes add one folder and one registry entry.

[Dated verification and captures](../research/landscape-upgrade/L21-24/README.md).
