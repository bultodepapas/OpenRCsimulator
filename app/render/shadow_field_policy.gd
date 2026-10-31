## Own the existing field projections and the bounded Native comparison casters.
## Discover source geometry once at attachment or manager replacement, never per frame.
extends Node

const ShadowSettings = preload("res://render/shadow_settings.gd")
const FieldShadows = preload("res://render/field_projected_shadows.gd")
const OPAQUE_SHELTER_SHADER := "res://scenery/pit_shelter_roof.gdshader"
const MAX_SHELTER_MESHES := 2
const OPAQUE_CUE_SHADERS := [
	"res://render/pilot_station.gdshader", "res://render/flightline_barrier.gdshader",
	"res://render/windsock_support.gdshader", "res://render/windsock_fabric.gdshader",
]

var _manager: Node
var _pilot: Dictionary = {}
var _planes: Array[MeshInstance3D] = []
var _prior_visibility: Array[bool] = []
var _enabled := true
var _revision := -1
var _native_casters: Array[GeometryInstance3D] = []
var _native_prior: Array[int] = []
var _native_active := false
var _diagnostics: Dictionary = {}


static func attach(field: Node3D, field_data: Dictionary = {}) -> void:
	var policy := new()
	policy.name = "ShadowFieldPolicy"
	policy._pilot = (field_data.get("pilot", {}) as Dictionary).duplicate(true)
	policy._capture(field, field.get_node_or_null("ProjectedFieldShadows"))
	if policy._manager == null and policy._planes.is_empty() and policy._native_casters.is_empty():
		policy.free()
		return
	field.add_child(policy)
	field.set_meta("shadow_field_policy", policy)
	policy.apply_shadow_policy()


func _ready() -> void:
	add_to_group("shadow_policy_consumers")
	process_priority = -100
	# The manager's own _ready may have reapplied lighting as a detached field entered the tree.
	apply_shadow_policy(true)


func _process(_delta: float) -> void:
	if _revision != ShadowSettings.revision:
		apply_shadow_policy()


func apply_shadow_policy(force: bool = false) -> void:
	var enabled := ShadowSettings.projected_enabled()
	if not force and _revision == ShadowSettings.revision:
		return
	_revision = ShadowSettings.revision
	var effective := ShadowSettings.effective()
	_set_native_casters(str(effective.technique) == "native" and bool(effective.native))
	if not enabled:
		if _enabled:
			_prior_visibility.clear()
			for plane in _planes:
				_prior_visibility.append(plane.visible if is_instance_valid(plane) else false)
		for plane in _planes:
			if is_instance_valid(plane):
				plane.visible = false
		_disable_projectors()
	elif not _enabled:
		_restore_planes()
		if is_instance_valid(_manager):
			_manager.apply(_manager.snapshot)
	_enabled = enabled


## Replace a retired manager only on a lighting commit; the normal revision poll is constant work.
func apply_lighting(lighting: Dictionary) -> void:
	var field := get_parent() as Node3D
	var current := field.get_node_or_null("ProjectedFieldShadows")
	if current != _manager:
		_set_native_casters(false)
		var was_suppressed := not _enabled
		if was_suppressed:
			_restore_planes()
		_enabled = true
		_capture(field, current)
		if was_suppressed:
			_hide_managed_fallbacks(field)
		_revision = -1
		apply_shadow_policy(true)
	else:
		apply_shadow_policy()
	if not is_instance_valid(_manager):
		return
	if _enabled:
		_manager.apply(lighting)
	else:
		_manager.snapshot = lighting.duplicate(true)


func _restore_planes() -> void:
	for index in mini(_planes.size(), _prior_visibility.size()):
		if is_instance_valid(_planes[index]):
			_planes[index].visible = _prior_visibility[index]


func _capture(field: Node3D, manager: Node) -> void:
	_manager = manager
	_planes.clear()
	_native_casters.clear()
	_native_prior.clear()
	_diagnostics = {"active": false, "source_meshes": 0, "population_batches": 0,
		"skipped_material": 0, "skipped_population_range": 0, "selected_cells": 0,
		"shelter_meshes": 0, "skipped_shelter_range": 0, "skipped_shelter_budget": 0,
		"enabled_from_off": 0, "already_casting": 0,
		"max_shelter_meshes": MAX_SHELTER_MESHES,
		"max_scenery_range_m": FieldShadows.MAX_SCENERY_RANGE}
	var cues := field.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if cues != null:
		_planes.append(cues)
	var scenery := field.get_node_or_null("Scenery") as Node3D
	if scenery != null:
		for child: Node in scenery.get_children():
			if child is MeshInstance3D and (str(child.name).begins_with("shadows_") or child.name == "PopulationContacts"):
				_planes.append(child as MeshInstance3D)
	if is_instance_valid(_manager):
		var selected_cells: Dictionary = {}
		for projector: Node in _manager.projectors:
			var source := projector.get("source") as Node3D
			if not is_instance_valid(source):
				continue
			_collect_source(source, source)
			if scenery != null and source.get_parent() == scenery and str(source.name).begins_with("cell_"):
				var parts := str(source.name).split("_")
				if parts.size() == 3:
					selected_cells[Vector2i(int(parts[1]), int(parts[2]))] = projector
		_diagnostics.selected_cells = selected_cells.size()
		_collect_population(scenery, selected_cells)
	_collect_shelters(scenery)
	if _manager != null or not _planes.is_empty() or not _native_casters.is_empty():
		field.set_meta("shadow_native_casters", _diagnostics)


