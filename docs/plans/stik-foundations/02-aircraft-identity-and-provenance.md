# P2 — Stable aircraft identities and traceable installations

**Status:** proposed implementation plan; no runtime or data change is delivered by this document. **Planning baseline:** `6616ec37350bf217b58f598c32ea86c58f611586`, 2026-11-15. **Owners/prefixes:** existing AS aircraft-contract and DATA owners, EL1e-STIK/EL/BAT and NITRO installation owners, AE Workshop, UI selection, US presentation, AFC compatibility and FL observation owners. P2 and the slice labels below are navigation labels, not new track IDs. Implementation steps belong to the [existing registry](../../README.md#tracks-plans-and-step-ids).

## Outcome and reason for selection

A player sees two understandable stock Stiks. A developer can identify the exact accepted aircraft, installation and energy source behind any flight, report or saved experiment. A future engine, battery, model or coefficient update has a traceable authoring path and an explicit compatibility decision.

The [two-variant policy](../ugly-stik-two-variants.md) is already implemented. The [route audit](../../research/ugly-stik-flight-physics-2026-11-15/variants-and-routes.md) found stale descriptions and consumer distinctions, not an unexplained set of safe-to-delete duplicates. The significant improvement is preserving that policy across future work and closing provenance gaps at the producer/consumer boundary.

| Identity | Existing role to preserve | Distinction that must remain visible |
| --- | --- | --- |
| `jensen-das-ugly-stik-60` | Basic stock reference and default | Prescribed RPM/fuel representation; the engine name does not make it equivalent to finite 61FX. |
| `stik-electric-6s` | Experimental stock electric installation | Normal finite pack and explicitly selected ideal source share one aircraft ID. Workshop currently supports the labeled ideal trial. |
| `stik-glow-61fx-2t` | Hidden technical/research and compatibility route | Coupled finite-glow specimen; do not alias it to Basic. |
| `stik-glow-55ax-2t`, `stik-glow-fs64v-4t` | Hidden technical/research and compatibility routes | Retained generators, tests, saved contexts and economy/export dependencies. |

This table is a planning snapshot. The catalog and owning guides remain authoritative for implemented status. Physical qualification, source mode, stock visibility and technical existence are separate properties.

## Existing boundary and proposed contract

The [catalog](../../../app/app_state/aircraft_catalog.gd) already separates `ids()` from `player_ids()`/`player_entries()`, and provides `default_battery_mode()` and `data_for()`. Keep this single registry; do not create a second list of aircraft inside a report generator. Preserve the versioned Natural Random pool and the separately qualified companion fleet; neither should automatically inherit every stock addition.

[FlightSession.trace_meta()](../../../app/sim/flight_session.gd) already provides the accepted input-byte hash, a separately described semantic hash, configuration, law descriptions, engine and pack details. Frozen Workshop inputs have their own identity treatment. Reuse these facts. A common metadata view should be extracted or extended only when an actual consumer gap requires it; do not move per-frame state into a new identity service or change the checkpoint layout merely to label reports.

The contract to close is:

1. Resolve and validate the requested route, aircraft and energy source before publishing an accepted session. A rejected selection preserves the preceding accepted state.
2. Read identity from that accepted session or its frozen inputs. A report must not reconstruct yesterday's configuration from today's catalog or files.
3. Keep exact input bytes distinct from semantic content and presentation/package identity. Cosmetic changes need not masquerade as aerodynamic changes; a source-proof refresh is not automatic permission to rebase a saved Workshop document.
4. Declare missing historical identity as unknown. A label or catalog ID alone does not establish the actual pack, aircraft bytes or solver.
5. Keep experiment parameters in the existing authored recipe/Workshop or owner research path. Generate outputs through the owning pipeline; do not multiply catalog identities for every test or independently tune ideal and pack JSON files.

The [aircraft contract](../../AIRCRAFT_CONTRACT.md) already carries `{value, unit, kind, source}`. Parameter evidence should use that contract and linked owner dossiers. If uncertainty or applicability needs richer records, place them with the existing installation/measurement source first; add runtime schema only if a runtime consumer actually needs it.

## Research questions and decision experiments

| Question | Alternatives | Discriminating experiment / decision |
| --- | --- | --- |
| Is accepted identity missing, or merely not propagated? | Consume existing `trace_meta()`; extract a narrow common view; add a versioned field only for a real gap. | Trace Home pack, explicit ideal, direct CLI and frozen Workshop trial to the actual accepted bytes. Prefer propagation if the producer already knows the value. |
| Does every source mode derive from one installation? | Existing deterministic generator; extra authored override with declared scope. | Regenerate ideal/pack from one installation and compare invariant airframe/inventory/control fields. Any intended difference must have an owner and source. |
| Which historical identities can change? | Retain exact IDs; explicit migration; retire an unsupported route later. | Exercise saved selections, recipes, descriptors, logs, economy and explicit CLI consumers on disposable profiles. No deletion based only on menu visibility or filename age. |
| How should developers see evidence quality? | Existing `kind/source` plus linked dossier; generated human-readable coverage table. | Audit one Basic and one Electric installation through source → generator → admitted data. Add a small derived table only if it exposes a concrete provenance gap; never maintain duplicate parameter values. |

Sources and contrasts are the [variant audit](../../research/ugly-stik-flight-physics-2026-11-15/variants-and-routes.md), [R08](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r08-electric-motor-esc-battery.md), [R10](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r10-measured-mass-cg-inertia.md) and [R21](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r21-capture-provenance.md). This plan does not infer physical calibration from successful generation.

## Incremental delivery

The slice labels are local ordering. Use an available step under the named owner when implementation begins; do not reopen completed EL1e-STIK steps as if absent.

| ID / owner | Work and likely paths | Proof/status |
| --- | --- | --- |
| A — AS/DATA, EL1e-STIK, UI | Refresh the route/identity map against the intended integration commit. Inspect existing `test_stik_stock_selection.gd`, `test_stik_electric_6s.gd`, catalog, preferences and `app/app_root.gd`; add only uncovered rejection/source-mode cases. Document the accepted metadata fields consumed by P4. | Proposed first PR. Exactly two Stik stock choices; hidden technical routes remain explicit; rejected requests preserve accepted state; Basic and Electric sources identified correctly. Existing coverage that already closes a case is retained, not duplicated. |
| B — FL/session with AS/AE/BAT | Propagate existing accepted identity through the narrow session metadata boundary. Extend a versioned producer field only if A demonstrates a gap. Source code is `app/sim/flight_session.gd` and the actual requesting session/Workshop consumer. | Proposed. Frozen in-memory input, pack/ideal selection, reset/restore and failed setup retain truthful identity; no reread of mutable catalog data to relabel history. P4 owns capture/card/report serialization. |
| C — DATA/EL/BAT/NITRO, AS/AE | Close one concrete generation/provenance gap. Reuse `research/propulsion/stik-6s/build_aircraft.py`, its installation source, `research/glow-engines/build_installations.py`, overlay proof and descriptor builders. Run existing freshness checks before changing their coverage. | Proposed, conditional on a gap. Deterministic source-to-output proof; ideal/pack invariant agreement; valid actual loader result; unrelated aircraft bytes and existing source-proof contracts preserved. |
| D — UI/AE/AFC with aircraft owners | Apply the route matrix to the player/developer descriptions and to one real future installation change. Document the promotion and compatibility decision in the owning guide; reconcile obsolete instructions instead of creating another inventory. | Proposed. Home, Workshop, CLI/debug, economy/export and qualified scenario/companion routes describe their actual scope. No silent rebasing, retroactive relabeling or hidden technical choice exposed in the stock picker. |

Generated dependencies remain in their existing order: installation/pack → aircraft data → registered model proof/manifests → customization/Workshop descriptor → economy/export proof → affected native identity. Existing builders include `research/aircraft-standardization/build_overlay_proof.py`, `research/aircraft-editor/build_descriptors.py` and `research/crash-economics/build_runtime.py`; the [owning workflow](../../TOOLS.md#aircraft-workshop) defines commands. Shared source changes can invalidate downstream proofs even when physical values stay equal; inspect and regenerate the exact affected chain.

## Acceptance and migration

| Case | Required evidence |
| --- | --- |
| Stock subset and technical inventory | The Stik stock subset is exactly Basic + Electric, in intended relative order. Assert the scoped invariant rather than freezing unrelated future fleet counts. Hidden specimens remain loadable only through supported technical contexts. |
| Same aircraft, different source | Home default pack and explicitly accepted ideal have the same Electric ID and distinguishable accepted source identity. Workshop never claims finite-pack qualification from its ideal trial. |
| Rejection and persistence | Unknown ID, hidden stock selection, missing source, invalid generated input and failed save do not partially replace accepted settings or destroy the original saved document. |
| Frozen/custom aircraft | Two user documents with the same display name remain distinct. Changed disk/catalog files cannot relabel an already accepted or retained run. |
| Generated consistency | One authored installation produces both energy representations with intended differences only. Loader/module checks and actual affected export resources pass; a generator `--check` alone is insufficient. |
| Old evidence | Missing fields remain unknown; old logs/recipes are preserved. Any required schema transition has explicit reader behavior and a reversible compatibility boundary. |

No user-profile rewrite is needed for the initial documentation/propagation slices. If a later persistence change is justified, use the existing validated replacement/recovery mechanism and disposable interruption tests. Roll back producer/consumer changes together if their schema changes; retain previous readers where the format permits. Keep published observations at their original identity. Generated-data rollback restores the matching authored source and regenerates the affected chain, rather than hand-editing outputs.

## Dependencies, risks and exit

[P4](04-experiment-and-product-evidence.md) can implement card horizons immediately and use existing accepted metadata; it does not wait for all of P2. P2 owns producer semantics, P4 owns evidence consumers, and [P3](03-validated-flight-model.md) owns physical promotion. [P1](01-controls-and-feel.md) records input/profile identity separately from aircraft identity. [P5](05-deterministic-performance.md) consumes both in benchmark manifests.

The main risks are overbuilding a registry already present, mistaking technical specimens for duplicates, hashing mutable data after acceptance, and forcing unrelated generated artifacts to change. The simplest successful outcome may be stronger propagation, focused conformance and clearer owner documentation with very little runtime code.

**First PR ready scope:** slice A plus the smallest demonstrated metadata propagation gap from B, if any; no coefficient edits, ID replacement or data migration. **Exit:** every selected route has a truthful source identity or explicit unknown, the two-stock policy is protected, and a future installation change has one reproducible authoring/compatibility path. Physical realism remains qualified by P3, not by this contract.
