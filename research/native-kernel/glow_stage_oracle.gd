## NK-3 research-only Glow joint-stage oracle. Actual catalog sessions own
## lifecycle/events while native stages evaluate source, feed and rigid-body
## response. It does not change app admission or claim physical validation.
extends "stage_oracle.gd"

const GlowAdapter := preload("res://sim/native/glow_stage_adapter.gd")
const GlowWeather := preload("res://physics/wind_config.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")

const GLOW_AIRCRAFT := ["stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "gp-extra-300s-60"]


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/glow/flight.gd", "res://physics/glow/lifecycle.gd", "res://physics/glow/source.gd",
			"res://physics/glow/two_stroke.gd", "res://physics/glow/four_stroke.gd", "res://physics/glow/carburetor.gd",
			"res://physics/glow/thermal.gd", "res://physics/glow/propeller.gd", "res://physics/glow/fuel_mass.gd",
			"res://physics/glow/fuel_feed.gd", "res://physics/glow/profile.gd", "res://physics/glow/installation.gd",
			"res://physics/mass_inventory.gd", "res://physics/fixed_datum_body.gd", "res://physics/rigid_body.gd",
			"res://physics/rotor_coupling.gd", "res://physics/wind_aircraft_flow.gd", "res://physics/slipstream.gd",
			"res://app_state/aircraft_catalog.gd", "res://data/aircraft/stik_glow_61fx_2t.json",
			"res://data/aircraft/stik_glow_55ax_2t.json", "res://data/aircraft/stik_glow_fs64v_4t.json",
			"res://data/aircraft/gp_extra_300s_60.json", "res://data/glow/stik_61fx_2t.json",
			"res://data/glow/stik_55ax_2t.json", "res://data/glow/stik_fs64v_4t.json",
			"res://data/glow/extra_61fx_2t.json", "res://data/glow/os_max_61fx_candidate.json",
			"res://data/glow/os_max_55ax_candidate.json", "res://data/glow/os_fs_64v_candidate.json",
			"res://data/glow/os_max_61fx_installed_candidate.json", "res://data/glow/profile_contract.json",
			"res://data/fuels/openrc-fuel-registry.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-glow-stage-oracle v1"
	var ticks: int = int(_options.get("ticks", "64"))
	if _states < 1 or ticks < 1:
		_failures.append("glow stage states and ticks must be positive")
		return
	_report.glow_stage = {cases = [], trajectories = []}
	var scenarios: Array[Dictionary] = []
	for label: String in ["calm", "gusty", "turbulent", "hot-high", "standard-column",
			"spatial-gusty-v1", "spatial-thermal-soaring-v2"]:
		var config: Dictionary = GlowWeather.preset(label)
		if config.is_empty():
			_failures.append("glow stage weather preset absent: " + label)
			continue
		if label == "gusty": config.gust_delay_s = 0.0
		if label == "spatial-gusty-v1": config.spatial_wind.gusts.events[0].start_s = 0.0
		if label == "spatial-thermal-soaring-v2":
			var cell: Dictionary = config.spatial_wind.thermal_field.cells[0]
			cell.birth_s = 0.0
			cell.duration_s = 120.0
			cell.center_ne_m = [60.0, -40.0]
			cell.drift_ne_mps = [0.0, 0.0]
		scenarios.append({id = label, config = config})
	var index := 0
	for id: String in GLOW_AIRCRAFT:
		for scenario: Dictionary in scenarios:
			_check_glow_stage(id, scenario, _states)
		_check_glow_trajectory(id, scenarios[[0, 2, 3, 6][index]], ticks)
		for event_kind: String in ["exhaustion", "overheat", "stall", "cut_restart"]:
			_check_glow_trajectory(id, scenarios[0], maxi(12, ticks), event_kind)
		index += 1


func _glow_session(id: String, weather: Dictionary) -> Node:
	var session: Node = Session.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(Catalog.data_for(id), id)
	if not session.is_flyable() or not session.glow_is_active():
		_failures.append("glow session failed: %s (%s)" % [id, session.pause_reason])
		session.free()
		return null
	if not session.setup_weather(weather):
		_failures.append("glow weather failed: %s (%s)" % [id, session.weather_error])
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok or not session.set_field(field.field) or not session.set_lake_context(lake.lake):
		_failures.append("glow field/lake failed: " + id)
		session.free()
		return null
	session.start_choice = Session.START_AIRBORNE
	session.reset()
	if session.sim.paused or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
		_failures.append("glow reset failed: %s (%s)" % [id, session.pause_reason])
		session.free()
		return null
	if not session.engine_running and not session.glow_start():
		_failures.append("glow starter failed: " + id)
		session.free()
		return null
	return session


func _glow_aux(context: Dictionary, session: Node, state: PackedFloat64Array) -> PackedFloat64Array:
	var gear: Dictionary = context.gear
	var aux: PackedFloat64Array
	if gear.has("contacts") and not gear.contacts.is_empty(): aux = _stage_aux(context, session, state)
	else:
		aux = context.aux.duplicate()
		for k: int in 3: aux[Session.AUX_SERVO + k] = _rng.randf_range(-1.0, 1.0)
		var lag: int = session.downwash_index()
		if lag >= 0: aux[lag] = _rng.randf_range(-5.0, 30.0)
	if session.flaps_available():
		var flap: int = session.flap_aux_index()
		if flap >= 0 and flap < aux.size(): aux[flap] = _rng.randf_range(0.0, 1.0)
	return aux


func _check_glow_stage(id: String, scenario: Dictionary, count: int) -> void:
	var label := "%s/%s" % [id, str(scenario.id)]
	var session := _glow_session(id, scenario.config)
	if session == null: return
	var config: Dictionary = GlowAdapter.config_for(session)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "provider identity refused"}
	if not prepared.get("ok", false):
		_failures.append("glow stage %s prepare refused: %s" % [label, str(prepared.get("error", ""))])
		session.free()
		return
	if session._weather.has_turbulence():
		session.sim.step()
		if session.sim.tick != 1 or session.sim.paused or not session.sim.fault_reason.is_empty():
			_failures.append("glow OU pre_tick failed: " + label)
			session.free()
			return
	var context := {model = session.aircraft.model, gear = session.current_landing_gear(session.sim.aux),
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate()}
	var initial: PackedFloat64Array = session.sim.continuous.duplicate()
	var install: Dictionary = session.aircraft.model.propulsion.glow
	if initial.size() != GlowFlight.SIZE + session.wheel_count():
		_failures.append("glow state layout invalid: " + label)
		session.free()
		return
	var finite := 0
	var refused := 0
	for i: int in count:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var state: PackedFloat64Array = drawn.s
		if session._weather.is_spatial() and not drawn.malformed:
			var domain: Dictionary = scenario.config.spatial_wind.domain
			state[RB.POS] = clampf(state[RB.POS], -float(domain.half_extent_north_m) + 5.0, float(domain.half_extent_north_m) - 5.0)
			state[RB.POS + 1] = clampf(state[RB.POS + 1], -float(domain.half_extent_east_m) + 5.0, float(domain.half_extent_east_m) - 5.0)
			state[RB.POS + 2] = -_rng.randf_range(5.0, float(domain.max_height_agl_m) - 5.0)
			if scenario.id == "spatial-thermal-soaring-v2" and i % 7 == 0:
				state[RB.POS] = 60.0
				state[RB.POS + 1] = -40.0
				state[RB.POS + 2] = -float(scenario.config.spatial_wind.thermal_field.cells[0].top_agl_m) * 0.5
		var aux := _glow_aux(context, session, state)
		session.sim.aux = aux
		session.sim.inputs[3] = _rng.randf_range(0.0, 1.0)
		session.engine_running = i % 5 != 0
		if not GlowAdapter.set_context(session, _native, aux, session.sim.inputs, session.sim.time()):
			_failures.append("glow stage context refused: " + label)
			break
		var values: PackedFloat64Array = initial.duplicate()
		values[0] = _rng.randf_range(0.0, float(install.profile.operation.max_rpm))
		if i % 13 == 0: values[0] = [0.0, 0.5, -0.001, float(install.profile.operation.max_rpm) + 1.0][(i / 13) % 4]
		values[1] = _rng.randf_range(float(install.unusable_fuel_kg), float(install.capacity_fuel_kg))
		if i % 29 == 0: values[1] = [0.0, -0.001, float(install.capacity_fuel_kg), float(install.unusable_fuel_kg)][(i / 29) % 4]
		values[2] = _rng.randf_range(280.0, 480.0)
		values[3] = _rng.randf_range(0.0, 1.0)
		values[4] = clampf(initial[4] * _rng.randf_range(0.8, 1.2), 0.001, 1.0)
		values[5] = maxf(0.0, initial[5] * (maxf(0.0, values[0]) / maxf(1.0, initial[0])) * _rng.randf_range(0.7, 1.3))
		values[6] = _rng.randf_range(0.0, float(install.profile.identity.cycle_revolutions) * 1.1)
		values[7] = 1.0 if i % 3 != 0 else 0.0
		values[12] = float(install.profile.operation.nominal_mixture) * _rng.randf_range(0.8, 1.2)
		values[18] = 0.0 if i % 7 == 0 else 1.0
		for k: int in range(GlowFlight.SIZE, values.size()): values[k] = _rng.randf_range(-25.0, 25.0)
		if i > 0 and i % 83 == 0: values.resize(values.size() - 1)
		var stage_time: float = [0.0, 0.01, 0.5, 4.0, 10.0, 30.0][i % 6]
		if session._weather.has_turbulence():
			var ti: int = session.turbulence_index()
			stage_time = aux[ti + 6] + session.sim.dt() * [0.0, 0.5, 1.0][i % 3]
		var reference: Dictionary = GlowFlight.evaluate(state, values, stage_time, session)
		var native: Dictionary = _native.stage(state, values, stage_time)
		_compare_glow_stage(reference, native, [label, i, state, aux, values, stage_time, session.sim.inputs, session.engine_running])
		if _glow_finite_stage(reference, values.size()): finite += 1
		else: refused += 1
		_tally("glow_stage", "states")
	if finite == 0 or refused == 0: _failures.append("glow stage %s missed finite or refused stages" % label)
	_report.glow_stage.cases.append({name = label, states = count, finite = finite, refused = refused,
		family = install.profile.family, feed = install.has("fuel_feed"), wheel_count = session.wheel_count()})
	if scenario.id == "calm": _check_glow_snapshot_guards(id, config, session)
	session.free()


