"""Offline CR-38 price review queue. Never refreshes, selects or purchases an offer."""
from __future__ import annotations

import argparse
import copy
from collections import Counter
from datetime import date
import json
from pathlib import Path

import build_runtime

SALE_PRICE_KINDS = {"live_retailer_sale_price", "live_us_retailer_sale_price"}


def observation_age(observed_on: str, as_of: str, review_days: int, stale_days: int) -> dict:
    """Thresholds are inclusive; future observations are invalid evidence as of that date."""
    for value in (observed_on, as_of):
        if not isinstance(value, str) or date.fromisoformat(value).isoformat() != value:
            raise ValueError("Dates must be canonical YYYY-MM-DD")
    if type(review_days) is not int or type(stale_days) is not int or not 0 < review_days < stale_days:
        raise ValueError("Review policy requires 0 < review_after_days < stale_after_days")
    age = (date.fromisoformat(as_of) - date.fromisoformat(observed_on)).days
    status = "future_observation" if age < 0 else "stale" if age >= stale_days else "review_due" if age >= review_days else "within_review_window"
    return {"age_days": age, "review_status": status}


def _source_lines(context: dict, aircraft_id: str) -> dict:
    fleet = context["fleet"][aircraft_id]
    if aircraft_id == context["baseline_id"] or fleet.get("inherits") == context["baseline_id"]:
        rows = {row["id"]: row for row in context["baseline"]["lines"]}
        rows.update({row["id"]: row for row in fleet.get("component_overrides", [])})
        return rows
    return {row["id"]: row for row in fleet.get("dossier", {}).get("lines", [])}


def build_audit(document: dict, context: dict, as_of: str) -> dict:
    """Inputs come from build_runtime_data's validated sources; output is detached."""
    policy = context["price_catalog"]["policy"]
    review, stale = policy["review_after_days"], policy["stale_after_days"]
    observation_age(as_of, as_of, review, stale)
    usage: dict[str, list] = {offer["id"]: [] for offer in document["offers"]}
    aircraft = []
    for dossier in sorted(document["aircraft"], key=lambda row: row["aircraft_id"]):
        aircraft_id = dossier["aircraft_id"]
        authored = _source_lines(context, aircraft_id)
        components = []
        for component in sorted(dossier["components"], key=lambda row: row["id"]):
            component_id = component["id"]
            source = authored.get(component_id, {})
            references = []
            if component["offer_id"] is not None:
                references.append({"offer_id": component["offer_id"], "role": "unit_price", "quantity_per_component_unit": 1})
            for part in source.get("price_constituents", []):
                references.append({"offer_id": part["offer_id"], "role": "composite_constituent", "quantity_per_component_unit": part["quantity"]})
            # An advisory reference is not the price used by an estimated component.
            if source.get("reference_observation"):
                references.append({"offer_id": source["reference_observation"], "role": "reference_only", "quantity_per_component_unit": None})
            for reference in references:
                if reference["offer_id"] not in usage:
                    raise ValueError("Unknown authored price reference: " + reference["offer_id"])
                usage[reference["offer_id"]].append({"aircraft_id": aircraft_id, "component_id": component_id,
                    "installed_quantity": component["quantity"], **{k: v for k, v in reference.items() if k != "offer_id"}})
            amount = component["unit_minor"]
            components.append({"id": component_id, "quantity": component["quantity"], "unit_minor": amount,
                "line_minor": None if amount is None else amount * component["quantity"],
                "price_basis": component["price_basis"], "references": references,
                "physical_inventory_ids": list(component["physical_inventory_ids"]), "notes": component["notes"]})
        priced = [row for row in components if row["unit_minor"] is not None]
        known = sum(row["line_minor"] for row in priced)
        aircraft.append({"aircraft_id": aircraft_id, "inventory_cost_coverage_complete": dossier["complete"],
            "source_sha256": dossier["source_sha256"], "component_rows": len(components), "priced_component_rows": len(priced),
            "known_subtotal_minor": known if priced else None,
            "modeled_inventory_total_minor": known if dossier["complete"] and priced else None,
            "unpriced_component_ids": [row["id"] for row in components if row["unit_minor"] is None],
            "approximate_component_ids": [row["id"] for row in priced if row["price_basis"] != "exact_product_price"],
            "missing": list(dossier["missing"]), "components": components})
    products = {row["id"]: row for row in document["products"]}
    observations = []
    for offer in document["offers"]:
        product = products[offer["product_id"]]
        observations.append({"offer_id": offer["id"], "product": product["name"], "brand": product["brand"],
            "sku": product["sku"], "amount_minor": offer["amount_minor"], "currency": offer["currency"],
            **{key: offer[key] for key in ("price_kind", "condition", "market", "tax_shipping")},
            "sale_recheck_required": bool(policy.get("sale_price_requires_refresh", False)) and offer["price_kind"] in SALE_PRICE_KINDS,
            "observed_on": offer["observed_on"], **observation_age(offer["observed_on"], as_of, review, stale),
            "availability_at_observation": offer["availability"], "package_description": offer["package_description"],
            "source_url": offer["source_url"], "uses": sorted(usage[offer["id"]], key=lambda row: (row["aircraft_id"], row["component_id"], row["role"]))})
    priority = {"future_observation": 0, "stale": 1, "review_due": 2, "within_review_window": 3}
    observations.sort(key=lambda row: (priority[row["review_status"]], -row["age_days"], row["offer_id"]))
    counts = Counter(row["review_status"] for row in observations)
    return {"format": "openrc-price-review v1", "as_of": as_of, "currency": "USD",
        "catalog_snapshot_date": document["price_date"], "source_hashes": dict(document["generated_from"]),
        "policy": {"review_after_days": review, "stale_after_days": stale, "thresholds": "inclusive", "kind": "catalog_upkeep_policy"},
        "limits": ["Offline evidence review, not a live stock or compatibility check.",
                   "A date inside the review window does not guarantee today's price or availability.",
                   "Modeled inventory coverage is not a verified fully assembled retail quote or physical qualification.",
                   "Unknown rows remain null and do not become free parts; partial subtotals exclude them.",
                   "No price, dossier, archive, physical state or inventory is changed."],
        "summary": {"observations": len(observations), "aircraft_routes": len(aircraft),
                    "review_status_counts": {key: counts[key] for key in priority},
                    "unmapped_observations": sum(not row["uses"] for row in observations),
                    "sale_observations_requiring_recheck": sum(row["sale_recheck_required"] for row in observations),
                    "incomplete_aircraft": sum(not row["inventory_cost_coverage_complete"] for row in aircraft)},
        "aircraft": aircraft, "observations": observations,
        "service_parts": copy.deepcopy(context["price_catalog"].get("service_parts", []))}


