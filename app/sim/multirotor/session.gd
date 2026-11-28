# DR-16b: dedicated headless multirotor flight session. Owns one Simulation stepping the closed-loop plant
# (physics/multirotor/controlled_plant.gd) through the framed sampled protocol, the field environment (surface table,
# calm or steady uniform wind), an optional immutable obstacle inventory, the accepted pilot tape and the session
# checkpoint envelope (FPV engineering contracts §3, §4 "Session envelope", §6).
#
# Ticks come only from tick_once(); the engine physics loop never steps this kernel. A pilot frame outside its domain
# is refused before the kernel sees it. Every controller memory, held command, arming latch, pack charge and cut latch
# lives in the kernel's checkpointed arrays; the session adds only the accepted tape, the published crash record and
# the pause/fault flags of the envelope. prepare() builds the whole candidate (data, rates, plant, environment, start
# frame and a separate committed kernel) before it replaces anything, so a refusal keeps the running flight.
# Research-grade estimated data; nothing here is validated against flight data. 64-bit floats only.
extends Node

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const WindFieldLaw := preload("res://physics/wind_field.gd")
const WindSettings := preload("res://physics/wind_config.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const FpvForest := preload("res://scenery/fpv_forest.gd")
const FrameContact := preload("res://sim/multirotor/frame_obstacle_contact.gd")
const SweptProp := preload("res://sim/multirotor/swept_prop_contact.gd")
const Track := preload("res://sim/race/track.gd")
const AirfieldTrack := preload("res://physics/ground_vehicle/airfield_track.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const RaceDirector := preload("res://sim/race/race_director.gd")

const FORMAT := "openrc-multirotor-session v1"
const DEFAULT_DATA := "res://data/multirotors/openrc-fpv5-x1.json"
const FIXED_HZ := 240
const MAX_TAPE_TICKS := FIXED_HZ * 60 * 30
const MAX_WIND_MPS := 8.0
const FOCUS_PAUSE := "Paused: the window lost focus."
const TAPE_FULL := "Paused: the input tape is full (30 minutes); reset to fly again."
const READY := "Ready. Cycle the arm switch OFF then ON at low throttle."
## CR-AUD-01: an enabled lake is part of the collision environment. The quad has no water force model, so water contact
## is a terminal, observable crash (never silent dry ground, never invented flotation).
const WATER_CRASH := "Water contact"
const WATER_PAUSE := "Water contact: the quad is down. Restart on the pad to fly again."
## Clearance (m) added to the airframe radius when refusing a start beside the water.
const WATER_START_MARGIN_M := 0.5
## Obstacle query reach beyond the airframe sphere (m); the plant decides a strike at the sphere radius.
const OBSTACLE_SLACK_M := 0.5
## Contact terrain law (DR-22/R1, contact_ground): linearization square (m), memo bound (entries) and the coordinate
## bound of the square index (Vector2i cells stay inside int32 below it).
const TERRAIN_CELL_M := 1.0e-4
const TERRAIN_MEMO_MAX := 256 # a parked quad uses 10-20 squares; a small memo clears in microseconds
const TERRAIN_MEMO_REACH_M := 1.0e5
## Obstacle broad phase (DR-22/R1): index cell size (m) and the cell count above which a proxy is tested always.
const OBSTACLE_INDEX_CELL_M := 4.0
const OBSTACLE_INDEX_MAX_CELLS := 256
const ENVELOPE_KEYS := ["format", "identity", "kernel", "crash", "tape_ticks", "paused", "collision_identity", "results"]
## DR-26: bound of the pending race-result outbox. A full outbox refuses another race start or attempt replacement
## until results are saved or discarded; an in-memory record is not durable before save_results() confirms it.
const MAX_PENDING_RESULTS := 8
const RESULTS_DIRECTORY := "user://race_results"
const RACE_EVENT_TYPES := ["race_countdown", "race_go", "race_gate", "race_lap", "race_finish", "race_abort",
	"race_refused", "race_cancelled"]

signal tick_advanced(tick: int, time_s: float)
## One accepted crash event; the aftermath keeps simulating with the drive cut.
signal crashed(reason: String)
## One accepted pack-depletion event.
signal depleted()
signal pause_changed(paused: bool, reason: String)
signal faulted(reason: String)
## Emitted before a reset, restore or reconfiguration replaces the flight (recorders close their file here).
signal resetting
## DR-25/26 (race sessions only): every accepted race event, and the terminal record of a finished or aborted attempt.
signal race_event(event: Dictionary)
signal race_result(result: Dictionary)
## DR-19c: a non-terminal impact, prop damage or (DR-19f) sliding scrape of an accepted tick
## ({type = "impact" | "prop_damage" | "scrape", ...}).
signal impact(event: Dictionary)

var sim: Node
var environment: SimEnvironment = SimEnvironment.new()
var plant: RefCounted
var prepared := false
var paused := true
var pause_reason := "prepared"
var load_error := ""
var fault_reason := ""
## {} or {reason, tick, time_s} of the accepted crash event.
var crash: Dictionary = {}
## The prepared multirotor document.
var data: Dictionary = {}
var options: Dictionary = {}
var source_sha256 := ""
## Race composition (option race_track): the race-state wrapper around the plant and its prepared course; null and
## empty for free flight. `results` is the pending terminal-record outbox (checkpointed in the envelope).
var race: RefCounted
var course: Dictionary = {}
var results: Array[Dictionary] = []
var _result_sequence := 0
## Test seam: Callable() -> String giving a new publication id ("" = generation failed). Default: 128 random bits.
var publication_id_source := Callable()
var _field: Dictionary = {}
## Resolved start pose {mode, north_m, east_m, heading_deg[, altitude_m], initial_soc, source_generation}.
var _start: Dictionary = {}
var _tape := PackedFloat64Array()
var _pending_events: Array = []
## Detached physical geometry for this quad. Other vehicle families use the shared field inventory.
var _obstacles := {solids = [], foliage = [], identity = ""}
var _body_radius := 0.0
## True while the kernel steps inside tick_once: session state (tape, crash record) is then mid-transition, so a
## checkpoint taken by an observer of the kernel's own signals would be incomplete (CR-AUD-17).
var _stepping := false


func _init() -> void:
	sim = Sim.new()
	_adopt(sim)


static func default_options() -> Dictionary:
	return {data_path = DEFAULT_DATA, rates = {}, throttle_policy = "absolute", start = "pad", altitude_m = 3.0,
		north_offset_m = 12.0, east_offset_m = 0.0, heading_deg = 0.0, wind_speed_mps = 0.0, wind_from_deg = 0.0,
		initial_soc = -1.0, source_generation = 0, throttle_limit = 1.0, race_track = "", rc_track = {}, crash_model = "strict"}


## Build every derived object detached, then replace the running configuration. Refusal keeps the old session,
## its tape and its recorder untouched. An empty `field` is flat fixture ground at height 0. Starts paused.
func prepare(field: Dictionary, requested: Dictionary = {}) -> bool:
	var built := _build(field, requested)
	if not built.ok:
		load_error = str(built.error)
		return false
	resetting.emit()
	var old: Node = sim
	remove_child(old)
	old.queue_free()
	sim = built.sim
	_adopt(sim)
	plant = built.plant
	environment = built.environment
	data = built.data
	options = built.options
	source_sha256 = built.sha256
	_field = built.field
	_start = built.start
	_body_radius = built.body_radius
	race = built.race
	course = built.course
	_tape = PackedFloat64Array()
	_pending_events = []
	crash = {}
	fault_reason = ""
	load_error = ""
	prepared = true
	_set_paused(true, "prepared")
	return true


func _build(field: Dictionary, requested: Dictionary) -> Dictionary:
	var opts := default_options()
	opts.merge(requested, true)
	opts = opts.duplicate(true)
	for key: String in ["altitude_m", "north_offset_m", "east_offset_m", "heading_deg", "wind_speed_mps", "wind_from_deg", "initial_soc"]:
		if typeof(opts.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			return _refused("option %s must be a number" % key)
	if typeof(opts.start) != TYPE_STRING or str(opts.start) not in ["pad", "air"]:
		return _refused("option start must be \"pad\" or \"air\"")
	if typeof(opts.throttle_policy) != TYPE_STRING or str(opts.throttle_policy) not in ["absolute", "rate"]:
		return _refused("option throttle_policy must be \"absolute\" or \"rate\"")
	var policy: int = FC.THROTTLE_RATE if opts.throttle_policy == "rate" else FC.THROTTLE_ABSOLUTE
	var generation_value: Variant = opts.get("source_generation")
	if typeof(generation_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(generation_value)) \
			or float(generation_value) < 0.0 or float(generation_value) != floorf(float(generation_value)) or float(generation_value) >= 9.0e15:
		return _refused("option source_generation must be a nonnegative integer")
	var generation := int(generation_value)
	var air: bool = opts.start == "air"
	var altitude := float(opts.altitude_m)
	if air and (not is_finite(altitude) or altitude <= 0.0 or altitude > 500.0):
		return _refused("an air start needs an altitude between 0 and 500 m")
	var heading := float(opts.heading_deg)
	if not is_finite(heading):
		return _refused("option heading_deg must be finite")
	var soc := float(opts.initial_soc)
	if not (soc == -1.0 or (soc >= 0.0 and soc <= 1.0)):
		return _refused("option initial_soc must be -1 (document default) or within [0, 1]")
	# Data: an in-memory prepared document (tests, Workshop) or the strict loader on a data file.
	var doc: Dictionary
	var sha := ""
	if opts.has("prepared_data"):
		if typeof(opts.prepared_data) != TYPE_DICTIONARY:
			return _refused("prepared_data must be a prepared multirotor document")
		var shape := _prepared_shape_error(opts.prepared_data)
		if not shape.is_empty():
			return _refused(shape)
		doc = opts.prepared_data.duplicate(true)
		sha = _sha256_hex(var_to_bytes(doc))
	else:
		if typeof(opts.get("data_path")) != TYPE_STRING:
			return _refused("option data_path must be a path")
		var loaded: Dictionary = Data.load_file(str(opts.data_path))
		if not loaded.ok:
			return _refused("; ".join(loaded.errors))
		var made: Dictionary = Data.prepare(loaded.data, str(loaded.sha256))
		if not made.ok:
			return _refused("; ".join(made.errors))
		doc = made.prepared
		sha = str(loaded.sha256)
		var shape := _prepared_shape_error(doc)
		if not shape.is_empty():
			return _refused(shape)
	# Audit A09: one physical-invariant list for both routes; a prepared document (tests, Workshop, a candidate
	# replay) meets the loader's bounds (passive drag, nonnegative resistances, positive-definite inertia, a pack
	# that carries the hover load). Nothing is built yet, so a refusal leaves an accepted session untouched.
	var invariants: PackedStringArray = Data.physical_invariant_errors(doc)
	if not invariants.is_empty():
		return _refused("multirotor model: " + "; ".join(invariants))
	if typeof(opts.rates) != TYPE_DICTIONARY:
		return _refused("option rates must be an openrc-rates profile or empty")
	var profile: Dictionary = Rates.default_profile() if opts.rates.is_empty() else opts.rates
	var rates_check: Dictionary = Rates.validate(profile)
	if not rates_check.ok:
		return _refused("; ".join(rates_check.errors))
	# Weather: calm or steady uniform wind.
	var wind_speed := float(opts.wind_speed_mps)
	if not is_finite(wind_speed) or wind_speed < 0.0 or wind_speed > MAX_WIND_MPS or not is_finite(float(opts.wind_from_deg)):
		return _refused("multirotor weather admits calm or steady wind up to %.1f m/s" % MAX_WIND_MPS)
	var weather_raw := WindSettings.defaults()
	weather_raw.speed_mps = wind_speed
	weather_raw.from_deg = fposmod(float(opts.wind_from_deg), 360.0)
	var built_weather := WindFieldLaw.build(weather_raw)
	if not built_weather.ok:
		return _refused("; ".join(built_weather.errors))
	var surfaces := PackedFloat64Array()
	if not field.is_empty():
		var table := GroundSurfaces.load_table()
		var built: Dictionary = GroundSurfaces.build(table.table, field) if table.ok else table
		if not built.ok:
			return _refused("; ".join(built.errors))
		surfaces = built.rects
		if not Terrain.is_valid_surface_table(surfaces):
			return _refused("field surface table is invalid")
	var candidate_env := SimEnvironment.new()
	candidate_env.surfaces = surfaces
	candidate_env.weather = built_weather.field
	# CR-AUD-01: the field's validated lake (option `lake`, the scene's published normalized definition; {} or absent
	# = no water) is composed into every terrain query, so the bed depression is honoured by contact, impact and
	# telemetry. A disabled lake keeps the exact dry arithmetic and leaves the options untouched.
	var lake_check: String = _install_lake(candidate_env, opts)
	if not lake_check.is_empty():
		return _refused(lake_check)
	# RC-TRACK: the club field's RC car circuit, when the pilot shows it, is solid relief for the quad as for the
	# airplanes and cars (the same float64 overlay on the field terrain); {} keeps the plain field.
	if typeof(opts.get("rc_track")) != TYPE_DICTIONARY:
		return _refused("option rc_track must be the RC circuit or empty")
	if not opts.rc_track.is_empty():
		if not AirfieldTrack.valid(opts.rc_track) or not AirfieldTrack.matches_field(field):
			return _refused("option rc_track is not a valid circuit for this field")
		candidate_env.terrain_overlay = opts.rc_track
	# Start pose: the pilot station plus the option offsets, on the terrain under it.
	var pilot: Dictionary = field.get("pilot", {north = 0.0, east = 0.0, down = 0.0})
	var north := float(pilot.north) + float(opts.north_offset_m)
	var east := float(pilot.east) + float(opts.east_offset_m)
	var under := candidate_env.ground(north, east)
	if under.size() != 3 or not is_finite(under[0]) or not is_finite(under[1]) or not is_finite(under[2]):
		return _refused("start position is outside the field")
	var start := {mode = str(opts.start), north_m = north, east_m = east, heading_deg = heading,
		initial_soc = soc, source_generation = generation}
	if air:
		start.altitude_m = altitude
	# Closed-loop plant: environment, terrain and obstacle queries are pure functions of immutable prepared data.
	if typeof(opts.throttle_limit) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(opts.throttle_limit)) \
			or float(opts.throttle_limit) < 0.2 or float(opts.throttle_limit) > 1.0:
		return _refused("option throttle_limit must lie in 0.2..1")
	# DR-19c: "strict" ends the flight at any hard contact (the original law); "graded" lets most impacts bounce or wear
	# the props (electrical law). Part of the model identity, so a log replays with the law it was flown with.
	if typeof(opts.get("crash_model")) != TYPE_STRING or not str(opts.crash_model) in ["strict", "graded"]:
		return _refused("option crash_model must be strict or graded")
	var created: Dictionary = Plant.create(doc, profile, policy, 0, float(opts.throttle_limit))
	if not created.ok:
		return _refused("; ".join(created.errors))
	var candidate_plant: RefCounted = created.plant
	candidate_plant.graded_impacts = str(opts.crash_model) == "graded"
	var captured_env := candidate_env
	candidate_plant.environment = captured_env
	candidate_plant.ground = contact_ground(captured_env)
	var exact_ground := func(n: float, e: float) -> PackedFloat64Array: return captured_env.ground(n, e)
	var radius := _airframe_radius(doc)
	# DR-23…26 race composition: a strict track for this field, its pad as the start, its gate frames as solids,
	# and the race-state wrapper as the one installed model. Free flight installs the plant's own model.
	var race_wrapper: RefCounted = null
	var race_course: Dictionary = {}
	var vehicle: RefCounted = candidate_plant.build()
	var framer: RefCounted = candidate_plant
	if typeof(opts.race_track) != TYPE_STRING:
		return _refused("option race_track must be a track path or empty")
	if not str(opts.race_track).is_empty():
		if air:
			return _refused("a race starts on the track's pad, not in the air")
		var loaded_track: Dictionary = Track.load_file(str(opts.race_track))
		if not loaded_track.ok:
			return _refused("; ".join(loaded_track.errors))
		var wood_index := {}
		if not collision_identity().is_empty():
			_prepare_obstacle_index(radius)
			wood_index = _obstacles.solid_index
		var made_course: Dictionary = Track.prepare(loaded_track.track, field, exact_ground, wood_index)
		if not made_course.ok:
			return _refused("; ".join(made_course.errors))
		race_course = made_course.course
		var wrapped: Dictionary = RaceModel.wrap(candidate_plant, race_course, false)
		if not wrapped.ok:
			return _refused("; ".join(wrapped.errors))
		race_wrapper = wrapped.wrapper
		vehicle = wrapped.model
		framer = race_wrapper
		start.north_m = float(race_course.pad.north)
		start.east_m = float(race_course.pad.east)
		start.heading_deg = float(race_course.pad.heading_deg)
		start.race_course = str(race_course.identity)
	if not candidate_env.lake.is_empty() and _start_near_water(candidate_env.lake, start, radius):
		return _refused("multirotor start refused: the start is over or beside the lake and water contact is a crash")
	var gate_frames: Array = _frame_proxies(race_course.get("frames", []))
	_install_obstacle_queries(candidate_plant, gate_frames, radius)
	if not candidate_env.lake.is_empty():
		# R2: water is adjudicated in the plant's endpoint transition, so the drive is cut like any crash.
		var lake: Dictionary = candidate_env.lake
		candidate_plant.water_contact = func(body: PackedFloat64Array, time_s: float) -> bool:
			return _water_contact(lake, body, radius, time_s)
	var frame := _start_frame(framer, doc, candidate_env, start)
	var kernel: Node = Sim.new()
	kernel.process_mode = Node.PROCESS_MODE_DISABLED
	if not kernel.set_model(vehicle):
		kernel.free()
		return _refused("multirotor vehicle model is malformed")
	kernel.mass = float(doc.mass_kg)
	kernel.inertia = doc.inertia_kg_m2.duplicate()
	kernel.gravity = candidate_env.gravity
	# The domain check is not a per-step kernel hook (cost); a start frame is validated here instead.
	var start_valid: bool = race_wrapper.validate(frame, {tick = 0, time_s = 0.0, dt = 1.0 / float(FIXED_HZ)}) \
		if race_wrapper != null else candidate_plant.state_validator(frame, {})
	if not start_valid:
		kernel.free()
		return _refused("multirotor start refused: the start frame is outside the model's domain")
	var neutral: PackedFloat64Array = FC.neutral_input(generation)
	var reset: Dictionary = kernel.prepare_reset_frame(frame,
		race_wrapper.input(neutral, RaceDirector.ACTION_NONE) if race_wrapper != null else neutral)
	if not reset.ok:
		kernel.free()
		return _refused("multirotor start refused: " + str(reset.message))
	if not kernel.commit_prepared_reset_frame(reset):
		kernel.free()
		return _refused("multirotor start commit refused")
	return {ok = true, sim = kernel, plant = candidate_plant, environment = candidate_env, data = doc, options = opts,
		sha256 = sha, field = field.duplicate(true), start = start, body_radius = radius, race = race_wrapper,
		course = race_course}


static func _refused(message: String) -> Dictionary:
	return {ok = false, error = message}


## Validate option `lake` and install a detached copy into `env`. "" on success; an absent or empty lake removes the
## key so a dry session is exactly as before.
static func _install_lake(env: SimEnvironment, opts: Dictionary) -> String:
	var value: Variant = opts.get("lake", {})
	if typeof(value) != TYPE_DICTIONARY:
		return "option lake must be a normalized lake definition or empty"
	var lake: Dictionary = value
	if lake.is_empty():
		opts.erase("lake")
		return ""
	if not LakeSurface.is_valid_definition(lake):
		return "option lake is not a valid lake definition"
	var identity: String = LakeLoader.identity(lake)
	if identity.is_empty() or identity != str(lake.get("identity", "")):
		return "option lake identity does not match its geometry"
	env.lake = lake.duplicate(true)
	return ""


## True when a start position lies over the water polygon or within the airframe radius (plus margin) of it.
static func _start_near_water(lake: Dictionary, start: Dictionary, radius: float) -> bool:
	var distance: float = LakeSurface.shore_distance_validated(lake, float(start.north_m), float(start.east_m))
	return not is_finite(distance) or distance > -(radius + WATER_START_MARGIN_M)


## True when the airframe bounding sphere (centre `body[0..2]`, NED) touches the lake water at `time_s`: the sphere's
## lowest point is at or below the wave-displaced surface over the water polygon. Cheap gates first: no lake, or the
## sphere clear of the highest possible surface, costs a comparison.
static func _water_contact(lake: Dictionary, body: PackedFloat64Array, radius: float, time_s: float) -> bool:
	if lake.is_empty() or body.size() < 3:
		return false
	var bottom: float = body[2] + radius
	if bottom < float(lake.water_level_down_m) - float(lake.wave_bounds.max_amplitude_m):
		return false
	var surface: float = LakeSurface.water_height_down(lake, body[0], body[1], time_s)
	return is_finite(surface) and bottom >= surface


## The detached, normalized lake composed into this session's terrain ({} = dry).
func lake_context() -> Dictionary:
	return environment.lake.duplicate(true)


## The start frame: on the pad at the document's rest height, or (research/test) in the air with the shafts at the
## closed-form hover speed. Always disarmed, Acro, no arm evidence, pack at the selected charge.
func _start_frame(p: RefCounted, doc: Dictionary, env: SimEnvironment, start: Dictionary) -> Dictionary:
	var height: float = env.ground(float(start.north_m), float(start.east_m))[0]
	var air: bool = start.mode == "air"
	var down: float = -height - (float(start.altitude_m) if air else float(doc.start.rest_height_m))
	var attitude := M.q_from_euler(deg_to_rad(float(start.heading_deg)), 0.0, 0.0)
	var body := RB.make_state(M.v3(float(start.north_m), float(start.east_m), down), M.v3(0.0, 0.0, 0.0), attitude,
		M.v3(0.0, 0.0, 0.0))
	var frame: Dictionary = p.initial_frame(body, int(start.source_generation), float(start.initial_soc))
	if air:
		var hover_speed: float = sqrt(float(doc.mass_kg) * env.gravity / (4.0 * float(doc.rotor_law.thrust_coefficient_n_s2)))
		for i in 4:
			frame.continuous[i] = hover_speed
	return frame


static func _airframe_radius(doc: Dictionary) -> float:
	var radius := 0.0
	for rotor: Dictionary in doc.rotors:
		radius = maxf(radius, M.norm(rotor.hub_frd) + 0.5 * float(rotor.diameter_m))
	return radius


func _adopt(kernel: Node) -> void:
	kernel.name = "Simulation"
	kernel.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(kernel)
	kernel.faulted.connect(_on_kernel_fault)
	kernel.paused_changed.connect(_on_kernel_paused)
	kernel.events_located.connect(_on_events)


func _on_kernel_fault(reason: String) -> void:
	fault_reason = "multirotor kernel: " + reason
	paused = true
	pause_reason = "Simulation paused: " + fault_reason
	faulted.emit(fault_reason)
	pause_changed.emit(true, pause_reason)


## The kernel pauses itself when the application loses focus; the flight follows and needs an explicit resume.
func _on_kernel_paused(value: bool) -> void:
	if value and not paused and sim.fault_reason.is_empty():
		_set_paused(true, FOCUS_PAUSE)


func _on_events(_tick: int, events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		_pending_events.append(event.duplicate(true))


## Same configuration, fresh start frame (the configured pad or air start): disarmed, tape and crash cleared, the
## sticky kernel fault cleared. A held-high arm switch is not a fresh request. Refusal keeps the flight.
func reset_to_pad() -> bool:
	if not prepared:
		return false
	var frame := _start_frame(race if race != null else plant, data, environment, _start)
	var input := FC.neutral_input(int(_start.source_generation))
	if race != null:
		input = race.input(input, RaceDirector.ACTION_NONE)
	if not _frame_is_valid(frame, 0):
		load_error = "multirotor reset refused: the start frame is outside the model's domain"
		return false
	# A pad reset aborts a race attempt in progress; its terminal record is kept before the frame is replaced.
	var aborted: Dictionary = {}
	if race != null and sim.modes[RaceModel.MODE_PHASE] in [RaceDirector.PHASE_COUNTDOWN, RaceDirector.PHASE_RACING]:
		if results.size() >= MAX_PENDING_RESULTS:
			load_error = "multirotor reset refused: the race result outbox is full; save or discard results first"
			return false
		aborted = race.result(self.frame())
		aborted.terminal = true
		aborted.phase = "ABORTED"
		aborted.valid = false
		# Audit A14: the reset's own reason code, and the terminal clock of the accepted frame being left (the record
		# is published after the new tick-zero frame is committed).
		aborted.reason = RaceDirector.REASON_NAMES[RaceDirector.REASON_PAD_RESET]
		aborted.reason_code = RaceDirector.REASON_PAD_RESET
		aborted.terminal_tick = int(sim.tick)
		aborted.terminal_time_s = float(sim.time())
	var candidate: Dictionary = sim.prepare_reset_frame(frame, input)
	if not candidate.ok:
		load_error = "multirotor reset refused: " + str(candidate.message)
		return false
	resetting.emit()
	if not sim.commit_prepared_reset_frame(candidate):
		# A resetting observer changed the kernel context: prepare against the current context once more.
		candidate = sim.prepare_reset_frame(frame, input)
		if not candidate.ok or not sim.commit_prepared_reset_frame(candidate):
			load_error = "multirotor reset commit refused"
			return false
	_tape = PackedFloat64Array()
	_pending_events = []
	crash = {}
	fault_reason = ""
	load_error = ""
	if not aborted.is_empty():
		_publish_result(aborted)
	_set_paused(true, READY)
	return true


## Domain check of a frame for this session's model (the race wrapper's, or the plant's).
func _frame_is_valid(frame: Dictionary, at_tick: int) -> bool:
	if race != null:
		return race.validate(frame, {tick = at_tick, time_s = float(at_tick) / float(FIXED_HZ), dt = 1.0 / float(FIXED_HZ)})
	return plant.state_validator(frame, {})


## Values per accepted tick in the kernel input and the tape: the pilot frame, plus the race action in a race.
func input_size() -> int:
	return RaceModel.INPUT_SIZE if race != null else FC.INPUT_SIZE


## Stamp and queue a terminal race record, then announce it. The outbox is bounded; the oldest pending record is
## never dropped silently (callers check the bound before they start or replace an attempt).
func _publish_result(result: Dictionary) -> void:
	var record: Dictionary = result.duplicate(true)
	record.records_identity = records_identity()
	record.session = {data_sha256 = source_sha256, rates = str(plant.config.rates.identity), controller = str(plant.config.identity),
		collision_identity = collision_identity(), impacts = str(sim.model.identity.impacts), field_id = str(_field.get("id", ""))}
	record.terminal_tick = int(result.get("terminal_tick", sim.tick))
	record.saved = false
	# Diagnostic order inside this session; the file identity is publication_id.
	_result_sequence += 1
	record.sequence = _result_sequence
	record.created_utc = Time.get_datetime_string_from_system(true)
	# Audit A12: a stable, globally unique publication identity, kept by every retry ("" when generation failed:
	# save_results() tries again and then keeps the id on this pending record).
	record.publication_id = _new_publication_id()
	results.append(record)
	race_result.emit(record.duplicate(true))


func _new_publication_id() -> String:
	if publication_id_source.is_valid():
		return str(publication_id_source.call())
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode() if bytes.size() == 16 else ""


## DR-26: write every pending terminal record as its own JSON file. A record leaves the outbox only after its file is
## confirmed; a failure keeps it for a later retry. Audit A12/A13: the file name carries the record's stable
## publication id, and a result file is never replaced: a complete, read-back temporary file is renamed onto a name
## that does not exist yet (so no earlier file can be lost on a failed rename, also where the engine removes the
## target before moving), and an existing file with the same bytes is the idempotent success of a retry while one
## with other bytes is a conflict that keeps the record pending. No fsync: not a power-loss guarantee.
## Returns {saved, failed, errors, paths}. Accepted physics is never touched.
func save_results(directory: String = RESULTS_DIRECTORY) -> Dictionary:
	var report := {saved = 0, failed = 0, errors = PackedStringArray(), paths = PackedStringArray()}
	if results.is_empty():
		return report
	var made: Error = DirAccess.make_dir_recursive_absolute(directory)
	if made != OK:
		report.failed = results.size()
		report.errors.append("cannot create %s (%s)" % [directory, error_string(made)])
		return report
	var kept: Array[Dictionary] = []
	for record: Dictionary in results:
		if str(record.get("publication_id", "")).is_empty():
			record.publication_id = _new_publication_id() # kept on the pending record from now on
		var id := str(record.get("publication_id", ""))
		var target := directory.path_join("race-%s-%s-%s.json" % [str(record.get("track_id", "track")).validate_filename(),
			str(record.get("created_utc", "")).replace(":", "").validate_filename(), id.validate_filename()])
		var failure := ""
		if id.is_empty() or id != id.validate_filename():
			failure = "no valid publication id"
		else:
			var stored: Dictionary = record.duplicate(true)
			stored.saved = true
			failure = _publish_new_file(target, JSON.stringify(stored, "\t", true) + "\n")
		if failure.is_empty():
			report.saved += 1
			report.paths.append(target)
		else:
			report.failed += 1
			report.errors.append("could not write %s: %s" % [target, failure])
			kept.append(record)
	results = kept
	return report


## Publish a result file without ever replacing another one. "" when the file now holds exactly `text` (written now,
## or already identical: the retry of the same record); otherwise the reason.
static func _publish_new_file(target: String, text: String) -> String:
	var expected := text.to_utf8_buffer()
	if FileAccess.file_exists(target):
		return "" if FileAccess.get_file_as_bytes(target) == expected else "a different result already uses this name"
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "cannot open %s (%s)" % [temporary, error_string(FileAccess.get_open_error())]
	file.store_buffer(expected)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_bytes(temporary) != expected:
		DirAccess.remove_absolute(temporary)
		return "the temporary file was not written completely"
	var renamed: Error = DirAccess.rename_absolute(temporary, target)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return "rename failed (%s)" % error_string(renamed)
	return "" if FileAccess.get_file_as_bytes(target) == expected else "the file differs after publication"


## Drop every pending record without saving (an explicit pilot choice, never automatic).
func discard_results() -> void:
	results = []


## Release the hold. Refused when not prepared, faulted, after a crash (a pad reset is required) or with a full tape.
func resume() -> bool:
	if not prepared or not fault_reason.is_empty() or not crash.is_empty():
		return false
	if _tape.size() >= MAX_TAPE_TICKS * input_size():
		pause_reason = TAPE_FULL
		return false
	sim.set_paused(false)
	if paused:
		_set_paused(false, "")
	return true


func pause(reason: String = "Paused") -> void:
	_set_paused(true, reason)


func _set_paused(value: bool, reason: String) -> void:
	paused = value
	pause_reason = reason
	pause_changed.emit(paused, reason)


## Advance exactly one 240 Hz tick with one pilot frame (FC.INPUT_SIZE values). False, with nothing changed, when
## not prepared, paused, faulted, the tape is full or the frame is outside its domain; false after a kernel fault.
## In a race session `race_action` (RaceDirector.ACTION_START or ACTION_CANCEL) is sampled with this tick; pulse it
## for one tick. A start is refused, with nothing changed, while the result outbox is full.
func tick_once(pilot: PackedFloat64Array, race_action: int = 0) -> bool:
	if not prepared or paused or not fault_reason.is_empty():
		return false
	if _tape.size() >= MAX_TAPE_TICKS * input_size():
		_set_paused(true, TAPE_FULL)
		return false
	if not FC.input_is_valid(plant.config, pilot):
		return false
	var kernel_input: PackedFloat64Array = pilot.duplicate()
	if race != null:
		if race_action not in [RaceDirector.ACTION_NONE, RaceDirector.ACTION_START, RaceDirector.ACTION_CANCEL]:
			return false
		if race_action == RaceDirector.ACTION_START and results.size() >= MAX_PENDING_RESULTS:
			return false
		kernel_input = race.input(pilot, race_action)
	elif race_action != 0:
		return false
	var before: int = sim.tick
	_pending_events = []
	sim.inputs = kernel_input
	_stepping = true
	sim.step()
	_stepping = false
	if not sim.fault_reason.is_empty():
		if fault_reason.is_empty():
			_on_kernel_fault(sim.fault_reason)
		_pending_events = []
		return false
	if sim.tick != before + 1:
		_pending_events = []
		return false
	_tape.append_array(kernel_input)
	var located := _pending_events
	_pending_events = []
	for event: Dictionary in located:
		var kind := str(event.get("type", ""))
		match kind:
			"crash":
				if crash.is_empty():
					crash = {reason = str(event.get("reason", "Crash")), tick = int(sim.tick), time_s = float(event.get("time_s", sim.time()))}
					if str(crash.reason) == WATER_CRASH:
						_set_paused(true, WATER_PAUSE)
					crashed.emit(str(crash.reason))
			"pack_depleted":
				depleted.emit()
			"impact", "prop_damage", "scrape":
				impact.emit(event.duplicate(true))
		if race != null and kind in RACE_EVENT_TYPES:
			race_event.emit(event.duplicate(true))
			if kind == "race_finish" or kind == "race_abort":
				# The terminal record is a projection of this committed frame; the start bound kept room for it.
				_publish_result(race.result(frame()))
	# CR-AUD-01: an enabled lake's water is terminal. The plant adjudicates it in its endpoint transition (cutting the
	# drive) after its other crash causes, so a ground crash of the same tick keeps its reason.
	tick_advanced.emit(sim.tick, sim.time())
	return true


## One accepted tick from a full kernel input row (input_size() values), as a recorded tape replays it.
func tick_input(row: PackedFloat64Array) -> bool:
	if row.size() != input_size():
		return false
	if race == null:
		return tick_once(row)
	var action: float = row[RaceModel.IN_RACE_ACTION]
	if action not in [0.0, 1.0, 2.0]:
		return false
	return tick_once(row.slice(0, FC.INPUT_SIZE), int(action))


## Install the field obstacle inventory; refused while a flight is under way. A changed inventory on a prepared
## session closes recorders (`resetting`): accepted physics after it uses the new obstacles.
func set_collision_world(world: Dictionary) -> bool:
	if prepared and sim.tick > 0 and not paused:
		return false
	if not world.is_empty():
		if not CollisionWorld._world_header_is_valid(world):
			return false
		for proxy: Dictionary in world.proxies:
			if not CollisionWorld._proxy_is_valid(proxy):
				return false
	var projected := FpvForest.project(world)
	if not projected.ok:
		load_error = str(projected.error)
		return false
	if prepared and str(projected.identity) != collision_identity():
		if race != null and sim.modes[RaceModel.MODE_PHASE] in [RaceDirector.PHASE_COUNTDOWN, RaceDirector.PHASE_RACING]:
			load_error = "multirotor obstacle change refused during a race attempt"
			return false
		resetting.emit()
	_obstacles = projected
	if prepared:
		_install_obstacle_queries(plant, _frame_proxies(course.get("frames", [])), _body_radius)
	return true


## Identity of the installed obstacle inventory ("" = terrain only).
func collision_identity() -> String:
	return str(_obstacles.identity)


## Results compare runs on the same resolved course, obstacle inventory and admitted impact law.
## Geometry-only keys are retained in the book for earlier attempts.
func records_identity() -> String:
	if race == null:
		return ""
	return JSON.stringify(["fpv-race-records-v2", course.identity, collision_identity(), sim.model.identity.impacts]).sha256_text()


func _prepare_obstacle_index(radius: float) -> void:
	# Pad restarts and course switches share the installed forest. Refit the search cells
	# only when the aircraft reach or the projected world changes.
	if _obstacles.get("index_radius") != radius:
		_obstacles.solid_index = obstacle_index({proxies = _obstacles.solids}, radius + OBSTACLE_SLACK_M)
		_obstacles.leaf_index = obstacle_index({proxies = _obstacles.foliage}, radius)
		_obstacles.index_radius = radius


func _install_obstacle_queries(target: RefCounted, frames: Array, radius: float) -> void:
	_prepare_obstacle_index(radius)
	var reach := radius + OBSTACLE_SLACK_M
	var solid: Dictionary = _obstacles.solid_index
	var has_solids: bool = not _obstacles.solids.is_empty() or not frames.is_empty()
	target.obstacle = _obstacle_query(solid, frames, reach) if has_solids else Callable()
	target.obstacle_class = _obstacle_class_query(solid, frames, reach) if has_solids else Callable()
	var gates := FrameContact.prepare_gates(frames)
	target.frame_contact = FrameContact.from_prepared(solid, gates) if has_solids else Callable()
	target.swept_prop_contact = SweptProp.from_prepared(solid, gates) if has_solids else Callable()
	target.solids_near = FrameContact.near_query(solid, gates, target.scenery_sweep_radius(), reach) if has_solids else Callable()
	target.prop_disc_contact = _prop_disc_query(solid, frames) if has_solids else Callable()
	target.foliage_density = Callable()
	target.foliage_near = Callable()
	if not _obstacles.foliage.is_empty():
		target.foliage_density = _foliage_query(_obstacles.leaf_index, radius, target.prepared.rotors)
		target.foliage_near = _foliage_near_query(_obstacles.leaf_index, radius)


## The leaf cells already include the reach of every hub. If the chord stays inside one cell,
## a scalar altitude check rejects most clear-air ticks before any pose or leaf samples are built.
static func _foliage_near_query(index: Dictionary, radius: float) -> Callable:
	var size_m := float(index.cell_m)
	return func(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
		if not index.wide.is_empty():
			return true
		var cell := Vector2i(floori(a[RB.POS] / size_m), floori(a[RB.POS + 1] / size_m))
		if cell.x != floori(b[RB.POS] / size_m) or cell.y != floori(b[RB.POS + 1] / size_m):
			return true
		var list: Variant = index.cells.get(cell)
		if list == null:
			return false
		var top := minf(a[RB.POS + 2], b[RB.POS + 2]) - radius
		var bottom := maxf(a[RB.POS + 2], b[RB.POS + 2]) + radius
		for crown: Dictionary in list:
			if top <= crown.bounds_down_max and bottom >= crown.bounds_down_min:
				return true
		return false


## Sample the crown occupancy at the four arm ends in a single spatial lookup. A cell is expanded by
## the full craft radius at preparation, so a body centred across the cell border can still brush a crown.
static func _foliage_query(index: Dictionary, radius: float, rotors: Array) -> Callable:
	var empty := PackedFloat64Array()
	return func(body: PackedFloat64Array, attitude: PackedFloat64Array) -> PackedFloat64Array:
		var n := body[RB.POS]
		var e := body[RB.POS + 1]
		var d := body[RB.POS + 2]
		var candidates := obstacle_candidates(index, n, e)
		if candidates.is_empty():
			return empty
		var weights := empty
		var offsets: Array[PackedFloat64Array] = []
		for proxy: Dictionary in candidates:
			if not CollisionWorld._aabb_sphere_overlap(proxy, n, e, d, radius):
				continue
			if offsets.is_empty():
				weights = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
				for rotor: Dictionary in rotors:
					offsets.append(M.q_rotate(attitude, rotor.hub_frd))
			for i in offsets.size():
				var r := offsets[i]
				weights[i] = maxf(weights[i], FpvForest.density_at(proxy, n + r[0], e + r[1], d + r[2]))
		return weights


## obstacle(north, east, down) -> signed clearance (m) to the nearest proxy within `reach`, else `reach`. Pure: it
## reads only an immutable index built here from the installed world (no query-time memory), so the kernel's
## guarded callbacks see no session state. On a validated world (set_collision_world checks every proxy) the result
## equals the former fresh CollisionWorld.nearby query: the index's fine cells give a superset of candidates and the
## world's own AABB-sphere test keeps the proxies that query returned; the minimum of their clearances does not
## depend on order or repeats except for a signed zero (bit for bit on 199 376 queries, DR-22/R1,
## test_mr_fast_paths). At a 32 m bin border the index can also find a proxy the former query missed by rounding. `frames` are the race course's gate-frame boxes (few:
## tested directly, no broad phase).
static func _obstacle_query(index: Dictionary, frames: Array, reach: float) -> Callable:
	return func(north: float, east: float, down: float) -> float:
		var nearest := reach
		if not index.is_empty() and is_finite(north) and is_finite(east) and is_finite(down):
			for proxy: Dictionary in obstacle_candidates(index, north, east):
				if CollisionWorld._aabb_sphere_overlap(proxy, north, east, down, reach):
					nearest = minf(nearest, _clearance(proxy, north, east, down))
		for proxy: Dictionary in frames:
			if absf(north - float(proxy.north)) < proxy.span and absf(east - float(proxy.east)) < proxy.span:
				nearest = minf(nearest, _clearance(proxy, north, east, down))
		return nearest


## DR-19c: obstacle_class(north, east, down) -> the response class of the nearest proxy within `reach` (gate frames:
## "gate_frame"), "" when none; the same pure index and candidates as _obstacle_query.
static func _obstacle_class_query(index: Dictionary, frames: Array, reach: float) -> Callable:
	return func(north: float, east: float, down: float) -> String:
		var nearest := reach
		var kind := ""
		if not index.is_empty() and is_finite(north) and is_finite(east) and is_finite(down):
			for proxy: Dictionary in obstacle_candidates(index, north, east):
				if CollisionWorld._aabb_sphere_overlap(proxy, north, east, down, reach):
					var clearance := _clearance(proxy, north, east, down)
					if clearance < nearest:
						nearest = clearance
						kind = str(proxy.get("response_class", ""))
		for proxy: Dictionary in frames:
			if absf(north - float(proxy.north)) < proxy.span and absf(east - float(proxy.east)) < proxy.span:
				var clearance := _clearance(proxy, north, east, down)
				if clearance < nearest:
					nearest = clearance
					kind = "gate_frame"
		return kind


## DR-22/R1 terrain law of the plant's contact, impact and substep queries: the field surface linearized inside
## TERRAIN_CELL_M squares, h(n, e) = h(a) + dh/dn(a)·(n − a_n) + dh/de(a)·(e − a_e) with slopes dh(a), where a is the
## square's centre. A pure function of (n, e): the memo of centre samples changes the speed, never a value, so
## replay, checkpoints and reset are unaffected by what it holds. A quad resting on the pad queries the same few
## squares every stage, so the microrelief sampler (about 5 µs) runs once per square instead of about 230 times a
## tick. Linearization error: curvature × (cell/2)² ≈ 1e-9 m on the field's microrelief. Points beyond
## TERRAIN_MEMO_REACH_M from the origin or non-finite take the exact sample.
static func contact_ground(env: RefCounted) -> Callable:
	var memo := {}
	return func(n: float, e: float) -> PackedFloat64Array:
		if not (absf(n) < TERRAIN_MEMO_REACH_M and absf(e) < TERRAIN_MEMO_REACH_M):
			return env.ground(n, e)
		var cell_n := floori(n / TERRAIN_CELL_M)
		var cell_e := floori(e / TERRAIN_CELL_M)
		var anchor_n := (float(cell_n) + 0.5) * TERRAIN_CELL_M
		var anchor_e := (float(cell_e) + 0.5) * TERRAIN_CELL_M
		var key := Vector2i(cell_n, cell_e)
		var centre: Variant = memo.get(key)
		if centre == null:
			if memo.size() >= TERRAIN_MEMO_MAX:
				memo.clear()
			centre = env.ground(anchor_n, anchor_e)
			memo[key] = centre
		var a: PackedFloat64Array = centre
		return PackedFloat64Array([a[0] + a[1] * (n - anchor_n) + a[2] * (e - anchor_e), a[1], a[2]])


## Fine 2D broad phase over a validated world for queries of radius `reach`: {cell_m, cells: {key: Array of
## proxies}, wide: proxies spanning too many cells}. Every proxy is listed in each cell its AABB, grown by `reach`,
## touches, so the one cell holding a query point lists every proxy whose AABB the reach sphere can overlap.
## {} for an empty world.
static func obstacle_index(world: Dictionary, reach: float) -> Dictionary:
	if world.is_empty() or not world.get("proxies") is Array:
		return {}
	var cell := OBSTACLE_INDEX_CELL_M
	# A centimetre beyond the reach keeps rounding at a cell border from ever dropping a candidate.
	var grow := reach + 0.01
	var cells := {}
	var wide: Array[Dictionary] = []
	for proxy: Dictionary in world.proxies:
		var n0 := floori((float(proxy.bounds_north_min) - grow) / cell)
		var n1 := floori((float(proxy.bounds_north_max) + grow) / cell)
		var e0 := floori((float(proxy.bounds_east_min) - grow) / cell)
		var e1 := floori((float(proxy.bounds_east_max) + grow) / cell)
		if (n1 - n0 + 1) * (e1 - e0 + 1) > OBSTACLE_INDEX_MAX_CELLS:
			wide.append(proxy)
			continue
		for n in range(n0, n1 + 1):
			for e in range(e0, e1 + 1):
				var key := Vector2i(n, e)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(proxy)
	return {cell_m = cell, cells = cells, wide = wide}


## Candidate proxies for a point: the cell's list plus the wide proxies (a superset; the caller applies the exact
## AABB-sphere test).
static func obstacle_candidates(index: Dictionary, north: float, east: float) -> Array:
	var key := Vector2i(floori(north / float(index.cell_m)), floori(east / float(index.cell_m)))
	var listed: Array = index.cells.get(key, [])
	if index.wide.is_empty():
		return listed
	return listed + index.wide


## Gate-frame boxes of a prepared course ({north, east, down, half_x along the gate normal, half_down, half_z
## across it, heading_deg}) as box proxies for _clearance (whose z axis runs along the heading, x across it).
static func _frame_proxies(frames: Array) -> Array:
	var proxies: Array = []
	for box: Dictionary in frames:
		var heading: float = deg_to_rad(float(box.heading_deg))
		var across: float = box.half_z
		var along: float = box.half_x
		proxies.append({shape = "box", north = float(box.north), east = float(box.east), down = float(box.down),
			half_x = across, half_z = along, half_down = float(box.half_down), sin_heading = M.sin_(heading), cos_heading = M.cos_(heading),
			span = maxf(across, along) + 2.0})
	return proxies


## Euclidean distance from a world NED point to the proxy solid (<= 0 inside), as the airship session.
## CR-AUD-25: prop_disc_contact(hub, axis, radius, half_thickness) -> {} or the deepest obstacle intersecting the finite
## prop disc, judged per proxy with its own witness, outward normal and class (gate frames: "gate_frame"). Pure, on
## the same index and candidates as _obstacle_query; candidate order is the index order, the deepest wins.
static func _prop_disc_query(index: Dictionary, frames: Array) -> Callable:
	return func(hub: PackedFloat64Array, axis: PackedFloat64Array, radius: float, half_thickness: float) -> Dictionary:
		var best := {}
		if hub.size() != 3 or axis.size() != 3 or not (is_finite(hub[0]) and is_finite(hub[1]) and is_finite(hub[2])):
			return best
		var candidates: Array = []
		if not index.is_empty():
			for proxy: Dictionary in obstacle_candidates(index, hub[0], hub[1]):
				if CollisionWorld._aabb_sphere_overlap(proxy, hub[0], hub[1], hub[2], radius + half_thickness):
					candidates.append([proxy, str(proxy.get("response_class", ""))])
		for proxy: Dictionary in frames:
			if absf(hub[0] - float(proxy.north)) < proxy.span and absf(hub[1] - float(proxy.east)) < proxy.span:
				candidates.append([proxy, "gate_frame"])
		for entry: Array in candidates:
			var contact := _disc_proxy_contact(entry[0], hub, axis, radius, half_thickness)
			if not contact.is_empty() and (best.is_empty() or float(contact.penetration_m) > float(best.penetration_m)):
				contact.kind = entry[1]
				best = contact
		return best


const DISC_PROJECTION_ITERATIONS := 16
const DISC_GRADIENT_STEP_M := 1.0e-5


## Closest approach of a thin disc (centre `hub`, unit `axis`, `radius`) and one convex proxy, by alternating
## projections between the two from two seeds (the proxy centre and the hub). {} when separated by more than
## `half_thickness`; else {penetration_m, normal (proxy's outward normal at the witness), point_ned (disc witness)}.
static func _disc_proxy_contact(proxy: Dictionary, hub: PackedFloat64Array, axis: PackedFloat64Array, radius: float,
		half_thickness: float) -> Dictionary:
	var best_point := PackedFloat64Array()
	var best_distance := INF
	for seed: PackedFloat64Array in [PackedFloat64Array([float(proxy.north), float(proxy.east), float(proxy.down)]), hub]:
		var point := _project_to_disc(seed, hub, axis, radius)
		for iteration in DISC_PROJECTION_ITERATIONS:
			var distance := _clearance(proxy, point[0], point[1], point[2])
			if not (distance > 0.0):
				break
			var gradient := _clearance_gradient(proxy, point)
			if gradient.is_empty():
				break
			var surface := PackedFloat64Array([point[0] - gradient[0] * distance, point[1] - gradient[1] * distance,
				point[2] - gradient[2] * distance])
			var next := _project_to_disc(surface, hub, axis, radius)
			var moved := absf(next[0] - point[0]) + absf(next[1] - point[1]) + absf(next[2] - point[2])
			point = next
			if moved < 1.0e-9:
				break
		var final := _clearance(proxy, point[0], point[1], point[2])
		if final < best_distance:
			best_distance = final
			best_point = point
	if not (half_thickness - best_distance > 0.0) or best_point.is_empty():
		return {}
	# Intersecting: the projections stop at the first point inside, so the deepest point is also looked for on the
	# rim and at the hub (DISC_DEPTH_SAMPLES phases); the deeper witness sets the penetration and normal.
	var u := _perpendicular(axis)
	var v := PackedFloat64Array([axis[1] * u[2] - axis[2] * u[1], axis[2] * u[0] - axis[0] * u[2],
		axis[0] * u[1] - axis[1] * u[0]])
	for k in DISC_DEPTH_SAMPLES + 1:
		var sample := hub.duplicate()
		if k < DISC_DEPTH_SAMPLES:
			var phase := TAU * float(k) / float(DISC_DEPTH_SAMPLES)
			var cosine := M.cos_(phase)
			var sine := M.sin_(phase)
			for j in 3:
				sample[j] += radius * (cosine * u[j] + sine * v[j])
		var distance := _clearance(proxy, sample[0], sample[1], sample[2])
		if distance < best_distance:
			best_distance = distance
			best_point = sample
	var normal := _clearance_gradient(proxy, best_point)
	if normal.is_empty():
		# A medial point inside the proxy has no gradient: leave toward the hub's side of the proxy centre.
		var away := PackedFloat64Array([hub[0] - float(proxy.north), hub[1] - float(proxy.east), hub[2] - float(proxy.down)])
		var length := sqrt(away[0] * away[0] + away[1] * away[1] + away[2] * away[2])
		normal = PackedFloat64Array([away[0] / length, away[1] / length, away[2] / length]) if length > 1.0e-9 \
			else PackedFloat64Array([-axis[0], -axis[1], -axis[2]])
	return {penetration_m = half_thickness - best_distance, normal = normal, point_ned = best_point}


const DISC_DEPTH_SAMPLES := 24


## A unit vector perpendicular to the unit `axis`.
static func _perpendicular(axis: PackedFloat64Array) -> PackedFloat64Array:
	var seed := PackedFloat64Array([0.0, 0.0, 1.0]) if absf(axis[2]) < 0.9 else PackedFloat64Array([1.0, 0.0, 0.0])
	var c := PackedFloat64Array([axis[1] * seed[2] - axis[2] * seed[1], axis[2] * seed[0] - axis[0] * seed[2],
		axis[0] * seed[1] - axis[1] * seed[0]])
	var length := sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2])
	return PackedFloat64Array([c[0] / length, c[1] / length, c[2] / length])


static func _project_to_disc(point: PackedFloat64Array, hub: PackedFloat64Array, axis: PackedFloat64Array,
		radius: float) -> PackedFloat64Array:
	var rel := PackedFloat64Array([point[0] - hub[0], point[1] - hub[1], point[2] - hub[2]])
	var along := rel[0] * axis[0] + rel[1] * axis[1] + rel[2] * axis[2]
	var in_plane := PackedFloat64Array([rel[0] - along * axis[0], rel[1] - along * axis[1], rel[2] - along * axis[2]])
	var length := sqrt(in_plane[0] * in_plane[0] + in_plane[1] * in_plane[1] + in_plane[2] * in_plane[2])
	var scale := radius / length if length > radius else 1.0
	return PackedFloat64Array([hub[0] + in_plane[0] * scale, hub[1] + in_plane[1] * scale, hub[2] + in_plane[2] * scale])


## Unit outward gradient of a proxy's signed distance at `point` (central differences); empty where it is flat.
static func _clearance_gradient(proxy: Dictionary, point: PackedFloat64Array) -> PackedFloat64Array:
	var g := PackedFloat64Array([0.0, 0.0, 0.0])
	for k in 3:
		var plus := point.duplicate()
		var minus := point.duplicate()
		plus[k] += DISC_GRADIENT_STEP_M
		minus[k] -= DISC_GRADIENT_STEP_M
		g[k] = (_clearance(proxy, plus[0], plus[1], plus[2]) - _clearance(proxy, minus[0], minus[1], minus[2])) \
			/ (2.0 * DISC_GRADIENT_STEP_M)
	var length := sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])
	if not (is_finite(length) and length > 1.0e-6):
		return PackedFloat64Array()
	return PackedFloat64Array([g[0] / length, g[1] / length, g[2] / length])


