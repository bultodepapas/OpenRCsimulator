extends SceneTree
## NK-6p (owner decision, 2026-11-27): a native flight freezes the configuration its guard watches.
## - After preparation the aircraft dictionary, the hull contact and the lake are read-only all the way down, and the
##   guard's per-tick plan proves those roots by identity, without their deep snapshots.
## - Replacing a frozen root with an equal writable copy still refuses the configuration.
## - A packed array stays writable in place under a read-only parent; its bitwise watch refuses an alias write and a
##   direct element write (Good Enemy review of NK-6p).
## - Preparation alone does not freeze: only the kernel's acceptance does.
## - With the freeze off the containers stay writable and the plan keeps its snapshots.
## - Flights are byte-identical with the freeze on and off.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const ElectricAdapter := preload("res://sim/native/electric_stage_adapter.gd")
const LiquidAdapter := preload("res://sim/native/liquid_stage_adapter.gd")
const GlowAdapter := preload("res://sim/native/glow_stage_adapter.gd")
const PrescribedAdapter := preload("res://sim/native/prescribed_stage_adapter.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary
var _lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var tested := 0
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "stik-glow-61fx-2t"]:
		NativeConfiguration.freeze_guarded_configuration = true
		var s := _session(id)
		if s == null or s.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK6P_SKIP %s" % id)
			if s != null:
				s.free()
			continue
		tested += 1
		_frozen(id, s)
		s.free()
		_unfrozen(id)
		_preparation_alone(id)
		_pair(id)
	NativeConfiguration.freeze_guarded_configuration = true
	if tested == 0:
		print("NK6P_SKIP no native session")
	print("native frozen configuration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## True when every Dictionary and Array in value is read-only.
func _deep_read_only(value: Variant) -> bool:
	if value is Dictionary:
		if not (value as Dictionary).is_read_only():
			return false
		for key: Variant in value:
			if not _deep_read_only(value[key]):
				return false
	elif value is Array:
		if not (value as Array).is_read_only():
			return false
		for item: Variant in value:
			if not _deep_read_only(item):
				return false
	return true


func _frozen(id: String, s: Node) -> void:
	_check(id + ": the aircraft is read-only all the way down", _deep_read_only(s.aircraft))
	_check(id + ": the hull contact is read-only all the way down", _deep_read_only(s._hull_contact))
	_check(id + ": the lake is read-only all the way down", _deep_read_only(s.environment.lake))
	var profile: Dictionary = s._native_stage._native.configuration_guard_profile(s, 1)
	_check(id + ": the guard proves the frozen roots by identity", int(profile.get("plan_frozen_roots", 0)) >= 3
		and bool(profile.get("plan_ready", false)), str(profile.get("plan_frozen_roots")))
	for i in 240:
		_tick(s)
	_check(id + ": the frozen configuration still matches", s._native_stage.configuration_matches(s)
		and s.sim.fault_reason.is_empty(), s.sim.fault_reason)
	# A root replaced by an equal writable copy is another instance: the guard refuses it.
	var original: Dictionary = s._hull_contact
	s._hull_contact = original.duplicate(true)
	_check(id + ": an equal writable copy of a frozen root refuses", not s._native_stage.configuration_matches(s))
	s._hull_contact = original
	_check(id + ": the original root matches again", s._native_stage.configuration_matches(s))
	# Capability answers kept for the frozen aircraft equal a fresh computation, and a replaced aircraft is answered
	# afresh: a copy whose wheel profile is no longer applied has no brake hardware.
	s._drop_tick_facts()
	_check(id + ": the frozen aircraft owns the kept capability answers", is_same(s._frozen_facts_owner, s.aircraft))
	var brakes: bool = s._wheel_brake_hardware()
	_check(id + ": the kept wheel-brake answer equals the hardware check", s.wheel_brake_available() == brakes
		and s.wheel_brake_available() == brakes)
	var prop: Dictionary = s.aircraft.model.propulsion
	var fresh_rotor: int = prop.slipstream.pieces.size() if prop.get("slipstream", {}).has("transport_speed_floor") else 0
	_check(id + ": the kept rotor index equals a fresh computation", s._rotor_index() == fresh_rotor
		and s._rotor_index() == fresh_rotor)
	var frozen_aircraft: Dictionary = s.aircraft
	var changed: Dictionary = frozen_aircraft.duplicate(true)
	if changed.model.get("wheel_profile") is Dictionary:
		changed.model.wheel_profile.status = "removed-for-test"
	s.aircraft = changed
	_check(id + ": a replaced aircraft is answered afresh", not s.wheel_brake_available()
		and s.wheel_brake_available() == s._wheel_brake_hardware())
	s.aircraft = frozen_aircraft
	_check(id + ": the frozen aircraft keeps its answer", s.wheel_brake_available() == brakes)
	# A packed array stays writable in place under a read-only parent: the engine shares its buffer with every
	# alias. Its bitwise watch must refuse an alias write and a direct element write.
	for root_name: String in ["aircraft", "_hull_contact", "lake"]:
		var root: Dictionary = s.environment.lake if root_name == "lake" else s.get(root_name)
		var leaf := _first_packed(root)
		_check(id + ": the " + root_name + " holds a packed leaf", not leaf.is_empty())
		if leaf.is_empty():
			continue
		var alias: PackedFloat64Array = leaf[0][leaf[1]]
		var old: float = alias[0]
		alias[0] = old + 1.0
		_check(id + ": an alias write into the " + root_name + "'s packed leaf reaches it",
			(leaf[0][leaf[1]] as PackedFloat64Array)[0] == old + 1.0)
		_check(id + ": the guard refuses an alias write into the " + root_name + "'s packed leaf",
			not s._native_stage.configuration_matches(s))
		alias[0] = old
		_check(id + ": the restored " + root_name + " matches again", s._native_stage.configuration_matches(s))
	var element := _first_packed(s.aircraft)
	if not element.is_empty():
		var held: float = (element[0][element[1]] as PackedFloat64Array)[0]
		element[0][element[1]][0] = held + 2.0
		_check(id + ": the guard refuses a direct element write under a read-only parent",
			not s._native_stage.configuration_matches(s))
		element[0][element[1]][0] = held
		_check(id + ": the restored element matches again", s._native_stage.configuration_matches(s))
	# The frozen lake's validity, kept inside guarded ticks, equals the full check and starts over at each preparation.
	_check(id + ": the frozen lake owns its kept validity", is_same(s._frozen_lake_owner, s.environment.lake))
	if s.finite_fuel_is_active():
		_check(id + ": the kept lake validity equals the full check", s._frozen_lake_valid
			and LakeSurface.is_valid_definition(s.environment.lake))
	s.reset()
	_check(id + ": a new preparation starts the kept lake validity over", not s._frozen_lake_valid
		and is_same(s._frozen_lake_owner, s.environment.lake))
	print("NK6P_FROZEN %s frozen_roots=%d snapshots=%d watches=%d" % [id, int(profile.get("plan_frozen_roots", 0)),
		int(profile.get("plan_snapshots", 0)), int(profile.get("plan_watches", 0))])


## [parent, key] of the first non-empty PackedFloat64Array found depth-first, or [].
func _first_packed(value: Variant) -> Array:
	if value is Dictionary:
		for key: Variant in value:
			var child: Variant = value[key]
			if child is PackedFloat64Array and not (child as PackedFloat64Array).is_empty():
				return [value, key]
			var found := _first_packed(child)
			if not found.is_empty():
				return found
	elif value is Array:
		for index: int in (value as Array).size():
			var child: Variant = value[index]
			if child is PackedFloat64Array and not (child as PackedFloat64Array).is_empty():
				return [value, index]
			var found := _first_packed(child)
			if not found.is_empty():
				return found
	return []


## The freeze waits for the kernel's acceptance: NativeConfiguration.prepare alone leaves the containers writable,
## so a refused native stage cannot leave a reference flight frozen.
func _preparation_alone(id: String) -> void:
	var s: Node = Flight.new()
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_REFERENCE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	var builder: Callable = WeatherAdapter.config_for
	if s.glow_is_active():
		builder = GlowAdapter.config_for
	elif s.liquid_fuel_is_active():
		builder = LiquidAdapter.config_for
	elif Propulsion.is_electric(s.aircraft.model.propulsion):
		builder = ElectricAdapter.config_for
	elif not PrescribedAdapter.kind_for(s).is_empty():
		builder = PrescribedAdapter.config_for
	var boundary: Dictionary = NativeConfiguration.prepare(s, builder)
	_check(id + ": preparation alone accepts the configuration", boundary.get("ok", false), str(boundary.get("reason")))
	_check(id + ": preparation alone leaves the aircraft writable", not s.aircraft.is_read_only()
		and not (s.aircraft.model as Dictionary).is_read_only() and not s._hull_contact.is_read_only())
	s.free()


func _unfrozen(id: String) -> void:
	NativeConfiguration.freeze_guarded_configuration = false
	var s := _session(id)
	NativeConfiguration.freeze_guarded_configuration = true
	if s == null:
		return
	var profile: Dictionary = s._native_stage._native.configuration_guard_profile(s, 1)
	_check(id + ": with the freeze off the aircraft stays writable", not s.aircraft.is_read_only()
		and not (s.aircraft.model as Dictionary).is_read_only())
	_check(id + ": with the freeze off the plan keeps its snapshots", int(profile.get("plan_frozen_roots", -1)) == 0
		and int(profile.get("plan_snapshots", 0)) >= 3, str(profile))
	s.free()


func _pair(id: String) -> void:
	var pair: Array = []
	for frozen: bool in [true, false]:
		NativeConfiguration.freeze_guarded_configuration = frozen
		var s := _session(id)
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.1 if s.sim.tick > 600 else 0.0, yaw = 0.05, throttle = 1.0}
		pair.append(s)
	NativeConfiguration.freeze_guarded_configuration = true
	var mismatched := 0
	for tick in 1200:
		_tick(pair[0])
		_tick(pair[1])
		if var_to_bytes([pair[0].sim.tick, pair[0].sim.state, pair[0].sim.continuous, pair[0].sim.aux,
				pair[0].sim.fault_reason]) != var_to_bytes([pair[1].sim.tick, pair[1].sim.state, pair[1].sim.continuous,
				pair[1].sim.aux, pair[1].sim.fault_reason]):
			mismatched += 1
		if not pair[0].crash.is_empty() or not pair[1].crash.is_empty():
			break
	_check(id + ": flights are byte-identical with the freeze on and off", mismatched == 0
		and pair[0].sim.fault_reason.is_empty(), str(mismatched) + " " + pair[0].sim.fault_reason)
	for s: Node in pair:
		s.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