def _cell(value: str) -> str:
    return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def render_markdown(audit: dict) -> str:
    lines = ["# Price review queue", "", f"As of {audit['as_of']}; catalog snapshot {audit['catalog_snapshot_date']}. Offline review only.", ""]
    lines.extend("- " + note for note in audit["limits"])
    sale_rows = [row for row in audit["observations"] if row.get("sale_recheck_required")]
    if sale_rows:
        lines += ["", "## Sale quotes requiring recheck", "", "Sale expiry is not established by the observation date. Recheck these quotes before relying on them; the age status below remains a separate calendar measure.", ""]
        lines.extend(f"- [{_cell(row['offer_id'])}]({row['source_url']}): recorded sale price; availability remains as observed." for row in sale_rows)
    lines += ["", "## Aircraft cost coverage", "", "| Aircraft | Priced rows | Known subtotal (USD) | Coverage | Unpriced rows |", "| --- | ---: | ---: | --- | --- |"]
    for row in audit["aircraft"]:
        known = row["known_subtotal_minor"]
        money = "unknown" if known is None else f"{known // 100:,}.{known % 100:02d}"
        lines.append(f"| {_cell(row['aircraft_id'])} | {row['priced_component_rows']}/{row['component_rows']} | {money} | {'complete modeled estimate' if row['inventory_cost_coverage_complete'] else 'partial / unknown'} | {_cell(', '.join(row['unpriced_component_ids']) or 'See dossier gaps')} |")
    lines += ["", "## Observations, oldest due first", "", "Unmapped observations remain research/comparators; they are not silently assigned to an aircraft.", "",
              "| Offer / source | USD per listed package | Observed | Review status | Aircraft/component uses | Availability at observation |", "| --- | ---: | --- | --- | ---: | --- |"]
    for row in audit["observations"]:
        amount = row["amount_minor"]
        lines.append(f"| [{_cell(row['offer_id'])}]({row['source_url']}) | {amount // 100:,}.{amount % 100:02d} | {row['observed_on']} | {row['review_status']} | {len(row['uses'])} | {_cell(row['availability_at_observation'])} |")
    if audit.get("service_parts"):
        by_id = {row["offer_id"]: row for row in audit["observations"]}
        lines += ["", "## Service-part references", "", "These named-model service references do not establish installed aircraft compatibility or a repair decision. A whole-engine price proxy cannot transfer mechanical fit to its service parts.", "",
                  "| Part offer | Named target model | Whole-unit price reference |", "| --- | --- | --- |"]
        for row in audit["service_parts"]:
            offer = by_id[row["part_offer_id"]]
            lines.append(f"| [{_cell(row['part_offer_id'])}]({offer['source_url']}) | {_cell(row['compatibility_evidence']['target_model'])} | {_cell(row['whole_unit_offer_id'])} |")
    lines += ["", "Component references, approximation bases, package descriptions and remaining dossier gaps are retained in the companion JSON.", ""]
    return "\n".join(lines)


def validate_output_paths(output: Path) -> None:
    """Permit repeat report generation, but refuse to overwrite unrelated source files."""
    if output.suffix.lower() != ".json":
        raise ValueError("--out must end in .json so its Markdown companion has a distinct path")
    if output.exists():
        existing = json.loads(output.read_text(encoding="utf-8"))
        if not isinstance(existing, dict) or existing.get("format") != "openrc-price-review v1":
            raise ValueError("Refusing to overwrite a file that is not a price-review report")
    markdown = output.with_suffix(".md")
    if markdown.exists() and not markdown.read_text(encoding="utf-8").startswith("# Price review queue\n"):
        raise ValueError("Refusing to overwrite an unrelated Markdown file")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--as-of", required=True, help="Explicit YYYY-MM-DD review date; no implicit wall clock")
    parser.add_argument("--out", type=Path, required=True, help="JSON report path (a Markdown companion is also written)")
    args = parser.parse_args(argv)
    try:
        validate_output_paths(args.out)
        document, context = build_runtime.build_runtime_data()
        audit = build_audit(document, context, args.as_of)
    except (ValueError, build_runtime.ContractError) as error:
        parser.error(str(error))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.out.with_suffix(".md").write_text(render_markdown(audit), encoding="utf-8")
    print(json.dumps(audit["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
