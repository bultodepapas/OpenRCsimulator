# C7-R2: metadata follows loaded configuration and recording-start state, never catalog identity.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trace := preload("res://sim/trace.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Flaps := preload("res://physics/flaps.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const Turbine := preload("res://physics/turbine.gd")
const TIMBER := "turbo-lumber-evolution"
const WHEEL_LAYOUT_SUFFIX := "wheel rim speeds in m/s, landing-gear contact order, appended continuous tail"

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _aux_matches(encoded: String, aux: PackedFloat64Array) -> bool:
	var decoded: Array = JSON.parse_string(encoded)
	if decoded.size() != aux.size():
		return false
	for index in aux.size():
		# JSON decimal conversion is not a bit-exact replay format. Stay stricter
		# than the CSV's nine-place tolerance while allowing a float64 ULP.
		if absf(float(decoded[index]) - aux[index]) > maxf(1e-15, absf(aux[index]) * 2e-15):
			return false
	return true


func _without_wheel_profile(model: Dictionary) -> Dictionary:
	var out: Dictionary = model.duplicate(true)
	out.erase("wheel_profile")
	var gear: Dictionary = out.get("landing_gear", {})
	if not gear.is_empty():
		gear.erase("rolling_reference_radius")
		gear.erase("rolling_reference_radius_provenance")
		var contacts: Array = gear.get("contacts", []).duplicate(true)
		for index in contacts.size():
			var contact: Dictionary = contacts[index]
			for key in ["wheel_radius", "wheel_inertia", "spin_relaxation", "brake_torque", "brake_availability", "wheel_provenance"]:
				contact.erase(key)
			contacts[index] = contact
		gear.contacts = contacts
		out.landing_gear = gear
	return out


