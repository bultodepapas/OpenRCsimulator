#!/usr/bin/env python3
"""Generate the explicit, offline game-cost companion without modifying aircraft physics."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import build_runtime

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("research/crash-economics/cost-profiles.json")
OUTPUT = Path("app/data/economy/cost-profiles.json")
FORMAT = "openrc-cost-profiles v2"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(root: Path = ROOT) -> dict:
    source, source_bytes = build_runtime._read_json(root / SOURCE)
    legacy, context = build_runtime.build_runtime_data(root)
    if set(source) != {"format", "policy_version", "price_date", "assumptions", "aircraft"} \
            or source["format"] != FORMAT or source["policy_version"] != "local-contact-v1":
        raise ValueError("unsupported cost profile source")
    build_runtime._date(source["price_date"], "price_date")
    if not isinstance(source["assumptions"], list) or not source["assumptions"]:
        raise ValueError("game profiles require explicit assumptions")
    routes = context["routes"]
    expected = {row["aircraft_id"] for row in legacy["aircraft"] if row["components"]}
    if set(source["aircraft"]) != expected:
        raise ValueError("every fixed-wing route needs an explicit profile; unsupported routes stay excluded")
    result = {"format": FORMAT, "policy_version": source["policy_version"],
              "price_date": source["price_date"], "assumptions": source["assumptions"],
              "generated_from": {"source_sha256": digest(source_bytes),
                                 "legacy_catalog_sha256": digest(build_runtime.render_runtime_json(legacy)),
                                 "generator_sha256": digest(Path(__file__).read_bytes().replace(b"\r\n", b"\n"))},
              "aircraft": {}}
    for aircraft_id, profile in source["aircraft"].items():
        if set(profile) != {"components", "zones", "propeller_component_id", "propeller_inspection_ids", "assumptions", "shared_parent_children", "source_hashes"}:
            raise ValueError(f"{aircraft_id}: unknown/missing profile fields")
        physical, raw = build_runtime._read_json(root / "app" / routes[aircraft_id].removeprefix("res://"))
        inventory = {row["id"] for row in physical["inventory"]}
        component_ids: set[str] = set()
        ownership: set[str] = set()
        parent_children: dict[str, list[str]] = {}
        old = next(d for d in legacy["aircraft"] if d["aircraft_id"] == aircraft_id)
        old_components = {c["id"]: c for c in old["components"]}
        for component in profile["components"]:
            keys = {"id", "quantity", "unit_minor", "low_unit_minor", "high_unit_minor", "physical_inventory_ids", "price_basis", "offer_id", "notes"}
            if set(component) != keys or component["id"] in component_ids:
                raise ValueError(f"{aircraft_id}: invalid/duplicate financial component")
            component_ids.add(build_runtime._require_string(component["id"], "component id"))
            build_runtime._require_int(component["quantity"], "quantity", minimum=1, maximum=1000000)
            for key in ("unit_minor", "low_unit_minor", "high_unit_minor"):
                build_runtime._require_int(component[key], key)
            if not component["low_unit_minor"] <= component["unit_minor"] <= component["high_unit_minor"]:
                raise ValueError("invalid price bounds")
            if component["price_basis"] not in ("estimated", "price_proxy", "exact_product_price") or not component["notes"]:
                raise ValueError("every cost needs a labeled basis")
            if component["offer_id"] is not None:
                original = old_components.get(component["id"], {})
                if component["offer_id"] != original.get("offer_id") or component["unit_minor"] != original.get("unit_minor"):
                    raise ValueError("retained offer/price differs from validated legacy costing")
            elif component["price_basis"] == "exact_product_price":
                raise ValueError("an exact product price requires a validated offer")
            parents = component["physical_inventory_ids"]
            if not isinstance(parents, list) or not parents or not all(isinstance(p, str) for p in parents) or len(parents) != len(set(parents)):
                raise ValueError("material financial components require distinct physical parents")
            for parent in parents:
                if parent not in inventory:
                    raise ValueError(f"{aircraft_id}: unknown physical parent {parent}")
                # Shared parents are allowed ONLY for explicitly disjoint financial children.
                ownership.add(parent)
                parent_children.setdefault(parent, []).append(component["id"])
        shared = {p: sorted(children) for p, children in parent_children.items() if len(children) > 1}
        if shared != {p: sorted(children) for p, children in profile["shared_parent_children"].items()}:
            raise ValueError(f"{aircraft_id}: shared parent requires an exact reviewed child crosswalk")
        excluded = {i for row in old["exclusions"] for i in row["physical_inventory_ids"]}
        if ownership | excluded != inventory or ownership & excluded:
            raise ValueError(f"{aircraft_id}: physical parent coverage gap/overlap")
        known = {("hull", p) for p in physical["crash_hull_ids"]}
        known |= {("gear", p["id"]) for p in physical.get("landing_gear", {}).get("contacts", [])}
        if physical.get("propulsion", {}).get("propeller"):
            known.add(("propeller", "propeller/" + physical["propulsion"]["id"]))
        seen: set[tuple[str, str]] = set()
        for zone in profile["zones"]:
            if set(zone) != {"source", "probe_id", "component_ids", "response"}:
                raise ValueError("invalid zone fields")
            key = (zone["source"], zone["probe_id"])
            if key not in known or key in seen or not zone["component_ids"] or not set(zone["component_ids"]) <= component_ids:
                raise ValueError(f"{aircraft_id}: invalid zone {key}")
            seen.add(key)
            rule = zone["response"]
            if rule == {"kind": "inspect"}:
                continue
            if rule.get("kind") != "channel_bands" or set(rule) != {"kind", "channel", "clear_below", "replace_at", "terminal_replace"}:
                raise ValueError("invalid game response rule")
            if rule["channel"] not in ("depth_m", "compression_ratio", "normal_speed_mps", "slide_speed_mps") \
                    or not isinstance(rule["terminal_replace"], bool):
                raise ValueError("unsupported game response channel")
            for threshold in (rule["clear_below"], rule["replace_at"]):
                if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not 0 <= threshold <= 10000:
                    raise ValueError("invalid response threshold")
            if rule["clear_below"] > rule["replace_at"]:
                raise ValueError("reversed response thresholds")
        if seen != known:
            raise ValueError(f"{aircraft_id}: missing qualified zones {known - seen}")
        if profile["propeller_component_id"] and profile["propeller_component_id"] not in component_ids:
            raise ValueError("invalid propeller component")
        if not set(profile["propeller_inspection_ids"]) <= component_ids:
            raise ValueError("invalid powertrain inspection targets")
        # Exact bytes pin both registered installation variants. No weak name/mass fallback.
        hashes = [digest(raw)]
        catalog_text = (root / "app/app_state/aircraft_catalog.gd").read_text(encoding="utf-8")
        import re
        blocks = re.findall(r'^\s*\{\s*$([\s\S]*?)^\s*\},', catalog_text, re.M)
        entry = next((block for block in blocks if re.search(r'^\s*id\s*=\s*"' + re.escape(aircraft_id) + r'"', block, re.M)), "")
        battery = re.search(r'battery_data\s*=\s*"(res://[^"]+)"', entry)
        if battery:
            hashes.append(digest((root / "app" / battery.group(1).removeprefix("res://")).read_bytes()))
        if sorted(set(hashes)) != profile["source_hashes"]:
            raise ValueError(f"{aircraft_id}: selected installation changed; review source hashes, mappings and prices before authoring")
        result["aircraft"][aircraft_id] = dict(profile)
    return result


def render(document: dict) -> bytes:
    return (json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        payload = render(build())
        target = ROOT / OUTPUT
        if args.check:
            if not target.exists() or target.read_bytes() != payload:
                raise ValueError("stale game cost profiles; regenerate with build_profiles.py")
        else:
            target.write_bytes(payload)
        print("Game cost profiles current: 11 fixed-wing routes; X-Cell unsupported")
        return 0
    except (ValueError, OSError, build_runtime.ContractError) as exc:
        print(f"build_profiles: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