func _hide_managed_fallbacks(field: Node3D) -> void:
	if not is_instance_valid(_manager):
		return
	var scenery := field.get_node_or_null("Scenery") as Node3D
	for projector: Node in _manager.projectors:
		var source := projector.get("source") as Node3D
		if not is_instance_valid(source):
			continue
		if source.get_parent() == field:
			var cues := field.get_node_or_null("FlightCueShadows") as MeshInstance3D
			if cues != null:
				cues.visible = false
		elif scenery != null and source.get_parent() == scenery and str(source.name).begins_with("cell_"):
			var old := scenery.get_node_or_null(NodePath(str(source.name).replace("cell_", "shadows_"))) as MeshInstance3D
			if old != null:
				old.visible = false


func _collect_source(node: Node, source: Node3D) -> void:
	if node != source:
		if node is Node3D and not (node as Node3D).visible:
			return
		var node_name := str(node.name).to_lower()
		if node_name == "propeller" or node_name.contains("shadow") or node_name == "soilcollars":
			return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			if _opaque_mesh(mesh_node, mesh_node.mesh):
				_add_caster(mesh_node, false)
			else:
				_diagnostics.skipped_material += 1
	for child: Node in node.get_children():
		if not child is MultiMeshInstance3D:
			_collect_source(child, source)


## A MultiMesh casts every instance together. Admit only complete, in-range batches whose
## placements all belong to selected projected cells; mixed or alpha-cut batches remain off.
func _collect_population(scenery: Node3D, selected_cells: Dictionary) -> void:
	if scenery == null or selected_cells.is_empty() or _pilot.is_empty():
		return
	var population := scenery.get_node_or_null("Population") as Node3D
	if population == null:
		return
	var eligible_batches: Array[MultiMeshInstance3D] = []
	for child: Node in population.get_children():
		if not child is MultiMeshInstance3D or not (child as MultiMeshInstance3D).visible:
			continue
		var batch := child as MultiMeshInstance3D
		var asset := str(batch.get_meta("source_asset", ""))
		if asset not in ["standing", "sitting", "pilot"] or batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		var count := batch.multimesh.instance_count
		var placements: Array = batch.get_meta("placements", [])
		var transforms: Array = batch.get_meta("instance_transforms", [])
		if count == 0 or placements.size() < count or transforms.size() < count:
			continue
		if not _opaque_mesh(batch, batch.multimesh.mesh):
			_diagnostics.skipped_material += 1
			continue
		eligible_batches.append(batch)
	if eligible_batches.is_empty():
		return
	var pilot := Vector2(float(_pilot.east), -float(_pilot.north))
	var candidates: Array[MeshInstance3D] = []
	for child: Node in scenery.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("cell_"):
			continue
		var cell := child as MeshInstance3D
		if cell.mesh == null:
			continue
		var box := cell.mesh.get_aabb()
		var center := box.get_center()
		if box.size.y >= 0.08 and Vector2(center.x, center.z).distance_to(pilot) <= FieldShadows.MAX_SCENERY_RANGE:
			candidates.append(cell)
	var owners: Dictionary = FieldShadows.population_cell_owners(candidates, population, pilot)
	for batch in eligible_batches:
		var asset := str(batch.get_meta("source_asset", ""))
		var mesh := batch.multimesh.mesh
		var placements: Array = batch.get_meta("placements", [])
		var transforms: Array = batch.get_meta("instance_transforms", [])
		var count := batch.multimesh.instance_count
		var faces := mesh.get_faces()
		if faces.is_empty():
			continue
		var eligible := true
		for index in count:
			var placement: Dictionary = placements[index]
			var pos: Vector3 = (placement.get("transform", Transform3D.IDENTITY) as Transform3D).origin
			var id := "%s:%d" % [str(batch.get_meta("asset_key", asset)), index]
			if not owners.has(id) or not selected_cells.has(owners[id]) \
					or Vector2(pos.x, pos.z).distance_to(pilot) > FieldShadows.MAX_SCENERY_RANGE \
					or int((selected_cells[owners[id]] as Node).get_meta("population_triangles", 0)) <= 0:
				eligible = false
				break
			var cell: Node3D = (selected_cells[owners[id]] as Node).get("source")
			var to_cell: Transform3D = cell.transform.affine_inverse() * population.transform * batch.transform * transforms[index]
			var has_projected_face := false
			for point: Vector3 in faces:
				if (to_cell * point).y > 0.04:
					has_projected_face = true
					break
			if not has_projected_face:
				eligible = false
				break
		if not eligible:
			_diagnostics.skipped_population_range += 1
		else:
			_add_caster(batch, true)


