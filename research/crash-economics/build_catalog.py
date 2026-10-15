"""CR-28: normalize authored research offers and check the Stik cost arithmetic.

No network, dependencies or runtime integration. Run with --check in review/CI.
The source arrays remain dated evidence; amounts are per one sold unit/package.
"""
from __future__ import annotations

import argparse
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DATE = "2026-10-15"
SOURCES = ["price-research-components.json", "price-research-fleet.json"]


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def cents(value) -> int:
    amount = Decimal(str(value)) * 100
    assert amount.is_finite() and amount >= 0
    assert amount == amount.to_integral_value(), "Offer has fractional cents"
    return int(amount)


def rounded(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def build():
    products, observations, identities = {}, [], set()
    for source in SOURCES:
        for record in read(HERE / source):
            required = {"id", "brand", "product", "sku", "category", "amount_usd", "price_kind", "availability", "quantity", "url", "evidence_quality", "notes"}
            assert required <= record.keys(), (source, record.get("id"))
            assert record["id"] not in identities, record["id"]
            identities.add(record["id"])
            parsed = urlparse(record["url"])
            assert parsed.scheme == "https" and parsed.netloc
            assert DATE in record["notes"], "Observation date must be explicit"
            product_id = slug(record["brand"] + "_" + record["sku"])
            products.setdefault(product_id, {
                "id": product_id, "brand": record["brand"], "sku": record["sku"],
                "name": record["product"], "category": record["category"],
                "physical_compatibility": "not_established_by_price_catalog",
                "partner_status": "representation_permission_recorded" if record["brand"] == "Savox" else "not_recorded",
            })
            # The fleet source's HS-311 quantity=4 is an installation example,
            # not a four-servo retail package. All offers here sell one package.
            observations.append({
                "id": record["id"], "product_id": product_id,
                "amount_minor": cents(record["amount_usd"]), "currency": "USD",
                "observed_on": DATE, "seller_domain": parsed.netloc,
                "market": "USD storefront; destination charges not assessed",
                "condition": "new_listing", "price_kind": record["price_kind"],
                "availability": record["availability"],
                "sold_package_quantity": 1,
                "package_description": record["quantity"] if isinstance(record["quantity"], str) else "one listed item or set; see source notes for included components",
                "reference_installation_quantity": record["quantity"] if isinstance(record["quantity"], int) else None,
                "tax_shipping": "excluded_from_model; verify seller/destination charges",
                "source_url": record["url"], "source_file": source,
                "evidence_quality": record["evidence_quality"], "notes": record["notes"],
            })
    catalog = {
        "format": "openrc-price-catalog v1-draft", "runtime_supported": False,
        "observed_on": DATE, "generated_by": "research/crash-economics/build_catalog.py",
        "source_hashes": {p: hashlib.sha256((HERE / p).read_bytes()).hexdigest() for p in SOURCES},
        "policy": {"currency": "USD", "amounts": "integer cents per sold package", "review_after_days": 90, "stale_after_days": 180, "freshness_policy_kind": "gameplay_estimate", "missing_price": None, "automatic_offer_selection": False, "sale_price_requires_refresh": True},
        "products": sorted(products.values(), key=lambda r: r["id"]),
        "observations": sorted(observations, key=lambda r: r["id"]),
    }
    offers = {r["id"]: r for r in observations}
    cost = read(HERE / "aircraft-costing.json")
    baseline = cost["baseline"]
    physical_path = ROOT / baseline["physical_source"]
    aircraft = read(physical_path)
    inventory = {item["id"] for item in aircraft["inventory"]}
    coverage = Counter()
    totals = [0, 0, 0]
    lines = []
    for line in baseline["lines"]:
        q = line["quantity"]
        assert isinstance(q, int) and q > 0
        assert ("price_observation" in line) != ("estimated_unit_minor" in line)
        if "reference_observation" in line:
            assert line["reference_observation"] in offers
        nominal = offers[line["price_observation"]]["amount_minor"] if "price_observation" in line else line["estimated_unit_minor"]
        low, high = line.get("range_unit_minor", [nominal, nominal])
        assert 0 <= low <= nominal <= high
        assert all(isinstance(n, int) for n in (low, nominal, high))
        totals = [a + b * q for a, b in zip(totals, (low, nominal, high))]
        coverage.update(line["physical_inventory_ids"])
        lines.append({"id": line["id"], "quantity": q, "unit_minor": nominal, "line_minor": nominal * q})
    coverage.update(e["physical_inventory_id"] for e in baseline["inventory_exclusions"])
    assert set(coverage) == inventory, ("Missing/extra inventory", inventory ^ set(coverage))
    assert all(count == 1 for count in coverage.values()), "Double-counted inventory coverage"
    assert len({line["id"] for line in lines}) == len(lines)
    fleet_ids = {r["aircraft_id"] for r in cost["fleet"]}
    assert len(fleet_ids) == len(cost["fleet"])
    for row in cost["fleet"]:
        assert all(ref in offers for ref in row.get("price_observations", []))
    # Validate discovered production routes; no hardcoded count acceptance.
    catalog_source = (ROOT / "app/app_state/aircraft_catalog.gd").read_text(encoding="utf-8")
    actual_ids = set(re.findall(r'^\s*id = "([^"]+)"', catalog_source, re.MULTILINE))
    assert fleet_ids == actual_ids, ("Catalog coverage drift", fleet_ids ^ actual_ids)
    inputs = cost["worked_case_inputs"]
    mass = sum(Decimal(str(item["mass"]["value"])) for item in aircraft["inventory"])
    speed = Decimal(inputs["speed_kph"]) / Decimal("3.6")
    energy = mass * speed * speed / 2
    servo_price = offers["savox-sc0252mgp"]["amount_minor"]
    labor = next(line["line_minor"] for line in lines if line["id"] == "final_assembly_and_commissioning")
    patch = inputs["covering_patch"]
    sheet_area = Decimal(patch["sheet_inches"][0]) * Decimal(patch["sheet_inches"][1])
    overlap = Decimal(str(patch["overlap_inches"]))
    used_area = (Decimal(patch["tear_inches"][0]) + 2*overlap) * (Decimal(patch["tear_inches"][1]) + 2*overlap) * Decimal(str(patch["waste_multiplier"]))
    assert 0 < used_area <= sheet_area
    sheet_price = offers[patch["price_observation"]]["amount_minor"]
    material_cost = rounded(Decimal(sheet_price) * used_area / sheet_area)
    patch_labor = rounded(Decimal(str(patch["labor_hours"])) * patch["labor_rate_minor_per_hour"])
    examples = {
        "format": "openrc-crash-cost-examples v1-research", "generated_by": "research/crash-economics/build_catalog.py",
        "physical_source_sha256": hashlib.sha256(physical_path.read_bytes()).hexdigest(),
        "costing_source_sha256": hashlib.sha256((HERE / "aircraft-costing.json").read_bytes()).hexdigest(),
        "currency": "USD", "baseline_lines": lines,
        "baseline_complete_build_minor": totals[1], "baseline_diy_cash_minor": totals[1] - labor,
        "baseline_planning_range_minor": [totals[0], totals[2]],
        "impact": {"mass_kg": float(mass), "speed_kph": inputs["speed_kph"], "speed_mps": float(speed), "translational_energy_j": float(energy), "interpretation": "Input-energy calculation, not a measured structural strength or simulation result."},
        "conditional_total_loss_examples": [{"reused_servos": q, "salvage_minor": q * servo_price, "net_loss_minor": totals[1] - q * servo_price, "basis": "Conditional reuse avoidance; inspection/refit assumed within commissioning allowance; no other salvage."} for q in inputs["reusable_servo_count_cases"]],
        "propeller_only": {"parts_minor": offers["apc-lp12060"]["amount_minor"], "full_repair_total_minor": None, "reason": "Inspection/labor/shaft condition unresolved; parts-only quote is not final repair total."},
        "covering_patch": {"used_area_sq_in": float(used_area), "sheet_area_sq_in": float(sheet_area), "consumption_minor": material_cost, "purchase_minor": sheet_price, "labor_minor": patch_labor, "consumption_plus_labor_minor": material_cost + patch_labor, "purchase_plus_labor_minor": sheet_price + patch_labor, "status": "Illustrative recipe using a stale out-of-stock material price."},
        "fleet_comparisons": {"timber_bnf_plus_4s_reference_minor": offers["timber_evolution_bnf_aircraft"]["amount_minor"] + offers["timber_evolution_battery_proxy"]["amount_minor"], "jet_retract_set_minor": offers["jet_retracts_jp_hobby_er150_avanti"]["amount_minor"], "jet_turbine_package_minor": offers["jet_turbine_jetcat_p100_rx_bl_proxy"]["amount_minor"], "note": "Commercial reference configurations, not complete installed-fleet valuations."},
    }
    assert examples["baseline_complete_build_minor"] == 99433, "Update documented examples intentionally"
    assert all(0 <= r["salvage_minor"] <= totals[1] for r in examples["conditional_total_loss_examples"])
    return {"catalog.json": catalog, "worked-examples.json": examples}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Validate sources and fail if generated files differ")
    args = parser.parse_args()
    for name, document in build().items():
        content = json.dumps(document, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
        path = HERE / name
        if args.check:
            assert path.read_text(encoding="utf-8") == content, f"Stale generated file: {name}"
        else:
            path.write_text(content, encoding="utf-8", newline="\n")
    print("CR-28: offers, integer cents, baseline coverage, fleet IDs, examples and generated freshness OK")


if __name__ == "__main__":
    main()
