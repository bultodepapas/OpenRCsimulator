# Repository integration audit — TELEM-00

Inspected 2026-11-18 at commit 39fa2746ae4f4ba8698b87db279adcfe84ef5d17. The accessible target is bultodepapas/OpenRCsimulator; no separate Editor repository was found by the connected repository search. The production game and Workshop/editor live in app/. This branch targets that repository.

This is a source audit, not an executed game/packet/performance campaign. No existing runtime file is changed.

## Verified source boundaries

| Source | Observation | Implementation consequence |
| --- | --- | --- |
| [STACK](../../../STACK.md), [engine pin](../../../../app/get-godot.sh), [project](../../../../app/project.godot) | Current stack declares official Godot 4.8-beta2/GDScript, Compatibility generally and native Metal/Mobile on Apple Silicon, fixed 240 Hz simulation | Keep the pinned engine and renderer-specific qualification; do not introduce Unity/C++ dependencies by assumption |
| [AppRoot](../../../../app/app_root.gd), _ready / start_flight / Settings | Technical/direct, input-report, ground, airship and multirotor routes branch before ordinary Home preferences; Home loads locale/preferences and creates local statistics | Place admission in the ordinary product lifecycle and cover every later activity; do not use a blanket autoload |
| [startup](../../../../app/ui/startup.gd) | Rendered startup/splash hands off to app root, with bypasses for technical/headless routes | A splash dismissal is not consent; show the notice after locale/UI readiness |
| [build_info](../../../../app/app_state/build_info.gd) | Export identity differs from development fallback; arbitrary describe and commit metadata can exist | Project an approved public release identifier, not the whole dictionary |
| [preferences](../../../../app/app_state/preferences.gd), [preferences_file](../../../../app/app_state/preferences_file.gd) | Versioned settings, protected/unwritable outcomes and direct-route defaults | Separate consent state with explicit migration/failure behavior; preserve existing settings |
| [settings_screen](../../../../app/ui/settings_screen.gd) | Categories include Display, Interface, Sound, Graphics, Camera and Lighting; update controls have explicit state | Privacy is a proposed new category, not a current UI feature |
| [frame_samples](../../../../app/render/frame_samples.gd), [Main](../../../../app/main.gd), _log_frame_time | Existing logger measures monotonic wall intervals and draw-counter/drawability coverage, with separate engine delta and raw-stream options | Reuse measurement meaning and small pure helpers; do not enable megabyte/raw trace buffers for every player |
| [frame_diagnostics](../../../../app/render/frame_diagnostics.gd) | start() reads full CPU/GPU/API/OS strings and metadata; GPU status explicitly says freshness unverified; memory estimates have scope warnings | Do not initialize it before grant or upload its metadata; allowlist hardware locally and keep unknown readings explicit |
| [render_timing_lease](../../../../app/render/render_timing_lease.gd) | A shared lease owns the per-viewport measurement flag and prevents one consumer from disabling another | Optional GPU telemetry must use this owner; baseline GPU timing remains off |
| [aircraft_catalog](../../../../app/app_state/aircraft_catalog.gd), [vehicle_roster](../../../../app/app_state/vehicle_roster.gd) | Stable stock IDs coexist with research-only aircraft and other vehicle activity families | Approve only shipped selectable IDs; custom content becomes custom; selection is not successful play |
| [statistics service](../../../../app/statistics/service.gd), [store](../../../../app/statistics/store.gd), [flight event](../../../../app/statistics/flight_event.gd) | Local state contains UUIDs, precise UTC times, activity/configuration identities and rich flight events; accepted events have a detached notification | Reuse approved classifications only; never backfill or serialize store/data/raw event dictionaries |
| [update_checker](../../../../app/app_state/update_checker.gd), _start / set_automatic | Independent GitHub release check; documented unthreaded transport avoids a silent-peer worker-join issue; disabling automatic checks does not cancel an already running update | Telemetry needs stricter cancel/purge semantics; do not claim its switch disables updates |
| [existing analytics tool](../../../../tools/analytics/README.md) | Locally archives GitHub repository traffic/release download counters; website analytics are separate | It cannot answer runtime FPS/aircraft questions; keep traffic and game metrics denominators separate |

## Proposed ownership

Register TELEM in [docs/README](../../../README.md#tracks-plans-and-step-ids) before runtime implementation. Own new telemetry modules/schemas/tests, while coordinating changes in AppRoot/Settings/i18n with UI, measurement helpers with PT/VQ, accepted activity semantics with UI-FS/vehicle owners, and export flags with DT. Do not change the simulation kernel or generated aircraft sources.

Runtime candidates are listed in the [architecture](../../../plans/telemetry/architecture.md#proposed-module-interfaces). They are proposed paths, not implemented APIs. This branch owns only planning/research, synthetic contracts/prototype and narrow documentation indexes.

## Integration hazards to carry into implementation

A direct flight launched with arguments intentionally avoids Home preferences. A developer build cannot silently inherit a production telemetry grant. A no-argument exported GUI started in a terminal cannot be reliably identified as a “CLI run,” so policy must refer to observable routes.

Local flight statistics and telemetry are different data boundaries. Existing statistics may keep collecting locally for the player's own features while remote telemetry is off. Do not change or delete that local store as an incidental telemetry action.

Render timing samples can be cached and a zero can be ambiguous. Per-frame logger output and snapshots may contain full hardware strings, exact timings, paths or scene data; a blacklist is not a safe upload filter. Construct a fresh closed object.

The source snapshot's frame report explicitly states that the app has no named performance presets. Initial telemetry records effective bounded options and current_default/custom rather than fictional preset labels.

No production scene was opened and no Godot test was needed for this documentation/prototype change. Existing runtime behavior and hardware qualification remain outside this branch's test claim.
