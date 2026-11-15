extends RefCounted

# Explicit diagnostic only. The captured list is historical; current nodes can
# share resources, have changed, or be outside the rendered scene.
const NODE_LIMIT := 8192
const RESULT_LIMIT := 64
const ENTRY_LIMIT := 8
const CHAIN_LIMIT := 8
const PATH_LIMIT := 1024


static func _path(node: Node) -> Dictionary:
	# Avoid Node.get_path(), which populates the node's internal path cache.
	var parts: Array[String] = []
	var length := 0
	var current: Node = node
	var truncated := false
	while current != null:
		var part := str(current.name)
		if length + part.length() + 1 > PATH_LIMIT or parts.size() >= NODE_LIMIT:
			truncated = true
			break
		parts.append(part)
		length += part.length() + 1
		current = current.get_parent()
	parts.reverse()
	return {"path": (".../" if truncated else "/") + "/".join(PackedStringArray(parts)), "path_truncated": truncated}


static func _material_chain(material: Material) -> Dictionary:
	var values: Array[Dictionary] = []
	var seen := {}
	var cycle := false
	while material != null and values.size() < CHAIN_LIMIT:
		var object_id := material.get_instance_id()
		if seen.has(object_id):
			cycle = true
			break
		seen[object_id] = true
		var resource_path := material.resource_path
		var item := {
			"object_id": object_id,
			"class": material.get_class(),
			"resource_path": resource_path.substr(0, 256),
			"resource_path_truncated": resource_path.length() > 256,
		}
		if material is ShaderMaterial:
			var shader: Shader = (material as ShaderMaterial).shader
			if shader != null:
				var shader_path := shader.resource_path
				item["shader_path"] = shader_path.substr(0, 256)
				item["shader_path_truncated"] = shader_path.length() > 256
		values.append(item)
		material = material.next_pass
	# Material.get_rid() can initialize a material or update a shader. It is
	# intentionally not called, including for override and next-pass resources.
	return {"resources": values, "truncated": material != null, "cycle": cycle, "resource_rids_available": false}


static func _candidate(node: GeometryInstance3D, entry: Dictionary, entry_index: int, viewport: Viewport) -> Dictionary:
	var base := node.get_base()
	var mesh: RID = base
	var mesh_resource: Mesh = null
	if node is MeshInstance3D:
		mesh_resource = (node as MeshInstance3D).mesh
	else:
		mesh = RenderingServer.multimesh_get_mesh(base)
		var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if multimesh != null:
			mesh_resource = multimesh.mesh
	var surface := int(entry.get("surface", -1))
	var surface_valid := mesh.is_valid() and surface >= 0 and surface < RenderingServer.mesh_get_surface_count(mesh)
	var mesh_material := RID()
	if surface_valid:
		mesh_material = RenderingServer.mesh_surface_get_material(mesh, surface)
	var override_material: Material = node.material_override
	var surface_override: Material = null
	if node is MeshInstance3D and surface >= 0:
		var instance := node as MeshInstance3D
		if surface < instance.get_surface_override_material_count():
			surface_override = instance.get_surface_override_material(surface)
	var effective: Material = override_material
	var source := "material_override"
	if effective == null:
		effective = surface_override
		source = "surface_override"
	if effective == null:
		source = "mesh_surface"
		# These native getters read stored references. PrimitiveMesh's
		# get_surface_count/get_rid can rebuild the mesh, so do not call them.
		if surface_valid and mesh_resource is ArrayMesh and surface < (mesh_resource as ArrayMesh).get_surface_count():
			effective = (mesh_resource as ArrayMesh).surface_get_material(surface)
		elif surface_valid and mesh_resource is PrimitiveMesh and surface == 0:
			effective = (mesh_resource as PrimitiveMesh).surface_get_material(surface)
	var path := _path(node)
	var mesh_match := "unavailable"
	if mesh.is_valid() and entry.get("mesh_rid_available", false):
		mesh_match = "match" if mesh.get_id() == int(entry.get("mesh_rid", 0)) else "different"
	return {
		"entry_index": entry_index,
		"relationship": "base_rid_candidate_not_proof_of_material_instance_or_pixels",
		"path": path.path,
		"path_truncated": path.path_truncated,
		"class": node.get_class(),
		"visible_in_tree": node.is_visible_in_tree(),
		"current_viewport_matches": node.get_viewport() == viewport,
		"current_instance_rid": node.get_instance().get_id(),
		"base_rid": base.get_id(),
		"mesh_rid": mesh.get_id(),
		"mesh_match": mesh_match,
		"surface": surface,
		"surface_valid": surface_valid,
		"mesh_surface_material_rid": mesh_material.get_id(),
		"mesh_surface_material_rid_available": mesh_material.is_valid(),
		"current_first_material_source": source,
		"current_first_material_scope": "node_selection_not_captured_pass_or_renderer_fallback",
		"current_first_material_rid": mesh_material.get_id() if source == "mesh_surface" else 0,
		"current_first_material_rid_available": source == "mesh_surface" and mesh_material.is_valid(),
		"material_override": _material_chain(override_material),
		"surface_override": _material_chain(surface_override),
		"current_first_material": _material_chain(effective),
		"material_overlay": _material_chain(node.material_overlay),
	}


