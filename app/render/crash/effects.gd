## CR-03a/19a/22a. Bounded, disposable flat-field crash presentation.
## The simulation never reads these particles, marks or fragment transforms.
extends Node3D

const MAX_MARKS := 16
const MAX_SPLINTERS := 160
var emitters: Array[CPUParticles3D] = []
var dust: CPUParticles3D
var smoke: CPUParticles3D
var flame: CPUParticles3D
var sparks: CPUParticles3D
var light: OmniLight3D
var marks: Array[MeshInstance3D] = []
var fragments: MultiMeshInstance3D
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _rotations := PackedVector3Array()
var _spins := PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _age := 0.0
var _fire_duration := 0.0
var _active := false
var _paused := false
var _mark_index := 0
var _fragment_count := 0
var _origin := Vector3.ZERO
var last_update_usec := 0

func prepare() -> void:
	if not emitters.is_empty():
		return
	_rng.seed = 220031
	var puff: Texture2D = load("res://assets/crash/smoke.png")
	var fire_tex: Texture2D = load("res://assets/crash/flame.png")
	dust = _particles(160, 2.2, puff, false)
	dust.one_shot = true
	dust.explosiveness = 0.94
	dust.spread = 82.0
	dust.initial_velocity_min = 1.5
	dust.initial_velocity_max = 6.0
	dust.gravity = Vector3(0, -0.6, 0)
	dust.scale_amount_min = 0.15
	dust.scale_amount_max = 0.55
	dust.color_ramp = _gradient([Color(0.36,0.28,0.17,0), Color(0.38,0.30,0.20,0.65), Color(0.46,0.40,0.30,0)], [0.0,0.08,1.0])
	smoke = _particles(180, 6.0, puff, false)
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.4
	smoke.spread = 15.0
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.scale_amount_min = 0.3
	smoke.scale_amount_max = 0.8
	smoke.scale_amount_curve = _curve([Vector2(0,0.35),Vector2(0.5,1.9),Vector2(1,3.2)])
	smoke.color_ramp = _gradient([Color(0.09,0.075,0.06,0),Color(0.11,0.10,0.09,0.9),Color(0.22,0.21,0.20,0.7),Color(0.3,0.29,0.28,0)], [0.0,0.04,0.45,1.0])
	flame = _particles(120, 0.85, fire_tex, true)
	flame.initial_velocity_min = 1.2
	flame.initial_velocity_max = 3.4
	flame.spread = 18.0
	flame.gravity = Vector3(0, 1.0, 0)
	flame.scale_amount_min = 0.28
	flame.scale_amount_max = 0.7
	flame.scale_amount_curve = _curve([Vector2(0,0.5),Vector2(0.22,1),Vector2(1,0.05)])
	flame.color_ramp = _gradient([Color(1,0.92,0.62,0),Color(1,0.7,0.22,0.95),Color(1,0.18,0.025,0.65),Color(0.2,0.025,0.01,0)], [0.0,0.08,0.55,1.0])
	sparks = _particles(96, 0.65, null, true)
	sparks.one_shot = true
	sparks.explosiveness = 0.98
	sparks.spread = 78.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 12.0
	sparks.gravity = Vector3(0, -9.81, 0)
	sparks.scale_amount_min = 0.015
	sparks.scale_amount_max = 0.035
	sparks.color_ramp = _gradient([Color(1,0.95,0.7,1),Color(1,0.22,0.025,0)], [0.0,1.0])
	light = OmniLight3D.new()
	light.light_color = Color(1,0.28,0.05)
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	_build_marks()
	_build_splinters()
	reset()

func _particles(count: int, lifetime_s: float, texture: Texture2D, hot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = count
	p.lifetime = lifetime_s
	p.local_coords = false
	# Alpha particle cards must not cast opaque quad silhouettes on the field.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.angular_velocity_min = -35.0
	p.angular_velocity_max = 35.0
	p.use_fixed_seed = true
	p.seed = 6300 + emitters.size()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if hot:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material
	p.mesh = mesh
	add_child(p)
	emitters.append(p)
	return p

func _gradient(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	return g

func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.max_value = 4
	for point: Vector2 in points:
		curve.add_point(point)
	return curve

func _build_marks() -> void:
	for i in MAX_MARKS:
		var mark := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * 2
		mark.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = load("res://assets/crash/smoke.png")
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mark.material_override = mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visible = false
		add_child(mark)
		marks.append(mark)

func _build_splinters() -> void:
	fragments = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.018,0.008,0.11)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	box.material = mat
	mm.mesh = box
	mm.instance_count = MAX_SPLINTERS
	mm.visible_instance_count = 0
	fragments.multimesh = mm
	fragments.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fragments)
	_positions.resize(MAX_SPLINTERS)
	_velocities.resize(MAX_SPLINTERS)
	_rotations.resize(MAX_SPLINTERS)
	_spins.resize(MAX_SPLINTERS)

