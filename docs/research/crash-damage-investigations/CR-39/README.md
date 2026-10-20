# CR-39 — Accident cost audit and hardening plan

2026-10-17 · Crash track · Audit of the accident cost feature (CR-29…38) on `main` at `049df203`: [`app/economy/`](../../../../app/economy/), [`app/ui/accident_report.gd`](../../../../app/ui/accident_report.gd), its integration in [`app/main.gd`](../../../../app/main.gd) and the generated [runtime sidecar](../../../../app/data/economy/catalog.json). The [economics plan](../../../plans/crash-damage-economics.md) owns scope; this file records findings and the proposed CR-39 steps.

## Method

- Read the production path: contact signal → `Incident.observe()` → frame-boundary `Calculator.calculate()` + `ReplacementQuote.quote()` → `AccidentReport` headline → `user://last_accident.json`.
- Ran the 14 economy/accident test scripts natively (Godot 4.7.2, Windows 11, headless).
- Timed the path with [`probe_timing.gd`](../../../../research/crash-economics/probe_timing.gd) (mean of 20–200 calls, this workstation only, not the target host).

## Results

| Test script | Result |
| --- | --- |
| accident_report, accident_settlement, economy_checkpoint, inspection, package_optimizer, repair_details, repair_planner, replacement_quote, component_resolver, impact_budget, thermal_budget | All pass |
| economy_catalog | 3 of 64 fail: Extra and P-51 dossiers stale |
| economy_calculator | 1 of 59 fails: P-51 dossier does not load |
| accident_integration | 2 of 65 fail: Extra propeller strike is not priced |

`python research/crash-economics/build_runtime.py --check` also fails: `gp-extra-300s-60: independent dossier physical source identity mismatch; review before rebinding`.

| Measurement (µs) | Stik | P-51 (stale) | Lumber |
| --- | --- | --- | --- |
| `Catalog.load_for` (every reset) | 11 339 | 13 027 | 10 136 |
| `begin_with_catalog` (recipe read + hash) | 505 | 359 | 471 |
| `Calculator.calculate` | 151 | 8 | 89 |
| `ReplacementQuote.quote` (recalculates) | 215 | 18 | 106 |
| Revision recalc + signal | 196 | 29 | 204 |
| Archive flush (pretty JSON, tmp + rename) | 1 190 | 1 064 | 1 425 |

A terminal hull crash with no propeller strike, Stik: `outcome=inspection`, `total=null`, `low=0`, `high=null`, no priced lines. The headline therefore reads **AMOUNT UNKNOWN · Cost unavailable**, while the complete-build reference of US$827.34–1,331.34 appears only inside the breakdown.

## Findings

| ID | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| A1 | Critical, product | Real crashes do not show a cost. Production writes component dispositions only for propeller strikes. No production caller supplies `apply_inspection()`. `contact_components` is validated in `catalog.gd` but never read by `incident.gd`. `ComponentResolver`, `ImpactBudget` and `ThermalBudget` (~1 200 lines) have no runtime caller, because production billing is disabled by design (CR-33c). | Probe result above; `_headline_state()` falls through to "Cost unavailable" when `low=0` and no line is priced. |
| A2 | Critical, regression | Extra and P-51 crash costs are unavailable in play. Commits `208f0b89` (Extra: a description string plus `breakaway_factor`) and `0296ac59` (P-51) changed the physical JSON without rebinding the sidecar. The dossier binds a SHA-256 of the raw file bytes, so any edit invalidates it. Prices are advisory, so the flight loads and the failure stays silent for the player. | Failing checks above. `app/test.sh` runs the generator check (lines 83–85), yet the commits landed. |
| A3 | High | Every new non-propeller contact, including a light wingtip brush, adds the same "structural inspection" item. The settled card then shows INSPECTION REQUIRED with no amount and no affected part. | `incident.gd` `observe()` else-branch. |
| A4 | Medium | Turbo Lumber prices `propeller_main` (US$16.98) but leaves `propeller_component_id` empty. An electric prop strike becomes "no compatible replacement price". | Sidecar dossier. |
| A5 | Medium, performance | Each reset or restart reloads the whole catalog on the main thread: read 200 KB, SHA-256, parse and fully validate 9 aircraft, then reread, hash and parse the aircraft JSON and the recipe book. That takes ~10–13 ms, most of a 60 FPS frame, for unchanged bytes. | Probe. |
| A6 | Low, performance | Each revision runs the calculator twice (directly and inside `quote()`), deep-copies the report three times (signal, UI, archive) and writes pretty-printed JSON (~1.1–1.4 ms). Bounded and coalesced per frame, but avoidable. | Probe; `incident.gd` `_recalculate()`. |
| A7 | Low, robustness | The "persistent record" holds one report: each new incident overwrites `user://last_accident.json`. `incident_id` comes from wall clock and µs ticks, so a replayed tape cannot match its earlier report. | `incident.gd` `begin_with_catalog()`, `_write_archive()`. |

