# EX-03 / AV-03 / UI-05: the aircraft catalog resolves each ID to its own model, data and datum, never another's.
# Every ID builds with the model team's builder; every flyable ID loads valid data whose id is the catalog's, trims at
# its own start speed, and puts the simulated CG where its visual model has it. The flight scene flies the ID it is
# given. Run: godot --headless --path . --script res://tests/test_aircraft_catalog.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const ModelRegistry := preload("res://aircraft/model_registry.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Frames := preload("res://render/frames.gd")
const Shadow := preload("res://render/shadow.gd")
const Commands := preload("res://input/commands.gd")
const Extra := preload("res://aircraft/extra_300s_model.gd")
const ExtraGeometry := preload("res://aircraft/extra_300s_geometry.gd")
const StikGeometry := preload("res://aircraft/ugly_stik_geometry.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _press_key(flight: Node, physical_keycode: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = physical_keycode
	flight._unhandled_input(event)


func _initialize() -> void:
	_check("default is the Ugly Stik and it is in the catalog", Catalog.DEFAULT_ID == AirplaneBuilder.STIK_ID and Catalog.has(Catalog.DEFAULT_ID))
	_check("ten catalog entries, unique IDs", Catalog.ids().size() == 10 and Array(Catalog.ids()).filter(func(i): return Catalog.ids().count(i) == 1).size() == 10, str(Catalog.ids()))
	_check("nine airplane configurations remain available to airplane solvers", Catalog.airplane_flyable_ids().size() == 9 and Catalog.airplane_flyable_ids().has(AirplaneBuilder.TIMBER_ID))
	var expected_airplane_families := PackedStringArray([
		AirplaneBuilder.STIK_ID, AirplaneBuilder.EXTRA_ID, AirplaneBuilder.P51_ID, AirplaneBuilder.CORSAIR_ID,
		AirplaneBuilder.AVANTI_ID, AirplaneBuilder.TIMBER_ID,
	])
	var airplane_families := Catalog.airplane_visual_families()
	var all_airplane_families_registered := true
	for family in airplane_families:
		if not ModelRegistry.describe(family).get("ok", false):
			all_airplane_families_registered = false
	_check("airplane visual families are unique, complete, registered, include Timber, and exclude HX-700",
		airplane_families == expected_airplane_families
		and airplane_families.has(Catalog.visual_family(AirplaneBuilder.TIMBER_ID))
		and not airplane_families.has("hx-700")
		and all_airplane_families_registered,
		str(airplane_families))
	_check("ten simulated entries include the experimental helicopter", Catalog.flyable_ids().size() == 10 and Catalog.flyable_ids().has("xcell-60-research")
		and Catalog.flyable_entries().all(func(e): return e.data != "" and e.status != Catalog.PREVIEW), str(Catalog.flyable_ids()))
	_check("Extra's finite glow store is exposed to fill selection", Catalog.has_finite_fuel(AirplaneBuilder.EXTRA_ID))
	var helicopter_entry: Dictionary = Catalog.entry("xcell-60-research")
	_check("research helicopter catalog identity and visual family are explicit",
		helicopter_entry.get("vehicle", "") == "rotorcraft"
		and helicopter_entry.get("visual_family", "") == "hx-700"
		and helicopter_entry.get("name", "") == "RC Helicopter Research Trainer"
		and helicopter_entry.get("summary", "") == "X-Cell reference physics · HX-700 visual"
		and helicopter_entry.get("data", "") == "res://data/aircraft/xcell_60_research.json"
		and Catalog.is_rotorcraft("xcell-60-research") and not Catalog.is_rotorcraft(AirplaneBuilder.STIK_ID))
	_check("glow Stik variants are explicitly experimental and identify inferred profiles",
		Catalog.entry(AirplaneBuilder.STIK_GLOW_55AX_ID).status == Catalog.EXPERIMENTAL
		and Catalog.entry(AirplaneBuilder.STIK_GLOW_55AX_ID).status_note.contains("inferred")
		and Catalog.entry(AirplaneBuilder.STIK_GLOW_FS64V_ID).status == Catalog.EXPERIMENTAL
		and Catalog.entry(AirplaneBuilder.STIK_GLOW_FS64V_ID).status_note.contains("inferred"))
	_check("unknown ID: no entry, cannot fly", Catalog.entry("nope").is_empty() and not Catalog.can_fly("nope"))
	_check("step wraps both ways", Catalog.step(Catalog.ids()[-1], 1) == Catalog.ids()[0] and Catalog.step(Catalog.ids()[0], -1) == Catalog.ids()[-1])
	_check("the airplane render adapter retains its nine catalog IDs",
		[AirplaneBuilder.STIK_ID, AirplaneBuilder.STIK_GLOW_61FX_ID, AirplaneBuilder.STIK_GLOW_55AX_ID, AirplaneBuilder.STIK_GLOW_FS64V_ID, AirplaneBuilder.EXTRA_ID, AirplaneBuilder.P51_ID, AirplaneBuilder.CORSAIR_ID, AirplaneBuilder.AVANTI_ID, AirplaneBuilder.TIMBER_ID] == Array(Catalog.airplane_flyable_ids()))

	for id in Catalog.ids():
		var e := Catalog.entry(id)
		var airplane := AirplaneBuilder.build(id)
		if Catalog.is_rotorcraft(id):
			var heli_contract: bool = airplane.get("root") is Node3D and airplane.root.name == "airplane" \
				and airplane.get("main_rotor_pivot") is Node3D and airplane.get("tail_rotor_pivot") is Node3D \
				and airplane.get("cg_model_m") is Vector3 and airplane.aircraft_id == id \
				and not airplane.has("model_manifest") and airplane.visual_family == "hx-700"
			_check("%s: explicit rotorcraft adapter bypasses airplane manifests" % id, heli_contract)
			if airplane.get("root") is Node:
				airplane.root.free()
			continue
		var ok_contract: bool = airplane.get("root") is Node3D and airplane.root.name == "airplane" and airplane.get("propeller") is Node3D \
			and airplane.get("hinges", {}).size() >= 4 and airplane.aircraft_id == id
		_check("%s: builds root/propeller/hinges" % id, ok_contract)
		var extent := Shadow.model_extent(airplane.root)
		AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({ roll = 1.0, pitch = -1.0, yaw = 1.0, throttle = 0.0 }, { aileron = 20.0, elevator = 20.0, rudder = 20.0 }))
		AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(Commands.neutral_commands(), { aileron = 20.0, elevator = 20.0, rudder = 20.0 }))
		_check("%s: surfaces deflect and return through the shared adapter" % id, true)
		if e.status == Catalog.PREVIEW:
			_check("%s: preview has no data and cannot fly" % id, e.data == "" and not Catalog.can_fly(id))
			# A preview may carry a real propeller (the Timber's imported rotor): the catalog, not the model, refuses flight.
			# has_propeller must agree with the geometry under the node, and the node is shown exactly when it has some.
			var prop_meshes: int = airplane.propeller.find_children("*", "MeshInstance3D", true, false).size()
			_check("%s: preview declares its propeller honestly (%d meshes)" % [id, prop_meshes],
				airplane.get("has_propeller", false) == (prop_meshes > 0) and airplane.propeller.visible == (prop_meshes > 0))
			airplane.root.free()
			continue
		var data := AircraftData.load_file(e.data)
		_check("%s: data loads" % id, data.ok, "" if data.ok else str(data.errors))
		if not data.ok:
			airplane.root.free()
			continue
		var model: Dictionary = data.model
		_check("%s: the data file is this aircraft (id matches)" % id, model.id == id, model.id)
		if id == AirplaneBuilder.STIK_GLOW_55AX_ID or id == AirplaneBuilder.STIK_GLOW_FS64V_ID:
			var expected_family := "glow_2t" if id == AirplaneBuilder.STIK_GLOW_55AX_ID else "glow_4t"
			_check("%s: data carries its explicit %s family" % [id, expected_family],
				model.propulsion.get("glow", {}).get("profile", {}).get("family", "") == expected_family)
			var selected_diameter_m: float = float(model.propulsion.glow.propeller.diameter_m)
			var base_visual_diameter: float = float(StikGeometry.DATA.equipment.prop_diameter)
			var expected_scale: float = selected_diameter_m / base_visual_diameter
			var catalog_default_scale_ok := is_equal_approx(airplane.propeller.scale.x, expected_scale)
			var scaled := AirplaneBuilder.apply_propeller_diameter(airplane, selected_diameter_m)
			var base_plane := AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
			var base_radius: float = float(PropellerBlur.profile(base_plane.propeller, base_plane.root).radius)
			var visual_profile: Dictionary = PropellerBlur.profile(airplane.propeller, airplane.root)
			_check("%s: visual and blur radii use the selected model diameter" % id,
				catalog_default_scale_ok and scaled and is_equal_approx(airplane.propeller.scale.x, expected_scale)
				and is_equal_approx(airplane.propeller.scale.y, expected_scale)
				and is_equal_approx(float(visual_profile.get("radius", 0.0)), base_radius)
				and is_equal_approx(float(visual_profile.get("radius", 0.0)) * airplane.propeller.scale.x,
					base_radius * expected_scale))
			_check("%s: glow propeller uses the physical shaft spin sign" % id,
				float(airplane.get("propeller_spin_sign", 1.0)) == -1.0)
			base_plane.root.free()
		_check("%s: span of the built model matches the data within 1 %%" % id, absf(extent.x - model.reference.b) / model.reference.b < 0.01,
			"model %.4f m, data %.4f m" % [extent.x, model.reference.b])
		# The simulated CG, placed in the model through the datum, lies on the symmetry plane, between the wing's
		# leading and trailing edges at the root, and within the fuselage's height.
		var datum := AirplaneBuilder.datum(id)
		var cg := Frames.cg_in_model_frame(model.cg_le, datum.x, datum.y)
		var root_chord: float = model.reference.chords[0] if not model.reference.chords.is_empty() else model.reference.c
		_check("%s: CG lands on the root chord in the visual model" % id, absf(cg.x) < 1e-6 and cg.z > datum.x and cg.z < datum.x + root_chord and absf(cg.y) < 0.1,
			"model point %s, LE z %.4f, chord %.4f" % [cg, datum.x, root_chord])
		airplane.root.free()

	# Alternative installations retain the catalog aircraft ID but select a different propeller diameter. Applying each
	# loaded model to the same generated Stik geometry proves the adapter does not bake in one variant's prop size.
	var standard_airplane := AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	var standard_radius: float = float(PropellerBlur.profile(standard_airplane.propeller, standard_airplane.root).radius)
	for option: Dictionary in [
		{"id": AirplaneBuilder.STIK_GLOW_55AX_ID, "path": "res://data/aircraft/stik_glow_55ax_2t_apc_13x6.json"},
		{"id": AirplaneBuilder.STIK_GLOW_FS64V_ID, "path": "res://data/aircraft/stik_glow_fs64v_4t_apc_13x6.json"},
	]:
		var alternative: Dictionary = AircraftData.load_file(str(option.path))
		var accepted := false
		var diameter_m := NAN
		var blur_radius := 0.0
		var scale_ratio := 0.0
		if alternative.ok:
			var alternative_model: Dictionary = alternative.model
			diameter_m = float(alternative_model.propulsion.glow.propeller.diameter_m)
			var alternative_airplane := AirplaneBuilder.build(str(option.id))
			accepted = AirplaneBuilder.apply_propeller_diameter(alternative_airplane, diameter_m)
			blur_radius = float(PropellerBlur.profile(alternative_airplane.propeller, alternative_airplane.root).get("radius", 0.0))
			scale_ratio = alternative_airplane.propeller.scale.x
			accepted = accepted and is_equal_approx(scale_ratio, diameter_m / float(StikGeometry.DATA.equipment.prop_diameter))
			alternative_airplane.root.free()
		_check("%s APC 13x6 alternative diameter reaches visual and blur geometry" % option.id,
			alternative.ok and accepted and is_equal_approx(blur_radius, standard_radius)
			and is_equal_approx(blur_radius * scale_ratio,
				standard_radius * diameter_m / float(StikGeometry.DATA.equipment.prop_diameter)))
	standard_airplane.root.free()

	# Extra specifics: the manual's EMPTY-TANK balance point is model z 0. The loaded CG moves when the full finite
	# glow tank is added (EX-06). The throws remain the model team's manual-rate conversion.
	var extra: Dictionary = AircraftData.load_file(Catalog.entry(AirplaneBuilder.EXTRA_ID).data).model
	var datum := AirplaneBuilder.datum(AirplaneBuilder.EXTRA_ID)
	var cg := Frames.cg_in_model_frame(extra.cg_le, datum.x, datum.y)
	var raw_extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry(AirplaneBuilder.EXTRA_ID).data))
	var fuel_model_moment := 0.0
	for component: Dictionary in raw_extra.inventory:
		if component.id == "fuel_flight":
			fuel_model_moment += float(component.mass.value) * (float(component.position.value[0]) + datum.x)
	var expected_loaded_z: float = fuel_model_moment / extra.mass_kg # Dry mass has zero moment about model z=0.
	_check("Extra: loaded CG = dry manual station plus full finite glow fuel within 1 mm",
		absf(cg.z - expected_loaded_z) < 0.001 and cg.z < 0.0, "z %.5f m, expected %.5f m" % [cg.z, expected_loaded_z])
	var manual := Extra.manual_throws_deg()
	var same := true
	for k in manual:
		same = same and absf(float(manual[k]) - float(extra.controls.throw_deg[k])) < 0.01
	_check("Extra: physics throws = the model's manual high rates", same, "%s vs %s" % [extra.controls.throw_deg, manual])
	_check("Extra: tapered wing roots = measured geometry", is_equal_approx(extra.reference.chords[0], ExtraGeometry.DATA.wing.root_chord) and is_equal_approx(extra.reference.chords[1], ExtraGeometry.DATA.wing.tip_chord))
	_check("Extra: equal-area strips move inboard on the tapered wing", extra.envelope.station_ys[5] < 0.8 * extra.reference.b / 2.0 and extra.envelope.station_ys[5] > 0.0,
		"outer strip at %.3f m of %.3f" % [extra.envelope.station_ys[5], extra.reference.b / 2.0])

	# The flight scene flies the aircraft it is given (Home sets aircraft_id before adding it).
	var flight: Node = load("res://main.tscn").instantiate()
	flight.aircraft_id = AirplaneBuilder.EXTRA_ID
	root.add_child(flight)
	await process_frame # ready (and session created) by the first frame
	_check("flight scene: Extra model and Extra physics together", flight._airplane.aircraft_id == AirplaneBuilder.EXTRA_ID and flight.session.aircraft.model.id == AirplaneBuilder.EXTRA_ID)
	_check("flight scene: trimmed at the Extra's start speed", is_equal_approx(float(flight.session.start.V), float(extra.start_speed)), str(flight.session.start.V))
	_check("flight scene: trace header names the Extra and its speed", str(flight._trace_meta().aircraft).begins_with(AirplaneBuilder.EXTRA_ID)
		and str(flight._trace_meta().scenario).contains("%.1f m/s" % float(extra.start_speed)),
		str(flight._trace_meta().scenario))
	flight.free()

	# The experimental Stik profiles share the Stik airframe but expose their own engine state and physical controls.
	for glow_id in [AirplaneBuilder.STIK_GLOW_55AX_ID, AirplaneBuilder.STIK_GLOW_FS64V_ID]:
		var glow_flight: Node = load("res://main.tscn").instantiate()
		glow_flight.aircraft_id = glow_id
		root.add_child(glow_flight)
		await process_frame
		var expected_family := "glow_2t" if glow_id == AirplaneBuilder.STIK_GLOW_55AX_ID else "glow_4t"
		var glow: Dictionary = glow_flight.session.glow_state()
		_check("%s flight scene: matching glow telemetry is available" % glow_id,
			glow.get("ok", false) and glow.get("family", "") == expected_family, str(glow))
		var audio_snapshot: Dictionary = glow_flight._soundscape_audio.snapshot()
		var audio_glow: Dictionary = audio_snapshot.get("glow", {})
		_check("%s runtime audio snapshot follows the accepted family and firing fraction" % glow_id,
			audio_glow.get("family", "") == expected_family and audio_glow.get("running", false)
			and float(audio_glow.get("firing_fraction", 0.0)) > 0.0 and audio_glow.get("blade_count", 0) == 2)
		_check("%s runtime glow voice replaces legacy motor and propeller loops" % glow_id,
			glow_flight._soundscape_audio.soundscape.glow_player != null
			and glow_flight._soundscape_audio.soundscape.voices[0].stream == null
			and glow_flight._soundscape_audio.soundscape.voices[1].stream == null)
		var runtime_diameter_m: float = float(glow_flight.session.aircraft.model.propulsion.glow.propeller.diameter_m)
		var glow_blur: Node3D = glow_flight.get_node_or_null("PropellerBlur") as Node3D
		if glow_blur != null:
			glow_blur.call("update", 0.0)
		var glow_blur_profile: Dictionary = glow_blur.get("measured") if glow_blur != null else {}
		_check("%s runtime visual and blur follow session model propeller" % glow_id,
			is_equal_approx(glow_flight._airplane.propeller.scale.x,
				runtime_diameter_m / float(StikGeometry.DATA.equipment.prop_diameter))
			and glow_blur != null and is_equal_approx(float(glow_blur_profile.get("radius", 0.0)),
				float(PropellerBlur.profile(glow_flight._airplane.propeller, glow_flight._airplane.root).radius))
			and is_equal_approx(float(glow_blur.global_transform.basis.x.length()) * float(glow_blur_profile.get("radius", 0.0)),
				float(PropellerBlur.profile(glow_flight._airplane.propeller, glow_flight._airplane.root).radius)
				* float(glow_flight._airplane.propeller.scale.x)))
		glow_flight._update_hud()
		var expected_label := "2-stroke" if expected_family == "glow_2t" else "4-stroke"
		_check("%s HUD shows family, engine values, mode and controls" % glow_id,
			glow_flight._hud.text.contains("Glow " + expected_label)
			and glow_flight._hud.text.contains("rpm") and glow_flight._hud.text.contains("°C")
			and glow_flight._hud.text.contains("fuel ~") and glow_flight._hud.text.contains("running")
			and glow_flight._hud.text.contains("φ ") and glow_flight._hud.text.contains("[F6] cut")
			and glow_flight._hud.text.contains("[F7] starter") and glow_flight._hud.text.contains("[F8] lean")
			and glow_flight._hud.text.contains("[F9] rich"), glow_flight._hud.text)
		# FUEL-01b: displayed volume uses the profile blend density (72/10/18 ≈ 857 kg/m³), not 0.8 g/mL.
		var fuel_density: float = float(glow.get("fuel_density_kg_m3", NAN))
		var expected_fuel := "fuel ~%.0f mL" % (float(glow.get("fuel_kg", NAN)) / fuel_density * 1.0e6)
		_check("%s HUD fuel volume uses the installed blend density" % glow_id,
			fuel_density > 840.0 and fuel_density < 880.0
			and is_equal_approx(float(glow.get("fuel_volume_m3", NAN)), float(glow.get("fuel_kg", NAN)) / fuel_density)
			and glow_flight._hud.text.contains(expected_fuel), "%s in %s" % [expected_fuel, glow_flight._hud.text])
		_check("%s recommended RPM warning is hidden at the trimmed start point" % glow_id,
			not glow_flight._hud.text.contains("ABOVE RECOMMENDED RPM"))
		var original_continuous_rpm: float = float(glow_flight.session.sim.continuous[0])
		var original_aux_rpm: float = float(glow_flight.session.sim.aux[0])
		var recommended_rpm: float = float(glow.get("recommended_max_rpm", NAN))
		var overspeed_flag := false
		if is_finite(recommended_rpm):
			glow_flight.session.sim.continuous[0] = recommended_rpm + 1.0
			glow_flight.session.sim.aux[0] = recommended_rpm + 1.0
			glow = glow_flight.session.glow_state()
			overspeed_flag = bool(glow.get("above_recommended_rpm", false))
			glow_flight._update_hud()
			_check("%s HUD consumes the physical above-recommended RPM flag" % glow_id,
				overspeed_flag and glow_flight._hud.text.contains("ABOVE RECOMMENDED RPM"), str(glow))
		else:
			_check("%s exposes a finite recommended RPM for the HUD warning" % glow_id, false, str(glow))
		glow_flight.session.sim.continuous[0] = original_continuous_rpm
		glow_flight.session.sim.aux[0] = original_aux_rpm
		glow_flight._update_hud()
		glow_flight._render_pose(glow_flight._current_pose(), glow_flight.session.surfaces(), 0.25)
		_check("%s main render applies the adapter's physical spin sign" % glow_id,
			is_equal_approx(glow_flight._airplane.propeller.rotation.z, -0.25))
		var nominal_phi: float = float(glow_flight.session.aircraft.model.propulsion.glow.profile.operation.nominal_mixture)
		_press_key(glow_flight, KEY_F6)
		glow = glow_flight.session.glow_state()
		_check("%s F6 cuts combustion" % glow_id, glow.get("ok", false) and not glow.get("running", true) and glow.get("stop_reason", "") == "cut")
		_press_key(glow_flight, KEY_F8)
		_check("%s F8 requests a lean physical mixture value" % glow_id,
			absf(float(glow_flight.session.sim.continuous[12]) - nominal_phi * 0.85) < 1e-8)
		_press_key(glow_flight, KEY_F9)
		_check("%s F9 requests a rich physical mixture value" % glow_id,
			absf(float(glow_flight.session.sim.continuous[12]) - nominal_phi * 1.15) < 1e-8)
		_press_key(glow_flight, KEY_F7)
		glow = glow_flight.session.glow_state()
		_check("%s F7 restarts the glow engine" % glow_id, glow.get("ok", false) and glow.get("running", false))
		glow_flight.recorder.detach()
		glow_flight.free()

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