func start(point: Vector3, velocity: Vector3, severity: Dictionary, fuel_kg: float, hot_turbine: bool, wind: Vector3) -> void:
	reset()
	_active = true
	_origin = point
	_origin.y = 0.04
	var level := clampi(int(severity.get("class",0)),0,4)
	var power := clampf(float(severity.get("severity",0.0)),0.0,1.0)
	var radius := 0.2 + 1.0*power
	_fire_duration = minf(50.0, fuel_kg / 0.035) if hot_turbine and level >= 3 and fuel_kg > 0.0 and severity.get("tank_ruptured",false) else 0.0
	for p in emitters:
		p.global_position = _origin
		p.visible = true
		p.restart()
	dust.initial_velocity_max = 2.0 + 8.0*power
	dust.emission_sphere_radius = radius
	dust.restart()
	dust.emitting = level > 0
	sparks.restart()
	sparks.emitting = level >= 3 and (hot_turbine or severity.get("surface","") in ["runway","asphalt","concrete"])
	flame.emission_sphere_radius = 0.25 + 0.4*power
	flame.emitting = _fire_duration > 0
	smoke.emitting = _fire_duration > 0
	smoke.gravity = Vector3(0,0.35,0) + wind.limit_length(10.0)*0.2
	flame.gravity = Vector3(0,1,0) + wind.limit_length(10.0)*0.08
	light.global_position = _origin + Vector3.UP*0.6
	light.visible = _fire_duration > 0
	if level > 0:
		mark(_origin, velocity, radius, _fire_duration > 0)
	_fragment_count = 0 if level < 3 else mini(MAX_SPLINTERS, 32 + level*28)
	fragments.multimesh.visible_instance_count = _fragment_count
	for i in _fragment_count:
		_positions[i] = _origin + Vector3(_rng.randf_range(-0.5,0.5),_rng.randf_range(0.15,0.7),_rng.randf_range(-0.5,0.5))
		_velocities[i] = velocity.limit_length(80)*0.18 + Vector3(_rng.randf_range(-4,4),_rng.randf_range(2,8),_rng.randf_range(-4,4))*power
		_rotations[i] = Vector3(_rng.randf()*TAU,_rng.randf()*TAU,_rng.randf()*TAU)
		_spins[i] = Vector3(_rng.randf_range(-14,14),_rng.randf_range(-14,14),_rng.randf_range(-14,14))
		fragments.multimesh.set_instance_color(i, Color(0.18,0.18,0.17) if hot_turbine else Color(0.62,0.40,0.19))
		fragments.multimesh.set_instance_transform(i,Transform3D(Basis.from_euler(_rotations[i]),_positions[i]))

func mark(point: Vector3, direction: Vector3, radius: float, burned: bool = false) -> void:
	# Reserve the primary gouge/scorch for the lifetime of this aftermath.
	var slot := 0 if _mark_index == 0 else 1+((_mark_index-1) % (MAX_MARKS-1))
	var item := marks[slot]
	_mark_index += 1
	item.position = Vector3(point.x,0.012 + float(_mark_index % MAX_MARKS)*0.0002,point.z)
	item.rotation.y = atan2(direction.x,direction.z)
	# Vertical impact speed must not elongate a horizontal ground scuff.
	var slide_speed := Vector2(direction.x,direction.z).length()
	item.scale = Vector3(clampf(radius*0.8,0.12,1.4),1,clampf(radius+slide_speed*0.035,0.2,2.5))
	(item.material_override as StandardMaterial3D).albedo_color = Color(0.035,0.029,0.025,0.88) if burned else Color(0.12,0.075,0.025,0.78)
	item.visible = true

func secondary(point: Vector3, strength: float) -> void:
	if not _active or _paused or strength < 0.3:
		return
	mark(point,Vector3.ZERO,0.12+clampf(strength,0,1)*0.3)

func update(delta: float, paused: bool) -> void:
	var began := Time.get_ticks_usec()
	_paused = paused
	for p in emitters:
		p.speed_scale = 0.0 if paused else 1.0
	if not _active or paused:
		last_update_usec = Time.get_ticks_usec()-began
		return
	var dt := clampf(delta,0,0.05)
	_age += dt
	var burning := fire_strength()
	flame.emitting = burning > 0
	smoke.emitting = burning > 0
	light.visible = burning > 0
	light.light_energy = burning*(1.7+0.35*sin(_age*19.0)+0.25*sin(_age*31.0))
	if _age < 12.0:
		for i in _fragment_count:
			if _velocities[i].length_squared() < 0.002 and _positions[i].y <= 0.015:
				continue
			_velocities[i] += Vector3.DOWN*9.81*dt
			_velocities[i] *= exp(-dt*0.65)
			_positions[i] += _velocities[i]*dt
			_rotations[i] += _spins[i]*dt
			if _positions[i].y < 0.012:
				_positions[i].y = 0.012
				_velocities[i].y = absf(_velocities[i].y)*0.2
				_velocities[i].x *= 0.55
				_velocities[i].z *= 0.55
				_spins[i] *= 0.35
				if _velocities[i].length_squared() < 0.12:
					_velocities[i] = Vector3.ZERO
			fragments.multimesh.set_instance_transform(i,Transform3D(Basis.from_euler(_rotations[i]),_positions[i]))
	last_update_usec = Time.get_ticks_usec()-began

func fire_strength() -> float:
	return clampf((_fire_duration-_age)/3.0,0,1) if _active else 0.0

func reset() -> void:
	_active = false
	_paused = false
	_age = 0
	_fire_duration = 0
	_mark_index = 0
	_fragment_count = 0
	_rng.seed = 220031
	for p in emitters:
		p.emitting = false
		p.visible = false
		p.speed_scale = 1
	for item in marks:
		item.visible = false
	if fragments != null:
		fragments.multimesh.visible_instance_count = 0
	if light != null:
		light.visible = false

func stats() -> Dictionary:
	return {particles=556, splinters=_fragment_count, marks=mini(_mark_index,MAX_MARKS), fire=fire_strength(), update_usec=last_update_usec}