Strengths to keep: integer cents with overflow guards, no US$0 stand-in for unknown prices, honest incomplete labels, bounded journal with confirmed facts, valuation outside accepted ticks, tmp + rename writes, strict archive validation and paired physics/economics checkpoints.

## Plan

Each step is one small, reviewable change. Pricing/UI steps do not change physics, so no golden re-record.

| ID | Work | Acceptance proof |
| --- | --- | --- |
| CR-39a | Restore green: review the Extra/P-51 physical diffs, then rebind both dossiers through `build_runtime.py` (never by hand). | `build_runtime.py --check` passes; the 3 economy/accident scripts report 0 failed. |
| CR-39b | Bind economics to an economics-relevant projection: inventory IDs, contact IDs, propulsion ID/kind and quantities, not raw bytes. A text or tuning edit keeps costs available; a removed or renamed bound ID still invalidates. Coordinate the identity contract with AS. | New catalog tests: a description-only edit loads; a renamed inventory ID fails with a named reason. |
| CR-39c | Show money in a terminal crash: report the range `[known subtotal, complete-build high + inspection]` as **ESTIMATED LOSS · UP TO US$…**, labeled provisional reference, never as the total. It applies only to complete dossiers; incomplete fleets keep their current labels. | Calculator/report tests for Stik terminal, no strike (US$0–1,331.34 range); EN/ES capture at 1280×720. |
| CR-39d | Map accepted contacts to parts: read `contact_components` and mark mapped parts `inspect`. A nonterminal brush then shows `[0, part high]` and names the part. Author Stik/Extra/P-51 contact maps in the generator sources, and set the Lumber `propeller_component_id`. | Integration tests: Lumber wingtip brush lists `wing_main` up to US$115.95; electric prop strike prices `propeller_main` once. |
| CR-39e | Cache the parsed catalog per session, keyed by catalog-bytes and source hash; `begin()` on reset only clears the ledger. | Probe: reset `begin` < 1 ms on this workstation (from ~11 ms); identical report bytes. |
| CR-39f | One calculation per revision: let `ReplacementQuote` take the calculator result, and emit a single copy. Write compact JSON only on settle, terminal, reset and exit. Optionally keep a bounded ring of the last 10 reports. | Probe: recalc ≤ 120 µs Stik, flush count per incident ≤ 3; archive tests for ring size and byte cap. |
| CR-39g | Make failures visible: show a stale or missing dossier as "Cost data out of date for this aircraft", not a generic unavailable. Add a cheap pre-push check that runs `build_runtime.py --check` when `app/data/aircraft/*.json` changes. | Fault-injection tests (stale hash, missing recipes, corrupt archive, failed write) and a hook run log. |
| CR-39h | Run the plan's determinism matrix end to end: replay one recorded `.orfl` crash tape at 30/60/144 FPS and with effects off. Compare the report minus `incident_id` and time. | Identical lines and amounts across runs; tape, config identities and report retained here. |

### Implementation status — 2026-10-17

All CR-39 steps are implemented. Product effect: every airplane route loads its cost data again; a terminal crash on a complete dossier headlines a provisional whole-aircraft ceiling; hull and gear contacts name the parts they affect.

