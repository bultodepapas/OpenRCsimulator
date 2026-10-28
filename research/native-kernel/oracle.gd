## NK-3 milestone 1 oracle: byte comparison of the native stage-evaluator components against the GDScript reference
## loaded from app/ at run time (run with --path app). Research only; nothing here is installed into the app.
## Components: math shim semantics, float-literal parsing, terrain + lake sampler, GP-02 wheel evaluate and
## compressions (electric Ugly Stik runway context and variants), Air.compute, GroundEffect.factors and Aero.loads
## with its strip/oracle parts (Stik model and variants), D6 refusals, then paired component timings.
## Usage: godot --headless --path app --script <abs>/oracle.gd -- --extension=<abs .gdextension> --output=<new json>
##        [--seed=20261027] [--states=12000] [--variant-states=1500] [--timing-rounds=15]
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

const AIRCRAFT := "jensen-das-ugly-stik-60"
const MAX_EXAMPLES := 6

var _extension := ""
var _output := ""
var _seed := 20261027
var _states := 12000
var _variant_states := 1500
var _timing_rounds := 15
var _rng := RandomNumberGenerator.new()
var _native: Object
var _report := {}
var _failures := PackedStringArray()
var _specials := PackedFloat64Array()
var _options := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _parse():
		printerr("NK3_ORACLE usage: " + ", ".join(_failures))
		quit(2)
		return
	_rng.seed = _seed
	_specials = _special_values()
	if not _load_native_extension():
		quit(2)
		return
	var started := Time.get_ticks_msec()
	_report = {
		format = "openrc-nk3-oracle v1", seed = _seed, states = _states, variant_states = _variant_states,
		engine = Engine.get_version_info().string, processor = OS.get_processor_name(),
		identity = _native.backend_identity(), sources = _source_hashes(), components = {}, coverage = {},
		refusals = {}, timing = {},
	}
	if not _self_test():
		_finish(started)
		return
	_check_law_identity()
	_check_literals()
	_checks()
	_finish(started)


## Production fleet overrides this hook so receipt validation precedes library initialization.
func _load_native_extension() -> bool:
	# One OpenRCNativeKernel per process: an app install (app/native/kernel, possibly auto-loaded through
	# .godot/extension_list.cfg) and a tmp research build cannot both register the class.
	if ClassDB.class_exists("OpenRCNativeKernel") and not GDExtensionManager.is_extension_loaded(_extension):
		printerr("NK3_ORACLE another OpenRCNativeKernel library is already loaded; run with --app-library " +
			"(res://native/kernel) or remove the app install")
		return false
	var status: int = OK if GDExtensionManager.is_extension_loaded(_extension) else GDExtensionManager.load_extension(_extension)
	if status != OK or not ClassDB.class_exists("OpenRCNativeKernel"):
		printerr("NK3_ORACLE cannot load extension: %s (status %d)" % [_extension, status])
		return false
	_native = ClassDB.instantiate("OpenRCNativeKernel")
	return true


## Milestone-1 component checks; harnesses extending this script (stage_oracle.gd, trajectory.gd) override it.
func _checks() -> void:
	_check_math_shim()
	var context := _session_context()
	if context.is_empty():
		return
	_check_terrain(context)
	_check_wheels(context)
	_check_aero(context)
	_check_refusals(context)
	_time_components(context)


## Extra `--name=value` options a subclass accepts; values land in `_options`.
func _extra_option_names() -> PackedStringArray:
	return PackedStringArray()


func _parse() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			_failures.append("bad argument " + arg)
			continue
		match pair[0]:
			"extension": _extension = pair[1]
			"output": _output = pair[1]
			"seed": _seed = pair[1].to_int()
			"states": _states = pair[1].to_int()
			"variant-states": _variant_states = pair[1].to_int()
			"timing-rounds": _timing_rounds = pair[1].to_int()
			_:
				if pair[0] in _extra_option_names(): _options[pair[0]] = pair[1]
				else: _failures.append("unknown option " + pair[0])
	if _extension.is_empty() or _output.is_empty():
		_failures.append("--extension and --output are required")
	elif FileAccess.file_exists(_output):
		_failures.append("--output must name a new file")
	return _failures.is_empty()


func _finish(started: int) -> void:
	_report.wall_ms = Time.get_ticks_msec() - started
	_report.failures = _failures
	var total := 0
	var identical := 0
	for name: String in _report.components:
		total += int(_report.components[name].count)
		identical += int(_report.components[name].identical)
	_report.total = {compared = total, identical = identical, mismatched = total - identical}
	_report.verdict = "pass" if _failures.is_empty() and total == identical and total > 0 else "fail"
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t", true, true) + "\n")
		file.close()
	print("NK3_ORACLE verdict=%s compared=%d identical=%d failures=%d output=%s"
		% [_report.verdict, total, identical, _failures.size(), _output])
	quit(0 if _report.verdict == "pass" else 1)


# ---------------------------------------------------------------- comparison bookkeeping

static func _bits(x: float) -> int:
	return PackedFloat64Array([x]).to_byte_array().decode_s64(0)


static func _from_bits(values: PackedInt64Array) -> PackedFloat64Array:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 8)
	for i in values.size():
		bytes.encode_s64(i * 8, values[i])
	return bytes.to_float64_array()


func _special_values() -> PackedFloat64Array:
	return _from_bits(PackedInt64Array([
		0, -9223372036854775808, # +0, -0
		0x7ff8000000000000, -2251799813685248, 0x7ff8000000000001, # +NaN, -NaN (0xfff8...), payload NaN
		0x7ff0000000000000, -4503599627370496, # +INF, -INF
		1, -9223372036854775807, # +-min subnormal
		0x7fefffffffffffff, -4503599627370497, # +-DBL_MAX
	]))


