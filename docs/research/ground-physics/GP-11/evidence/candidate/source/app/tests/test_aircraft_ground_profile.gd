extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Profile := preload("res://physics/aircraft_ground_profile.gd")
const Actuators := preload("res://physics/control_actuators.gd")
const Wheels := preload("res://physics/wheel_profiles.gd")
const Compliance := preload("res://physics/normal_compliance.gd")
const Contract := preload("res://physics/aircraft_contract.gd")
const Modules := preload("res://physics/aircraft_modules.gd")
const BASE_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
var _checks := 0
var _failures := 0
var _raw: Dictionary = {}
var _model: Dictionary = {}
var _ground: Dictionary = {}


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_raw = JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	var base := Data.validate_and_derive(_raw)
	_check("stock base remains valid without ground module", base.ok)
	if not base.ok:
		quit(1)
		return
	_model = base.model
	_ground = _ground_fixture()
	_test_resolution()
	_test_legacy_compatibility()
	_test_rejections()
	_test_classifier_and_launch_boundary()
	_test_rotor_partition()
	_test_steering()
	print("Aircraft ground profile: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "derived", source = "authoring contract fixture; no measured aircraft claim"}


func _normal() -> Dictionary:
	var raw := {format = Compliance.FORMAT}
	var values := {stiffness = 1000.0, compression_damping = 3.0, rebound_damping = 8.0,
		damping_onset = 0.002, stroke = 0.02, stop_stiffness = 3000.0,
		stop_scale = 0.01, stop_exponent = 3.0, stop_damping = 5.0}
	for key: String in values: raw[key] = _q(values[key], Compliance.SPECS[key][0])
	return raw


func _ground_fixture() -> Dictionary:
	var applied := Wheels.apply_to_model(_model)
	var supports: Array = []
	for index in _raw.landing_gear.contacts.size():
		var authored: Dictionary = _raw.landing_gear.contacts[index]
		var hub: Array = authored.position.value.duplicate()
		hub[2] += applied.model.landing_gear.contacts[index].wheel_radius
		supports.append({contact_id = authored.id, support_type = "wheel", hub_le = _q(hub, "m"),
			axle_le = _q([0.0, -1.0, 0.0], "1"), width_model = "zero_width", normal_profile_id = "normal_main"})
	return {format = Profile.FORMAT, law = Profile.COUPLED_LAW,
		capabilities = {support = "wheels", shape = "thin_ring", normal = "effective_leg_tire"},
		wheel_profile_ref = {format = Wheels.FORMAT, profile_id = _raw.id, profile_sha256 = applied.identity.profile_sha256},
		normal_profiles = [{id = "normal_main", parameters = _normal()}], supports = supports}


func _test_resolution() -> void:
	var before := var_to_bytes([_ground, _model])
	var result := Profile.resolve(_ground, _model)
	_check("valid authored ground profile resolves without launch permission", result.ok and not result.launch_available, str(result.get("errors", [])))
	if not result.ok: return
	_check("resolution leaves caller data unchanged", before == var_to_bytes([_ground, _model]))
	_check("immutable normalized identity is deterministic", result.profile.identity == Profile.resolve(_ground, _model).profile.identity)
	_check("normal resources stay separately identified", result.profile.normal_profiles.size() == 1
		and result.profile.supports[0].normal.identity == result.profile.normal_profiles.normal_main.identity)
	var wheel := Wheels.apply_to_model(_model)
	for index in result.profile.supports.size():
		var support: Dictionary = result.profile.supports[index]
		var raw: Dictionary = _ground.supports[index]
		var contact: Dictionary = result.model.landing_gear.contacts[support.contact_index]
		_check("stable contact ID resolves without a second hardware owner", support.contact_id == contact.id
			and not support.has("wheel_radius") and not support.has("wheel_inertia") and not support.has("brake_torque"))
		_check("hardware remains exactly the applied wheel profile", contact.wheel_radius == wheel.model.landing_gear.contacts[index].wheel_radius
			and contact.wheel_inertia == wheel.model.landing_gear.contacts[index].wheel_inertia
			and contact.brake_torque == wheel.model.landing_gear.contacts[index].brake_torque
			and contact.wheel_provenance == wheel.model.landing_gear.contacts[index].wheel_provenance)
		_check("LE hub converts once about derived inventory CG", support.hub_body == PackedFloat64Array([
			_model.cg_le[0] - raw.hub_le.value[0], raw.hub_le.value[1] - _model.cg_le[1], _model.cg_le[2] - raw.hub_le.value[2]]))
		_check("axle frame conversion has no translation", absf(support.axle_body[0]) < 1e-15 and support.axle_body[1] == -1.0 and absf(support.axle_body[2]) < 1e-15)
	var reordered := _ground.duplicate(true)
	reordered.supports.reverse()
	var mapped := Profile.resolve(reordered, _model)
	_check("source support order cannot rebind hardware by position", mapped.ok
		and mapped.profile.supports[0].contact_id == _ground.supports.back().contact_id
		and mapped.profile.supports[0].contact_index == _ground.supports.size() - 1)
	var renamed := _model.duplicate(true)
	renamed.id = "workshop_custom_aircraft"
	var selected := Profile.resolve(_ground, renamed)
	_check("explicit profile survives aircraft rename", selected.ok and selected.model.id == renamed.id
		and selected.model.wheel_profile.profile_id == _raw.id and selected.model.wheel_profile.aircraft_id == renamed.id)
	var changed := _ground.duplicate(true)
	changed.supports[0].hub_le.value[0] += 0.001
	_check("geometry affects profile identity", Profile.resolve(changed, _model).profile.identity != result.profile.identity)
	changed = _ground.duplicate(true)
	changed.normal_profiles[0].parameters.rebound_damping.value += 0.1
	_check("compliance affects profile identity", Profile.resolve(changed, _model).profile.identity != result.profile.identity)
	result.profile.supports[0].hub_body[0] += 100.0
	result.profile.normal_profiles.normal_main.values.stiffness = 1234.0
	_check("normalized output mutations cannot corrupt a future resolution", before == var_to_bytes([_ground, _model])
		and Profile.resolve(_ground, _model).profile.normal_profiles.normal_main.values.stiffness == 1000.0)


func _test_legacy_compatibility() -> void:
	var legacy := {format = Profile.FORMAT, law = Profile.LEGACY_LAW}
	var resolved := Profile.resolve(legacy, _model)
	_check("explicit legacy keeps the historical model byte-exact", resolved.ok and resolved.launch_available
		and var_to_bytes(resolved.model) == var_to_bytes(_model))
	var raw := _raw.duplicate(true)
	raw.ground = legacy
	var checked := Data.validate_and_derive(raw)
	_check("explicit legacy source validates", checked.ok, str(checked.get("errors", [])))
	if checked.ok:
		var compared: Dictionary = checked.model.duplicate(true)
		compared.data_sha256 = _model.data_sha256
		_check("explicit legacy changes source identity only", var_to_bytes(compared) == var_to_bytes(_model))
	var legacy_path := "user://ground_profile_legacy_%d.json" % OS.get_process_id()
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var file_loaded := Data.load_file(legacy_path)
	var stock_loaded := Data.load_file(BASE_PATH)
	_check("explicit legacy preserves file-boundary wheel profile behavior", file_loaded.ok and stock_loaded.ok
		and var_to_bytes(file_loaded.model.wheel_profile) == var_to_bytes(stock_loaded.model.wheel_profile))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	var model_before := var_to_bytes(Wheels.apply_to_model(_model))
	_check("default wheel-profile application remains deterministic", model_before == var_to_bytes(Wheels.apply_to_model(_model)))
	var classified := Modules.classify(_raw)
	_check("absent module adds no ground law or module", classified.ok
		and not classified.modules.has("aircraft.ground.thin_ring_compliance.v1")
		and classified.laws.has("gear.point_contacts.v1"))


func _test_rotor_partition() -> void:
	# Use an installed closed-shaft aircraft, not the Stik's prescribed RPM law.
	_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	var derived := Data.validate_and_derive(_raw)
	_check("partition fixture uses valid installed dynamic-shaft data", derived.ok, str(derived.get("errors", [])))
	if not derived.ok: return
	_model = derived.model
	_ground = _ground_fixture()
	var ground := _ground.duplicate(true)
	var applied := Wheels.apply_to_model(_model)
	var records: Array = [{rotor_id = _model.propulsion.id,
		transverse_inertia = _q(0.5 * _model.propulsion.rotor_inertia, "kg·m2")}]
	for contact: Dictionary in applied.model.landing_gear.contacts:
		records.append({rotor_id = contact.id, transverse_inertia = _q(0.5 * contact.wheel_inertia, "kg·m2")})
	ground.rotor_partition = {format = Profile.PARTITION_FORMAT, partition_id = "test_aggregate", reference_pose_id = "authored_hubs",
		kind = "estimated", source = "test-only thin rotors; no component inventory or measured inertia claim", center_model = "fixed_hubs", rotors = records}
	var before := var_to_bytes([ground, _model])
	var resolved := Profile.resolve(ground, _model)
	_check("explicit aggregate partition validates but does not authorize launch", resolved.ok and not resolved.launch_available, str(resolved.errors))
	if not resolved.ok: return
	var authored := _raw.duplicate(true)
	authored.ground = ground
	_check("partition passes closed runtime authoring structure", Contract.validate(authored).is_empty(), str(Contract.validate(authored)))
	var admitted := Data.validate_and_derive(authored)
	_check("prepared partition does not bypass session launch boundary", not admitted.ok and admitted.model.is_empty()
		and admitted.has("ground_profile") and admitted.ground_profile.has("rotor_system"), str(admitted.get("errors", [])))
	_check("aggregate reservation preserves locked tensor, mass and CG", resolved.profile.rotor_system.locked_reference == _model.inertia
		and resolved.model.mass_kg == _model.mass_kg and resolved.model.cg_le == _model.cg_le)
	_check("partition never mutates input", before == var_to_bytes([ground, _model]))
	_check("shaft comes first then hardware contact order", resolved.profile.rotor_order[0] == _model.propulsion.id
		and resolved.profile.rotor_order[1] == applied.model.landing_gear.contacts[0].id)
	var reverse := ground.duplicate(true)
	reverse.rotor_partition.rotors.reverse()
	reverse.supports.reverse()
	var reordered := Profile.resolve(reverse, _model)
	_check("record/source order cannot change tensor binding or rotor system identity", reordered.ok
		and reordered.profile.rotor_system.identity == resolved.profile.rotor_system.identity)
	_check("partition affects aircraft ground identity", resolved.profile.identity != Profile.resolve(_ground, _model).profile.identity)
	var altered := ground.duplicate(true)
	altered.rotor_partition.source += "; other source"
	_check("partition provenance is pinned", Profile.resolve(altered, _model).profile.rotor_system.identity != resolved.profile.rotor_system.identity)
	var mutations := [
		func(g: Dictionary) -> void: g.rotor_partition.kind = "measured",
		func(g: Dictionary) -> void: g.rotor_partition.center_model = "moving_hubs",
		func(g: Dictionary) -> void: g.rotor_partition.source = " ",
		func(g: Dictionary) -> void: g.rotor_partition.extra = 1,
		func(g: Dictionary) -> void: g.rotor_partition.rotors.pop_back(),
		func(g: Dictionary) -> void: g.rotor_partition.rotors.append(g.rotor_partition.rotors[0].duplicate(true)),
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].rotor_id = "unknown",
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].axial_inertia = _q(0.1, "kg·m2"),
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.value = NAN,
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.value = 0.0,
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.value = 1000.0,
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.value = _model.propulsion.rotor_inertia * 0.1,
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.unit = "kg",
		func(g: Dictionary) -> void: g.rotor_partition.rotors[0].transverse_inertia.source = "",
	]
	for index in mutations.size():
		altered = ground.duplicate(true)
		mutations[index].call(altered)
		_check("invalid/duplicate/unowned/nonphysical partition rejects %d" % index, not Profile.resolve(altered, _model).ok)
	var prescribed := _model.duplicate(true)
	prescribed.propulsion.erase("shaft")
	_check("prescribed propeller is not silently converted to a closed shaft", not Profile.resolve(ground, prescribed).ok)
	resolved.profile.rotor_partition.rotors[0].transverse_inertia.value = 1000.0
	resolved.profile.rotor_system.axial[0] = 1000.0
	_check("partition outputs are detached", before == var_to_bytes([ground, _model]))
	if OS.get_cmdline_user_args().has("--emit-partition-fixture"):
		var raw := _raw.duplicate(true)
		raw.ground = ground
		print("GROUND_PARTITION_FIXTURE=" + JSON.stringify(raw))