static func _clearance(proxy: Dictionary, n: float, e: float, d: float) -> float:
	var dn := n - float(proxy.north)
	var de := e - float(proxy.east)
	var dd := d - float(proxy.down)
	if proxy.shape == "capsule":
		if proxy.has("axis_ned"):
			var axis: PackedFloat64Array = proxy.axis_ned
			var t := clampf(dn * axis[0] + de * axis[1] + dd * axis[2], -float(proxy.half_length), float(proxy.half_length))
			dn -= t * axis[0]
			de -= t * axis[1]
			dd -= t * axis[2]
			return sqrt(dn * dn + de * de + dd * dd) - float(proxy.radius)
		var along := clampf(dd, -float(proxy.half_length), float(proxy.half_length))
		return sqrt(dn * dn + de * de + (dd - along) * (dd - along)) - float(proxy.radius)
	var sh: float = proxy.sin_heading
	var ch: float = proxy.cos_heading
	var ox := absf(-dn * sh + de * ch) - float(proxy.half_x)
	var oz := absf(dn * ch + de * sh) - float(proxy.half_z)
	var od := absf(dd) - float(proxy.half_down)
	var outside := sqrt(maxf(ox, 0.0) ** 2 + maxf(oz, 0.0) ** 2 + maxf(od, 0.0) ** 2)
	return outside + minf(maxf(ox, maxf(oz, od)), 0.0)