func _component(name: String) -> Dictionary:
	if not _report.components.has(name):
		_report.components[name] = {count = 0, identical = 0, finite_ulp = 0, max_ulp = 0, zero_sign = 0,
			nan_bits = 0, class_mismatch = 0, shape = 0, examples = []}
	return _report.components[name]


## Compare two flat float arrays bit for bit (var_to_bytes identity) and classify any difference.
func _compare(name: String, reference: Variant, native: Variant, inputs: Variant = null) -> bool:
	var entry := _component(name)
	entry.count += 1
	if var_to_bytes(reference) == var_to_bytes(native):
		entry.identical += 1
		return true
	var kind := "shape"
	var ulp := 0
	if reference is PackedFloat64Array and native is PackedFloat64Array and reference.size() == native.size():
		kind = "identical"
		for i in reference.size():
			var a: float = reference[i]
			var b: float = native[i]
			if _bits(a) == _bits(b):
				continue
			if is_nan(a) and is_nan(b):
				kind = "nan_bits" if kind == "identical" else kind
			elif a == 0.0 and b == 0.0:
				kind = "zero_sign" if kind == "identical" else kind
			elif is_finite(a) and is_finite(b) and signf(a) == signf(b):
				kind = "finite_ulp"
				ulp = maxi(ulp, absi(_bits(a) - _bits(b)))
			else:
				kind = "class_mismatch"
				break
	match kind:
		"finite_ulp":
			entry.finite_ulp += 1
			entry.max_ulp = maxi(int(entry.max_ulp), ulp)
		"nan_bits": entry.nan_bits += 1
		"zero_sign": entry.zero_sign += 1
		"class_mismatch": entry.class_mismatch += 1
		_: entry.shape += 1
	if entry.examples.size() < MAX_EXAMPLES:
		entry.examples.append({kind = kind, ulp = ulp, reference = _hex(reference), native = _hex(native),
			inputs = _hex(inputs)})
	return false


## Exact, replayable rendering: floats as 16-digit IEEE-754 bit patterns, containers recursively.
static func _hex(value: Variant) -> Variant:
	if value is float:
		return "%016x" % _bits(value)
	if value is PackedFloat64Array:
		var out: Array = []
		for x: float in value:
			out.append("%016x" % _bits(x))
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_hex(item))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _hex(value[key])
		return out
	return var_to_str(value)


func _tally(group: String, key: String, amount := 1) -> void:
	if not _report.coverage.has(group):
		_report.coverage[group] = {}
	_report.coverage[group][key] = int(_report.coverage[group].get(key, 0)) + amount


# ---------------------------------------------------------------- comparator self-test, identity, literals, math shim

## The comparator must flag a one-ulp change, a zero-sign change and a NaN-sign change before any result counts.
func _self_test() -> bool:
	var one := PackedFloat64Array([1.0])
	var next := _from_bits(PackedInt64Array([_bits(1.0) + 1]))
	var nan_pair := _from_bits(PackedInt64Array([0x7ff8000000000000, -2251799813685248]))
	var caught := [
		not _compare("_self_test", one, next), # GDScript's -0.0 literal is +0.0 (NK-1): build -0.0 from its bits
		not _compare("_self_test", PackedFloat64Array([0.0]), _from_bits(PackedInt64Array([-9223372036854775808]))),
		not _compare("_self_test", PackedFloat64Array([nan_pair[0]]), PackedFloat64Array([nan_pair[1]])),
		_compare("_self_test", one, PackedFloat64Array([1.0])),
	]
	var entry: Dictionary = _report.components["_self_test"]
	var ok: bool = caught == [true, true, true, true] and entry.finite_ulp == 1 and entry.zero_sign == 1 and entry.nan_bits == 1
	_report.components.erase("_self_test")
	_report.self_test = {passed = ok, detected = caught}
	if not ok:
		_failures.append("comparator self-test failed")
	return ok