func _reject(label: String, mutate: Callable) -> void:
	var raw := _ground.duplicate(true)
	mutate.call(raw)
	var result := Profile.resolve(raw, _model)
	_check(label, not result.ok and result.model.is_empty() and not result.launch_available, str(result.get("errors", [])))


func _steering_fixture() -> Dictionary:
	var ground := _ground.duplicate(true)
	var parameters := {format = Actuators.PRESCRIBED_ANGLE_FORMAT, id = "nose_linkage"}
	var values := {angle_limit = 0.5, signed_full_scale_angle = -0.4, lag_time = 0.25,
		max_rate = 4.0, max_acceleration = 32.0}
	for key: String in values: parameters[key] = _q(values[key], Actuators.PRESCRIBED_ANGLE_SPECS[key][0])
	ground.steering_profiles = [{id = "nose_linkage", parameters = parameters}]
	ground.supports[0].steering_profile_id = "nose_linkage"
	ground.supports[0].steering_axis_le = _q([0.0, 0.6, 0.8], "1")
	return ground


func _test_steering() -> void:
	var ground := _steering_fixture()
	var before := var_to_bytes([ground, _model])
	var resolved := Profile.resolve(ground, _model)
	_check("explicit prescribed linkage resolves but does not authorize launch", resolved.ok and not resolved.launch_available, str(resolved.errors))
	if not resolved.ok: return
	var support: Dictionary = resolved.profile.supports[0]
	_check("steering axis converts once without translating hinge from hub", support.steering_axis_body == PackedFloat64Array([-0.0, 0.6, -0.8])
		and support.hub_body == Profile.resolve(_ground, _model).profile.supports[0].hub_body)
	_check("signed linkage and compiled response retain their sole owner", support.steering.identity == resolved.profile.steering_profiles.nose_linkage.identity
		and support.steering.values.signed_full_scale_angle == -0.4)
	_check("unsteered supports get no invented motion parameters", not resolved.profile.supports[1].has("steering")
		and not Profile.resolve(_ground, _model).profile.has("steering_profiles"))
	var response := Actuators.prescribed_angle_response(support.steering, PackedFloat64Array([0.1, 0.2]), 0.7)
	var motion := Actuators.fixed_axis_motion(support.axle_body, support.steering_axis_body, 0.1, 0.2, response.acceleration_radps2)
	_check("authored linkage directly supplies carrier kinematics", response.ok and motion.ok)
	_check("authoring does not mutate source or legacy hardware", before == var_to_bytes([ground, _model])
		and var_to_bytes(resolved.model) == var_to_bytes(Profile.resolve(_ground, _model).model))
	_check("steering resources affect ground identity", resolved.profile.identity != Profile.resolve(_ground, _model).profile.identity)
	var authored := _raw.duplicate(true)
	authored.ground = ground
	_check("steering passes closed runtime structural contract", Contract.validate(authored).is_empty(), str(Contract.validate(authored)))
	var changed := ground.duplicate(true)
	changed.supports.reverse()
	var reverse := Profile.resolve(changed, _model)
	_check("support reordering preserves linkage by contact ID", reverse.ok and reverse.profile.supports.back().steering.identity == support.steering.identity
		and reverse.profile.supports.back().contact_id == ground.supports[0].contact_id)
	changed = ground.duplicate(true)
	changed.supports[1].steering_profile_id = "nose_linkage"
	changed.supports[1].steering_axis_le = _q([0.0, 0.0, 1.0], "1")
	_check("multiple supports may share a resource with distinct installed axes", Profile.resolve(changed, _model).ok)
	var mutations := [
		func(g: Dictionary) -> void: g.steering_profiles = [],
		func(g: Dictionary) -> void: g.steering_profiles = {},
		func(g: Dictionary) -> void: g.steering_profiles[0] = 1,
		func(g: Dictionary) -> void: g.steering_profiles.append(g.steering_profiles[0].duplicate(true)),
		func(g: Dictionary) -> void: g.steering_profiles[0].id = "other_resource",
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.id = "other_resource",
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters = [],
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.max_rate.value = 3.0,
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.max_acceleration.value = 31.0,
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.signed_full_scale_angle.value = 0.6,
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.lag_time.value = NAN,
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.lag_time.unit = "rad",
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.lag_time.source = "",
		func(g: Dictionary) -> void: g.steering_profiles[0].parameters.unknown = 1,
		func(g: Dictionary) -> void: g.supports[0].erase("steering_axis_le"),
		func(g: Dictionary) -> void: g.supports[0].erase("steering_profile_id"),
		func(g: Dictionary) -> void: g.supports[0].steering_profile_id = "unknown_linkage",
		func(g: Dictionary) -> void: g.supports[0].steering_axis_le.value = [0, 0, 0],
		func(g: Dictionary) -> void: g.supports[0].steering_axis_le.value = [0, 2, 0],
		func(g: Dictionary) -> void: g.supports[0].steering_axis_le.value = [0, NAN, 0],
		func(g: Dictionary) -> void: g.supports[0].steering_axis_le.unit = "m",
		func(g: Dictionary) -> void: g.supports[0].steering_axis_le.source = " ",
		func(g: Dictionary) -> void:
			g.supports[0].erase("steering_profile_id")
			g.supports[0].erase("steering_axis_le"),
	]
	for index in mutations.size():
		changed = ground.duplicate(true)
		mutations[index].call(changed)
		_check("invalid/partial/unbound steering rejects %d" % index, not Profile.resolve(changed, _model).ok)
	resolved.profile.steering_profiles.nose_linkage.values.lag_time = 999.0
	support.steering_axis_body[2] = 1.0
	_check("linkage output detaches from authored data and future resolution", before == var_to_bytes([ground, _model])
		and Profile.resolve(ground, _model).profile.steering_profiles.nose_linkage.values.lag_time == 0.25)
	if OS.get_cmdline_user_args().has("--emit-steering-fixture"):
		print("GROUND_STEERING_FIXTURE=" + JSON.stringify(authored))


