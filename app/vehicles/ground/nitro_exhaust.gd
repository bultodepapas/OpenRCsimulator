## Bounded cosmetic exhaust. Observes accepted nitro telemetry; never drives physics.
extends CPUParticles3D

const SMOKE_TEXTURE: Texture2D = preload("res://assets/crash/smoke.png")

func _init() -> void:
	name = "NitroExhaust"
	amount = 32
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

func observe(snapshot: Dictionary, paused: bool) -> void:
	var engine: Dictionary = snapshot.get("nitro", {})
	var rpm := float(engine.get("engine_rpm", 0.0))
	var fuel := float(engine.get("fuel_kg", 0.0))
	speed_scale = 0.0 if paused else 1.0
	emitting = not paused and is_finite(rpm) and rpm > 500.0 and is_finite(fuel) and fuel > 0.0
	if emitting:
		var load := clampf(rpm / 36000.0, 0.0, 1.0)
		initial_velocity_max = lerpf(0.5, 1.5, load)
		color.a = lerpf(0.12, 0.28, load)