func _source_hashes() -> Dictionary:
	var out := {}
	for path: String in ["res://physics/math3d.gd", "res://physics/ground_terrain.gd", "res://physics/lake_surface.gd",
			"res://physics/ground_wheels.gd", "res://physics/ground_contact.gd", "res://physics/air_data.gd",
			"res://physics/ground_effect.gd", "res://physics/aero.gd", "res://physics/propulsion.gd",
			"res://physics/dynamics.gd", "res://physics/hull_contact.gd", "res://physics/wind_field.gd",
			"res://sim/environment.gd", "res://sim/flight_session.gd", "res://sim/simulation.gd",
			"res://sim/native_stage.gd", "res://app_state/native_package.gd", "res://data/aircraft/jensen_ugly_stik_60.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _check_law_identity() -> void:
	var identity: Dictionary = _native.backend_identity()
	_report.law_identity = {aero_reference = Aero.LOADS_LAW, aero_native = identity.aero_law,
		rolling_reference = Wheels.ROLLING_LAW, rolling_native = identity.rolling_law}
	if identity.aero_law != Aero.LOADS_LAW or identity.rolling_law != Wheels.ROLLING_LAW:
		_failures.append("law identity differs from the loaded reference (D6: native must not be used)")


## The engine parses GDScript float literals itself; compile the native table's spellings and compare bits.
func _check_literals() -> void:
	var table: Dictionary = _native.literal_table()
	var spellings: Array = table.keys()
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nstatic func values() -> Array:\n\treturn [%s]\n" % ", ".join(spellings)
	if script.reload() != OK:
		_failures.append("literal probe script failed to compile")
		return
	var values: Array = script.values()
	for i in spellings.size():
		_compare("literals", PackedFloat64Array([values[i]]), PackedFloat64Array([table[spellings[i]]]), spellings[i])


func _check_math_shim() -> void:
	var a := PackedFloat64Array()
	var b := PackedFloat64Array()
	var c := PackedFloat64Array()
	# Special grid, PI seams for wrapf, then random arguments.
	var seams := PackedFloat64Array([PI, -PI, 2.0 * PI, -2.0 * PI, 3.0 * PI, PI - 1e-12, -PI + 1e-12, PI + 1e-6,
		1e-5, -1e-5, 0.5, 1.0, -1.0, 2.0, 1e22, -1e22])
	var pool := _specials.duplicate()
	pool.append_array(seams)
	for x: float in pool:
		for y: float in pool:
			a.append(x)
			b.append(y)
			c.append(pool[_rng.randi_range(0, pool.size() - 1)])
	for i in 20000:
		a.append(_rng.randf_range(-20.0, 20.0) if i % 3 else _rng.randf_range(-1e6, 1e6))
		b.append(_rng.randf_range(-5.0, 5.0))
		c.append(_rng.randf_range(-5.0, 5.0))
	var minus_pi := PackedFloat64Array()
	var plus_pi := PackedFloat64Array()
	var magnitude := PackedFloat64Array()
	for x: float in a:
		minus_pi.append(-PI)
		plus_pi.append(PI)
		magnitude.append(absf(x))
	var wrap_pi: PackedFloat64Array = _native.math_probe(0, a, minus_pi, plus_pi)
	var pow_positive: PackedFloat64Array = _native.math_probe(6, magnitude, b, c)
	for fn in 14:
		var native: PackedFloat64Array = _native.math_probe(fn, a, b, c)
		for i in a.size():
			var x: float = a[i]
			var y: float = b[i]
			var z: float = c[i]
			var r: float
			var n: float = native[i]
			match fn:
				0:
					if i % 2:
						r = wrapf(x, -PI, PI)
						n = wrap_pi[i]
					else:
						r = wrapf(x, y, z)
				1: r = clampf(x, y, z)
				2: r = maxf(x, y)
				3: r = minf(x, y)
				4: r = absf(x)
				5: r = lerpf(x, y, z)
				6:
					if i % 2:
						r = pow(absf(x), y)
						n = pow_positive[i]
					else:
						r = pow(x, y)
				7: r = atan2(x, y)
				8: r = sin(x)
				9: r = cos(x)
				10: r = sqrt(x)
				11: r = Aero._smoothstep(x)
				12: r = LakeSurface._smoothstep(x)
				13: r = M.pow_(x, 2)
			_compare("math_shim", PackedFloat64Array([r]), PackedFloat64Array([n]), [fn, x, y, z])


# ---------------------------------------------------------------- session context

func _session_context() -> Dictionary:
	var session: Node = Session.new()
	session.soft_hull_contacts = true
	session.setup(str(Catalog.entry(AIRCRAFT).data), AIRCRAFT)
	if not session.is_flyable():
		_failures.append("aircraft setup failed: " + str(session.pause_reason))
		session.free()
		return {}
	var field: Dictionary = FieldLoader.load_from()
	var lake_load: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake_load.ok or not session.set_field(field.field) or not session.set_lake_context(lake_load.lake):
		_failures.append("field/lake setup failed")
		session.free()
		return {}
	session.start_choice = Session.START_RUNWAY
	session.reset()
	if not session.sim.fault_reason.is_empty() or session.wheel_count() != 3 or session._rotor_index() != 0:
		_failures.append("unexpected runway session layout")
		session.free()
		return {}
	var aux: PackedFloat64Array = session.sim.aux
	var context := {
		model = session.aircraft.model.duplicate(true),
		gear = session.current_landing_gear(aux).duplicate(true),
		surfaces = session.ground_surfaces.duplicate(),
		lake = session._lake.duplicate(true),
		rest = session.sim.state.duplicate(),
		aux = aux.duplicate(),
		continuous = session.sim.continuous.duplicate(),
		anchors = aux.slice(Session.AUX_ANCHORS, Session.AUX_ANCHORS + 9),
		steer = aux[Session.AUX_SERVO + 2],
		downwash = aux[session.downwash_index()],
		rpm = aux[Session.AUX_RPM],
		deflections = session._deflections(aux).duplicate(),
		rho = session.air_density(session.sim.state),
	}
	_report.session = {aircraft = AIRCRAFT, data_sha256 = context.model.data_sha256, lake_identity = context.lake.identity,
		surfaces = var_to_str(context.surfaces), rest_state = var_to_str(context.rest),
		brake_input_index = session.wheel_brake_input_index(), retractable = session.gear_is_retractable()}
	session.free()
	return context


static func _ground_ready(native: Object, gear: Dictionary, surfaces: PackedFloat64Array, lake: Dictionary) -> Dictionary:
	return native.prepare_ground(gear, surfaces, lake, lake.is_empty() or LakeSurface.is_valid_definition(lake))


# ---------------------------------------------------------------- terrain

func _check_terrain(context: Dictionary) -> void:
	var surfaces: PackedFloat64Array = context.surfaces
	var lake: Dictionary = context.lake
	var prepared: Dictionary = _ground_ready(_native, context.gear, surfaces, lake)
	if not prepared.ok:
		_failures.append("prepare_ground failed: " + str(prepared.error))
		return
	var bank: PackedFloat64Array = lake.bank_ne_m
	var aabb := LakeSurface._polygon_aabb(bank)
	for i in _states:
		var north: float
		var east: float
		match i % 6:
			0, 1: # inside / around the lake bank, where the five-point stencil and bed/bank branches run
				north = _rng.randf_range(aabb[0] - 1.0, aabb[1] + 1.0)
				east = _rng.randf_range(aabb[2] - 1.0, aabb[3] + 1.0)
			2: # surface-rectangle edges (smoothstep feathers)
				var row: int = _rng.randi_range(0, surfaces.size() / 6 - 2) * 6
				north = surfaces[row + _rng.randi_range(0, 1)] + _rng.randf_range(-0.6, 0.6)
				east = _rng.randf_range(surfaces[row + 2] - 1.0, surfaces[row + 3] + 1.0) if absf(surfaces[row + 2]) < 1000.0 \
					else _rng.randf_range(-300.0, 300.0)
			3:
				north = _rng.randf_range(-300.0, 300.0)
				east = _rng.randf_range(-300.0, 300.0)
			4:
				north = _rng.randf_range(5.0, 25.0)
				east = _rng.randf_range(-55.0, 55.0)
			_:
				north = _specials[_rng.randi_range(0, _specials.size() - 1)] if _rng.randf() < 0.5 else _rng.randf_range(-3e4, 3e4)
				east = _specials[_rng.randi_range(0, _specials.size() - 1)] if _rng.randf() < 0.5 else _rng.randf_range(-3e4, 3e4)
		if i % 6 < 2 and bool(LakeSurface.sample_covered_terrain_validated(lake, north, east).get("covered", false)):
			_tally("terrain", "lake_covered")
		_compare("terrain_with_lake", Terrain.sample_validated(north, east, surfaces, lake),
			_native.terrain_sample(north, east, true), [north, east])
		_compare("terrain_no_lake", Terrain.sample_validated(north, east, surfaces),
			_native.terrain_sample(north, east, false), [north, east])
	for table: PackedFloat64Array in _surface_table_variants(surfaces):
		_compare("surface_table_validity", PackedFloat64Array([1.0 if Terrain.is_valid_surface_table(table) else 0.0]),
			PackedFloat64Array([1.0 if _native.surface_table_is_valid(table) else 0.0]), var_to_str(table))


func _surface_table_variants(surfaces: PackedFloat64Array) -> Array[PackedFloat64Array]:
	var out: Array[PackedFloat64Array] = [surfaces, PackedFloat64Array(), PackedFloat64Array([1.0, 2.0, 3.0])]
	for index in surfaces.size():
		for value: float in [NAN, INF, -INF, 0.0, _specials[1], 0.04, 0.05, 1.0, 1.01, 0.5, 20.0, 20.5, -1.0]: # [1] is a true -0.0
			var edited := surfaces.duplicate()
			edited[index] = value
			out.append(edited)
	return out


# ---------------------------------------------------------------- wheels

func _random_unit_quaternion() -> PackedFloat64Array:
	var u1 := _rng.randf()
	var u2 := _rng.randf() * TAU
	var u3 := _rng.randf() * TAU
	var a := sqrt(1.0 - u1)
	var b := sqrt(u1)
	return M.quat(a * sin(u2), a * cos(u2), b * sin(u3), b * cos(u3))


func _small_rotation(base: PackedFloat64Array, max_angle: float) -> PackedFloat64Array:
	var axis := M.v3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	if M.norm(axis) < 1e-6:
		axis = M.v3(1.0, 0.0, 0.0)
	return M.q_normalized(M.q_mul(base, M.q_from_axis_angle(axis, _rng.randf_range(-max_angle, max_angle))))


func _special() -> float:
	return _specials[_rng.randi_range(0, _specials.size() - 1)]


## A runway-contact state around the session's rest pose, over runway, rotor pad, grass and the lake bank.
func _ground_state(context: Dictionary, surfaces: PackedFloat64Array, lake: Dictionary, malformed: bool) -> PackedFloat64Array:
	var s: PackedFloat64Array = context.rest.duplicate()
	var region := _rng.randi_range(0, 9)
	if region <= 3:
		s[0] = _rng.randf_range(8.0, 22.0)
		s[1] = _rng.randf_range(-52.0, 52.0)
	elif region == 4:
		s[0] = _rng.randf_range(2.0, 10.0)
		s[1] = _rng.randf_range(-4.0, 4.0)
	elif region <= 6 and not lake.is_empty():
		var aabb := LakeSurface._polygon_aabb(lake.bank_ne_m)
		s[0] = _rng.randf_range(aabb[0] - 1.0, aabb[1] + 1.0)
		s[1] = _rng.randf_range(aabb[2] - 1.0, aabb[3] + 1.0)
	else:
		s[0] = _rng.randf_range(-250.0, 250.0)
		s[1] = _rng.randf_range(-250.0, 250.0)
	var attitude: PackedFloat64Array = context.rest.slice(RB.ATT, RB.ATT + 4)
	var pick := _rng.randf()
	if pick < 0.75:
		var yaw := _rng.randf_range(-PI, PI)
		attitude = M.q_mul(M.q_from_axis_angle(M.v3(0.0, 0.0, 1.0), yaw), attitude)
		attitude = _small_rotation(attitude, 0.25)
	elif pick < 0.9:
		attitude = _random_unit_quaternion()
	for k in 4:
		s[RB.ATT + k] = attitude[k]
	var rest_clearance: float = context.rest[RB.POS + 2] + Terrain.sample_validated(context.rest[0], context.rest[1], surfaces, lake)[0]
	var ground: PackedFloat64Array = Terrain.sample_validated(s[0], s[1], surfaces, lake)
	s[RB.POS + 2] = rest_clearance - ground[0] + _rng.randf_range(-0.06, 0.09)
	var motion := _rng.randf()
	for k in 3:
		if motion < 0.3:
			s[RB.VEL + k] = _rng.randf_range(-0.03, 0.03)
		elif motion < 0.8:
			s[RB.VEL + k] = _rng.randf_range(-2.0, 25.0) if k == 0 else _rng.randf_range(-2.0, 2.0)
		else:
			s[RB.VEL + k] = _rng.randf_range(-40.0, 40.0)
		s[RB.RATE + k] = _rng.randf_range(-0.5, 0.5) if motion < 0.8 else _rng.randf_range(-15.0, 15.0)
	if malformed:
		for _k in _rng.randi_range(1, 3):
			s[_rng.randi_range(0, 12)] = _special() if _rng.randf() < 0.8 else _rng.randf_range(-1e6, 1e6)
	return s


func _check_wheels(context: Dictionary) -> void:
	var cases := [
		{name = "stik", gear = context.gear, surfaces = context.surfaces, lake = context.lake, states = _states},
		{name = "variant_brakes_steer_defaults", gear = _gear_variant(context.gear), surfaces = context.surfaces,
			lake = context.lake, states = _variant_states},
		{name = "flat_no_lake", gear = context.gear, surfaces = PackedFloat64Array(), lake = {}, states = _variant_states},
		{name = "invalid_table", gear = context.gear, surfaces = _bad_table(context.surfaces), lake = context.lake,
			states = maxi(100, _variant_states / 5)},
		{name = "invalid_lake", gear = context.gear, surfaces = context.surfaces, lake = _bad_lake(context.lake),
			states = maxi(100, _variant_states / 5)},
		{name = "no_gear", gear = {}, surfaces = context.surfaces, lake = context.lake, states = maxi(100, _variant_states / 5)},
	]
	for case: Dictionary in cases:
		var gear: Dictionary = case.gear
		var surfaces: PackedFloat64Array = case.surfaces
		var lake: Dictionary = case.lake
		var prepared: Dictionary = _ground_ready(_native, gear, surfaces, lake)
		if not prepared.ok:
			_failures.append("prepare_ground %s failed: %s" % [case.name, prepared.error])
			continue
		var contacts: int = gear.contacts.size() if not gear.is_empty() else 3
		var valid_context: bool = Terrain.is_valid_surface_table(surfaces) and (lake.is_empty() or LakeSurface.is_valid_definition(lake))
		for i in int(case.states):
			var malformed := _rng.randf() < 0.1
			var s := _ground_state(context, surfaces if valid_context else context.surfaces, lake if valid_context else context.lake, malformed)
			var steer: float = _rng.randf_range(-1.2, 1.2) if _rng.randf() < 0.9 else _special()
			var brake: float = 0.0 if case.name == "stik" and _rng.randf() < 0.8 else _rng.randf_range(-0.5, 1.5)
			var anchors := PackedFloat64Array()
			var speeds := PackedFloat64Array()
			var shape := _rng.randf()
			for k in contacts:
				var position := PackedFloat64Array([s[0], s[1], 0.0])
				var long_speed := 0.0
				if not gear.is_empty() and valid_context:
					var f: Dictionary = Wheels.frame(s, gear.contacts[k], steer, surfaces, PackedFloat64Array(), true, lake)
					position = f.position
					long_speed = f.long_speed
				var stuck_pick := _rng.randf()
				anchors.append(position[0] + _rng.randf_range(-0.02, 0.02))
				anchors.append(position[1] + _rng.randf_range(-0.02, 0.02))
				anchors.append(1.0 if stuck_pick < 0.6 else (0.0 if stuck_pick < 0.92 else [0.5, NAN, 2.0][_rng.randi_range(0, 2)]))
				speeds.append(long_speed + _rng.randf_range(-0.03, 0.03) if _rng.randf() < 0.5 else _rng.randf_range(-30.0, 30.0))
			if malformed and _rng.randf() < 0.5:
				if _rng.randf() < 0.5: speeds[_rng.randi_range(0, speeds.size() - 1)] = _special()
				else: anchors[_rng.randi_range(0, anchors.size() - 1)] = _special()
			if shape < 0.03:
				speeds.resize(_rng.randi_range(0, contacts + 1))
			elif shape < 0.06:
				anchors.resize(_rng.randi_range(0, anchors.size() + 2))
			var reference: Dictionary = Wheels.evaluate(s, gear, steer, surfaces, anchors, speeds, brake, false, lake)
			var native: Dictionary = _native.wheels_evaluate(s, steer, anchors, speeds, brake)
			var inputs := [s, steer, anchors, speeds, brake]
			_compare("wheels_loads", reference.loads, native.get("loads", null), inputs)
			_compare("wheels_derivative", reference.derivative, native.get("derivative", null), inputs)
			_compare("wheels_compressions", Wheels.compressions(s, gear, surfaces, lake), _native.wheels_compressions(s), s)
			_tally("wheels_" + case.name, "states")
			if malformed: _tally("wheels_" + case.name, "malformed")
			if not reference.loads.is_empty() and reference.loads.size() == 6:
				_tally("wheels_" + case.name, "loaded_states")
			if case.name == "stik" or case.name == "variant_brakes_steer_defaults":
				var diagnostics: Dictionary = Wheels.evaluate(s, gear, steer, surfaces, anchors, speeds, brake, true, lake)
				for k in diagnostics.wheels.size():
					var row: Dictionary = diagnostics.wheels[k]
					if row.normal_load > 0.0:
						_tally("wheels_" + case.name, "loaded_wheels")
						_tally("wheels_" + case.name, "surface_row_%d" % row.surface_index)
						if anchors.size() == contacts * 3 and anchors[k * 3 + 2] == 1.0 and absf(row.longitudinal_slip) < Wheels.STICK_SPEED:
							_tally("wheels_" + case.name, "stuck_wheels")
						if row.brake_torque != 0.0:
							_tally("wheels_" + case.name, "braking_wheels")
					if not lake.is_empty() and k < anchors.size() / 3 and \
							bool(LakeSurface.sample_covered_terrain_validated(lake, anchors[k * 3], anchors[k * 3 + 1]).get("covered", false)):
						_tally("wheels_" + case.name, "lake_covered_wheels")


func _gear_variant(gear: Dictionary) -> Dictionary:
	var out := gear.duplicate(true)
	out.erase("tan_peak_slip")
	out.erase("breakaway_factor")
	out.erase("rolling_reference_radius")
	out.erase("rolling_reference_radius_provenance")
	for k in out.contacts.size():
		var c: Dictionary = out.contacts[k]
		c.brake_torque = 0.35 + 0.1 * k
		if k == out.contacts.size() - 1:
			c.max_steering = 0.6
			c.erase("wheel_radius")
			c.erase("wheel_inertia")
			c.erase("spin_relaxation")
		if k == 0:
			c.damping_onset = 0.0
	return out


func _bad_table(surfaces: PackedFloat64Array) -> PackedFloat64Array:
	var out := surfaces.duplicate()
	out[4] = 2.0
	return out


func _bad_lake(lake: Dictionary) -> Dictionary:
	var out := lake.duplicate(true)
	out.water_level_down_m = "not a number"
	return out


# ---------------------------------------------------------------- aero

func _deflection_array(d: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])


