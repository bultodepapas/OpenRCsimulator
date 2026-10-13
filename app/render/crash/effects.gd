## CR-03a/19a/22a. Bounded, disposable flat-field crash presentation.
## The simulation never reads these particles, marks or fragment transforms.
extends Node3D

const MAX_MARKS := 16
const MAX_SPLINTERS := 160
# CR-03b: surfaces that throw no dust (hard paving, structures); sparks need a metal part sliding fast on one.
const HARD_SURFACES := ["runway", "asphalt", "concrete", "building", "vehicle", "lamp"]
const SPARK_SLIDE_MPS := 10.0
const METAL_GROUPS := ["engine", "propeller"]
# Cut grass and turf, bare soil, and bark. Alpha ramps keep the existing fade shape.
const DUST_COLORS := {
	"grass": [Color(0.30, 0.36, 0.16), Color(0.36, 0.30, 0.18)],
	"soil": [Color(0.38, 0.30, 0.20), Color(0.46, 0.40, 0.30)],
	"bark": [Color(0.24, 0.17, 0.10), Color(0.32, 0.25, 0.17)],
	"leaves": [Color(0.20, 0.32, 0.12), Color(0.28, 0.36, 0.16)],
}
const DEFAULT_DEBRIS := [Color(0.62, 0.40, 0.19)]
## CR-03b: ejecta fall by material: turf clods, soil and bark drop back; leaves drift (m/s², downward).
const EJECTA_FALL := {"grass": 4.0, "soil": 4.0, "bark": 4.0, "leaves": 0.8}
# CR-22b (research.md): burn rates and venting timing are presentation estimates, not measurements.
const KEROSENE_BURN_KG_S := 0.035
const GASOLINE_BURN_KG_S := 0.05
const KEROSENE_FIRE_MAX_S := 50.0
const GASOLINE_FIRE_MAX_S := 40.0
const VENT_DELAY_MAX_S := 30.0
const VENT_DELAY_MIN_S := 5.0
const VENT_DURATION_S := 20.0
const FLARE_S := 3.0
const FLARE_MIN_SEVERITY := 0.8
const CENTRAL_GROUPS := ["fuselage", "engine", "propeller"]
# CR-22d: ignition flash when a fuel fire starts. Roberts (1981) fireball correlations, D = 5.8·M^(1/3) m and
# t = 0.45·M^(1/3) s, applied to an estimated atomised share of the fuel; a minimum duration keeps it perceptible.
const FLASH_ATOMISED_FRACTION := 0.01
const FLASH_MIN_S := 0.35
const FLASH_MAX_RADIUS_M := 1.2
var vent: CPUParticles3D # CR-22b: grey-white smoke from a damaged LiPo pack
var _vent_start_s := INF
var _vent_end_s := INF
var _flare_end_s := -INF
var fireball: CPUParticles3D # CR-22d
var _flash_end_s := -INF
var _flash_s := 0.0
var debris_colors: Array = DEFAULT_DEBRIS.duplicate()
var emitters: Array[CPUParticles3D] = []
var dust: CPUParticles3D
var smoke: CPUParticles3D
var flame: CPUParticles3D
var sparks: CPUParticles3D
var touch_dust: CPUParticles3D # E3d1: small puff for a soft hull contact that continues the flight
var blade_chips: CPUParticles3D # E3d2: fragments of propeller blades after a prop strike
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
	vent = _particles(96, 5.0, puff, false)
	fireball = _particles(12, 0.6, fire_tex, true)
	fireball.one_shot = true
	fireball.explosiveness = 1.0
	fireball.spread = 180.0
	fireball.initial_velocity_min = 0.3
	fireball.initial_velocity_max = 1.2
	fireball.gravity = Vector3(0, 2.0, 0)
	fireball.scale_amount_curve = _curve([Vector2(0,0.4),Vector2(0.3,1.0),Vector2(1,0.2)])
	fireball.color_ramp = _gradient([Color(1,1,0.9,1.0),Color(1,0.85,0.45,1.0),Color(1,0.4,0.08,0.8),Color(0.2,0.06,0.02,0)], [0.0,0.15,0.55,1.0])
	# The flash is light from burning fuel: draw it after the dust thrown at the same instant, not under it.
	((fireball.mesh as QuadMesh).material as StandardMaterial3D).render_priority = 2
	vent.initial_velocity_min = 0.4
	vent.initial_velocity_max = 1.2
	vent.spread = 12.0
	vent.gravity = Vector3(0, 0.5, 0)
	vent.scale_amount_min = 0.15
	vent.scale_amount_max = 0.4
	vent.scale_amount_curve = _curve([Vector2(0,0.4),Vector2(0.5,1.6),Vector2(1,2.6)])
	vent.color_ramp = _gradient([Color(0.85,0.85,0.82,0),Color(0.82,0.82,0.80,0.7),Color(0.70,0.70,0.68,0)], [0.0,0.1,1.0])
	blade_chips = _particles(12, 1.6, null, false)
	blade_chips.one_shot = true
	blade_chips.explosiveness = 1.0
	blade_chips.spread = 55.0
	blade_chips.initial_velocity_min = 3.0
	blade_chips.initial_velocity_max = 9.0
	blade_chips.gravity = Vector3(0, -9.81, 0)
	blade_chips.angular_velocity_min = -720.0
	blade_chips.angular_velocity_max = 720.0
	blade_chips.scale_amount_min = 1.0
	blade_chips.scale_amount_max = 1.0
	var shard := BoxMesh.new()
	shard.size = Vector3(0.012, 0.004, 0.06)
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = Color(0.08, 0.08, 0.08)
	shard_material.roughness = 0.6
	shard.material = shard_material
	blade_chips.mesh = shard
	touch_dust = _particles(24, 1.2, puff, false)
	touch_dust.one_shot = true
	touch_dust.explosiveness = 0.9
	touch_dust.spread = 35.0
	touch_dust.initial_velocity_min = 0.3
	touch_dust.gravity = Vector3(0, -0.8, 0)
	touch_dust.scale_amount_min = 0.08
	touch_dust.scale_amount_max = 0.25
	touch_dust.emission_sphere_radius = 0.05
	touch_dust.color_ramp = dust.color_ramp
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
	var radius := 0.15 + 0.35*power
	var surface := str(severity.get("surface",""))
	var slide := Vector3(velocity.x,0.0,velocity.z)
	_fire_duration = minf(KEROSENE_FIRE_MAX_S, fuel_kg / KEROSENE_BURN_KG_S) if hot_turbine and level >= 3 and fuel_kg > 0.0 and severity.get("tank_ruptured",false) else 0.0
	for p in emitters:
		p.global_position = _origin
		p.visible = true
		p.restart()
	# CR-03b: material-driven ejecta thrown forward along the slide, never a spherical burst.
	var profile := dust_profile(surface)
	dust.direction = (slide.normalized()*0.6 + Vector3.UP*0.8).normalized() if slide.length() > 1.0 else Vector3.UP
	dust.spread = 30.0
	dust.initial_velocity_max = 1.5 + 6.0*power
	dust.emission_sphere_radius = radius
	if not profile.is_empty():
		dust.color_ramp = _gradient([Color(profile[0], 0.0), Color(profile[0], 0.65), Color(profile[1], 0.0)], [0.0, 0.08, 1.0])
		dust.gravity = Vector3(0, -float(EJECTA_FALL.get(_profile_name(profile), 0.6)), 0)
	dust.restart()
	dust.emitting = level > 0 and not profile.is_empty()
	touch_dust.emitting = false
	blade_chips.emitting = false
	vent.emitting = false
	fireball.emitting = false
	vent.gravity = Vector3(0, 0.5, 0) + wind.limit_length(10.0)*0.2
	sparks.restart()
	sparks.emitting = sparks_for(level, surface, str(severity.get("component_group","")), float(severity.get("tangential_speed_mps", 0.0)), hot_turbine)
	flame.emission_sphere_radius = 0.25 + 0.4*power
	flame.emitting = _fire_duration > 0
	smoke.emitting = _fire_duration > 0
	smoke.gravity = Vector3(0,0.35,0) + wind.limit_length(10.0)*0.2
	flame.gravity = Vector3(0,1,0) + wind.limit_length(10.0)*0.08
	light.global_position = _origin + Vector3.UP*0.6
	light.visible = _fire_duration > 0
	if level > 0:
		mark(_origin, velocity, radius, _fire_duration > 0)
	_fragment_count = splinter_count(level, power)
	fragments.multimesh.visible_instance_count = _fragment_count
	for i in _fragment_count:
		_positions[i] = _origin + Vector3(_rng.randf_range(-0.5,0.5),_rng.randf_range(0.15,0.7),_rng.randf_range(-0.5,0.5))
		# CR-03b: chips trail the slide; only a small spread and lift, scaled by severity, separates them.
		_velocities[i] = slide.limit_length(80)*0.25 + Vector3(_rng.randf_range(-1.5,1.5),_rng.randf_range(0.5,3.0),_rng.randf_range(-1.5,1.5))*(0.4 + power)
		_rotations[i] = Vector3(_rng.randf()*TAU,_rng.randf()*TAU,_rng.randf()*TAU)
		_spins[i] = Vector3(_rng.randf_range(-14,14),_rng.randf_range(-14,14),_rng.randf_range(-14,14))
		fragments.multimesh.set_instance_color(i, chip_color(i, hot_turbine))
		fragments.multimesh.set_instance_transform(i,Transform3D(Basis.from_euler(_rotations[i]),_positions[i]))

