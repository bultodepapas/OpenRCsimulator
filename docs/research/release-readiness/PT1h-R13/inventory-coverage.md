# Tool inventory coverage

Baseline: `997e212784dbf873a7b054ddbbc68e7905495adf`.

The detailed static index contains **1,859 files in 90 families**. The full tracked-tree census contains **47,278 blobs**, including **5,861 source files** under the explicit extension/name definition in the JSON.

**This is a broad inventory, not a claim that every file was deeply audited.** Static declarations and imported module names do not prove runtime behavior, dependency installation, or caller reachability.

## Review coverage

| Level | Files |
| --- | ---: |
| read_source_representative | 52 |
| indexed_only | 1,799 |
| implemented_and_focused_tested | 8 |

## Source census

| Corpus | Source files |
| --- | ---: |
| application_regression_source_not_individually_indexed | 924 |
| application_runtime_source_not_individually_indexed | 706 |
| detailed_tool_inventory | 1,858 |
| documentation_and_retained_reproduction_source | 1,927 |
| external_audit_source | 28 |
| other_source | 1 |
| prototype_source | 12 |
| retained_asset_delivery_source | 394 |
| site_runtime_or_vendored_source_not_individually_indexed | 11 |

## Tool families

| Family | Files | Guide | Review counts |
| --- | ---: | --- | --- |
| app/build-and-orchestration | 6 | `docs/TOOLS.md` | indexed_only: 3, read_source_representative: 3 |
| app/editor-addons | 6 | `docs/TOOLS.md` | read_source_representative: 3, indexed_only: 3 |
| app/runtime-tools | 4 | `docs/TOOLS.md` | indexed_only: 4 |
| app/test-helpers | 69 | `docs/tools/shared.md` | indexed_only: 69 |
| assets/authoring | 15 | `docs/tools/physics.md` | indexed_only: 15 |
| ci/workflow | 1 | `.github/workflows/ci.yml` | read_source_representative: 1 |
| research/aero | 6 | `research/README.md` | indexed_only: 6 |
| research/ai-companions | 88 | `research/README.md` | indexed_only: 88 |
| research/aircraft-data | 19 | `research/aircraft-data/d1-r4/README.md` | indexed_only: 19 |
| research/aircraft-editor | 11 | `research/README.md` | read_source_representative: 2, indexed_only: 9 |
| research/aircraft-standardization | 29 | `research/README.md` | read_source_representative: 3, indexed_only: 26 |
| research/audio | 22 | `research/audio/air-absorption-2026-10-17/README.md` | indexed_only: 22 |
| research/avanti-s | 49 | `research/avanti-s/alignment/README.md` | indexed_only: 49 |
| research/battery | 9 | `research/battery/README.md` | indexed_only: 9 |
| research/camera-views | 6 | `research/README.md` | indexed_only: 6 |
| research/crash-damage | 49 | `research/README.md` | indexed_only: 49 |
| research/crash-economics | 11 | `research/README.md` | indexed_only: 11 |
| research/d1 | 1 | `research/README.md` | indexed_only: 1 |
| research/drone-racing | 1 | `research/README.md` | indexed_only: 1 |
| research/engine-upgrade | 5 | `research/README.md` | indexed_only: 5 |
| research/extra-300 | 15 | `research/README.md` | read_source_representative: 1, indexed_only: 14 |
| research/f4u-corsair | 40 | `research/README.md` | indexed_only: 40 |
| research/failure-mode | 3 | `research/README.md` | indexed_only: 3 |
| research/field-world | 26 | `research/README.md` | indexed_only: 26 |
| research/flight-dynamics | 52 | `research/flight-dynamics/climb-trim/README.md` | indexed_only: 52 |
| research/flight-modes | 2 | `research/README.md` | indexed_only: 2 |
| research/flight-overlays | 3 | `research/README.md` | indexed_only: 3 |
| research/flight-robustness | 12 | `research/README.md` | indexed_only: 12 |
| research/flight-test | 11 | `research/flight-test/README.md` | indexed_only: 10, read_source_representative: 1 |
| research/fuel-systems | 22 | `research/README.md` | indexed_only: 22 |
| research/glow-engines | 43 | `research/glow-engines/README.md` | indexed_only: 43 |
| research/ground-contact | 5 | `research/ground-contact/e5a/README.md` | indexed_only: 5 |
| research/ground-physics | 17 | `research/ground-physics/README.md` | indexed_only: 17 |
| research/helicopter | 71 | `research/README.md` | indexed_only: 71 |
| research/input | 2 | `research/input/d6b-r2/README.md` | indexed_only: 2 |
| research/landing | 19 | `research/README.md` | indexed_only: 19 |
| research/native-kernel | 94 | `research/native-kernel/README.md` | indexed_only: 94 |
| research/native-math-spike | 4 | `research/native-math-spike/README.md` | indexed_only: 4 |
| research/native-slipstream | 7 | `research/README.md` | indexed_only: 7 |
| research/natural-random | 4 | `research/README.md` | indexed_only: 4 |
| research/p51 | 39 | `research/p51/p51-02/silhouette/README.md` | indexed_only: 39 |
| research/performance | 55 | `research/performance/README.md` | indexed_only: 39, read_source_representative: 14, implemented_and_focused_tested: 2 |
| research/physics-audit-2026-10-14 | 76 | `research/README.md` | indexed_only: 76 |
| research/physics-audit-2026-10-23 | 3 | `research/README.md` | indexed_only: 3 |
| research/propulsion | 55 | `research/README.md` | indexed_only: 55 |
| research/propwash | 61 | `research/README.md` | indexed_only: 60, read_source_representative: 1 |
| research/radio-latency | 2 | `research/radio-latency/README.md` | indexed_only: 2 |
| research/rc-monster-truck | 177 | `research/rc-monster-truck/README.md` | indexed_only: 177 |
| research/reddit-launch-feedback | 1 | `research/reddit-launch-feedback/README.md` | indexed_only: 1 |
| research/reference-library | 1 | `research/README.md` | indexed_only: 1 |
| research/root | 3 | `research/README.md` | indexed_only: 2, read_source_representative: 1 |
| research/scenery | 4 | `research/README.md` | indexed_only: 4 |
| research/sensitivity | 1 | `research/README.md` | indexed_only: 1 |
| research/skywalker-x8 | 6 | `research/README.md` | indexed_only: 6 |
| research/sun | 3 | `research/README.md` | indexed_only: 3 |
| research/timber | 33 | `research/README.md` | indexed_only: 33 |
| research/time-of-day | 16 | `research/time-of-day/tod-01/README.md` | indexed_only: 16 |
| research/ugly-stik | 26 | `research/README.md` | indexed_only: 26 |
| research/validation | 22 | `docs/TOOLS.md` | indexed_only: 14, read_source_representative: 6, implemented_and_focused_tested: 2 |
| research/visual-quality | 39 | `research/README.md` | indexed_only: 39 |
| research/wind | 3 | `research/README.md` | indexed_only: 3 |
| site/automation | 9 | `site/README.md` | read_source_representative: 1, indexed_only: 8 |
| tools/aircraft | 3 | `tools/aircraft/moonrunner/README.md` | indexed_only: 3 |
| tools/analytics | 3 | `tools/analytics/README.md` | indexed_only: 3 |
| tools/atmosphere | 16 | `tools/atmosphere/README.md` | indexed_only: 16 |
| tools/audio | 29 | `tools/audio/README.md` | indexed_only: 29 |
| tools/blender | 3 | `tools/blender/README.md` | indexed_only: 3 |
| tools/branding | 2 | `docs/tools/README.md` | indexed_only: 2 |
| tools/ci | 17 | `tools/ci/README.md` | indexed_only: 13, read_source_representative: 4 |
| tools/companions | 3 | `tools/companions/README.md` | indexed_only: 3 |
| tools/debug | 6 | `tools/debug/README.md` | read_source_representative: 3, implemented_and_focused_tested: 2, indexed_only: 1 |
| tools/flight_log | 2 | `docs/FLIGHT-LOGGING.md` | implemented_and_focused_tested: 2 |
| tools/godot | 31 | `tools/godot/README.md` | read_source_representative: 1, indexed_only: 30 |
| tools/graphics | 37 | `tools/graphics/README.md` | indexed_only: 37 |
| tools/grass | 24 | `tools/grass/README.md` | indexed_only: 24 |
| tools/ground | 25 | `tools/ground/README.md` | indexed_only: 25 |
| tools/landscape | 22 | `tools/landscape/README.md` | indexed_only: 19, read_source_representative: 3 |
| tools/night-lighting | 1 | `tools/night-lighting/README.md` | indexed_only: 1 |
| tools/readme | 2 | `docs/tools/README.md` | indexed_only: 2 |
| tools/release | 8 | `tools/release/README.md` | indexed_only: 7, read_source_representative: 1 |
| tools/repo | 1 | `docs/tools/README.md` | indexed_only: 1 |
| tools/scenery | 32 | `tools/scenery/README.md` | indexed_only: 32 |
| tools/shadows | 7 | `tools/shadows/README.md` | indexed_only: 7 |
| tools/skins | 9 | `tools/skins/README.md` | indexed_only: 6, read_source_representative: 3 |
| tools/smoke | 3 | `tools/smoke/README.md` | indexed_only: 3 |
| tools/terrain | 5 | `tools/terrain/README.md` | indexed_only: 5 |
| tools/trailer | 25 | `tools/trailer/README.md` | indexed_only: 25 |
| tools/trees | 39 | `tools/trees/README.md` | indexed_only: 39 |
| tools/ui | 2 | `docs/tools/README.md` | indexed_only: 2 |
| tools/world | 8 | `tools/world/README.md` | indexed_only: 8 |

## Extraction limits

Per-file records preserve the baseline Git blob identity, family, static role/language/purpose, nearest README, literal CLI declarations, Python imports and review level. For locally changed files the current blob identity is separate. Nine website automation files and one research JavaScript file absent from the sparse checkout were read from the pinned Git objects; the website README was also verified through the GitHub connector. No tool was run to obtain help. Repeated source-basis defaults and extraction-code explanations live at the top level of the compact JSON.

Retained copies and dated research are labeled from explicit path/name cues, which do not establish that the file is obsolete. Documentation research sources, retained asset deliveries, prototypes, runtime files and ordinary application regression scripts remain in the census without a duplicated historical file registry. The nearest ancestor README may be generic; consult each family guide and source for exact behavior.