func _aero_inputs(context: Dictionary, surfaces: PackedFloat64Array) -> Dictionary:
	var s := PackedFloat64Array()
	s.resize(13)
	s[0] = _rng.randf_range(-150.0, 150.0)
	s[1] = _rng.randf_range(-150.0, 150.0)
	var terrain_up: float = Terrain.sample_validated(s[0], s[1], surfaces)[0]
	var near := _rng.randf() < 0.6
	s[2] = -(terrain_up + (_rng.randf_range(0.02, 4.5) if near else _rng.randf_range(4.5, 120.0)))
	var attitude := _random_unit_quaternion() if _rng.randf() < 0.4 else \
		_small_rotation(M.q_from_axis_angle(M.v3(0.0, 0.0, 1.0), _rng.randf_range(-PI, PI)), 0.35)
	for k in 4:
		s[RB.ATT + k] = attitude[k]
	var speed: float = _rng.randf_range(0.0, 45.0)
	var mode := _rng.randf()
	var direction: PackedFloat64Array
	if mode < 0.45:
		# Attached cruise/climb/approach: the oracle (blend 0) and blended (0 < blend < 1) domain.
		var alpha := _rng.randf_range(-0.1, 0.13)
		var beta := _rng.randf_range(-0.08, 0.08)
		speed = _rng.randf_range(6.0, 35.0)
		for k in 3:
			s[RB.VEL + k] = speed * [cos(alpha) * cos(beta), sin(beta), sin(alpha) * cos(beta)][k]
			s[RB.RATE + k] = _rng.randf_range(-0.4, 0.4)
		var small := {elevator = _rng.randf_range(-0.12, 0.12), aileron_right = _rng.randf_range(-0.1, 0.1),
			aileron_left = _rng.randf_range(-0.1, 0.1), rudder = _rng.randf_range(-0.12, 0.12)}
		var lag: float = NAN if _rng.randf() < 0.4 else speed * _rng.randf_range(0.1, 0.7)
		var gu: float = terrain_up if near and _rng.randf() < 0.85 else NAN
		var still := M.v3(0.0, 0.0, 0.0) if _rng.randf() < 0.5 else M.v3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), 0.0)
		return {s = s, wind = still, rho = 1.225 if _rng.randf() < 0.5 else _rng.randf_range(0.9, 1.3), d = small,
			downwash = lag, ground_up = gu}
	if mode < 0.65:
		var alpha := _rng.randf_range(-0.6, 0.6)
		var beta := _rng.randf_range(-0.6, 0.6)
		direction = M.v3(cos(alpha) * cos(beta), sin(beta), sin(alpha) * cos(beta))
	elif mode < 0.85:
		direction = M.q_rotate(_random_unit_quaternion(), M.v3(1.0, 0.0, 0.0))
	elif mode < 0.93:
		speed = _rng.randf_range(0.0, 1e-3)
		direction = M.v3(1.0, 0.0, 0.0)
	else:
		speed = 0.0
		direction = M.v3(1.0, 0.0, 0.0)
	for k in 3:
		s[RB.VEL + k] = speed * direction[k]
	var wild := _rng.randf() < 0.3
	for k in 3:
		s[RB.RATE + k] = _rng.randf_range(-30.0, 30.0) if wild else _rng.randf_range(-3.0, 3.0)
	var wind := M.v3(0.0, 0.0, 0.0)
	if _rng.randf() < 0.6 and speed > 0.0:
		wind = M.v3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0), _rng.randf_range(-2.0, 2.0))
	var rho: float = 1.225 if _rng.randf() < 0.5 else _rng.randf_range(0.9, 1.3)
	var d := {elevator = _rng.randf_range(-0.45, 0.45), aileron_right = _rng.randf_range(-0.45, 0.45),
		aileron_left = _rng.randf_range(-0.45, 0.45), rudder = _rng.randf_range(-0.5, 0.5)}
	if _rng.randf() < 0.2:
		d = context.deflections.duplicate()
	var downwash: float = NAN if _rng.randf() < 0.3 else _rng.randf_range(-5.0, 30.0)
	var ground_up: float = terrain_up if near and _rng.randf() < 0.85 else (NAN if _rng.randf() < 0.7 else _rng.randf_range(-2.0, 2.0))
	var malformed := _rng.randf() < 0.08
	if malformed: # malformed / non-finite inputs
		match _rng.randi_range(0, 5):
			0: s[_rng.randi_range(0, 12)] = _special()
			1: wind[_rng.randi_range(0, 2)] = _special()
			2: rho = _special()
			3: d[["elevator", "aileron_right", "aileron_left", "rudder"][_rng.randi_range(0, 3)]] = _special()
			4: downwash = _special()
			5: ground_up = _special()
	return {s = s, wind = wind, rho = rho, d = d, downwash = downwash, ground_up = ground_up, malformed = malformed}