func _test_rejections() -> void:
	_reject("unknown law is never downgraded", func(g: Dictionary) -> void: g.law = "future_law")
	_reject("unknown format rejected", func(g: Dictionary) -> void: g.format = "openrc-aircraft-ground v9")
	_reject("unsupported capability rejected", func(g: Dictionary) -> void: g.capabilities.shape = "finite_tire")
	_reject("duplicate radius ownership rejected", func(g: Dictionary) -> void: g.supports[0].wheel_radius = _q(0.04, "m"))
	_reject("duplicate inertia ownership rejected", func(g: Dictionary) -> void: g.supports[0].wheel_inertia = _q(0.001, "kg·m2"))
	_reject("brake ownership remains wheel-profile-only", func(g: Dictionary) -> void: g.supports[0].brake_torque = _q(1.0, "N·m"))
	_reject("finite width unsupported explicitly", func(g: Dictionary) -> void: g.supports[0].width_model = "finite_width")
	_reject("skid support is not inferred", func(g: Dictionary) -> void: g.supports[0].support_type = "skid")
	_reject("duplicate physical support binding rejected", func(g: Dictionary) -> void: g.supports[1].contact_id = g.supports[0].contact_id)
	_reject("unbound contact rejected", func(g: Dictionary) -> void: g.supports.pop_back())
	_reject("unknown physical support rejected", func(g: Dictionary) -> void: g.supports[0].contact_id = "missing_support")
	_reject("unknown compliance resource rejected", func(g: Dictionary) -> void: g.supports[0].normal_profile_id = "missing_normal")
	_reject("unused compliance resource rejected", func(g: Dictionary) -> void: g.normal_profiles.append({id = "unused", parameters = _normal()}))
	_reject("duplicate compliance identity rejected", func(g: Dictionary) -> void: g.normal_profiles.append(g.normal_profiles[0].duplicate(true)))
	_reject("trailing-newline identity rejected", func(g: Dictionary) -> void: g.normal_profiles[0].id += "\n")
	_reject("nonunit axle rejected", func(g: Dictionary) -> void: g.supports[0].axle_le.value = [0, -2, 0])
	_reject("zero axle rejected", func(g: Dictionary) -> void: g.supports[0].axle_le.value = [0, 0, 0])
	_reject("nonfinite hub rejected", func(g: Dictionary) -> void: g.supports[0].hub_le.value[0] = NAN)
	_reject("wrong hub dimension rejected", func(g: Dictionary) -> void: g.supports[0].hub_le.value = [0, 0])
	_reject("wrong axle unit rejected", func(g: Dictionary) -> void: g.supports[0].axle_le.unit = "rad")
	_reject("missing hub provenance rejected", func(g: Dictionary) -> void: g.supports[0].hub_le.source = " ")
	_reject("normal resource is strictly validated", func(g: Dictionary) -> void: g.normal_profiles[0].parameters.stroke.unit = "s")
	_reject("negative stiffness rejected", func(g: Dictionary) -> void: g.normal_profiles[0].parameters.stiffness.value = -1)
	_reject("profile pin mismatch rejected", func(g: Dictionary) -> void: g.wheel_profile_ref.profile_sha256 = "0".repeat(64))
	_reject("missing explicit profile cannot become legacy fallback", func(g: Dictionary) -> void: g.wheel_profile_ref.profile_id = "not_installed")
	var missing := _model.duplicate(true)
	missing.erase("physical_identity")
	_check("coupled module requires authored physical identity", not Profile.resolve(_ground, missing).ok)
	var legacy := {format = Profile.FORMAT, law = Profile.LEGACY_LAW, supports = []}
	_check("legacy branch cannot hide inactive advanced parameters", not Profile.resolve(legacy, _model).ok)