## CR-03b: dust colours for a ground or obstacle surface, [start, end]; empty = no dust (hard surfaces).
static func dust_profile(surface: String) -> Array:
	var s := surface.to_lower()
	if HARD_SURFACES.has(s):
		return []
	if s == "tree_trunk":
		return DUST_COLORS.bark
	if s == "tree_foliage":
		return DUST_COLORS.leaves
	if s in ["rough", "dirt", "parked_aircraft"]:
		return DUST_COLORS.soil
	return DUST_COLORS.grass


static func _profile_name(profile: Array) -> String:
	for name: String in DUST_COLORS:
		if DUST_COLORS[name] == profile:
			return name
	return ""


## CR-03b: sparks need metal (a hot turbine casing at C3+, or an engine/propeller part) sliding fast on a hard surface.
static func sparks_for(level: int, surface: String, component_group: String, tangential_mps: float, hot_turbine: bool) -> bool:
	if not HARD_SURFACES.has(surface.to_lower()) or level < 2:
		return false
	if hot_turbine and level >= 3:
		return true
	return METAL_GROUPS.has(component_group) and tangential_mps >= SPARK_SLIDE_MPS


## CR-03b: chips from the struck part at C2, a wreck's worth at C3/C4, scaled by severity; none below C2.
static func splinter_count(level: int, power: float) -> int:
	if level < 2:
		return 0
	if level == 2:
		return int(round(8.0 + 8.0 * clampf(power, 0.0, 1.0)))
	return mini(MAX_SPLINTERS, int(round((32 + level * 28) * (0.5 + 0.5 * clampf(power, 0.0, 1.0)))))