## 13-value body between the previous and the accepted tick, for rendering.
func interpolated(fraction: float) -> PackedFloat64Array:
	return sim.interpolated(clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 1.0)


## Detached accepted frame {body, continuous, aux, modes}.
func frame() -> Dictionary:
	return {body = sim.state.duplicate(), continuous = sim.continuous.duplicate(), aux = sim.aux.duplicate(),
		modes = sim.modes.duplicate()}


## The plant's part of the accepted frame (the whole frame in free flight; without the race suffix in a race).
func plant_frame() -> Dictionary:
	return race.plant_frame(frame()) if race != null else frame()


## Pilot-facing telemetry of the accepted frame (a pure evaluation; nothing advances).
func telemetry() -> Dictionary:
	if not prepared:
		return {}
	var f := plant_frame()
	var out: Dictionary = plant.telemetry(f, sim.time())
	if race != null:
		out.race = race.race_state(frame(), sim.time())
		out.race.pending_results = results.size()
	var b: PackedFloat64Array = f.body
	var modes: PackedInt64Array = f.modes
	out.tick = int(sim.tick)
	out.time_s = sim.time()
	out.armed = modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	out.crashed = not crash.is_empty()
	out.depleted = modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED
	out.arm_block = modes[FC.MODE_ARM_BLOCK]
	out.flight_mode = modes[FC.MODE_FLIGHT]
	out.altitude_agl_m = -b[RB.POS + 2] - environment.ground(b[RB.POS], b[RB.POS + 1])[0]
	out.speed_mps = sqrt(b[RB.VEL] * b[RB.VEL] + b[RB.VEL + 1] * b[RB.VEL + 1] + b[RB.VEL + 2] * b[RB.VEL + 2])
	return out