| ID | Status | Evidence |
| --- | --- | --- |
| CR-39a | Done. The reviewed diffs since binding were aero/ground only: P-51 `propeller_sidewash` (`0296ac59`); Extra gear description and `breakaway_factor` (`208f0b89`). No inventory changed. `expected_source_sha256` in [`aircraft-costing.json`](../../../../research/crash-economics/aircraft-costing.json) was updated and the sidecar regenerated. | Extra `9b174cb2…1c62`, P-51 `a37f7f42…a321` (CRLF checkout bytes per `.gitattributes`). `build_runtime.py --check` and `build_catalog.py --check` pass. |
| CR-39b | Done at runtime. Each dossier carries a generated `physical_signature`: inventory name, mass and energy source per item, contact IDs, and propulsion ID/kind/propeller. When raw bytes drift but the signature matches, [`catalog.gd`](../../../../app/economy/catalog.gd) keeps the costs, binds them to the flown bytes and adds a report assumption. The generator keeps its exact-byte gate as provenance. | Signature tests: text edit kept; renamed, heavier or removed item, new contact or changed propulsion kind rejected. Catalog drift test split into accepted and rejected cases. |
| CR-39c | Done in [`calculator.gd`](../../../../app/economy/calculator.gd) and the [`accident_report.gd`](../../../../app/ui/accident_report.gd) headline (EN/ES). `range_basis = complete_build_replacement_ceiling`. | Terminal Stik crash without a strike: US$0–1,331.34, headline "Up to US$1,331"; with a strike "US$5.39 – US$1,331". Native [EN](hull-crash-en-1280x720.png)/[ES](hull-crash-es-1280x720.png) captures: 56 px headline; panel and actions fit at 1280×720, 1920×1080 and 3840×2160. [Decision](../../../DECISIONS.md). |
| CR-39d | Done. A retained non-propeller contact keeps the structural note and also names its mapped parts as pending inspection, without overriding an existing decision. [`checkpoint.gd`](../../../../app/economy/checkpoint.gd) re-derives those inspections from the journal. Maps are authored for the Stik family (single airframe group), Extra, P-51, Avanti and Lumber. The Lumber prop strike is bound to `propeller_main`. | Fleet binding checks per route; a forged inspection on an unmapped part is rejected at restore; Lumber strike prices US$16.98 once. |
| CR-39e | Done: per-ledger cache keyed by route and physical identity; the recipe book loads once. | Reset `begin()` 0.10–0.19 ms (first load 11–13 ms). Same workstation. |
| CR-39f | Done: `ReplacementQuote.quote_calculated()` reuses the revision's calculation; compact archive JSON. Signal copies unchanged. | Recalc 0.10–0.19 ms, flush 1.1–1.5 ms: no gain beyond run-to-run noise. Flush is disk-bound. |
| CR-39g | Done: a stale dossier reports "Cost data is out of date for this aircraft version; no prices were applied." (EN/ES). Opt-in [`tools/hooks/pre-push`](../../../../tools/hooks/pre-push) runs both generator checks ([TOOLS](../../../TOOLS.md)). | Hook run passes on the current tree. |
| CR-39h | Done in [`test_accident_integration.gd`](../../../../app/tests/test_accident_integration.gd): one production hull crash with effects on, off, and publication every 1 or 5 frames gives an identical report apart from incident identity. The existing 30/60/144 Hz cadence check is unchanged. | 12 new checks. Software determinism only, not physical validation. |

Verification on Windows 11, Godot 4.7.2 native: 19 economy, accident, crash and prop-strike scripts, 0 failed. These include `test_economy_cr39.gd` (46 checks), accident integration (77) and crash integration (179). Also passing: 61 crash-economics Python tests, both generator checks, the CI partition test and parse checks of every changed script. The full `app/test.sh` (WSL/Linux) was not run.

Remaining limits: the Extra, P-51, Avanti, Lumber and X-Cell dossiers are still incomplete (CR-36 pricing). A terminal crash on them keeps an honest "Cost unavailable", or a lower bound when a part is priced, because no replacement ceiling exists. Component damage is still not inferred from impact severity (CR-33).

Severity-based damage, structural thresholds and thermal billing stay in CR-33/CR-35. CR-39 adds no joule cut-offs or speed × price rules.
