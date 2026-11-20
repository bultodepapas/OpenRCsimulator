# TELEM-02…11 implementation verification

Date: 2026-11-18. Scope: the product-telemetry client in `app/telemetry/` and its UI/AppRoot integration, the receiver in `services/telemetry/`, the release configuration path and the contract change below. Plan and activation steps: [telemetry plan](../../../plans/telemetry.md). No receiving service is deployed and no build carries a release configuration, so every build reports telemetry as unavailable.

## What was built

| Part | Result |
| --- | --- |
| Client contract and admission | Closed wire builders with a local schema/semantic check; pure policy (on/ask/off/unavailable); release gate requiring an exact clean tag, release template, engine 4.8 and a packed endpoint/operator/contact; strict consent file |
| Measurement | Process-cadence windows (5 s gap exclusion, 10 s warmup, 30 s complete, 60 s hard bound), post-grant hardware classification, activity summaries with accepted fixed-wing counts, reset/slice/custom handling |
| Delivery | Memory queue (32 batches, 256 KiB, 10 min), 60 s cadence with jitter, five full-jitter retries, fixed hourly budget, unthreaded sender with monotonic 5 s deadline, no redirects, 4 KiB answers, 401/403/410 suspension |
| UI | First-launch notice (Esc/close/Continue decline; neutral initial focus; choices armed only after inputs are released), Home status line, Settings → Interface switch/status/preview/notice, translations in nine languages with an EN/ES reviewed-notice gate |
| Receiver | Starlette ingress, strict decode and schema/semantic validation, SQLite raw/aggregate separation, built-in and command purge, daily GPU/vehicle rollups with suppression, weekly report and digest-bound GitHub publisher, operator 410 switch |
| Contract | `release_id` also accepts the repository's dotted preview tags (`v0.1.9-beta.1`, `v0.2.0-rc.10`); schema and examples regenerated |

## Executed checks

Godot 4.8-beta2 (`.tools/Godot_v4.8-beta2_win64_console.exe`), headless, run directly because this host's `app/.godot` is a junction the checked runner refuses; every run was also scanned for `SCRIPT ERROR`/`ERROR:` lines (none). Python 3.12.12 with exact pins.

| Check | Result |
| --- | --- |
| `test_telemetry_contract.gd` | 92 checks: schema parity (enums, keys, release pattern, stock vehicles incl. every Home-selectable vehicle), client batch encodes byte-equal to the generated example, rejections, classifiers, windows |
| `test_telemetry_admission.gd` | 75 checks: policy truth table incl. mistyped facts, route predicate, release gate, endpoint rules, consent file incl. a failed decline leaving no grant |
| `test_telemetry_queue.gd` | 37 checks: bounds, TTL, cadence, budget, 5/10/20/40/80 s backoff, Retry-After, status outcomes, stale answers |
| `test_telemetry_service.gd` | 38 checks: nothing before Enable, windows, sealing, sending, errors, activities, off switch and generation fence, locale gate, 410 suspension, session rotation, failed decline |
| `test_telemetry_sender.gd` | 18 checks against a loopback collector: exact body and headers, 429 Retry-After, refused redirect, silent peer timeout, silent cancel, refused connection |
| `test_telemetry_app.gd` | 33 checks through the real AppRoot: development run unavailable, notice once, neutral focus, Esc declines and is remembered, Settings switch, preview, German/Spanish gate, Enable button, batch accepted by a collector, a real flight with stock vehicle, simulated clock, accepted classifier and returned-home summary |
| Existing UI tests | `test_ui_language` 104 (catalog completeness, formats, glyphs), `test_settings_ui` 113, `test_ui_settings_integration` 51, `test_ui_update_notice` 46, `test_ui_home` 333, `test_ui_home_layout` 2916, `test_startup_loading` 51, `test_ui_home_rebuild` 22 |
| Receiver suite | 106 tests incl. reference equivalence and the Godot client end to end (`OPENRC_GODOT` set): batches stored once, no CPU/GPU names, paths or user strings in stored bodies |
| Research suite | 124 tests; both generator checks match |

Not run here: the receiver container (Docker is not running on this host; the [contracts workflow](../../../../.github/workflows/telemetry-contracts.yml) builds and smoke-tests it), the full `app/test.sh`, captures, native platforms, rendered/assistive-technology review, TLS against a real endpoint, real GitHub publication.

## Independent review and dispositions

Two source-read-only reviews (requested Sonnet, high; effective settings not independently verified) checked the plan against the code before implementation and the implementation before commit. The second found no consent bypass, raw-string leak or SQL injection. Accepted and fixed:

