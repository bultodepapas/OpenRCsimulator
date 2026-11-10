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
FORMAT = "openrc-cost-profiles v3"
POLICY = "local-contact-v2"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(root: Path = ROOT) -> dict:
    source, source_bytes = build_runtime._read_json(root / SOURCE)
    if b"\r" in source_bytes:
        raise ValueError("cost profile source must use the LF line endings declared in .gitattributes")
    legacy, context = build_runtime.build_runtime_data(root)
    if set(source) != {"format", "policy_version", "price_date", "assumptions", "aircraft"} \
            or source["format"] != FORMAT or source["policy_version"] != POLICY:
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
        if set(profile) != {"components", "zones", "propeller_component_id", "propeller_inspection_ids", "assumptions", "shared_parent_children", "source_hashes", "construction_class", "propeller_followups", "packages", "labor_policy"}:
            raise ValueError(f"{aircraft_id}: unknown/missing profile fields")
        if profile["construction_class"] not in ("wood", "foam", "composite"):
            raise ValueError("unsupported declared construction class")
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
            if set(zone) != {"source", "probe_id", "component_ids", "response", "component_responses"}:
                raise ValueError("invalid zone fields")
            key = (zone["source"], zone["probe_id"])
            if key not in known or key in seen or not zone["component_ids"] or not set(zone["component_ids"]) <= component_ids:
                raise ValueError(f"{aircraft_id}: invalid zone {key}")
            seen.add(key)
            overrides = zone["component_responses"]
            if not isinstance(overrides, dict) or (len(zone["component_ids"]) > 1 and set(overrides) != set(zone["component_ids"])) or not set(overrides) <= set(zone["component_ids"]):
                raise ValueError("multi-target zones require explicit per-component responses")
            _validate_response(zone["response"], set(zone["component_ids"]))
            for ident, response in overrides.items():
                _validate_response(response, {ident})
        if seen != known:
            raise ValueError(f"{aircraft_id}: missing qualified zones {known - seen}")
        if profile["propeller_component_id"] and profile["propeller_component_id"] not in component_ids:
            raise ValueError("invalid propeller component")
        if not set(profile["propeller_inspection_ids"]) <= component_ids:
            raise ValueError("invalid powertrain inspection targets")
        followup_ids = set()
        for follow in profile["propeller_followups"]:
            keys = {"component_id", "kind", "clear_speed_mps", "clear_rpm", "replace_speed_mps", "replace_rpm", "middle_action", "service_minor"}
            if not isinstance(follow, dict) or set(follow) != keys or follow["component_id"] not in profile["propeller_inspection_ids"] or follow["component_id"] in followup_ids or follow["kind"] != "powered_envelope_bands":
                raise ValueError("invalid qualified propeller follow-up")
            followup_ids.add(follow["component_id"])
            for key in ("clear_speed_mps", "clear_rpm", "replace_speed_mps", "replace_rpm"):
                val = follow[key]
                if isinstance(val, bool) or not isinstance(val, (int, float)) or not 0 <= val <= 100000:
                    raise ValueError("invalid endpoint propeller bound")
            if follow["clear_speed_mps"] > follow["replace_speed_mps"] or follow["clear_rpm"] > follow["replace_rpm"]:
                raise ValueError("reversed propeller follow-up bounds")
            if follow["middle_action"] not in ("inspect", "repair", "scope_clear"):
                raise ValueError("invalid propeller follow-up action")
            if follow["middle_action"] == "repair":
                build_runtime._require_int(follow["service_minor"], "propeller follow-up service")
            elif follow["service_minor"] is not None:
                raise ValueError("non-repair follow-up cannot charge a service")
        if followup_ids != set(profile["propeller_inspection_ids"]) - {profile["propeller_component_id"]}:
            raise ValueError("common propeller follow-up coverage is incomplete")
        _validate_purchase_book(profile["packages"], profile["components"])
        _validate_labor(profile["labor_policy"], component_ids)
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


