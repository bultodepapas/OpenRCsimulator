## RCV-38: per-vehicle lamp materials and a bounded light rig for the supplied GLB.
## No simulation state, geometry or shared material is modified.
extends Node3D

const GROUPS := {
	"head": ["Faros"],
	"running": ["Faros_Diurna", "Faros_Direccional", "Marcadores_Ambar"],
	"auxiliary": ["LED_Frontal", "LED_Techo", "Focos_Antivuelco_LED", "Antiniebla_Lente"],
	"tail": ["Calaveras"],
	"neon": ["Neon_Lateral", "Neon_Frente_Cola", "Aleron_Gurney"],
	"accent": ["Carroceria_Casco", "Carroceria_Cabina", "Capo_Bulto", "Aleron_Aletas"],
}
const WHITE := Color(0.82, 0.91, 1.0)
const RED := Color(1.0, 0.012, 0.018)
const NEON := Color(0.12, 1.0, 0.028)
const LIGHT_BUDGET := 5

var headlights: Array[SpotLight3D] = []
var _lights: Array[SpotLight3D] = []
var _auxiliary: SpotLight3D
var _underglow: SpotLight3D
var _stop_spill: SpotLight3D
var _groups := {}
var _group_energy := {}
var _body: MeshInstance3D
var _prepared := false
var _last_night := -1.0
var _last_heads := false
var _last_aux := false
var _last_neon := false
var _last_brake := false
var _last_visible := false
var _update_count := 0
var _material_writes := 0
var _material_count := 0


func prepare(visual: Dictionary) -> bool:
	if _prepared or not visual.get("root") is Node3D or not visual.get("_mesh_nodes") is Dictionary \
			or not visual.get("nodes") is Dictionary:
		return false
	var vehicle: Node3D = visual.root
	var meshes: Dictionary = visual._mesh_nodes
	# Validate the entire authored set before creating overrides or lights.
	for group: String in GROUPS:
		for mesh_name: String in GROUPS[group]:
			var mesh: Variant = meshes.get(mesh_name)
			if not mesh is MeshInstance3D or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
				return false
			for surface in mesh.mesh.get_surface_count():
				if not mesh.get_active_material(surface) is StandardMaterial3D:
					return false
	var anchors: Variant = visual.get("headlight_positions")
	if not anchors is Array or anchors.size() != 2:
		return false
	for point: Variant in anchors:
		if not point is Vector3 or not point.is_finite(): return false
	_body = visual.nodes.get("Body") as MeshInstance3D
	if _body == null: return false
	name = "MonsterCar2Lights"
	if get_parent() == null: vehicle.add_child(self)
	if get_parent() != vehicle: return false
	# One material copy per source/group, not one copy per LED or per frame.
	for group: String in GROUPS:
		var materials: Array[StandardMaterial3D] = []
		var copies := {}
		for mesh_name: String in GROUPS[group]:
			var mesh := meshes[mesh_name] as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				var key := source.get_instance_id()
				if not copies.has(key):
					var material := source.duplicate() as StandardMaterial3D
					material.emission_enabled = true
					material.emission_energy_multiplier = 0.0
					material.emission = RED if group == "tail" else NEON if group == "neon" else WHITE
					# Retain the author's blue daytime signature and warm fog lenses.
					if group in ["running", "accent"] or mesh_name == "Antiniebla_Lente":
						material.emission = source.emission if source.emission_enabled else source.albedo_color
					copies[key] = material
					materials.append(material)
					_material_count += 1
				mesh.set_surface_override_material(surface, copies[key])
		_groups[group] = materials
		_group_energy[group] = 0.0
	for i in 2:
		var position: Vector3 = anchors[i] + Vector3(0, 0, -0.008)
		headlights.append(_spot("HeadLowBeam" + str(i), position, Vector3(0, -0.105, -1), WHITE, 7.0, 30.0, 18.0, 8.0))
	# Flattened GLB pivots are at the origin; anchors come from the vertex bounds.
	var roof := _center_in_vehicle(meshes.LED_Techo, vehicle)
	_auxiliary = _spot("AuxiliaryRoofBeam", roof + Vector3(0, 0, -0.012),
		Vector3(0, -0.08, -1), WHITE, 11.0, 24.0, 22.0, 10.0)
	var neon_center := _center_in_vehicle(meshes.Neon_Lateral, vehicle)
	_underglow = _spot("NeonGroundWash", neon_center + Vector3(0, -0.008, 0),
		Vector3.DOWN, NEON, 0.8, 78.0, 6.0, 4.0)
	var rear := _center_in_vehicle(meshes.Calaveras, vehicle)
	_stop_spill = _spot("StopGroundWash", rear + Vector3(0, -0.01, 0.012),
		Vector3(0, -0.65, 1), RED, 0.9, 65.0, 8.0, 4.0)
	_prepared = true
	observe({}, 0.0, true, false, true)
	return true