| Finding | Fix |
| --- | --- |
| A failed decline save could leave an older "enabled" file, so the next launch would resume | A decline removes the earlier grant before writing and again after a failed write; regression tests in admission and service suites; Settings wording corrected in all languages |
| Once armed, focus landed on Enable, so a reflexive Enter could grant | Initial focus is the notice text; Enter there answers nothing (tested) |
| Raw retention depended on an external timer | `serve` purges at start and every 5 min, cutting interval + 60 s early (tested) |
| Raw and aggregate databases shared one volume | Separate directories and container volumes; back up aggregates only |
| No receiver path to suspend clients | `OPENRC_TELEMETRY_SUSPEND_RELEASES` / `_SUSPEND_ALL` answer 410 without storing (tested) |
| IPv6 clients were limited per address | Limited per /64; IPv4-mapped addresses count as IPv4 (tested) |
| A failed `send()` could stall the queue; a sent body stayed in memory | Treated as a transport failure; the copy was removed |
| Slow bodies could hold sockets | `limit_concurrency=200`; proxy body/header timeouts in the README example |

Retained as documented limits: the release gate trusts the build identity written by `export.sh`/CI; per-day volume caps and a stricter global rate are deployment tuning; the Spanish notice must be confirmed by the owner before activation (it is in the reviewed list); `graphics_profile` is `unknown` until a graphics owner can answer it.

## Earlier fixes found by the tests

The contract test caught a release pattern that accepted a trailing newline (`$` versus `(?![\s\S])`); the service test caught a placeholder `seq` overwriting the session number (the local check dropped the batch instead of sending it); the end-to-end test showed zero-length intervals counted as drops. All three were fixed before review.

## Post-merge audit, 2026-11-18

Hosted CI on the first push showed two integration problems; a lead self-audit and a third independent review (receiver rollup/report/publisher, not read in depth before) found more. All fixed and tested:

