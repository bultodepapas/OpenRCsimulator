"""Validation helpers for authored physical identities in aircraft data v2.

Identity values belong to the aircraft source records. This module validates
the resulting metadata and deliberately does not derive or assign IDs.
"""

from __future__ import annotations

import re
import math
from collections.abc import Mapping
from typing import Any


IDENTIFIER_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
SURFACE_ID_KEYS = frozenset({"aileron_left", "aileron_right", "elevator", "rudder"})
MAX_IDENTIFIER_LENGTH = 80


def validate_physical_identity(data: Mapping[str, Any]) -> None:
    """Require the complete v1 authored-identity module on one aircraft.

    Raises ``ValueError`` with the first invalid JSON-style path. IDs must be
    present on each physical source record and globally unique within the
    aircraft, including crash probes and control surfaces.
    """
    if not isinstance(data, Mapping):
        raise ValueError("aircraft: expected an object")

    version = data.get("physical_identity_version")
    if type(version) not in (int, float) or not math.isfinite(version) or version != 1:
        raise ValueError("/physical_identity_version: expected numeric 1")

    identities: dict[str, str] = {}

    def add_id(value: Any, path: str) -> None:
        if not isinstance(value, str):
            raise ValueError(f"{path}: expected string ID")
        if len(value) > MAX_IDENTIFIER_LENGTH:
            raise ValueError(f"{path}: ID exceeds {MAX_IDENTIFIER_LENGTH} characters")
        if not IDENTIFIER_PATTERN.fullmatch(value):
            raise ValueError(f"{path}: invalid ID {value!r}")
        previous = identities.get(value)
        if previous is not None:
            raise ValueError(f"{path}: ID {value!r} duplicates {previous}")
        identities[value] = path

    inventory = data.get("inventory")
    if not isinstance(inventory, list):
        raise ValueError("/inventory: expected array")
    if not inventory:
        raise ValueError("/inventory: expected at least one item")
    for index, item in enumerate(inventory):
        path = f"/inventory/{index}/id"
        if not isinstance(item, Mapping):
            raise ValueError(f"/inventory/{index}: expected object")
        if "id" not in item:
            raise ValueError(f"{path}: required ID is missing")
        add_id(item["id"], path)

    if "landing_gear" in data:
        gear = data["landing_gear"]
        if not isinstance(gear, Mapping):
            raise ValueError("/landing_gear: expected object")
        contacts = gear.get("contacts")
        if not isinstance(contacts, list):
            raise ValueError("/landing_gear/contacts: expected array")
        for index, contact in enumerate(contacts):
            path = f"/landing_gear/contacts/{index}/id"
            if not isinstance(contact, Mapping):
                raise ValueError(f"/landing_gear/contacts/{index}: expected object")
            if "id" not in contact:
                raise ValueError(f"{path}: required ID is missing")
            add_id(contact["id"], path)

    crash_hull = data.get("crash_hull")
    if not isinstance(crash_hull, Mapping):
        raise ValueError("/crash_hull: expected quantity object")
    points = crash_hull.get("value")
    if not isinstance(points, list):
        raise ValueError("/crash_hull/value: expected array")
    hull_ids = data.get("crash_hull_ids")
    if not isinstance(hull_ids, list):
        raise ValueError("/crash_hull_ids: expected array")
    if len(hull_ids) != len(points):
        raise ValueError("/crash_hull_ids: must align with /crash_hull/value")
    for index, value in enumerate(hull_ids):
        add_id(value, f"/crash_hull_ids/{index}")

    propulsion = data.get("propulsion")
    if not isinstance(propulsion, Mapping):
        raise ValueError("/propulsion: expected object")
    if "id" not in propulsion:
        raise ValueError("/propulsion/id: required ID is missing")
    add_id(propulsion["id"], "/propulsion/id")

    controls = data.get("controls")
    if not isinstance(controls, Mapping):
        raise ValueError("/controls: expected object")
    surface_ids = controls.get("surface_ids")
    if not isinstance(surface_ids, Mapping):
        raise ValueError("/controls/surface_ids: expected object")
    if set(surface_ids) != SURFACE_ID_KEYS:
        raise ValueError(
            "/controls/surface_ids: expected exactly "
            + ", ".join(sorted(SURFACE_ID_KEYS))
        )
    for key in sorted(SURFACE_ID_KEYS):
        add_id(surface_ids[key], f"/controls/surface_ids/{key}")


__all__ = [
    "IDENTIFIER_PATTERN",
    "MAX_IDENTIFIER_LENGTH",
    "SURFACE_ID_KEYS",
    "validate_physical_identity",
]