## Separate shelter meshes are baked in scenery coordinates. Admit at most two whose
## complete transformed horizontal bounds fit within the existing near-field radius.
func _collect_shelters(scenery: Node3D) -> void:
	if scenery == null or _pilot.is_empty():
		return
	var pilot := Vector2(float(_pilot.east), -float(_pilot.north))
	var candidates: Array[Dictionary] = []
	for child: Node in scenery.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("PitShelter_"):
			continue
		var shelter := child as MeshInstance3D
		if not shelter.visible:
			continue
		if shelter.mesh == null or shelter.mesh.get_surface_count() != 1:
			_diagnostics.skipped_material += 1
			continue
		var material: Material = shelter.material_override if shelter.material_override != null else shelter.get_active_material(0)
		var shader: Shader = (material as ShaderMaterial).shader if material is ShaderMaterial else null
		if shader == null or shader.resource_path != OPAQUE_SHELTER_SHADER or not _opaque_mesh(shelter, shelter.mesh, true):
			_diagnostics.skipped_material += 1
			continue
		var bounds: AABB = (scenery.transform * shelter.transform) * shelter.mesh.get_aabb()
		var center := bounds.get_center()
		var furthest := Vector2(absf(center.x - pilot.x) + bounds.size.x * 0.5,
			absf(center.z - pilot.y) + bounds.size.z * 0.5)
		if not is_finite(furthest.x) or not is_finite(furthest.y) \
				or furthest.length_squared() > FieldShadows.MAX_SCENERY_RANGE * FieldShadows.MAX_SCENERY_RANGE:
			_diagnostics.skipped_shelter_range += 1
			continue
		candidates.append({"node": shelter, "distance_squared": Vector2(center.x, center.z).distance_squared_to(pilot)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance_squared != b.distance_squared:
			return float(a.distance_squared) < float(b.distance_squared)
		return str((a.node as Node).name) < str((b.node as Node).name))
	for index in candidates.size():
		if index >= MAX_SHELTER_MESHES:
			_diagnostics.skipped_shelter_budget += 1
			continue
		var shelter := candidates[index].node as MeshInstance3D
		if not _native_casters.has(shelter):
			_add_caster(shelter, false)
			_diagnostics.shelter_meshes += 1


func _opaque_mesh(node: GeometryInstance3D, mesh: Mesh, allow_shelter_shader: bool = false) -> bool:
	if node.material_overlay != null:
		return false
	for index in mesh.get_surface_count():
		var material: Material = node.material_override
		if material == null:
			material = (node as MeshInstance3D).get_active_material(index) if node is MeshInstance3D else mesh.surface_get_material(index)
		if material == null:
			continue # Godot's default surface material is opaque.
		if material.next_pass != null:
			return false
		if material is BaseMaterial3D:
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return false
		elif material is ShaderMaterial:
			if material.shader == null:
				return false
			var shader_path: String = material.shader.resource_path
			if shader_path not in OPAQUE_CUE_SHADERS \
					and not (allow_shelter_shader and shader_path == OPAQUE_SHELTER_SHADER):
				return false
		else:
			return false
	return mesh.get_surface_count() > 0


func _add_caster(caster: GeometryInstance3D, population: bool) -> void:
	if _native_casters.has(caster):
		return
	_native_casters.append(caster)
	_diagnostics.population_batches += 1 if population else 0
	_diagnostics.source_meshes += 0 if population else 1


func _set_native_casters(active: bool) -> void:
	if active == _native_active:
		return
	if active:
		_native_prior.clear()
		_diagnostics.enabled_from_off = 0
		_diagnostics.already_casting = 0
		for caster in _native_casters:
			_native_prior.append(int(caster.cast_shadow) if is_instance_valid(caster) else -1)
			if is_instance_valid(caster) and caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				_diagnostics.enabled_from_off += 1
			elif is_instance_valid(caster):
				_diagnostics.already_casting += 1
	else:
		for index in mini(_native_casters.size(), _native_prior.size()):
			var caster := _native_casters[index]
			if is_instance_valid(caster) and _native_prior[index] >= 0:
				caster.cast_shadow = _native_prior[index] as GeometryInstance3D.ShadowCastingSetting
		_diagnostics.enabled_from_off = 0
		_diagnostics.already_casting = 0
	_native_active = active
	_diagnostics.active = active


func _disable_projectors() -> void:
	if not is_instance_valid(_manager):
		return
	_manager.set_process(false)
	for projector: Node in _manager.projectors:
		var request: Array = projector.get("_last_request")
		if request.size() == 4:
			projector.refresh(request[0], request[1], request[2], false)
		else:
			projector.refresh(float(projector.get_meta("soft_height", 0.0)), Vector3.UP, 0.0, false)
