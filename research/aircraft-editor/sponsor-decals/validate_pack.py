#!/usr/bin/env python3
"""Validate the research contract/fixtures; does not qualify the Godot renderer."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import sys

from jsonschema import Draft202012Validator

from build_catalog import HERE, build_outputs, read_catalog, strict_object

MAX_STACK_BYTES = 65536


def reject_constant(value):
    raise ValueError(f"Non-finite JSON number: {value}")


def read_json(data: bytes):
    if len(data) > MAX_STACK_BYTES:
        raise ValueError("Research stack exceeds 65536 bytes")
    return json.loads(data.decode("utf-8"), object_pairs_hook=strict_object,
                      parse_constant=reject_constant)


def finite_tree(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("Number overflow/non-finite value")
    if isinstance(value, dict):
        for item in value.values():
            finite_tree(item)
    elif isinstance(value, list):
        for item in value:
            finite_tree(item)


def validate_stack(value: dict) -> None:
    finite_tree(value)
    if len(json.dumps(value, allow_nan=False, separators=(",", ":")).encode()) > MAX_STACK_BYTES:
        raise ValueError("Canonical stack exceeds 65536 bytes")
    schema = json.loads((HERE / "schemas/decal-stack.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    problems = sorted(Draft202012Validator(schema).iter_errors(value), key=lambda e: str(e.path))
    if problems:
        raise ValueError(problems[0].message)

    fixture_bytes = (HERE / "receiver-fixture.json").read_bytes()
    fixture = json.loads(fixture_bytes, object_pairs_hook=strict_object)
    fixture_sha = hashlib.sha256(fixture_bytes).hexdigest()
    if (value["receiver_bindings_sha256"] != fixture_sha
            or value["visual_base"]["model_sha256"] != fixture_sha):
        raise ValueError("Receiver/model identity is stale for the synthetic fixture")
    visual = value["visual_base"]
    if (visual["visual_family"] != fixture["visual_family"] or visual["kind"] != "factory"
            or visual["appearance_id"] != "factory"):
        raise ValueError("This checker admits the declared synthetic factory base only")
    factory_sha = hashlib.sha256(fixture["factory_paint_identity"].encode()).hexdigest()
    if visual["appearance_sha256"] != factory_sha:
        raise ValueError("Fixture factory appearance identity mismatch")

    receivers = {r["id"]: r for r in fixture["receivers"]}
    assets = {a["id"]: a for a in read_catalog()["entries"]}
    locks = {a["id"]: a for a in json.loads((HERE / "asset-lock.json").read_text(encoding="utf-8"))["assets"]}
    ids = set()
    for layer in value["layers"]:
        if layer["id"] in ids:
            raise ValueError("Duplicate decal instance ID")
        ids.add(layer["id"])
        asset = assets.get(layer["asset_id"])
        if asset is None or not asset["demo_placement"]:
            raise ValueError("Asset is unavailable for the interaction fixture")
        if layer["asset_sha256"] != asset["source_sha256"]:
            raise ValueError("Asset identity mismatch")
        receiver = receivers.get(layer["receiver_id"])
        if receiver is None:
            raise ValueError("Unknown receiver; no implicit remapping")
        if any(not lo <= x <= hi for lo, x, hi in zip(receiver["minimum_m"], layer["position_m"], receiver["maximum_m"])):
            raise ValueError("Anchor falls outside the synthetic receiver bounds")
        normal, tangent = layer["normal"], layer["tangent"]
        if any(abs(sum(x*x for x in vector) - 1) > 1e-6 for vector in (normal, tangent)):
            raise ValueError("Anchor normal/tangent must be unit length")
        if abs(sum(a*b for a, b in zip(normal, tangent))) > 1e-6:
            raise ValueError("Anchor normal/tangent must be orthogonal")
        actual = layer["size_m"][0] / layer["size_m"][1]
        locked_asset = locks[layer["asset_id"]]
        expected = locked_asset["width"] / locked_asset["height"]
        if not math.isclose(actual, expected, rel_tol=1e-6):
            raise ValueError("Aspect-locked dimensions distort the image")


def self_test() -> dict:
    baseline = read_json((HERE / "examples/layered-stack.json").read_bytes())
    validate_stack(baseline)
    full = copy.deepcopy(baseline)
    full["layers"] = [dict(copy.deepcopy(baseline["layers"][0]), id=f"decal-{i:03}") for i in range(64)]
    validate_stack(full)  # Contract boundary only, not a performance claim.
    cases = []

    def bad(name, mutate, expected_error=None):
        value = copy.deepcopy(baseline)
        mutate(value)
        try:
            validate_stack(value)
        except (ValueError, TypeError) as exc:
            if expected_error is not None and str(exc) != expected_error:
                raise AssertionError(f"Wrong refusal for {name}: {exc}") from exc
            cases.append(name)
            return
        raise AssertionError(f"Invalid contract accepted: {name}")

    bad("unknown top-level field", lambda v: v.update(script="res://unsafe.gd"))
    bad("unknown layer field", lambda v: v["layers"][0].update(path="../../image.png"))
    bad("missing layer field", lambda v: v["layers"][0].pop("normal"))
    bad("duplicate instance id", lambda v: v["layers"][1].update(id=v["layers"][0]["id"]))
    bad("unknown asset", lambda v: v["layers"][0].update(asset_id="unknown"))
    bad("path-shaped asset id", lambda v: v["layers"][0].update(asset_id="../image"))
    # Use the correct bytes and aspect so this proves admission refusal, not an
    # unrelated hash/geometry failure after accidental brand activation.
    savox = next(a for a in read_catalog()["entries"] if a["id"] == "savox")
    bad("reference-only sponsor", lambda v: v["layers"][0].update(
        asset_id="savox", asset_sha256=savox["source_sha256"],
        size_m=[0.25, 0.25 * savox["height"] / savox["width"]]),
        expected_error="Asset is unavailable for the interaction fixture")
    bad("wrong asset bytes", lambda v: v["layers"][0].update(asset_sha256="0"*64))
    bad("stale receiver identity", lambda v: v.update(receiver_bindings_sha256="0"*64))
    bad("stale model identity", lambda v: v["visual_base"].update(model_sha256="0"*64))
    bad("stale paint identity", lambda v: v["visual_base"].update(appearance_sha256="0"*64))
    bad("unknown receiver", lambda v: v["layers"][0].update(receiver_id="fixture.unknown"))
    bad("anchor outside receiver", lambda v: v["layers"][0].update(position_m=[99,0,0]))
    bad("zero normal", lambda v: v["layers"][0].update(normal=[0,0,0]))
    bad("parallel tangent", lambda v: v["layers"][0].update(tangent=[0,1,0]))
    bad("negative dimensions", lambda v: v["layers"][0].update(size_m=[-0.25,0.1]))
    bad("zero dimensions", lambda v: v["layers"][0].update(size_m=[0,0.1]))
    bad("aspect distortion", lambda v: v["layers"][0].update(size_m=[0.5,0.1]))
    bad("noncanonical rotation", lambda v: v["layers"][0].update(rotation_deg=180))
    bad("boolean numeric value", lambda v: v["layers"][0].update(rotation_deg=True))
    bad("non-finite coordinate", lambda v: v["layers"][0].update(position_m=[float('inf'),0,0]))
    bad("numeric flip", lambda v: v["layers"][0].update(flip_u=-1))
    bad("excess opacity", lambda v: v["layers"][0].update(opacity=1.1))
    bad("65th layer", lambda v: v.update(layers=copy.deepcopy(full["layers"])+[dict(full["layers"][0],id="one-too-many")]))
    for name, data in [("duplicate JSON keys", b'{"version":1,"version":1}'),
                       ("NaN token", b'{"number":NaN}'),
                       ("oversize bytes", b' '*65537)]:
        try:
            read_json(data)
        except (ValueError, UnicodeError):
            cases.append(name)
        else:
            raise AssertionError(f"Malformed JSON accepted: {name}")

    # These schema-only cases do not claim a real custom skin was loaded.
    schema = Draft202012Validator(json.loads((HERE / "schemas/decal-stack.schema.json").read_text(encoding="utf-8")))
    custom = copy.deepcopy(baseline)
    custom["visual_base"].update(kind="custom_skin", appearance_id="custom_0123456789abcdef01234567")
    schema.validate(custom)
    stock = copy.deepcopy(baseline)
    stock["visual_base"].update(kind="stock", appearance_id="neon_carbon")
    schema.validate(stock)
    for ident in ["custom_123", "custom_0123456789abcdef0123456z", "factory"]:
        bad_custom = copy.deepcopy(custom)
        bad_custom["visual_base"]["appearance_id"] = ident
        if not list(schema.iter_errors(bad_custom)):
            raise AssertionError("Malformed installed-skin ID accepted")

    # Receiver-local point -> local hinge rotation -> receiver bind -> aircraft scale.
    fixture = json.loads((HERE / "receiver-fixture.json").read_text(encoding="utf-8"))
    hinge = next(r for r in fixture["receivers"] if r["id"] == "fixture.aileron.left")

    def to_model(point, angle_deg, scale):
        angle = math.radians(angle_deg)
        x, y, z = point
        # This synthetic hinge is explicitly local +X, at its local origin.
        rotated = [x, y*math.cos(angle)-z*math.sin(angle), y*math.sin(angle)+z*math.cos(angle)]
        basis = hinge["bind_to_model"]["basis_columns"]
        origin = hinge["bind_to_model"]["origin_m"]
        return [scale*(origin[i] + sum(basis[j][i]*rotated[j] for j in range(3))) for i in range(3)]

    known = [([0,0,0],0,1,[-0.9,0,0.2]),
             ([0.1,0,0],0,1,[-0.9,0,0.1]),
             ([0,0,0.1],0,1,[-0.8,0,0.2]),
             ([0,0,0.1],90,1,[-0.9,-0.1,0.2]),
             ([0,0,0.1],90,0.1,[-0.09,-0.01,0.02]),
             ([0,0,0.1],90,5,[-4.5,-0.5,1])]
    for point, angle, scale, expected in known:
        if any(not math.isclose(a,b,abs_tol=1e-12) for a,b in zip(to_model(point,angle,scale),expected)):
            raise AssertionError("Receiver-local frame/hinge/scale fixture mismatch")

    # Nonuniform model->world matrix M = Rz(90 degrees) * diag(2, 1, 0.5).
    # World->local normals use M^T, world->local tangent directions use M^-1.
    def unit(v):
        length = math.sqrt(sum(x*x for x in v))
        return [x/length for x in v]

    normal_world = unit([1,1,0])
    tangent_world = unit([-1,1,0])
    normal_local = unit([2*normal_world[1], -normal_world[0], 0.5*normal_world[2]])
    tangent_local = unit([0.5*tangent_world[1], -tangent_world[0], 2*tangent_world[2]])
    expected_normal = unit([2,-1,0])
    expected_tangent = unit([1,2,0])
    if any(not math.isclose(a,b,abs_tol=1e-12) for a,b in zip(normal_local, expected_normal)):
        raise AssertionError("Nonuniform world-to-local normal transform mismatch")
    if (any(not math.isclose(a,b,abs_tol=1e-12) for a,b in zip(tangent_local, expected_tangent))
            or not math.isclose(sum(a*b for a,b in zip(normal_local,tangent_local)),0,abs_tol=1e-12)):
        raise AssertionError("Nonuniform world-to-local tangent transform mismatch")
    return {"negative_cases_passed": len(cases), "cases": cases,
            "base_selector_schema_cases": 5, "known_coordinate_cases": len(known),
            "nonuniform_normal_tangent_cases": 2,
            "64_layer_structure": "pass_not_render_qualification"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        outputs = build_outputs()
        for rel, data in outputs.items():
            if not (HERE / rel).is_file() or (HERE / rel).read_bytes() != data:
                raise ValueError(f"Generated reference drift: {rel}")
        examples = sorted((HERE / "examples").glob("*.json"))
        for path in examples:
            validate_stack(read_json(path.read_bytes()))
        result = {"status": "pass", "examples": len(examples), "generated_files": len(outputs),
                  "qualification": "offline_contract_only"}
        if args.self_test:
            result.update(self_test())
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, KeyError, TypeError, OSError, AssertionError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