## CR-03b: debris takes the airframe's own covering colours (sampled once by the director); empty keeps the default.
func set_debris_colors(colors: Array) -> void:
	debris_colors = colors.duplicate() if not colors.is_empty() else DEFAULT_DEBRIS.duplicate()


## Colour of chip `index`: the airframe palette in turn; a hot turbine adds soot-dark casing pieces.
func chip_color(index: int, hot_turbine: bool) -> Color:
	if hot_turbine and index % 3 == 0:
		return Color(0.18, 0.18, 0.17)
	return debris_colors[index % debris_colors.size()]


func mark(point: Vector3, direction: Vector3, radius: float, burned: bool = false) -> MeshInstance3D:
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
	return item

## E3d1: a soft hull contact that continues the flight: a scuff along the slide and a small puff thrown along it,
## sized by `strength` (0..1). Never a radial burst; the crash aftermath (start) supersedes it.
func touch(point: Vector3, velocity: Vector3, strength: float, surface := "grass") -> void:
	var level := clampf(strength, 0.0, 1.0)
	mark(Vector3(point.x, 0.0, point.z), velocity, 0.06 + 0.22 * level)
	# CR-03b: the same surface rule as crash dust: turf, soil or nothing on paving.
	var profile := dust_profile(surface)
	if profile.is_empty():
		return
	touch_dust.color_ramp = _gradient([Color(profile[0], 0.0), Color(profile[0], 0.6), Color(profile[1], 0.0)], [0.0, 0.1, 1.0])
	var slide := Vector3(velocity.x, 0.0, velocity.z)
	touch_dust.global_position = Vector3(point.x, 0.03, point.z)
	touch_dust.direction = (slide.normalized() * 0.8 + Vector3.UP * 0.6).normalized() if slide.length() > 0.5 else Vector3.UP
	touch_dust.initial_velocity_max = 0.8 + 3.0 * level
	touch_dust.visible = true
	touch_dust.restart()
	touch_dust.emitting = true