## Plain identity of the configuration that affects accepted physics: model/law/controller/rates/data, throttle
## policy, resolved start, weather, field surfaces and the fixed tick. The obstacle inventory has its own identity;
## a change of the solver source itself (for example DR-18/22-R1's parked substeps and contact terrain law) is
## identified by the flight log's solver identity, not here.
func identity() -> Dictionary:
	if not prepared:
		return {}
	return {format = FORMAT, model = sim.model.identity.duplicate(true), data_sha256 = source_sha256,
		rates = str(plant.config.rates.identity), controller = str(plant.config.identity),
		throttle_policy = str(options.throttle_policy), start = _start.duplicate(true),
		wind = {speed_mps = float(options.wind_speed_mps), from_deg = fposmod(float(options.wind_from_deg), 360.0)},
		environment = environment.identity(), mass_kg = float(data.mass_kg), fixed_hz = FIXED_HZ,
		engine_tick_hz = Engine.physics_ticks_per_second,
		race = {course = str(course.get("identity", "")), ruleset = Track.RULESET if race != null else "",
			path_policy = Track.PATH_POLICY if race != null else ""}}


## Full envelope: the kernel checkpoint (body, shafts, pack, controller block, modes, inputs, clock) plus the session
## crash record, pause flag and identities. {} when not prepared or faulted.
func checkpoint() -> Dictionary:
	if not prepared or _stepping:
		return {}
	var kernel: Dictionary = sim.checkpoint()
	if kernel.is_empty():
		return {}
	return {format = FORMAT, identity = identity(), kernel = kernel, crash = crash.duplicate(true),
		tape_ticks = _tape.size() / input_size(), paused = paused, collision_identity = collision_identity(),
		results = results.duplicate(true)}


