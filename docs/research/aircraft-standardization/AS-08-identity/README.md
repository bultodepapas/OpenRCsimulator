# AS-08: stable physical identities

Date: 2026-10-13. Scope: authored physical identity metadata, contact/event adapters and Workshop inventory bindings. The authoritative authoring rules are in [AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#stable-physical-identities); editor behavior is in the [Workshop guide](../../../AIRCRAFT-WORKSHOP.md). This slice does not complete the [remaining standardization plan](../../../plans/aircraft-standardization.md).

## Delivered behavior

- `openrc-aircraft v2` accepts the optional complete `physical_identity_version: 1` module. Inventory parts, deployed supports, hull probes, the propulsion installation and four conventional surfaces have authored, globally unique IDs. Partial, duplicated, malformed or unsupported identities fail before flight.
- Nine physical sources and the onboarding template carry IDs. Five source pipelines preserve authored IDs through regeneration; hull IDs travel with their source points. Seven catalog configurations receive Workshop v3 descriptors. Four synthetic electric regression sources retain the historical ID-less path, also tested with explicit identities.
- The normalized model retains ID maps independently of display names. Contacts and accepted observations use authored IDs; historical data retains its explicit positional/name fallback. Wheel profile keys and contact order remain their separately versioned interface.
- Workshop v3 resolves an inventory binding against the current source ID. Renaming/reordering a source requires descriptor regeneration because exact source and model-manifest hashes remain enforced. Historical v1/v2 readers remain available for matching historical sources. There is no automatic rebase of saved edits or checkpoints.
- Fixed-wing authoring tests and Workshop distinguish explicitly tagged rotorcraft, which use their own loader and schema. Unknown aircraft metadata still goes through strict validation.

IDs do not select propulsion laws or add flaps, mixers, multiple engines, structural failures or new contact laws. Those capabilities require their own complete contract/runtime work.

## Numerical evidence and concurrent changes

The baseline was captured at `7265b2e0dc10bfcc7f220544998e21be28159380` before the identity migration. [Before](fleet-before.json), [identity-only candidate](fleet-identity-only.json) and [comparison](fleet-comparison.json) record seven aircraft with terminal and soft hull routes at 240 Hz for 240 ticks each. All fourteen cases have exactly matching initial states, sampled states, trajectory hashes and replay results. Only `model_sha256` changes; the probe format, Godot build, frequency and tick count match. This is same-platform software regression evidence, not physical validation.

The shared tree subsequently received the independent D6e-R1 Stik calibration and control-rate updates. Regenerating the four Glow variants legitimately propagates their donor's aerodynamic changes. The [first source audit](source-migration-audit.json) and [final source audit](source-audit-final.json) record changed JSON paths and values, including a later horizontal-tail incidence update. Four of nine outputs match the frozen sources after removing identity metadata; five contain independent donor changes. The optional strict baseline audit therefore reports failure, rather than overwriting the baseline or attributing those changes to identities. Current identity tests separately compare each current derived model with and without metadata.

No golden flight was re-recorded for this work. Old source identities deliberately fail checkpoint restoration, and rejection preserves the current session.

## Current working-tree checks

The [current fleet run](fleet-current.json) passes all fourteen initialization/flight/replay cases. It is a smoke/replay check of the current calibrated sources, not a claim that they equal the older calibration. [Integration input hashes](integration-inputs.json) retain the shared-tree boundary and detected concurrent file changes.

All 24 focused test/probe entries pass after the documented reruns: [verification report](verification.json). The identity suite passes 248 checks; the aircraft contract suite passes 2,612. [Schema/loader parity](schema-parity.json) passes 97 cases: 93 agreements and four deliberate coupled constraints enforced by the runtime. [Python checks](python-checks.json) pass source validation, shared-module parity, generated schema/model/descriptor freshness and eight clean-checkout cases. Contact identity, events, sessions, propulsion, checkpoints, wheel/soft-contact/prop-strike and Workshop results are retained in `logs/`. Workshop compiler, historical trial and descriptor suites pass 301, 36 and 94 checks respectively; UI and the complete production-scene editor/flight/return route pass.

The first identity run encountered a transient parse error in the concurrently edited `failures/runtime.gd`; its [original log](logs/physical_identity-initial.log) is retained and the [rerun](logs/physical_identity.log) passes. Initial production-scene checks encountered incomplete parallel sky changes, and one subsequent run read a Stik file during a concurrent write. After those dependencies became complete, atomic line-ending normalization and source/descriptor regeneration, [prop-strike feedback](logs/prop_strike_feedback.log) and [Workshop integration](logs/workshop_integration.log) passed. The final fleet, identity and Workshop runs record unchanged physical inputs during their checks. The compiler test now uses fixed-wing catalog entries; the historical trial test now builds a genuinely ID-less source with matching v1 bindings. Original failed attempts remain in the report and logs. The complete application suite, performance qualification and export were not rerun by this slice.

## Reproduce

Use the pinned Godot 4.7.2 binary with the current working tree. Generator freshness and clean-checkout checks cover CRLF aircraft bytes and LF descriptors, including both Git `autocrlf` modes.

```powershell
python research/aircraft-standardization/build_schema.py --check
python research/aircraft-standardization/test_physical_identity_sources.py
python research/aircraft-standardization/test_modules.py
python research/aircraft-standardization/test_schema_v2.py --godot .tools/Godot_v4.7.2-stable_win64.exe --report .tools/as-schema-identity.json
python research/aircraft-editor/build_descriptors.py --check
python research/aircraft-editor/test_descriptor_checkout.py
```

The standard [conformance runner](../../../../research/aircraft-standardization/conformance.py) includes the identity source and runtime suites. Relevant native tests are `test_physical_identity.gd`, `test_aircraft_physical_identity_contacts.gd`, contact/event/session, propulsion, checkpoint and Workshop suites. Source pipelines and their `--check` commands are recorded in [source-generation.log](source-generation.log).
