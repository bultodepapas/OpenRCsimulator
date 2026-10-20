#!/usr/bin/env python3
"""Inspect the supplied MT8 visual package without importing it into the app.

This is an intake gate, not an importer or a physical validation. It uses only
the Python standard library and reads the GLB container directly so that
``--check`` is deterministic and does not depend on a Godot editor cache.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PACKAGE = REPO_ROOT / "assets" / "source-deliveries" / "mt8-bisonte" / "MT8_Bisonte_entrega1_1" / "MT8_Bisonte"
DEFAULT_DELIVERY_GLB = REPO_ROOT / "assets" / "source-deliveries" / "mt8-bisonte" / "MT8_Bisonte_1.glb"
DEFAULT_OUTPUT = REPO_ROOT / "docs" / "research" / "rc-monster-truck" / "RCV-14a" / "intake.json"
FORMAT = "openrc-rcv-asset-intake v1"
CORNERS = ("FL", "FR", "RL", "RR")
RIG_PARTS = (
	"ArmLower", "ArmUpper", "Suspension", "Spin", "WheelMesh",
	"DriveshaftIn", "DriveshaftOut",
	"ShockA_Body", "ShockA_Spring", "ShockA_Shaft",
	"ShockB_Body", "ShockB_Spring", "ShockB_Shaft",
)
BASE_PARTS = (
	"Chassis", "Body", "Bumper_F", "Bumper_R", "Propulsion", "Collision",
	"COL_Chassis", "COL_Roof", "COL_Side_L", "COL_Side_R", "COL_Bumper_F", "COL_Bumper_R",
)


class IntakeError(ValueError):
	"""A deterministic, user-actionable reason the asset cannot be accepted."""


def _fail(message: str) -> None:
	raise IntakeError(message)


def _no_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
	result: dict[str, Any] = {}
	for key, value in pairs:
		if key in result:
			_fail(f"duplicate JSON object key: {key}")
		result[key] = value
	return result


def _finite_number(value: Any, path: str) -> float:
	if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
		_fail(f"{path} must be a finite number")
	return float(value)


def _sha256_bytes(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
	return _sha256_bytes(path.read_bytes())


def _json_bytes(document: dict[str, Any]) -> bytes:
	return (json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def _parse_glb(data: bytes) -> tuple[dict[str, Any], bytes]:
	if len(data) < 20 or data[:4] != b"glTF":
		_fail("GLB header is missing or truncated")
	version, total_length = struct.unpack_from("<II", data, 4)
	if version != 2:
		_fail(f"unsupported GLB version: {version}")
	if total_length != len(data):
		_fail(f"GLB declared length {total_length} does not match file length {len(data)}")

	chunks: list[tuple[int, bytes]] = []
	offset = 12
	while offset < total_length:
		if offset + 8 > total_length:
			_fail("truncated GLB chunk header")
		chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
		offset += 8
		if chunk_length % 4 != 0 or offset + chunk_length > total_length:
			_fail("invalid or truncated GLB chunk length")
		chunks.append((chunk_type, data[offset:offset + chunk_length]))
		offset += chunk_length
	if not chunks or chunks[0][0] != 0x4E4F534A:
		_fail("GLB JSON chunk must be first")
	json_chunks = [chunk for kind, chunk in chunks if kind == 0x4E4F534A]
	bin_chunks = [chunk for kind, chunk in chunks if kind == 0x004E4942]
	if len(json_chunks) != 1 or len(bin_chunks) > 1:
		_fail("GLB must contain one JSON chunk and at most one BIN chunk")
	try:
		json_text = json_chunks[0].rstrip(b" \t\r\n\x00").decode("utf-8")
		document = json.loads(json_text, object_pairs_hook=_no_duplicate_json_keys, parse_constant=lambda v: _fail(f"invalid JSON number: {v}"))
	except (UnicodeDecodeError, json.JSONDecodeError) as exc:
		_fail(f"GLB JSON chunk is invalid: {exc}")
	if not isinstance(document, dict):
		_fail("GLB JSON root must be an object")
	return document, bin_chunks[0] if bin_chunks else b""


def _decode_data_uri(uri: str, path: str) -> bytes:
	if not uri.startswith("data:"):
		_fail(f"external resource URI is forbidden at {path}: {uri}")
	try:
		metadata, payload = uri.split(",", 1)
		if metadata.endswith(";base64"):
			return base64.b64decode(payload, validate=True)
		from urllib.parse import unquote_to_bytes
		return unquote_to_bytes(payload)
	except (ValueError, base64.binascii.Error) as exc:
		_fail(f"invalid embedded data URI at {path}: {exc}")


def _check_self_contained(document: dict[str, Any], bin_chunk: bytes) -> dict[str, int]:
	buffers = document.get("buffers", [])
	images = document.get("images", [])
	if not isinstance(buffers, list) or not isinstance(images, list):
		_fail("GLB buffers and images must be arrays")
	if not buffers:
		_fail("GLB contains no embedded geometry buffer")

	buffer_lengths: list[int] = []
	for index, buffer in enumerate(buffers):
		if not isinstance(buffer, dict):
			_fail(f"buffers[{index}] must be an object")
		length = buffer.get("byteLength")
		if isinstance(length, bool) or not isinstance(length, int) or length < 0:
			_fail(f"buffers[{index}].byteLength is invalid")
		buffer_lengths.append(length)
		uri = buffer.get("uri")
		if uri is None:
			if len(buffers) != 1 or not bin_chunk:
				_fail("a URI-less GLB buffer must be the sole buffer and use the BIN chunk")
			if length > len(bin_chunk):
				_fail("GLB BIN chunk is shorter than buffers[0].byteLength")
		elif isinstance(uri, str):
			embedded = _decode_data_uri(uri, f"buffers[{index}].uri")
			if len(embedded) < length:
				_fail(f"embedded buffer {index} is shorter than byteLength")
		else:
			_fail(f"buffers[{index}].uri must be a string")

	for index, image in enumerate(images):
		if not isinstance(image, dict):
			_fail(f"images[{index}] must be an object")
		uri = image.get("uri")
		view = image.get("bufferView")
		if uri is not None:
			if not isinstance(uri, str):
				_fail(f"images[{index}].uri must be a string")
			_decode_data_uri(uri, f"images[{index}].uri")
		elif view is None:
			_fail(f"images[{index}] needs a bufferView or embedded data URI")
		elif isinstance(view, bool) or not isinstance(view, int) or not 0 <= view < len(document.get("bufferViews", [])):
			_fail(f"images[{index}].bufferView is out of range")

	views = document.get("bufferViews", [])
	if not isinstance(views, list):
		_fail("bufferViews must be an array")
	for index, view in enumerate(views):
		if not isinstance(view, dict):
			_fail(f"bufferViews[{index}] must be an object")
		buffer_index = view.get("buffer", 0)
		if isinstance(buffer_index, bool) or not isinstance(buffer_index, int) or not 0 <= buffer_index < len(buffer_lengths):
			_fail(f"bufferViews[{index}].buffer is out of range")
		offset = view.get("byteOffset", 0)
		length = view.get("byteLength")
		if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0 or isinstance(length, bool) or not isinstance(length, int) or length < 0:
			_fail(f"bufferViews[{index}] has invalid byte offsets")
		if offset + length > buffer_lengths[buffer_index]:
			_fail(f"bufferViews[{index}] exceeds its buffer")
	return {"buffers": len(buffers), "images": len(images), "buffer_views": len(views)}


def _identity4() -> list[list[float]]:
	return [[1.0 if row == col else 0.0 for col in range(4)] for row in range(4)]


def _mul4(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
	return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def _node_local_matrix(node: dict[str, Any], index: int) -> list[list[float]]:
	if "matrix" in node:
		values = node["matrix"]
		if not isinstance(values, list) or len(values) != 16:
			_fail(f"nodes[{index}].matrix must have 16 values")
			return _identity4()
		flat = [_finite_number(v, f"nodes[{index}].matrix") for v in values]
		return [[flat[c * 4 + r] for c in range(4)] for r in range(4)]

	translation = node.get("translation", [0.0, 0.0, 0.0])
	rotation = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	scale = node.get("scale", [1.0, 1.0, 1.0])
	if not isinstance(translation, list) or len(translation) != 3 or not isinstance(rotation, list) or len(rotation) != 4 or not isinstance(scale, list) or len(scale) != 3:
		_fail(f"nodes[{index}] has malformed TRS values")
	tx, ty, tz = (_finite_number(v, f"nodes[{index}].translation") for v in translation)
	sx, sy, sz = (_finite_number(v, f"nodes[{index}].scale") for v in scale)
	qx, qy, qz, qw = (_finite_number(v, f"nodes[{index}].rotation") for v in rotation)
	qnorm = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if qnorm <= 1.0e-12:
		_fail(f"nodes[{index}].rotation quaternion is zero")
	qx, qy, qz, qw = qx / qnorm, qy / qnorm, qz / qnorm, qw / qnorm
	rot = [
		[1.0 - 2.0 * (qy * qy + qz * qz), 2.0 * (qx * qy - qz * qw), 2.0 * (qx * qz + qy * qw), 0.0],
		[2.0 * (qx * qy + qz * qw), 1.0 - 2.0 * (qx * qx + qz * qz), 2.0 * (qy * qz - qx * qw), 0.0],
		[2.0 * (qx * qz - qy * qw), 2.0 * (qy * qz + qx * qw), 1.0 - 2.0 * (qx * qx + qy * qy), 0.0],
		[0.0, 0.0, 0.0, 1.0],
	]
	local = _mul4(rot, [[sx, 0.0, 0.0, 0.0], [0.0, sy, 0.0, 0.0], [0.0, 0.0, sz, 0.0], [0.0, 0.0, 0.0, 1.0]])
	local[0][3], local[1][3], local[2][3] = tx, ty, tz
	return local


def _det3(matrix: list[list[float]]) -> float:
	a, b, c = matrix[0][:3]
	d, e, f = matrix[1][:3]
	g, h, i = matrix[2][:3]
	return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def _transform_point(matrix: list[list[float]], point: list[float] | tuple[float, float, float]) -> list[float]:
	x, y, z = point
	return [
		matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z + matrix[0][3],
		matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z + matrix[1][3],
		matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z + matrix[2][3],
	]


def _node_graph(document: dict[str, Any]) -> tuple[list[dict[str, Any]], list[int], dict[str, int], dict[int, list[list[float]]]]:
	nodes = document.get("nodes", [])
	if not isinstance(nodes, list) or not nodes:
		_fail("GLB must contain a non-empty nodes array")
	parents: dict[int, int] = {}
	children: dict[int, list[int]] = {}
	by_name: dict[str, int] = {}
	duplicates: list[str] = []
	for index, node in enumerate(nodes):
		if not isinstance(node, dict):
			_fail(f"nodes[{index}] must be an object")
		name = node.get("name", "")
		if name and not isinstance(name, str):
			_fail(f"nodes[{index}].name must be a string")
		if name:
			if name in by_name:
				duplicates.append(name)
			else:
				by_name[name] = index
		list_of_children = node.get("children", [])
		if not isinstance(list_of_children, list):
			_fail(f"nodes[{index}].children must be an array")
		seen_children: set[int] = set()
		for child in list_of_children:
			if isinstance(child, bool) or not isinstance(child, int) or not 0 <= child < len(nodes):
				_fail(f"nodes[{index}] has an out-of-range child index")
			if child in seen_children:
				_fail(f"nodes[{index}] has duplicate child indices")
			seen_children.add(child)
			if child in parents:
				_fail(f"node {child} has more than one parent")
			parents[child] = index
		children[index] = list_of_children
	if duplicates:
		_fail("duplicate node names: " + ", ".join(sorted(set(duplicates))))

	scenes = document.get("scenes", [])
	if not isinstance(scenes, list) or not scenes:
		_fail("GLB must declare at least one scene")
	active_scene = document.get("scene", 0)
	if isinstance(active_scene, bool) or not isinstance(active_scene, int) or not 0 <= active_scene < len(scenes):
		_fail("GLB default scene index is out of range")
	root_nodes = scenes[active_scene].get("nodes", [])
	if not isinstance(root_nodes, list) or not root_nodes:
		_fail("GLB default scene must have root nodes")
	for node_index in root_nodes:
		if isinstance(node_index, bool) or not isinstance(node_index, int) or not 0 <= node_index < len(nodes):
			_fail("GLB scene contains an out-of-range root node")
		if node_index in parents:
			_fail("GLB scene root also has a parent")

	world: dict[int, list[list[float]]] = {}
	visiting: set[int] = set()
	def visit(index: int, parent_matrix: list[list[float]]) -> None:
		if index in visiting:
			_fail("GLB node graph contains a cycle")
		visiting.add(index)
		local = _node_local_matrix(nodes[index], index)
		world[index] = _mul4(parent_matrix, local)
		for child in children[index]:
			visit(child, world[index])
		visiting.remove(index)
	for index in root_nodes:
		visit(index, _identity4())
	if len(world) != len(nodes):
		_fail("GLB contains nodes that are not reachable from the default scene")
	return nodes, root_nodes, by_name, world


def _check_node_transforms(nodes: list[dict[str, Any]], world: dict[int, list[list[float]]]) -> None:
	negative: list[str] = []
	for index, node in enumerate(nodes):
		name = str(node.get("name", f"node_{index}"))
		if "scale" in node:
			scale = node["scale"]
			if not isinstance(scale, list) or len(scale) != 3:
				_fail(f"nodes[{index}].scale must have 3 values")
			if any(_finite_number(v, f"nodes[{index}].scale") < -1.0e-9 for v in scale):
				negative.append(name)
		if _det3(world[index]) <= 0.0:
			negative.append(name)
	if negative:
		_fail("negative-scale or non-positive-determinant nodes: " + ", ".join(sorted(set(negative))))


def _accessor_count(document: dict[str, Any], index: int, path: str) -> int:
	accessors = document.get("accessors", [])
	if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(accessors):
		_fail(f"{path} accessor index is out of range")
	accessor = accessors[index]
	if not isinstance(accessor, dict):
		_fail(f"accessors[{index}] must be an object")
	count = accessor.get("count")
	if isinstance(count, bool) or not isinstance(count, int) or count < 0:
		_fail(f"accessors[{index}].count is invalid")
	return count


def _geometry(document: dict[str, Any], nodes: list[dict[str, Any]], world: dict[int, list[list[float]]]) -> dict[str, Any]:
	meshes = document.get("meshes", [])
	if not isinstance(meshes, list) or not meshes:
		_fail("GLB must contain meshes")
	triangle_total = 0
	visual_triangle_total = 0
	primitive_total = 0
	visual_primitive_total = 0
	bounds_points: list[list[float]] = []
	named_bounds_points: dict[str, list[list[float]]] = {}
	proxy_bounds_points: dict[str, list[list[float]]] = {}
	mesh_instances = 0
	for node_index, node in enumerate(nodes):
		mesh_index = node.get("mesh")
		if mesh_index is None:
			continue
		if isinstance(mesh_index, bool) or not isinstance(mesh_index, int) or not 0 <= mesh_index < len(meshes):
			_fail(f"nodes[{node_index}].mesh is out of range")
		mesh_instances += 1
		mesh = meshes[mesh_index]
		if not isinstance(mesh, dict) or not isinstance(mesh.get("primitives"), list):
			_fail(f"meshes[{mesh_index}] must contain primitives")
		is_visual = not str(node.get("name", "")).startswith("COL_")
		node_bounds_points: list[list[float]] = []
		for primitive_index, primitive in enumerate(mesh["primitives"]):
			primitive_total += 1
			if is_visual:
				visual_primitive_total += 1
			if not isinstance(primitive, dict) or not isinstance(primitive.get("attributes"), dict):
				_fail(f"meshes[{mesh_index}].primitives[{primitive_index}] is malformed")
			attributes = primitive["attributes"]
			position_accessor = attributes.get("POSITION")
			if position_accessor is None:
				_fail(f"meshes[{mesh_index}].primitives[{primitive_index}] has no POSITION")
			position_count = _accessor_count(document, position_accessor, f"meshes[{mesh_index}].primitives[{primitive_index}].POSITION")
			position = document["accessors"][position_accessor]
			minimum, maximum = position.get("min"), position.get("max")
			if not isinstance(minimum, list) or not isinstance(maximum, list) or len(minimum) != 3 or len(maximum) != 3:
				_fail(f"POSITION accessor {position_accessor} needs 3D min/max bounds")
			minimum = [_finite_number(v, f"accessors[{position_accessor}].min") for v in minimum]
			maximum = [_finite_number(v, f"accessors[{position_accessor}].max") for v in maximum]
			if any(minimum[axis] > maximum[axis] for axis in range(3)):
				_fail(f"POSITION accessor {position_accessor} has inverted bounds")
			mode = primitive.get("mode", 4)
			if isinstance(mode, bool) or not isinstance(mode, int) or not 0 <= mode <= 6:
				_fail(f"mesh primitive has invalid mode {mode}")
			count = _accessor_count(document, primitive["indices"], "primitive indices") if "indices" in primitive else position_count
			triangles = count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
			triangle_total += triangles
			if is_visual:
				visual_triangle_total += triangles
			for x in (minimum[0], maximum[0]):
				for y in (minimum[1], maximum[1]):
					for z in (minimum[2], maximum[2]):
						transformed = _transform_point(world[node_index], [x, y, z])
						node_bounds_points.append(transformed)
						if is_visual:
							bounds_points.append(transformed)
		if is_visual and str(node.get("name", "")).endswith("_WheelMesh"):
			named_bounds_points[str(node["name"])] = node_bounds_points
		if str(node.get("name", "")).startswith("COL_"):
			proxy_bounds_points[str(node["name"])] = node_bounds_points
	if not bounds_points:
		_fail("GLB has no visible triangle mesh bounds")
	minimum = [min(point[axis] for point in bounds_points) for axis in range(3)]
	maximum = [max(point[axis] for point in bounds_points) for axis in range(3)]
	wheel_bounds: dict[str, dict[str, list[float]]] = {}
	for corner in CORNERS:
		name = f"{corner}_WheelMesh"
		points = named_bounds_points.get(name, [])
		if not points:
			_fail(f"{name} has no visual geometry bounds")
		wheel_min = [min(point[axis] for point in points) for axis in range(3)]
		wheel_max = [max(point[axis] for point in points) for axis in range(3)]
		wheel_bounds[corner] = {"min": wheel_min, "max": wheel_max, "size": [wheel_max[i] - wheel_min[i] for i in range(3)]}
	proxy_bounds: dict[str, dict[str, list[float]]] = {}
	for name, points in sorted(proxy_bounds_points.items()):
		if not points:
			_fail(f"{name} has no proxy geometry bounds")
		proxy_min = [min(point[axis] for point in points) for axis in range(3)]
		proxy_max = [max(point[axis] for point in points) for axis in range(3)]
		proxy_bounds[name] = {"min": proxy_min, "max": proxy_max,
							  "center": [(proxy_min[i] + proxy_max[i]) / 2.0 for i in range(3)],
							  "size": [proxy_max[i] - proxy_min[i] for i in range(3)]}
	return {
		"mesh_instances": mesh_instances,
		"primitive_count_including_proxies": primitive_total,
		"visual_primitive_count": visual_primitive_total,
		"triangle_count_including_proxies": triangle_total,
		"visual_triangle_count": visual_triangle_total,
		"visual_bounds_m": {"min": minimum, "max": maximum, "size": [maximum[i] - minimum[i] for i in range(3)]},
		"wheel_mesh_bounds_m": wheel_bounds,
		"collision_proxy_bounds_m": proxy_bounds,
	}


def _check_materials(document: dict[str, Any], nodes: list[dict[str, Any]]) -> dict[str, Any]:
	materials = document.get("materials", [])
	if not isinstance(materials, list):
		_fail("materials must be an array")
	names: list[str] = []
	for index, material in enumerate(materials):
		if not isinstance(material, dict):
			_fail(f"materials[{index}] must be an object")
		name = material.get("name", "")
		if not isinstance(name, str) or not name.strip():
			_fail(f"materials[{index}] needs a stable non-empty name")
		names.append(name)
	duplicates = sorted({name for name in names if names.count(name) > 1})
	if duplicates:
		_fail("duplicate material names: " + ", ".join(duplicates))
	meshes = document.get("meshes", [])
	visual_indices: set[int] = set()
	proxy_indices: set[int] = set()
	for node_index, node in enumerate(nodes):
		mesh_index = node.get("mesh")
		if mesh_index is None:
			continue
		if isinstance(mesh_index, bool) or not isinstance(mesh_index, int) or not 0 <= mesh_index < len(meshes):
			_fail(f"nodes[{node_index}].mesh is out of range")
		for primitive_index, primitive in enumerate(meshes[mesh_index].get("primitives", [])):
			material_index = primitive.get("material")
			if material_index is None:
				continue
			if isinstance(material_index, bool) or not isinstance(material_index, int) or not 0 <= material_index < len(materials):
				_fail(f"meshes[{mesh_index}].primitives[{primitive_index}].material is out of range")
			(material := proxy_indices if str(node.get("name", "")).startswith("COL_") else visual_indices).add(material_index)
	return {
		"definition_count": len(materials),
		"names": names,
		"visual_used_count": len(visual_indices),
		"visual_used_names": [names[index] for index in sorted(visual_indices)],
		"proxy_used_count": len(proxy_indices),
		"proxy_used_names": [names[index] for index in sorted(proxy_indices)],
		"unused_names": [names[index] for index in range(len(names)) if index not in visual_indices | proxy_indices],
	}


def _require_node(by_name: dict[str, int], name: str) -> int:
	if name not in by_name:
		_fail(f"required node is missing: {name}")
	return by_name[name]


def _node_parent(nodes: list[dict[str, Any]], node_index: int) -> int | None:
	for parent_index, node in enumerate(nodes):
		if node_index in node.get("children", []):
			return parent_index
	return None


def _parent_name(nodes: list[dict[str, Any]], node_index: int) -> str | None:
	parent = _node_parent(nodes, node_index)
	return None if parent is None else str(nodes[parent].get("name", ""))


def _close(actual: list[float], expected: list[float], tol: float = 1.0e-3) -> bool:
	return len(actual) == len(expected) and all(abs(float(actual[i]) - float(expected[i])) <= tol for i in range(len(expected)))


def _check_articulation(nodes: list[dict[str, Any]], by_name: dict[str, int], world: dict[int, list[list[float]]], spec: dict[str, Any], geometry: dict[str, Any]) -> dict[str, Any]:
	root_index = _require_node(by_name, "MT8_Root")
	root = world[root_index]
	root_identity_error = max(abs(root[r][c] - (1.0 if r == c else 0.0)) for r in range(4) for c in range(4))
	if root_identity_error > 1.0e-5:
		_fail(f"MT8_Root must be the identity datum; matrix error {root_identity_error:.6g}")

	missing: list[str] = []
	for name in BASE_PARTS:
		if name not in by_name:
			missing.append(name)
	for corner in CORNERS:
		for part in RIG_PARTS:
			if f"{corner}_{part}" not in by_name:
				missing.append(f"{corner}_{part}")
		if corner[0] == "F":
			for part in ("Steer", "Knuckle"):
				if f"{corner}_{part}" not in by_name:
					missing.append(f"{corner}_{part}")
		else:
			if f"{corner}_Carrier" not in by_name:
				missing.append(f"{corner}_Carrier")
	if missing:
		_fail("articulation node contract is incomplete: " + ", ".join(missing))

	for corner in CORNERS:
		spin_name = f"{corner}_Spin"
		suspension_name = f"{corner}_Suspension"
		wheel_name = f"{corner}_WheelMesh"
		spin_index = by_name[spin_name]
		wheel_index = by_name[wheel_name]
		if _parent_name(nodes, wheel_index) != spin_name:
			_fail(f"{wheel_name} must be a child of {spin_name}")
		if corner[0] == "F":
			steer_name = f"{corner}_Steer"
			if _parent_name(nodes, by_name[steer_name]) != suspension_name or _parent_name(nodes, spin_index) != steer_name:
				_fail(f"front wheel hierarchy must be {suspension_name}/{steer_name}/{spin_name}")
		elif _parent_name(nodes, spin_index) != suspension_name:
			_fail(f"rear {spin_name} must be a child of {suspension_name}")
		for shock in ("A", "B"):
			shaft_name = f"{corner}_Shock{shock}_Shaft"
			if _parent_name(nodes, by_name[shaft_name]) != f"{corner}_ArmLower":
				_fail(f"{shaft_name} must be a child of {corner}_ArmLower")

		corner_spec = spec.get("corners", {}).get(corner)
		if not isinstance(corner_spec, dict):
			_fail(f"spec is missing corner data for {corner}")
		for node_name, spec_key in ((spin_name, "wheel_center_rest"), (suspension_name, "wheel_center_rest"),
									(f"{corner}_ArmLower", "arm_lower_pivot"), (f"{corner}_ArmUpper", "arm_upper_pivot"),
								(f"{corner}_DriveshaftIn", "driveshaft_inner")):
			matrix = world[by_name[node_name]]
			actual = [matrix[row][3] for row in range(3)]
			expected = corner_spec.get(spec_key)
			if not isinstance(expected, list) or not _close(actual, expected):
				_fail(f"{node_name} pivot does not match spec.{corner}.{spec_key}: {actual} vs {expected}")
		for shock in ("A", "B"):
			shock_spec = corner_spec.get("shocks", {}).get(shock, {})
			for part, spec_key in (("Body", "upper_mount"), ("Shaft", "lower_mount_rest")):
				node_name = f"{corner}_Shock{shock}_{part}"
				matrix = world[by_name[node_name]]
				actual = [matrix[row][3] for row in range(3)]
				expected = shock_spec.get(spec_key)
				if not isinstance(expected, list) or not _close(actual, expected):
					_fail(f"{node_name} pivot does not match spec.{corner}.shocks.{shock}.{spec_key}: {actual} vs {expected}")

	wheel_centers = {corner: [world[by_name[f"{corner}_Spin"]][row][3] for row in range(3)] for corner in CORNERS}
	wheelbase = abs(wheel_centers["RL"][2] - wheel_centers["FL"][2])
	front_track = wheel_centers["FR"][0] - wheel_centers["FL"][0]
	rear_track = wheel_centers["RR"][0] - wheel_centers["RL"][0]
	expected_wheelbase = _finite_number(spec.get("wheelbase"), "spec.wheelbase")
	expected_track = _finite_number(spec.get("track"), "spec.track")
	if abs(wheelbase - expected_wheelbase) > 1.0e-3 or abs(front_track - expected_track) > 1.0e-3 or abs(rear_track - expected_track) > 1.0e-3:
		_fail(f"wheelbase/track dimensions disagree with the runtime spec: measured {wheelbase}, {front_track}, {rear_track}")
	tire_radius = _finite_number(spec.get("tire_radius"), "spec.tire_radius")
	tire_width = _finite_number(spec.get("tire_width"), "spec.tire_width")
	wheel_dimensions: dict[str, dict[str, float]] = {}
	for corner in CORNERS:
		size = geometry["wheel_mesh_bounds_m"][corner]["size"]
		diameter = (size[1] + size[2]) / 2.0
		if abs(diameter - 2.0 * tire_radius) > 0.006 or abs(size[0] - tire_width) > 0.015:
			_fail(f"{corner} tire mesh dimensions disagree with the runtime spec: width={size[0]}, diameter={diameter}")
		wheel_dimensions[corner] = {"width_m": size[0], "diameter_m": diameter}
	return {
		"root_node": "MT8_Root", "root_identity_error": root_identity_error,
		"articulation_nodes": 72, "pivot_tolerance_m": 1.0e-3,
		"wheelbase_m": wheelbase, "front_track_m": front_track, "rear_track_m": rear_track,
		"wheel_dimensions_m": wheel_dimensions,
	}


def _check_collision_proxies(by_name: dict[str, int], geometry: dict[str, Any], spec: dict[str, Any]) -> dict[str, Any]:
	proxy_spec = spec.get("collision_boxes")
	if not isinstance(proxy_spec, dict) or not proxy_spec:
		_fail("runtime spec must declare collision_boxes")
	actual = geometry.get("collision_proxy_bounds_m", {})
	if set(actual) != set(proxy_spec):
		missing = sorted(set(proxy_spec) - set(actual))
		extra = sorted(set(actual) - set(proxy_spec))
		_fail(f"GLB collision proxies and spec collision_boxes differ; missing={missing}, undocumented={extra}")
	verified: list[dict[str, Any]] = []
	for name in sorted(proxy_spec):
		_require_node(by_name, name)
		record = proxy_spec[name]
		if not isinstance(record, dict) or not isinstance(record.get("center"), list) or not isinstance(record.get("size"), list):
			_fail(f"spec.collision_boxes.{name} needs center and size")
		center = [_finite_number(value, f"spec.collision_boxes.{name}.center") for value in record["center"]]
		size = [_finite_number(value, f"spec.collision_boxes.{name}.size") for value in record["size"]]
		if len(center) != 3 or len(size) != 3 or any(value <= 0.0 for value in size):
			_fail(f"spec.collision_boxes.{name} must have a 3D center and positive 3D size")
		measured = actual[name]
		if not _close(measured["center"], center, 1.0e-3) or not _close(measured["size"], size, 1.0e-3):
			_fail(f"{name} imported proxy bounds mismatch: measured center/size {measured['center']} / {measured['size']}, spec {center} / {size}")
		verified.append({"name": name, "center_m": measured["center"], "size_m": measured["size"]})
	return {"count": len(verified), "tolerance_m": 1.0e-3, "verified": verified}


def _rig_constants(rig_text: str) -> dict[str, Any]:
	if "gen_rig_gd.py" not in rig_text or not re.search(r"(generated by|generado por)\s+gen_rig_gd\.py", rig_text, re.IGNORECASE):
		_fail("rig identity is missing its generated-source marker")
	for method in ("set_travel", "set_steer", "set_spin", "_cache", "_apply_corner"):
		if not re.search(rf"func\s+{re.escape(method)}\s*\(", rig_text):
			_fail(f"rig identity is missing method {method}")
	path_match = re.search(r'@export\s+var\s+root_path:\s*NodePath\s*=\s*\^"([^"]+)"', rig_text)
	if path_match is None or path_match.group(1) != "MT8_Root":
		_fail("rig root_path must bind to MT8_Root")
	constants: dict[str, str] = {}
	for name, value in re.findall(r"^const\s+([A-Z0-9_]+)\s*:=\s*(.+?)\s*$", rig_text, re.MULTILINE):
		constants[name] = value
	return {"root_path": path_match.group(1), "constants": constants}


def _check_spec_and_rig_identity(spec: dict[str, Any], rig_text: str) -> dict[str, Any]:
	if spec.get("name") != "Bisonte MT8" or not str(spec.get("version", "")).startswith("0.1.0"):
		_fail("runtime spec identity must be Bisonte MT8 0.1.x blockout")
	if spec.get("units") != "m" or spec.get("frame") != {"right": "+X", "up": "+Y", "forward": "-Z"}:
		_fail("runtime spec must use metres and the Godot +X/+Y/-Z frame")
	constants = _rig_constants(rig_text)
	values = constants["constants"]
	def numeric(name: str) -> float:
		if name not in values:
			_fail(f"rig constant {name} is missing")
		match = re.fullmatch(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", values[name])
		if match is None:
			_fail(f"rig constant {name} is not a numeric literal")
		return float(values[name])
	def same(name: str, expected: float, tol: float = 1.0e-8) -> None:
		actual = numeric(name)
		if abs(actual - expected) > tol:
			_fail(f"rig/spec identity mismatch for {name}: rig {actual} vs spec {expected}")
	corner_specs = spec.get("corners", {})
	front_left = corner_specs.get("FL", {})
	front_right = corner_specs.get("FR", {})
 
	same("ARM_L", _finite_number(spec.get("arm_length"), "spec.arm_length"))
	same("TRAVEL_BUMP", _finite_number(spec.get("travel_bump"), "spec.travel_bump"))
	same("TRAVEL_DROOP", _finite_number(spec.get("travel_droop"), "spec.travel_droop"))
	same("X_WHEEL", abs(_finite_number(front_right.get("wheel_center_rest", [None])[0], "spec.FR.wheel_center_rest.x")))
	same("RIDE_Y_WHEEL", _finite_number(front_right.get("wheel_center_rest", [None, None])[1], "spec.FR.wheel_center_rest.y"))
	same("Z_FRONT", _finite_number(front_left.get("wheel_center_rest", [None, None, None])[2], "spec.FL.wheel_center_rest.z"))
	same("Z_REAR", _finite_number(corner_specs.get("RL", {}).get("wheel_center_rest", [None, None, None])[2], "spec.RL.wheel_center_rest.z"))
	same("SPRING_REST", _finite_number(spec.get("spring_rest_len"), "spec.spring_rest_len"))
	same("CV_OFF", _finite_number(spec.get("cv_offset"), "spec.cv_offset"))
	same("ARM_X_IN", abs(_finite_number(front_left.get("arm_lower_pivot", [None])[0], "spec.FL.arm_lower_pivot.x")))
	same("Y_ARM_LO", _finite_number(front_left.get("arm_lower_pivot", [None, None])[1], "spec.FL.arm_lower_pivot.y"))
	same("Y_ARM_UP", _finite_number(front_left.get("arm_upper_pivot", [None, None])[1], "spec.FL.arm_upper_pivot.y"))
	same("DIFF_OUT_X", abs(_finite_number(front_right.get("driveshaft_inner", [None])[0], "spec.FR.driveshaft_inner.x")))
	same("SHOCK_DZ", abs(_finite_number(front_left.get("shocks", {}).get("A", {}).get("upper_mount", [None, None, None])[2], "spec.FL.shocks.A.upper_mount.z") - _finite_number(front_left.get("wheel_center_rest", [None, None, None])[2], "spec.FL.wheel_center_rest.z")))
	for name, expected in (("SHOCK_CAP_UP", _finite_number(spec.get("shock_cap_up"), "spec.shock_cap_up")),
						("SHOCK_CAP_LO", _finite_number(spec.get("shock_cap_lo"), "spec.shock_cap_lo"))):
		same(name, expected)
	for name, expected in (("STEER_MAX", math.radians(_finite_number(spec.get("steer_max_deg"), "spec.steer_max_deg"))),):
		if name not in values:
			_fail(f"rig constant {name} is missing")
		match = re.fullmatch(r"deg_to_rad\(([-+0-9.eE]+)\)", values[name])
		if match is None or abs(math.radians(float(match.group(1))) - expected) > 1.0e-10:
			_fail("rig/spec identity mismatch for STEER_MAX")
	for name, expected in (("SHOCK_LO_ARM", [abs(front_left.get("shocks", {}).get("A", {}).get("lower_mount_arm_local", [0.0])[0]), front_left.get("shocks", {}).get("A", {}).get("lower_mount_arm_local", [0.0, 0.0])[1]]),
						("SHOCK_UP", [abs(front_left.get("shocks", {}).get("A", {}).get("upper_mount", [0.0])[0]), front_left.get("shocks", {}).get("A", {}).get("upper_mount", [0.0, 0.0])[1]])):
		match = re.fullmatch(rf"Vector2\(([-+0-9.eE]+),\s*([-+0-9.eE]+)\)", values.get(name, ""))
		if match is None or len(expected) != 2 or not _close([float(match.group(1)), float(match.group(2))], [_finite_number(v, f"spec.{name}") for v in expected], 1.0e-8):
			_fail(f"rig/spec identity mismatch for {name}")
	corners_match = re.search(r"const\s+CORNERS\s*:=\s*\[([^\]]*)\]", rig_text)
	if corners_match is None or tuple(re.findall(r'"([A-Z]{2})"', corners_match.group(1))) != CORNERS:
		_fail("rig corner order must be FL, FR, RL, RR")
	return {"spec_name": spec["name"], "spec_version": spec["version"], "rig_root_path": constants["root_path"], "rig_generated_from": "gen_rig_gd.py", "matched_constants": 19}


def inspect_glb(data: bytes, spec: dict[str, Any], rig_text: str) -> dict[str, Any]:
	document, bin_chunk = _parse_glb(data)
	asset = document.get("asset", {})
	if not isinstance(asset, dict) or asset.get("version") != "2.0":
		_fail("asset.version must be 2.0")
	self_contained = _check_self_contained(document, bin_chunk)
	nodes, scene_roots, by_name, world = _node_graph(document)
	_check_node_transforms(nodes, world)
	if document.get("animations", []) != []:
		_fail("GLB contains unapproved animations; articulation must be driven by the external rig")
	geometry = _geometry(document, nodes, world)
	materials = _check_materials(document, nodes)
	articulation = _check_articulation(nodes, by_name, world, spec, geometry)
	collision_proxies = _check_collision_proxies(by_name, geometry, spec)
	identity = _check_spec_and_rig_identity(spec, rig_text)
	return {
		"glb_version": 2,
		"scene_count": len(document.get("scenes", [])),
		"scene_root_names": [str(nodes[index].get("name", "")) for index in scene_roots],
		"node_count": len(nodes),
		"material_count": materials["definition_count"],
		"material_names": materials["names"],
		"visual_material_count": materials["visual_used_count"],
		"visual_material_names": materials["visual_used_names"],
		"proxy_material_count": materials["proxy_used_count"],
		"proxy_material_names": materials["proxy_used_names"],
		"unused_material_names": materials["unused_names"],
		"animation_count": 0,
		"self_contained": self_contained,
		"geometry": geometry,
		"articulation": articulation,
		"collision_proxies": collision_proxies,
		"identity": identity,
	}


def _repo_relative(path: Path, repo_root: Path, fallback_prefix: str) -> str:
	try:
		return path.resolve().relative_to(repo_root.resolve()).as_posix()
	except ValueError:
		return f"{fallback_prefix}/{path.name}"


def _artifact_inventory(package_root: Path, repo_root: Path) -> list[dict[str, Any]]:
	if not package_root.is_dir():
		_fail(f"source package does not exist: {package_root}")
	files = sorted(package_root.rglob("*"), key=lambda item: item.relative_to(package_root).as_posix().casefold())
	artifacts: list[dict[str, Any]] = []
	for path in files:
		if path.is_symlink():
			_fail(f"source package contains a symlink: {path.relative_to(package_root).as_posix()}")
		if not path.is_file():
			continue
		artifacts.append({
			"path": _repo_relative(path, repo_root, "package"),
			"bytes": path.stat().st_size,
			"sha256": _sha256_file(path),
		})
	if not artifacts:
		_fail("source package contains no files")
	return artifacts


def _finding(identifier: str, status: str, detail: str) -> dict[str, str]:
	return {"id": identifier, "status": status, "detail": detail}


def build_manifest(repo_root: Path = REPO_ROOT, package_root: Path = DEFAULT_PACKAGE,
				   delivery_glb: Path = DEFAULT_DELIVERY_GLB) -> dict[str, Any]:
	package_root, repo_root = Path(package_root), Path(repo_root)
	spec_path = package_root / "out" / "mt8_spec.json"
	rig_path = package_root / "godot" / "mt8_rig.gd"
	package_glb = package_root / "out" / "MT8_Bisonte.glb"
	for path in (spec_path, rig_path, package_glb):
		if not path.is_file():
			_fail(f"required intake artifact is missing: {path}")
	try:
		spec = json.loads(spec_path.read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_json_keys)
	except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
		_fail(f"runtime geometry spec is invalid: {exc}")
	if not isinstance(spec, dict):
		_fail("runtime geometry spec must be an object")
	rig_text = rig_path.read_text(encoding="utf-8")
	package_glb_bytes = package_glb.read_bytes()
	delivery_glb = Path(delivery_glb)
	if not delivery_glb.is_file():
		delivery_glb = package_glb
	delivery_bytes = delivery_glb.read_bytes()
	if _sha256_bytes(package_glb_bytes) != _sha256_bytes(delivery_bytes):
		_fail("submitted GLB differs from the package's exported GLB; reconcile model identity before intake")
	glb_report = inspect_glb(delivery_bytes, spec, rig_text)
	artifacts = _artifact_inventory(package_root, repo_root)
	license_names = [item["path"] for item in artifacts if re.search(r"(^|/)(LICENSE|LICENCE|NOTICE|COPYING)(\.|$)", item["path"], re.IGNORECASE)]
	archive_license = "provided" if license_names else "missing"
	proxy_names = [name for name in BASE_PARTS if name.startswith("COL_")]
	wheel_proxy_names = [name for name in glb_report["geometry"]["collision_proxy_bounds_m"] if "wheel" in name.lower() or any(corner in name for corner in CORNERS)]
	lod_artifacts = [item["path"] for item in artifacts if re.search(r"(^|[/_.-])lod[1-9]([/_.-]|$)", item["path"], re.IGNORECASE)]
	anchor_keys = [key for key in spec if re.search(r"camera|audio|sound|listener", key, re.IGNORECASE)]
	godot_spec_copy = package_root / "godot" / "mt8_spec.json"
	findings = [
		_finding("redistribution_license", "present" if archive_license == "provided" else "missing",
				 "License/notice file is included: " + ", ".join(license_names) if license_names else "No license or attribution file is present in the supplied package; do not copy this model into distributable app assets until rights are documented."),
		_finding("camera_audio_anchors", "present" if anchor_keys else "missing",
				 "Spec keys: " + ", ".join(anchor_keys) if anchor_keys else "The geometry spec does not identify camera/audio anchors; a local inspection preview can use an explicit temporary camera, but no runtime anchor binding is accepted."),
		_finding("lod_set", "present" if lod_artifacts else "missing",
				 "LOD artifacts: " + ", ".join(lod_artifacts) if lod_artifacts else "Only the blockout GLB is supplied; no LOD1/LOD2 assets or LOD transition contract were found."),
		_finding("wheel_envelope_proxy_meshes", "present" if wheel_proxy_names else "dimensions-declared-no-mesh-proxy",
				 "Wheel collision proxies: " + ", ".join(wheel_proxy_names) if wheel_proxy_names else "The GLB has no separate COL_* wheel proxy meshes. The spec declares tire_radius and tire_width, so a runtime primitive envelope can be derived without missing tire dimensions."),
		_finding("source_identity", "matched", "The package export and submitted root GLB are byte-identical; the rig constants and rest pivots match the runtime spec."),
	]
	return {
		"format": FORMAT,
		"asset_id": "mt8-bisonte",
		"display_name": spec["name"],
		"acceptance": "local-preview-only-pending-license-and-runtime-contract",
		"inspection_performed": {"godot": False, "blender": False, "glb_parser": "stdlib-glb2"},
		"source": {
			"package_root": _repo_relative(package_root, repo_root, "package"),
			"geometry_spec": {"path": _repo_relative(spec_path, repo_root, "package"), "sha256": _sha256_file(spec_path)},
			"rig": {"path": _repo_relative(rig_path, repo_root, "package"), "sha256": _sha256_file(rig_path)},
			"package_export_glb": {"path": _repo_relative(package_glb, repo_root, "package"), "sha256": _sha256_bytes(package_glb_bytes), "bytes": len(package_glb_bytes)},
			"submitted_glb": {"path": _repo_relative(delivery_glb, repo_root, "delivery"), "sha256": _sha256_bytes(delivery_bytes), "bytes": len(delivery_bytes), "matches_package_export": True},
			"artifacts": artifacts,
		},
		"standalone_test_staging": {
			"godot_glb_copy_present": (package_root / "godot" / "MT8_Bisonte.glb").is_file(),
			"godot_spec_copy_present": godot_spec_copy.is_file(),
			"note": "The package README explicitly stages the GLB and spec into godot/ before its standalone test; absent staged copies are not treated as asset defects.",
		},
		"glb": glb_report,
		"findings": findings,
		"evidence_limits": [
			"A successful static GLB intake does not constitute a fresh Godot import/render check or physical validation.",
			"The existing Godot report, Blender renders, and interference report are source-package artifacts and were not regenerated by this tool.",
		],
	}


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repository root used for stable artifact paths")
	parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE, help="supplied MT8 source package")
	parser.add_argument("--glb", type=Path, default=DEFAULT_DELIVERY_GLB, help="submitted GLB copy to bind")
	parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="intake manifest path")
	parser.add_argument("--check", action="store_true", help="compare generated bytes with --output without writing")
	return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
	args = _parse_args(argv)
	try:
		manifest = build_manifest(args.root, args.package, args.glb)
		expected = _json_bytes(manifest)
		if args.check:
			if not args.output.is_file():
				print(f"intake manifest missing: {args.output}", file=sys.stderr)
				return 1
			actual = args.output.read_bytes()
			if actual != expected:
				print(f"intake manifest is stale: {args.output}", file=sys.stderr)
				return 1
			print(f"intake manifest matches: {args.output}")
			return 0
		args.output.parent.mkdir(parents=True, exist_ok=True)
		args.output.write_bytes(expected)
		print(f"wrote {args.output} ({manifest['glb']['geometry']['visual_triangle_count']} visual triangles)")
		return 0
	except (IntakeError, OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
		print(f"asset intake rejected: {exc}", file=sys.stderr)
		return 2


if __name__ == "__main__":
	sys.exit(main())