## Validates format, identity, obstacle identity and the kernel checkpoint before changing anything. The tape
## restarts empty; the pause flag and crash record come from the envelope.
func restore_checkpoint(envelope: Dictionary) -> bool:
	if not prepared or envelope.size() != ENVELOPE_KEYS.size() or not envelope.has_all(ENVELOPE_KEYS):
		return false
	if typeof(envelope.format) != TYPE_STRING or envelope.format != FORMAT or typeof(envelope.identity) != TYPE_DICTIONARY \
			or var_to_bytes(envelope.identity) != var_to_bytes(identity()) or typeof(envelope.paused) != TYPE_BOOL \
			or typeof(envelope.collision_identity) != TYPE_STRING or envelope.collision_identity != collision_identity() \
			or typeof(envelope.tape_ticks) != TYPE_INT or not _crash_is_valid(envelope.crash) \
			or typeof(envelope.kernel) != TYPE_DICTIONARY or not sim.can_restore_checkpoint(envelope.kernel):
		return false
	# Enum domains, shaft and charge bounds, the cut latch's agreement with the lifecycle and, in a race, the race
	# domains and the course tag (see reset). The envelope identity above pins the full course identity.
	if not _frame_is_valid({body = envelope.kernel.state, continuous = envelope.kernel.continuous,
			aux = envelope.kernel.aux, modes = envelope.kernel.modes}, int(envelope.kernel.tick)):
		return false
	if typeof(envelope.results) != TYPE_ARRAY or envelope.results.size() > MAX_PENDING_RESULTS:
		return false
	var restored_results: Array[Dictionary] = []
	for record: Variant in envelope.results:
		if typeof(record) != TYPE_DICTIONARY or record.size() > 64:
			return false
		restored_results.append(record.duplicate(true))
	resetting.emit()
	var was_paused := paused
	paused = true # the kernel restore pauses itself; that is not a focus loss
	if not sim.restore_checkpoint(envelope.kernel.duplicate(true)):
		paused = was_paused
		return false
	_tape = PackedFloat64Array()
	_pending_events = []
	results = restored_results
	crash = envelope.crash.duplicate(true)
	fault_reason = ""
	load_error = ""
	if envelope.paused:
		_set_paused(true, "Restored from a checkpoint.")
	else:
		sim.set_paused(false)
		_set_paused(false, "")
	return true


