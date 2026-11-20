## DR-19d (docs/plans/drone-racing.md §18): the FPV quad's crash presentation. Reuses the project's crash kit: the
## synthetic MIT crash sounds (render/crash/crash_audio.gd) and the dust, blade-chip, mark and debris effects
## (render/crash/effects.gd), scaled for a 0.6 kg quad. Presentation only: it reads accepted impact, prop-damage and
## crash events and never writes simulation state. Nothing is allocated before the first event or the activity's
## warm-up (warm()), and the kit stays disabled while effects or sound are off. Grinding props report damage every tick; sounds and effects are
## paced (one per prop per band, one touch per TOUCH_INTERVAL_S) so a scrape is a scrape, not a machine gun.
extends Node3D

const Effects := preload("res://render/crash/effects.gd")
const CrashAudio := preload("res://render/crash/crash_audio.gd")
const Frames := preload("res://render/frames.gd")

## Shortest interval (s) between two touch sounds or dust puffs.
const TOUCH_INTERVAL_S := 0.12
## A prop's damage band for pacing: intact, damaged, badly damaged, broken.
const BAND_LIMITS := [1.0, 0.75, 0.0]
## Impact speed (m/s along the normal) that maps to a full-strength touch, and the curve exponent. Measured against
## the motor loop at hover (max 50 ms RMS, FPV listener; docs/plans/drone-racing.md §19.3): a 3 m/s touchdown sits
## about 10 dB under the motors, 6 m/s about 5 dB under, and 12 m/s level with them (a linear map left everything
## under 5 m/s buried 10 to 20 dB under the motors).
const FULL_TOUCH_SPEED_MPS := 12.0
const TOUCH_EXPONENT := 0.6
## DR-19f: sliding speed (m/s) of a full-strength scrape (a graze or skid) and the shortest interval (s) between two
## scrape grains. Strength sqrt(v / 15): a 2 m/s scrape sits about 11 dB under the motors, 15 m/s about 5 dB under.
const FULL_SCRAPE_SPEED_MPS := 15.0
const SCRAPE_INTERVAL_S := 0.15
## Strength of the blade-chip tick of a damaged (not yet broken) prop: about 8 dB under the motors.
const CHIP_STRENGTH := 0.7
## The kit's voices take the motor loop's distance law (unit size and range of the quad's motor player), so the crash
## to motor balance is the same in FPV and from a ground view; the shared kit's 20 m unit suits a full-size airframe.
const VOICE_UNIT_SIZE_M := 2.0
const VOICE_MAX_DISTANCE_M := 150.0
## Terminal crash speed (m/s) that maps to the top of the shared outcome ladder.
const FULL_CRASH_SPEED_MPS := 20.0

var enable_audio := true
var enable_effects := true
var effects: Node3D
var audio: Node3D
## Rotor index -> last presented damage band (pacing).
var _bands: Dictionary = {}
var _touch_cooldown := 0.0
var _scrape_cooldown := 0.0
var _crashed := false
## Optional ground sampler (render x, z) -> render height; flat 0 when unset.
var ground_height: Callable = Callable()


func _ensure() -> void:
	if enable_effects and effects == null:
		effects = Effects.new()
		effects.name = "QuadImpactEffects"
		add_child(effects)
		effects.prepare()
		effects.set_debris_colors([Color(0.03, 0.03, 0.035), Color(0.12, 0.13, 0.14), Color(0.9, 0.25, 0.05), Color(0.8, 0.82, 0.85)])
		# A 5-inch quad throws a small puff and tiny carbon and prop chips.
		effects.dust.amount = 32
		effects.dust.lifetime = 1.1
		effects.dust.scale_amount_min = 0.04
		effects.dust.scale_amount_max = 0.12
		effects.dust.initial_velocity_min = 0.25
		(effects.fragments.multimesh.mesh as BoxMesh).size = Vector3(0.006, 0.002, 0.025)
	if enable_audio and audio == null:
		audio = CrashAudio.new()
		audio.name = "QuadImpactAudio"
		add_child(audio)
		audio.setup()
		for voice in audio.get_children():
			if voice is AudioStreamPlayer3D:
				voice.unit_size = VOICE_UNIT_SIZE_M
				voice.max_distance = VOICE_MAX_DISTANCE_M


## Audit: build the enabled parts of the kit now (the activity calls it while loading). The first allocation costs
## about 20 ms (particles, synthesized voices), a visible hitch on the first touch if paid mid-flight. Disabled parts
## stay unallocated.
func warm() -> void:
	_ensure()


## A survivable impact event ({surface, normal_speed_mps, point_ned}); `velocity` is the quad's render velocity.
func impact(event: Dictionary, velocity: Vector3) -> void:
	if _crashed or _touch_cooldown > 0.0:
		return
	_ensure()
	_touch_cooldown = TOUCH_INTERVAL_S
	var point := _render_point(event)
	var strength := touch_strength(float(event.get("normal_speed_mps", 0.0)))
	var on_ground := str(event.get("surface", "")) == "ground"
	var sliding := float(event.get("slip_speed_mps", Vector2(velocity.x, velocity.z).length())) > 2.0
	if audio != null:
		audio.touch(point, strength, sliding, "grass" if on_ground else "hard")
	if effects != null and on_ground:
		_at_ground(point, func(local: Vector3) -> void: effects.touch(local, velocity, strength, "grass"))