func _compare_glow_stage(reference: Dictionary, native: Dictionary, inputs: Array) -> void:
	_compare("glow_stage_shape", PackedFloat64Array([reference.size(), 1.0 if reference.keys() == native.keys() else 0.0]),
		PackedFloat64Array([native.size(), 1.0]), inputs)
	if reference.is_empty() or native.is_empty(): return
	_compare("glow_stage_loads", reference.loads, native.loads, inputs)
	_compare("glow_stage_derivative", reference.derivative, native.derivative, inputs)
	_compare("glow_stage_rotor", reference.rotor_momentum, native.rotor_momentum, inputs)
	_compare("glow_stage_body", reference.body_derivative, native.body_derivative, inputs)
	_compare("glow_stage_bytes", var_to_bytes(reference), var_to_bytes(native), inputs)


static func _glow_finite_stage(stage: Dictionary, derivative_size: int) -> bool:
	if not stage.get("loads") is PackedFloat64Array or not stage.get("derivative") is PackedFloat64Array \
			or not stage.get("rotor_momentum") is PackedFloat64Array or not stage.get("body_derivative") is PackedFloat64Array \
			or stage.loads.size() != 6 or stage.derivative.size() != derivative_size \
			or stage.rotor_momentum.size() != 3 or stage.body_derivative.size() != 13: return false
	for values: PackedFloat64Array in [stage.loads, stage.derivative, stage.rotor_momentum, stage.body_derivative]:
		for value: float in values:
			if not is_finite(value): return false
	return true


