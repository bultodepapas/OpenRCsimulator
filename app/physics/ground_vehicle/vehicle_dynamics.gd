extends RefCounted
## Six-DOF sprung body, four moving hubs, four axial wheel rotors, and a
## second-order steering servo. This custom float64 kernel does not use the
## Godot rigid-body solver. It is a compact game-simulation model, not a
## calibrated tire or suspension model for a specific physical truck.
##
## State begins with the shared NED/FRD rigid-body contract, then appends
## compression-positive arm travel, travel rates, positive-forward wheel
## spin rates, wheel angles, and the positive-right steering servo state.
## Unsprung hubs follow the finite-length arm curve; their translational
## kinetic energy is included in a coupled generalized mass matrix, including
## Coriolis/centrifugal terms. Wheel axial inertia is coupled to body rate and
## relative spin exactly at the axle. Suspension and travel-stop forces are
## internal generalized loads; ground tire/hull forces are external loads.
##
## Tires are point-probed compliant spheres. Tangential tire and hull forces
## use a combined Coulomb circle with a mobility-metric projected Gauss-Seidel acceleration
## constraint and finite slip-relaxation target. This provides low-speed
## sticking and wheelspin without the engine contact solver. The model uses
## parallel front steering, equal four-wheel drive torque, no differential
## gearing dynamics, and axial-only wheel inertia. Terrain callbacks must be
## deterministic and return a unit outward/up normal in NED.

const M := preload("res://physics/math3d.gd")
const Integrator := preload("res://physics/integrator.gd")
const WetPhysics := preload("res://physics/ground_vehicle/vehicle_environment.gd")

const POS := 0
const VEL := 3
const ATT := 6
const RATE := 10
const TRAVEL := 13
const TRAVEL_RATE := 17
const WHEEL_SPIN := 21
const WHEEL_ANGLE := 25
const STEER := 29
const STEER_RATE := 30
const STATE_SIZE := 31
const CORNER_COUNT := 4
const GENERALIZED_SIZE := 14
const SOLVER_VERSION := "openrc-ground-vehicle-dynamics-rk4-v5"
const SUBSTEPS_PER_TICK := 1
const WALL_MAX_INTEGRATION_STEP_S := 1.0 / 120.0
const FRICTION_SWEEPS := 128
const FRICTION_CONVERGENCE_FORCE_TOLERANCE_N := 0.000001
const BRAKE_CONVERGENCE_TORQUE_TOLERANCE_N_M := 0.000001
const MIN_SLIP_SPEED_M_PER_S := 0.05
const MATRIX_PIVOT_RELATIVE_TOLERANCE := 1.0e-12
const MAX_WALL_CONTACT_BOXES := 8
const WALL_FRICTION_REGULARIZATION_M_PER_S := 0.05
const BACKEND_GDSCRIPT_REFERENCE := "gdscript_reference"
const BACKEND_NATIVE := "native"
const BACKEND_ABI_VERSION := 1
const BACKEND_NATIVE_VERSION := "openrc-ground-vehicle-native-evaluate-v3"
const NATIVE_EXTENSION_PATH := "res://native/ground_vehicle/openrc_ground_vehicle.gdextension"
const NATIVE_RECEIPT_PATH := "res://native/ground_vehicle/build-receipt.json"

static var _backend_identity_cache: Dictionary = {}
static var _reference_backend_identity_cache: Dictionary = {}
static var _native_backend_instance: Object
static var _native_extension_checked := false
## This selector exists only for isolated debug/test processes. It lets the
## production adapter run both implementations against identical inputs while
## Session's frozen-backend guard still rejects an in-session switch.
static var _backend_override_for_tests := ""

const STATE_LAYOUT := [
	"north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
	"qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
	"travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
	"travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
	"wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
	"wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
	"steering_right_rad", "steering_rate_right_rad_per_s",
]

const DEFAULT_CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


## Return the cached identity for the active solver implementation. The reference
## backend has no native artifact or toolchain receipt; native builds replace this
## through the app loader and provide their receipt hashes here.
static func backend_identity() -> Dictionary:
	if _backend_override_for_tests == BACKEND_GDSCRIPT_REFERENCE:
		return _reference_backend_identity()
	if _backend_identity_cache.is_empty():
		var native := _load_native_backend()
		if native != null:
			var candidate: Variant = native.call("backend_identity")
			if _native_identity_is_compatible(candidate):
				_backend_identity_cache = candidate.duplicate(true)
		if _backend_identity_cache.is_empty():
			_backend_identity_cache = _reference_backend_identity()
	return _backend_identity_cache.duplicate(true)


## Explicit process-local test switch. It is disabled in release builds and
## cannot select native unless the pinned native artifact passes the real loader.
## Clearing it restores automatic selection. This does not alter a live Session;
## its backend identity guard is expected to reject a switch on the next action.
static func set_backend_override_for_tests(backend: String) -> bool:
	if not OS.is_debug_build():
		return false
	if backend not in ["", BACKEND_GDSCRIPT_REFERENCE, BACKEND_NATIVE]:
		return false
	if backend == BACKEND_NATIVE and _load_native_backend() == null:
		return false
	_backend_override_for_tests = backend
	_backend_identity_cache.clear()
	return true


static func _reference_backend_identity() -> Dictionary:
	if not _reference_backend_identity_cache.is_empty():
		return _reference_backend_identity_cache.duplicate(true)
	var source_path := "res://physics/ground_vehicle/vehicle_dynamics.gd"
	var implementation := _reference_implementation_artifact(source_path)
	_reference_backend_identity_cache = {
		"backend": BACKEND_GDSCRIPT_REFERENCE,
		"backend_version": SOLVER_VERSION,
		"abi_version": BACKEND_ABI_VERSION,
		"solver_version": SOLVER_VERSION,
		# The hash is of the source script in editor/source builds, or of its exact
		# remapped .gdc payload in stripped exports. The kind disambiguates them.
		"source_sha256": str(implementation.get("sha256", "")),
		"implementation_artifact_kind": str(implementation.get("kind", "")),
		"toolchain_sha256": "",
		"binary_sha256": "",
	}
	return _reference_backend_identity_cache.duplicate(true)


static func _reference_implementation_artifact(source_path: String) -> Dictionary:
	if FileAccess.file_exists(source_path):
		var source_sha256 := FileAccess.get_sha256(source_path)
		if _sha256_is_valid(source_sha256):
			return {"sha256": source_sha256, "kind": "gdscript_source"}
	var remap_path := source_path + ".remap"
	if not FileAccess.file_exists(remap_path):
		return {"sha256": "", "kind": ""}
	var remap := ConfigFile.new()
	if remap.load(remap_path) != OK:
		return {"sha256": "", "kind": ""}
	var target_value: Variant = remap.get_value("remap", "path", "")
	if typeof(target_value) != TYPE_STRING or not str(target_value).begins_with("res://"):
		return {"sha256": "", "kind": ""}
	var bytecode_path := str(target_value)
	if not FileAccess.file_exists(bytecode_path):
		return {"sha256": "", "kind": ""}
	var bytecode_sha256 := FileAccess.get_sha256(bytecode_path)
	if not _sha256_is_valid(bytecode_sha256):
		return {"sha256": "", "kind": ""}
	return {"sha256": bytecode_sha256, "kind": "gdscript_remapped_bytecode"}


static func _load_native_backend() -> Object:
	if _native_extension_checked:
		return _native_backend_instance
	_native_extension_checked = true
	var binary_paths := _native_binary_candidate_paths()
	if binary_paths.is_empty() or not FileAccess.file_exists(NATIVE_EXTENSION_PATH) \
			or not FileAccess.file_exists(NATIVE_RECEIPT_PATH):
		return null
	var receipt_file := FileAccess.open(NATIVE_RECEIPT_PATH, FileAccess.READ)
	if receipt_file == null:
		return null
	var receipt_value: Variant = JSON.parse_string(receipt_file.get_as_text())
	receipt_file.close()
	var receipt := _native_platform_receipt(receipt_value)
	if receipt.is_empty() or not _native_binary_matches_receipt(binary_paths, str(receipt.binary_sha256)):
		return null
	if not GDExtensionManager.is_extension_loaded(NATIVE_EXTENSION_PATH):
		var load_status: int = GDExtensionManager.load_extension(NATIVE_EXTENSION_PATH)
		if load_status != 0 and load_status != 2:
			return null
	if not ClassDB.class_exists("OpenRCGroundVehicleNative"):
		return null
	var candidate: Object = ClassDB.instantiate("OpenRCGroundVehicleNative")
	if candidate == null or not candidate.has_method("evaluate") or not candidate.has_method("backend_identity"):
		return null
	var identity: Variant = candidate.call("backend_identity")
	if not _native_identity_is_compatible(identity) or not _native_identities_match(identity, receipt):
		return null
	_native_backend_instance = candidate
	return _native_backend_instance


## Optional exact bathymetry accelerator. Empty means use the shared GDScript sampler.
## The reference override must cover road sampling as well as the dynamics evaluator.
static func sample_lake_terrain(lake: Dictionary, north: float, east: float, base: PackedFloat64Array) -> PackedFloat64Array:
	if _backend_override_for_tests == BACKEND_GDSCRIPT_REFERENCE: return PackedFloat64Array()
	var native := _load_native_backend()
	if native == null or not native.has_method("sample_lake_terrain"): return PackedFloat64Array()
	var result: Variant = native.call("sample_lake_terrain", lake, north, east, base)
	if typeof(result) != TYPE_PACKED_FLOAT64_ARRAY or result.size() != 4 or not _finite_array(result):
		return PackedFloat64Array()
	return result



static func _native_binary_candidate_paths() -> PackedStringArray:
	var binary_name := ""
	match OS.get_name():
		"Windows": binary_name = "openrc_ground_vehicle.dll"
		"Linux": binary_name = "libopenrc_ground_vehicle.so"
		_: return PackedStringArray()
	var paths := PackedStringArray([
		"res://native/ground_vehicle/" + binary_name,
	])
	var executable_directory := OS.get_executable_path().get_base_dir()
	for relative_path in [
		"native/" + binary_name,
		"native/ground_vehicle/" + binary_name,
		binary_name,
	]:
		var candidate := executable_directory.path_join(relative_path)
		if not paths.has(candidate):
			paths.append(candidate)
	return paths


static func _native_binary_matches_receipt(paths: PackedStringArray, expected_sha256: String) -> bool:
	for path in paths:
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected_sha256:
			return true
	return false


