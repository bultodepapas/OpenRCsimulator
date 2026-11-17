## DR-19d (docs/plans/drone-racing.md §18): the FPV quad's crash presentation. Reuses the project's crash kit: the
## synthetic MIT crash sounds (render/crash/crash_audio.gd) and the dust, blade-chip, mark and debris effects
## (render/crash/effects.gd), scaled for a 0.6 kg quad. Presentation only: it reads accepted impact, prop-damage and
## crash events and never writes simulation state. Nothing is allocated before the first event of a flight, and the
## kit stays disabled while effects or sound are off. Grinding props report damage every tick; sounds and effects are
## paced (one per prop per band, one touch per TOUCH_INTERVAL_S) so a scrape is a scrape, not a machine gun.
extends Node3D

const Effects := preload("res://render/crash/effects.gd")
const CrashAudio := preload("res://render/crash/crash_audio.gd")
const Frames := preload("res://render/frames.gd")

## Shortest interval (s) between two touch sounds or dust puffs.
const TOUCH_INTERVAL_S := 0.12
## A prop's damage band for pacing: intact, damaged, badly damaged, broken.
const BAND_LIMITS := [1.0, 0.75, 0.0]
## Impact speed (m/s along the normal) that maps to a full-strength touch.
const FULL_TOUCH_SPEED_MPS := 12.0
## Terminal crash speed (m/s) that maps to the top of the shared outcome ladder.
const FULL_CRASH_SPEED_MPS := 20.0

var enable_audio := true
var enable_effects := true
var effects: Node3D
var audio: Node3D
## Rotor index -> last presented damage band (pacing).
var _bands: Dictionary = {}
var _touch_cooldown := 0.0
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


## A survivable impact event ({surface, normal_speed_mps, point_ned}); `velocity` is the quad's render velocity.
func impact(event: Dictionary, velocity: Vector3) -> void:
	if _crashed or _touch_cooldown > 0.0:
		return
	_ensure()
	_touch_cooldown = TOUCH_INTERVAL_S
	var point := _render_point(event)
	var strength := clampf(float(event.get("normal_speed_mps", 0.0)) / FULL_TOUCH_SPEED_MPS, 0.05, 1.0)
	var on_ground := str(event.get("surface", "")) == "ground"
	var sliding := Vector2(velocity.x, velocity.z).length() > 2.0
	if audio != null:
		audio.touch(point, strength, sliding, "grass" if on_ground else "hard")
	if effects != null and on_ground:
		_at_ground(point, func(local: Vector3) -> void: effects.touch(local, velocity, strength, "grass"))


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
			audio.touch(point, 0.35, true, "hard")
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
	if effects != null:
		effects.update(delta, paused)
	if audio != null:
		audio.update(delta, paused, 0.0)


## A pad restart: no damage presented, no running effect or sound.
func reset() -> void:
	_bands.clear()
	_touch_cooldown = 0.0
	_crashed = false
	if effects != null:
		effects.reset()
	if audio != null:
		audio.reset()


## Damage band of a prop health (0 intact, 1 damaged, 2 badly damaged, 3 broken).
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
## the emitters (which the kit places in global coordinates) by the same height.
func _at_ground(point: Vector3, call: Callable) -> void:
	var height := float(ground_height.call(point.x, point.z)) if ground_height.is_valid() else 0.0
	effects.position = Vector3(0.0, height, 0.0)
	call.call(Vector3(point.x, point.y - height, point.z))
	for emitter: CPUParticles3D in effects.emitters:
		emitter.global_position.y += height