static func snapshot(root: Node) -> Dictionary:
	var result := {
		"status": "unavailable",
		"scope": "historical_resource_candidates_not_unique_instances_or_pixel_contribution",
		"coverage": "current root subtree; MeshInstance3D and MultiMeshInstance3D only",
		"candidates": [], "visited_nodes": 0,
		"nodes_truncated": false, "results_truncated": false,
	}
	if not is_instance_valid(root) or not root.is_inside_tree():
		result["reason"] = "root_not_in_tree"
		return result
	if not RenderingServer.has_method("viewport_get_metalfx_frame_status"):
		result["reason"] = "frame_status_api_unavailable"
		return result
	var viewport := root.get_viewport()
	if viewport == null:
		result["reason"] = "viewport_unavailable"
		return result
	var status: Variant = RenderingServer.call("viewport_get_metalfx_frame_status", viewport.get_viewport_rid())
	if not status is Dictionary:
		result["reason"] = "frame_status_malformed"
		return result
	result["frame_status"] = status
	var detail: Variant = status.get("alpha_diagnostic")
	if detail == null:
		result["reason"] = "alpha_diagnostic_unavailable_or_not_captured"
		return result
	if not detail is Dictionary or not detail.get("entries") is Array:
		result["reason"] = "alpha_diagnostic_malformed"
		return result
	result["capture_viewport_matches"] = int(detail.get("viewport_rid", 0)) == viewport.get_viewport_rid().get_id()
	var entries: Array = detail.entries
	var by_base := {}
	result["entries_truncated"] = entries.size() > ENTRY_LIMIT
	for index in mini(entries.size(), ENTRY_LIMIT):
		if entries[index] is Dictionary:
			var id := int(entries[index].get("base_rid", 0))
			if id != 0:
				if not by_base.has(id):
					by_base[id] = []
				by_base[id].append(index)
	var pending: Array[Node] = [root]
	var cursor := 0
	var candidates: Array = result.candidates
	while cursor < pending.size():
		var node := pending[cursor]
		cursor += 1
		result.visited_nodes = cursor
		if not is_instance_valid(node):
			continue
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			var geometry := node as GeometryInstance3D
			var base := geometry.get_base()
			if base.is_valid() and by_base.has(base.get_id()):
				for index: int in by_base[base.get_id()]:
					if candidates.size() >= RESULT_LIMIT:
						result.results_truncated = true
						break
					candidates.append(_candidate(geometry, entries[index], index, viewport))
		if result.results_truncated:
			break
		var count := node.get_child_count(true)
		var remaining := NODE_LIMIT - pending.size()
		if count > remaining:
			result.nodes_truncated = true
		for child in mini(count, remaining):
			pending.append(node.get_child(child, true))
	result["status"] = "observed"
	return result