static func _native_platform_receipt(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.get("format") != "openrc-ground-vehicle-native-receipt" \
			or value.get("backend") != BACKEND_NATIVE or value.get("backend_version") != BACKEND_NATIVE_VERSION \
			or int(value.get("abi_version", 0)) != BACKEND_ABI_VERSION \
			or value.get("solver_version") != SOLVER_VERSION:
		return {}
	var platform := "windows" if OS.get_name() == "Windows" else "linux" if OS.get_name() == "Linux" else ""
	var platforms: Variant = value.get("platforms")
	if platform.is_empty() or typeof(platforms) != TYPE_DICTIONARY:
		return {}
	var record: Variant = platforms.get(platform)
	if typeof(record) != TYPE_DICTIONARY or record.get("backend") != BACKEND_NATIVE \
			or record.get("backend_version") != BACKEND_NATIVE_VERSION \
			or int(record.get("abi_version", 0)) != BACKEND_ABI_VERSION \
			or record.get("solver_version") != SOLVER_VERSION:
		return {}
	for key in ["source_sha256", "toolchain_sha256", "binary_sha256"]:
		if not _sha256_is_valid(record.get(key)):
			return {}
	return record


static func _native_identity_is_compatible(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.get("backend") != BACKEND_NATIVE \
			or value.get("backend_version") != BACKEND_NATIVE_VERSION \
			or int(value.get("abi_version", 0)) != BACKEND_ABI_VERSION \
			or value.get("solver_version") != SOLVER_VERSION:
		return false
	for key in ["source_sha256", "toolchain_sha256", "binary_sha256"]:
		if not _sha256_is_valid(value.get(key)):
			return false
	return true


static func _native_identities_match(left: Dictionary, right: Dictionary) -> bool:
	for key in ["backend", "backend_version", "abi_version", "solver_version",
			"source_sha256", "toolchain_sha256", "binary_sha256"]:
		if key == "abi_version":
			var left_abi: Variant = left.get(key)
			var right_abi: Variant = right.get(key)
			if typeof(left_abi) not in [TYPE_INT, TYPE_FLOAT] \
					or typeof(right_abi) not in [TYPE_INT, TYPE_FLOAT] \
					or int(left_abi) != int(right_abi):
				return false
			continue
		if str(left.get(key, "")) != str(right.get(key, "")):
			return false
	return true


static func _sha256_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var digest := str(value)
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true


## Construct a level, zero-speed supported state for a spawn point. Spawns must
## lie on a locally level, flat start patch; the function refuses unequal
## corner heights/normals instead of hiding an unsupported initial impulse.
static func initialize(
	model: Dictionary,
	road: Callable,
	north_m: float = 0.0,
	east_m: float = 0.0,
) -> Dictionary:
	if not _valid_model(model) or not road.is_valid() or not is_finite(north_m) or not is_finite(east_m):
		return _failure("Invalid model, road callback, or spawn position")
	var static_travel := _static_travel(model)
	var tire_radius := float(model["tire_radius_m"])
	var tire_stiffness := float(model["tire_stiffness_n_per_m"])
	var unsprung_mass := float(model["unsprung_mass_kg"])
	var gravity := float(model["gravity_m_per_s2"])
	var sprung_mass := float(model["sprung_mass_kg"])
	var wheel_load := (sprung_mass / 4.0 + unsprung_mass) * gravity
	var tire_compression := wheel_load / tire_stiffness if gravity > 0.0 else 0.0
	var patch := _check_static_spawn_patch(model, road, north_m, east_m, 0.0, static_travel)
	if not bool(patch["ok"]):
		return _failure(str(patch["error"]))
	var mean_height := float(patch["mean_height_m"])
	var cg_height := (
		mean_height + tire_radius - tire_compression
		+ float(model["cg_height_above_chassis_datum_m"])
		+ float(model["wheel_center_rest_below_chassis_datum_m"])
		- static_travel
	)
	var pose := {
		"id": "default",
		"north_m": north_m,
		"east_m": east_m,
		"heading_rad": 0.0,
		"vehicle_up_m": cg_height,
	}
	var state := make_state(model, pose, road)
	if state.is_empty():
		return _failure("Spawn equilibrium could not be constructed")
	return {"ok": true, "state": state, "error": ""}


## Construct a supported state at an explicit course pose. `vehicle_up_m` is
## the sprung-CG altitude, heading is clockwise/right-positive from north, and
## the initial patch must be level and flat for the tire/spring preload used.
static func make_state(model: Dictionary, pose: Dictionary, road: Callable) -> PackedFloat64Array:
	if not _valid_model(model) or not road.is_valid() or not _valid_pose(pose):
		return PackedFloat64Array()
	var north_m := float(pose["north_m"])
	var east_m := float(pose["east_m"])
	var vehicle_up_m := float(pose["vehicle_up_m"])
	var heading_rad := float(pose["heading_rad"])
	var travel := _static_travel(model)
	var patch := _check_static_spawn_patch(
		model, road, north_m, east_m, heading_rad, travel,
	)
	if not bool(patch["ok"]):
		return PackedFloat64Array()
	var state := PackedFloat64Array()
	state.resize(STATE_SIZE)
	state[POS] = north_m
	state[POS + 1] = east_m
	state[POS + 2] = -vehicle_up_m
	var attitude := M.q_from_euler(heading_rad, 0.0, 0.0)
	for i in 4:
		state[ATT + i] = attitude[i]
	for corner in CORNER_COUNT:
		state[TRAVEL + corner] = travel
	return state


## Zero-speed placement on a mildly uneven runway. Fit each tire to the actual
## surface with gravity preload; a small physical settling transient is allowed.
## This is not a static-equilibrium solver for arbitrary slopes/obstacles.
## The supplied altitude is replaced by terrain support and the model's CG offset.
## No terrain is flattened and the existing flat-course initializer is unchanged.
static func make_terrain_state(model: Dictionary, pose: Dictionary, road: Callable) -> PackedFloat64Array:
	if not _valid_model(model) or not _valid_pose(pose) or not road.is_valid():
		return PackedFloat64Array()
	var state := PackedFloat64Array()
	state.resize(STATE_SIZE)
	state[POS] = float(pose.north_m)
	state[POS + 1] = float(pose.east_m)
	var attitude := M.q_from_euler(float(pose.heading_rad), 0.0, 0.0)
	for i in 4: state[ATT + i] = attitude[i]
	var travel := _static_travel(model)
	for i in CORNER_COUNT: state[TRAVEL + i] = travel
	var gravity := float(model.gravity_m_per_s2)
	var normal_distance := float(model.tire_radius_m) - (float(model.sprung_mass_kg) / 4.0 + float(model.unsprung_mass_kg)) * gravity / float(model.tire_stiffness_n_per_m)
	if normal_distance <= 0.0:
		return PackedFloat64Array()
	var datum := float(model.cg_height_above_chassis_datum_m) + float(model.wheel_center_rest_below_chassis_datum_m)
	# Suspension motion changes the hub's lateral coordinate. Iterate its exact
	# finite-arm geometry rather than sampling at an unrelated fixed wheel station.
	for iteration in 12:
		var geometry := _corner_geometry(state, model, 0.0, 0.0, 0.0)
		if not geometry.ok: return PackedFloat64Array()
		var hub_heights := PackedFloat64Array()
		var mean_height := 0.0
		for corner in CORNER_COUNT:
			var offset := M.q_rotate(attitude, geometry.hub_position_body[corner])
			var checked := _sample_surface(road, state[POS] + offset[0], state[POS + 1] + offset[1])
			if not checked.ok: return PackedFloat64Array()
			var surface: Dictionary = checked.surface
			var normal: PackedFloat64Array = surface.normal_ned
			if normal[2] > -0.98: return PackedFloat64Array()
			var height := float(surface.height_m) + normal_distance / -normal[2]
			hub_heights.append(height)
			mean_height += height / float(CORNER_COUNT)
		var cg_up := mean_height + datum - travel
		if gravity == 0.0:
			# Without weight there is no spring/tire preload. Place the relaxed
			# suspension just clear of the highest tire patch, with no stored energy.
			var highest := hub_heights[0]
			for height in hub_heights: highest = maxf(highest, height)
			state[POS + 2] = -(highest + datum + 1.0e-9)
			return state if _finite_array(state) else PackedFloat64Array()
		var change := absf(state[POS + 2] + cg_up)
		state[POS + 2] = -cg_up
		for corner in CORNER_COUNT:
			if absf(hub_heights[corner] - mean_height) > 0.02: return PackedFloat64Array()
			var fitted_travel := travel + hub_heights[corner] - mean_height
			if fitted_travel < -float(model.travel_droop_m) or fitted_travel > float(model.travel_bump_m):
				return PackedFloat64Array()
			change = maxf(change, absf(state[TRAVEL + corner] - fitted_travel))
			state[TRAVEL + corner] = fitted_travel
		if change < 1.0e-9:
			return state if _finite_array(state) else PackedFloat64Array()
	return PackedFloat64Array() # A nonconvergent or unsupported patch is refused.


## One deterministic fixed public tick. The caller owns tick/time policy;
## controls stay constant through all RK stages. Input arrays are never edited.
## Returns an empty array on malformed inputs, road samples, or a singular
## generalized mass matrix so a Session can reject the tick transactionally.
static func step(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
	if state.size() != STATE_SIZE or not _valid_model(model) or not _valid_controls(controls):
		return PackedFloat64Array()
	if not road.is_valid() or not is_finite(dt) or dt <= 0.0 or dt > 1.0 / 30.0:
		return PackedFloat64Array()
	if not _finite_array(state) or not _valid_attitude(state):
		return PackedFloat64Array()
	var initial_wall_sample: Variant = road.call(state[POS], state[POS + 1])
	if typeof(initial_wall_sample) != TYPE_DICTIONARY:
		return PackedFloat64Array()
	var initial_wall_surface: Dictionary = initial_wall_sample
	var initial_walls := _validated_walls(initial_wall_surface)
	if not bool(initial_walls.get("ok", false)):
		return PackedFloat64Array()
	var wall_boxes: Array = initial_walls["walls"]
	var step_substeps := SUBSTEPS_PER_TICK
	if not WetPhysics.surface_is_valid(initial_wall_surface):
		return PackedFloat64Array()
	if bool(initial_wall_surface.get("wet_zone", false)):
		step_substeps = maxi(step_substeps, ceili(dt / WetPhysics.WET_MAX_STEP_S))
	if not wall_boxes.is_empty():
		step_substeps = maxi(step_substeps, ceili(dt / WALL_MAX_INTEGRATION_STEP_S))
	var cached_north := state[POS]
	var cached_east := state[POS + 1]
	var integration_road := func(north: float, east: float) -> Dictionary:
		if north == cached_north and east == cached_east:
			return initial_wall_surface
		return road.call(north, east)
	var next := state.duplicate()
	var substep_dt := dt / float(step_substeps)
	for substep in step_substeps:
		var initial_derivative := _derivative_core(next, model, controls, integration_road)
		if initial_derivative.is_empty():
			return PackedFloat64Array()
		if _derivative_is_exactly_zero(initial_derivative):
			return next
		next = _rk4_step(next, model, controls, integration_road, substep_dt, initial_derivative)
		if next.is_empty():
			return PackedFloat64Array()
	return next


## State derivative under one set of controls and a spatially sampled road.
## Exposed for independent numerical oracles; invalid input returns empty.
static func derivative(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
) -> PackedFloat64Array:
	if state.size() != STATE_SIZE or not _valid_model(model) or not _valid_controls(controls):
		return PackedFloat64Array()
	if not road.is_valid() or not _finite_array(state) or not _valid_attitude(state):
		return PackedFloat64Array()
	return _derivative_core(state, model, controls, road)


static func _derivative_core(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
) -> PackedFloat64Array:
	if state.size() != STATE_SIZE or not _finite_array(state):
		return PackedFloat64Array()
	var quaternion_length := _quaternion_length(state)
	if not is_finite(quaternion_length) or quaternion_length <= 1.0e-10:
		return PackedFloat64Array()
	var evaluated := _evaluate_active(state, model, controls, road, false)
	if not bool(evaluated["ok"]):
		return PackedFloat64Array()
	var acceleration: PackedFloat64Array = evaluated["generalized_acceleration"]
	var result := PackedFloat64Array()
	result.resize(STATE_SIZE)
	var velocity_body := _slice3(state, VEL)
	var rate_body := _slice3(state, RATE)
	var accel_body: PackedFloat64Array = PackedFloat64Array([acceleration[0], acceleration[1], acceleration[2]])
	var body_velocity_rate := M.sub(accel_body, M.cross(rate_body, velocity_body))
	# RK stage states are not unit length even though accepted public states are.
	# q_rotate assumes a unit quaternion, so normalize only for this spatial map;
	# qdot below must use the raw stage value for the quaternion ODE.
	var position_rate := M.q_rotate(M.q_normalized(_state_quaternion(state)), velocity_body)
	for i in 3:
		result[POS + i] = position_rate[i]
		result[VEL + i] = body_velocity_rate[i]
		result[RATE + i] = acceleration[3 + i]
	for i in 4:
		result[ATT + i] = _quaternion_rate_component(state, rate_body, i)
		result[TRAVEL + i] = state[TRAVEL_RATE + i]
		result[TRAVEL_RATE + i] = acceleration[6 + i]
		result[WHEEL_SPIN + i] = acceleration[10 + i]
		result[WHEEL_ANGLE + i] = state[WHEEL_SPIN + i]
	result[STEER] = state[STEER_RATE]
	result[STEER_RATE] = float(evaluated["steering_acceleration_rad_per_s2"])
	return result if _finite_array(result) else PackedFloat64Array()


## Diagnostic scalar total energy in joules: sprung/hub/axial-rotor kinetic,
## gravitational, suspension/stop, tire and hull elastic terms. Friction and
## damping dissipate energy; this is diagnostic, not a conserved invariant.
static func energy(state: PackedFloat64Array, model: Dictionary, road: Callable) -> float:
	if state.size() != STATE_SIZE or not _valid_model(model) or not road.is_valid() or not _finite_array(state):
		return NAN
	var evaluated := _evaluate_active(state, model, DEFAULT_CONTROLS, road)
	if not bool(evaluated["ok"]):
		return NAN
	return float(evaluated["energy_j"])


## Per-corner loads, slip and support diagnostics. Returned vectors use
## FL,FR,RL,RR order; `airborne` means no tire or hull sphere is supporting.
static func telemetry(
	state: PackedFloat64Array,
	model: Dictionary,
	road: Callable,
	controls: Dictionary = DEFAULT_CONTROLS,
) -> Dictionary:
	if state.size() != STATE_SIZE or not _valid_model(model) or not road.is_valid() or not _valid_controls(controls) or not _finite_array(state) or not _valid_attitude(state):
		return {"ok": false, "error": "Invalid telemetry input"}
	var evaluated := _evaluate_active(state, model, controls, road)
	if not bool(evaluated["ok"]):
		return {"ok": false, "error": str(evaluated["error"])}
	var velocity: PackedFloat64Array = _slice3(state, VEL)
	var position_world_velocity: PackedFloat64Array = M.q_rotate(M.q_normalized(_state_quaternion(state)), velocity)
	return {
		"ok": true,
		"error": "",
		"speed_m_per_s": M.norm(position_world_velocity),
		"forward_speed_m_per_s": velocity[0],
		"wheel_load_n": evaluated["wheel_load_n"],
		"wheel_longitudinal_force_n": evaluated["wheel_longitudinal_force_n"],
		"wheel_lateral_force_n": evaluated["wheel_lateral_force_n"],
		"wheel_brake_torque_n_m": evaluated["wheel_brake_torque_n_m"],
		"wheel_slip_ratio": evaluated["wheel_slip_ratio"],
		"wheel_slip_angle_rad": evaluated["wheel_slip_angle_rad"],
		"wheel_slip_speed_m_per_s": evaluated["wheel_slip_speed_m_per_s"],
		"wheel_in_contact": evaluated["wheel_in_contact"],
		"wheel_wall_load_n": evaluated.get("wheel_wall_load_n", PackedFloat64Array()),
		"wheel_wall_in_contact": evaluated.get("wheel_wall_in_contact", PackedByteArray()),
		"hull_in_contact": evaluated["hull_in_contact"],
		"hull_wall_load_n": evaluated.get("hull_wall_load_n", PackedFloat64Array()),
		"wall_contact_count": int(evaluated.get("wall_contact_count", 0)),
		"wall_normal_load_n": float(evaluated.get("wall_normal_load_n", 0.0)),
		"wall_friction_power_w": float(evaluated.get("wall_friction_power_w", 0.0)),
		"friction_sweeps_used": evaluated["friction_sweeps_used"],
		"airborne": bool(evaluated["airborne"]),
		"suspension_travel_m": PackedFloat64Array([state[TRAVEL], state[TRAVEL + 1], state[TRAVEL + 2], state[TRAVEL + 3]]),
		"suspension_force_n": evaluated["suspension_force_n"],
		"total_energy_j": evaluated["energy_j"],
		"environment": evaluated.get("environment", WetPhysics.dry()),
	}


static func _rk4_step(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
	dt: float,
	initial_derivative: PackedFloat64Array = PackedFloat64Array(),
) -> PackedFloat64Array:
	var k1 := initial_derivative
	if k1.size() != STATE_SIZE:
		k1 = _derivative_core(state, model, controls, road)
	if k1.is_empty():
		return PackedFloat64Array()
	var stage_2 := Integrator.axpy(state, 0.5 * dt, k1)
	var k2 := _derivative_core(stage_2, model, controls, road)
	if k2.is_empty():
		return PackedFloat64Array()
	var stage_3 := Integrator.axpy(state, 0.5 * dt, k2)
	var k3 := _derivative_core(stage_3, model, controls, road)
	if k3.is_empty():
		return PackedFloat64Array()
	var stage_4 := Integrator.axpy(state, dt, k3)
	var k4 := _derivative_core(stage_4, model, controls, road)
	if k4.is_empty():
		return PackedFloat64Array()
	var weighted := Integrator.axpy(k1, 2.0, k2)
	weighted = Integrator.axpy(weighted, 2.0, k3)
	weighted = Integrator.axpy(weighted, 1.0, k4)
	var next := Integrator.axpy(state, dt / 6.0, weighted)
	if not _finite_array(next):
		return PackedFloat64Array()
	var attitude := M.q_normalized(_state_quaternion(next))
	for i in 4:
		next[ATT + i] = attitude[i]
	return next


## Runtime evaluation dispatch. `_evaluate` below remains the independent GDScript
## oracle used by parity tests and source-only fallback installations.
static func _evaluate_active(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
	calculate_energy: bool = true,
	adaptive_friction: bool = true,
) -> Dictionary:
	var result: Dictionary
	# A road is a deterministic spatial function for the duration of one
	# evaluation. Cache exact float coordinate pairs here only; never quantize,
	# retain values across states/times, or expose callback-owned mutable samples.
	var road_cache: Dictionary = {}
	var evaluation_road: Callable = func(north_m: float, east_m: float) -> Variant:
		var east_samples: Dictionary = road_cache.get(north_m, {})
		if east_samples.has(east_m):
			return east_samples[east_m]
		var sample: Variant = road.call(north_m, east_m)
		if typeof(sample) == TYPE_DICTIONARY:
			sample = sample.duplicate(true)
		east_samples[east_m] = sample
		road_cache[north_m] = east_samples
		return sample
	var center_value: Variant = evaluation_road.call(state[POS], state[POS + 1])
	if typeof(center_value) != TYPE_DICTIONARY or not WetPhysics.surface_is_valid(center_value):
		return _failure("Malformed environmental road sample")
	var environmental: Dictionary = {}
	var applied_controls := controls
	if bool(center_value.get("wet_zone", false)):
		var geometry := _corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
		if not geometry.ok: return geometry
		environmental = WetPhysics.evaluate(state, model, geometry, evaluation_road, center_value)
		if not environmental.ok: return environmental
		applied_controls = controls.duplicate()
		var external: PackedFloat64Array = environmental.generalized_force.duplicate()
		if controls.has("external_generalized_force"):
			if not _valid_external_force(controls): return _failure("Malformed external generalized force")
			for index in GENERALIZED_SIZE: external[index] += controls.external_generalized_force[index]
		applied_controls["external_generalized_force"] = external
		environmental.erase("generalized_force")
	if _backend_override_for_tests == BACKEND_GDSCRIPT_REFERENCE:
		result = _evaluate(state, model, applied_controls, evaluation_road, calculate_energy, adaptive_friction)
	else:
		var native := _load_native_backend()
		if native == null:
			result = _evaluate(state, model, applied_controls, evaluation_road, calculate_energy, adaptive_friction)
		else:
			var road_batch := func(coordinates_xy: PackedFloat64Array) -> Dictionary:
				return _sample_road_batch(evaluation_road, coordinates_xy)
			var native_result: Variant = native.call("evaluate", state, model, applied_controls, road_batch,
				calculate_energy, adaptive_friction)
			if typeof(native_result) != TYPE_DICTIONARY:
				return _failure("Native vehicle backend returned a non-dictionary result")
			result = native_result
			if not bool(result.get("ok", false)):
				return result
			if not _native_evaluation_is_valid(result, model):
				return _failure("Native vehicle backend returned malformed evaluation channels")
	if not bool(result.get("ok", false)):
		return result
	if not environmental.is_empty(): result["environment"] = environmental
	return _apply_wall_contacts(state, model, evaluation_road, result, calculate_energy, center_value)


## Optional static AABBs are sampled once at the sprung-body center, shared by
## both solver backends, and applied as additive generalized forces. The road
## callback remains the source of truth; an absent `walls` field means no boxes.
static func _apply_wall_contacts(
	state: PackedFloat64Array,
	model: Dictionary,
	road: Callable,
	base_result: Dictionary,
	calculate_energy: bool,
	cached_center: Dictionary = {},
) -> Dictionary:
	var result := base_result.duplicate(true)
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	var wheel_wall_load := PackedFloat64Array()
	wheel_wall_load.resize(CORNER_COUNT)
	var wheel_wall_contact := PackedByteArray()
	wheel_wall_contact.resize(CORNER_COUNT)
	var hull_wall_load := PackedFloat64Array()
	hull_wall_load.resize(hull_radii.size())
	result["wheel_wall_load_n"] = wheel_wall_load
	result["wheel_wall_in_contact"] = wheel_wall_contact
	result["hull_wall_load_n"] = hull_wall_load
	result["wall_contact_count"] = 0
	result["wall_normal_load_n"] = 0.0
	result["wall_friction_power_w"] = 0.0
	var center_sample: Variant = cached_center if not cached_center.is_empty() else road.call(state[POS], state[POS + 1])
	if typeof(center_sample) != TYPE_DICTIONARY:
		return _failure("Road callback must return a Dictionary for wall sampling")
	var center_surface: Dictionary = center_sample
	var walls_result := _validated_walls(center_surface)
	if not bool(walls_result.get("ok", false)):
		return _failure(str(walls_result.get("error", "Malformed wall data")))
	var walls: Array = walls_result["walls"]
	if walls.is_empty():
		return result

	var servo_acceleration := float(base_result.get("steering_acceleration_rad_per_s2", 0.0))
	var geometry := _corner_geometry(state, model, state[STEER], state[STEER_RATE], servo_acceleration)
	if not bool(geometry.get("ok", false)):
		return geometry
	var q := M.q_normalized(_state_quaternion(state))
	var q_conjugate := M.q_conj(q)
	var position_world := _slice3(state, POS)
	var body_velocity := _slice3(state, VEL)
	var body_rate := _slice3(state, RATE)
	var rhs := PackedFloat64Array()
	rhs.resize(GENERALIZED_SIZE)
	var wall_count := 0
	var wall_normal_load := 0.0
	var wall_friction_power := 0.0
	var wall_energy := 0.0
	var wall_stiffness := float(model["hull_contact_stiffness_n_per_m"])
	var wall_damping := float(model["hull_contact_damping_n_s_per_m"])
	var tire_wall_stiffness := float(model["tire_stiffness_n_per_m"])
	var tire_wall_damping := float(model["tire_damping_n_s_per_m"])
	var tire_friction_scale := float(model["tire_friction_scale"])
	var hull_friction_scale := float(model["hull_contact_friction_scale"])
	var tire_radius := float(model["tire_radius_m"])
	var hub_position_body: Array[PackedFloat64Array] = geometry["hub_position_body"]
	var hub_position_derivative_body: Array[PackedFloat64Array] = geometry["hub_position_derivative_body"]
	var spin_axis_body: Array[PackedFloat64Array] = geometry["spin_axis_body"]
	for corner in CORNER_COUNT:
		var r: PackedFloat64Array = hub_position_body[corner]
		var r_prime: PackedFloat64Array = hub_position_derivative_body[corner]
		var hub_world := M.add(position_world, M.q_rotate(q, r))
		var hub_velocity_body := M.add(body_velocity, M.add(
			M.cross(body_rate, r), M.scale(r_prime, state[TRAVEL_RATE + corner])))
		var hub_velocity_world := M.q_rotate(q, hub_velocity_body)
		var left_steer_rate := -state[STEER_RATE] if corner < 2 else 0.0
		var wheel_omega := M.add(body_rate, M.add(
			PackedFloat64Array([0.0, 0.0, -left_steer_rate]),
			M.scale(spin_axis_body[corner], state[WHEEL_SPIN + corner])))
		for wall in walls:
			var contact := _sphere_aabb_contact(hub_world, tire_radius, wall)
			if not bool(contact.get("overlap", false)):
				continue
			var normal: PackedFloat64Array = contact["normal_ned"]
			var penetration := float(contact["penetration_m"])
			var normal_speed := M.dot(hub_velocity_world, normal)
			var normal_load := maxf(0.0, tire_wall_stiffness * penetration - tire_wall_damping * minf(normal_speed, 0.0))
			if normal_load <= 0.0:
				continue
			wall_count += 1
			wall_normal_load += normal_load
			wheel_wall_load[corner] += normal_load
			wheel_wall_contact[corner] = 1
			if calculate_energy:
				wall_energy += 0.5 * tire_wall_stiffness * penetration * penetration
			var rho_world := M.scale(normal, -tire_radius)
			var rho_body := M.q_rotate(q_conjugate, rho_world)
			var contact_velocity_world := M.add(hub_velocity_world, M.q_rotate(q,
				M.cross(wheel_omega, rho_body)))
			var friction_force_world := _wall_friction_force(
				normal, contact_velocity_world, float(wall["mu"]) * tire_friction_scale, normal_load,
			)
			wall_friction_power += M.dot(friction_force_world, contact_velocity_world)
			var total_force_world := M.add(M.scale(normal, normal_load), friction_force_world)
			var total_force_body := M.q_rotate(q_conjugate, total_force_world)
			_add_contact_force(rhs, hub_position_body[corner], total_force_body,
				hub_position_derivative_body[corner], corner, spin_axis_body[corner], rho_body)

	var hull_centers: PackedFloat64Array = model["hull_probe_centers_frd_m"]
	for probe in hull_radii.size():
		var center := PackedFloat64Array([
			hull_centers[probe * 3], hull_centers[probe * 3 + 1], hull_centers[probe * 3 + 2],
		])
		var center_world := M.add(position_world, M.q_rotate(q, center))
		var center_velocity_body := M.add(body_velocity, M.cross(body_rate, center))
		var center_velocity_world := M.q_rotate(q, center_velocity_body)
		for wall in walls:
			var contact := _sphere_aabb_contact(center_world, hull_radii[probe], wall)
			if not bool(contact.get("overlap", false)):
				continue
			var normal: PackedFloat64Array = contact["normal_ned"]
			var penetration := float(contact["penetration_m"])
			var normal_speed := M.dot(center_velocity_world, normal)
			var normal_load := maxf(0.0, wall_stiffness * penetration - wall_damping * minf(normal_speed, 0.0))
			if normal_load <= 0.0:
				continue
			wall_count += 1
			wall_normal_load += normal_load
			hull_wall_load[probe] += normal_load
			if calculate_energy:
				wall_energy += 0.5 * wall_stiffness * penetration * penetration
			var rho_world := M.scale(normal, -hull_radii[probe])
			var rho_body := M.q_rotate(q_conjugate, rho_world)
			var contact_velocity_world := M.add(center_velocity_world, M.q_rotate(q,
				M.cross(body_rate, rho_body)))
			var friction_force_world := _wall_friction_force(
				normal, contact_velocity_world, float(wall["mu"]) * hull_friction_scale, normal_load,
			)
			wall_friction_power += M.dot(friction_force_world, contact_velocity_world)
			var total_force_world := M.add(M.scale(normal, normal_load), friction_force_world)
			_add_body_force(rhs, M.add(center, rho_body), M.q_rotate(q_conjugate, total_force_world))

	result["wall_contact_count"] = wall_count
	result["wall_normal_load_n"] = wall_normal_load
	result["wall_friction_power_w"] = wall_friction_power
	result["wheel_wall_load_n"] = wheel_wall_load
	result["wheel_wall_in_contact"] = wheel_wall_contact
	result["hull_wall_load_n"] = hull_wall_load
	if wall_count == 0:
		return result
	var matrix := _generalized_mass_matrix(model, geometry)
	var factor_result := _factor_generalized_mass_matrix(matrix)
	if not bool(factor_result.get("ok", false)):
		return _failure("Could not factor generalized mass matrix for wall contacts")
	var wall_acceleration := _solve_generalized(factor_result, rhs)
	var acceleration: PackedFloat64Array = result.get("generalized_acceleration", PackedFloat64Array())
	if wall_acceleration.size() != GENERALIZED_SIZE or acceleration.size() != GENERALIZED_SIZE:
		return _failure("Wall response returned malformed generalized acceleration")
	acceleration = acceleration.duplicate()
	for degree in GENERALIZED_SIZE:
		acceleration[degree] += wall_acceleration[degree]
	if not _finite_array(acceleration):
		return _failure("Wall response generalized acceleration is non-finite")
	result["generalized_acceleration"] = acceleration
	var hull_contact: PackedByteArray = result["hull_in_contact"].duplicate()
	for probe in hull_wall_load.size():
		if hull_wall_load[probe] > 0.0:
			hull_contact[probe] = 1
	result["hull_in_contact"] = hull_contact
	result["airborne"] = false
	if calculate_energy:
		result["energy_j"] = float(result.get("energy_j", 0.0)) + wall_energy
	return result


static func _validated_walls(sample: Dictionary) -> Dictionary:
	if not sample.has("walls"):
		return {"ok": true, "walls": []}
	var walls_value: Variant = sample["walls"]
	if typeof(walls_value) != TYPE_ARRAY:
		return _failure("Road walls must be an Array")
	var walls: Array = walls_value
	if walls.size() > MAX_WALL_CONTACT_BOXES:
		return _failure("Road returned more than %d wall boxes" % MAX_WALL_CONTACT_BOXES)
	var valid_walls: Array = []
	var scalar_keys := [
		"north_min_m", "north_max_m", "east_min_m", "east_max_m",
		"bottom_up_m", "top_up_m", "mu",
	]
	for index in walls.size():
		var value: Variant = walls[index]
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("Road wall %d must be a Dictionary" % index)
		var wall: Dictionary = value
		if typeof(wall.get("id")) != TYPE_STRING or str(wall["id"]).is_empty():
			return _failure("Road wall %d must have a nonempty string id" % index)
		var clean := {"id": str(wall["id"])}
		for key in scalar_keys:
			if not wall.has(key):
				return _failure("Road wall %d omitted %s" % [index, key])
			var scalar: Variant = wall[key]
			if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scalar)):
				return _failure("Road wall %d has invalid %s" % [index, key])
			clean[key] = float(scalar)
		if clean["north_min_m"] >= clean["north_max_m"] \
				or clean["east_min_m"] >= clean["east_max_m"] \
				or clean["bottom_up_m"] >= clean["top_up_m"] or clean["mu"] < 0.0:
			return _failure("Road wall %d has invalid bounds or friction" % index)
		valid_walls.append(clean)
	return {"ok": true, "walls": valid_walls}


static func _sphere_aabb_contact(center_ned: PackedFloat64Array, radius: float, wall: Dictionary) -> Dictionary:
	var lower := PackedFloat64Array([
		float(wall["north_min_m"]), float(wall["east_min_m"]), -float(wall["top_up_m"]),
	])
	var upper := PackedFloat64Array([
		float(wall["north_max_m"]), float(wall["east_max_m"]), -float(wall["bottom_up_m"]),
	])
	var closest := PackedFloat64Array()
	closest.resize(3)
	var outside := false
	for axis in 3:
		closest[axis] = clampf(center_ned[axis], lower[axis], upper[axis])
		outside = outside or center_ned[axis] < lower[axis] or center_ned[axis] > upper[axis]
	var normal := PackedFloat64Array()
	normal.resize(3)
	var signed_distance := 0.0
	if outside:
		var offset := M.sub(center_ned, closest)
		var distance := M.norm(offset)
		if distance <= 1.0e-12:
			return {"overlap": false}
		normal = M.scale(offset, 1.0 / distance)
		signed_distance = distance
	else:
		var nearest_distance := INF
		var nearest_axis := 0
		var nearest_sign := -1.0
		for axis in 3:
			var to_lower := center_ned[axis] - lower[axis]
			var to_upper := upper[axis] - center_ned[axis]
			if to_lower < nearest_distance:
				nearest_distance = to_lower
				nearest_axis = axis
				nearest_sign = -1.0
			if to_upper < nearest_distance:
				nearest_distance = to_upper
				nearest_axis = axis
				nearest_sign = 1.0
		normal[nearest_axis] = nearest_sign
		signed_distance = -nearest_distance
	var penetration := radius - signed_distance
	return {
		"overlap": penetration > 0.0,
		"normal_ned": normal,
		"penetration_m": maxf(penetration, 0.0),
	}


static func _wall_friction_force(
	normal_ned: PackedFloat64Array,
	contact_velocity_ned: PackedFloat64Array,
	friction_coefficient: float,
	normal_load_n: float,
) -> PackedFloat64Array:
	var tangent_velocity := M.sub(contact_velocity_ned,
		M.scale(normal_ned, M.dot(contact_velocity_ned, normal_ned)))
	var tangent_speed := M.norm(tangent_velocity)
	if tangent_speed <= 1.0e-12 or friction_coefficient <= 0.0 or normal_load_n <= 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var magnitude := friction_coefficient * normal_load_n \
		* M.tanh_(tangent_speed / WALL_FRICTION_REGULARIZATION_M_PER_S)
	return M.scale(tangent_velocity, -magnitude / tangent_speed)


static func _sample_road_batch(road: Callable, coordinates_xy: PackedFloat64Array) -> Dictionary:
	if not road.is_valid() or coordinates_xy.size() % 2 != 0 or not _finite_array(coordinates_xy):
		return {"ok": false, "error": "Native road batch request is malformed", "samples": PackedFloat64Array()}
	var samples := PackedFloat64Array()
	for index in range(0, coordinates_xy.size(), 2):
		var sampled := _sample_surface(road, coordinates_xy[index], coordinates_xy[index + 1])
		if not bool(sampled.get("ok", false)):
			return {"ok": false, "error": str(sampled.get("error", "Road callback failed")), "samples": PackedFloat64Array()}
		var surface: Dictionary = sampled["surface"]
		var normal: PackedFloat64Array = surface["normal_ned"]
		samples.append(float(surface["height_m"]))
		samples.append(normal[0])
		samples.append(normal[1])
		samples.append(normal[2])
		samples.append(float(surface["mu"]))
		samples.append(float(surface["rolling"]))
	return {"ok": true, "error": "", "samples": samples}


static func _native_evaluation_is_valid(result: Dictionary, model: Dictionary) -> bool:
	var vector_sizes := {
		"generalized_acceleration": GENERALIZED_SIZE,
		"suspension_force_n": CORNER_COUNT,
		"wheel_load_n": CORNER_COUNT,
		"wheel_longitudinal_force_n": CORNER_COUNT,
		"wheel_lateral_force_n": CORNER_COUNT,
		"wheel_brake_torque_n_m": CORNER_COUNT,
		"wheel_slip_ratio": CORNER_COUNT,
		"wheel_slip_angle_rad": CORNER_COUNT,
		"wheel_slip_speed_m_per_s": CORNER_COUNT,
	}
	for key in vector_sizes:
		var values: Variant = result.get(key)
		if typeof(values) != TYPE_PACKED_FLOAT64_ARRAY or values.size() != int(vector_sizes[key]):
			return false
		var float_values: PackedFloat64Array = values
		if not _finite_array(float_values):
			return false
	for key in ["wheel_in_contact", "hull_in_contact"]:
		var contacts: Variant = result.get(key)
		var expected_size := CORNER_COUNT
		if key == "hull_in_contact":
			var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
			expected_size = hull_radii.size()
		if typeof(contacts) != TYPE_PACKED_BYTE_ARRAY or contacts.size() != expected_size:
			return false
	for key in ["steering_acceleration_rad_per_s2", "energy_j"]:
		var scalar: Variant = result.get(key, NAN)
		if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scalar)):
			return false
	if typeof(result.get("airborne")) != TYPE_BOOL or typeof(result.get("friction_sweeps_used")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return true


static func _evaluate(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
	calculate_energy: bool = true,
	adaptive_friction: bool = true,
) -> Dictionary:
	if not _valid_external_force(controls): return _failure("Malformed external generalized force")
	var q := M.q_normalized(_state_quaternion(state))
	var q_conjugate := M.q_conj(q)
	var body_rate := _slice3(state, RATE)
	var servo_angle := state[STEER]
	var servo_rate := state[STEER_RATE]
	var servo_target := float(controls["steering"]) * float(model["max_steer_angle_rad"])
	var servo_frequency := float(model["steer_servo_natural_frequency_rad_s"])
	var servo_damping := float(model["steer_servo_damping_ratio"])
	var servo_acceleration := (
		servo_frequency * servo_frequency * (servo_target - servo_angle)
		- 2.0 * servo_damping * servo_frequency * servo_rate
	)
	if not is_finite(servo_acceleration):
		return _failure("Steering servo acceleration is non-finite")

	var geometry := _corner_geometry(state, model, servo_angle, servo_rate, servo_acceleration)
	if not bool(geometry["ok"]):
		return geometry
	var matrix := _generalized_mass_matrix(model, geometry)
	if matrix.is_empty():
		return _failure("Could not assemble the coupled generalized mass matrix")
	var rhs := PackedFloat64Array()
	rhs.resize(GENERALIZED_SIZE)
	var gravity_body := M.q_rotate(q_conjugate, PackedFloat64Array([0.0, 0.0, float(model["gravity_m_per_s2"])]))
	var sprung_mass := float(model["sprung_mass_kg"])
	for axis in 3:
		rhs[axis] += sprung_mass * gravity_body[axis]
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	var angular_momentum := _symmetric_inertia_mul(inertia, body_rate)
	var body_gyro := M.cross(body_rate, angular_momentum)
	for axis in 3:
		rhs[3 + axis] -= body_gyro[axis]

	var suspension_force := PackedFloat64Array()
	suspension_force.resize(CORNER_COUNT)
	var tire_load := PackedFloat64Array()
	tire_load.resize(CORNER_COUNT)
	var tire_slip_ratio := PackedFloat64Array()
	tire_slip_ratio.resize(CORNER_COUNT)
	var tire_slip_angle := PackedFloat64Array()
	tire_slip_angle.resize(CORNER_COUNT)
	var tire_slip_speed := PackedFloat64Array()
	tire_slip_speed.resize(CORNER_COUNT)
	var tire_longitudinal_force := PackedFloat64Array()
	tire_longitudinal_force.resize(CORNER_COUNT)
	var tire_lateral_force := PackedFloat64Array()
	tire_lateral_force.resize(CORNER_COUNT)
	var brake_torque := PackedFloat64Array()
	brake_torque.resize(CORNER_COUNT)
	var tire_contact := PackedByteArray()
	tire_contact.resize(CORNER_COUNT)
	var hull_contact := PackedByteArray()
	var hull_centers: PackedFloat64Array = model["hull_probe_centers_frd_m"]
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	hull_contact.resize(hull_radii.size())
	var spring_energy := 0.0
	var tire_energy := 0.0
	var hull_energy := 0.0
	var friction_contacts: Array[Dictionary] = []
	var position_world := _slice3(state, POS)
	var body_velocity := _slice3(state, VEL)
	var unsprung_mass := float(model["unsprung_mass_kg"])
	var suspension_k := float(model["suspension_stiffness_n_per_m"])
	var suspension_c := float(model["suspension_damping_n_s_per_m"])
	var tire_k := float(model["tire_stiffness_n_per_m"])
	var tire_c := float(model["tire_damping_n_s_per_m"])
	var radius := float(model["tire_radius_m"])
	var bump_k := float(model["bump_stop_stiffness_n_per_m"])
	var bump_c := float(model["bump_stop_damping_n_s_per_m"])
	var droop_k := float(model["droop_stop_stiffness_n_per_m"])
	var droop_c := float(model["droop_stop_damping_n_s_per_m"])
	var wheel_inertia := float(model["wheel_spin_inertia_kg_m2"])
	var spin_axis_body: Array[PackedFloat64Array] = geometry["spin_axis_body"]
	var hub_position_body: Array[PackedFloat64Array] = geometry["hub_position_body"]
	var hub_position_world: Array[PackedFloat64Array] = []
	var hub_velocity_world: Array[PackedFloat64Array] = []
	var hub_force_world: Array[PackedFloat64Array] = []
	var tire_contact_offset_body: Array[PackedFloat64Array] = []
	var tire_normal_world: Array[PackedFloat64Array] = []
	var tire_surface_id: Array = []
	var tire_road_sample: Array[Dictionary] = []
	var controls_throttle := float(controls["throttle"])
	var reverse_factor := -float(model["reverse_torque_fraction"]) if bool(controls["reverse"]) else 1.0
	var drive_base := controls_throttle * float(model["drive_torque_per_wheel_nm"]) * reverse_factor
	var brake_base := float(controls["brake"]) * float(model["brake_torque_per_wheel_nm"])
	var brake_front_fraction := float(model.get("brake_front_fraction", 0.5))
	var drive_fade := float(model["drive_torque_fade_rad_s"])
	var rolling_scale := float(model["rolling_resistance_coefficient"])
	var tire_mu_scale := float(model["tire_friction_scale"])
	var gravity := float(model["gravity_m_per_s2"])
	var can_skip_flat_static_friction := _is_quiescent_level_state(state, controls) and not _has_external_force(controls)
	var wheel_angles := PackedFloat64Array()
	wheel_angles.resize(CORNER_COUNT)
	var normal_forces_body: Array[PackedFloat64Array] = []
	var hub_bias_body: Array[PackedFloat64Array] = geometry["hub_bias_body"]
	var hub_speed_body: Array[PackedFloat64Array] = geometry["hub_speed_body"]
	var wheel_axis_rate_body: Array[PackedFloat64Array] = geometry["spin_axis_rate_body"]
	var wheel_abs_omega_body: Array[PackedFloat64Array] = []
	var tire_forward_world: Array[PackedFloat64Array] = []
	var tire_lateral_world: Array[PackedFloat64Array] = []
	var tire_slip_long := PackedFloat64Array()
	var tire_slip_lat := PackedFloat64Array()
	tire_slip_long.resize(CORNER_COUNT)
	tire_slip_lat.resize(CORNER_COUNT)
	var tire_mu_normal := PackedFloat64Array()
	tire_mu_normal.resize(CORNER_COUNT)
	var total_rotor_kinetic := 0.0
	var hub_kinetic := 0.0
	# NED down is positive, so gravitational potential is -m*g*down.
	var gravity_potential := -sprung_mass * gravity * position_world[2] if calculate_energy else 0.0

	for corner in CORNER_COUNT:
		var travel := state[TRAVEL + corner]
		var travel_rate := state[TRAVEL_RATE + corner]
		var stop_force := _travel_stop_force(travel, travel_rate, model)
		var fs := suspension_k * travel + suspension_c * travel_rate
		suspension_force[corner] = fs
		rhs[6 + corner] -= fs
		rhs[6 + corner] += stop_force
		if calculate_energy:
			spring_energy += 0.5 * suspension_k * travel * travel
			if travel > float(model["travel_bump_m"]):
				var compression := travel - float(model["travel_bump_m"])
				spring_energy += 0.5 * bump_k * compression * compression
			elif travel < -float(model["travel_droop_m"]):
				var extension := -float(model["travel_droop_m"]) - travel
				spring_energy += 0.5 * droop_k * extension * extension

		var r: PackedFloat64Array = hub_position_body[corner]
		var r_prime: PackedFloat64Array = geometry["hub_position_derivative_body"][corner]
		var hub_world := M.add(position_world, M.q_rotate(q, r))
		var hub_velocity := M.add(body_velocity, M.add(M.cross(body_rate, r), M.scale(r_prime, travel_rate)))
		var hub_velocity_ned := M.q_rotate(q, hub_velocity)
		hub_position_world.append(hub_world)
		hub_velocity_world.append(hub_velocity_ned)
		var sample_result := _sample_surface(road, hub_world[0], hub_world[1])
		if not bool(sample_result["ok"]):
			return sample_result
		var sample: Dictionary = sample_result["surface"]
		tire_road_sample.append(sample)
		tire_surface_id.append(sample.get("surface_id", ""))
		var normal: PackedFloat64Array = sample["normal_ned"]
		tire_normal_world.append(normal)
		var surface_point := PackedFloat64Array([hub_world[0], hub_world[1], -float(sample["height_m"])])
		var signed_distance := M.dot(normal, M.sub(hub_world, surface_point))
		var penetration := maxf(radius - signed_distance, 0.0)
		var hub_normal_speed := M.dot(hub_velocity_ned, normal)
		var normal_load := 0.0
		if penetration > 0.0:
			normal_load = maxf(0.0, tire_k * penetration - tire_c * hub_normal_speed)
		tire_load[corner] = normal_load
		tire_contact[corner] = 1 if normal_load > 0.0 else 0
		tire_mu_normal[corner] = maxf(0.0, float(sample["mu"]) * tire_mu_scale * normal_load)
		if calculate_energy:
			tire_energy += 0.5 * tire_k * penetration * penetration
		var force_world := M.scale(normal, normal_load)
		var force_body := M.q_rotate(q_conjugate, force_world)
		var rho_world := M.scale(normal, -radius)
		var rho_body := M.q_rotate(q_conjugate, rho_world)
		tire_contact_offset_body.append(rho_body)
		hub_force_world.append(force_world)
		normal_forces_body.append(force_body)
		_add_contact_force(rhs, r, force_body, r_prime, corner, spin_axis_body[corner], rho_body)

		var left_steer_angle := -servo_angle if corner < 2 else 0.0
		var left_steer_rate := -servo_rate if corner < 2 else 0.0
		var wheel_axis := spin_axis_body[corner]
		var wheel_spin := state[WHEEL_SPIN + corner]
		var wheel_omega := M.add(body_rate, M.add(
			PackedFloat64Array([0.0, 0.0, -left_steer_rate]), M.scale(wheel_axis, wheel_spin)))
		wheel_abs_omega_body.append(wheel_omega)
		var contact_velocity_ned := M.add(
			hub_velocity_ned,
			M.q_rotate(q, M.cross(wheel_omega, rho_body)),
		)
		var forward_body := PackedFloat64Array([M.cos_(left_steer_angle), -M.sin_(left_steer_angle), 0.0])
		var forward_world := M.q_rotate(q, forward_body)
		forward_world = M.sub(forward_world, M.scale(normal, M.dot(forward_world, normal)))
		var forward_norm := M.norm(forward_world)
		if forward_norm <= 1.0e-10:
			return _failure("Tire forward axis is degenerate on the sampled surface")
		forward_world = M.scale(forward_world, 1.0 / forward_norm)
		var lateral_world := M.cross(forward_world, normal)
		var lateral_norm := M.norm(lateral_world)
		if lateral_norm <= 1.0e-10:
			return _failure("Tire lateral axis is degenerate on the sampled surface")
		lateral_world = M.scale(lateral_world, 1.0 / lateral_norm)
		tire_forward_world.append(forward_world)
		tire_lateral_world.append(lateral_world)
		var slip_long := M.dot(contact_velocity_ned, forward_world)
		var slip_lateral := M.dot(contact_velocity_ned, lateral_world)
		tire_slip_long[corner] = slip_long
		tire_slip_lat[corner] = slip_lateral
		tire_slip_speed[corner] = M.sqrt_(slip_long * slip_long + slip_lateral * slip_lateral)
		var wheel_circumference_speed := wheel_spin * radius
		var hub_forward_speed := M.dot(hub_velocity_ned, forward_world)
		var ratio_denominator := maxf(MIN_SLIP_SPEED_M_PER_S, maxf(absf(hub_forward_speed), absf(wheel_circumference_speed)))
		tire_slip_ratio[corner] = (wheel_circumference_speed - hub_forward_speed) / ratio_denominator
		# Tire slip angle is the hub's travel direction relative to the wheel
		# plane. Contact-patch longitudinal slip tends to zero in free rolling
		# and must not be used as its denominator (it reported near 90 degrees).
		var hub_lateral_speed := M.dot(hub_velocity_ned, lateral_world)
		tire_slip_angle[corner] = M.atan2_(hub_lateral_speed, maxf(absf(hub_forward_speed), MIN_SLIP_SPEED_M_PER_S))
		var level_surface := absf(normal[0]) <= 1.0e-12 and absf(normal[1]) <= 1.0e-12 and normal[2] <= -1.0 + 1.0e-12
		if normal_load > 0.0 and not (can_skip_flat_static_friction and level_surface):
			var tangent_rows := _tire_contact_rows(q_conjugate, forward_world, lateral_world, r, rho_body, r_prime, wheel_axis, corner)
			var bias_result := _tire_contact_bias(
				q, body_rate, hub_bias_body[corner], hub_velocity, wheel_omega,
				wheel_axis_rate_body[corner], left_steer_rate,
				geometry["steering_acceleration_body"][corner],
				wheel_spin, rho_body,
			)
			if not bool(bias_result["ok"]):
				return bias_result
			friction_contacts.append({
				"rows": tangent_rows,
				"directions": [forward_world, lateral_world],
				"slip": PackedFloat64Array([slip_long, slip_lateral]),
				"bias": bias_result["bias"],
				"mu_load": tire_mu_normal[corner],
				"tau": float(model["tire_slip_relaxation_s"]),
				"kind": "wheel",
				"index": corner,
			})
		if brake_base > 0.0:
			# Brake is a bounded one-dimensional friction constraint on relative
			# wheel spin. It can hold the wheel at zero without reversing it; the
			# equal-and-opposite body reaction is already represented by the
			# relative-spin generalized coordinate and rotor inertia coupling.
			var brake_row := PackedFloat64Array()
			brake_row.resize(GENERALIZED_SIZE)
			brake_row[10 + corner] = 1.0
			friction_contacts.append({
				"rows": [brake_row],
				"slip": PackedFloat64Array([wheel_spin]),
				"bias": PackedFloat64Array([0.0, 0.0, 0.0]),
				# Fixed axle allocation; total capacity remains four times brake_base.
				# No velocity, yaw, wheel-slip or terrain feedback alters this split.
				"mu_load": brake_base * 2.0 * (brake_front_fraction if corner < 2 else 1.0 - brake_front_fraction),
				"tau": float(model["tire_slip_relaxation_s"]),
				"kind": "brake",
				"index": corner,
			})

		var torque := drive_base
		if drive_fade > 0.0:
			torque *= maxf(0.0, 1.0 - absf(wheel_spin) / drive_fade)
		rhs[10 + corner] += torque
		if normal_load > 0.0:
			var rolling_torque := (
				rolling_scale * float(sample["rolling"]) * normal_load * radius
				* wheel_spin / M.sqrt_(wheel_spin * wheel_spin + 1.0e-6)
			)
			rhs[10 + corner] -= rolling_torque
		var rotor_rate := M.dot(body_rate, wheel_axis) + wheel_spin
		if calculate_energy:
			total_rotor_kinetic += 0.5 * wheel_inertia * rotor_rate * rotor_rate
		wheel_angles[corner] = state[WHEEL_ANGLE + corner]

		var hub_bias: PackedFloat64Array = hub_bias_body[corner]
		var hub_bias_generalized := _hub_bias_generalized(r, r_prime, corner, unsprung_mass, hub_bias)
		_add_scaled_vector(rhs, hub_bias_generalized, -1.0)
		var gravity_generalized := _hub_gravity_generalized(r, r_prime, corner, unsprung_mass, gravity_body)
		_add_scaled_vector(rhs, gravity_generalized, 1.0)
		var hub_velocity_vec: PackedFloat64Array = hub_speed_body[corner]
		if calculate_energy:
			hub_kinetic += 0.5 * unsprung_mass * M.dot(hub_velocity_vec, hub_velocity_vec)
			gravity_potential -= unsprung_mass * gravity * hub_world[2]

	# Add wheel-rotor convective angular momentum bias. Axial inertia is included
	# in the mass matrix; this term accounts for body transport and steering-axis
	# motion without counting motor/contact torque twice.
	for corner in CORNER_COUNT:
		var axis: PackedFloat64Array = spin_axis_body[corner]
		var axis_rate: PackedFloat64Array = wheel_axis_rate_body[corner]
		var spin := state[WHEEL_SPIN + corner]
		var axial_rate := M.dot(body_rate, axis) + spin
		var rotor_bias := M.add(
			M.scale(axis, M.dot(body_rate, axis_rate)),
			M.scale(M.add(axis_rate, M.cross(body_rate, axis)), axial_rate),
		)
		var wheel_inertia_value := float(model["wheel_spin_inertia_kg_m2"])
		for axis_index in 3:
			rhs[3 + axis_index] -= wheel_inertia_value * rotor_bias[axis_index]
		rhs[10 + corner] -= wheel_inertia_value * M.dot(body_rate, axis_rate)

	# Hull spheres provide physical bumper, roof and side impacts for rollovers.
	for probe in hull_radii.size():
		var center := PackedFloat64Array([
			hull_centers[probe * 3], hull_centers[probe * 3 + 1], hull_centers[probe * 3 + 2],
		])
		var center_world := M.add(position_world, M.q_rotate(q, center))
		var surface_result := _sample_surface(road, center_world[0], center_world[1])
		if not bool(surface_result["ok"]):
			return surface_result
		var surface_probe: Dictionary = surface_result["surface"]
		var normal_probe: PackedFloat64Array = surface_probe["normal_ned"]
		var ground_point := PackedFloat64Array([
			center_world[0], center_world[1], -float(surface_probe["height_m"]),
		])
		var signed_probe_distance := M.dot(normal_probe, M.sub(center_world, ground_point))
		var probe_penetration := maxf(hull_radii[probe] - signed_probe_distance, 0.0)
		var center_velocity_body := M.add(body_velocity, M.cross(body_rate, center))
		var center_velocity_world := M.q_rotate(q, center_velocity_body)
		var probe_normal_speed := M.dot(center_velocity_world, normal_probe)
		var hull_load := 0.0
		if probe_penetration > 0.0:
			hull_load = maxf(
				0.0,
				float(model["hull_contact_stiffness_n_per_m"]) * probe_penetration
				- float(model["hull_contact_damping_n_s_per_m"]) * probe_normal_speed,
			)
		hull_contact[probe] = 1 if hull_load > 0.0 else 0
		if calculate_energy:
			hull_energy += 0.5 * float(model["hull_contact_stiffness_n_per_m"]) * probe_penetration * probe_penetration
		if hull_load <= 0.0:
			continue
		var hull_force_world := M.scale(normal_probe, hull_load)
		var hull_force_body := M.q_rotate(q_conjugate, hull_force_world)
		_add_body_force(rhs, center, hull_force_body)
		var rho_world_hull := M.scale(normal_probe, -hull_radii[probe])
		var rho_body_hull := M.q_rotate(q_conjugate, rho_world_hull)
		var hull_contact_point_velocity := M.add(
			center_velocity_world,
			M.q_rotate(q, M.cross(body_rate, rho_body_hull)),
		)
		var hull_tangent := M.sub(hull_contact_point_velocity, M.scale(normal_probe, M.dot(hull_contact_point_velocity, normal_probe)))
		var hull_tangent_speed := M.norm(hull_tangent)
		var hull_friction_limit := maxf(0.0, float(surface_probe["mu"]) * float(model["hull_contact_friction_scale"]) * hull_load)
		if hull_tangent_speed > 1.0e-10 and hull_friction_limit > 0.0:
			var tangent_direction := M.scale(hull_tangent, -1.0 / hull_tangent_speed)
			var tangent_force := M.scale(tangent_direction, hull_friction_limit * M.tanh_(hull_tangent_speed / 0.02))
			_add_body_force(rhs, M.add(center, rho_body_hull), M.q_rotate(q_conjugate, tangent_force))

	if controls.has("external_generalized_force"):
		for index in GENERALIZED_SIZE:
			rhs[index] += controls.external_generalized_force[index]
	var factor_result := _factor_generalized_mass_matrix(matrix)
	if not bool(factor_result["ok"]):
		return _failure("Coupled generalized mass matrix is singular: " + str(factor_result["error"]))
	var factor: Dictionary = factor_result
	var acceleration := _solve_generalized(factor, rhs)
	if not _finite_array(acceleration):
		return _failure("Unconstrained generalized acceleration is non-finite")
	var friction_result := _solve_tangent_friction(
		factor, acceleration, friction_contacts, tire_longitudinal_force, tire_lateral_force, brake_torque,
		adaptive_friction,
	)
	if not bool(friction_result["ok"]):
		return friction_result
	acceleration = friction_result["acceleration"]
	var tire_in_contact_count := 0
	var hull_in_contact_count := 0
	for byte in tire_contact:
		tire_in_contact_count += int(byte)
	for byte in hull_contact:
		hull_in_contact_count += int(byte)
	var energy_value := _energy_from_terms(state, model, body_rate, hub_kinetic, total_rotor_kinetic,
		gravity_potential, spring_energy, tire_energy, hull_energy) if calculate_energy else 0.0
	return {
		"ok": true,
		"error": "",
		"generalized_acceleration": acceleration,
		"steering_acceleration_rad_per_s2": servo_acceleration,
		"suspension_force_n": suspension_force,
		"wheel_load_n": tire_load,
		"wheel_longitudinal_force_n": tire_longitudinal_force,
		"wheel_lateral_force_n": tire_lateral_force,
		"wheel_brake_torque_n_m": brake_torque,
		"wheel_slip_ratio": tire_slip_ratio,
		"wheel_slip_angle_rad": tire_slip_angle,
		"wheel_slip_speed_m_per_s": tire_slip_speed,
		"wheel_in_contact": tire_contact,
		"hull_in_contact": hull_contact,
		"airborne": tire_in_contact_count == 0 and hull_in_contact_count == 0,
		"friction_sweeps_used": int(friction_result.get("sweeps_used", 0)),
		"energy_j": energy_value,
	}


static func _corner_geometry(state: PackedFloat64Array, model: Dictionary, steer_right: float, steer_rate_right: float, steer_accel_right: float) -> Dictionary:
	var corner_x: PackedFloat64Array = model["corner_x_m"]
	var corner_y: PackedFloat64Array = model["corner_y_m"]
	var arm_length := float(model["arm_length_m"])
	var cg_height := float(model["cg_height_above_chassis_datum_m"])
	var rest_below := float(model["wheel_center_rest_below_chassis_datum_m"])
	var body_rate := _slice3(state, RATE)
	var hubs: Array[PackedFloat64Array] = []
	var derivatives: Array[PackedFloat64Array] = []
	var second_derivatives: Array[PackedFloat64Array] = []
	var hub_speed: Array[PackedFloat64Array] = []
	var hub_bias: Array[PackedFloat64Array] = []
	var axes: Array[PackedFloat64Array] = []
	var axis_rates: Array[PackedFloat64Array] = []
	var servo_accels: Array[float] = []
	for corner in CORNER_COUNT:
		var travel := state[TRAVEL + corner]
		if absf(travel) >= arm_length:
			return _failure("Suspension travel reaches the A-arm geometric singularity")
		var lateral_offset := M.sqrt_(arm_length * arm_length - travel * travel)
		var side := signf(corner_y[corner])
		# Preserve the authored wheel station about the shifted CG; travel moves
		# the hub laterally along its arm from that zero-travel location.
		var y := corner_y[corner] + side * (lateral_offset - arm_length)
		var y_prime := -side * travel / lateral_offset
		var y_second := -side * arm_length * arm_length / (lateral_offset * lateral_offset * lateral_offset)
		var r := PackedFloat64Array([corner_x[corner], y, cg_height + rest_below - travel])
		var r_prime := PackedFloat64Array([0.0, y_prime, -1.0])
		var r_second := PackedFloat64Array([0.0, y_second, 0.0])
		var rate := state[TRAVEL_RATE + corner]
		var hub_v := M.add(_slice3(state, VEL), M.add(M.cross(body_rate, r), M.scale(r_prime, rate)))
		var hub_b := M.add(
			M.cross(body_rate, M.cross(body_rate, r)),
			M.add(M.scale(M.cross(body_rate, r_prime), 2.0 * rate), M.scale(r_second, rate * rate)),
		)
		var left_angle := -steer_right if corner < 2 else 0.0
		var left_rate := -steer_rate_right if corner < 2 else 0.0
		var left_accel := -steer_accel_right if corner < 2 else 0.0
		var forward := PackedFloat64Array([M.cos_(left_angle), -M.sin_(left_angle), 0.0])
		# A positive spin rate means forward rolling: the wheel axle points
		# forward × down (toward the vehicle's left at zero steer).
		var axis := M.cross(PackedFloat64Array([0.0, 0.0, -1.0]), forward)
		# The wheel assembly rotates around local up as its left angle grows.
		var axis_rate := M.scale(M.cross(PackedFloat64Array([0.0, 0.0, 1.0]), axis), -left_rate)
		hubs.append(r)
		derivatives.append(r_prime)
		second_derivatives.append(r_second)
		hub_speed.append(hub_v)
		hub_bias.append(hub_b)
		axes.append(axis)
		axis_rates.append(axis_rate)
		servo_accels.append(left_accel)
	return {
		"ok": true,
		"hub_position_body": hubs,
		"hub_position_derivative_body": derivatives,
		"hub_position_second_derivative_body": second_derivatives,
		"hub_speed_body": hub_speed,
		"hub_bias_body": hub_bias,
		"spin_axis_body": axes,
		"spin_axis_rate_body": axis_rates,
		"steering_acceleration_body": servo_accels,
	}


static func _generalized_mass_matrix(model: Dictionary, geometry: Dictionary) -> PackedFloat64Array:
	var n := GENERALIZED_SIZE
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	var sprung_mass := float(model["sprung_mass_kg"])
	for axis in 3:
		matrix[axis * n + axis] += sprung_mass
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	matrix[3 * n + 3] += inertia[0]
	matrix[4 * n + 4] += inertia[1]
	matrix[5 * n + 5] += inertia[2]
	matrix[3 * n + 4] += inertia[3]
	matrix[4 * n + 3] += inertia[3]
	matrix[3 * n + 5] += inertia[4]
	matrix[5 * n + 3] += inertia[4]
	matrix[4 * n + 5] += inertia[5]
	matrix[5 * n + 4] += inertia[5]
	var mass := float(model["unsprung_mass_kg"])
	var hubs: Array[PackedFloat64Array] = geometry["hub_position_body"]
	var derivatives: Array[PackedFloat64Array] = geometry["hub_position_derivative_body"]
	for corner in CORNER_COUNT:
		var jacobian := _hub_jacobian(hubs[corner], derivatives[corner], corner)
		_add_gram(matrix, jacobian, mass, n, corner)
	var wheel_inertia := float(model["wheel_spin_inertia_kg_m2"])
	var axes: Array[PackedFloat64Array] = geometry["spin_axis_body"]
	for corner in CORNER_COUNT:
		_add_rotor_inertia(matrix, axes[corner], corner, wheel_inertia, n)
	return matrix


static func _hub_jacobian(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int) -> PackedFloat64Array:
	var n := GENERALIZED_SIZE
	var jacobian := PackedFloat64Array()
	jacobian.resize(3 * n)
	for axis in 3:
		jacobian[axis * n + axis] = 1.0
	# A hub's body angular velocity contribution is omega × r = -[r]x omega.
	jacobian[0 * n + 4] = r[2]
	jacobian[0 * n + 5] = -r[1]
	jacobian[1 * n + 3] = -r[2]
	jacobian[1 * n + 5] = r[0]
	jacobian[2 * n + 3] = r[1]
	jacobian[2 * n + 4] = -r[0]
	for axis in 3:
		jacobian[axis * n + 6 + corner] = r_prime[axis]
	return jacobian


static func _add_gram(matrix: PackedFloat64Array, jacobian: PackedFloat64Array, mass: float, n: int, corner: int) -> void:
	# Hub Jacobians have seven active generalized coordinates: body translation,
	# body rotation, and this corner's travel. Skip the seven-by-seven zero rows.
	var travel_dof := 6 + corner
	for row_local in 7:
		var row := row_local if row_local < 6 else travel_dof
		for column_local in 7:
			var column := column_local if column_local < 6 else travel_dof
			var value := (
				jacobian[row] * jacobian[column]
				+ jacobian[n + row] * jacobian[n + column]
				+ jacobian[2 * n + row] * jacobian[2 * n + column]
			)
			matrix[row * n + column] += mass * value


static func _add_rotor_inertia(
	matrix: PackedFloat64Array,
	axis: PackedFloat64Array,
	corner: int,
	inertia: float,
	n: int,
) -> void:
	var spin_dof := 10 + corner
	for row in 3:
		var body_row := 3 + row
		for column in 3:
			var body_column := 3 + column
			matrix[body_row * n + body_column] += inertia * axis[row] * axis[column]
		matrix[body_row * n + spin_dof] += inertia * axis[row]
		matrix[spin_dof * n + body_row] += inertia * axis[row]
	matrix[spin_dof * n + spin_dof] += inertia


static func _hub_bias_generalized(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int, mass: float, bias: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(GENERALIZED_SIZE)
	for axis in 3:
		result[axis] = mass * bias[axis]
	var moment := M.cross(r, bias)
	for axis in 3:
		result[3 + axis] = mass * moment[axis]
	result[6 + corner] = mass * M.dot(r_prime, bias)
	return result


static func _hub_gravity_generalized(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int, mass: float, gravity_body: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(GENERALIZED_SIZE)
	for axis in 3:
		result[axis] = mass * gravity_body[axis]
	var moment := M.cross(r, gravity_body)
	for axis in 3:
		result[3 + axis] = mass * moment[axis]
	result[6 + corner] = mass * M.dot(r_prime, gravity_body)
	return result


static func _add_contact_force(
	rhs: PackedFloat64Array,
	r: PackedFloat64Array,
	force_body: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	corner: int,
	spin_axis: PackedFloat64Array,
	rho_body: PackedFloat64Array,
) -> void:
	for axis in 3:
		rhs[axis] += force_body[axis]
	var moment := M.cross(M.add(r, rho_body), force_body)
	for axis in 3:
		rhs[3 + axis] += moment[axis]
	rhs[6 + corner] += M.dot(r_prime, force_body)
	rhs[10 + corner] += M.dot(spin_axis, M.cross(rho_body, force_body))


static func _add_body_force(rhs: PackedFloat64Array, point_body: PackedFloat64Array, force_body: PackedFloat64Array) -> void:
	for axis in 3:
		rhs[axis] += force_body[axis]
	var moment := M.cross(point_body, force_body)
	for axis in 3:
		rhs[3 + axis] += moment[axis]


static func _tire_contact_rows(
	q_conjugate: PackedFloat64Array,
	forward_world: PackedFloat64Array,
	lateral_world: PackedFloat64Array,
	r: PackedFloat64Array,
	rho: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	spin_axis: PackedFloat64Array,
	corner: int,
) -> Array[PackedFloat64Array]:
	var rows: Array[PackedFloat64Array] = []
	rows.append(_contact_row(q_conjugate, forward_world, M.add(r, rho), r_prime, spin_axis, rho, corner))
	rows.append(_contact_row(q_conjugate, lateral_world, M.add(r, rho), r_prime, spin_axis, rho, corner))
	return rows


static func _contact_row(
	q_conjugate: PackedFloat64Array,
	direction_world: PackedFloat64Array,
	lever_body: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	spin_axis: PackedFloat64Array,
	rho: PackedFloat64Array,
	corner: int,
) -> PackedFloat64Array:
	var direction_body := M.q_rotate(q_conjugate, direction_world)
	var row := PackedFloat64Array()
	row.resize(GENERALIZED_SIZE)
	for axis in 3:
		row[axis] = direction_body[axis]
	var moment := M.cross(lever_body, direction_body)
	for axis in 3:
		row[3 + axis] = moment[axis]
	row[6 + corner] = M.dot(r_prime, direction_body)
	row[10 + corner] = M.dot(spin_axis, M.cross(rho, direction_body))
	return row


static func _tire_contact_bias(
	q: PackedFloat64Array,
	body_rate: PackedFloat64Array,
	hub_bias: PackedFloat64Array,
	hub_velocity: PackedFloat64Array,
	wheel_omega: PackedFloat64Array,
	spin_axis_rate: PackedFloat64Array,
	steer_rate_left: float,
	steer_accel_left: float,
	wheel_spin: float,
	rho_body: PackedFloat64Array,
) -> Dictionary:
	var angular_convective := M.add(
		M.cross(body_rate, wheel_omega),
	M.add(
		M.scale(PackedFloat64Array([0.0, 0.0, -1.0]), steer_accel_left),
		M.scale(spin_axis_rate, wheel_spin),
	)
	)
	var point_bias_body := M.add(
		hub_bias,
		M.cross(angular_convective, rho_body),
	)
	var point_bias_world := M.q_rotate(q, point_bias_body)
	# The surface normal's spatial derivative is unavailable in the road API;
	# this local constraint therefore treats the sampled plane as tangent-fixed.
	if not _finite_array(point_bias_world) or not is_finite(steer_rate_left) or not _finite_array(hub_velocity):
		return _failure("Tire contact bias became non-finite")
	return {"ok": true, "bias": point_bias_world}


static func _solve_tangent_friction(
	factor: Dictionary,
	acceleration: PackedFloat64Array,
	contacts: Array[Dictionary],
	longitudinal_force: PackedFloat64Array,
	lateral_force: PackedFloat64Array,
	brake_torque: PackedFloat64Array,
	adaptive_early_out: bool = true,
) -> Dictionary:
	if contacts.is_empty():
		return {"ok": true, "acceleration": acceleration, "sweeps_used": 0}
	var rows: Array[PackedFloat64Array] = []
	var columns: Array[PackedFloat64Array] = []
	var contact_row_indexes: Array[PackedInt32Array] = []
	for contact in contacts:
		var contact_rows: Array = contact["rows"]
		var indexes := PackedInt32Array()
		for row_value in contact_rows:
			var row: PackedFloat64Array = row_value
			indexes.append(rows.size())
			rows.append(row)
			columns.append(_solve_generalized(factor, row))
		contact_row_indexes.append(indexes)
	var forces := PackedFloat64Array()
	forces.resize(rows.size())
	# Contact geometry and inverse mass are constant within this evaluation.
	# Cache local mobility blocks once, rather than redo 14-term dot products
	# on every solver sweep.
	var mobilities: Array[PackedFloat64Array] = []
	for contact_index in contacts.size():
		var indexes: PackedInt32Array = contact_row_indexes[contact_index]
		var i0 := indexes[0]
		var w00 := _dot_generalized(rows[i0], columns[i0])
		if indexes.size() == 1:
			if not is_finite(w00) or w00 <= 1.0e-18:
				return _failure("Wheel brake mobility is singular")
			mobilities.append(PackedFloat64Array([w00]))
			continue
		var i1 := indexes[1]
		var w01 := _dot_generalized(rows[i0], columns[i1])
		var w10 := _dot_generalized(rows[i1], columns[i0])
		var w11 := _dot_generalized(rows[i1], columns[i1])
		var determinant := w00 * w11 - w01 * w10
		if not is_finite(determinant) or determinant <= 1.0e-18:
			return _failure("Tangent contact mobility is singular")
		mobilities.append(PackedFloat64Array([w00, w01, w10, w11, determinant]))
	var slip_bias: Array[PackedFloat64Array] = []
	for contact in contacts:
		if str(contact["kind"]) == "brake":
			slip_bias.append(PackedFloat64Array([0.0]))
			continue
		var bias_world: PackedFloat64Array = contact["bias"]
		var directions: Array = contact["directions"]
		var forward_direction: PackedFloat64Array = directions[0]
		var lateral_direction: PackedFloat64Array = directions[1]
		var bias := PackedFloat64Array([
			M.dot(forward_direction, bias_world), M.dot(lateral_direction, bias_world),
		])
		slip_bias.append(bias)
	var sweeps_used := 0
	for sweep in FRICTION_SWEEPS:
		var max_force_delta := 0.0
		var max_brake_torque_delta := 0.0
		for contact_index in contacts.size():
			var contact: Dictionary = contacts[contact_index]
			var indexes: PackedInt32Array = contact_row_indexes[contact_index]
			var i0 := indexes[0]
			if str(contact["kind"]) == "brake":
				var brake_row: PackedFloat64Array = rows[i0]
				var brake_column: PackedFloat64Array = columns[i0]
				var brake_mobility := mobilities[contact_index][0]
				var brake_slip: PackedFloat64Array = contact["slip"]
				var brake_tau := maxf(float(contact["tau"]), 1.0e-5)
				var current_brake := _dot_generalized(brake_row, acceleration) + slip_bias[contact_index][0]
				var target_brake := -brake_slip[0] / brake_tau
				var delta_brake := (target_brake - current_brake) / brake_mobility
				var brake_limit := maxf(0.0, float(contact["mu_load"]))
				var trial_brake := clampf(forces[i0] + delta_brake, -brake_limit, brake_limit)
				delta_brake = trial_brake - forces[i0]
				max_brake_torque_delta = maxf(max_brake_torque_delta, absf(delta_brake))
				forces[i0] = trial_brake
				for degree in GENERALIZED_SIZE:
					acceleration[degree] += brake_column[degree] * delta_brake
				brake_torque[int(contact["index"])] = trial_brake
				continue
			var i1 := indexes[1]
			var row0: PackedFloat64Array = rows[i0]
			var row1: PackedFloat64Array = rows[i1]
			var mobility: PackedFloat64Array = mobilities[contact_index]
			var w00 := mobility[0]
			var w01 := mobility[1]
			var w10 := mobility[2]
			var w11 := mobility[3]
			var determinant := mobility[4]
			var current_long := _dot_generalized(row0, acceleration) + slip_bias[contact_index][0]
			var current_lateral := _dot_generalized(row1, acceleration) + slip_bias[contact_index][1]
			var slip: PackedFloat64Array = contact["slip"]
			var tau := maxf(float(contact["tau"]), 1.0e-5)
			var target_long := -slip[0] / tau
			var target_lateral := -slip[1] / tau
			var error_long := target_long - current_long
			var error_lateral := target_lateral - current_lateral
			var delta_long := (w11 * error_long - w01 * error_lateral) / determinant
			var delta_lateral := (-w10 * error_long + w00 * error_lateral) / determinant
			var trial_long := forces[i0] + delta_long
			var trial_lateral := forces[i1] + delta_lateral
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			var projected := _project_friction_circle(w00, w01, w10, w11, trial_long, trial_lateral, force_limit)
			trial_long = projected[0]
			trial_lateral = projected[1]
			delta_long = trial_long - forces[i0]
			delta_lateral = trial_lateral - forces[i1]
			max_force_delta = maxf(max_force_delta, maxf(absf(delta_long), absf(delta_lateral)))
			forces[i0] = trial_long
			forces[i1] = trial_lateral
			for degree in GENERALIZED_SIZE:
				acceleration[degree] += columns[i0][degree] * delta_long + columns[i1][degree] * delta_lateral
			if str(contact["kind"]) == "wheel":
				var corner := int(contact["index"])
				longitudinal_force[corner] = trial_long
				lateral_force[corner] = trial_lateral
		sweeps_used = sweep + 1
		if adaptive_early_out \
				and max_force_delta <= FRICTION_CONVERGENCE_FORCE_TOLERANCE_N \
				and max_brake_torque_delta <= BRAKE_CONVERGENCE_TORQUE_TOLERANCE_N_M:
			break
	return {"ok": true, "acceleration": acceleration, "sweeps_used": sweeps_used}


## Minimize .5*f'W*f - (W*free_force)'f subject to |f| <= limit.
## A radial clamp solves this only when contact mobility W is isotropic.
## Wheel spin makes longitudinal and lateral mobility very different.
## The KKT multiplier has a finite upper bound |W*free_force|/limit for
## positive-definite W. Return the feasible side of the bounded bisection.
static func _project_friction_circle(
	w00: float, w01: float, w10: float, w11: float,
	free_x: float, free_y: float, limit: float,
) -> PackedFloat64Array:
	if limit <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	if free_x * free_x + free_y * free_y <= limit * limit:
		return PackedFloat64Array([free_x, free_y])
	var b0 := w00 * free_x + w01 * free_y
	var b1 := w10 * free_x + w11 * free_y
	var lower := 0.0
	var upper := M.sqrt_(b0 * b0 + b1 * b1) / limit
	for _iteration in 32:
		var multiplier := 0.5 * (lower + upper)
		var a00 := w00 + multiplier
		var a11 := w11 + multiplier
		var determinant := a00 * a11 - w01 * w10
		var fx := (a11 * b0 - w01 * b1) / determinant
		var fy := (a00 * b1 - w10 * b0) / determinant
		if fx * fx + fy * fy > limit * limit:
			lower = multiplier
		else:
			upper = multiplier
	var a00 := w00 + upper
	var a11 := w11 + upper
	var determinant := a00 * a11 - w01 * w10
	return PackedFloat64Array([(a11 * b0 - w01 * b1) / determinant,
		(a00 * b1 - w10 * b0) / determinant])


static func _matrix_vector(matrix: PackedFloat64Array, vector: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(n)
	for row in n:
		var value := 0.0
		for column in n:
			value += matrix[row * n + column] * vector[column]
		result[row] = value
	return result


static func _cholesky_factor(matrix: PackedFloat64Array, n: int) -> Dictionary:
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var lower := PackedFloat64Array()
	lower.resize(n * n)
	var scale := 0.0
	for i in n:
		scale = maxf(scale, absf(matrix[i * n + i]))
	if not is_finite(scale) or scale <= 0.0:
		return {"ok": false, "error": "nonpositive matrix scale"}
	for row in n:
		for column in range(row + 1):
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite matrix entry"}
			for k in column:
				value -= lower[row * n + k] * lower[column * n + k]
			if row == column:
				if value <= scale * MATRIX_PIVOT_RELATIVE_TOLERANCE:
					return {"ok": false, "error": "nonpositive Cholesky pivot"}
				lower[row * n + column] = M.sqrt_(value)
			else:
				lower[row * n + column] = value / lower[column * n + column]
	return {"ok": true, "lower": lower}


## Exploit the exact block structure of the generalized mass matrix. The first
## six coordinates are sprung-body motion; each of the eight remaining local
## wheel coordinates has a positive diagonal mass and couples only to that
## six-coordinate block. This Schur factorization is algebraically equivalent
## to factoring the full 14x14 matrix, while reducing dense work in every RK
## stage and every tire-contact mobility solve.
static func _factor_generalized_mass_matrix(matrix: PackedFloat64Array) -> Dictionary:
	if matrix.size() != GENERALIZED_SIZE * GENERALIZED_SIZE:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var local_mass := PackedFloat64Array()
	local_mass.resize(8)
	var coupling := PackedFloat64Array()
	coupling.resize(6 * 8)
	for local in 8:
		var dof := 6 + local
		var mass := matrix[dof * GENERALIZED_SIZE + dof]
		if not is_finite(mass) or mass <= 0.0:
			return {"ok": false, "error": "nonpositive local generalized mass"}
		local_mass[local] = mass
		for body in 6:
			var value := matrix[body * GENERALIZED_SIZE + dof]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite generalized coupling"}
			coupling[body * 8 + local] = value
	var schur := PackedFloat64Array()
	schur.resize(6 * 6)
	for row in 6:
		for column in 6:
			var value := matrix[row * GENERALIZED_SIZE + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite sprung-body mass entry"}
			for local in 8:
				value -= coupling[row * 8 + local] * coupling[column * 8 + local] / local_mass[local]
			schur[row * 6 + column] = value
	var body_factor := _cholesky_factor(schur, 6)
	if not bool(body_factor["ok"]):
		return body_factor
	return {
		"ok": true,
		"body_lower": body_factor["lower"],
		"coupling": coupling,
		"local_mass": local_mass,
	}


static func _solve_generalized(factor: Dictionary, rhs: PackedFloat64Array) -> PackedFloat64Array:
	if rhs.size() != GENERALIZED_SIZE or not factor.has("body_lower") \
			or not factor.has("coupling") or not factor.has("local_mass"):
		return PackedFloat64Array()
	var body_lower: PackedFloat64Array = factor["body_lower"]
	var coupling: PackedFloat64Array = factor["coupling"]
	var local_mass: PackedFloat64Array = factor["local_mass"]
	if body_lower.size() != 36 or coupling.size() != 48 or local_mass.size() != 8:
		return PackedFloat64Array()
	var adjusted_body := PackedFloat64Array()
	adjusted_body.resize(6)
	for body in 6:
		adjusted_body[body] = rhs[body]
	for local in 8:
		var adjusted_local := rhs[6 + local] / local_mass[local]
		for body in 6:
			adjusted_body[body] -= coupling[body * 8 + local] * adjusted_local
	var body_solution := _solve_cholesky(body_lower, adjusted_body, 6)
	if body_solution.size() != 6:
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(GENERALIZED_SIZE)
	for body in 6:
		result[body] = body_solution[body]
	for local in 8:
		var value := rhs[6 + local]
		for body in 6:
			value -= coupling[body * 8 + local] * body_solution[body]
		result[6 + local] = value / local_mass[local]
	return result if _finite_array(result) else PackedFloat64Array()


static func _solve_cholesky(lower: PackedFloat64Array, rhs: PackedFloat64Array, n: int) -> PackedFloat64Array:
	if lower.size() != n * n or rhs.size() != n:
		return PackedFloat64Array()
	var forward := PackedFloat64Array()
	forward.resize(n)
	for row in n:
		var value := rhs[row]
		for column in row:
			value -= lower[row * n + column] * forward[column]
		var diagonal := lower[row * n + row]
		if not is_finite(value) or not is_finite(diagonal) or diagonal <= 0.0:
			return PackedFloat64Array()
		forward[row] = value / diagonal
	var solution := PackedFloat64Array()
	solution.resize(n)
	for row in range(n - 1, -1, -1):
		var value := forward[row]
		for column in range(row + 1, n):
			value -= lower[column * n + row] * solution[column]
		var diagonal := lower[row * n + row]
		if not is_finite(value) or not is_finite(diagonal) or diagonal <= 0.0:
			return PackedFloat64Array()
		solution[row] = value / diagonal
	return solution


static func _dot_generalized(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var result := 0.0
	for i in GENERALIZED_SIZE:
		result += a[i] * b[i]
	return result


static func _invert_matrix(matrix: PackedFloat64Array, n: int) -> Dictionary:
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var width := 2 * n
	var augmented := PackedFloat64Array()
	augmented.resize(n * width)
	var scale := 0.0
	for row in n:
		for column in n:
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite matrix entry"}
			augmented[row * width + column] = value
			scale = maxf(scale, absf(value))
		augmented[row * width + n + row] = 1.0
	if scale <= 0.0:
		return {"ok": false, "error": "zero matrix"}
	for pivot_column in n:
		var pivot_row := pivot_column
		for row in range(pivot_column + 1, n):
			if absf(augmented[row * width + pivot_column]) > absf(augmented[pivot_row * width + pivot_column]):
				pivot_row = row
		var pivot := augmented[pivot_row * width + pivot_column]
		if not is_finite(pivot) or absf(pivot) <= scale * MATRIX_PIVOT_RELATIVE_TOLERANCE:
			return {"ok": false, "error": "pivot is below relative precision threshold"}
		if pivot_row != pivot_column:
			for column in width:
				var swap := augmented[pivot_column * width + column]
				augmented[pivot_column * width + column] = augmented[pivot_row * width + column]
				augmented[pivot_row * width + column] = swap
		pivot = augmented[pivot_column * width + pivot_column]
		for column in width:
			augmented[pivot_column * width + column] /= pivot
		for row in n:
			if row == pivot_column:
				continue
			var factor := augmented[row * width + pivot_column]
			for column in width:
				augmented[row * width + column] -= factor * augmented[pivot_column * width + column]
	var inverse := PackedFloat64Array()
	inverse.resize(n * n)
	for row in n:
		for column in n:
			var value := augmented[row * width + n + column]
			if not is_finite(value):
				return {"ok": false, "error": "inverse became non-finite"}
			inverse[row * n + column] = value
	return {"ok": true, "inverse": inverse}


static func _travel_stop_force(travel: float, travel_rate: float, model: Dictionary) -> float:
	var bump := float(model["travel_bump_m"])
	var droop := float(model["travel_droop_m"])
	if travel > bump:
		return -(
			float(model["bump_stop_stiffness_n_per_m"]) * (travel - bump)
			+ float(model["bump_stop_damping_n_s_per_m"]) * maxf(travel_rate, 0.0)
		)
	if travel < -droop:
		return (
			float(model["droop_stop_stiffness_n_per_m"]) * (-droop - travel)
			+ float(model["droop_stop_damping_n_s_per_m"]) * maxf(-travel_rate, 0.0)
		)
	return 0.0


static func _sample_surface(road: Callable, north: float, east: float) -> Dictionary:
	if not road.is_valid() or not is_finite(north) or not is_finite(east):
		return _failure("Invalid road sample request")
	var raw: Variant = road.call(north, east)
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("Road callback must return a Dictionary")
	var surface: Dictionary = raw
	if not surface.has("height_m") or not surface.has("normal_ned") or not surface.has("mu") or not surface.has("rolling"):
		return _failure("Road callback omitted height, normal, friction, or rolling resistance")
	var normal_variant: Variant = surface["normal_ned"]
	if typeof(normal_variant) != TYPE_PACKED_FLOAT64_ARRAY:
		return _failure("Road normal must be a PackedFloat64Array")
	var normal: PackedFloat64Array = normal_variant
	if normal.size() != 3 or not _finite_array(normal):
		return _failure("Road normal must contain three finite NED values")
	var normal_length := M.norm(normal)
	if absf(normal_length - 1.0) > 1.0e-5:
		return _failure("Road normal must be unit length")
	var height := float(surface["height_m"])
	var mu := float(surface["mu"])
	var rolling := float(surface["rolling"])
	if not is_finite(height) or not is_finite(mu) or not is_finite(rolling) or mu < 0.0 or rolling < 0.0:
		return _failure("Road height/friction/rolling values must be finite and nonnegative where applicable")
	return {"ok": true, "surface": surface}


static func _valid_model(model: Dictionary) -> bool:
	var scalars := [
		"sprung_mass_kg", "unsprung_mass_kg", "wheel_spin_inertia_kg_m2", "gravity_m_per_s2",
		"arm_inner_offset_m", "arm_length_m", "cg_height_above_chassis_datum_m",
		"wheel_center_rest_below_chassis_datum_m", "tire_radius_m",
		"suspension_stiffness_n_per_m", "suspension_damping_n_s_per_m",
		"tire_stiffness_n_per_m", "tire_damping_n_s_per_m", "tire_slip_relaxation_s",
		"travel_droop_m", "travel_bump_m", "bump_stop_stiffness_n_per_m",
		"bump_stop_damping_n_s_per_m", "droop_stop_stiffness_n_per_m",
		"droop_stop_damping_n_s_per_m", "drive_torque_per_wheel_nm",
		"brake_torque_per_wheel_nm", "reverse_torque_fraction", "drive_torque_fade_rad_s",
		"rolling_resistance_coefficient", "tire_friction_scale", "max_steer_angle_rad",
		"steer_servo_natural_frequency_rad_s", "steer_servo_damping_ratio",
		"hull_contact_stiffness_n_per_m", "hull_contact_damping_n_s_per_m",
		"hull_contact_friction_scale",
	]
	for key in scalars:
		if not model.has(key) or not is_finite(float(model[key])):
			return false
	var positive := [
		"sprung_mass_kg", "unsprung_mass_kg", "wheel_spin_inertia_kg_m2", "arm_length_m",
		"tire_radius_m", "suspension_stiffness_n_per_m", "tire_stiffness_n_per_m",
		"tire_slip_relaxation_s", "travel_droop_m", "travel_bump_m",
		"bump_stop_stiffness_n_per_m", "droop_stop_stiffness_n_per_m",
		"max_steer_angle_rad", "steer_servo_natural_frequency_rad_s",
		"hull_contact_stiffness_n_per_m",
	]
	for key in positive:
		if float(model[key]) <= 0.0:
			return false
	var nonnegative := [
		"gravity_m_per_s2", "arm_inner_offset_m", "cg_height_above_chassis_datum_m",
		"wheel_center_rest_below_chassis_datum_m", "suspension_damping_n_s_per_m",
		"tire_damping_n_s_per_m", "bump_stop_damping_n_s_per_m", "droop_stop_damping_n_s_per_m",
		"drive_torque_per_wheel_nm", "brake_torque_per_wheel_nm", "reverse_torque_fraction",
		"drive_torque_fade_rad_s", "rolling_resistance_coefficient", "tire_friction_scale",
		"steer_servo_damping_ratio", "hull_contact_damping_n_s_per_m", "hull_contact_friction_scale",
	]
	for key in nonnegative:
		if float(model[key]) < 0.0:
			return false
	var brake_split: Variant = model.get("brake_front_fraction", 0.5)
	if typeof(brake_split) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(brake_split)) \
			or float(brake_split) < 0.0 or float(brake_split) > 1.0:
		return false
	if not model.has("sprung_inertia_kg_m2") or not model.has("corner_x_m") or not model.has("corner_y_m"):
		return false
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	var corner_x: PackedFloat64Array = model["corner_x_m"]
	var corner_y: PackedFloat64Array = model["corner_y_m"]
	if inertia.size() != 6 or corner_x.size() != CORNER_COUNT or corner_y.size() != CORNER_COUNT:
		return false
	if not _finite_array(inertia) or not _finite_array(corner_x) or not _finite_array(corner_y):
		return false
	if inertia[0] <= 0.0 or inertia[1] <= 0.0 or inertia[2] <= 0.0:
		return false
	if not model.has("hull_probe_centers_frd_m") or not model.has("hull_probe_radii_m"):
		return false
	var centers: PackedFloat64Array = model["hull_probe_centers_frd_m"]
	var radii: PackedFloat64Array = model["hull_probe_radii_m"]
	if centers.is_empty() or centers.size() % 3 != 0 or radii.size() * 3 != centers.size():
		return false
	if not _finite_array(centers) or not _finite_array(radii):
		return false
	for radius in radii:
		if radius <= 0.0:
			return false
	for corner in CORNER_COUNT:
		if corner_y[corner] == 0.0 or absf(corner_x[corner]) >= 10.0 or absf(corner_y[corner]) >= 10.0:
			return false
	return true


static func _valid_controls(controls: Dictionary) -> bool:
	if not _valid_external_force(controls): return false
	if not controls.has("throttle") or not controls.has("steering") or not controls.has("brake") or not controls.has("reverse"):
		return false
	var throttle := float(controls["throttle"])
	var steering := float(controls["steering"])
	var brake := float(controls["brake"])
	return is_finite(throttle) and throttle >= 0.0 and throttle <= 1.0 \
		and is_finite(steering) and steering >= -1.0 and steering <= 1.0 \
		and is_finite(brake) and brake >= 0.0 and brake <= 1.0 \
		and typeof(controls["reverse"]) == TYPE_BOOL


static func _valid_external_force(controls: Dictionary) -> bool:
	if not controls.has("external_generalized_force"): return true
	var value: Variant = controls.external_generalized_force
	return typeof(value) == TYPE_PACKED_FLOAT64_ARRAY and value.size() == GENERALIZED_SIZE and _finite_array(value)


static func _has_external_force(controls: Dictionary) -> bool:
	if not controls.has("external_generalized_force"): return false
	for value in controls.external_generalized_force:
		if value != 0.0: return true
	return false


static func _valid_pose(pose: Dictionary) -> bool:
	for key in ["north_m", "east_m", "heading_rad", "vehicle_up_m"]:
		if not pose.has(key) or not is_finite(float(pose[key])):
			return false
	return true


static func _valid_attitude(state: PackedFloat64Array) -> bool:
	var length := _quaternion_length(state)
	return is_finite(length) and length > 1.0e-10 and absf(length - 1.0) < 1.0e-3


static func _quaternion_length(state: PackedFloat64Array) -> float:
	var q := _state_quaternion(state)
	return M.sqrt_(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])


static func _derivative_is_exactly_zero(value: PackedFloat64Array) -> bool:
	if value.size() != STATE_SIZE:
		return false
	for component in value:
		if component != 0.0:
			return false
	return true


static func _is_quiescent_level_state(state: PackedFloat64Array, controls: Dictionary) -> bool:
	if float(controls["throttle"]) != 0.0 or float(controls["steering"]) != 0.0 or float(controls["brake"]) != 0.0:
		return false
	var q := _state_quaternion(state)
	if absf(absf(q[0]) - 1.0) > 1.0e-12 or absf(q[1]) > 1.0e-12 or absf(q[2]) > 1.0e-12 or absf(q[3]) > 1.0e-12:
		return false
	for index in 3:
		if state[VEL + index] != 0.0 or state[RATE + index] != 0.0:
			return false
	for corner in CORNER_COUNT:
		if state[TRAVEL_RATE + corner] != 0.0 or state[WHEEL_SPIN + corner] != 0.0:
			return false
	return state[STEER] == 0.0 and state[STEER_RATE] == 0.0


static func _state_quaternion(state: PackedFloat64Array) -> PackedFloat64Array:
	return M.quat(state[ATT], state[ATT + 1], state[ATT + 2], state[ATT + 3])


static func _quaternion_rate_component(state: PackedFloat64Array, rate: PackedFloat64Array, component: int) -> float:
	var qdot := M.q_mul(_state_quaternion(state), M.quat(0.0, rate[0], rate[1], rate[2]))
	return 0.5 * qdot[component]


static func _slice3(state: PackedFloat64Array, index: int) -> PackedFloat64Array:
	return PackedFloat64Array([state[index], state[index + 1], state[index + 2]])


static func _symmetric_inertia_mul(inertia: PackedFloat64Array, value: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		inertia[0] * value[0] + inertia[3] * value[1] + inertia[4] * value[2],
		inertia[3] * value[0] + inertia[1] * value[1] + inertia[5] * value[2],
		inertia[4] * value[0] + inertia[5] * value[1] + inertia[2] * value[2],
	])


static func _add_scaled_vector(target: PackedFloat64Array, value: PackedFloat64Array, scale: float) -> void:
	for i in target.size():
		target[i] += scale * value[i]


static func _static_travel(model: Dictionary) -> float:
	if float(model["gravity_m_per_s2"]) <= 0.0:
		return 0.0
	return float(model["sprung_mass_kg"]) * float(model["gravity_m_per_s2"]) \
		/ (4.0 * float(model["suspension_stiffness_n_per_m"]))


static func _check_static_spawn_patch(
	model: Dictionary,
	road: Callable,
	north_m: float,
	east_m: float,
	heading_rad: float,
	travel: float,
) -> Dictionary:
	var arm_length := float(model["arm_length_m"])
	if absf(travel) >= arm_length:
		return _failure("Static suspension travel reaches the A-arm singularity")
	var q := M.q_from_euler(heading_rad, 0.0, 0.0)
	var x: PackedFloat64Array = model["corner_x_m"]
	var y: PackedFloat64Array = model["corner_y_m"]
	var heights := PackedFloat64Array()
	heights.resize(CORNER_COUNT)
	var mean_height := 0.0
	for corner in CORNER_COUNT:
		var side := signf(y[corner])
		var lateral_offset := M.sqrt_(arm_length * arm_length - travel * travel)
		var r := PackedFloat64Array([
			x[corner],
			y[corner] + side * (lateral_offset - arm_length),
			float(model["cg_height_above_chassis_datum_m"])
				+ float(model["wheel_center_rest_below_chassis_datum_m"]) - travel,
		])
		var world_offset := M.q_rotate(q, r)
		var sample_result := _sample_surface(road, north_m + world_offset[0], east_m + world_offset[1])
		if not bool(sample_result["ok"]):
			return _failure("Could not sample a spawn tire patch: " + str(sample_result["error"]))
		var surface: Dictionary = sample_result["surface"]
		var normal: PackedFloat64Array = surface["normal_ned"]
		if M.norm(M.sub(normal, PackedFloat64Array([0.0, 0.0, -1.0]))) > 1.0e-5:
			return _failure("Static spawn requires an upward level surface")
		heights[corner] = float(surface["height_m"])
		mean_height += heights[corner] / float(CORNER_COUNT)
	for corner in CORNER_COUNT:
		if absf(heights[corner] - mean_height) > 1.0e-4:
			return _failure("Static spawn requires a flat patch across all four tires")
	return {"ok": true, "mean_height_m": mean_height, "corner_heights_m": heights}


static func _energy_from_terms(
	state: PackedFloat64Array,
	model: Dictionary,
	body_rate: PackedFloat64Array,
	hub_kinetic: float,
	rotor_kinetic: float,
	gravity_potential: float,
	spring_energy: float,
	tire_energy: float,
	hull_energy: float,
) -> float:
	var body_velocity := _slice3(state, VEL)
	var energy_value := (
		0.5 * float(model["sprung_mass_kg"]) * M.dot(body_velocity, body_velocity)
		+ 0.5 * M.dot(body_rate, _symmetric_inertia_mul(model["sprung_inertia_kg_m2"], body_rate))
		+ hub_kinetic + rotor_kinetic + gravity_potential + spring_energy + tire_energy + hull_energy
	)
	return energy_value


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