| Finding | Fix and proof |
| --- | --- |
| `app/app_root.gd` is pinned by the AI-companion behavior manifest; the edit made companion profiles refuse to load (7 of 8 hosted unit shards) | AFC-02 pin renewal (the other track's commit, cherry-picked); renewed again with the audit edit. `test_companions_profiles` 95, `_behavior_manifest` 39, `_airspace` 48, `_external_rejection` 63 |
| The two Settings telemetry buttons did not fit Spanish at 200 % text or Russian at 960 px (`test_ui_modal_responsive`, which the first battery missed) | One row sharing the width, wrapping inside each button: 3,030 responsive cases, 0 failures; `test_settings_ui` 113 (Interface page still fits 1080p without scrolling) |
| Each seal or send rewrote the Home note and cleared other notices (launch failures, save/browser errors) | The telemetry status only takes a free note line or replaces its own previous text; tested through AppRoot |
| Workshop editing was measured as Home, and a "workshop" mode would have become a vehicle activity | Explicit `activity` context flag: Workshop editing is mode `workshop` with no vehicle and no summary (tested) |
| Stored vehicle rows were not re-validated at publication | Floor, bounds, stock id and non-empty check at the report boundary; four bypass cases tested |
| A long purge interval could delete raw rows before their day's rollup deadline | Interval limited to 30–1800 s (purge stays after 47 h; tested) |
| A week could be approved before Sunday was rolled up, then change | Publication waits until Sunday + 47 h |
| The vehicle cohort floor could be lowered by a direct call; an empty release allowlist published anything | `cohort_floor` refusal; empty allowlist publishes nothing (tested) |

Pre-existing failures on main before this track's runtime code (also present on the docs-only merge `054489491`): an H6 math-guard violation in `app/physics/event_step.gd` (servo work, 2026-11-16), shared-capacity simulation/checkpoint and weather-fixture unit failures, and NK-3 macOS. They belong to their owning tracks.

## Release review with the real app, 2026-11-18

The owner asked for a final review: ready for the next release, clear translations and controls, useful data, and a test in the installed game. Two independent reviews (translations; data usefulness and release path) and a third on the candidate, plus a live run of the real app, found the following. All fixed:

| Finding | Fix and proof |
| --- | --- |
| **First-launch notice unreadable at every resolution.** Its two button rows wrapped word by word without a width share, so the panel grew to about 1725 px at 1080p and the notice text collapsed to zero height. Found only by the live run (screenshot); no test covered this screen's layout | Equal-width buttons; title, recommendation, text and links scroll and only the two choices stay fixed. `test_ui_modal_responsive` now covers the consent, notice and preview screens: before the fix 56 of 168 English/Spanish cases failed; after, 0 failures in all nine languages |
| **Every real flight was reported incomplete and unclassified.** The rendered game loads a flight behind the loading screen; the activity started on the first loading frame, before the session clock and the statistics classifier existed, so takeoff/landing/crash counts were never sent. Found in the live run's stored batch (`classification: unsupported`) | A vehicle activity starts once its session runs, after loading. `test_telemetry_app` now flies through the staged loading screen and requires `accepted_fixed_wing` |
| The notice promised "whether graphics settings are customized" but `unknown` was always sent | `graphics_profile` compares the Restore-graphics-defaults choices (one shared key list) with this GPU's recommended defaults: `current_default` or `custom` |
| The notice promised software-error categories; none was emitted | `asset_load_failed` (flight scene not loaded/created) and `renderer_unavailable` (RendererGuard's Compatibility restart after a renderer failure, once per process); the other two categories stay reserved |
| Renderer-fallback and graphics-mode restarts add `--rendering-method`, which closed the route, so the configurations whose renderer failed were never measured | Exact renderer-selection pairs are benign on the route; any other argument still closes it. The benchmark launcher `tools/graphics/launch.py` now sets `OPENRC_TELEMETRY_DISABLE=1` for its child |
| The weekly report only showed mean FPS per GPU family (capped by VSync, hides stutter) and the rollup discarded the frame-interval histograms the client sends | Report v2: daily GPU rows keep the summed 8-bucket histogram and excluded gaps (same 20-session cells); the weekly table adds intervals over 33.3 ms and 50 ms and intervals over 100 ms per minute. Reference and service stay equivalent |
| A configured release could ship with telemetry silently off (endpoint without a path, loopback host, partial variables, or a tag outside the client pattern) | `export.sh` refuses such a build before exporting (14 cases checked); the export plugin applies the game's own endpoint/text rules |
| Steam Deck (`AMD Custom GPU 0405 (RADV VANGOGH)`) and newer Intel names (`Intel(R) Graphics`, `Mesa Intel(R) Xe Graphics`) were classified `other` | AMD+RADV → `amd_radeon`; Intel without Arc plus Graphics/Xe → `intel_integrated` (client and reference, tested) |
| Translations: "raw logs" was "complete logs" in all eight languages (a weaker promise); several Spanish, German, French, Japanese and Chinese wording issues; the unreviewed-language and suspended status lines did not say telemetry was off or what to do | Fixed in all eight catalogs; new status lines: "Telemetry is off: it is not offered in this language yet. Switch to English or Spanish to choose." and "The receiving service paused telemetry, so it is off until you restart the simulator." The Spanish notice edits still need the owner's confirmation before activation |

### Live run of the real app (Windows, RTX 3090, source tree)

A scratch driver loaded the real `app_root.tscn` in a rendered window with an isolated profile and `OPENRC_TELEMETRY_QUALIFICATION_URL` pointing at the receiver from this commit on loopback; no test seam was set (release from `TelemetryRelease.current()`, route from `interactive_route()`). Result: the notice appeared once over Home; nothing was sent before the choice; Enable turned it on and Home said so; Settings → Interface showed the switch; a real Ugly Stik flight produced a batch accepted during the flight and a second with the activity summary after returning home; the Spanish notice and Settings were readable; the Settings switch turned it off and nothing more was sent in the next 75 s. The receiver stored two batches from one session token: OS `windows`, CPU `amd_ryzen`, `17_plus` threads, `33_64` GiB, GPU `nvidia_rtx`, `gl_compatibility`/`opengl3`, VSync on, graphics `current_default`, keyboard, a complete 30 s steady flight window (76 FPS, histogram `[1, 2079, 139, 58, 4, 0, 0, 0]`). The bodies contain no GPU model, user name or path. Screenshots stayed outside the repository.

### Exported release build

A real Windows release export (`--export-release`, release template, 167 s) with the three `OPENRC_TELEMETRY_*` variables set to an unreachable `https://telemetry.invalid/v1/batches` and the v0.2.8 build identity packed `res://telemetry_release.json` through the export plugin. Started with no arguments on an isolated profile, as a player would, it chose High graphics on this GPU, restarted itself, and showed the first-launch notice over Home with readable text and both choices visible (window capture only; closed without a choice, so nothing was saved or sent). The native-kernel plugin refused this host's stale prepared manifest, so that build used the reference physics; it does not affect telemetry.

### Checks after the fixes

Godot 4.8-beta2 headless, logs scanned for script errors: `test_telemetry_app` 39 (staged loading flight), `test_telemetry_service` 40, `test_telemetry_admission` 81, `test_telemetry_contract` 98, `test_ui_modal_responsive` 3,534 cases 0 failures (309 s; consent and notice screens added), `test_settings_ui` 113, `test_ui_settings_integration` 51, `test_ui_language` 104, `test_ui_home` 333, `test_advanced_graphics_settings` 159, `test_companions_behavior_manifest` 39, `test_companions_profiles` 95. Receiver 109 tests plus the Godot client end to end; research 126 tests and both generator checks; `tools/graphics/test_launch.py` 22; 1,506 local links in the telemetry documentation resolve.