static func _glow_tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs, sim.last_loads, sim.modes, sim.last_events])


func _check_glow_trajectory(id: String, scenario: Dictionary, ticks: int, event_kind := "nominal") -> void:
	var label := "%s/%s/%s" % [id, str(scenario.id), event_kind]
	var reference := _glow_session(id, scenario.config)
	var native := _glow_session(id, scenario.config)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	# Existing session event policy remains in use; set the same near-boundary
	# accepted state in each disposable session to exercise its real locator.
	for flight: Node in [reference, native]:
		var install: Dictionary = flight.aircraft.model.propulsion.glow
		match event_kind:
			"exhaustion": flight.sim.continuous[1] = float(install.unusable_fuel_kg) + 1.0e-8
			"overheat": flight.sim.continuous[2] = float(install.settings.temperature_firing_hot_zero_k) + 1.0
			"stall":
				var rpm: float = float(install.settings.stall_rpm) * 0.5
				flight.sim.continuous[0] = rpm
				flight.sim.aux[Session.AUX_RPM] = rpm
				for axis: int in 3: flight.sim.state[RB.VEL + axis] = 0.0
				var admission: float = GlowFlight.admission_at(install, flight.sim.continuous[4], rpm)
				var source: Dictionary = GlowFlight.Source.evaluate(install.profile, rpm, admission,
					flight.sim.continuous[12], 1.225 * flight.engine_charge_ratio(), true)
				if not source.get("ok", false):
					_failures.append("glow stall fixture source invalid: " + label)
					reference.free()
					native.free()
					return
				flight.sim.continuous[5] = source.delivered_fuel_kg_s
	var config: Dictionary = GlowAdapter.config_for(native)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "provider identity refused"}
	if not prepared.get("ok", false):
		_failures.append("glow trajectory %s prepare failed: %s" % [label, str(prepared.get("error", ""))])
		reference.free()
		native.free()
		return
	var inner: Callable = native.sim.model.pre_tick
	var context_state := {ok = true}
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = inner.call(aux, inputs, dt)
		if next is PackedFloat64Array and next.size() == aux.size():
			context_state.ok = bool(context_state.ok) and GlowAdapter.set_context(native, _native, next, inputs, native.sim.time())
		return next
	native.sim.model.pre_tick = wrapped
	native.sim.model.stage = Callable(_native, "stage")
	context_state.ok = GlowAdapter.set_context(native, _native, native.sim.aux, native.sim.inputs, native.sim.time())
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var complete := true
	var ran := 0
	var first_divergence := -1
	var located: Array[String] = []
	var cut_ok := false
	var restart_ok := false
	if not _compare("glow_trajectory_tick", _glow_tape(reference), _glow_tape(native), [label, 0]): first_divergence = 0
	for i: int in ticks:
		if event_kind == "cut_restart" and i == 2:
			var left: bool = reference.glow_cut()
			var right: bool = native.glow_cut()
			cut_ok = left and right
			_compare("glow_event_command", PackedFloat64Array([1.0 if left else 0.0]),
				PackedFloat64Array([1.0 if right else 0.0]), [label, "cut"])
		if event_kind == "cut_restart" and i == 8:
			var left: bool = reference.glow_start()
			var right: bool = native.glow_start()
			restart_ok = left and right
			_compare("glow_event_command", PackedFloat64Array([1.0 if left else 0.0]),
				PackedFloat64Array([1.0 if right else 0.0]), [label, "restart"])
		var inputs: PackedFloat64Array = reference.sim.inputs.duplicate()
		if inputs.size() >= 4:
			inputs[0] = 0.04 if i % 40 < 20 else -0.04
			inputs[1] = 0.02 if i % 60 < 30 else -0.02
			inputs[3] = [0.2, 0.5, 0.8][(i / 16) % 3]
		reference.sim.inputs = inputs.duplicate()
		native.sim.inputs = inputs.duplicate()
		reference.sim.step()
		native.sim.step()
		for event: Dictionary in reference.sim.last_events:
			located.append(str(event.get("type", "")))
		var stats: Dictionary = _native.stage_stats()
		var healthy: bool = reference.sim.tick == i + 1 and native.sim.tick == i + 1 and context_state.ok \
			and not reference.sim.paused and not native.sim.paused and reference.sim.fault_reason.is_empty() \
			and native.sim.fault_reason.is_empty() and reference.crash.is_empty() and native.crash.is_empty()
		var covered: bool = native.sim.model.stage == Callable(_native, "stage") and native.sim.model.pre_tick == wrapped \
			and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		if not healthy or not covered:
			_failures.append("glow trajectory %s tick %d failed or lacked native coverage: %s/%s" %
				[label, i + 1, reference.sim.fault_reason, native.sim.fault_reason])
			complete = false
			break
		previous = stats
		ran += 1
		if not _compare("glow_trajectory_tick", _glow_tape(reference), _glow_tape(native), [label, i + 1]) and first_divergence < 0:
			first_divergence = i + 1
	if event_kind == "exhaustion" and not located.has("fuel_exhausted"):
		_failures.append("glow exhaustion fixture located no fuel event: " + label)
	if event_kind in ["overheat", "stall"] and not located.has("glow_stopped"):
		_failures.append("glow %s fixture located no stopped event: %s" % [event_kind, label])
	if event_kind == "cut_restart" and (not cut_ok or not restart_ok):
		_failures.append("glow cut/restart command failed: " + label)
	_report.glow_stage.trajectories.append({name = label, event_kind = event_kind, requested_ticks = ticks, ticks_run = ran,
		complete = complete and ran == ticks, first_divergence = first_divergence, located = located,
		cut_ok = cut_ok, restart_ok = restart_ok,
		native_stage_calls = int(previous.get("stage_calls", 0)), native_context_calls = int(previous.get("context_calls", 0))})
	if first_divergence >= 0: _failures.append("glow trajectory %s diverged at tick %d" % [label, first_divergence])
	reference.free()
	native.free()