static func _crash_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if value.is_empty():
		return true
	return value.size() == 3 and typeof(value.get("reason")) == TYPE_STRING and typeof(value.get("tick")) == TYPE_INT \
		and typeof(value.get("time_s")) == TYPE_FLOAT and is_finite(value.time_s)


## Accepted pilot frames, FC.INPUT_SIZE values per accepted tick since the last reset or restore.
func tape() -> PackedFloat64Array:
	return _tape.duplicate()


static func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Shape screen of an in-memory prepared document before the plant reads it ("" = acceptable). The plant, the
## actuator map, the allocator and the controller validate their own values; this only keeps them from reading a
## missing or mistyped block.
static func _prepared_shape_error(doc: Dictionary) -> String:
	for key: String in ["identity", "rotor_law", "airframe", "powertrain", "controller", "contacts", "start"]:
		if typeof(doc.get(key)) != TYPE_DICTIONARY:
			return "prepared_data.%s: required block is missing" % key
	if not _positive(doc.get("mass_kg")):
		return "prepared_data.mass_kg: positive finite mass required"
	if not _floats(doc.get("inertia_kg_m2"), 6):
		return "prepared_data.inertia_kg_m2: six finite values required"
	if typeof(doc.get("rotors")) != TYPE_ARRAY or doc.rotors.size() != 4:
		return "prepared_data.rotors: exactly four rotors required"
	for rotor: Variant in doc.rotors:
		if typeof(rotor) != TYPE_DICTIONARY or not rotor.has("id") or not _floats(rotor.get("hub_frd"), 3) \
				or not _number(rotor.get("spin")) or not _positive(rotor.get("diameter_m")) or not _positive(rotor.get("inertia_kg_m2")):
			return "prepared_data.rotors: each rotor needs id, hub_frd, spin, diameter_m and inertia_kg_m2"
	for key: String in ["thrust_coefficient_n_s2", "torque_coefficient_n_m_s2", "max_speed_rad_s"]:
		if not _positive(doc.rotor_law.get(key)):
			return "prepared_data.rotor_law.%s: positive finite value required" % key
	if not _number(doc.rotor_law.get("rotor_drag_n_s2_per_m")):
		return "prepared_data.rotor_law.rotor_drag_n_s2_per_m: finite value required"
	if not _floats(doc.airframe.get("drag_areas_m2"), 3):
		return "prepared_data.airframe.drag_areas_m2: three finite values required"
	if not _floats(doc.controller.get("allocator_weights"), 4):
		return "prepared_data.controller.allocator_weights: four finite values required"
	var law: Variant = doc.powertrain.get("law")
	if typeof(law) != TYPE_STRING or str(law) not in [ActuatorMap.LAW_LAB, ActuatorMap.LAW_ELECTRIC]:
		return "prepared_data.powertrain.law: unsupported powertrain law"
	if law == ActuatorMap.LAW_LAB and not _positive(doc.powertrain.get("time_constant_s")):
		return "prepared_data.powertrain.time_constant_s: positive finite value required"
	var contacts: Dictionary = doc.contacts
	for key: String in ["stiffness_n_per_m", "damping_n_s_per_m", "friction", "crash_speed_mps", "rotor_strike_speed_rad_s"]:
		if not _number(contacts.get(key)):
			return "prepared_data.contacts.%s: finite value required" % key
	for key: String in ["feet_frd", "hull_frd"]:
		if typeof(contacts.get(key)) != TYPE_ARRAY:
			return "prepared_data.contacts.%s: list of points required" % key
		for point: Variant in contacts[key]:
			if not _floats(point, 3):
				return "prepared_data.contacts.%s: every point needs three finite values" % key
	if not _number(doc.start.get("rest_height_m")) or float(doc.start.rest_height_m) < 0.0:
		return "prepared_data.start.rest_height_m: nonnegative finite height required"
	if law == ActuatorMap.LAW_ELECTRIC:
		if typeof(doc.get("battery")) != TYPE_DICTIONARY:
			return "prepared_data.battery: required for the electrical law"
		var battery: Dictionary = doc.battery
		for key: String in ["capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc"]:
			if not _number(battery.get(key)):
				return "prepared_data.battery.%s: finite value required" % key
		var points: Variant = battery.get("ocv_points")
		if typeof(points) != TYPE_PACKED_FLOAT64_ARRAY or points.size() < 4 or points.size() % 2 != 0 or not _floats(points, points.size()):
			return "prepared_data.battery.ocv_points: [soc, volts] pairs required"
	return ""


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0


static func _floats(value: Variant, size: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != size:
		return false
	for item: float in value:
		if not is_finite(item):
			return false
	return true