## E3d2: the blades of a turning propeller break on the ground: a burst of blade fragments thrown along the slide
## and upward, and a surface puff. The flight continues; the crash aftermath (start) supersedes it.
func prop_break(point: Vector3, velocity: Vector3, surface := "grass") -> void:
	touch(point, velocity, 0.6, surface)
	var slide := Vector3(velocity.x, 0.0, velocity.z)
	blade_chips.global_position = Vector3(point.x, maxf(point.y, 0.03), point.z)
	blade_chips.direction = (slide.normalized() * 0.5 + Vector3.UP).normalized() if slide.length() > 0.5 else Vector3.UP
	blade_chips.visible = true
	blade_chips.restart()
	blade_chips.emitting = true


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
	var venting := _age >= _vent_start_s and _age < _vent_end_s
	vent.emitting = venting
	var flaring := _age >= _vent_start_s and _age < _flare_end_s
	if flaring:
		burning = maxf(burning, 1.0)
	flame.emitting = burning > 0
	smoke.emitting = burning > 0
	light.visible = burning > 0
	light.light_energy = burning*(1.7+0.35*sin(_age*19.0)+0.25*sin(_age*31.0))
	var flash := flash_strength()
	if flash > 0.0:
		light.visible = true
		light.light_energy = maxf(light.light_energy, 8.0 * flash)
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

## CR-22d: 1 at ignition, fading to 0 over the flash duration; 0 when no flash.
func flash_strength() -> float:
	if not _active or _flash_s <= 0.0 or _age >= _flash_end_s:
		return 0.0
	return clampf((_flash_end_s - _age) / _flash_s, 0.0, 1.0)


func fire_strength() -> float:
	if not _active:
		return 0.0
	var flare := 1.0 if _age >= _vent_start_s and _age < _flare_end_s else 0.0
	return maxf(clampf((_fire_duration-_age)/3.0,0,1), flare)