func _check_glow_snapshot_guards(id: String, config: Dictionary, session: Node) -> void:
	var variants: Array[Dictionary] = []
	var changed: Dictionary = config.duplicate(true)
	changed.glow_snapshot.blade.pitch_m = float(changed.glow_snapshot.blade.pitch_m) * 1.01
	variants.append({name = "blade_value", config = changed})
	changed = config.duplicate(true)
	changed.glow_snapshot.lifecycle.thermal.cooling_base_w_k += 0.001
	variants.append({name = "thermal_value", config = changed})
	changed = config.duplicate(true)
	var curve: PackedFloat64Array = changed.glow_snapshot.source.mechanical_torque_nm.duplicate()
	curve[1] += 0.00001
	changed.glow_snapshot.source.mechanical_torque_nm = curve
	variants.append({name = "source_map", config = changed})
	changed = config.duplicate(true)
	changed.glow_snapshot.store.unusable_kg = float(changed.glow_snapshot.store.unusable_kg) + 0.00001
	variants.append({name = "fuel_residue", config = changed})
	changed = config.duplicate(true)
	changed.model.mass_kg = float(changed.model.mass_kg) + 0.01
	variants.append({name = "reference_mass", config = changed})
	changed = config.duplicate(true)
	var centers: Array = changed.glow_snapshot.mass.centers.duplicate(true)
	var flipped := false
	for row_index: int in centers.size():
		var row: PackedFloat64Array = centers[row_index].duplicate()
		for k: int in row.size():
			if row[k] == 0.0:
				var old_bits: int = _bits(row[k])
				row[k] = _from_bits(PackedInt64Array([-9223372036854775808 if old_bits == 0 else 0]))[0]
				flipped = _bits(row[k]) != old_bits
				break
		if flipped:
			centers[row_index] = row
			break
	if flipped:
		changed.glow_snapshot.mass.centers = centers
	else:
		# Some installations have an offset on all three tank axes. The
		# combustion table includes a zero knot and is equally source-owned.
		var combustion: PackedFloat64Array = changed.glow_snapshot.source.combustion_efficiency.duplicate()
		for k: int in combustion.size():
			if combustion[k] == 0.0:
				var old_bits: int = _bits(combustion[k])
				combustion[k] = _from_bits(PackedInt64Array([-9223372036854775808 if old_bits == 0 else 0]))[0]
				flipped = _bits(combustion[k]) != old_bits
				break
		if flipped: changed.glow_snapshot.source.combustion_efficiency = combustion
	if not flipped:
		_failures.append("glow signed-zero fixture unavailable: " + id)
	else:
		variants.append({name = "packed_signed_zero", config = changed})
	if config.glow_snapshot.has("feed"):
		changed = config.duplicate(true)
		changed.glow_snapshot.feed.idle_drive_pressure_pa *= 1.01
		variants.append({name = "feed_pressure", config = changed})
	var index: int = GLOW_AIRCRAFT.find(id)
	var other_id: String = GLOW_AIRCRAFT[(index + 1) % GLOW_AIRCRAFT.size()]
	var other: Dictionary = AircraftData.load_file(Catalog.data_for(other_id))
	if not other.get("ok", false):
		_failures.append("glow cross-aircraft fixture failed: " + other_id)
	else:
		var other_snapshot: Dictionary = GlowAdapter.snapshot(other.model.propulsion.glow)
		if not _native.prepare_glow(other_snapshot).get("ok", false):
			_failures.append("glow cross-aircraft source itself is invalid: " + other_id)
		else:
			changed = config.duplicate(true)
			changed.glow_snapshot = other_snapshot
			variants.append({name = "valid_other_aircraft", config = changed})
	for item: Dictionary in variants:
		var result: Dictionary = _native.prepare_stage(item.config)
		var refused: bool = not result.get("ok", true) and not str(result.get("error", "")).is_empty()
		_compare("glow_stage_snapshot_refusal", PackedFloat64Array([1.0]),
			PackedFloat64Array([1.0 if refused else 0.0]), [id, item.name])
		if not refused:
			_failures.append("glow stage accepted mismatched snapshot %s/%s" % [id, item.name])
		elif not _native.stage(session.sim.state, session.sim.continuous, session.sim.time()).is_empty():
			_failures.append("glow failed prepare retained a stage: %s/%s" % [id, item.name])
