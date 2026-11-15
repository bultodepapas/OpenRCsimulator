extends Node3D
## View-only scaffold. Parent this node to a validated nozzle marker.
## Local origin is the nozzle exit; local +Z points rearward.
## Values come from an accepted/interpolated simulation snapshot, never raw input.

const PLUME_SHADER = preload("res://visual/afterburner_plume.gdshader")
const MIN_RADIUS_M := 0.005
const MAX_RADIUS_M := 1.0
const MIN_LENGTH_M := 0.02
const MAX_LENGTH_M := 8.0

@export_range(0.005, 1.0, 0.001) var nozzle_radius_m: float = 0.036
@export_range(0.02, 8.0, 0.01) var max_length_m: float = 0.42
@export_range(0.0, 4.0, 0.01) var brightness: float = 1.0
@export_range(0.0, 1.0, 0.01) var shock_strength: float = 0.25
@export var phase: float = 0.0

var burner_actual: float = 0.0
var accepted_sim_time_s: float = 0.0
var _layers: Array[MeshInstance3D] = []


func _ready() -> void:
	_ensure_geometry()
	set_snapshot(burner_actual, accepted_sim_time_s)


func _ensure_geometry() -> void:
	if not _layers.is_empty():
		return
	nozzle_radius_m = clampf(nozzle_radius_m, MIN_RADIUS_M, MAX_RADIUS_M) if is_finite(nozzle_radius_m) else 0.036
	max_length_m = clampf(max_length_m, MIN_LENGTH_M, MAX_LENGTH_M) if is_finite(max_length_m) else 0.42
	for index in 2:
		var mesh := CylinderMesh.new()
		mesh.height = 1.0
		mesh.bottom_radius = 1.0
		mesh.top_radius = 0.0
		mesh.radial_segments = 24
		mesh.rings = 12
		mesh.cap_bottom = index == 1
		mesh.cap_top = false
		var layer := MeshInstance3D.new()
		layer.name = "OuterPlume" if index == 0 else "InnerCore"
		layer.mesh = mesh
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Shader deformation cannot extend outside this finite, nozzle-local box.
		var radius := nozzle_radius_m * 1.10
		layer.custom_aabb = AABB(Vector3(-radius, -radius, -0.001), Vector3(radius * 2.0, radius * 2.0, max_length_m + 0.002))
		var material := ShaderMaterial.new()
		material.shader = PLUME_SHADER
		material.set_shader_parameter("core_layer", float(index))
		material.set_shader_parameter("nozzle_radius_m", nozzle_radius_m)
		material.set_shader_parameter("max_length_m", max_length_m)
		# Each layer owns a separate material; another engine cannot change this one.
		layer.material_override = material
		add_child(layer)
		_layers.append(layer)


func set_snapshot(actual: float, sim_time_s: float) -> void:
	_ensure_geometry()
	# Fail closed for invalid presentation data; do not feed this decision to physics.
	if not is_finite(actual) or not is_finite(sim_time_s):
		actual = 0.0
		sim_time_s = 0.0
	burner_actual = clampf(actual, 0.0, 1.0)
	accepted_sim_time_s = maxf(sim_time_s, 0.0)
	visible = burner_actual > 0.0001
	var safe_brightness := clampf(brightness, 0.0, 4.0) if is_finite(brightness) else 1.0
	var safe_shock := clampf(shock_strength, 0.0, 1.0) if is_finite(shock_strength) else 0.0
	var safe_phase := fposmod(phase, TAU) if is_finite(phase) else 0.0
	var animation_phase := phase_for_time(accepted_sim_time_s)
	for layer: MeshInstance3D in _layers:
		var material := layer.material_override as ShaderMaterial
		material.set_shader_parameter("burner_actual", burner_actual)
		material.set_shader_parameter("animation_phase_rad", animation_phase)
		material.set_shader_parameter("brightness", safe_brightness)
		material.set_shader_parameter("shock_strength", safe_shock)
		material.set_shader_parameter("phase", safe_phase)


static func phase_for_time(sim_time_s: float) -> Vector4:
	if not is_finite(sim_time_s):
		return Vector4.ZERO
	# All four oscillators repeat at 1024 seconds, matching the production shared
	# clock period without a visible seam. Reduction precedes multiplication, so
	# a very large finite timestamp cannot overflow. Rendering only: float64 time
	# is converted to bounded float32 phase values at this view boundary.
	var cycle := fposmod(maxf(sim_time_s, 0.0), 1024.0) / 1024.0
	return Vector4(
		fposmod(cycle * 2119.0, 1.0) * TAU,
		fposmod(cycle * 1141.0, 1.0) * TAU,
		fposmod(cycle * 3097.0, 1.0) * TAU,
		fposmod(cycle * 5052.0, 1.0) * TAU)


func clear() -> void:
	set_snapshot(0.0, 0.0)
