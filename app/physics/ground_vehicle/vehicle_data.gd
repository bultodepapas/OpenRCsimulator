## Strict MT8 ground-vehicle data loader and deterministic experiment builder.
## The returned model is normalized SI data for VehicleDynamics; the source JSON
## retains provenance for every physical parameter.
extends RefCounted

const FORMAT := "openrc-ground-vehicle"
const VERSION := 1
const DEFAULT_PATH := "res://data/vehicles/ground/mt8_bisonte.json"
const KINDS := ["manual", "measured", "derived", "borrowed", "estimated"]
const TOP_KEYS := ["format", "version", "id", "name", "description", "drive_configuration", "geometry_source", "parameters"]
const GEOMETRY_SOURCE_KEYS := ["spec_path", "spec_sha256", "glb_path", "glb_sha256", "asset_frame", "physics_frame", "rights_status"]
const PARAMETER_UNITS := {
	"sprung_mass_kg": "kg",
	"unsprung_mass_kg": "kg",
	"sprung_inertia_kg_m2": "kg m^2",
	"wheel_spin_inertia_kg_m2": "kg m^2",
	"gravity_m_per_s2": "m/s^2",
	"corner_x_datum_frd_m": "m",
	"corner_y_datum_frd_m": "m",
	"corner_z_datum_frd_m": "m",
	"cg_forward_from_datum_m": "m",
	"cg_right_from_datum_m": "m",
	"cg_height_above_chassis_datum_m": "m",
	"arm_inner_offset_m": "m",
	"arm_length_m": "m",
	"wheel_center_rest_below_chassis_datum_m": "m",
	"tire_radius_m": "m",
	"suspension_stiffness_n_per_m": "N/m",
	"suspension_damping_n_s_per_m": "N s/m",
	"tire_stiffness_n_per_m": "N/m",
	"tire_damping_n_s_per_m": "N s/m",
	"tire_slip_relaxation_s": "s",
	"travel_droop_m": "m",
	"travel_bump_m": "m",
	"bump_stop_stiffness_n_per_m": "N/m",
	"bump_stop_damping_n_s_per_m": "N s/m",
	"droop_stop_stiffness_n_per_m": "N/m",
	"droop_stop_damping_n_s_per_m": "N s/m",
	"drive_torque_per_wheel_nm": "N m",
	"brake_torque_per_wheel_nm": "N m",
	"brake_front_fraction": "1",
	"reverse_torque_fraction": "1",
	"drive_torque_fade_rad_s": "rad/s",
	"rolling_resistance_coefficient": "1",
	"tire_friction_scale": "1",
	"max_steer_angle_rad": "rad",
	"steer_servo_natural_frequency_rad_s": "rad/s",
	"steer_servo_damping_ratio": "1",
	"hull_probe_centers_datum_frd_m": "m",
	"hull_probe_radii_m": "m",
	"hull_contact_stiffness_n_per_m": "N/m",
	"hull_contact_damping_n_s_per_m": "N s/m",
	"hull_contact_friction_scale": "1",
}
const ARRAY_SIZES := {
	"sprung_inertia_kg_m2": 6,
	"corner_x_datum_frd_m": 4,
	"corner_y_datum_frd_m": 4,
	"corner_z_datum_frd_m": 4,
	"hull_probe_centers_datum_frd_m": 18,
	"hull_probe_radii_m": 6,
}
const NONNEGATIVE_FIELDS := [
	"gravity_m_per_s2",
	"suspension_damping_n_s_per_m",
	"tire_damping_n_s_per_m",
	"bump_stop_damping_n_s_per_m",
	"droop_stop_damping_n_s_per_m",
]
const KNOB_KEYS := ["gravity_scale", "grip_scale", "spring_scale", "damper_scale", "ballast_kg", "ballast_height_m"]


static func load_default() -> Dictionary:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(PackedStringArray(["Cannot read ground vehicle data: %s (error %d)" % [path, FileAccess.get_open_error()]]))
	var source: String = file.get_as_text()
	file.close()
	var parsed := parse_text(source)
	if bool(parsed.get("ok", false)):
		var identity: Dictionary = parsed.identity.duplicate(true)
		identity.sha256 = FileAccess.get_sha256(path)
		parsed.identity = identity
	return parsed


