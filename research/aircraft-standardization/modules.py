"""Shared AS-07 classifier for aircraft capabilities and selected physics laws."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "app" / "data" / "schema" / "aircraft-modules-v1.json"
REGISTRY_FORMAT = "openrc-aircraft-modules v1"


@lru_cache(maxsize=1)
def _registry() -> dict[str, Any]:
    try:
        value = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"module registry could not be read: {exc}") from exc
    if not isinstance(value, dict) or value.get("format") != REGISTRY_FORMAT:
        raise ValueError(f"module registry format must be exactly {REGISTRY_FORMAT!r}")
    return value


def _at_path(root: Any, path: str) -> tuple[bool, Any]:
    current = root
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def _result(
    errors: list[str],
    diagnostics: list[dict[str, str]],
    *,
    modules: list[str] | None = None,
    laws: list[str] | None = None,
    parameters: dict[str, str] | None = None,
    transforms: dict[str, bool] | None = None,
    transform_reasons: list[str] | None = None,
) -> dict[str, Any]:
    ok = not errors
    return {
        "ok": ok,
        "errors": errors,
        "diagnostics": diagnostics,
        "modules": sorted(set(modules or [])) if ok else [],
        "laws": sorted(set(laws or [])) if ok else [],
        "parameters": parameters or {} if ok else {},
        "compiler_transforms": transforms or {"scale": False, "weight": False, "power": False, "controls": False} if ok else {
            "scale": False,
            "weight": False,
            "power": False,
            "controls": False,
        },
        "compiler_transform_reasons": transform_reasons or [] if ok else [],
    }


def classify(base: Any) -> dict[str, Any]:
    """Classify a v2 source without coercing selectors or guessing from names.

    ``modules`` preserves the original Workshop module IDs. ``laws`` and
    ``parameters`` expose the normalized runtime-law selection separately.
    Every failure keeps the diagnostics and returns empty modules and laws.
    """
    errors: list[str] = []
    diagnostics: list[dict[str, str]] = []

    def issue(code: str, path: str, message: str) -> None:
        diagnostics.append({"code": code, "path": path, "message": message})
        errors.append(f"{path}: {message}" if path else message)

    try:
        registry = _registry()
    except ValueError as exc:
        issue("module.registry.invalid", "", str(exc))
        return _result(errors, diagnostics)

    if not isinstance(base, dict):
        issue("module.source.type", "/", "must be an object")
        return _result(errors, diagnostics)
    if type(base.get("format")) is not str or base.get("format") != registry.get("aircraft_format"):
        issue("module.source.version", "format", f"must be exactly {registry.get('aircraft_format')!r}")
        return _result(errors, diagnostics)

    modules: list[str] = list(registry.get("always_modules", []))
    laws: list[str] = []
    parameters: dict[str, str] = {}
    transform_reasons: list[str] = []
    selected_values: dict[str, str] = {}
    control_transform_supported = False

    capabilities = base.get("capabilities")
    if not isinstance(capabilities, dict):
        issue("module.capabilities.type", "capabilities", "must be an object")
        capabilities = {}
    expected_capability_keys = set(registry.get("capability_keys", []))
    for key in sorted(set(capabilities) - expected_capability_keys):
        issue("module.capability.unknown_field", f"capabilities.{key}", "is not a registered capability field")
    for key in registry.get("capability_keys", []):
        if key not in capabilities:
            issue("module.capability.missing", f"capabilities.{key}", "is required")
            continue
        value = capabilities[key]
        if type(value) is not str:
            issue("module.capability.type", f"capabilities.{key}", "must be a string selector")
            continue
        entry = registry.get("capabilities", {}).get(key, {}).get(value)
        if not isinstance(entry, dict):
            issue("module.capability.unknown", f"capabilities.{key}", f"has unregistered value {value!r}")
            continue
        selected_values[key] = value
        parameters[f"capabilities.{key}"] = value
        module_id = entry.get("module")
        if type(module_id) is str and module_id:
            modules.append(module_id)
        law_id = entry.get("law")
        if type(law_id) is str and law_id:
            laws.append(law_id)
        control_transform_supported = control_transform_supported or bool(
            entry.get("compiler_transforms", {}).get("controls", False)
        )
        for relation in entry.get("presence_relations", []):
            if not isinstance(relation, dict):
                continue
            related_path = relation.get("path")
            expected_presence = relation.get("present")
            if type(related_path) is not str or type(expected_presence) is not bool:
                continue
            related_exists, _ = _at_path(base, related_path)
            if related_exists is not expected_presence:
                requirement = "present" if expected_presence else "absent"
                issue(
                    "module.capability.relation",
                    f"capabilities.{key}",
                    f"requires {related_path} to be {requirement}",
                )

    propulsion = base.get("propulsion")
    if not isinstance(propulsion, dict):
        issue("module.propulsion.type", "propulsion", "must be an object")
        return _result(errors, diagnostics)
    propulsion_kind = propulsion.get("kind")
    if type(propulsion_kind) is not str:
        issue("module.propulsion.kind.type", "propulsion.kind", "must be a string selector")
        return _result(errors, diagnostics)
    family = registry.get("propulsion", {}).get(propulsion_kind)
    if not isinstance(family, dict):
        issue("module.propulsion.kind.unknown", "propulsion.kind", f"has unregistered value {propulsion_kind!r}")
        return _result(errors, diagnostics)

    allowed_fields = set(family.get("fields", []))
    for key in sorted(set(propulsion) - allowed_fields):
        issue("module.propulsion.unknown_field", f"propulsion.{key}", "is not registered for this propulsion family")
    for key in family.get("required_fields", []):
        if key not in propulsion:
            issue("module.propulsion.missing_field", f"propulsion.{key}", "is required for this propulsion family")

    modules.append(str(family["module"]))
    parameters["propulsion.kind"] = propulsion_kind
    laws.append(str(family.get("law", ""))) if family.get("law") else None

    for field, accepted in family.get("allowed_capabilities", {}).items():
        value = selected_values.get(field)
        if value is not None and value not in accepted:
            issue(
                "module.relation.unsupported",
                f"capabilities.{field}",
                f"{value!r} is incompatible with propulsion family {propulsion_kind!r}",
            )

    section_variants = family.get("section_variants", {})
    for section_name, default_fields in family.get("sections", {}).items():
        if section_name not in propulsion:
            continue
        section = propulsion[section_name]
        if not isinstance(section, dict):
            issue("module.section.type", f"propulsion.{section_name}", "must be an object")
            continue
        section_fields = default_fields
        selector = section_variants.get(section_name)
        if isinstance(selector, dict):
            selector_path = selector.get("selector_path", "")
            selector_exists, selector_value = _at_path(propulsion, selector_path)
            per_value = selector.get("fields", {})
            required_by_value = selector.get("required_fields_by_value", {})
            selected_value = ""
            if not selector_exists:
                if selector.get("selector_required", False):
                    issue(
                        "module.section.selector.missing",
                        f"propulsion.{selector_path}",
                        "is required for this module section",
                    )
            elif type(selector_value) is not str:
                issue(
                    "module.section.selector.type",
                    f"propulsion.{selector_path}",
                    "must be a string selector",
                )
            else:
                selected_value = selector_value
                if selected_value in per_value:
                    section_fields = per_value[selected_value]
                elif selector.get("reject_unknown_selector", False):
                    issue(
                        "module.section.selector.unknown",
                        f"propulsion.{selector_path}",
                        f"has unregistered value {selected_value!r}",
                    )
            for required_field in required_by_value.get(selected_value, selector.get("required_fields", [])):
                if required_field not in section:
                    issue(
                        "module.section.field.missing",
                        f"propulsion.{section_name}.{required_field}",
                        "is required for this module section",
                    )
        for key in sorted(set(section) - set(section_fields)):
            issue(
                "module.field.unknown",
                f"propulsion.{section_name}.{key}",
                "is not registered for this module section",
            )

    variant: dict[str, Any] | None = None
    family_transforms = dict(family.get("compiler_transforms", {}))
    if propulsion_kind == "glow_prop":
        engine = propulsion.get("engine")
        if not isinstance(engine, dict):
            engine = {}
        variants = family.get("variants", [])
        matching: list[dict[str, Any]] = []
        for candidate in variants:
            conditions_match = True
            for relative_path, present in candidate.get("when", {}).items():
                full_path = f"propulsion.{relative_path}"
                exists, _ = _at_path(base, full_path)
                if exists is not present:
                    conditions_match = False
                    break
            if not conditions_match:
                continue
            if selected_values.get("energy") != candidate.get("energy"):
                continue
            matching.append(candidate)
        if len(matching) != 1:
            issue(
                "module.relation.invalid",
                "propulsion.engine",
                "shaft, glow installation, and energy selections do not match a registered propulsion variant",
            )
        else:
            variant = matching[0]
            laws.append(str(variant.get("law", "")))
            modules.extend(str(value) for value in variant.get("modules", []))
            parameters["propulsion.law"] = str(variant.get("law", ""))
            family_transforms = dict(variant.get("compiler_transforms", family_transforms))
            reason = variant.get("compiler_reason", "")
            if type(reason) is str and reason:
                transform_reasons.append(reason)
            if "shaft" in engine and not isinstance(engine["shaft"], dict):
                issue("module.field.type", "propulsion.engine.shaft", "must be an object")
            if "glow_installation" in engine and (
                type(engine["glow_installation"]) is not str or not engine["glow_installation"]
            ):
                issue("module.field.type", "propulsion.engine.glow_installation", "must be a non-empty resource path")
    elif propulsion_kind == "electric_prop":
        battery = propulsion.get("battery")
        if not isinstance(battery, dict):
            issue("module.section.type", "propulsion.battery", "must be an object")
        else:
            battery_kind = battery.get("kind")
            if type(battery_kind) is not str:
                issue("module.battery.kind.type", "propulsion.battery.kind", "must be a string selector")
            else:
                battery_law = family.get("battery_laws", {}).get(battery_kind)
                if type(battery_law) is not str:
                    issue("module.battery.kind.unknown", "propulsion.battery.kind", f"has unregistered value {battery_kind!r}")
                else:
                    laws.append(battery_law)
                    parameters["propulsion.battery.kind"] = battery_kind
                if selected_values.get("energy") is not None and selected_values["energy"] != battery_kind:
                    issue(
                        "module.relation.battery_energy",
                        "capabilities.energy",
                        "must match propulsion.battery.kind",
                    )
    elif propulsion_kind == "turbine":
        engine = propulsion.get("engine")
        if not isinstance(engine, dict):
            engine = {}
        integrator_key = family.get("integrator_path", "engine.spool_integrator")
        relative_key = integrator_key.removeprefix("engine.")
        integrator = engine.get(relative_key, family.get("integrator_default"))
        if type(integrator) is not str:
            issue("module.turbine.integrator.type", f"propulsion.{integrator_key}", "must be a string selector")
        else:
            integrator_law = family.get("integrator_laws", {}).get(integrator)
            if type(integrator_law) is not str:
                issue("module.turbine.integrator.unknown", f"propulsion.{integrator_key}", f"has unregistered value {integrator!r}")
            else:
                laws.append(integrator_law)
                parameters[f"propulsion.{integrator_key}"] = integrator

    family_reason = family.get("compiler_family_transform_reason", "")
    if type(family_reason) is str and family_reason and not all(
        family_transforms.get(key, False) for key in ("scale", "weight", "power")
    ):
        transform_reasons.insert(0, family_reason.replace("{kind}", propulsion_kind))

    for conditional in registry.get("conditional_laws", []):
        if conditional.get("family") != propulsion_kind:
            continue
        exists, _ = _at_path(base, f"propulsion.{conditional['path']}")
        if not exists:
            continue
        laws.append(str(conditional["law"]))
        reason = conditional.get("compiler_transform_reason", "")
        if type(reason) is str and reason:
            transform_reasons.append(reason)
        overrides = conditional.get("compiler_transforms", {})
        for key in ("scale", "weight", "power"):
            if key in overrides:
                family_transforms[key] = bool(family_transforms.get(key, False) and overrides[key])

    if errors:
        return _result(errors, diagnostics)
    return _result(
        errors,
        diagnostics,
        modules=modules,
        laws=laws,
        parameters=parameters,
        transforms={
            **{key: bool(family_transforms.get(key, False)) for key in ("scale", "weight", "power")},
            "controls": control_transform_supported,
        },
        transform_reasons=transform_reasons,
    )

