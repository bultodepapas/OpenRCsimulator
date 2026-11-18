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
| `test_telemetry_service.gd` | 37 checks: nothing before Enable, windows, sealing, sending, errors, activities, off switch and generation fence, locale gate, 410 suspension, session rotation, failed decline |
| `test_telemetry_sender.gd` | 18 checks against a loopback collector: exact body and headers, 429 Retry-After, refused redirect, silent peer timeout, silent cancel, refused connection |
| `test_telemetry_app.gd` | 31 checks through the real AppRoot: development run unavailable, notice once, neutral focus, Esc declines and is remembered, Settings switch, preview, German/Spanish gate, Enable button, batch accepted by a collector, a real flight with stock vehicle, simulated clock, accepted classifier and returned-home summary |
| Existing UI tests | `test_ui_language` 104 (catalog completeness, formats, glyphs), `test_settings_ui` 113, `test_ui_settings_integration` 51, `test_ui_update_notice` 46, `test_ui_home` 333, `test_ui_home_layout` 2916, `test_startup_loading` 51, `test_ui_home_rebuild` 22 |
| Receiver suite | 103 tests incl. reference equivalence and the Godot client end to end (`OPENRC_GODOT` set): batches stored once, no CPU/GPU names, paths or user strings in stored bodies |
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
