## Structural source10 matrix checks. These do not execute a native evaluator or qualify a product run.
extends SceneTree

const Domain := preload("res://sim/native_macos_domain.gd")
const Fleet := preload("fleet.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Wind := preload("res://physics/wind_config.gd")

# Each entry excludes both soft-hull values. These are the 42 open source10 rows, not accepted flights.
const OPEN := [
	"jensen-das-ugly-stik-60|ideal|runway|crosswind", "jensen-das-ugly-stik-60|ideal|runway|spatial-crosswind-v1",
	"stik-glow-61fx-2t|ideal|runway|crosswind", "stik-glow-61fx-2t|ideal|runway|gusty", "stik-glow-61fx-2t|ideal|runway|spatial-crosswind-v1",
	"stik-glow-55ax-2t|ideal|runway|crosswind", "stik-glow-55ax-2t|ideal|runway|gusty", "stik-glow-55ax-2t|ideal|runway|spatial-crosswind-v1",
	"stik-glow-fs64v-4t|ideal|runway|crosswind", "stik-glow-fs64v-4t|ideal|runway|gusty", "stik-glow-fs64v-4t|ideal|runway|spatial-crosswind-v1",
	"stik-electric-6s|ideal|runway|crosswind", "stik-electric-6s|ideal|runway|spatial-crosswind-v1",
	"stik-electric-6s|pack|runway|crosswind", "stik-electric-6s|pack|runway|spatial-crosswind-v1",
	"p51d-mustang-120|ideal|runway|crosswind", "sebart-avanti-s-a200-p100rx|ideal|runway|crosswind",
	"turbo-lumber-evolution|ideal|runway|crosswind", "turbo-lumber-evolution|pack|runway|crosswind",
	"moonrunner-x99|pack|hand_launch|spatial-crosswind-v1", "moonrunner-x99|ideal|airborne_half_power|hot-high",
]

var _checks := 0
var _failed := 0


class GuardSim:
	extends Node
	func dt() -> float:
		return 1.0 / 240.0


class GuardSession:
	extends Node
	var sim := GuardSim.new()
	var _collision_world := {}
	var _runway_field := {}
	var aircraft := {}
	var expected_aircraft_id := "jensen-das-ugly-stik-60"
	var aircraft_path := "res://data/aircraft/jensen_ugly_stik_60.json"
	var start_choice := "airborne"
	var start := {V = 15.0, state = PackedFloat64Array([60.0, -40.0, -30.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])}
	var trim_throttle := NAN
	var soft_hull_contacts := false
	var fuel_start_fill := 1.0
	var _failures: RefCounted = null
	var _frozen_aircraft := {}
	var workshop_identity := {}
	var _out_of_trim := {}
	var _rc_track := {}
	var _airframe_offset := PackedFloat64Array([0.0, 0.0, 0.0])
	var _shaft_explicit := false
	var _shaft_pending_reset := false
	var _external_spawn_heading_set := false


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failed += 1
		printerr("MAC_DOMAIN failed: " + label)


func _selection(row: Dictionary) -> Dictionary:
	var path: String = Catalog.data_for(row.aircraft, row.battery)
	return {vehicle = row.vehicle, aircraft = row.aircraft, battery = row.battery, path = path,
		aircraft_sha256 = FileAccess.get_sha256(path), start = "airborne" if row.case == "trim" else row.case,
		trim_throttle = NAN, weather = Wind.preset(row.weather), soft_hull = row.soft_hull}


func _check_frozen_guard() -> void:
	var original := {proxies = [{north = 1.0}], bins = {cell = PackedInt64Array([3, 7])}}
	var field := {id = "default", nested = [{point = 4.0}]}
	var world_copy: Dictionary = Domain._detached_read_only(original)
	var field_copy: Dictionary = Domain._detached_read_only(field)
	_check(not is_same(original, world_copy) and world_copy.is_read_only() and world_copy.proxies.is_read_only() \
		and world_copy.proxies[0].is_read_only() and world_copy.bins.is_read_only(), "world is detached and recursively read-only")
	_check(not is_same(field, field_copy) and field_copy.is_read_only() and field_copy.nested.is_read_only() \
		and field_copy.nested[0].is_read_only(), "field is detached and recursively read-only")
	original.proxies[0].north = 9.0
	field.nested[0].point = 8.0
	_check(world_copy.proxies[0].north == 1.0 and field_copy.nested[0].point == 4.0,
		"original nested aliases cannot mutate detached owners")
	var old_bin_alias: PackedInt64Array = original.bins.cell
	old_bin_alias[0] = 99
	_check(world_copy.bins.cell[0] == 3, "serialization detaches existing packed aliases")
	var session := GuardSession.new()
	session._collision_world = world_copy
	session._runway_field = field_copy
	var guard := Domain.Guard.new()
	guard.owner = session
	guard.sim = session.sim
	guard.world = world_copy
	guard.field = field_copy
	guard.aircraft_id = session.expected_aircraft_id
	guard.aircraft_path = session.aircraft_path
	guard.start_choice = session.start_choice
	guard.start_state = session.start.state.duplicate()
	guard.start_bytes = Domain._start_bytes(session.start)
	guard.trim_throttle = session.trim_throttle
	guard.soft_hull = session.soft_hull_contacts
	_check(Domain.guard_matches(session, guard), "frozen context and NaN trim match")
	session.aircraft = session.aircraft.duplicate(true)
	_check(Domain.guard_matches(session, guard), "aircraft replacement is owned by configuration guard")
	session._collision_world = world_copy.duplicate(true)
	_check(not Domain.guard_matches(session, guard), "world replacement is detected")
	session._collision_world = world_copy
	session._runway_field = field_copy.duplicate(true)
	_check(not Domain.guard_matches(session, guard), "field replacement is detected")
	session._runway_field = field_copy
	session.start_choice = "runway"
	_check(not Domain.guard_matches(session, guard), "start selection change is detected")
	session.start_choice = "airborne"
	session.trim_throttle = 0.5
	_check(not Domain.guard_matches(session, guard), "NaN and 0.5 trim are distinct")
	session.trim_throttle = NAN
	var changed_start: PackedFloat64Array = session.start.state.duplicate()
	changed_start[0] += 1.0
	session.start.state = changed_start
	_check(not Domain.guard_matches(session, guard), "start state change is detected")
	session.start.state = guard.start_state.duplicate()
	session.start.V += 0.01
	_check(not Domain.guard_matches(session, guard), "start metadata change is detected")
	session.start.V = 15.0
	_check(Domain.guard_matches(session, guard), "restored exact start matches")
	session.fuel_start_fill = 0.5
	_check(not Domain.guard_matches(session, guard), "fuel setting change is detected")
	session.fuel_start_fill = 1.0
	session._rc_track = {custom = true}
	_check(not Domain.guard_matches(session, guard), "custom track is detected")
	session._rc_track = {}
	session._external_spawn_heading_set = true
	_check(not Domain.guard_matches(session, guard), "custom spawn is detected")
	session.sim.free()
	session.free()


func _initialize() -> void:
	var admitted := 0
	var refused := 0
	for row: Dictionary in Fleet._fleet_declared_rows():
		if row.vehicle != "fixed-wing": continue
		var key := "%s|%s|%s|%s" % [row.aircraft, row.battery, row.case, row.weather]
		var result: Dictionary = Domain.screen(_selection(row))
		var expected: bool = key not in OPEN
		_check(result.ok == expected, key + "/soft=" + str(row.soft_hull))
		if result.ok: admitted += 1
		else: refused += 1
	_check(admitted == 1386 and refused == 42, "source10 matrix split")
	var row := {vehicle = "fixed-wing", aircraft = "jensen-das-ugly-stik-60", battery = "ideal", case = "trim",
		weather = "calm", soft_hull = false}
	var good := _selection(row)
	_check(Domain.screen(good).ok, "stock reference fixture")
	for change: Dictionary in [{vehicle = "rotorcraft"}, {aircraft = "moonrunner-other"}, {battery = "pack"},
			{path = "res://custom.json"}, {aircraft_sha256 = "0".repeat(64)}, {start = "runway-custom"},
			{soft_hull = 1}, {trim_throttle = 0.4}, {trim_throttle = 0}, {weather = {}}]:
		var bad: Dictionary = good.duplicate(true)
		bad.merge(change, true)
		_check(not Domain.screen(bad).ok, "reject " + str(change.keys()))
	var custom: Dictionary = good.duplicate(true)
	custom.weather.speed_mps = 0.125
	_check(not Domain.screen(custom).ok, "custom weather")
	var production: Dictionary = good.duplicate(true)
	production.trim_throttle = 0.5
	var pending: Dictionary = Domain.screen(production)
	_check(not pending.ok and pending.profile == "production", "production requires independent evidence")
	_check(Domain.screen(production, true).ok, "qualified production profile selects structurally")
	var initial := {ok = true, requested_throttle = 0.5, V = 15.0,
		state = PackedFloat64Array([60.0, -40.0, -30.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])}
	var start_hash := Domain.start_sha256(initial, true)
	_check(start_hash.length() == 64 and start_hash == Domain.start_sha256(initial.duplicate(true), true),
		"exact production start identity is deterministic")
	var changed: Dictionary = initial.duplicate(true)
	changed.V += 0.01
	_check(Domain.start_sha256(changed, true) != start_hash, "custom trim metadata changes the start hash")
	changed = initial.duplicate(true)
	changed.erase("requested_throttle")
	_check(Domain.start_sha256(changed, true).is_empty(), "custom trim without requested throttle is refused")
	changed = initial.duplicate(true)
	changed.requested_throttle = 0.4
	_check(Domain.start_sha256(changed, true).is_empty(), "other requested throttle is refused")
	changed = initial.duplicate(true)
	changed.extra = [1, 2]
	_check(Domain.start_sha256(changed, true).is_empty(), "nested start values are refused")
	_check(not Domain.screen_session(null).ok, "null session refused")
	_check_frozen_guard()
	print("MAC_DOMAIN checks=%d failures=%d" % [_checks, _failed])
	quit(0 if _failed == 0 else 1)
