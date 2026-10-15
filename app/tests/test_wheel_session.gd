# GP-02: file-backed wheel profiles, appended state slots and exact replay boundaries.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const EXTRA := "res://data/aircraft/gp_extra_300s_60.json"
const P51 := "res://data/aircraft/p51d_mustang_120.json"
const AVANTI := "res://data/aircraft/sebart_avanti_s_a200.json"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	var profiled_data: Dictionary = AircraftData.load_file(STIK)
	_check("file-backed Stik has a wheel profile", profiled_data.ok and profiled_data.model.wheel_profile.status == "applied", str(profiled_data.errors))
	if not profiled_data.ok:
		quit(1)
		return
	var gear: Dictionary = profiled_data.model.landing_gear
	_check("profile follows declared gear contact order", gear.contacts.map(func(c: Dictionary) -> String: return c.name) == ["main_left", "main_right", "nose"])
	_check("Stik main wheel radius uses the sourced 3-inch diameter", is_equal_approx(gear.contacts[0].wheel_radius, 0.0381))
	_check("nose wheel radius is separately specified", is_equal_approx(gear.contacts[2].wheel_radius, 0.034925))
	_check("Crr radius reference preserves the largest wheel's aircraft calibration",
		gear.rolling_reference_radius == 0.0381 and gear.rolling_reference_radius_provenance.kind == "derived")
	_check("wheel inertia and spin relaxation carry provenance", gear.contacts[0].wheel_inertia > 0.0 and gear.contacts[0].spin_relaxation == 0.03 \
		and gear.contacts[0].wheel_provenance.wheel_inertia.kind == "estimated")
	_check("Stik brake availability is explicitly none", gear.contacts[0].brake_availability == "none" and gear.contacts[0].brake_torque == 0.0)
	var profile_source: Dictionary = WheelProfiles._read(WheelProfiles.DEFAULT_PATH)
	var bad_brakes: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	bad_brakes.contacts.main_left.brake_availability = "unspecified"
	bad_brakes.contacts.main_left.brake_torque.value = 5.0
	var brake_errors := PackedStringArray()
	WheelProfiles._validate_profile("wheel_profiles.json", "jensen-das-ugly-stik-60", bad_brakes, brake_errors)
	_check("positive brake torque requires explicitly available hardware", str(brake_errors).contains("positive brake torque requires"))
	_check("loader rejects positive torque with unspecified brake hardware",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", bad_brakes, "bad-brakes"))
	var negative_inertia: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	negative_inertia.contacts.main_left.wheel_inertia.value = -0.001
	_check("loader rejects negative wheel inertia",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", negative_inertia, "negative-inertia"))
	var wrong_unit: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	wrong_unit.contacts.main_left.wheel_radius.unit = "cm"
	_check("loader rejects wheel quantities with wrong units",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", wrong_unit, "wrong-unit"))
	var unknown_contact: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	unknown_contact.contacts.unlisted_wheel = unknown_contact.contacts.main_left.duplicate(true)
	_check("loader rejects profile contacts absent from landing gear",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", unknown_contact, "unknown-contact"))
	var unstable_profile: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	unstable_profile.contacts.main_left.spin_relaxation.value = 0.001
	_check("profile rejects spin relaxation too stiff for explicit RK4",
		not WheelProfiles._validate_physics_limits(profiled_data.model, unstable_profile).is_empty())
	_check("loader rejects time-constant step ratio above 0.25",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", unstable_profile, "too-fast"))
	var excessive_inertia: Dictionary = profile_source.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	excessive_inertia.contacts.main_left.wheel_inertia.value = 10.0
	_check("profile rejects wheel inertia that dominates aircraft effective mass",
		not WheelProfiles._validate_physics_limits(profiled_data.model, excessive_inertia).is_empty())
	_check("loader rejects summed wheel effective mass above ten percent",
		_apply_invalid_profile(profiled_data.model, profile_source.profiles, "jensen-das-ugly-stik-60", excessive_inertia, "heavy"))
	var extra: Dictionary = AircraftData.load_file(EXTRA)
	_check("Extra profile uses its distinct main and tail wheel sizes", extra.ok and extra.model.landing_gear.contacts[0].wheel_radius == 0.034925 \
		and extra.model.landing_gear.contacts[2].wheel_radius == 0.0127 \
		and extra.model.landing_gear.rolling_reference_radius == 0.034925 \
		and extra.model.landing_gear.contacts[2].brake_availability == "none")
	var p51: Dictionary = AircraftData.load_file(P51)
	_check("P-51 profile uses its geometry-derived wheel sizes and unspecified brakes", p51.ok \
		and p51.model.landing_gear.contacts[0].wheel_radius == 0.0857 \
		and p51.model.landing_gear.contacts[2].wheel_radius == 0.03975 \
		and p51.model.landing_gear.rolling_reference_radius == 0.0857 \
		and p51.model.landing_gear.contacts[0].brake_availability == "unspecified")
	for variant in ["synthetic_stik_electric_4s", "synthetic_stik_electric_4s_battery",
		"synthetic_stik_electric_6s", "synthetic_stik_electric_6s_battery"]:
		var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/%s.json" % variant)
		_check("synthetic Stik variant %s reuses explicit wheel profile" % variant, loaded.ok \
			and loaded.model.wheel_profile.status == "applied" and loaded.model.landing_gear.contacts.size() == 3)

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK))
	var memory: Dictionary = AircraftData.validate_and_derive(raw)
	_check("in-memory validation keeps legacy gear", memory.ok and not memory.model.landing_gear.contacts[0].has("wheel_radius") \
		and not memory.model.has("wheel_profile"))
	var avanti: Dictionary = AircraftData.load_file(AVANTI)
	_check("Avanti applies its declared retractable gear and sourced wheel profile", avanti.ok \
		and avanti.model.landing_gear.contacts.size() == 3 \
		and avanti.model.wheel_profile.status == "applied" \
		and avanti.model.landing_gear.contacts[0].wheel_radius == 0.04338 \
		and avanti.model.landing_gear.contacts[2].wheel_radius == 0.03532 \
		and avanti.model.landing_gear.contacts[0].brake_availability == "available" \
		and avanti.model.landing_gear.contacts[2].brake_availability == "none",
		str(avanti.get("model", {}).get("wheel_profile", {})))
	# No product aircraft is currently gearless. Exercise that route through a valid file-backed v2 fixture.
	var gearless_raw: Dictionary = raw.duplicate(true)
	gearless_raw.id = "wheel-profile-gearless-fixture"
	gearless_raw.erase("landing_gear")
	gearless_raw.capabilities.gear = "locked_up"
	var gearless_path := "user://wheel-profile-gearless-%d.json" % OS.get_process_id()
	var gearless_file := FileAccess.open(gearless_path, FileAccess.WRITE)
	_check("gearless v2 fixture can be written", gearless_file != null)
	if gearless_file != null:
		gearless_file.store_string(JSON.stringify(gearless_raw, "", true, true))
		gearless_file.close()
		var gearless: Dictionary = AircraftData.load_file(gearless_path)
		_check("file-backed gearless fixture preserves the explicit no-gear profile route", gearless.ok \
			and gearless.model.landing_gear.is_empty() and gearless.model.wheel_profile.status == "no_gear",
			str(gearless.errors))
		if gearless.ok:
			var no_wheels := Session.new()
			no_wheels.physics_enabled = false
			no_wheels.input_enabled = false
			no_wheels.setup(gearless_path)
			_check("gearless session has no invented wheel slots", no_wheels.aircraft.ok \
				and no_wheels.wheel_count() == 0 and no_wheels.sim.continuous.is_empty())
			no_wheels.free()
		_check("gearless fixture removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(gearless_path)) == OK)
	var fallback_raw: Dictionary = raw.duplicate(true)
	fallback_raw.id = "unlisted-wheel-profile-fixture"
	var fallback_path := "user://wheel-profile-fallback-%d.json" % OS.get_process_id()
	var fallback_file: FileAccess = FileAccess.open(fallback_path, FileAccess.WRITE)
	_check("unknown aircraft fixture can be written", fallback_file != null)
	if fallback_file != null:
		fallback_file.store_string(JSON.stringify(fallback_raw))
		fallback_file.close()
	var fallback: Dictionary = AircraftData.load_file(fallback_path)
	_check("unknown aircraft keeps legacy gear behavior", fallback.ok and fallback.model.wheel_profile.status == "legacy_fallback" \
		and not fallback.model.landing_gear.contacts[0].has("wheel_radius"))
	_check("unknown aircraft fixture removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(fallback_path)) == OK)

	var profiled: Node = Session.new()
	profiled.physics_enabled = false
	profiled.input_enabled = false
	profiled.setup(STIK)
	_check("profiled Stik appends one continuous slot per wheel", profiled.wheel_count() == 3 \
		and profiled.wheel_index() == 0 and profiled.sim.continuous.size() == 3)
	_check("reset initializes wheel rim speeds to rest", _all_zero(profiled.sim.continuous))
	var initial_meta: Dictionary = profiled.trace_meta()
	var layout: Array = JSON.parse_string(initial_meta.wheel_state_layout)
	_check("trace declares profiled wheel state and its indices", initial_meta.metadata_schema == "openrc-flight-meta v6" \
		and initial_meta.wheel_state_model == "relative-wheel-rim-speed-rk4-v1" \
		and layout.size() == 3 and layout[0].index == profiled.wheel_index())
	_check("trace records continuous start state and brake availability", JSON.parse_string(initial_meta.recording_start_continuous).size() == 3 \
		and JSON.parse_string(initial_meta.wheel_brakes).size() == 3)

	# A compressed, moving contact exercises the session's joint load/derivative callback.
	var touchdown: PackedFloat64Array = profiled.sim.state.duplicate()
	var main_contact: Dictionary = gear.contacts[0]
	touchdown[RB.POS + 2] = -float(main_contact.position[2]) + 0.02
	touchdown[RB.ATT] = 1.0
	for axis in 3:
		touchdown[RB.ATT + 1 + axis] = 0.0
		touchdown[RB.RATE + axis] = 0.0
	touchdown[RB.VEL] = 10.0
	touchdown[RB.VEL + 1] = 0.0
	touchdown[RB.VEL + 2] = 0.0
	var wheel_stage: Dictionary = profiled._wheel_evaluate(touchdown, profiled.sim.continuous, 0.0)
	_check("session stage appends wheel acceleration from contact slip", wheel_stage.has("derivative") \
		and wheel_stage.derivative.size() == profiled.sim.continuous.size() \
		and wheel_stage.derivative[0] > 0.0, str(wheel_stage))
	_check("session stage returns six-axis body loads", wheel_stage.has("loads") and wheel_stage.loads.size() == 6)
	_check("contact reset establishes a valid integrated wheel state", profiled.sim.reset(touchdown))
	profiled.sim.step()
	_check("RK4 advances session rim speed on a loaded moving wheel", profiled.sim.fault_reason.is_empty() \
		and profiled.sim.continuous[profiled.wheel_index()] > 0.0)
	profiled.reset()

	# Legacy in-memory models retain the old callback and exact airborne body arithmetic.
	var legacy: Node = Session.new()
	legacy.physics_enabled = false
	legacy.input_enabled = false
	legacy.setup(STIK)
	_check("in-memory replacement does not opt into wheel state", legacy._apply(memory) and legacy.wheel_count() == 0)
	legacy.reset()
	var parity := true
	for _tick in 8:
		profiled.sim.step()
		legacy.sim.step()
		parity = parity and var_to_bytes(profiled.sim.state) == var_to_bytes(legacy.sim.state)
	_check("airborne body integration is byte-identical with omitted wheel forces", parity)
	_check("airborne wheel speeds stay dormant", _all_zero(profiled.sim.continuous))

	# Rim speeds are part of the continuous checkpoint payload and are restored exactly.
	var checkpoint: Dictionary = profiled.checkpoint()
	_check("checkpoint records wheel layout and profile provenance", checkpoint.has("wheel_state_layout") \
		and checkpoint.has("wheel_profile_sha256") and checkpoint.has("wheel_profile_input_sha256") \
		and checkpoint.simulation.continuous.size() == 3)
	if checkpoint.is_empty():
		profiled.free()
		legacy.free()
		quit(1)
		return
	var seeded: Dictionary = checkpoint.duplicate(true)
	seeded.simulation.continuous = PackedFloat64Array([1.25, -0.5, 3.0])
	var restored: Node = Session.new()
	restored.physics_enabled = false
	restored.input_enabled = false
	restored.setup(STIK)
	_check("matching profile restores appended wheel state", restored.restore_checkpoint(seeded) \
		and var_to_bytes(restored.sim.continuous) == var_to_bytes(seeded.simulation.continuous))
	var wrong_profile: Dictionary = seeded.duplicate(true)
	wrong_profile.wheel_profile_sha256 = "0".repeat(64)
	var before_reject: PackedByteArray = var_to_bytes(restored.sim.checkpoint())
	_check("mismatched profile is rejected without changing simulation", not restored.restore_checkpoint(wrong_profile) \
		and var_to_bytes(restored.sim.checkpoint()) == before_reject)
	restored.reset()
	_check("reset clears all wheel rim-speed slots", _all_zero(restored.sim.continuous))

	for node in [profiled, legacy, restored]:
		node.free()
	print("GP-02 wheel session: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _all_zero(values: PackedFloat64Array) -> bool:
	for value in values:
		if value != 0.0:
			return false
	return true


func _apply_invalid_profile(model: Dictionary, profiles: Dictionary, aircraft_id: String, profile: Dictionary, label: String) -> bool:
	var root := {"format": WheelProfiles.FORMAT, "profiles": profiles.duplicate(true)}
	root.profiles[aircraft_id] = profile
	var path := "user://wheel-profile-invalid-%s-%d.json" % [label, OS.get_process_id()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(root))
	file.close()
	var result: Dictionary = WheelProfiles.apply_to_model(model, path)
	var removed: bool = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	return not result.ok and removed
