## Bounded cosmetic exhaust. Observes accepted nitro telemetry; never drives physics.
extends CPUParticles3D

const SMOKE_TEXTURE: Texture2D = preload("res://assets/crash/smoke.png")
const PEAK_FUEL_FLOW_KG_PER_S := 0.0012

var _display_load := 0.0
var _paused := false

func _init() -> void:
	name = "NitroExhaust"
	amount = 32
	fixed_fps = 60
	fract_delta = true
	lifetime = 0.65
	lifetime_randomness = 0.25
	local_coords = false
	emitting = false
	spread = 18.0
	direction = Vector3(1.0, 0.1, 0.15)
	gravity = Vector3(0.0, 0.14, 0.0)
	initial_velocity_min = 0.35
	initial_velocity_max = 0.8
	scale_amount_min = 0.12
	scale_amount_max = 0.4
	color = Color(0.79, 0.86, 0.96, 0.22)
	visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = SMOKE_TEXTURE
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	quad.material = material
	mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.65))
	fade.set_color(1, Color(1, 1, 1, 0))
	color_ramp = fade

func observe(snapshot: Dictionary, paused: bool, simulation_delta: float = 0.0) -> void:
	_paused = paused
	if paused:
		emitting = false
		speed_scale = 0.0
		return
	speed_scale = 1.0
	var engine_value: Variant = snapshot.get("nitro", {})
	if typeof(engine_value) != TYPE_DICTIONARY:
		emitting = false
		return
	var engine: Dictionary = engine_value
	var rpm := _read_nonnegative(engine.get("engine_rpm", 0.0))
	var fuel := _read_nonnegative(engine.get("fuel_kg", 0.0))
	var flow_key_present := engine.has("fuel_flow_kg_per_s")
	var has_flow := flow_key_present and _is_nonnegative_number(engine.get("fuel_flow_kg_per_s"))
	if flow_key_present and not has_flow:
		emitting = false
		return
	var has_throttle := engine.has("throttle_fraction") and _is_finite_number(engine.get("throttle_fraction"))
	var has_slip := engine.has("clutch_slip") and _is_finite_number(engine.get("clutch_slip"))
	var flow := _read_nonnegative(engine.get("fuel_flow_kg_per_s", 0.0))
	var throttle := clampf(float(engine.get("throttle_fraction", 0.0)), 0.0, 1.0) if has_throttle else 0.0
	var clutch_slip := clampf(float(engine.get("clutch_slip", 0.0)), 0.0, 1.0) if has_slip else 0.0
	var rpm_load := clampf((rpm - 700.0) / 24000.0, 0.0, 1.0)
	var load: float
	if has_flow:
		var flow_load := clampf(flow / PEAK_FUEL_FLOW_KG_PER_S, 0.0, 1.0)
		load = clampf(flow_load * 0.48 + throttle * 0.25 + clutch_slip * 0.15 + rpm_load * 0.12, 0.0, 1.0)
		emitting = rpm > 500.0 and fuel > 0.0 and flow > 0.000002
	else:
		# Older snapshots lack the new accepted load metrics; retain the former RPM/fuel gate.
		load = rpm_load
		emitting = rpm > 500.0 and fuel > 0.0
	var dt := clampf(simulation_delta, 0.0, 0.1) if is_finite(simulation_delta) else 0.0
	if dt > 0.0:
		_display_load = move_toward(_display_load, load, minf(1.0, dt * 8.0))
	else:
		_display_load = load
	initial_velocity_min = lerpf(0.2, 0.55, _display_load)
	initial_velocity_max = lerpf(0.48, 1.75, _display_load)
	scale_amount_min = lerpf(0.09, 0.18, _display_load)
	scale_amount_max = lerpf(0.26, 0.78, _display_load)
	color = Color(0.79, 0.86, 0.96, lerpf(0.035, 0.30, _display_load))


func diagnostic_snapshot() -> Dictionary:
	return {
		"emitting": emitting,
		"paused": _paused,
		"speed_scale": speed_scale,
		"display_load": _display_load,
		"particle_budget": amount,
		"fuel_flow_reference_kg_per_s": PEAK_FUEL_FLOW_KG_PER_S,
	}


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_nonnegative_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) >= 0.0


static func _read_nonnegative(value: Variant) -> float:
	return float(value) if _is_nonnegative_number(value) else 0.0