func _test_classifier_and_launch_boundary() -> void:
	var raw := _raw.duplicate(true)
	raw.ground = _ground.duplicate(true)
	_check("new authoring module passes closed runtime structure", Contract.validate(raw).is_empty(), str(Contract.validate(raw)))
	var classified := Modules.classify(raw)
	_check("new law replaces point-law assertion", classified.ok and classified.modules.has("aircraft.ground.thin_ring_compliance.v1")
		and classified.laws.has("ground.coupled_thin_ring_compliance.v1") and not classified.laws.has("gear.point_contacts.v1"), str(classified))
	_check("unqualified module disables old similarity compiler operations", not classified.compiler_transforms.scale
		and not classified.compiler_transforms.weight and not classified.compiler_transforms.controls)
	var derived := Data.validate_and_derive(raw)
	_check("valid authoring cannot silently launch through legacy physics", not derived.ok and derived.model.is_empty()
		and "launch-unavailable" in " ".join(derived.errors) and derived.has("ground_profile"))
	var path := "user://ground_profile_contract_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var loaded := Data.load_file(path)
	_check("file boundary preserves coupled launch quarantine", not loaded.ok and loaded.model.is_empty() and loaded.has("ground_profile"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var invalid := raw.duplicate(true)
	invalid.ground.supports[0].unexpected = 1
	_check("unknown module physical fields rejected structurally", not Contract.validate(invalid).is_empty())
	invalid = raw.duplicate(true)
	invalid.ground.format = "unsupported"
	_check("classifier rejects unsupported optional format", not Modules.classify(invalid).ok)
	invalid = raw.duplicate(true)
	invalid.erase("physical_identity_version")
	_check("classifier requires explicit identity prerequisite", not Modules.classify(invalid).ok)
	if OS.get_cmdline_user_args().has("--emit-ground-fixture"):
		print("GROUND_PROFILE_FIXTURE=" + JSON.stringify(raw))
		print("GROUND_MODULE_CLASSIFICATION=" + JSON.stringify(classified))
