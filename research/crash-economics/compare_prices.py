"""Compare frozen price-review snapshots without selecting or applying offers."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

import audit_prices
import build_runtime

FORMAT = "openrc-price-changes v1"
MAX_BYTES = 16 * 1024 * 1024
IDENTITY = ("brand", "sku", "product", "currency", "package_description", "source_url")
EVIDENCE = ("observed_on", "availability_at_observation")
COMMERCIAL = ("price_kind", "condition", "market", "tax_shipping")


def _index(snapshot: dict) -> dict:
    if not isinstance(snapshot, dict) or snapshot.get("format") != "openrc-price-review v1" or snapshot.get("currency") != "USD":
        raise ValueError("Expected an openrc-price-review v1 USD snapshot")
    as_of = snapshot.get("as_of")
    audit_prices.observation_age(as_of, as_of, 90, 180)
    rows = snapshot.get("observations")
    if not isinstance(rows, list) or len(rows) > 10000:
        raise ValueError("Expected at most 10000 observations")
    indexed = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("Observation must be an object")
        for key in ("offer_id", *IDENTITY, *EVIDENCE):
            if not isinstance(row.get(key), str) or not row[key].strip() or len(row[key]) > 8192:
                raise ValueError("Missing or invalid observation text: " + key)
        offer_id = row["offer_id"]
        if offer_id in indexed:
            raise ValueError("Duplicate offer identity: " + offer_id)
        if row["currency"] != "USD" or type(row.get("amount_minor")) is not int or not 0 <= row["amount_minor"] <= build_runtime.MAX_MINOR:
            raise ValueError("Price must be bounded integer USD cents")
        audit_prices.observation_age(row["observed_on"], as_of, 90, 180)
        uses = row.get("uses")
        if not isinstance(uses, list) or len(uses) > 10000:
            raise ValueError("Expected bounded aircraft uses")
        normalized_uses = []
        for use in uses:
            if not isinstance(use, dict):
                raise ValueError("Aircraft use must be an object")
            for key in ("aircraft_id", "component_id", "role"):
                if not isinstance(use.get(key), str) or not use[key].strip() or len(use[key]) > 256:
                    raise ValueError("Invalid aircraft use identity")
            quantity, per_unit = use.get("installed_quantity"), use.get("quantity_per_component_unit")
            if type(quantity) is not int or not 1 <= quantity <= build_runtime.MAX_QUANTITY:
                raise ValueError("Invalid installed quantity")
            if use["role"] not in ("unit_price", "composite_constituent", "reference_only"):
                raise ValueError("Unknown reference role")
            if use["role"] == "reference_only":
                if per_unit is not None:
                    raise ValueError("Advisory references cannot assert a billed quantity")
            elif type(per_unit) is not int or not 1 <= per_unit <= build_runtime.MAX_QUANTITY:
                raise ValueError("Invalid price-reference quantity")
            normalized_uses.append({key: use.get(key) for key in ("aircraft_id", "component_id", "role", "installed_quantity", "quantity_per_component_unit")})
        normalized_uses.sort(key=lambda value: json.dumps(value, sort_keys=True))
        if len({json.dumps(value, sort_keys=True) for value in normalized_uses}) != len(normalized_uses):
            raise ValueError("Duplicate aircraft use")
        indexed[offer_id] = {key: row[key] for key in (*IDENTITY, *EVIDENCE, "amount_minor")}
        for key in COMMERCIAL:
            value = row.get(key)
            if value is not None and (not isinstance(value, str) or not value.strip() or len(value) > 8192):
                raise ValueError("Invalid commercial term: " + key)
            indexed[offer_id][key] = value
        indexed[offer_id]["uses"] = normalized_uses
    return indexed


def compare(before: dict, after: dict) -> dict:
    old, new = _index(before), _index(after)
    if after["as_of"] < before["as_of"]:
        raise ValueError("After review date precedes before review date")
    changes = []
    for offer_id in sorted(old.keys() | new.keys()):
        left, right = old.get(offer_id), new.get(offer_id)
        # Adding previously absent commercial metadata alone is not a price change.
        fields = [] if left is None or right is None else sorted(key for key in left if left[key] != right[key]
            and (key not in COMMERCIAL or (left[key] is not None and right[key] is not None)))
        if left is not None and right is not None and not fields:
            continue
        reasons = []
        if left is None or right is None:
            kind = "added" if left is None else "removed"
            reasons.append("No paired observation; missing prices are not zero")
        else:
            reasons.extend("Changed " + key for key in IDENTITY if left[key] != right[key])
            for key in COMMERCIAL:
                if left[key] is None or right[key] is None:
                    reasons.append("Commercial term not recorded: " + key)
                elif left[key] != right[key]:
                    reasons.append("Changed " + key)
            if right["observed_on"] < left["observed_on"]:
                reasons.append("Observation date moved backwards")
            if left["observed_on"] > before["as_of"] or right["observed_on"] > after["as_of"]:
                reasons.append("Observation is in the future relative to its review date")
            kind = "terms_changed" if reasons else "price_changed" if "amount_minor" in fields else "evidence_changed" if any(key in fields for key in EVIDENCE) else "allocation_changed"
        comparable = not reasons
        changes.append({"offer_id": offer_id, "change": kind, "changed_fields": fields,
            "same_offer_price_comparable": comparable,
            "price_delta_minor": right["amount_minor"] - left["amount_minor"] if comparable else None,
            "comparison_limits": reasons, "before": left, "after": right})
    counts = Counter(row["change"] for row in changes)
    return {"format": FORMAT, "currency": "USD", "before_as_of": before["as_of"], "after_as_of": after["as_of"],
        "summary": {"before_offers": len(old), "after_offers": len(new), "changed_offers": len(changes),
                    "unchanged_offers": len(old.keys() | new.keys()) - len(changes), "change_counts": dict(sorted(counts.items()))},
        "limits": ["Offline comparison of recorded observations; no live stock or fit check.",
                   "Delta requires matching recorded product, package, seller and commercial terms; it is not a complete repair or an inflation measure.",
                   "Availability remains dated seller text; a comparable price does not mean a purchasable offer.",
                   "Aircraft uses identify references, not automatic installation or a new accident charge.",
                   "No catalog, dossier, inventory, incident or historical bill is changed."],
        "changes": changes}


def _money(amount: int | None) -> str:
    if amount is None:
        return "—"
    return ("-" if amount < 0 else "") + f"{abs(amount) // 100:,}.{abs(amount) % 100:02d}"


def render_markdown(result: dict) -> str:
    lines = ["# Price snapshot comparison", "", f"{result['before_as_of']} → {result['after_as_of']} · USD per listed package", ""]
    lines.extend("- " + limit for limit in result["limits"])
    lines += ["", "| Offer | Change | Before USD | After USD | Comparable delta USD | Review detail |", "| --- | --- | ---: | ---: | ---: | --- |"]
    for row in result["changes"]:
        before, after = row["before"] or {}, row["after"] or {}
        detail = "; ".join(row["comparison_limits"]) or ", ".join(row["changed_fields"])
        lines.append(f"| {audit_prices._cell(row['offer_id'])} | {row['change']} | {_money(before.get('amount_minor'))} | {_money(after.get('amount_minor'))} | {_money(row['price_delta_minor'])} | {audit_prices._cell(detail)} |")
    if not result["changes"]:
        lines.append("\nNo offer, recorded evidence or aircraft-reference changes.")
    lines += ["", "The JSON companion retains both dated observations, seller URLs, package descriptions and aircraft-reference roles. Review-date aging and adding previously absent commercial metadata alone are not counted as offer changes. Changed legacy observations lacking commercial terms require review and receive no numeric delta.", ""]
    return "\n".join(lines)


def read_snapshot(path: Path) -> tuple[dict, str]:
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("Snapshot exceeds 16 MiB")
    document, data = build_runtime._read_json(path)
    return document, hashlib.sha256(data).hexdigest()


def validate_output(output: Path, inputs: list[Path]) -> None:
    if output.suffix.lower() != ".json":
        raise ValueError("--out must end in .json")
    destinations = [output, output.with_suffix(".md")]
    if any(path.resolve() in {item.resolve() for item in inputs} for path in destinations):
        raise ValueError("Output cannot overwrite an input snapshot")
    if output.exists() and read_snapshot(output)[0].get("format") != FORMAT:
        raise ValueError("Refusing to overwrite an unrelated JSON file")
    if destinations[1].exists() and not destinations[1].read_text(encoding="utf-8").startswith("# Price snapshot comparison\n"):
        raise ValueError("Refusing to overwrite an unrelated Markdown file")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        validate_output(args.out, [args.before, args.after])
        before, old_hash = read_snapshot(args.before)
        after, new_hash = read_snapshot(args.after)
        result = compare(before, after)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    result["snapshot_sha256"] = {"before": old_hash, "after": new_hash}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    args.out.with_suffix(".md").write_text(render_markdown(result), encoding="utf-8")
    print(json.dumps(result["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
