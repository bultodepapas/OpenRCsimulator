#!/usr/bin/env python3
"""Build the versioned aircraft-economics runtime sidecar from research sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RESEARCH_DIR = Path("research/crash-economics")
PRICE_CATALOG_PATH = RESEARCH_DIR / "catalog.json"
COSTING_PATH = RESEARCH_DIR / "aircraft-costing.json"
AIRCRAFT_CATALOG_PATH = Path("app/app_state/aircraft_catalog.gd")
OUTPUT_PATH = Path("app/data/economy/catalog.json")
FORMAT = "openrc-aircraft-economics v1"
PRICE_FORMAT = "openrc-price-catalog v1-draft"
COSTING_FORMAT = "openrc-aircraft-costing-research v1"
MAX_MINOR = 9_000_000_000_000_000
MAX_QUANTITY = 1_000_000
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class ContractError(ValueError):
    """Raised when source or generated data violates the economics contract."""


def _fail(message: str) -> None:
    raise ContractError(message)


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            _fail(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    _fail(f"non-finite JSON number is not allowed: {value}")


def _read_json(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        _fail(f"cannot read {path.as_posix()}: {exc}")
    if not data:
        _fail(f"empty JSON source: {path.as_posix()}")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        _fail(f"invalid JSON in {path.as_posix()}: {exc}")
    if not isinstance(value, dict):
        _fail(f"expected a JSON object in {path.as_posix()}")
    return value, data


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _require_string(value: Any, label: str, *, nonempty: bool = True) -> str:
    if not isinstance(value, str) or (nonempty and not value.strip()):
        _fail(f"{label}: expected a nonempty string")
    return value


def _require_int(value: Any, label: str, *, minimum: int = 0, maximum: int = MAX_MINOR) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        _fail(f"{label}: expected an integer")
    if value < minimum or value > maximum:
        _fail(f"{label}: must be within {minimum}..{maximum}")
    return value


def _date(value: Any, label: str) -> str:
    text = _require_string(value, label)
    if not DATE_RE.fullmatch(text):
        _fail(f"{label}: expected YYYY-MM-DD")
    try:
        from datetime import date

        date.fromisoformat(text)
    except ValueError:
        _fail(f"{label}: invalid calendar date")
    return text


def _parse_aircraft_routes(text: str) -> dict[str, str]:
    """Read the IDs and fixed data paths from the authoritative app catalog."""
    marker = re.search(r"(?m)^const ENTRIES := \[\s*$", text)
    if marker is None:
        _fail("aircraft catalog: ENTRIES array was not found")
    closing = re.search(r"(?m)^\]\s*$", text[marker.end() :])
    if closing is None:
        _fail("aircraft catalog: ENTRIES array was not closed")
    section = text[marker.end() : marker.end() + closing.start()]
    routes: dict[str, str] = {}
    block: list[str] | None = None
    for line in section.splitlines():
        if block is None:
            if re.match(r"^\s*\{", line):
                block = [line]
            continue
        block.append(line)
        if re.match(r"^\s*\},\s*(?:#.*)?$", line):
            body = "\n".join(block)
            id_match = re.search(r'(?m)^\s*id\s*=\s*"([^"\r\n]+)"\s*,?\s*$', body)
            data_match = re.search(r'(?m)^\s*data\s*=\s*"([^"\r\n]*)"\s*,?\s*$', body)
            if id_match is None or data_match is None:
                _fail("aircraft catalog: every entry must declare an ID and data path")
            aircraft_id = id_match.group(1)
            data_uri = data_match.group(1)
            if aircraft_id in routes:
                _fail(f"aircraft catalog: duplicate route ID {aircraft_id}")
            if not data_uri.startswith("res://data/aircraft/"):
                _fail(f"aircraft catalog: {aircraft_id} must use its fixed aircraft data path")
            relative = PurePosixPath(data_uri.removeprefix("res://"))
            if relative.is_absolute() or ".." in relative.parts or "\\" in data_uri:
                _fail(f"aircraft catalog: unsafe data path for {aircraft_id}")
            routes[aircraft_id] = data_uri
            block = None
    if block is not None:
        _fail("aircraft catalog: unterminated entry")
    if not routes:
        _fail("aircraft catalog: no routes were discovered")
    return routes


def _aircraft_catalog_discovery_identity(source_bytes: bytes) -> tuple[str, dict[str, str]]:
    """Hash UTF-8 catalog text with canonical LF endings and discover its fixed routes."""
    try:
        text = source_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        _fail(f"cannot read aircraft catalog source: {exc}")
    normalized_text = text.replace("\r\n", "\n").replace("\r", "\n")
    normalized_bytes = normalized_text.encode("utf-8")
    return _sha256(normalized_bytes), _parse_aircraft_routes(normalized_text)


def _inventory_rows(source: dict[str, Any], aircraft_id: str) -> list[dict[str, Any]]:
    raw = source.get("inventory", [])
    if not isinstance(raw, list):
        _fail(f"{aircraft_id}.inventory: expected an array")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, row in enumerate(raw):
        if not isinstance(row, dict):
            _fail(f"{aircraft_id}.inventory[{index}]: expected an object")
        item_id = _require_string(row.get("id"), f"{aircraft_id}.inventory[{index}].id")
        if item_id in seen:
            _fail(f"{aircraft_id}.inventory: duplicate physical ID {item_id}")
        seen.add(item_id)
        result.append(row)
    return result


def _is_virtual_inventory(row: dict[str, Any]) -> bool:
    item_id = str(row.get("id", "")).lower()
    name = str(row.get("name", "")).lower()
    return "virtual" in item_id or "virtual reference-build balancing mass" in name


def _source_contact_ids(source: dict[str, Any]) -> set[str]:
    valid: set[str] = set()
    hull_ids = source.get("crash_hull_ids", [])
    if isinstance(hull_ids, list):
        valid.update(item for item in hull_ids if isinstance(item, str))
    gear = source.get("landing_gear", {})
    contacts = gear.get("contacts", []) if isinstance(gear, dict) else []
    if isinstance(contacts, list):
        valid.update(
            row["id"] for row in contacts if isinstance(row, dict) and isinstance(row.get("id"), str)
        )
    propulsion = source.get("propulsion", {})
    if isinstance(propulsion, dict) and isinstance(propulsion.get("id"), str):
        if isinstance(propulsion.get("propeller"), dict):
            valid.add(f"propeller/{propulsion['id']}")
    return valid


def _products_and_offers(price_catalog: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, dict[str, Any]]]:
    products_raw = price_catalog.get("products")
    observations_raw = price_catalog.get("observations")
    if not isinstance(products_raw, list) or not isinstance(observations_raw, list):
        _fail("price catalog: products and observations must be arrays")
    products: list[dict[str, Any]] = []
    product_ids: set[str] = set()
    for index, product in enumerate(products_raw):
        if not isinstance(product, dict):
            _fail(f"price catalog.products[{index}]: expected an object")
        product_id = _require_string(product.get("id"), f"products[{index}].id")
        if product_id in product_ids:
            _fail(f"price catalog.products: duplicate ID {product_id}")
        product_ids.add(product_id)
        products.append({
            "id": product_id,
            "brand": _require_string(product.get("brand"), f"products[{index}].brand"),
            "sku": _require_string(product.get("sku"), f"products[{index}].sku"),
            "name": _require_string(product.get("name"), f"products[{index}].name"),
            "category": _require_string(product.get("category"), f"products[{index}].category"),
            "physical_compatibility": _require_string(
                product.get("physical_compatibility"), f"products[{index}].physical_compatibility"
            ),
            "partner_status": _require_string(product.get("partner_status"), f"products[{index}].partner_status"),
        })

    offers: list[dict[str, Any]] = []
    offer_by_id: dict[str, dict[str, Any]] = {}
    for index, observation in enumerate(observations_raw):
        if not isinstance(observation, dict):
            _fail(f"price catalog.observations[{index}]: expected an object")
        offer_id = _require_string(observation.get("id"), f"observations[{index}].id")
        if offer_id in offer_by_id:
            _fail(f"price catalog.observations: duplicate ID {offer_id}")
        product_id = _require_string(observation.get("product_id"), f"observations[{index}].product_id")
        if product_id not in product_ids:
            _fail(f"offer {offer_id}: unknown product ID {product_id}")
        currency = _require_string(observation.get("currency"), f"observations[{index}].currency")
        if currency != "USD":
            _fail(f"offer {offer_id}: runtime v1 requires USD")
        offer = {
            "id": offer_id,
            "product_id": product_id,
            "amount_minor": _require_int(observation.get("amount_minor"), f"offers[{index}].amount_minor"),
            "currency": currency,
            "observed_on": _date(observation.get("observed_on"), f"offers[{index}].observed_on"),
            "seller_domain": _require_string(observation.get("seller_domain"), f"offers[{index}].seller_domain"),
            "market": _require_string(observation.get("market"), f"offers[{index}].market"),
            "condition": _require_string(observation.get("condition"), f"offers[{index}].condition"),
            "price_kind": _require_string(observation.get("price_kind"), f"offers[{index}].price_kind"),
            "availability": _require_string(observation.get("availability"), f"offers[{index}].availability"),
            "sold_package_quantity": _require_int(
                observation.get("sold_package_quantity"), f"offers[{index}].sold_package_quantity", minimum=1, maximum=MAX_QUANTITY
            ),
            "package_description": _require_string(observation.get("package_description"), f"offers[{index}].package_description"),
            "tax_shipping": _require_string(observation.get("tax_shipping"), f"offers[{index}].tax_shipping"),
            "source_url": _require_string(observation.get("source_url"), f"offers[{index}].source_url"),
            "evidence_quality": _require_string(observation.get("evidence_quality"), f"offers[{index}].evidence_quality"),
            "notes": _require_string(observation.get("notes"), f"offers[{index}].notes"),
        }
        offer_by_id[offer_id] = offer
        offers.append(offer)
    return products, offers, offer_by_id


def _validate_source_hashes(root: Path, price_catalog: dict[str, Any]) -> dict[str, str]:
    hashes = price_catalog.get("source_hashes")
    if not isinstance(hashes, dict):
        _fail("price catalog.source_hashes: expected an object")
    allowed = {
        "price-research-components.json": RESEARCH_DIR / "price-research-components.json",
        "price-research-fleet.json": RESEARCH_DIR / "price-research-fleet.json",
    }
    if set(hashes) != set(allowed):
        _fail("price catalog.source_hashes: expected the two pinned research JSON sources")
    verified: dict[str, str] = {}
    for name, relative_path in allowed.items():
        expected = hashes[name]
        if not isinstance(expected, str) or not SHA256_RE.fullmatch(expected):
            _fail(f"price catalog.source_hashes.{name}: expected lowercase SHA-256")
        actual = _sha256((root / relative_path).read_bytes())
        if actual != expected:
            _fail(f"price catalog.source_hashes.{name}: stale source hash")
        verified[name] = actual
    return verified


def _inventory_signature(source: dict[str, Any], aircraft_id: str) -> dict[str, tuple[Any, ...]]:
    """Compare saleable physical identities, not balance ballast or inertia envelopes."""
    result: dict[str, tuple[Any, ...]] = {}
    for row in _inventory_rows(source, aircraft_id):
        if _is_virtual_inventory(row):
            continue
        item_id = str(row["id"])
        name = str(row.get("name", "")).strip().casefold()
        energy_source = str(row.get("energy_source", ""))
        if item_id.endswith("fuel_main") and energy_source == "glow_fuel":
            name = "onboard glow fuel"
        mass = row.get("mass", {})
        position = row.get("position", {})
        mass_value = mass.get("value") if isinstance(mass, dict) else None
        position_value = position.get("value") if isinstance(position, dict) else None
        result[item_id] = (name, json.dumps(mass_value, sort_keys=True), json.dumps(position_value, sort_keys=True), energy_source)
    return result


def _baseline_components(baseline: dict[str, Any], offers: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    lines = baseline.get("lines")
    if not isinstance(lines, list):
        _fail("costing baseline.lines: expected an array")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, line in enumerate(lines):
        if not isinstance(line, dict):
            _fail(f"costing baseline.lines[{index}]: expected an object")
        component_id = _require_string(line.get("id"), f"baseline.lines[{index}].id")
        if component_id in seen:
            _fail(f"costing baseline.lines: duplicate component ID {component_id}")
        seen.add(component_id)
        quantity = _require_int(line.get("quantity"), f"baseline.lines[{index}].quantity", minimum=1, maximum=MAX_QUANTITY)
        reference_id = line.get("price_observation", line.get("reference_observation"))
        if reference_id is not None:
            reference_id = _require_string(reference_id, f"baseline.lines[{index}].price_observation")
            if reference_id not in offers:
                _fail(f"baseline component {component_id}: unknown offer reference {reference_id}")
        raw_price = line.get("estimated_unit_minor")
        if raw_price is None and reference_id is not None:
            raw_price = offers[reference_id]["amount_minor"]
        unit_minor: int | None = None if raw_price is None else _require_int(
            raw_price, f"baseline.lines[{index}].unit_minor"
        )
        if unit_minor is None and reference_id is not None:
            _fail(f"baseline component {component_id}: referenced offer cannot have an unknown amount")
        basis = _require_string(line.get("evidence_kind"), f"baseline.lines[{index}].evidence_kind")
        if basis not in {"estimated", "price_proxy", "exact_product_price"}:
            _fail(f"baseline component {component_id}: unsupported evidence_kind {basis}")
        if basis in {"price_proxy", "exact_product_price"} and reference_id is None:
            _fail(f"baseline component {component_id}: priced component requires an offer reference")
        range_value = line.get("range_unit_minor")
        if range_value is None:
            low_minor = high_minor = None
        else:
            if not isinstance(range_value, list) or len(range_value) != 2:
                _fail(f"baseline component {component_id}: range_unit_minor must have two integer bounds")
            low_minor = _require_int(range_value[0], f"baseline component {component_id}.low_unit_minor")
            high_minor = _require_int(range_value[1], f"baseline component {component_id}.high_unit_minor")
            if low_minor > high_minor:
                _fail(f"baseline component {component_id}: low range exceeds high range")
            if unit_minor is not None and not low_minor <= unit_minor <= high_minor:
                _fail(f"baseline component {component_id}: unit amount is outside its range")
        raw_ids = line.get("physical_inventory_ids")
        if not isinstance(raw_ids, list):
            _fail(f"baseline component {component_id}: physical_inventory_ids must be an array")
        physical_ids: list[str] = []
        for physical_id in raw_ids:
            physical_ids.append(_require_string(physical_id, f"baseline component {component_id}.physical_inventory_ids[]"))
        if len(set(physical_ids)) != len(physical_ids):
            _fail(f"baseline component {component_id}: duplicate physical inventory binding")
        result.append({
            "id": component_id,
            "quantity": quantity,
            "unit_minor": unit_minor,
            "low_unit_minor": low_minor,
            "high_unit_minor": high_minor,
            "physical_inventory_ids": physical_ids,
            "price_basis": basis,
            "offer_id": reference_id,
            "notes": _require_string(line.get("notes"), f"baseline component {component_id}.notes"),
        })
    return result


def _baseline_exclusions(baseline: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    rows = baseline.get("inventory_exclusions", [])
    if not isinstance(rows, list):
        _fail("baseline.inventory_exclusions: expected an array")
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            _fail(f"baseline.inventory_exclusions[{index}]: expected an object")
        physical_id = _require_string(row.get("physical_inventory_id"), f"baseline.inventory_exclusions[{index}].physical_inventory_id")
        if physical_id in seen:
            _fail(f"baseline exclusions: duplicate physical ID {physical_id}")
        seen.add(physical_id)
        result.append({
            "id": physical_id,
            "scope": "inventory",
            "physical_inventory_ids": [physical_id],
            "reason": _require_string(row.get("reason"), f"baseline exclusion {physical_id}.reason"),
        })
    excluded = baseline.get("excluded", [])
    if not isinstance(excluded, list):
        _fail("baseline.excluded: expected an array")
    for item in excluded:
        text = _require_string(item, "baseline.excluded[]")
        identifier = re.sub(r"[^a-z0-9]+", "_", text.casefold()).strip("_")
        if identifier in seen:
            _fail(f"baseline exclusions: duplicate ID {identifier}")
        seen.add(identifier)
        result.append({
            "id": identifier,
            "scope": "outside_build",
            "physical_inventory_ids": [],
            "reason": f"Excluded from the reconstructed crash-loss build: {text}.",
        })
    return result


def _variant_components(
    aircraft_id: str, entry: dict[str, Any], source: dict[str, Any],
    base_source: dict[str, Any], base_components: list[dict[str, Any]],
    offers: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    """Replace whole economic groups only after explicit physical identity reconciliation."""
    overrides = _baseline_components({"lines": entry["component_overrides"]}, offers)
    if not overrides:
        _fail(f"{aircraft_id}: component_overrides must not be empty")
    base_by_id = {row["id"]: row for row in base_components}
    override_by_id = {row["id"]: row for row in overrides}
    replaced_inventory: set[str] = set()
    for component in overrides:
        component_id = component["id"]
        if component_id not in base_by_id:
            _fail(f"{aircraft_id}: unknown override component {component_id}")
        original = base_by_id[component_id]
        physical_ids = set(component["physical_inventory_ids"])
        if not physical_ids or physical_ids != set(original["physical_inventory_ids"]):
            _fail(f"{aircraft_id}: override {component_id} must retain its complete physical coverage group")
        if component["quantity"] != original["quantity"]:
            _fail(f"{aircraft_id}: override {component_id} changes installed quantity; author a separate BOM")
        if replaced_inventory & physical_ids:
            _fail(f"{aircraft_id}: overlapping override coverage")
        replaced_inventory.update(physical_ids)

    expected_rows = entry.get("expected_inventory")
    if not isinstance(expected_rows, list):
        _fail(f"{aircraft_id}: expected_inventory must explicitly pin every replaced physical item")
    actual_rows = {row["id"]: row for row in _inventory_rows(source, aircraft_id)}
    expected_ids: set[str] = set()
    for row in expected_rows:
        keys = {"id", "name", "mass_kg", "position_m", "energy_source"}
        if not isinstance(row, dict) or set(row) != keys:
            _fail(f"{aircraft_id}: expected_inventory row must have exactly {sorted(keys)}")
        item_id = _require_string(row["id"], f"{aircraft_id}.expected_inventory.id")
        if item_id in expected_ids or item_id not in replaced_inventory:
            _fail(f"{aircraft_id}: duplicate or unbound expected inventory {item_id}")
        expected_ids.add(item_id)
        actual = actual_rows.get(item_id, {})
        mass = actual.get("mass", {})
        position = actual.get("position", {})
        if mass.get("unit") != "kg" or position.get("unit") != "m":
            _fail(f"{aircraft_id}: override inventory {item_id} requires kg/m source quantities")
        expected_mass = row["mass_kg"]
        expected_position = row["position_m"]
        if type(expected_mass) not in (int, float) or expected_mass <= 0 \
                or not isinstance(expected_position, list) or len(expected_position) != 3 \
                or any(type(value) not in (int, float) for value in expected_position):
            _fail(f"{aircraft_id}: expected_inventory requires numeric mass and three position coordinates")
        if row["name"] != actual.get("name") or expected_mass != mass.get("value") \
                or expected_position != position.get("value") \
                or row["energy_source"] != actual.get("energy_source", ""):
            _fail(f"{aircraft_id}: override inventory identity mismatch for {item_id}")
    if expected_ids != replaced_inventory:
        _fail(f"{aircraft_id}: expected_inventory must cover every replaced physical item")

    base_signature = _inventory_signature(base_source, "baseline")
    variant_signature = _inventory_signature(source, aircraft_id)
    if set(base_signature) != set(variant_signature):
        _fail(f"{aircraft_id}: variant inventory additions/removals require a separate BOM")
    for item_id in base_signature.keys() - replaced_inventory:
        if base_signature[item_id] != variant_signature[item_id]:
            _fail(f"{aircraft_id}: unreviewed inherited inventory difference for {item_id}")

    expected_propulsion = entry.get("expected_propulsion")
    propulsion = source.get("propulsion", {})
    actual_propulsion = {
        "id": propulsion.get("id"), "kind": propulsion.get("kind"),
        "engine_name": propulsion.get("engine", {}).get("name"),
        "propeller_name": propulsion.get("propeller", {}).get("name"),
    }
    if expected_propulsion != actual_propulsion \
            or propulsion.get("id") != base_source.get("propulsion", {}).get("id"):
        _fail(f"{aircraft_id}: expected_propulsion identity/contact binding mismatch")
    # Replacement by component ID prevents donor engine/propeller double-counting.
    return [json.loads(json.dumps(override_by_id.get(row["id"], row))) for row in base_components]


def _other_exclusions(source: dict[str, Any], aircraft_id: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for row in _inventory_rows(source, aircraft_id):
        if _is_virtual_inventory(row):
            item_id = str(row["id"])
            result.append({
                "id": item_id,
                "scope": "inventory",
                "physical_inventory_ids": [item_id],
                "reason": "Virtual reference-build balancing mass; it is not a purchasable component.",
            })
    return result


def _partial_missing(
    fleet_entry: dict[str, Any], source: dict[str, Any], aircraft_id: str, offers: dict[str, dict[str, Any]],
    components: list[dict[str, Any]] | None = None,
) -> list[str]:
    components = components or []
    missing: list[str] = []
    raw_missing = fleet_entry.get("missing", [])
    if not isinstance(raw_missing, list):
        _fail(f"fleet {aircraft_id}.missing: expected an array")
    for item in raw_missing:
        missing.append(_require_string(item, f"fleet {aircraft_id}.missing[]"))
    references = fleet_entry.get("price_observations", [])
    if not isinstance(references, list):
        _fail(f"fleet {aircraft_id}.price_observations: expected an array")
    refs: list[str] = []
    for reference in references:
        ref = _require_string(reference, f"fleet {aircraft_id}.price_observations[]")
        if ref not in offers:
            _fail(f"fleet {aircraft_id}: unknown offer reference {ref}")
        if ref not in {row["offer_id"] for row in components}:
            refs.append(ref)
    if refs:
        missing.append(
            "Candidate offer references are not attached to a component until physical fit and package coverage are reconciled: "
            + ", ".join(refs)
            + "."
        )
    excluded_ids = {item_id for exclusion in _other_exclusions(source, aircraft_id) for item_id in exclusion["physical_inventory_ids"]}
    covered_ids = {item for row in components for item in row["physical_inventory_ids"]}
    uncovered = [row["id"] for row in _inventory_rows(source, aircraft_id) if row["id"] not in excluded_ids | covered_ids]
    if uncovered:
        missing.append("No reconciled economic component coverage for physical inventory IDs: " + ", ".join(uncovered) + ".")
    for component in components:
        if component["unit_minor"] is None:
            missing.append("No replacement price for economic component: " + component["id"] + ".")
    if not missing and not components:
        missing.append("No validated aircraft-specific economic BOM is available.")
    return missing


def _dossier(
    aircraft_id: str,
    source: dict[str, Any],
    source_hash: str,
    *,
    price_date: str,
    valuation_kind: str,
    components: list[dict[str, Any]],
    exclusions: list[dict[str, Any]],
    missing: list[str],
    contact_components: dict[str, list[str]] | None = None,
    propeller_component_id: str = "",
    propeller_inspection_ids: list[str] | None = None,
) -> dict[str, Any]:
    inventory_ids = {str(row["id"]) for row in _inventory_rows(source, aircraft_id)}
    covered_ids = {item_id for component in components for item_id in component["physical_inventory_ids"]}
    excluded_ids = {
        item_id
        for exclusion in exclusions
        for item_id in exclusion.get("physical_inventory_ids", [])
    }
    complete = not missing and bool(inventory_ids) and inventory_ids == (covered_ids | excluded_ids)
    return {
        "format": FORMAT,
        "aircraft_id": aircraft_id,
        "source_sha256": source_hash,
        "currency": "USD",
        "price_date": price_date,
        "valuation_kind": valuation_kind,
        "components": components,
        "exclusions": exclusions,
        "missing": missing,
        "complete": complete,
        "contact_components": {} if contact_components is None else contact_components,
        "propeller_component_id": propeller_component_id,
        "propeller_inspection_ids": [] if propeller_inspection_ids is None else propeller_inspection_ids,
    }


def _load_context(root: Path) -> dict[str, Any]:
    price_catalog, price_bytes = _read_json(root / PRICE_CATALOG_PATH)
    costing, costing_bytes = _read_json(root / COSTING_PATH)
    if price_catalog.get("format") != PRICE_FORMAT or price_catalog.get("runtime_supported") is not False:
        _fail(f"price catalog: expected unsupported research format {PRICE_FORMAT}")
    if costing.get("format") != COSTING_FORMAT or costing.get("runtime_supported") is not False:
        _fail(f"aircraft costing: expected unsupported research format {COSTING_FORMAT}")
    price_date = _date(price_catalog.get("observed_on"), "price catalog.observed_on")
    if _date(costing.get("observed_on"), "aircraft costing.observed_on") != price_date:
        _fail("price catalog and aircraft costing observation dates differ")
    research_source_hashes = _validate_source_hashes(root, price_catalog)

    catalog_path = root / AIRCRAFT_CATALOG_PATH
    try:
        catalog_bytes = catalog_path.read_bytes()
    except OSError as exc:
        _fail(f"cannot read aircraft catalog source: {exc}")
    aircraft_catalog_sha256, routes = _aircraft_catalog_discovery_identity(catalog_bytes)
    route_sources: dict[str, dict[str, Any]] = {}
    for aircraft_id, data_uri in routes.items():
        relative = PurePosixPath(data_uri.removeprefix("res://"))
        source_path = root / "app" / Path(*relative.parts)
        source, raw = _read_json(source_path)
        if source.get("format") != "openrc-aircraft v2" or source.get("id") != aircraft_id:
            _fail(f"aircraft route {aircraft_id}: physical source ID/format mismatch")
        route_sources[aircraft_id] = {
            "data_uri": data_uri,
            "source": source,
            "source_sha256": _sha256(raw),
            "inventory_rows": _inventory_rows(source, aircraft_id),
        }

    baseline = costing.get("baseline")
    if not isinstance(baseline, dict):
        _fail("aircraft costing.baseline: expected an object")
    baseline_id = _require_string(baseline.get("aircraft_id"), "baseline.aircraft_id")
    if baseline_id not in routes:
        _fail(f"baseline aircraft ID is not a live catalog route: {baseline_id}")
    source_ref = _require_string(baseline.get("physical_source"), "baseline.physical_source")
    expected_ref = "app/" + routes[baseline_id].removeprefix("res://")
    if source_ref != expected_ref:
        _fail("baseline physical_source does not match its fixed aircraft catalog route")

    fleet_raw = costing.get("fleet")
    if not isinstance(fleet_raw, list):
        _fail("aircraft costing.fleet: expected an array")
    fleet: dict[str, dict[str, Any]] = {}
    for index, entry in enumerate(fleet_raw):
        if not isinstance(entry, dict):
            _fail(f"aircraft costing.fleet[{index}]: expected an object")
        aircraft_id = _require_string(entry.get("aircraft_id"), f"fleet[{index}].aircraft_id")
        if aircraft_id in fleet:
            _fail(f"aircraft costing.fleet: duplicate route {aircraft_id}")
        fleet[aircraft_id] = entry
    if set(fleet) != set(routes):
        missing = sorted(set(routes) - set(fleet))
        extra = sorted(set(fleet) - set(routes))
        _fail(f"aircraft costing fleet route coverage differs from app catalog (missing={missing}, extra={extra})")
    if fleet[baseline_id].get("basis") != "baseline":
        _fail("baseline fleet entry must declare basis=baseline")

    products, offers, offer_by_id = _products_and_offers(price_catalog)
    return {
        "root": root,
        "price_catalog": price_catalog,
        "costing": costing,
        "price_date": price_date,
        "price_catalog_sha256": _sha256(price_bytes),
        "costing_sha256": _sha256(costing_bytes),
        "aircraft_catalog_sha256": aircraft_catalog_sha256,
        "research_source_hashes": research_source_hashes,
        "routes": routes,
        "route_sources": route_sources,
        "baseline_id": baseline_id,
        "baseline": baseline,
        "fleet": fleet,
        "products": products,
        "offers": offers,
        "offer_by_id": offer_by_id,
    }


def _build_dossiers(context: dict[str, Any]) -> list[dict[str, Any]]:
    baseline_id = context["baseline_id"]
    baseline = context["baseline"]
    base_route = context["route_sources"][baseline_id]
    base_source = base_route["source"]
    components = _baseline_components(baseline, context["offer_by_id"])
    exclusions = _baseline_exclusions(baseline)
    base_inventory_ids = {row["id"] for row in base_route["inventory_rows"]}
    base_bound = {item_id for component in components for item_id in component["physical_inventory_ids"]}
    base_excluded = {item_id for row in exclusions for item_id in row["physical_inventory_ids"]}
    if base_bound & base_excluded:
        _fail("baseline physical inventory is both priced and excluded")
    if base_bound | base_excluded != base_inventory_ids:
        _fail("baseline BOM has orphaned or unknown physical inventory coverage")
    source_exclusions = {row["physical_inventory_id"] for row in baseline.get("inventory_exclusions", [])}
    for row in base_route["inventory_rows"]:
        if _is_virtual_inventory(row) and row["id"] not in source_exclusions:
            _fail(f"baseline virtual inventory lacks an explicit source exclusion: {row['id']}")

    # The only authored event binding in this slice is the Stik propeller. It is
    # tied to the validated physical source and is inherited only with its BOM.
    propulsion = base_source.get("propulsion", {})
    if not isinstance(propulsion, dict) or propulsion.get("id") != "propulsion_main" or not isinstance(propulsion.get("propeller"), dict):
        _fail("baseline propeller contact binding does not match the physical source")
    base_component_map = {row["id"]: row for row in components}
    if "item_propeller_main" not in base_component_map.get("propeller", {}).get("physical_inventory_ids", []):
        _fail("baseline propeller component must bind item_propeller_main")
    if "item_engine_main" not in base_component_map.get("engine_and_muffler", {}).get("physical_inventory_ids", []):
        _fail("baseline engine strike inspection lacks item_engine_main")
    if "item_engine_mount" not in base_component_map.get("covered_airframe_and_installation_hardware", {}).get("physical_inventory_ids", []):
        _fail("baseline engine strike inspection lacks item_engine_mount")

    dossiers: dict[str, dict[str, Any]] = {}
    dossiers[baseline_id] = _dossier(
        baseline_id,
        base_source,
        base_route["source_sha256"],
        price_date=context["price_date"],
        valuation_kind="complete_inventory_coverage_with_cost_estimates",
        components=components,
        exclusions=exclusions,
        missing=[],
        contact_components={"propeller/propulsion_main": ["propeller"]},
        propeller_component_id="propeller",
        propeller_inspection_ids=["engine_and_muffler", "covered_airframe_and_installation_hardware"],
    )

    for aircraft_id, fleet_entry in context["fleet"].items():
        if aircraft_id == baseline_id:
            continue
        route = context["route_sources"][aircraft_id]
        source = route["source"]
        inherited_from = fleet_entry.get("inherits")
        authored = fleet_entry.get("dossier")
        if authored is not None and inherited_from is not None:
            _fail(f"{aircraft_id}: independent dossier cannot also inherit a BOM")
        override_fields = {"component_overrides", "expected_inventory", "expected_propulsion"}
        if inherited_from is None and override_fields & fleet_entry.keys():
            _fail(f"{aircraft_id}: component override fields require explicit baseline inheritance")
        if inherited_from is not None:
            if inherited_from != baseline_id:
                _fail(f"{aircraft_id}: unsupported inheritance parent {inherited_from}")
            baseline_signature = _inventory_signature(base_source, baseline_id)
            candidate_signature = _inventory_signature(source, aircraft_id)
            has_overrides = bool(override_fields & fleet_entry.keys())
            if has_overrides and not override_fields <= fleet_entry.keys():
                _fail(f"{aircraft_id}: component overrides require expected_inventory and expected_propulsion")
            if not has_overrides and baseline_signature != candidate_signature:
                raise ContractError(
                    f"{aircraft_id}: declared inherited inventory is not reconciled with {baseline_id}; refusing BOM inheritance"
                )
            inherited = json.loads(json.dumps(dossiers[baseline_id]))
            inherited["aircraft_id"] = aircraft_id
            inherited["source_sha256"] = route["source_sha256"]
            inherited["valuation_kind"] = "inherited_complete_inventory_coverage_with_cost_estimates"
            if has_overrides:
                inherited["components"] = _variant_components(
                    aircraft_id, fleet_entry, source, base_source, components, context["offer_by_id"]
                )
                inherited["valuation_kind"] = "reconciled_variant_inventory_coverage_with_cost_estimates"
            dossiers[aircraft_id] = inherited
            continue

        exclusions_for_route = _other_exclusions(source, aircraft_id)
        if authored is not None:
            required = {"expected_source_sha256", "lines", "contact_components", "propeller_component_id", "propeller_inspection_ids"}
            if not isinstance(authored, dict) or set(authored) != required:
                _fail(f"{aircraft_id}: independent dossier requires exactly {sorted(required)}")
            if authored["expected_source_sha256"] != route["source_sha256"]:
                _fail(f"{aircraft_id}: independent dossier physical source identity mismatch; review before rebinding")
            own_components = _baseline_components(authored, context["offer_by_id"])
            if not own_components:
                _fail(f"{aircraft_id}: independent dossier requires nonempty lines")
            dossiers[aircraft_id] = _dossier(
                aircraft_id, source, route["source_sha256"], price_date=context["price_date"],
                valuation_kind=_require_string(fleet_entry.get("status"), f"fleet {aircraft_id}.status"),
                components=own_components, exclusions=exclusions_for_route,
                missing=_partial_missing(fleet_entry, source, aircraft_id, context["offer_by_id"], own_components),
                contact_components=authored["contact_components"],
                propeller_component_id=authored["propeller_component_id"],
                propeller_inspection_ids=authored["propeller_inspection_ids"],
            )
            continue
        missing = _partial_missing(fleet_entry, source, aircraft_id, context["offer_by_id"])
        dossier = _dossier(
            aircraft_id,
            source,
            route["source_sha256"],
            price_date=context["price_date"],
            valuation_kind=_require_string(fleet_entry.get("status"), f"fleet {aircraft_id}.status"),
            components=[],
            exclusions=exclusions_for_route,
            missing=missing,
        )
        if dossier["complete"]:
            _fail(f"{aircraft_id}: partial fleet route unexpectedly has complete inventory coverage")
        dossiers[aircraft_id] = dossier
    return [dossiers[aircraft_id] for aircraft_id in context["routes"]]


def validate_runtime_document(document: dict[str, Any], context: dict[str, Any]) -> None:
    """Validate generated/runtime dossiers against the current catalog and sources."""
    if not isinstance(document, dict) or document.get("format") != FORMAT:
        _fail(f"runtime catalog.format must be {FORMAT}")
    if document.get("currency") != "USD":
        _fail("runtime catalog.currency must be USD")
    if _date(document.get("price_date"), "runtime catalog.price_date") != context["price_date"]:
        _fail("runtime catalog price_date is stale")
    generated_from = document.get("generated_from")
    if not isinstance(generated_from, dict):
        _fail("runtime catalog.generated_from must be an object")
    expected_generated = {
        "price_catalog_sha256": context["price_catalog_sha256"],
        "aircraft_costing_sha256": context["costing_sha256"],
        "aircraft_catalog_sha256": context["aircraft_catalog_sha256"],
        "price_research_components_sha256": context["research_source_hashes"]["price-research-components.json"],
        "price_research_fleet_sha256": context["research_source_hashes"]["price-research-fleet.json"],
    }
    if generated_from != expected_generated:
        _fail("runtime catalog.generated_from does not match exact current input bytes")

    products = document.get("products")
    offers = document.get("offers")
    if not isinstance(products, list) or not isinstance(offers, list):
        _fail("runtime catalog.products and offers must be arrays")
    product_ids: set[str] = set()
    for index, product in enumerate(products):
        if not isinstance(product, dict):
            _fail(f"runtime products[{index}]: expected an object")
        product_id = _require_string(product.get("id"), f"runtime products[{index}].id")
        if product_id in product_ids:
            _fail(f"runtime products: duplicate ID {product_id}")
        product_ids.add(product_id)
    offer_by_id: dict[str, dict[str, Any]] = {}
    for index, offer in enumerate(offers):
        if not isinstance(offer, dict):
            _fail(f"runtime offers[{index}]: expected an object")
        offer_id = _require_string(offer.get("id"), f"runtime offers[{index}].id")
        if offer_id in offer_by_id:
            _fail(f"runtime offers: duplicate ID {offer_id}")
        product_id = _require_string(offer.get("product_id"), f"runtime offers[{index}].product_id")
        if product_id not in product_ids:
            _fail(f"runtime offer {offer_id}: unknown product {product_id}")
        if offer.get("currency") != "USD":
            _fail(f"runtime offer {offer_id}: currency must be USD")
        _require_int(offer.get("amount_minor"), f"runtime offer {offer_id}.amount_minor")
        _date(offer.get("observed_on"), f"runtime offer {offer_id}.observed_on")
        _require_int(offer.get("sold_package_quantity"), f"runtime offer {offer_id}.sold_package_quantity", minimum=1, maximum=MAX_QUANTITY)
        offer_by_id[offer_id] = offer

    raw_dossiers = document.get("aircraft")
    if not isinstance(raw_dossiers, list):
        _fail("runtime catalog.aircraft must be an array")
    expected_ids = list(context["routes"])
    dossier_by_id: dict[str, dict[str, Any]] = {}
    for index, dossier in enumerate(raw_dossiers):
        if not isinstance(dossier, dict):
            _fail(f"runtime aircraft[{index}]: expected an object")
        aircraft_id = _require_string(dossier.get("aircraft_id"), f"runtime aircraft[{index}].aircraft_id")
        if aircraft_id in dossier_by_id:
            _fail(f"runtime aircraft: duplicate dossier {aircraft_id}")
        if aircraft_id not in context["route_sources"]:
            _fail(f"runtime aircraft: unknown catalog route {aircraft_id}")
        dossier_by_id[aircraft_id] = dossier
    if set(dossier_by_id) != set(expected_ids):
        _fail("runtime dossier route coverage must exactly match app/app_state/aircraft_catalog.gd")

    for aircraft_id in expected_ids:
        dossier = dossier_by_id[aircraft_id]
        route = context["route_sources"][aircraft_id]
        source = route["source"]
        if dossier.get("format") != FORMAT:
            _fail(f"{aircraft_id}: dossier format mismatch")
        source_hash = dossier.get("source_sha256")
        if not isinstance(source_hash, str) or not SHA256_RE.fullmatch(source_hash):
            _fail(f"{aircraft_id}: source_sha256 must be a lowercase SHA-256")
        if source_hash != route["source_sha256"]:
            _fail(f"{aircraft_id}: physical source hash is stale or mismatched")
        if dossier.get("currency") != "USD" or dossier.get("price_date") != context["price_date"]:
            _fail(f"{aircraft_id}: currency or price date mismatch")
        _require_string(dossier.get("valuation_kind"), f"{aircraft_id}.valuation_kind")
        if not isinstance(dossier.get("complete"), bool):
            _fail(f"{aircraft_id}.complete: expected a boolean")
        missing = dossier.get("missing")
        if not isinstance(missing, list):
            _fail(f"{aircraft_id}.missing: expected an array")
        for item in missing:
            _require_string(item, f"{aircraft_id}.missing[]")
        components = dossier.get("components")
        exclusions = dossier.get("exclusions")
        if not isinstance(components, list) or not isinstance(exclusions, list):
            _fail(f"{aircraft_id}: components and exclusions must be arrays")

        inventory_ids = {row["id"] for row in route["inventory_rows"]}
        component_ids: set[str] = set()
        bound_inventory_ids: set[str] = set()
        for index, component in enumerate(components):
            if not isinstance(component, dict):
                _fail(f"{aircraft_id}.components[{index}]: expected an object")
            component_id = _require_string(component.get("id"), f"{aircraft_id}.components[{index}].id")
            if component_id in component_ids:
                _fail(f"{aircraft_id}.components: duplicate component ID {component_id}")
            component_ids.add(component_id)
            _require_int(component.get("quantity"), f"{aircraft_id}.{component_id}.quantity", minimum=1, maximum=MAX_QUANTITY)
            unit = component.get("unit_minor")
            low = component.get("low_unit_minor")
            high = component.get("high_unit_minor")
            if unit is not None:
                _require_int(unit, f"{aircraft_id}.{component_id}.unit_minor")
            if (low is None) != (high is None):
                _fail(f"{aircraft_id}.{component_id}: low/high bounds must both be null or integers")
            if low is not None:
                _require_int(low, f"{aircraft_id}.{component_id}.low_unit_minor")
                _require_int(high, f"{aircraft_id}.{component_id}.high_unit_minor")
                if low > high or (unit is not None and not low <= unit <= high):
                    _fail(f"{aircraft_id}.{component_id}: invalid unit price range")
            basis = _require_string(component.get("price_basis"), f"{aircraft_id}.{component_id}.price_basis")
            if basis not in {"estimated", "price_proxy", "exact_product_price"}:
                _fail(f"{aircraft_id}.{component_id}: unsupported price_basis {basis}")
            offer_id = component.get("offer_id")
            if offer_id is not None:
                offer_id = _require_string(offer_id, f"{aircraft_id}.{component_id}.offer_id")
                if offer_id not in offer_by_id:
                    _fail(f"{aircraft_id}.{component_id}: unknown offer reference {offer_id}")
                if basis in {"price_proxy", "exact_product_price"} and unit != offer_by_id[offer_id].get("amount_minor"):
                    _fail(f"{aircraft_id}.{component_id}: unit amount disagrees with referenced offer package")
            elif basis in {"price_proxy", "exact_product_price"}:
                _fail(f"{aircraft_id}.{component_id}: priced component has no offer reference")
            _require_string(component.get("notes"), f"{aircraft_id}.{component_id}.notes")
            raw_physical_ids = component.get("physical_inventory_ids")
            if not isinstance(raw_physical_ids, list):
                _fail(f"{aircraft_id}.{component_id}.physical_inventory_ids: expected an array")
            local: set[str] = set()
            for physical_id in raw_physical_ids:
                physical_id = _require_string(physical_id, f"{aircraft_id}.{component_id}.physical_inventory_ids[]")
                if physical_id in local:
                    _fail(f"{aircraft_id}.{component_id}: duplicate physical ID {physical_id}")
                if physical_id not in inventory_ids:
                    _fail(f"{aircraft_id}.{component_id}: unknown physical inventory ID {physical_id}")
                if physical_id in bound_inventory_ids:
                    _fail(f"{aircraft_id}: duplicate physical coverage for {physical_id}")
                local.add(physical_id)
                bound_inventory_ids.add(physical_id)

        excluded_inventory_ids: set[str] = set()
        exclusion_ids: set[str] = set()
        for index, exclusion in enumerate(exclusions):
            if not isinstance(exclusion, dict):
                _fail(f"{aircraft_id}.exclusions[{index}]: expected an object")
            exclusion_id = _require_string(exclusion.get("id"), f"{aircraft_id}.exclusions[{index}].id")
            if exclusion_id in exclusion_ids:
                _fail(f"{aircraft_id}.exclusions: duplicate exclusion ID {exclusion_id}")
            exclusion_ids.add(exclusion_id)
            _require_string(exclusion.get("reason"), f"{aircraft_id}.exclusions[{index}].reason")
            raw_ids = exclusion.get("physical_inventory_ids")
            if not isinstance(raw_ids, list):
                _fail(f"{aircraft_id}.{exclusion_id}.physical_inventory_ids: expected an array")
            for physical_id in raw_ids:
                physical_id = _require_string(physical_id, f"{aircraft_id}.{exclusion_id}.physical_inventory_ids[]")
                if physical_id not in inventory_ids:
                    _fail(f"{aircraft_id}.{exclusion_id}: unknown physical inventory ID {physical_id}")
                if physical_id in bound_inventory_ids or physical_id in excluded_inventory_ids:
                    _fail(f"{aircraft_id}: duplicate or overlapping physical coverage for {physical_id}")
                excluded_inventory_ids.add(physical_id)

        complete = dossier["complete"]
        if complete and (bound_inventory_ids | excluded_inventory_ids) != inventory_ids:
            _fail(f"{aircraft_id}: complete dossier has orphaned physical inventory")
        if not complete and not missing:
            _fail(f"{aircraft_id}: incomplete dossier must state missing/unknown coverage")
        if complete and (missing or any(row["unit_minor"] is None for row in components)):
            _fail(f"{aircraft_id}: complete dossier cannot have missing prices or unresolved coverage")
        if (bound_inventory_ids | excluded_inventory_ids) - inventory_ids:
            _fail(f"{aircraft_id}: physical coverage contains orphaned inventory references")

        contact_components = dossier.get("contact_components")
        if not isinstance(contact_components, dict):
            _fail(f"{aircraft_id}.contact_components: expected an object")
        valid_contacts = _source_contact_ids(source)
        for contact_id, targets in contact_components.items():
            _require_string(contact_id, f"{aircraft_id}.contact_components key")
            if contact_id not in valid_contacts:
                _fail(f"{aircraft_id}.contact_components: unknown physical contact ID {contact_id}")
            if not isinstance(targets, list) or not targets:
                _fail(f"{aircraft_id}.contact_components.{contact_id}: expected a nonempty component array")
            seen_targets: set[str] = set()
            for target in targets:
                target_id = _require_string(target, f"{aircraft_id}.contact_components.{contact_id}[]")
                if target_id not in component_ids:
                    _fail(f"{aircraft_id}.contact_components.{contact_id}: unknown component ID {target_id}")
                if target_id in seen_targets:
                    _fail(f"{aircraft_id}.contact_components.{contact_id}: duplicate component ID {target_id}")
                seen_targets.add(target_id)
        propeller_component_id = dossier.get("propeller_component_id")
        if not isinstance(propeller_component_id, str):
            _fail(f"{aircraft_id}.propeller_component_id: expected a string")
        if propeller_component_id and propeller_component_id not in component_ids:
            _fail(f"{aircraft_id}.propeller_component_id: unknown component ID {propeller_component_id}")
        inspection_ids = dossier.get("propeller_inspection_ids")
        if not isinstance(inspection_ids, list):
            _fail(f"{aircraft_id}.propeller_inspection_ids: expected an array")
        if len(set(inspection_ids)) != len(inspection_ids):
            _fail(f"{aircraft_id}.propeller_inspection_ids: duplicate component IDs")
        for component_id in inspection_ids:
            if not isinstance(component_id, str) or component_id not in component_ids:
                _fail(f"{aircraft_id}.propeller_inspection_ids: unknown component ID {component_id}")
        if propeller_component_id:
            if not any(propeller_component_id in targets and contact_id.startswith("propeller/") for contact_id, targets in contact_components.items()):
                _fail(f"{aircraft_id}: propeller_component_id lacks a propeller contact mapping")


def build_runtime_data(root: Path = ROOT) -> tuple[dict[str, Any], dict[str, Any]]:
    context = _load_context(root.resolve())
    dossiers = _build_dossiers(context)
    document = {
        "format": FORMAT,
        "currency": "USD",
        "price_date": context["price_date"],
        "generated_from": {
            "price_catalog_sha256": context["price_catalog_sha256"],
            "aircraft_costing_sha256": context["costing_sha256"],
            "aircraft_catalog_sha256": context["aircraft_catalog_sha256"],
            "price_research_components_sha256": context["research_source_hashes"]["price-research-components.json"],
            "price_research_fleet_sha256": context["research_source_hashes"]["price-research-fleet.json"],
        },
        "products": context["products"],
        "offers": context["offers"],
        "aircraft": dossiers,
    }
    validate_runtime_document(document, context)
    return document, context


def render_runtime_json(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the generated sidecar without writing it")
    args = parser.parse_args(argv)
    try:
        document, context = build_runtime_data(ROOT)
        rendered = render_runtime_json(document)
        output_path = ROOT / OUTPUT_PATH
        if args.check:
            if not output_path.exists() or output_path.read_bytes() != rendered:
                print(f"stale runtime economics sidecar: {OUTPUT_PATH.as_posix()}", file=sys.stderr)
                return 1
            print(f"runtime economics sidecar is current ({len(context['routes'])} aircraft routes)")
            return 0
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(rendered)
        print(f"wrote {OUTPUT_PATH.as_posix()} ({len(context['routes'])} aircraft routes)")
        return 0
    except (ContractError, OSError) as exc:
        print(f"build_runtime: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