static func parse_text(source: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _result(PackedStringArray([
			"Invalid ground vehicle JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		]))
	var parsed := validate(parser.data)
	if bool(parsed.get("ok", false)):
		var identity: Dictionary = parsed.identity.duplicate(true)
		identity.sha256 = _sha256_bytes(source.to_utf8_buffer())
		parsed.identity = identity
	return parsed


## Atomic strict validation: failures expose no partial model or datum geometry.
static func validate(data: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return _result(PackedStringArray(["Ground vehicle data must be an object"]))
	_exact_keys(data, TOP_KEYS, "vehicle", errors)
	if data.get("format") != FORMAT:
		errors.append("Unsupported ground vehicle format")
	if not _number(data.get("version")) or float(data.get("version", -1.0)) != float(VERSION):
		errors.append("Unsupported ground vehicle version")
	if not _text(data.get("id")) or not _text(data.get("name")) or not _text(data.get("description")):
		errors.append("Ground vehicle id, name, and description must be nonempty text")
	if data.get("drive_configuration") != "electric_4wd":
		errors.append("Only electric_4wd is supported by this ground-vehicle schema")
	_validate_geometry_source(data.get("geometry_source"), errors)
	var raw_parameters: Variant = data.get("parameters")
	if not raw_parameters is Dictionary:
		errors.append("vehicle.parameters must be an object")
		return _result(errors)
	# The optional brake split extends v1 without changing older descriptors:
	# absent means the original equal torque on all four wheels.
	var present_keys := PARAMETER_UNITS.keys()
	if not raw_parameters.has("brake_front_fraction"):
		present_keys.erase("brake_front_fraction")
	_exact_keys(raw_parameters, present_keys, "parameters", errors)
	var values: Dictionary = {"brake_front_fraction": 0.5}
	for key: String in PARAMETER_UNITS:
		if not raw_parameters.has(key):
			continue
		var quantity: Variant = raw_parameters[key]
		if not quantity is Dictionary:
			errors.append("parameters.%s must be a quantity object" % key)
			continue
		_exact_keys(quantity, ["value", "unit", "kind", "source"], "parameters." + key, errors)
		if quantity.get("unit") != PARAMETER_UNITS[key]:
			errors.append("parameters.%s requires unit %s" % [key, PARAMETER_UNITS[key]])
		if not quantity.get("kind") in KINDS:
			errors.append("parameters.%s has an unsupported provenance kind" % key)
		if not _text(quantity.get("source")):
			errors.append("parameters.%s requires a nonempty source" % key)
		var value: Variant = quantity.get("value")
		if ARRAY_SIZES.has(key):
			if not _finite_array(value, int(ARRAY_SIZES[key])):
				errors.append("parameters.%s must be a finite numeric array of length %d" % [key, ARRAY_SIZES[key]])
				continue
			values[key] = PackedFloat64Array(value)
		else:
			if not _number(value):
				errors.append("parameters.%s must be a finite number, not a boolean" % key)
				continue
			values[key] = float(value)
	if not errors.is_empty():
		return _result(errors)
	_validate_values(values, errors)
	if not errors.is_empty():
		return _result(errors)
	var datum_geometry := {
		"corner_x_datum_frd_m": values.corner_x_datum_frd_m.duplicate(),
		"corner_y_datum_frd_m": values.corner_y_datum_frd_m.duplicate(),
		"corner_z_datum_frd_m": values.corner_z_datum_frd_m.duplicate(),
		"hull_probe_centers_datum_frd_m": values.hull_probe_centers_datum_frd_m.duplicate(),
		"cg_forward_from_datum_m": values.cg_forward_from_datum_m,
		"cg_right_from_datum_m": values.cg_right_from_datum_m,
		"cg_height_above_chassis_datum_m": values.cg_height_above_chassis_datum_m,
	}
	var model := _make_model(values, datum_geometry)
	var identity := {
		"format": FORMAT,
		"version": str(VERSION),
		"id": str(data.id),
		"sha256": _sha256_text(JSON.stringify(data, "", true, true)),
	}
	return _result(errors, model, identity, datum_geometry)


## Applies a bounded, reproducible what-if configuration without changing the base.
## Ballast is a point mass at the chassis centerline and requested height. Its
## parallel-axis contribution, shifted sprung CG, wheel stations, and hull probes
## are all recomputed from chassis-datum geometry.
static func with_experiment(base_loaded: Dictionary, knobs: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if not bool(base_loaded.get("ok", false)) or not base_loaded.get("model") is Dictionary:
		return _result(PackedStringArray(["Experiment requires a successfully loaded base vehicle"]))
	_exact_keys(knobs, KNOB_KEYS, "experiment", errors)
	var settings: Dictionary = {}
	for key: String in KNOB_KEYS:
		var value: Variant = knobs.get(key)
		if not _number(value):
			errors.append("experiment.%s must be a finite number" % key)
			continue
		settings[key] = float(value)
	if not errors.is_empty():
		return _result(errors)
	_check_range(settings.gravity_scale, 0.1, 2.0, "gravity_scale", errors, true)
	_check_range(settings.grip_scale, 0.15, 2.0, "grip_scale", errors)
	_check_range(settings.spring_scale, 0.5, 2.0, "spring_scale", errors)
	_check_range(settings.damper_scale, 0.25, 2.0, "damper_scale", errors)
	_check_range(settings.ballast_kg, 0.0, 1.5, "ballast_kg", errors)
	_check_range(settings.ballast_height_m, 0.03, 0.35, "ballast_height_m", errors)
	if not errors.is_empty():
		return _result(errors)
	var identity_in: Variant = base_loaded.get("identity")
	var datum_in: Variant = base_loaded.get("datum_geometry")
	if not identity_in is Dictionary or not datum_in is Dictionary or not _text(identity_in.get("sha256")):
		return _result(PackedStringArray(["Experiment base is missing source identity or datum geometry"]))
	var model: Dictionary = base_loaded.model.duplicate(true)
	var datum: Dictionary = datum_in.duplicate(true)
	var old_mass: float = float(model.sprung_mass_kg)
	var added_mass: float = settings.ballast_kg
	var total_mass: float = old_mass + added_mass
	var old_cg_forward: float = float(datum.cg_forward_from_datum_m)
	var old_cg_right: float = float(datum.cg_right_from_datum_m)
	var old_cg_height: float = float(datum.cg_height_above_chassis_datum_m)
	var new_cg_forward: float = old_mass * old_cg_forward / total_mass
	var new_cg_right: float = old_mass * old_cg_right / total_mass
	var new_cg_height: float = (old_mass * old_cg_height + added_mass * settings.ballast_height_m) / total_mass
	var old_cg_frd := PackedFloat64Array([old_cg_forward, old_cg_right, -old_cg_height])
	var new_cg_frd := PackedFloat64Array([new_cg_forward, new_cg_right, -new_cg_height])
	var ballast_frd := PackedFloat64Array([0.0, 0.0, -settings.ballast_height_m])
	var inertia: PackedFloat64Array = model.sprung_inertia_kg_m2.duplicate()
	_add_parallel_axis(inertia, old_mass, _subtract3(old_cg_frd, new_cg_frd))
	_add_parallel_axis(inertia, added_mass, _subtract3(ballast_frd, new_cg_frd))
	model.sprung_inertia_kg_m2 = inertia
	model.sprung_mass_kg = total_mass
	model.cg_height_above_chassis_datum_m = new_cg_height
	model.gravity_m_per_s2 = float(model.gravity_m_per_s2) * settings.gravity_scale
	model.tire_friction_scale = float(model.tire_friction_scale) * settings.grip_scale
	model.suspension_stiffness_n_per_m = float(model.suspension_stiffness_n_per_m) * settings.spring_scale
	model.bump_stop_stiffness_n_per_m = float(model.bump_stop_stiffness_n_per_m) * settings.spring_scale
	model.droop_stop_stiffness_n_per_m = float(model.droop_stop_stiffness_n_per_m) * settings.spring_scale
	model.suspension_damping_n_s_per_m = float(model.suspension_damping_n_s_per_m) * settings.damper_scale
	model.bump_stop_damping_n_s_per_m = float(model.bump_stop_damping_n_s_per_m) * settings.damper_scale
	model.droop_stop_damping_n_s_per_m = float(model.droop_stop_damping_n_s_per_m) * settings.damper_scale
	var x_from_datum: PackedFloat64Array = datum.corner_x_datum_frd_m
	var y_from_datum: PackedFloat64Array = datum.corner_y_datum_frd_m
	var corner_x := PackedFloat64Array()
	var corner_y := PackedFloat64Array()
	for corner in 4:
		corner_x.append(x_from_datum[corner] - new_cg_forward)
		corner_y.append(y_from_datum[corner] - new_cg_right)
	model.corner_x_m = corner_x
	model.corner_y_m = corner_y
	var centers_from_datum: PackedFloat64Array = datum.hull_probe_centers_datum_frd_m
	var centers_relative := PackedFloat64Array()
	for probe in model.hull_probe_radii_m.size():
		var offset: int = probe * 3
		centers_relative.append(centers_from_datum[offset] - new_cg_forward)
		centers_relative.append(centers_from_datum[offset + 1] - new_cg_right)
		centers_relative.append(centers_from_datum[offset + 2] + new_cg_height)
	model.hull_probe_centers_frd_m = centers_relative
	datum.cg_forward_from_datum_m = new_cg_forward
	datum.cg_right_from_datum_m = new_cg_right
	datum.cg_height_above_chassis_datum_m = new_cg_height
	var settings_json: String = JSON.stringify(settings, "", true, true)
	var base_sha: String = str(identity_in.sha256)
	var payload := {
		"base_sha256": base_sha,
		"settings": settings,
		"model": model,
	}
	var digest: String = _sha256_text(JSON.stringify(payload, "", true, true))
	var base_id: String = str(identity_in.get("id", "vehicle"))
	var identity := {
		"format": FORMAT,
		"version": str(VERSION),
		"id": "%s-experiment-%s" % [base_id, digest.left(12)],
		"sha256": digest,
		"base_sha256": base_sha,
		"settings_json": settings_json,
	}
	var result := _result(errors, model, identity, datum)
	if bool(result.get("ok", false)):
		result["experiment"] = settings.duplicate(true)
	return result


static func _make_model(values: Dictionary, datum_geometry: Dictionary) -> Dictionary:
	var corners_x := PackedFloat64Array()
	var corners_y := PackedFloat64Array()
	for corner in 4:
		corners_x.append(values.corner_x_datum_frd_m[corner] - values.cg_forward_from_datum_m)
		corners_y.append(values.corner_y_datum_frd_m[corner] - values.cg_right_from_datum_m)
	var hull_centers := PackedFloat64Array()
	for probe in values.hull_probe_radii_m.size():
		var offset: int = probe * 3
		hull_centers.append(values.hull_probe_centers_datum_frd_m[offset] - values.cg_forward_from_datum_m)
		hull_centers.append(values.hull_probe_centers_datum_frd_m[offset + 1] - values.cg_right_from_datum_m)
		hull_centers.append(values.hull_probe_centers_datum_frd_m[offset + 2] + values.cg_height_above_chassis_datum_m)
	return {
		"sprung_mass_kg": values.sprung_mass_kg,
		"unsprung_mass_kg": values.unsprung_mass_kg,
		"sprung_inertia_kg_m2": values.sprung_inertia_kg_m2.duplicate(),
		"wheel_spin_inertia_kg_m2": values.wheel_spin_inertia_kg_m2,
		"gravity_m_per_s2": values.gravity_m_per_s2,
		"corner_x_m": corners_x,
		"corner_y_m": corners_y,
		"arm_inner_offset_m": values.arm_inner_offset_m,
		"arm_length_m": values.arm_length_m,
		"cg_height_above_chassis_datum_m": values.cg_height_above_chassis_datum_m,
		"wheel_center_rest_below_chassis_datum_m": values.wheel_center_rest_below_chassis_datum_m,
		"tire_radius_m": values.tire_radius_m,
		"suspension_stiffness_n_per_m": values.suspension_stiffness_n_per_m,
		"suspension_damping_n_s_per_m": values.suspension_damping_n_s_per_m,
		"tire_stiffness_n_per_m": values.tire_stiffness_n_per_m,
		"tire_damping_n_s_per_m": values.tire_damping_n_s_per_m,
		"tire_slip_relaxation_s": values.tire_slip_relaxation_s,
		"travel_droop_m": values.travel_droop_m,
		"travel_bump_m": values.travel_bump_m,
		"bump_stop_stiffness_n_per_m": values.bump_stop_stiffness_n_per_m,
		"bump_stop_damping_n_s_per_m": values.bump_stop_damping_n_s_per_m,
		"droop_stop_stiffness_n_per_m": values.droop_stop_stiffness_n_per_m,
		"droop_stop_damping_n_s_per_m": values.droop_stop_damping_n_s_per_m,
		"drive_torque_per_wheel_nm": values.drive_torque_per_wheel_nm,
		"brake_torque_per_wheel_nm": values.brake_torque_per_wheel_nm,
		"brake_front_fraction": values.brake_front_fraction,
		"reverse_torque_fraction": values.reverse_torque_fraction,
		"drive_torque_fade_rad_s": values.drive_torque_fade_rad_s,
		"rolling_resistance_coefficient": values.rolling_resistance_coefficient,
		"tire_friction_scale": values.tire_friction_scale,
		"max_steer_angle_rad": values.max_steer_angle_rad,
		"steer_servo_natural_frequency_rad_s": values.steer_servo_natural_frequency_rad_s,
		"steer_servo_damping_ratio": values.steer_servo_damping_ratio,
		"hull_probe_centers_frd_m": hull_centers,
		"hull_probe_radii_m": values.hull_probe_radii_m.duplicate(),
		"hull_contact_stiffness_n_per_m": values.hull_contact_stiffness_n_per_m,
		"hull_contact_damping_n_s_per_m": values.hull_contact_damping_n_s_per_m,
		"hull_contact_friction_scale": values.hull_contact_friction_scale,
	}


static func _validate_values(v: Dictionary, errors: PackedStringArray) -> void:
	for key in PARAMETER_UNITS:
		if ARRAY_SIZES.has(key):
			continue
		var value: float = float(v[key])
		if key in NONNEGATIVE_FIELDS:
			if value < 0.0:
				errors.append("parameters.%s must be nonnegative" % key)
		elif key in ["cg_forward_from_datum_m", "cg_right_from_datum_m"]:
			pass
		elif key in ["reverse_torque_fraction", "brake_front_fraction", "steer_servo_damping_ratio", "rolling_resistance_coefficient"]:
			if value < 0.0 or (key in ["reverse_torque_fraction", "brake_front_fraction"] and value > 1.0):
				errors.append("parameters.%s is outside its valid range" % key)
		elif key == "hull_contact_friction_scale":
			if value < 0.0 or value > 2.0:
				errors.append("parameters.hull_contact_friction_scale must be in [0, 2]")
		elif value <= 0.0:
			errors.append("parameters.%s must be positive" % key)
	var front_x: PackedFloat64Array = v.corner_x_datum_frd_m
	var side_y: PackedFloat64Array = v.corner_y_datum_frd_m
	var center_z: PackedFloat64Array = v.corner_z_datum_frd_m
	if not (front_x[0] > 0.0 and front_x[1] > 0.0 and front_x[2] < 0.0 and front_x[3] < 0.0):
		errors.append("corner stations must be ordered FL, FR, RL, RR with front forward and rear aft")
	if not (side_y[0] < 0.0 and side_y[1] > 0.0 and side_y[2] < 0.0 and side_y[3] > 0.0):
		errors.append("corner stations must use FRD right-positive lateral coordinates")
	for corner in 4:
		if center_z[corner] < 0.0:
			errors.append("corner wheel centers must be down from the chassis datum")
	var inertia: PackedFloat64Array = v.sprung_inertia_kg_m2
	var minor2: float = inertia[0] * inertia[1] - inertia[3] * inertia[3]
	var determinant: float = (
		inertia[0] * inertia[1] * inertia[2]
		+ 2.0 * inertia[3] * inertia[4] * inertia[5]
		- inertia[0] * inertia[5] * inertia[5]
		- inertia[1] * inertia[4] * inertia[4]
		- inertia[2] * inertia[3] * inertia[3]
	)
	if inertia[0] <= 0.0 or minor2 <= 0.0 or determinant <= 0.0:
		errors.append("sprung inertia tensor must be positive definite")
	if v.max_steer_angle_rad >= PI * 0.5:
		errors.append("max_steer_angle_rad must be below 90 degrees")
	if v.hull_probe_centers_datum_frd_m.size() != v.hull_probe_radii_m.size() * 3:
		errors.append("hull probe center and radius inventories must match")
	for radius in v.hull_probe_radii_m:
		if radius <= 0.0:
			errors.append("hull probe radii must be positive")
			break


static func _validate_geometry_source(raw: Variant, errors: PackedStringArray) -> void:
	if not raw is Dictionary:
		errors.append("vehicle.geometry_source must be an object")
		return
	_exact_keys(raw, GEOMETRY_SOURCE_KEYS, "geometry_source", errors)
	for key in ["spec_path", "glb_path", "rights_status"]:
		if not _text(raw.get(key)):
			errors.append("geometry_source.%s must be nonempty text" % key)
	for key in ["spec_sha256", "glb_sha256"]:
		if not _sha_text(raw.get(key)):
			errors.append("geometry_source.%s must be a 64-character SHA-256" % key)
	if raw.get("asset_frame") != {"right": "+X", "up": "+Y", "forward": "-Z"}:
		errors.append("geometry_source.asset_frame is unsupported")
	if raw.get("physics_frame") != {"forward": "+X", "right": "+Y", "down": "+Z"}:
		errors.append("geometry_source.physics_frame is unsupported")


static func _exact_keys(data: Dictionary, allowed: Array, path: String, errors: PackedStringArray) -> void:
	for key in allowed:
		if not data.has(key):
			errors.append("%s.%s is required" % [path, key])
	for key in data:
		if not key is String or not key in allowed:
			errors.append("Unknown field %s.%s" % [path, key])


static func _finite_array(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for item in value:
		if not _number(item):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _sha_text(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _check_range(value: float, minimum: float, maximum: float, name: String, errors: PackedStringArray, allow_zero_outside := false) -> void:
	if allow_zero_outside and value == 0.0:
		return
	if value < minimum or value > maximum:
		errors.append("experiment.%s must be in [%s, %s]%s" % [name, minimum, maximum, " or 0" if allow_zero_outside else ""])


static func _subtract3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func _add_parallel_axis(inertia: PackedFloat64Array, mass: float, r: PackedFloat64Array) -> void:
	var x: float = r[0]
	var y: float = r[1]
	var z: float = r[2]
	inertia[0] += mass * (y * y + z * z)
	inertia[1] += mass * (x * x + z * z)
	inertia[2] += mass * (x * x + y * y)
	inertia[3] -= mass * x * y
	inertia[4] -= mass * x * z
	inertia[5] -= mass * y * z


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _sha256_text(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


static func _result(
	errors: PackedStringArray,
	model: Dictionary = {},
	identity: Dictionary = {},
	datum_geometry: Dictionary = {}
) -> Dictionary:
	var okay := errors.is_empty()
	return {
		"ok": okay,
		"errors": errors,
		"model": model if okay else {},
		"identity": identity if okay else {},
		"datum_geometry": datum_geometry if okay else {},
	}