## CR-22b: what each tagged energy source does in this crash (research.md). Pure. sources: {kind: kg};
## report: the director's crash report (class, severity, component_group, tank_ruptured).
## Returns {fire_kind, fire_s, stain, vent_delay_s (−1 = none), vent_s, flare}.
static func energy_outcome(sources: Dictionary, report: Dictionary, engine_running: bool, hot_turbine: bool) -> Dictionary:
	var level := clampi(int(report.get("class", 0)), 0, 4)
	var severity := clampf(float(report.get("severity", 0.0)), 0.0, 1.0)
	var central := CENTRAL_GROUPS.has(str(report.get("component_group", "")))
	var ruptured := bool(report.get("tank_ruptured", false))
	var out := {fire_kind = "", fire_s = 0.0, stain = false, vent_delay_s = -1.0, vent_s = 0.0, flare = false,
		flash = false, flash_radius_m = 0.0, flash_s = 0.0}
	var kerosene := float(sources.get("kerosene", 0.0))
	var gasoline := float(sources.get("gasoline", 0.0))
	var glow := float(sources.get("glow_fuel", 0.0))
	var lipo := float(sources.get("lipo", 0.0))
	if kerosene > 0.0 and hot_turbine and ruptured and level >= 3:
		out.fire_kind = "kerosene"
		out.fire_s = minf(KEROSENE_FIRE_MAX_S, kerosene / KEROSENE_BURN_KG_S)
	elif gasoline > 0.0 and engine_running and level == 4 and central:
		out.fire_kind = "gasoline"
		out.fire_s = minf(GASOLINE_FIRE_MAX_S, gasoline / GASOLINE_BURN_KG_S)
	if not out.fire_kind.is_empty():
		# A fuel fire starts with a short flash of the atomised fuel; glow and LiPo never flash (research.md).
		var atomised := FLASH_ATOMISED_FRACTION * (kerosene if out.fire_kind == "kerosene" else gasoline)
		var cube := pow(atomised, 1.0 / 3.0)
		out.flash = true
		out.flash_radius_m = minf(0.5 * 5.8 * cube, FLASH_MAX_RADIUS_M)
		out.flash_s = maxf(0.45 * cube, FLASH_MIN_S)
	if (glow > 0.0 or gasoline > 0.0 or kerosene > 0.0) and ruptured and out.fire_kind.is_empty():
		out.stain = true # methanol burns nearly invisibly; a spill shows as a dark wet stain
	if lipo > 0.0 and level >= 3 and central:
		out.vent_delay_s = lerpf(VENT_DELAY_MAX_S, VENT_DELAY_MIN_S, severity)
		out.vent_s = VENT_DURATION_S
		out.flare = level == 4 and severity >= FLARE_MIN_SEVERITY
	return out


## CR-22b: applies the non-kerosene outcomes (kerosene fire stays in start()): gasoline fire, fuel stain, LiPo venting.
func apply_energy(outcome: Dictionary) -> void:
	if not _active:
		return
	if bool(outcome.get("flash", false)):
		var radius := float(outcome.flash_radius_m)
		_flash_s = float(outcome.flash_s)
		_flash_end_s = _age + _flash_s
		fireball.global_position = _origin + Vector3.UP * radius * 0.6
		fireball.emission_sphere_radius = radius * 0.5
		fireball.scale_amount_min = radius * 1.8
		fireball.scale_amount_max = radius * 2.8
		fireball.lifetime = _flash_s + 0.25
		fireball.visible = true
		fireball.restart()
		fireball.emitting = true
		light.visible = true
	if str(outcome.get("fire_kind", "")) == "gasoline":
		_fire_duration = float(outcome.fire_s)
		light.visible = true
	if bool(outcome.get("stain", false)):
		var stain := mark(_origin, Vector3.ZERO, 0.7)
		(stain.material_override as StandardMaterial3D).albedo_color = Color(0.05, 0.05, 0.04, 0.55)
	if float(outcome.get("vent_delay_s", -1.0)) >= 0.0:
		_vent_start_s = float(outcome.vent_delay_s)
		_vent_end_s = _vent_start_s + float(outcome.vent_s)
		_flare_end_s = _vent_start_s + FLARE_S if bool(outcome.get("flare", false)) else -INF
		vent.global_position = _origin + Vector3.UP * 0.1

func reset() -> void:
	_active = false
	_paused = false
	_age = 0
	_fire_duration = 0
	_vent_start_s = INF
	_vent_end_s = INF
	_flare_end_s = -INF
	_flash_end_s = -INF
	_flash_s = 0.0
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
	return {particles=emitters.reduce(func(total: int, p: CPUParticles3D) -> int: return total + p.amount, 0), splinters=_fragment_count, marks=mini(_mark_index,MAX_MARKS), fire=fire_strength(), update_usec=last_update_usec}
