# CR-31b — Explicit repair candidates and package-aware costs

**Research date:** 2026-10-15. **Status:** bounded candidate-costing implementation; no repair physics, material qualification, or airworthiness finding.

## Scope

`RepairPlanner.plan(dossier, inspection, recipe_book, labor_mode)` accepts an explicit `openrc-repair-inspection v1` object and recipe dictionary. `labor_mode` is required and must be `diy` or `paid`. The inspection supplies a damage class, affected component count, evidence string, integer material measurements, labor minutes, and an explicit `replacement_comparable` flag. The planner does not read files, mutate inputs, infer damage, choose salvage, or apply a decision.

Each eligible recipe remains a separate option. Material consumption is allocated from the package price with integer-cent ceiling; cash purchase rounds the measured requirement up to full packages. Labor time is retained separately. DIY cash cost is explicitly zero by policy, not an unknown rate; paid labor uses the recipe's explicit rate. `select_option(plan, component_id, option_id, costing_basis = "cash")` returns the selected `Calculator` disposition and a finite `repair_minor` only when all required prices are known. Unknown repair cost refuses a finite repair decision. An explicitly chosen replacement may be returned with no monetary amount when the comparator is unavailable.

Every recipe also declares an exact `compatible_components` map from aircraft ID to economic component IDs. The planner requires both the aircraft and component to match before presenting a candidate, then copies the selected aircraft and applicable component IDs into repair provenance. This is a narrow research allowlist, not a physical compatibility or repair-suitability finding.

The replacement comparator uses exact dossier `unit_minor × inspected quantity` only when the inspection explicitly confirms that the dossier component and repair scope are comparable. It produces a comparison label, never an automatic selection. Duplicate component IDs and overlapping physical-inventory IDs are rejected. Recipe material IDs may not repeat within an option; alternative recipes are never summed.

## Covering price observation

The recipe uses Hangar 9 UltraCote Deep Red, SKU HANU871, as a current covering-film package-cost candidate. [Vortex Hobbies' listing](https://vortexhobbies.com/hangar-ultracote-deep-red-hanu871-p-25026.html) showed **US$22.99**, “In Stock For Shipping,” “South Jordan, UT Available Now,” and a 78 × 23.5 inch roll when retrieved on 2026-10-15. That gives 1,833 square inches; tax, shipping, final stock, color match, and compatibility with any specific airframe remain unverified. The research JSON stores this seller status and dimensions with the source.

The [Horizon Hobby HANU871 page](https://www.horizonhobby.com/product/ultracote-deep-red/HANU871.html) showed US$19.99 during the same review, but its captured availability controls were ambiguous, so the recipe uses the retailer listing that explicitly stated in-stock shipping rather than silently selecting the lower listing. These listings can change.

The old MonoKote comparison was not used as an available material: [Tower Hobbies' Cub Yellow TOPQ0220 listing](https://www.towerhobbies.com/product/top-flite-monokote-cub-yellow-6/TOPQ0220.html) showed **Out of Stock** at US$16.99. A price on an unavailable listing is not a current purchasable quote.

The paid labor rate is **US$45/hour as a scenario assumption**, not a sourced service price. DIY labor has zero monetary cost in this cash view, while entered minutes remain visible; the planner does not value owner time. Replace these assumptions with local quotes before using the output as an actual repair budget.

## Boundaries

- The film option is eligible only for an inspector-entered `covering_only` class. It cannot be selected for `structural` or `unknown` damage.
- The current map permits the four Jensen/Stik dossier IDs only on `covered_airframe_and_installation_hardware`. For the Extra 300S it permits `wing_main`, `fuselage_front`, `fuselage_rear`, `horizontal_tail`, and `vertical_tail`. Engines, other Extra components, the foam Turbo Lumber, the P-51 and unlisted aircraft/component IDs have no film candidate, even if an inspection labels them `covering_only`.
- The structural recipe row is deliberately unpriced and cannot yield a finite repair amount. No balsa, adhesive, joint, or labor specification is asserted.
- The area input is an integer number of milli-square-inches. It must already represent the explicit material requirement; no tear area, overlap allowance, or repair geometry is inferred.
- The sample UltraCote color is not matched to the Stik or any other airframe. A product price and package area do not establish fit or repair suitability.
- This is a cost comparison helper only. It does not establish component survival, salvage eligibility, strength, serviceability, or return to flight.

## Verification

The focused planner suite passes **50 checks** with pinned Godot 4.7.2 headless. It loads both the research JSON and packaged runtime sidecar and verifies they match, then covers aircraft/component applicability, explicit labor modes, covering-versus-structural eligibility, measurement/count separation, StringName measurement keys, package rounding, unknown-price refusal, comparator scope, integer bounds, duplicate inventory/material rejection, alternatives without accumulation, deterministic selection and input purity. `python research/crash-economics/build_runtime.py --check` reports the runtime economics sidecar current for all nine aircraft routes. These tests establish software behavior and integer arithmetic, not physical repair outcomes.

The covering material is also recorded in the reusable price catalog as `ultracote-hanu871-vortex-20261015`. Runtime generation rejects a recipe package price, source URL or observation date that differs from that selected offer. This keeps the standalone recipe snapshot and aircraft/parts database consistent without live price requests.