func _initialize() -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	var recorder: RefCounted = Recorder.new(session.sim, session.electrical_state, Callable(session, "mass_properties"))
	for entry in Catalog.airplane_flyable_entries(): # TT-06: previews carry no data file
		session.aircraft_path = entry.data
		_check("reload " + entry.id, session.reload().begins_with("aircraft reloaded:"))
		var meta: Dictionary = session.trace_meta()
		_check("active aircraft " + entry.id, meta.aircraft.begins_with(entry.id))
		# The catalog can add installations or profiled wheels independently of the test.
		# Metadata expectations follow the resolved aircraft model, not a fixed ID list.
		var glow_profiled: bool = session.glow_is_active()
		var wheel_profiled: bool = session.wheel_count() > 0
		var expected_schema: String = "openrc-flight-meta v10" if glow_profiled else ("openrc-flight-meta v6" if wheel_profiled else "openrc-flight-meta v2")
		if not glow_profiled and session.flaps_available():
			expected_schema = "openrc-flight-meta v9" # optional flap layout follows the gear channels
		elif not glow_profiled and session.gear_is_retractable():
			expected_schema = "openrc-flight-meta v8" # published gear/input/extension metadata contract
		_check("metadata schema " + entry.id, meta.metadata_schema == expected_schema,
			"expected=%s actual=%s" % [expected_schema, meta.metadata_schema])
		if wheel_profiled:
			var layout_text: String = str(meta.continuous_layout)
			var wheel_suffix_index: int = layout_text.find(WHEEL_LAYOUT_SUFFIX)
			var liquid_suffix_index: int = layout_text.find(LiquidFlight.LAYOUT)
			var layout_order_ok: bool = layout_text.ends_with(WHEEL_LAYOUT_SUFFIX) if not session.liquid_fuel_is_active() \
				else wheel_suffix_index >= 0 and liquid_suffix_index > wheel_suffix_index
			_check("wheel trace layout keeps wheel tail before any fuel tail", layout_order_ok)
			_check("wheel trace records selected-profile and source-file identity", str(meta.wheel_profile_sha256).length() == 64
				and str(meta.wheel_profile_input_sha256).length() == 64)
			_check("wheel trace has one state entry per gear contact", JSON.parse_string(meta.wheel_state_layout).size()
				== session.wheel_count())
		else:
			_check("unprofiled aircraft has no wheel-state metadata " + entry.id,
				not meta.has("wheel_state_model") and not meta.has("wheel_state_layout"))
		if glow_profiled:
			var expected_family: String = str(session.aircraft.model.propulsion.glow.profile.family)
			var identity: Dictionary = JSON.parse_string(meta.glow_identity)
			var start: Dictionary = JSON.parse_string(meta.glow_recording_start)
			_check("glow trace records the accepted installation law", meta.propulsion_model == GlowFlight.LAW)
			_check("glow trace keeps the explicit cycle family", meta.glow_family == expected_family and start.get("family", "") == expected_family)
			_check("glow profile identity carries the installation hash", str(identity.get("profile", {}).get("sha256", "")).length() == 64)
			_check("finite Glow trace identifies its selected tank and registry",
				str(meta.get("glow_fuel_tank_id", "")).length() > 0
				and str(meta.get("glow_fuel_registry_sha256", "")).length() == 64)
			var line_fuel: float = float(start.get("feed_line_fuel_kg", NAN))
			var main_fuel: float = float(start.get("main_fuel_kg", NAN))
			var source_mode: float = float(start.get("fuel_source_mode", NAN))
			_check("Glow start summary separates main and feed-line stores",
				is_finite(line_fuel) and is_finite(main_fuel) and is_finite(source_mode)
				and absf(line_fuel + main_fuel - float(start.get("fuel_kg", NAN))) < 1e-9
				and line_fuel == float(JSON.parse_string(meta.recording_start_continuous)[17])
				and source_mode == float(JSON.parse_string(meta.recording_start_continuous)[18]))
			_check("glow recording start matches all continuous state slots",
				JSON.parse_string(meta.recording_start_continuous).size() == GlowFlight.SIZE + session.wheel_count()
				and _aux_matches(meta.recording_start_continuous, session.sim.continuous))
			_check("glow continuous layout names crank phase and successful-fire counters",
				str(meta.continuous_layout).contains("crank revolutions")
				and str(meta.continuous_layout).contains("opportunities, fires, firing accumulator"))
		_check("input schema", meta.aircraft_input_format == AircraftData.FORMAT)
		_check("raw input identity " + entry.id, meta.aircraft_input_sha256 == FileAccess.get_sha256(entry.data))
		_check("semantic hash is separately named", meta.aircraft_semantic_sha256 == session.aircraft.model.data_sha256)
		_check("ambiguous legacy hash absent", not meta.has("aircraft_data_sha256"))
		_check("rigid body layout", JSON.parse_string(meta.state_layout).size() == RB.SIZE)
		_check("auxiliary layout", JSON.parse_string(meta.aux_layout) == Trace.COLUMNS.slice(30))
		_check("initial auxiliary snapshot", _aux_matches(meta.recording_start_aux, session.sim.aux.slice(0, Session.AUX_LAYOUT.size())))
		_check("powered start", meta.recording_start_engine_running == "true")
		if entry.id in ["p51d-mustang-120", "f4u-corsair-250"]:
			# The gasoline shaft warbirds (P-51, F4U-09 Corsair) share the coupled shaft law and the tail slipstream.
			_check("%s records the configured coupled shaft law" % entry.id,
				meta.propulsion_model == "propeller-shaft-coupled-rk4-v1" and meta.shaft_integrator == "coupled-rk4")
			_check("%s slipstream" % entry.id, meta.propwash_model == "tail-slipstream-increment-v1")
		elif entry.id == "sebart-avanti-s-a200-p100rx":
			_check("Avanti continuous turbine governor", meta.propulsion_model == Turbine.CONTINUOUS_LAW
				and meta.turbine_integrator == "rk4")
			_check("Avanti no propwash", meta.propwash_model == "none")
			if session.flaps_available():
				var input_layout: Array = JSON.parse_string(meta.input_layout)
				_check("Avanti flap schema and law are explicit", meta.metadata_schema == "openrc-flight-meta v9"
					and meta.flap_law == Flaps.LAW
					and meta.flap_trace_schema == "openrc-flap-trace v1")
				_check("Avanti flap indices follow gear and the declared input order",
					meta.flap_aux_index == session.flap_aux_index()
					and meta.flap_input_index == 6
					and input_layout == ["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake", "flaps"]
					and meta.recording_start_flap == session.flap_state().actual)
		elif entry.id in [TIMBER, "skywalker-x8"]:
			_check("%s coupled electric motor" % entry.id, meta.propulsion_model == "electric-fixed-bus-coupled-stop-v1")
			_check("%s no unmodeled propwash" % entry.id, meta.propwash_model == "none")
		elif glow_profiled:
			# EX-14c: a glow aircraft may declare the quasi-static tail slipstream (the Extra); it is then named, never transported.
			var washed: bool = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()
			_check("glow propwash is named exactly as declared " + entry.id,
				meta.propwash_model == ("tail-slipstream-increment-v1" if washed else "none") and meta.continuous_layout.find("axial wash") < 0)
		else:
			_check("Stik/Extra lag " + entry.id, meta.propulsion_model == "propeller-rpm-lag-v1")
			_check("Stik/Extra no propwash", meta.propwash_model == "none")

		# T may start recording after takeoff. The snapshot must describe that instant,
		# not the trim solution or the previous aircraft's initial state.
		session.sim.inputs[0] = 0.7
		for _tick in 12:
			session.sim.step()
		recorder.start(session.trace_meta())
		var trace_row_ok: bool = recorder.trace.row_count() == 1
		_check("recording-start row accepted " + entry.id, trace_row_ok,
			str({invalid = recorder.trace._invalid_weather, metadata_schema = recorder.trace.meta.get("metadata_schema"),
				propulsion_model = recorder.trace.meta.get("propulsion_model"), columns = recorder.trace.columns(),
				mass_schema = recorder.trace.meta.get("mass_trace_schema"), continuous_size = session.sim.continuous.size()}))
		if session.liquid_fuel_is_active():
			var current_fill: float = recorder.trace.value(0, "fuel_fill_fraction") if trace_row_ok else NAN
			var recorded_meta: Dictionary = recorder.trace.meta
			_check("mid-flight trace separates reset preference from accepted fuel inventory",
				trace_row_ok and recorded_meta.recording_start_tick == 12 and recorded_meta.fuel_start_fill_known == true
				and recorded_meta.fuel_start_fill == 1.0 and is_finite(current_fill) and current_fill < 1.0,
				"recorded fill=%s selected reset fill=%s" % [str(current_fill), str(recorded_meta.get("fuel_start_fill"))])
		if entry.id == TIMBER:
			_check("Timber trace carries endpoint-sampled motor current", recorder.trace.columns().has("motor_current_a")
				and recorder.trace.columns().has("drive_bus_current_a"))
		if glow_profiled:
			_check("glow CSV exposes accepted firing events and finite tank state",
				recorder.trace.columns().has("glow_fire_events") and recorder.trace.columns().has("glow_fuel_kg")
				and recorder.trace.columns().has("glow_line_fuel_kg")
				and recorder.trace.columns().has("mass_kg")
				and recorder.trace.row_count() == 1
				and recorder.trace.to_csv().begins_with("# format: openrc-trace v14\n"))
		var snapshot: Dictionary = recorder.trace.meta.duplicate(true)
		_check("mid-flight recording tick", snapshot.recording_start_tick == 12)
		_check("mid-flight aux snapshot", _aux_matches(snapshot.recording_start_aux, session.sim.aux.slice(0, Session.AUX_LAYOUT.size())))
		_check("CSV keeps new metadata", recorder.trace.to_csv().contains("# propulsion_model: " + snapshot.propulsion_model),
			"rows=%d invalid=%s" % [recorder.trace.row_count(), recorder.trace._invalid_weather])
		if trace_row_ok:
			for index in RB.SIZE:
				_check("state layout maps sample %d" % index,
					absf(recorder.trace.value(0, RB.STATE_LAYOUT[index]) - session.sim.state[index]) < 1e-12)
			for index in Session.AUX_LAYOUT.size():
				_check("aux layout maps sample %d" % index,
					recorder.trace.value(0, Session.AUX_LAYOUT[index]) == session.sim.aux[index])
		session.sim.step()
		_check("metadata snapshot remains at recording start", recorder.trace.meta == snapshot)
		recorder.recording = false

	# Remove opt-ins while retaining the P-51 ID: dispatch must follow configuration.
	session.aircraft_path = Catalog.entry("p51d-mustang-120").data
	session.reload()
	var prop: Dictionary = session.aircraft.model.propulsion
	var original_propulsion: Dictionary = prop.duplicate(true)
	var original_integrator: String = session.shaft_integrator()
	prop.erase("shaft")
	prop.erase("slipstream")
	prop.erase("liquid_fuel")
	prop.erase("normal_force")
	prop.erase("pfactor_moment")
	session._shaft_integrator = "split"
	session.aircraft.model.envelope = {}
	var changed: Dictionary = session.trace_meta()
	_check("same ID, lag path", changed.propulsion_model == "propeller-rpm-lag-v1")
	_check("same ID, no slipstream", changed.propwash_model == "none")
	_check("same ID, global aero", changed.aero_model == "global-derivatives-v1")
	var features: Dictionary = JSON.parse_string(changed.propulsion_features)
	_check("same ID, no propeller normal force/P-factor", not features.propeller_normal_force and not features.propeller_pfactor)
	session.aircraft.model.propulsion = original_propulsion
	session._shaft_integrator = original_integrator

	session.aircraft_path = Catalog.entry(Catalog.DEFAULT_ID).data
	session.reload()
	_check("glide trim succeeds", session.trim_at(15.0, "glide").ok)
	session.reset()
	var glide: Dictionary = session.trace_meta()
	_check("glide retains configured propulsion model", glide.propulsion_model == "propeller-rpm-lag-v1")
	_check("glide engine stopped", glide.recording_start_engine_running == "false")
	_check("glide RPM snapshot zero", JSON.parse_string(glide.recording_start_aux)[0] == 0.0)
	_test_input_identity(session)
	recorder.detach()
	session.free()
	print("C7-R2 / DATA-3: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check("temporary input opens", file != null)
	if file != null:
		file.store_buffer(content.to_utf8_buffer())
		file.close()


func _test_input_identity(session: Node) -> void:
	var source_path: String = Catalog.entry(Catalog.DEFAULT_ID).data
	var source: String = FileAccess.get_file_as_string(source_path)
	var original: Dictionary = AircraftData.load_file(source_path)
	var path: String = "user://data3-input-%d.json" % OS.get_process_id()
	var output: String = "user://data3-trace-%d.csv" % OS.get_process_id()
	var raw: Dictionary = JSON.parse_string(source)
	var memory: Dictionary = AircraftData.validate_and_derive(raw)
	_check("in-memory input has no file identity", memory.ok and not memory.has("input_identity"))
	_check("file identity is separate from the aircraft model; only the profile overlay adds wheel physics",
		_without_wheel_profile(original.model) == memory.model)

	# Both formatting-only changes and late numerical digits escaped the old fingerprint.
	var formatted: String = source.replace("\n", "\r\n") + " \t\r\n"
	var late_digit: String = source.replace('"value": 0.1068,', '"value": 0.1068000000000001,')
	_check("late-digit fixture changes input", source != late_digit)
	for changed in [formatted, late_digit]:
		_write(path, changed)
		var loaded: Dictionary = AircraftData.load_file(path)
		_check("changed input loads", loaded.ok)
		if not loaded.ok:
			continue
		_check("exact hash matches independent file hashing", loaded.input_identity.sha256 == FileAccess.get_sha256(path))
		_check("raw hash distinguishes changed bytes", loaded.input_identity.sha256 != original.input_identity.sha256)
		_check("legacy rounded semantic digest collides", loaded.model.data_sha256 == original.model.data_sha256)
		if changed == late_digit:
			_check("late digit reaches physics model", loaded.model.aero.CL0 != original.model.aero.CL0)

	_write(path, source)
	session.aircraft_path = path
	_check("temporary source reloads", session.reload().begins_with("aircraft reloaded:"))
	var before: Dictionary = session.trace_meta()
	_write(path, "{}")
	_check("recording identifies loaded bytes, not later disk content", session.trace_meta().aircraft_input_sha256 == before.aircraft_input_sha256)
	_check("failed reload refuses replacement", session.reload().begins_with("reload failed"))
	_check("failed reload retains source identity", session.trace_meta().aircraft_input_sha256 == before.aircraft_input_sha256)
	var trace: RefCounted = Trace.new()
	trace.meta = session.trace_meta()
	_check("trace artifact saves", trace.save(output) == OK)
	_check("saved trace preserves exact digest", FileAccess.get_file_as_string(output).contains(
		"# aircraft_input_sha256: " + FileAccess.get_sha256(source_path)))
	_check("in-memory candidate applies", session._apply(memory))
	_check("in-memory replacement cannot inherit file identity", session.trace_meta().aircraft_input_sha256 == "unavailable: in-memory input")
	_check("invalid input has no identity", not AircraftData.load_file(path).has("input_identity"))
	_check("temporary input removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	_check("temporary trace removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(output)) == OK)