def _validate_response(rule: object, targets: set[str]) -> None:
    if not isinstance(rule, dict):
        raise ValueError("invalid response object")
    if rule == {"kind": "inspect"}:
        return
    if rule.get("kind") != "channel_bands" or set(rule) != {"kind", "channel", "clear_below", "replace_at", "terminal_replace", "middle_action", "service_minor_by_component"}:
        raise ValueError("invalid game response rule")
    if rule["channel"] not in ("depth_m", "compression_ratio", "normal_speed_mps", "slide_speed_mps", "speed_mps", "down_speed_mps", "endpoint_normal_speed_mps", "contact_normal_proxy_mps") or not isinstance(rule["terminal_replace"], bool):
        raise ValueError("unsupported game response channel")
    for threshold in (rule["clear_below"], rule["replace_at"]):
        if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not 0 <= threshold <= 10000:
            raise ValueError("invalid response threshold")
    if rule["clear_below"] > rule["replace_at"]:
        raise ValueError("reversed response thresholds")
    if rule["middle_action"] not in ("inspect", "repair", "scope_clear") or not isinstance(rule["service_minor_by_component"], dict):
        raise ValueError("invalid middle-band game action")
    expected_services = targets if rule["middle_action"] == "repair" else set()
    if set(rule["service_minor_by_component"]) != expected_services:
        raise ValueError("service allowance must name each scoped component exactly once")
    for amount in rule["service_minor_by_component"].values():
        build_runtime._require_int(amount, "local service allowance")


def _validate_purchase_book(packages: object, components: list[dict]) -> None:
    if not isinstance(packages, list) or len(packages) > 64:
        raise ValueError("unbounded purchase book")
    known = {c["id"] for c in components}
    ids = set()
    for package in packages:
        if not isinstance(package, dict) or set(package) != {"id", "component_quantities", "cost_cents", "available", "compatible", "provenance"}:
            raise ValueError("invalid sold package fields")
        key = build_runtime._require_string(package["id"], "package id")
        if key in ids or len(key) > 128:
            raise ValueError("invalid or duplicate sold package")
        ids.add(key)
        contents = package["component_quantities"]
        if not isinstance(contents, dict) or not contents or not set(contents) <= known:
            raise ValueError("package contents require installed financial identities")
        for qty in contents.values():
            build_runtime._require_int(qty, "sold quantity", minimum=1, maximum=64)
        if sum(contents.values()) > 64:
            raise ValueError("sold package unit bound exceeded")
        if package["cost_cents"] is not None:
            build_runtime._require_int(package["cost_cents"], "package price")
        for field in ("available", "compatible"):
            if package[field] is not None and not isinstance(package[field], bool):
                raise ValueError("package eligibility must be boolean or unknown")
        note = build_runtime._require_string(package["provenance"], "package provenance")
        if len(note) > 2048:
            raise ValueError("unbounded package provenance")


def _validate_labor(policy: object, components: set[str]) -> None:
    fields = {"format", "currency", "paid_rate_minor_per_hour", "minutes_by_component", "shared_setup_minutes", "basis", "evidence"}
    if not isinstance(policy, dict) or set(policy) != fields or policy["format"] != "openrc-game-labor-policy v1" or policy["currency"] != "USD" or policy["basis"] != "authored_game_policy":
        raise ValueError("invalid game labor policy")
    build_runtime._require_int(policy["paid_rate_minor_per_hour"], "shop labor rate", maximum=1000000)
    build_runtime._require_int(policy["shared_setup_minutes"], "shared setup", maximum=60000)
    if not isinstance(policy["minutes_by_component"], dict) or set(policy["minutes_by_component"]) != components:
        raise ValueError("labor policy must explicitly cover every financial component")
    for minutes in policy["minutes_by_component"].values():
        build_runtime._require_int(minutes, "active labor minutes", maximum=60000)
    if not isinstance(policy["evidence"], str) or not policy["evidence"] or len(policy["evidence"]) > 2048:
        raise ValueError("game labor needs bounded provenance")


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
