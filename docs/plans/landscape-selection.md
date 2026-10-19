# Landscape selection implementation plan

Owner: landscape track, coordinated with UI and session owners. Prefix: **L21–L24**.
Scope: `app/landscapes/`, small `main.gd`, Home and helicopter presentation hooks,
landscape tests and the [contributor guide](../LANDSCAPES.md). Existing physics,
club assets and default launch behavior remain authoritative.

| ID | Work | Acceptance / status |
| --- | --- | --- |
| L21 | Register bundled landscape scripts explicitly in one ordered catalog. Each supplies its name, field path, renderer and matching obstacle inventory. Keep Club field first/default; avoid directory scanning and asset moves. | Both IDs resolve; unknown direct IDs are refused; old preferences retain the default. In progress. |
| L22 | Import and validate the selected `openrc-field v1` before constructing Home or `main`. Delegate rendering and contacts through the selected adapter; preserve the existing Club field builders. Add Green paradise with one flat grass plane, no club objects or lake. | Both worlds load; Green contains no hidden club contacts or night fixtures. In progress. |
| L23 | Add a remembered Home landscape selector. Replace the backdrop after validation; pass the same selection to flight and Workshop trials. Switch through End flight → Home; create a fresh session rather than teleporting a running vehicle. Support `--landscape=<id>` without reading preferences. | Club → Green → Club round trip, saved selection, direct route and restart checks. Green uses airborne/hover starts; truck courses remain separate. In progress. |
| L24 | Verify loading, keyboard selection, independent resources, lighting and both flight routes; publish the short authoring contract with Green as the example. | Focused headless regressions and native rendered captures required. Exported-package and target-hardware checks remain release gates. Pending. |

No third-party map loader, mod browser, new terrain solver or dynamic discovery is
needed. Future bundled landscapes add one folder and one registry entry.