func _spot(label: String, position_value: Vector3, direction: Vector3, color_value: Color,
		range_m: float, angle: float, fade_begin: float, fade_length: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = label
	light.position = position_value
	light.basis = Basis.looking_at(direction.normalized(), Vector3.FORWARD if direction == Vector3.DOWN else Vector3.UP)
	light.light_color = color_value
	light.light_energy = 0.0
	light.visible = false
	light.light_specular = 0.35
	light.light_indirect_energy = 0.0
	light.light_volumetric_fog_energy = 0.0
	light.light_bake_mode = Light3D.BAKE_DISABLED
	light.spot_range = range_m
	light.spot_angle = angle
	light.spot_attenuation = 1.15
	light.spot_angle_attenuation = 1.6
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = fade_begin
	light.distance_fade_length = fade_length
	add_child(light)
	_lights.append(light)
	return light


## Telemetry/input observer only. Brake lights work independently of the light switch.
## Unchanged accepted inputs perform no material or RenderingServer setter work.
func observe(controls: Dictionary, night_weight: float, heads: bool, auxiliary: bool, neon: bool) -> void:
	if not _prepared: return
	var night := clampf(night_weight, 0.0, 1.0) if is_finite(night_weight) else 0.0
	var brake_value: Variant = controls.get("brake", 0.0)
	var brake: bool = typeof(brake_value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(brake_value)) and float(brake_value) >= 0.08
	var shown := _body.is_visible_in_tree()
	if night == _last_night and heads == _last_heads and auxiliary == _last_aux \
			and neon == _last_neon and brake == _last_brake and shown == _last_visible:
		return
	_last_night = night
	_last_heads = heads
	_last_aux = auxiliary
	_last_neon = neon
	_last_brake = brake
	_last_visible = shown
	_update_count += 1
	_set_group("head", lerpf(1.8, 4.0, night) if heads else 0.0)
	_set_group("running", lerpf(0.75, 1.8, night) if heads else 0.0)
	_set_group("auxiliary", lerpf(2.0, 5.0, night) if auxiliary else 0.0)
	_set_group("tail", lerpf(5.0, 3.5, night) if brake else lerpf(0.22, 0.6, night) if heads else 0.0)
	_set_group("neon", lerpf(0.4, 2.4, night) if neon else 0.0)
	_set_group("accent", lerpf(0.10, 0.35, night) if neon else 0.0)
	for light in headlights: _set_light(light, lerpf(0.18, 2.1, night) if heads and shown else 0.0)
	_set_light(_auxiliary, lerpf(0.24, 3.2, night) if auxiliary and shown else 0.0)
	_set_light(_underglow, night * 0.65 if neon and shown else 0.0)
	_set_light(_stop_spill, night * (0.65 if brake else 0.07 if heads else 0.0) if shown else 0.0)


func _set_group(group: String, energy: float) -> void:
	if _group_energy[group] == energy: return
	_group_energy[group] = energy
	for material: StandardMaterial3D in _groups[group]:
		material.emission_energy_multiplier = energy
		_material_writes += 1


func _set_light(light: SpotLight3D, energy: float) -> void:
	if light.light_energy != energy: light.light_energy = energy
	var enabled := energy > 0.0
	if light.visible != enabled: light.visible = enabled


func diagnostic_snapshot() -> Dictionary:
	var active := 0
	var shadowed := 0
	for light in _lights:
		if light.visible and light.light_energy > 0.0: active += 1
		if light.shadow_enabled: shadowed += 1
	return {"prepared": _prepared, "headlights_enabled": _last_heads, "auxiliary_enabled": _last_aux,
		"neon_enabled": _last_neon, "brake_lights": _last_brake, "body_visible": _last_visible,
		"night_weight": _last_night, "light_node_count": _lights.size(), "active_lights": active,
		"shadow_light_count": shadowed, "light_budget": LIGHT_BUDGET, "material_count": _material_count,
		"update_count": _update_count, "material_writes": _material_writes,
		"headlight_energy": headlights[0].light_energy if not headlights.is_empty() else 0.0,
		"auxiliary_energy": _auxiliary.light_energy if _auxiliary != null else 0.0,
		"neon_energy": _underglow.light_energy if _underglow != null else 0.0,
		"stop_energy": _stop_spill.light_energy if _stop_spill != null else 0.0,
		"group_emission": _group_energy.duplicate()}


static func _center_in_vehicle(mesh: MeshInstance3D, vehicle: Node3D) -> Vector3:
	return vehicle.to_local(mesh.to_global(mesh.get_aabb().get_center()))


## Only this activity's Environment; no global renderer or shared world settings change.
static func configure_environment(environment: Environment) -> void:
	if environment == null: return
	environment.glow_enabled = true
	environment.glow_intensity = 0.28
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 0.92
	environment.glow_hdr_scale = 0.3
