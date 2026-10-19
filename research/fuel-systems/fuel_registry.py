"""FUEL-02: Python reader of app/data/fuels/openrc-fuel-registry.json for offline generators.

Same rules as app/physics/fuel_properties.gd: a blend's density is the volume-weighted sum of its
component densities at the blend's reference temperature; a component referenced at another
temperature is shifted by its declared slope, and refused without one. Generators call
blend_density(); they never write a density of their own.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "app" / "data" / "fuels" / "openrc-fuel-registry.json"
FORMAT = "openrc-fuel-registry v1"


def load(path: Path = REGISTRY) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if raw.get("format") != FORMAT:
        raise ValueError("unsupported fuel registry format: %r" % raw.get("format"))
    return raw


def blend_density(blend_id: str, registry: dict | None = None) -> float:
    """Density in kg/m3 of a registry blend at its reference temperature."""
    registry = load() if registry is None else registry
    blend = registry["blends"][blend_id]
    temperature = blend["reference_temperature"]["value"]
    total = 0.0
    density = 0.0
    for component_id, fraction in blend["volume_fractions"].items():
        component = registry["components"][component_id]
        rho = component["density"]["value"]
        offset = temperature - component["reference_temperature"]["value"]
        if abs(offset) > 1e-9:
            if "density_slope" not in component:
                raise ValueError("%s: %s needs a density slope" % (blend_id, component_id))
            rho += component["density_slope"]["value"] * offset
        total += fraction
        density += fraction * rho
    if abs(total - 1.0) > 1e-12:
        raise ValueError("%s: volume fractions sum to %r" % (blend_id, total))
    return density


def blend_source(blend_id: str) -> str:
    """Provenance string for data that derives a mass from this blend."""
    return "app/data/fuels/openrc-fuel-registry.json blend %s (%.2f kg/m3 at %.2f K)" % (
        blend_id, blend_density(blend_id), load()["blends"][blend_id]["reference_temperature"]["value"])
