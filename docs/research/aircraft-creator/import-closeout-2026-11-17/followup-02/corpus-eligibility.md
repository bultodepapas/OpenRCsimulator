# Corpus eligibility: what the source actually declares

**Checked:** 2026-11-17. **Code review:** `08f948265d40d83fbb4726a302b9e1c9490ccfce`.
**Visual outcomes:** the prior `2a3cf04d` campaign, reused without a new converter run.

This is the readable projection of the [26-model lexical ledger](evidence/eligibility-ledger.json). Exact ZIP/member hashes, parameter line numbers, component records and auxiliary geometry hashes are retained there. The [independent verifier](probes/verify_ledger.py) checked the selected records against the original ZIP bytes and the earlier visual evidence; its [receipt](evidence/ledger-check.json) reports 1,075 record locations. These checks establish transcription and identity, not physical truth or flight eligibility.

## Decision

**No specimen in this corpus has yet been established as a complete source-derived fit for the current Creator package.** This is not proof that none can become supported. The remaining task is to resolve one candidate's semantics and choose the smallest justified shared capability/data prerequisite, then qualify that configuration.

The current [trainer data](../../../../../app/data/creator/airframe-conventional-trainer-estimated-v1.json) has a **1–4 kg** domain; the current [power package](../../../../../app/data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json) is an estimated 4S/800kv installation named for a 12×6 propeller. The compiler's admitted configuration is conventional, single tractor and gearless. Package labels and software fixtures do not establish that a downloaded aircraft shares those properties.

The official [legacy parameter table](https://www.rcflightsim.com/ClearViewPlaneModelParameterDefinitions.html), checked again on this date, labels `modelMass` in kilograms. This supports the v5 interpretation used by the repository's [existing unit research](../../clearview-2026-11-15.md). It does not establish the v6 convention, a measured mass, or the meaning of every other solver-specific coefficient.

## Model-by-model facts

**D:** v5 kilogram interpretation documented. **I:** kilogram interpretation inferred for v6 and still unconfirmed. Every numeric mass is an unverified source declaration. “Unresolved” means no sectioned motor/propeller roster was found; it does not mean no engine/propeller exists. Dimensions below are declarations whose inch interpretation and installation correspondence still need validation. “Admitted” means visual conversion only, with `physics_imported=false`.

| Model | Dialect | Mass declaration | Declared motors / propeller | Prior visual result |
| --- | ---: | ---: | --- | --- |
| MC Tiburon-bipe-7-2 | 5 | 4.1 D | Unresolved | Admitted |
| Calmato 40 Sports | 6 | 2.0 I | 1; 14×8 | JPEG refusal |
| MC 3D Hobby Shops Extra 330 Red | 6 | 10.1 I | 1; 18×7 | Admitted |
| F-117 | 6 | 1.5 I | 1; 11×10 | Admitted |
| 701f | 5 | 8.0 D | Unresolved | Texture refusal |
| B-25 | 5 | 6.0 D | Unresolved | Admitted |
| 701F2 | 5 | 8.0 D | Unresolved | Texture refusal |
| BD-5J | 5 | 8.0 D | Unresolved | Admitted |
| C-130 | 5 | 15.6 D | Unresolved | Admitted |
| Beluga | 5 | 12.0 D | Unresolved | Admitted |
| A6-Zero | 5 | 6.0 D | Unresolved | Admitted |
| Beech99 | 5 | 6.0 D | Unresolved | JPEG refusal |
| A-10_GWS | 5 | 5.2000003 D | Unresolved | Admitted |
| AlleyCat | 5 | 5.0 D | Unresolved | Admitted |
| Beginair | 5 | 5.0 D | Unresolved | Admitted |
| Bell X-5 | 5 | 5.2000003 D | Unresolved | Admitted |
| A-7 Corsair | 5 | 15.6 D | Unresolved | Admitted |
| A-6 Intruder | 5 | 15.6 D | Unresolved | Admitted |
| B-26 Marauder | 5 | 10.0 D | Unresolved | Admitted |
| Bellanca C-27 | 5 | 5.2000003 D | Unresolved | JPEG refusal |
| Brown-B1 Racer | 5 | 12.0 D | Unresolved | Texture refusal |
| Agri Duck Duster | 5 | 8.0 D | Unresolved | Admitted |
| Ascent Park Glider | 5 | 5.0 D | Unresolved | Polygon refusal |
| B-52-Stratofortress | 6 | 8.0 I | 8; eight 6×2.5 declarations | Admitted |
| V22 Osprey | 6 | 4.0 I | 2; 12×3.9623365 section points to `none` | Admitted |
| MC 300S-Air Guard | 6 | 9.1 I | 1; 18×7 | Polygon refusal |

All **20 v5** declared masses exceed 4 kg; their range is 4.1–15.6. The **six v6** values cannot be treated as verified kilograms. Even if the apparent in-range values are confirmed, Calmato/F-117 have different declared propeller dimensions from the current package, V-22 has two declared motors, and geometry/aerodynamic/installation compatibility still needs proof. Do not infer a layout or energy family solely from the model's name.

## Reused auxiliary geometry is a correspondence question

| Auxiliary SHA-256 prefix | Occurrences | Meaning |
| --- | ---: | --- |
| `e9316bbc9cb36011` | 15 | Identical `PlaneParamModel.ac` in the Ken pack, including Beginair; not independent aircraft-specific geometry/installation evidence |
| `6fe7e4806c13bda5` | 4 | Another shared parameter-model byte set across Tiburon and three pack models |
| `c2ce7bc5cff30696` | 2 | Identical `fmodel.ac` in Extra and Air Guard; filename presence alone does not prove its role or source-to-render correspondence |

The machine ledger preserves complete hashes and occurrences. Interpret these files with their source declarations and scale/frame rules. Do not copy a shared `electricMotor` object's meaning into every aircraft that happens to include that mesh.

## Concrete continuation for Phase 0A

Use **Extra 330 Red as a translation reference**, because its v6 sections provide named motor, propeller, servo and surface relationships. Before selecting it for flight, resolve:

1. Mass/geometry/frame semantics and correspondence between render and physical input members.
2. Actual installation/energy meaning, including RPM/power-table axes and the 18×7 declaration. A watt table does not establish finite-battery electrical parameters.
3. Aerodynamic coefficient/law correspondence and independent force/moment expectations.
4. Functional gear/contact requirements and the supported start policy.
5. The named capability/domain/data prerequisite, its owner and acceptance evidence. Then reassess the actual flight specimen and freeze Phase 0B.

Beginair remains the v5 shared-template counterexample. Preserve B-52/V-22 multiplicity and the v6 inferred-unit cases in negative tests. The synthetic Stik battery record and estimated Creator template remain useful software fixtures; neither is independent physical evidence that this source corpus is compatible. No battery, propeller curve, reduced mass or omitted gear may be invented to force a pass.

The [implementation guide](../implementation-guide.md#2-turn-source-selection-into-a-decision) specifies the per-property disposition table. Complete that table for one candidate; this lexical ledger does not close Phase 0A by itself.