## DR-19f: a sliding contact ({surface, slip_speed_mps, point_ned}), a graze along an obstacle or a skid on the
## ground: a paced scrape grain, and a little dust on the ground.
func scrape(event: Dictionary, velocity: Vector3) -> void:
	if _crashed or _scrape_cooldown > 0.0:
		return
	_ensure()
	_scrape_cooldown = SCRAPE_INTERVAL_S
	var point := _render_point(event)
	var strength := scrape_strength(float(event.get("slip_speed_mps", 0.0)))
	var on_ground := str(event.get("surface", "")) == "ground"
	if audio != null:
		audio.touch(point, strength, true, "grass" if on_ground else "hard")
	if effects != null and on_ground:
		_at_ground(point, func(local: Vector3) -> void: effects.touch(local, velocity, 0.6 * strength, "grass"))


## Scrape strength [0.1, 1] of a sliding speed (m/s).
static func scrape_strength(slip_mps: float) -> float:
	return clampf(sqrt(maxf(slip_mps, 0.0) / FULL_SCRAPE_SPEED_MPS), 0.1, 1.0)


## A prop-damage event ({rotor, health, point_ned}): sound and blade chips once per damage band of that prop.
func prop_damage(event: Dictionary, velocity: Vector3) -> void:
	if _crashed:
		return
	var rotor := int(event.get("rotor", -1))
	var band := band_of(float(event.get("health", 1.0)))
	if band <= int(_bands.get(rotor, 0)):
		return
	_bands[rotor] = band
	_ensure()
	var point := _render_point(event)
	if audio != null:
		if band >= BAND_LIMITS.size():
			audio.prop_strike(point)
		else:
			audio.touch(point, CHIP_STRENGTH, true, "hard")
	if effects != null and band >= 2:
		_at_ground(point, func(local: Vector3) -> void: effects.prop_break(local, velocity, "grass"))


## The terminal crash: the shared impact ladder and debris, by impact speed (m/s), at the quad's render position.
func crash(reason: String, position: Vector3, velocity: Vector3) -> void:
	if _crashed:
		return
	_crashed = true
	_ensure()
	var speed := velocity.length()
	var power := clampf(speed / FULL_CRASH_SPEED_MPS, 0.0, 1.0)
	var outcome_class := 2 if reason == "Propeller strike" else (3 if power > 0.45 else 2)
	var severity := {"valid": true, "class": outcome_class, "severity": power,
		"surface": "hard" if reason == "Obstacle strike" else "grass",
		"component_group": "propeller" if reason == "Propeller strike" else "airframe"}
	if audio != null:
		audio.impact(position, severity, false)
	if effects != null and reason != "Obstacle strike":
		var start_debris := func(local: Vector3) -> void:
			effects.start(local, velocity, severity, 0.0, false, Vector3.ZERO)
			effects._fragment_count = mini(effects._fragment_count, 24)
			effects.fragments.multimesh.visible_instance_count = effects._fragment_count
		_at_ground(position, start_debris)


func update(delta: float, paused: bool) -> void:
	_touch_cooldown = maxf(0.0, _touch_cooldown - (0.0 if paused else delta))
	_scrape_cooldown = maxf(0.0, _scrape_cooldown - (0.0 if paused else delta))
	if effects != null:
		effects.update(delta, paused)
	if audio != null:
		audio.update(delta, paused, 0.0)


## A pad restart: no damage presented, no running effect or sound.
func reset() -> void:
	_bands.clear()
	_touch_cooldown = 0.0
	_scrape_cooldown = 0.0
	_crashed = false
	if effects != null:
		effects.reset()
	if audio != null:
		audio.reset()


## Damage band of a prop health (0 intact, 1 damaged, 2 badly damaged, 3 broken).
## Touch strength [0.05, 1] of an impact speed (m/s along the normal).
static func touch_strength(speed_mps: float) -> float:
	return clampf(pow(maxf(speed_mps, 0.0) / FULL_TOUCH_SPEED_MPS, TOUCH_EXPONENT), 0.05, 1.0)


static func band_of(health: float) -> int:
	if health <= 0.0:
		return 3
	for i in BAND_LIMITS.size():
		if health >= float(BAND_LIMITS[i]):
			return i
	return BAND_LIMITS.size() - 1


func _render_point(event: Dictionary) -> Vector3:
	var point: Variant = event.get("point_ned")
	if typeof(point) == TYPE_PACKED_FLOAT64_ARRAY and (point as PackedFloat64Array).size() == 3:
		return Frames.ned_to_render(point)
	return global_position


## The shared effects assume their ground at y = 0: run `call` in a frame lifted to the local ground height, then lift
## the emitters (which the kit places in global coordinates) by the same height. Audit: the marks already on the
## ground are children of the lifted frame; they are lowered by the same step so they stay where they were drawn
## (on rolling terrain they used to jump to each new touch's height). Likewise only the emitters this event places
## are lifted: one still running from an earlier event keeps its place in the world (it used to be lifted again by
## every later event and dragged by the frame).
func _at_ground(point: Vector3, call: Callable) -> void:
	var height := float(ground_height.call(point.x, point.z)) if ground_height.is_valid() else 0.0
	var emitters: Array[CPUParticles3D] = effects.emitters
	var before: Array[Vector3] = []
	for emitter: CPUParticles3D in emitters:
		before.append(emitter.global_position)
	var step := height - effects.position.y
	if step != 0.0:
		for item: MeshInstance3D in effects.marks:
			item.position.y -= step
		for decal: Decal in effects.mark_decals:
			decal.position.y -= step
	effects.position = Vector3(0.0, height, 0.0)
	for i in emitters.size():
		emitters[i].global_position = before[i]
	call.call(Vector3(point.x, point.y - height, point.z))
	# The kit places its emitters in global coordinates over ground at y = 0. An emitter it left alone is unchanged;
	# one placed again at its old position can only be at the same spot, where the lift is the same height.
	for i in emitters.size():
		if emitters[i].global_position != before[i]:
			emitters[i].global_position.y += height