func _check_aero(context: Dictionary) -> void:
	var cases := [
		{name = "stik", model = context.model, states = _states},
		{name = "variant_twist_cm_body_side", model = _aero_variant_twist(context.model), states = _variant_states},
		{name = "variant_no_ground_effect", model = _aero_variant_no_ge(context.model), states = _variant_states},
		{name = "variant_uncoupled", model = _aero_variant_uncoupled(context.model), states = _variant_states},
		{name = "variant_legacy_horizontal", model = _aero_variant_legacy_tail(context.model), states = _variant_states},
	]
	# NK-3 breadth: validate each prepared catalog geometry with the actual flap, polar and tailless laws.
	# This qualifies components only; fleet.gd separately requires the production native stage on every tick.
	for id: String in Catalog.airplane_flyable_ids():
		if id == AIRCRAFT:
			continue
		var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(id))
		if not loaded.ok:
			_failures.append("catalog aero data failed: " + id)
			continue
		cases.append({name = id, model = loaded.model, states = _variant_states})
	for case: Dictionary in cases:
		var model: Dictionary = case.model
		var prepared: Dictionary = _native.prepare_aero(model)
		if not prepared.ok:
			_failures.append("prepare_aero %s failed: %s" % [case.name, prepared.error])
			continue
		# Only sessions with a free horizontal tail own the downwash-lag state.
		var legacy: bool = not model.surfaces.get("horizontal", {}).has("free_slope")
		for i in int(case.states):
			var input := _aero_inputs(context, context.surfaces)
			var s: PackedFloat64Array = input.s
			var d: Dictionary = input.d
			if model.get("capabilities", {}).get("flaps", "") == "simulated":
				d.flap = _rng.randf_range(0.0, deg_to_rad(float(model.flaps.max_angle_deg)))
				if i % 31 == 0:
					d.flap = _special()
			var downwash: float = NAN if legacy else input.downwash
			var ground_up: float = input.ground_up
			var air: Dictionary = Air.compute(s, input.wind, input.rho)
			var da := _deflection_array(d)
			var native_args := [s, input.wind, input.rho, da, downwash, ground_up]
			var reference: PackedFloat64Array = Aero.loads(s, air, d, model, input.rho, downwash, ground_up)
			_compare("aero_loads", reference, _native.aero_loads(s, input.wind, input.rho, da, downwash, ground_up), native_args)
			var ge: PackedFloat64Array = GroundEffect.factors(s, model, ground_up)
			_compare("air_compute", PackedFloat64Array([air.v_air[0], air.v_air[1], air.v_air[2], air.V, air.alpha, air.beta, air.qbar]),
				_native.aero_component(1, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			_compare("ground_effect_factors", ge, _native.aero_component(2, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			var blend: float = Aero.local_flow_weight(s, air, d, model, downwash, ge)
			_compare("local_flow_weight", PackedFloat64Array([blend]),
				_native.aero_component(3, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			_compare("global_loads", Aero._global_loads(s, air, d, model, input.rho, downwash, ge),
				_native.aero_component(4, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			_compare("local_loads", Aero._local_loads(s, air, d, model, input.rho, downwash, null, ge),
				_native.aero_component(5, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			_compare("wing_wake_velocity", PackedFloat64Array([Aero._wing_lift_coefficient_with(s, air, d, model, ge, true)]),
				_native.aero_component(6, s, input.wind, input.rho, da, downwash, ground_up), native_args)
			var group: String = "aero_" + str(case.name)
			_tally(group, "states")
			if input.get("malformed", false): _tally(group, "malformed")
			_tally(group, "blend_zero" if blend == 0.0 else ("blend_one" if blend == 1.0 else ("blend_partial" if is_finite(blend) else "blend_nan")))
			if not ge.is_empty(): _tally(group, "ground_effect_active")
			if not is_nan(downwash): _tally(group, "downwash_lag")
			for value: float in reference:
				if not is_finite(value):
					_tally(group, "nonfinite_reference")
					break


func _aero_variant_twist(model: Dictionary) -> Dictionary:
	var out := model.duplicate(true)
	out.surfaces.station_incidence = PackedFloat64Array([-0.03, -0.01, 0.02, 0.02, -0.01, -0.03])
	out.surfaces.wing_cm_ac = -0.06
	out.surfaces.body_cy_beta = -0.31
	out.surfaces.body_crossflow_area = 0.021
	return out


func _aero_variant_no_ge(model: Dictionary) -> Dictionary:
	var out := model.duplicate(true)
	out.envelope.erase("ground_effect")
	out.surfaces.erase("body_cn_beta")
	return out


func _aero_variant_uncoupled(model: Dictionary) -> Dictionary:
	var out := model.duplicate(true)
	out.envelope.erase("induced_map")
	return out


func _aero_variant_legacy_tail(model: Dictionary) -> Dictionary:
	var out := model.duplicate(true)
	out.envelope.erase("ground_effect")
	for key: String in ["free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "downwash_lag_length"]:
		out.surfaces.horizontal.erase(key)
	return out


# ---------------------------------------------------------------- D6 refusals

func _check_refusals(context: Dictionary) -> void:
	var model: Dictionary = context.model
	var flaps := model.duplicate(true)
	flaps.capabilities.flaps = "simulated"
	flaps.flaps = {max_angle_deg = 30.0}
	var tailless := model.duplicate(true)
	tailless.surfaces.tailless = {tau = 0.5}
	var polar := model.duplicate(true)
	polar.envelope.wing_polar = {positive = {}}
	var unknown := model.duplicate(true)
	unknown.surfaces.future_term = 0.1
	var oracle_only := model.duplicate(true)
	oracle_only.envelope = {}
	var gear_unknown: Dictionary = context.gear.duplicate(true)
	gear_unknown.contacts[0].future_tyre_term = 1.0
	var checks := {
		aero_flaps = _native.prepare_aero(flaps), aero_tailless = _native.prepare_aero(tailless),
		aero_wing_polar = _native.prepare_aero(polar), aero_unknown_surface_key = _native.prepare_aero(unknown),
		aero_empty_envelope = _native.prepare_aero(oracle_only),
		gear_unknown_contact_key = _native.prepare_ground(gear_unknown, context.surfaces, context.lake, true),
	}
	for name: String in checks:
		var result: Dictionary = checks[name]
		_report.refusals[name] = {refused = not result.ok, error = result.error}
		if result.ok:
			_failures.append("D6: native accepted " + name)
	# Leave the production context prepared.
	_native.prepare_aero(model)
	_ground_ready(_native, context.gear, context.surfaces, context.lake)


# ---------------------------------------------------------------- timing

func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	return sorted[n / 2] if n % 2 else 0.5 * (sorted[n / 2 - 1] + sorted[n / 2])


## Alternating reference/native rounds of `calls` calls each; µs per call (median over rounds).
func _pair(label: String, calls: int, reference: Callable, native: Callable, kernel_ns: float) -> void:
	for _w in 2:
		reference.call(); native.call()
	var ref_us := PackedFloat64Array()
	var nat_us := PackedFloat64Array()
	for round in _timing_rounds:
		for order in 2:
			var use_reference: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for _i in calls:
				if use_reference: reference.call()
				else: native.call()
			var us := float(Time.get_ticks_usec() - started) / calls
			if use_reference: ref_us.append(us)
			else: nat_us.append(us)
	var ref_median := _median(ref_us)
	var nat_median := _median(nat_us)
	_report.timing[label] = {calls_per_round = calls, rounds = _timing_rounds, reference_us = ref_median,
		native_binding_us = nat_median, native_kernel_us = kernel_ns / 1000.0,
		speedup_binding = ref_median / nat_median, speedup_kernel = ref_median / (kernel_ns / 1000.0),
		reference_rounds_us = ref_us, native_rounds_us = nat_us}


func _time_components(context: Dictionary) -> void:
	var model: Dictionary = context.model
	var gear: Dictionary = context.gear
	var surfaces: PackedFloat64Array = context.surfaces
	var lake: Dictionary = context.lake
	var s: PackedFloat64Array = context.rest
	var anchors: PackedFloat64Array = context.anchors
	var speeds: PackedFloat64Array = context.continuous
	var steer: float = context.steer
	var reference_wheels: Dictionary = Wheels.evaluate(s, gear, steer, surfaces, anchors, speeds, 0.0, false, lake)
	var native_wheels: Dictionary = _native.wheels_evaluate(s, steer, anchors, speeds, 0.0)
	_compare("timing_inputs", reference_wheels.loads, native_wheels.loads)
	_compare("timing_inputs", reference_wheels.derivative, native_wheels.derivative)
	_pair("wheels_evaluate_runway_rest", 2000,
		func() -> void: Wheels.evaluate(s, gear, steer, surfaces, anchors, speeds, 0.0, false, lake),
		func() -> void: _native.wheels_evaluate(s, steer, anchors, speeds, 0.0),
		_native.bench_wheels(s, steer, anchors, speeds, 0.0, 200000))
	var wind := M.v3(0.0, 0.0, 0.0)
	var rho: float = context.rho
	var d: Dictionary = context.deflections
	var da := _deflection_array(d)
	var ground_up: float = Terrain.sample_validated(s[0], s[1], surfaces)[0]
	var downwash: float = context.downwash
	var regimes := {
		aero_runway_rest_ground_effect = [s, ground_up, downwash],
		aero_cruise_15mps_out_of_ground_effect = [_cruise_state(s, 15.0, 0.02, -60.0), NAN, 7.0],
		aero_takeoff_12mps_ground_effect = [_cruise_state(s, 12.0, 0.12, s[2] - 0.3), ground_up, 9.0],
		aero_post_stall_local_strips = [_cruise_state(s, 14.0, 0.7, -60.0), NAN, 4.0],
	}
	for label: String in regimes:
		var row: Array = regimes[label]
		var state: PackedFloat64Array = row[0]
		var gu: float = row[1]
		var dw: float = row[2]
		var air: Dictionary = Air.compute(state, wind, rho)
		_report.timing[label + "_regime"] = {blend = Aero.local_flow_weight(state, air, d, model, dw, GroundEffect.factors(state, model, gu)),
			ground_effect = not GroundEffect.factors(state, model, gu).is_empty()}
		_compare("timing_inputs", Aero.loads(state, air, d, model, rho, dw, gu), _native.aero_loads(state, wind, rho, da, dw, gu))
		_pair(label, 1000,
			func() -> void: Aero.loads(state, Air.compute(state, wind, rho), d, model, rho, dw, gu),
			func() -> void: _native.aero_loads(state, wind, rho, da, dw, gu),
			_native.bench_aero(state, wind, rho, da, dw, gu, 100000))
	_pair("terrain_sample_runway", 5000,
		func() -> void: Terrain.sample_validated(s[0], s[1], surfaces, lake),
		func() -> void: _native.terrain_sample(s[0], s[1], true), NAN)


func _cruise_state(rest: PackedFloat64Array, speed: float, alpha: float, down: float) -> PackedFloat64Array:
	var s := rest.duplicate()
	var attitude := M.q_from_euler(0.3, alpha, 0.05)
	for k in 4:
		s[RB.ATT + k] = attitude[k]
	s[RB.POS + 2] = down
	s[RB.VEL] = speed * cos(alpha)
	s[RB.VEL + 1] = 0.3
	s[RB.VEL + 2] = speed * sin(alpha)
	s[RB.RATE] = 0.05
	s[RB.RATE + 1] = -0.1
	s[RB.RATE + 2] = 0.02
	return s
